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
		let res;
		try {
			res = await WebAssembly.instantiateStreaming(
				fetch('retro.wasm'),
				go.importObject
			);
		} catch (err) {
			// A rejection here is an UNHANDLED one — it happens inside an async
			// message handler, so it never reaches the parent's worker.onerror
			// and the client just waits. Said out loud, the client can tell a
			// boot that failed (give up now) from one that is merely slow (a
			// 4.4MB wasm on a phone; keep waiting). Silent, they were the same
			// 30-second stall, and the client resolved both by dying.
			self.postMessage(`__boot_failed__ ${err}`);
			return;
		}
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
		// NOT "runs forever", which is what the comment here used to claim and
		// what the client was built on. `go.run` resolves when Go's main()
		// returns, and main returns when morlock's UCI driver closes — which it
		// does on `quit`, and on any command it fails to parse. Sending the same
		// `position` line twice is one of those (see the ucinewgame note in
		// retro_engine_web.dart), and it used to end the engine silently: every
		// later message threw from inside this async handler, i.e. as an
		// unhandled rejection that never reached the client, which then waited
		// out its whole move timeout and played a Stockfish stand-in.
		//
		// So say so the moment it happens, and let the client rebuild rather than
		// discover the corpse by posting into it.
		go.run(res.instance).then(
			() => self.postMessage('__exited__'),
			(err) => self.postMessage(`__exited__ ${err}`)
		);
		for (const line of pending.splice(0)) self.retroSend(line);
		self.postMessage('__ready__');
		return;
	}
	if (typeof e.data === 'string') {
		if (typeof self.retroSend === 'function') {
			// Belt and braces for the race the notification above cannot close:
			// a command already in flight when the program exits. Uncaught,
			// this rejects the handler's promise and the client hears nothing.
			try {
				self.retroSend(e.data);
			} catch (err) {
				self.postMessage(`__exited__ ${err}`);
			}
		} else pending.push(e.data);
	}
};
