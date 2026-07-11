// Native Stockfish via the Tauri shell's Rust UCI bridge — same protocol as
// the WASM worker, but full-strength NNUE on real cores. The Rust side spawns
// sidecars keyed by id and streams stdout as "engine-line" events; commands go
// through engine_send. The live engine is id "main"; the archive importer
// runs its own pool of ids so it never steals this one.

import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import { createLineSplitter } from './lineSplitter';
import type { TransportFactory } from './stockfish';

interface EngineLine {
	id: string;
	line: string;
}

// A raw line-oriented UCI pipe over the bridge, usable for any engine id.
export interface NativeUci {
	send(command: string): Promise<void>;
	dispose(): void;
}

export async function openNativeUci(
	id: string,
	onLine: (line: string) => void,
	onError: (message: string) => void
): Promise<NativeUci> {
	let closed = false;
	const unlisteners: UnlistenFn[] = [];
	const flush = createLineSplitter(onLine);

	unlisteners.push(
		await listen<EngineLine>('engine-line', (e) => {
			if (e.payload.id === id) flush(e.payload.line + '\n');
		})
	);
	unlisteners.push(
		await listen<EngineLine>('engine-error', (e) => {
			if (e.payload.id === id && !closed) onError(e.payload.line);
		})
	);
	unlisteners.push(
		await listen<EngineLine>('engine-exit', (e) => {
			if (e.payload.id === id && !closed) onError('engine process exited');
		})
	);
	await invoke('engine_start', { id });

	return {
		send: (command: string) => invoke('engine_send', { id, command }),
		dispose: () => {
			closed = true;
			for (const un of unlisteners) un();
			void invoke('engine_stop', { id }).catch(() => {});
		}
	};
}

export const nativeTransport: TransportFactory = (onLine, onError) => {
	let pipe: NativeUci | null = null;
	let queue: string[] = [];

	void (async () => {
		try {
			const p = await openNativeUci('main', onLine, onError);
			pipe = p;
			for (const q of queue) await p.send(q);
			queue = [];
			// native perk: real threads and a real hash table
			const threads = Math.max(1, (navigator.hardwareConcurrency ?? 4) - 2);
			await p.send(`setoption name Threads value ${threads}`);
			await p.send('setoption name Hash value 256');
		} catch (e) {
			onError(String(e));
		}
	})();

	// the Rust side kills any previous engine with the same id on start, so
	// reloads don't leak processes; still, be tidy on page unload
	const stop = () => pipe?.dispose();
	window.addEventListener('beforeunload', stop);

	return {
		send: (command: string) => {
			if (pipe) void pipe.send(command).catch((e) => onError(String(e)));
			else queue.push(command);
		},
		terminate: () => {
			window.removeEventListener('beforeunload', stop);
			pipe?.dispose();
			pipe = null;
		}
	};
};
