//go:build js && wasm

// retro-wasm: one WebAssembly binary hosting morlock's re-implementations of
// TUROCHAMP (1948), BERNSTEIN (1957) and SARGON (1978) for botvinnik-web.
//
// JS contract (set BEFORE running the Go instance):
//   globalThis.retroConfig = { engine: "bernstein"|"sargon"|"turochamp", ply: 2 }
//   globalThis.onRetroLine = (line) => { ... }   // engine → UI
// After the instance starts it exposes:
//   globalThis.retroSend(line)                   // UI → engine (UCI lines)
// The first line sent MUST be "uci" (same contract as the stdin binaries).
package main

import (
	"context"
	"flag"
	"syscall/js"
	"time"

	"github.com/herohde/morlock/cmd/bernstein/bernstein"
	"github.com/herohde/morlock/cmd/sargon/sargon"
	"github.com/herohde/morlock/cmd/turochamp/turochamp"
	"github.com/herohde/morlock/pkg/engine"
	"github.com/herohde/morlock/pkg/engine/uci"
	"github.com/herohde/morlock/pkg/search"
)

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

func main() {
	// glog tries to open log FILES in /tmp, which js/wasm cannot do — fatal
	// on first log call unless redirected to stderr (which wasm_exec pipes to
	// the console).
	_ = flag.Set("logtostderr", "true")

	ctx := context.Background()
	cfg := js.Global().Get("retroConfig")
	name := cfg.Get("engine").String()
	ply := uint(cfg.Get("ply").Int())

	in := make(chan string, 64)
	js.Global().Set("retroSend", js.FuncOf(func(_ js.Value, args []js.Value) any {
		in <- args[0].String()
		return nil
	}))

	e, opts := build(ctx, name, ply)

	// same contract as the stdin binaries: the first line selects the protocol
	if first := <-in; first != uci.ProtocolName {
		js.Global().Get("onRetroLine").Invoke("info string expected 'uci', got: " + first)
		return
	}
	driver, out := uci.NewDriver(ctx, e, in, opts...)
	onLine := js.Global().Get("onRetroLine")
	go func() {
		for line := range out {
			onLine.Invoke(line)
		}
	}()
	<-driver.Closed()
}
