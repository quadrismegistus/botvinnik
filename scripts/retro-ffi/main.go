//go:build darwin

// retro-ffi: one static archive hosting morlock's re-implementations of
// TUROCHAMP (1948), BERNSTEIN (1957) and SARGON (1978), for the platforms that
// cannot spawn a child process — which on Apple means iOS.
//
// It is the sibling of scripts/retro-wasm/main.go and deliberately so: the
// engines are built by the SAME `build()` switch, so the three transports (a
// spawned binary on macOS, wasm in a Worker on the web, this archive on iOS)
// are the same engines at the same ply, and the calibration means the same
// thing on all three. If you change one build(), change the other.
//
// BUILD (go.mod pins morlock via a replace to a gitignored checkout):
//   git clone https://github.com/herohde/morlock ../engines/morlock-src
//   git -C ../engines/morlock-src checkout 8c55f1e97f6259fcff48a567409b382961045463
//   ../../flutter/stage-ios-engines.sh     # both slices, then the xcframework
//
// C contract (retro_engine_ffi.dart is the only caller):
//   retro_start(name, ply, cb) -> handle   // 0 on failure
//   retro_send(handle, line)               // UCI in; first line MUST be "uci"
//   retro_stop(handle)                     // ends the driver; see session.driver
// `cb` is invoked with one UCI line at a time, from a goroutine — so on the
// Dart side it has to be a NativeCallable.listener, not an isolateLocal.
//
// One archive covers all three engines, selected by name at retro_start, which
// is why this costs ~3.5MB once rather than three times.
package main

/*
#include <stdlib.h>
typedef void (*retro_line_cb)(int handle, const char* line);
static void retro_emit(retro_line_cb cb, int handle, const char* line) {
	cb(handle, line);
}
*/
import "C"

import (
	"context"
	"flag"
	"strings"
	"sync"
	"time"
	"unsafe"

	"github.com/herohde/morlock/cmd/bernstein/bernstein"
	"github.com/herohde/morlock/cmd/sargon/sargon"
	"github.com/herohde/morlock/cmd/turochamp/turochamp"
	"github.com/herohde/morlock/pkg/engine"
	"github.com/herohde/morlock/pkg/engine/uci"
	"github.com/herohde/morlock/pkg/search"
)

// Identical to scripts/retro-wasm/main.go's build(), on purpose — see above.
func build(ctx context.Context, name string, ply uint) (*engine.Engine, []uci.Option) {
	switch name {
	case "bernstein":
		s := search.AlphaBeta{
			Explore: bernstein.PlausibleMoveTable{Limit: 7}.Explore,
			Eval:    search.Leaf{Eval: bernstein.Eval{Factor: 20}},
		}
		e := engine.New(ctx, "BERNSTEIN (1957)", "Alex Bernstein et al.", s,
			engine.WithOptions(engine.Options{Depth: ply}))
		return e, []uci.Option{uci.UseBook(bernstein.NewBook(), time.Now().UnixNano())}
	case "sargon":
		points := &sargon.Points{}
		s := sargon.Hook{
			Eval: search.AlphaBeta{
				Explore: sargon.SkipUnderPromotions,
				Eval:    sargon.OnePlyIfChecked{Leaf: search.Leaf{Eval: points}},
			},
			Hook: points,
		}
		e := engine.New(ctx, "SARGON (1978)", "Dan and Kathe Spracklen", s,
			engine.WithOptions(engine.Options{Depth: ply, Noise: 10}))
		return e, []uci.Option{uci.UseBook(sargon.NewBook(), time.Now().UnixNano())}
	default: // turochamp
		s := search.AlphaBeta{
			Eval: search.Quiescence{
				Explore: turochamp.ConsiderableMovesOnly,
				Eval:    search.Leaf{Eval: turochamp.Eval{}},
			},
		}
		e := engine.New(ctx, "TUROCHAMP (1948)", "Alan Turing and David Champernowne", s,
			engine.WithOptions(engine.Options{Depth: ply, Noise: 10}))
		return e, nil
	}
}

// A running engine. Handles rather than pointers cross the boundary: a Go
// pointer may not be held by C (the cgo pointer rules), and a small integer is
// also what lets a late line from a disposed engine be dropped rather than
// delivered to whoever inherited its memory.
type session struct {
	in     chan string
	cancel context.CancelFunc

	// Set once the UCI handshake has produced one.
	driver *uci.Driver

	// Whether a search has been started and its bestmove not yet seen, and
	// whether somebody is waiting to close as soon as it has been.
	//
	// This pair is the whole reason retro_stop is not a one-liner. Ending a
	// session tears down uci.Driver.process, whose `defer close(d.out)` fires
	// while the goroutine that reports a finished search may still be about to
	// send on that channel — a send on a closed channel, which is a Go panic.
	// Closing the DRIVER rather than the input channel narrows the window,
	// because that path clears the active-search flag first, but it does not
	// close it: the flag is read and the send made in the other goroutine, so
	// the two can still interleave.
	//
	// The only way to be sure is not to close while a search can still finish.
	// So a stop during a search asks the engine to stop, waits for the
	// bestmove that always follows, and closes then — with a backstop for an
	// engine that never answers.
	//
	// The other two transports have the same hazard and it is invisible there:
	// a panic kills a child process or a Worker, and both already model
	// "engine gone" as a null move. In a c-archive it is SIGABRT in the app's
	// own process, with no recovery point in //export'ed Go.
	searching bool
	wantClose bool

	closed bool
}

var (
	mu       sync.Mutex
	sessions = map[int]*session{}
	nextID   = 1
)

//export retro_start
func retro_start(name *C.char, ply C.int, cb C.retro_line_cb) C.int {
	// glog opens log FILES under TMPDIR, which is sandboxed and pointless on a
	// phone. Same redirect the wasm build needs, for the same reason: without
	// it the first log call is fatal.
	_ = flag.Set("logtostderr", "true")

	// Reject an unknown engine rather than quietly playing TUROCHAMP, which is
	// what build()'s default clause would do. macOS answers null for a name it
	// has no binary for, and a persona that silently becomes a different engine
	// is the substitution the roster gate exists to prevent.
	which := C.GoString(name)
	switch which {
	case "turochamp", "bernstein", "sargon":
	default:
		return 0
	}

	ctx, cancel := context.WithCancel(context.Background())
	e, opts := build(ctx, which, uint(ply))

	in := make(chan string, 64)
	s := &session{in: in, cancel: cancel}

	mu.Lock()
	id := nextID
	nextID++
	sessions[id] = s
	mu.Unlock()

	go func() {
		defer cancel()
		// Same contract as the stdin binaries and the wasm build: the first
		// line selects the protocol, and only UCI is offered here.
		first, ok := <-in
		if !ok {
			return
		}
		if first != uci.ProtocolName {
			emit(cb, id, "info string expected 'uci', got: "+first)
			return
		}
		driver, out := uci.NewDriver(ctx, e, in, opts...)
		mu.Lock()
		if s.closed {
			// stopped during the handshake; nobody will close this driver later
			mu.Unlock()
			driver.Close()
			return
		}
		s.driver = driver
		mu.Unlock()
		go func() {
			for line := range out {
				// Bookkeeping BEFORE delivery, and under the lock: a bestmove
				// means the engine is idle, which is the only moment a pending
				// close is safe to perform.
				mu.Lock()
				if strings.HasPrefix(line, "bestmove") {
					s.searching = false
					if s.wantClose {
						s.wantClose = false
						driver.Close()
					}
				}
				mu.Unlock()
				emit(cb, id, line)
			}
		}()
		<-driver.Closed()
	}()

	return C.int(id)
}

//export retro_send
func retro_send(handle C.int, line *C.char) {
	// The send happens UNDER the lock, which is the only thing that makes a
	// concurrent retro_stop safe: a send on a closed channel panics, and a
	// panic in a c-archive takes the host app with it. Cheap, because the send
	// below never blocks.
	mu.Lock()
	defer mu.Unlock()
	s := sessions[int(handle)]
	if s == nil || s.closed {
		return
	}
	// Never block the caller: a wedged engine must not take the UI thread down
	// with it. The buffer is 64 lines; a UCI session that far behind is
	// already broken.
	text := C.GoString(line)
	// "quit" is refused, and this is the one filter that matters.
	//
	// morlock handles it with a bare `return` out of Driver.process, whose
	// `defer close(d.out)` then fires WITHOUT clearing the active-search flag —
	// so a search still finishing sends its bestmove on a closed channel and
	// panics. That is invisible in the other two transports (it kills a child
	// process or a Worker, both of which already mean "engine gone") and is
	// SIGABRT in the host app here. Verified: it is the crash, and it was
	// reachable from the ordinary dispose path.
	//
	// Nothing is lost by refusing it. retro_stop owns teardown on this
	// transport, and does it in the one order that cannot race.
	if strings.TrimSpace(text) == "quit" {
		return
	}
	if strings.HasPrefix(text, "go") {
		s.searching = true
	}
	select {
	case s.in <- text:
	default:
	}
}

//export retro_stop
func retro_stop(handle C.int) {
	mu.Lock()
	defer mu.Unlock()
	s := sessions[int(handle)]
	if s == nil || s.closed {
		return
	}
	delete(sessions, int(handle))
	s.closed = true
	s.cancel()

	if s.driver == nil {
		// No driver yet, so process() is not running and there is nothing to
		// race: closing the input is what releases the goroutine waiting on
		// the first line.
		close(s.in)
		return
	}
	if !s.searching {
		s.driver.Close()
		return
	}
	// Mid-search. Ask the engine to stop and let the out reader close once the
	// bestmove has been and gone — see session.searching.
	s.wantClose = true
	select {
	case s.in <- "stop":
	default:
	}
	// An engine that never answers must not pin its driver for the life of the
	// app. Generous, because the cost of being early is a crash and the cost
	// of being late is one idle goroutine.
	driver := s.driver
	time.AfterFunc(15*time.Second, func() {
		mu.Lock()
		defer mu.Unlock()
		if s.wantClose {
			s.wantClose = false
			driver.Close()
		}
	})
}

// emit hands the callee a malloc'd copy and does NOT free it.
//
// This is the one place the Dart end's shape reaches back into Go. A
// NativeCallable.listener does not run when it is invoked — it posts to the
// isolate's event loop and returns immediately — so a string freed on return
// here would be read after free, intermittently, on a background thread. The
// line therefore belongs to the callee, which must hand it back to
// retro_free_line.
//
// It also runs under the same lock retro_stop takes, and that is what lets the
// Dart end close its NativeCallable at all: engine output comes from
// goroutines, so without this, `retro_stop` could return while a goroutine was
// mid-callback and the trampoline could be freed underneath it. Holding the
// lock means retro_stop cannot return until any in-flight emit has finished,
// and no later one can start. The callback itself only posts a message, so the
// lock is held for microseconds.
func emit(cb C.retro_line_cb, id int, line string) {
	mu.Lock()
	defer mu.Unlock()
	if s := sessions[id]; s == nil || s.closed {
		return
	}
	C.retro_emit(cb, C.int(id), C.CString(line))
}

//export retro_free_line
func retro_free_line(line *C.char) {
	C.free(unsafe.Pointer(line))
}

func main() {}
