// Native Stockfish over a Tauri sidecar process — same UCI protocol as the
// WASM worker, but full-strength NNUE on real cores. Selected at startup by
// the layout when the app runs inside Tauri.

import { Command, type Child } from '@tauri-apps/plugin-shell';
import type { TransportFactory } from './stockfish';

export const nativeTransport: TransportFactory = (onLine, onError) => {
	let child: Child | null = null;
	let closed = false;
	let queue: string[] = [];

	const cmd = Command.sidecar('binaries/stockfish');
	cmd.stdout.on('data', (line: string) => onLine(line));
	cmd.on('error', (e) => onError(String(e)));
	cmd.on('close', () => {
		if (!closed) onError('engine process exited');
	});

	cmd
		.spawn()
		.then(async (c) => {
			child = c;
			for (const q of queue) await c.write(q + '\n');
			queue = [];
			// native perk: real threads and a real hash table
			const threads = Math.max(1, (navigator.hardwareConcurrency ?? 4) - 2);
			await c.write(`setoption name Threads value ${threads}\n`);
			await c.write('setoption name Hash value 256\n');
		})
		.catch((e) => onError(String(e)));

	return {
		send: (command: string) => {
			if (child) void child.write(command + '\n');
			else queue.push(command);
		},
		terminate: () => {
			closed = true;
			if (child) {
				void child.write('quit\n').then(() => child?.kill());
			}
			child = null;
		}
	};
};
