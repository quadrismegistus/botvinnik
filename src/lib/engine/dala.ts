// Dala: human-imitation lc0 networks trained per lichess rating bracket
// (hrschubert/dala-training), with REAL human-pool lichess ratings — the
// best-anchored bots on the roster. Desktop (Tauri) only: the nets run on a
// native lc0 sidecar; weights are fetched on first use from the author's
// GitHub release into app-data (we never redistribute them).
//
// Move selection is WEIGHTED RANDOM over the policy priors (lc0
// VerboseMoveStats at 1 node) — the same selection rule as the dala lichess
// bots and our calibration gym. Argmax would inflate an imitation net far
// above its bracket.

import { invoke } from '@tauri-apps/api/core';
import { openNativeUci, type NativeUci } from './nativeTransport';

export function dalaAvailable(): boolean {
	return typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
}

interface Session {
	band: number;
	pipe: NativeUci;
	ready: Promise<void>;
	onLine: ((line: string) => void) | null;
}

let session: Session | null = null;

async function boot(band: number): Promise<Session> {
	if (session?.band === band) return session;
	session?.pipe.dispose();
	session = null;

	// may download 59-330MB on first use — the caller's thinking state covers it
	const weights = await invoke<string>('dala_ensure_weights', { band });

	const s: Session = { band, pipe: null as unknown as NativeUci, ready: Promise.resolve(), onLine: null };
	let resolveReady!: () => void;
	let rejectReady!: (e: Error) => void;
	s.ready = new Promise<void>((res, rej) => {
		resolveReady = res;
		rejectReady = rej;
	});
	s.ready.catch(() => {}); // avoid unhandled rejection from fire-and-forget preloads

	const timer = setTimeout(() => rejectReady(new Error('dala boot timeout')), 30_000);
	s.pipe = await openNativeUci(
		'dala',
		(line) => {
			if (line === 'uciok') {
				clearTimeout(timer);
				resolveReady();
			}
			s.onLine?.(line);
		},
		() => rejectReady(new Error('dala engine error')),
		{ engine: 'lc0', args: [`--weights=${weights}`] }
	);
	await s.pipe.send('uci');
	await s.pipe.send('setoption name VerboseMoveStats value true');
	session = s;
	return s;
}

/** Warm the sidecar (and trigger the weights download) ahead of the first move. */
export function preloadDala(band: number): void {
	void boot(band).catch(() => {});
}

/** Sample dala's move for this position, or null on any failure (caller falls back). */
export async function dalaMove(fen: string, band: number): Promise<string | null> {
	const s = await boot(band);
	await s.ready;
	return new Promise<string | null>((resolve) => {
		const policy = new Map<string, number>();
		const finish = (move: string | null) => {
			clearTimeout(timer);
			s.onLine = null;
			resolve(move);
		};
		const timer = setTimeout(() => finish(null), 20_000);
		s.onLine = (line) => {
			// "info string e2e4 (322 ) N: 0 (+ 0) (P:  4.05%) ..."
			const m = line.match(/^info string ([a-h][1-8][a-h][1-8][qrbn]?)\s.*\(P:\s*([\d.]+)%\)/);
			if (m) {
				policy.set(m[1], Number(m[2]));
				return;
			}
			if (!line.startsWith('bestmove')) return;
			if (policy.size === 0) {
				const uci = line.split(/\s+/)[1];
				finish(uci && uci !== '(none)' ? uci : null);
				return;
			}
			const entries = [...policy.entries()];
			const total = entries.reduce((a, [, p]) => a + p, 0);
			let r = Math.random() * total;
			for (const [move, p] of entries) {
				r -= p;
				if (r <= 0) return finish(move);
			}
			finish(entries[entries.length - 1][0]);
		};
		void s.pipe.send(`position fen ${fen}`);
		void s.pipe.send('go nodes 1');
	});
}
