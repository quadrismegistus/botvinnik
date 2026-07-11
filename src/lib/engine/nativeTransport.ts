// Native Stockfish via the Tauri shell's Rust UCI bridge — same protocol as
// the WASM worker, but full-strength NNUE on real cores. The Rust side spawns
// the sidecar and streams stdout as "engine-line" events; we send commands
// through the engine_send command.

import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import type { TransportFactory } from './stockfish';

export const nativeTransport: TransportFactory = (onLine, onError) => {
	let up = false;
	let closed = false;
	let queue: string[] = [];
	let buffer = '';
	const unlisteners: UnlistenFn[] = [];

	const flush = (chunk: string) => {
		buffer += chunk;
		// the bridge usually delivers whole lines, but never assume it
		const lines = buffer.split('\n');
		buffer = lines.pop() ?? '';
		for (const line of lines) {
			const trimmed = line.replace(/\r$/, '');
			if (trimmed) onLine(trimmed);
		}
	};

	void (async () => {
		try {
			unlisteners.push(
				await listen<string>('engine-line', (e) => {
					flush(e.payload + '\n');
				})
			);
			unlisteners.push(
				await listen<string>('engine-error', (e) => {
					if (!closed) onError(e.payload);
				})
			);
			unlisteners.push(
				await listen('engine-exit', () => {
					if (!closed) onError('engine process exited');
				})
			);
			await invoke('engine_start');
			up = true;
			for (const q of queue) await invoke('engine_send', { command: q });
			queue = [];
			// native perk: real threads and a real hash table
			const threads = Math.max(1, (navigator.hardwareConcurrency ?? 4) - 2);
			await invoke('engine_send', { command: `setoption name Threads value ${threads}` });
			await invoke('engine_send', { command: 'setoption name Hash value 256' });
		} catch (e) {
			onError(String(e));
		}
	})();

	// the Rust side kills any previous engine on engine_start, so reloads
	// don't leak processes; still, be tidy on page unload
	const stop = () => void invoke('engine_stop').catch(() => {});
	window.addEventListener('beforeunload', stop);

	return {
		send: (command: string) => {
			if (up) void invoke('engine_send', { command }).catch((e) => onError(String(e)));
			else queue.push(command);
		},
		terminate: () => {
			closed = true;
			window.removeEventListener('beforeunload', stop);
			for (const un of unlisteners) un();
			stop();
			up = false;
		}
	};
};
