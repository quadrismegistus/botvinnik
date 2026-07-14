// Maia move provider: a human-imitation net (McIlroy-Young et al.) that returns
// the move a human of a target rating band would most likely play — used for the
// "human-like" bot bands where Stockfish's weakening feels random/inhuman. It is
// NOT a UCI engine (no search, no eval), so it lives outside the engine
// TransportFactory: given a position (+ history) it does one ONNX policy
// forward-pass and returns a UCI move. See docs/bot-weakening.md.
//
// Weights are the pre-converted lc0/Maia-1 nets (one per band, ~3.5 MB), fetched
// from HuggingFace at runtime (GPL-3.0 — not bundled) and cached in IndexedDB.
// Runs on onnxruntime-web/wasm with numThreads=1, so no SharedArrayBuffer / no
// cross-origin-isolation headers (matches our lite-single setup).

import * as ort from 'onnxruntime-web';
import { Chess } from 'chess.js';
import { encodeFenHistory } from './maia/encoding';
import { decodePolicyOutput } from './maia/decoding';
import { getCachedModel, putCachedModel } from './maia/modelCache';

const BANDS = [1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900];
// the range of requested ELO for which we use Maia rather than Stockfish. Maia-1
// is mis-calibrated at the very bottom (Maia-1100 plays ~1500), so it covers the
// club range; the sub-1100 floor and the strong bands stay on Stockfish.
export const MAIA_MIN = 1100;
export const MAIA_MAX = 1900;

export function inMaiaRange(elo: number): boolean {
	return elo >= MAIA_MIN && elo <= MAIA_MAX;
}

export function maiaBand(elo: number): number {
	const e = Math.max(MAIA_MIN, Math.min(MAIA_MAX, elo));
	return BANDS.reduce((best, b) => (Math.abs(b - e) < Math.abs(best - e) ? b : best), BANDS[0]);
}

// community pre-conversions of the CSSLab lc0 weights, one repo per band
const modelUrl = (band: number) =>
	`https://huggingface.co/shermansiu/maia-${band}/resolve/main/model.onnx`;
// match the pinned onnxruntime-web version exactly
const WASM_PATHS = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.27.0/dist/';

let ortConfigured = false;
function configureOrt(): void {
	if (ortConfigured) return;
	ort.env.wasm.numThreads = 1; // single policy eval → no SharedArrayBuffer needed
	ort.env.wasm.wasmPaths = WASM_PATHS;
	ortConfigured = true;
}

interface Loaded {
	session: ort.InferenceSession;
	inputName: string;
	policyName: string;
}

const loads = new Map<number, Promise<Loaded>>();

async function load(band: number): Promise<Loaded> {
	let p = loads.get(band);
	if (!p) {
		p = (async () => {
			configureOrt();
			const key = `maia-${band}`;
			let bytes = await getCachedModel(key);
			if (!bytes) {
				const res = await fetch(modelUrl(band));
				if (!res.ok) throw new Error(`maia-${band} fetch failed: ${res.status}`);
				bytes = await res.arrayBuffer();
				await putCachedModel(key, bytes);
			}
			const session = await ort.InferenceSession.create(new Uint8Array(bytes), {
				executionProviders: ['wasm']
			});
			const inputName = session.inputNames[0];
			const policyName =
				session.outputNames.find((n) => n.toLowerCase().includes('policy')) ?? session.outputNames[0];
			return { session, inputName, policyName };
		})();
		loads.set(band, p);
		p.catch(() => loads.delete(band)); // allow retry after a failed load
	}
	return p;
}

/** Warm the net for a requested ELO ahead of the first move (fire-and-forget). */
export function preloadMaia(elo: number): void {
	if (inMaiaRange(elo)) void load(maiaBand(elo)).catch(() => {});
}

/**
 * The move Maia plays from the given position. `fenHistory` is the game's FENs
 * oldest-first (most recent = current position); pass at least the current FEN.
 * Real history sharpens Maia's move distribution (it was trained with it).
 * temperature 0 = the most-likely human move; >0 samples for variety.
 * Returns null if there are no legal moves.
 */
export async function maiaMove(
	fenHistory: string[],
	elo: number,
	temperature = 0
): Promise<string | null> {
	const fen = fenHistory[fenHistory.length - 1];
	if (!fen) return null;
	const legal = new Chess(fen)
		.moves({ verbose: true })
		.map((m) => m.from + m.to + (m.promotion ?? ''));
	if (legal.length === 0) return null;

	const isBlack = fen.split(' ')[1] === 'b';
	const { session, inputName, policyName } = await load(maiaBand(elo));
	const planes = encodeFenHistory(fenHistory);
	const out = await session.run({
		[inputName]: new ort.Tensor('float32', planes, [1, 112, 8, 8])
	});
	const policy = new Float32Array(out[policyName].data as ArrayLike<number>);
	return decodePolicyOutput(policy, legal, isBlack, temperature).best.move;
}
