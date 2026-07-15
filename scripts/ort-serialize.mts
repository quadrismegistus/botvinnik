// All Maia inference (Maia-1 and Maia-3) shares one onnxruntime-web wasm
// runtime, and run() is NOT reentrant. The harness runs games in parallel and a
// single Maia-3-vs-Maia-1 game touches BOTH providers, so serialize every
// inference through ONE global queue — not a per-provider one. Each run is ~ms;
// the Stockfish games dominate wall time.
let queue: Promise<unknown> = Promise.resolve();

export function serializeInference<T>(fn: () => Promise<T>): Promise<T> {
	const run = queue.then(fn, fn);
	queue = run.then(
		() => {},
		() => {}
	);
	return run;
}
