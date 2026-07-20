// Web Worker hosting the retro engines (TUROCHAMP 1948 / BERNSTEIN 1957 /
// SARGON 1978) — morlock's Go re-implementations compiled to WebAssembly.
//
// Protocol: first message {engine, ply} boots the wasm instance; every later
// string message is a UCI line; every UCI line the engine emits comes back as
// a string message. The first line sent after boot must be "uci".
/* global Go, retroSend */

importScripts('wasm_exec.js');

let booted = false;
// UCI lines arriving while the wasm is still fetching/compiling (the client
// sends "uci" right after the init message) — drained once retroSend exists.
// Without this queue the first lines were silently dropped and every retro
// persona fell back to Stockfish after a 20s boot timeout.
const pending = [];

self.onmessage = async (e) => {
	if (!booted && typeof e.data === 'object') {
		booted = true;
		self.retroConfig = { engine: e.data.engine, ply: e.data.ply };
		self.onRetroLine = (line) => self.postMessage(line);
		const go = new Go();
		const res = await WebAssembly.instantiateStreaming(
			fetch('retro.wasm'),
			go.importObject
		);
		// demote glog's stderr chatter (wasm_exec routes it through
		// fs.writeSync) — keep it reachable in the console for debugging Go
		// panics, but out of the main log
		const fsShim = globalThis.fs;
		if (fsShim) {
			const orig = fsShim.writeSync.bind(fsShim);
			const dec = new TextDecoder();
			fsShim.writeSync = (fd, buf) => {
				if (fd !== 2) return orig(fd, buf);
				console.debug('[retro]', dec.decode(buf).trimEnd());
				return buf.length;
			};
		}
		go.run(res.instance); // runs forever on its own goroutines
		for (const line of pending.splice(0)) self.retroSend(line);
		self.postMessage('__ready__');
		return;
	}
	if (typeof e.data === 'string') {
		if (typeof self.retroSend === 'function') self.retroSend(e.data);
		else pending.push(e.data);
	}
};
