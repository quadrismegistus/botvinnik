// Web Worker hosting the retro engines (TUROCHAMP 1948 / BERNSTEIN 1957 /
// SARGON 1978) — morlock's Go re-implementations compiled to WebAssembly.
//
// Protocol: first message {engine, ply} boots the wasm instance; every later
// string message is a UCI line; every UCI line the engine emits comes back as
// a string message. The first line sent after boot must be "uci".
/* global Go, retroSend */

importScripts('wasm_exec.js');

let booted = false;

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
		// mute glog's stderr spam (wasm_exec routes it through fs.writeSync)
		const fsShim = globalThis.fs;
		if (fsShim) {
			const orig = fsShim.writeSync.bind(fsShim);
			fsShim.writeSync = (fd, buf) => (fd === 2 ? buf.length : orig(fd, buf));
		}
		go.run(res.instance); // runs forever on its own goroutines
		self.postMessage('__ready__');
		return;
	}
	if (typeof e.data === 'string') {
		// retroSend is installed by the Go side at startup
		if (typeof self.retroSend === 'function') self.retroSend(e.data);
	}
};
