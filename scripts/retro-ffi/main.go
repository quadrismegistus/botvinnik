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
//   retro_stop(handle)                     // closes the input, ends the driver
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

	ctx, cancel := context.WithCancel(context.Background())
	e, opts := build(ctx, C.GoString(name), uint(ply))

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
		go func() {
			for line := range out {
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
	select {
	case s.in <- C.GoString(line):
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
	close(s.in)
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
