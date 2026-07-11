// A pool of engines dedicated to background archive analysis — separate from
// the live-analysis engine so imports never steal it. On the web this is a
// single extra WASM worker (the trickle); in the Tauri shell it's several
// native single-threaded Stockfish processes (the firehose), mirroring the
// offline script's design: fixed nodes per position, FEN-deduped per run.

import { base } from '$app/paths';

export interface UciEval {
	cp?: number; // side-to-move perspective
	mate?: number;
	pv: string[];
}

interface Pipe {
	send(cmd: string): void;
	dispose(): void;
}

class PoolEngine {
	busy = false;
	ready: Promise<void>;
	private pipe!: Pipe;
	private last: UciEval = { pv: [] };
	private resolve: ((r: UciEval) => void) | null = null;
	private markReady!: () => void;

	constructor(openPipe: (onLine: (line: string) => void) => Promise<Pipe> | Pipe) {
		this.ready = new Promise((r) => (this.markReady = r));
		void (async () => {
			this.pipe = await openPipe((line) => this.onLine(line));
			this.pipe.send('uci');
			this.pipe.send('setoption name Threads value 1');
			this.pipe.send('setoption name Hash value 32');
			this.pipe.send('isready');
		})();
	}

	private onLine(line: string) {
		if (line === 'readyok') this.markReady();
		if (line.startsWith('info ') && line.includes(' pv ') && !/ (upper|lower)bound /.test(line)) {
			const cp = line.match(/ score cp (-?\d+)/);
			const mate = line.match(/ score mate (-?\d+)/);
			const pv = line.split(' pv ')[1]?.trim().split(' ') ?? [];
			this.last = {
				cp: cp ? Number(cp[1]) : undefined,
				mate: mate ? Number(mate[1]) : undefined,
				pv
			};
		} else if (line.startsWith('bestmove')) {
			const r = this.resolve;
			this.resolve = null;
			this.busy = false;
			r?.(this.last);
		}
	}

	analyze(fen: string, nodes: number): Promise<UciEval> {
		this.busy = true;
		this.last = { pv: [] };
		return new Promise((resolve) => {
			this.resolve = resolve;
			this.pipe.send(`position fen ${fen}`);
			this.pipe.send(`go nodes ${nodes}`);
		});
	}

	dispose() {
		this.pipe?.send('quit');
		this.pipe?.dispose();
	}
}

export interface ImportPool {
	evalPosition(fen: string): Promise<UciEval>;
	stats(): { searched: number; deduped: number };
	dispose(): void;
	size: number;
}

export async function createImportPool(nodes: number): Promise<ImportPool> {
	const isTauri = '__TAURI_INTERNALS__' in window;
	let engines: PoolEngine[];

	if (isTauri) {
		const { openNativeUci } = await import('./nativeTransport');
		const n = Math.max(2, (navigator.hardwareConcurrency ?? 8) - 4);
		engines = Array.from(
			{ length: n },
			(_, i) =>
				new PoolEngine(async (onLine) => {
					const uci = await openNativeUci(`import-${i}`, onLine, () => {});
					return { send: (cmd) => void uci.send(cmd), dispose: () => uci.dispose() };
				})
		);
	} else {
		engines = [
			new PoolEngine((onLine) => {
				const w = new Worker(`${base}/wasm/stockfish.js`);
				w.onmessage = (e) => onLine(e.data);
				return { send: (cmd) => w.postMessage(cmd), dispose: () => w.terminate() };
			})
		];
	}

	await Promise.all(engines.map((e) => e.ready));

	const cache = new Map<string, Promise<UciEval>>();
	let searched = 0;
	let deduped = 0;

	return {
		size: engines.length,
		evalPosition(fen: string): Promise<UciEval> {
			const key = fen.split(' ').slice(0, 4).join(' ');
			const hit = cache.get(key);
			if (hit) {
				deduped++;
				return hit;
			}
			const p = (async () => {
				let engine: PoolEngine | undefined;
				while (!engine) {
					engine = engines.find((e) => !e.busy);
					if (!engine) await new Promise((r) => setTimeout(r, 5));
				}
				searched++;
				return engine.analyze(fen, nodes);
			})();
			cache.set(key, p);
			return p;
		},
		stats: () => ({ searched, deduped }),
		dispose() {
			for (const e of engines) e.dispose();
		}
	};
}
