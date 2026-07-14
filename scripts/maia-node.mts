// Maia as a bot for the calibration harness: same nets and encoding as the app
// (src/lib/engine/maia/*), but run in Node with a filesystem model cache. Lets
// us play our Stockfish bands against Maia's lichess-anchored bands and read our
// scale in human terms. Bot ids look like "maia:1500".

import * as ort from 'onnxruntime-web';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { Chess } from 'chess.js';
import { encodeFenHistory } from '../src/lib/engine/maia/encoding';
import { decodePolicyOutput } from '../src/lib/engine/maia/decoding';

ort.env.wasm.numThreads = 1; // ort-web finds its wasm in node_modules under Node

const MODEL_DIR = 'data/maia-models'; // gitignored, like the other calibration data
const modelUrl = (band: number) =>
	`https://huggingface.co/shermansiu/maia-${band}/resolve/main/model.onnx`;

export function isMaiaId(id: string): boolean {
	return id.startsWith('maia:');
}
export function maiaBandOf(id: string): number {
	return Number(id.split(':')[1]);
}

interface Loaded {
	session: ort.InferenceSession;
	inputName: string;
	policyName: string;
}
const loads = new Map<number, Promise<Loaded>>();

async function loadBand(band: number): Promise<Loaded> {
	let p = loads.get(band);
	if (!p) {
		p = (async () => {
			const path = `${MODEL_DIR}/maia-${band}.onnx`;
			if (!existsSync(path)) {
				const res = await fetch(modelUrl(band));
				if (!res.ok) throw new Error(`maia-${band} download failed: ${res.status}`);
				mkdirSync(MODEL_DIR, { recursive: true });
				writeFileSync(path, Buffer.from(await res.arrayBuffer()));
			}
			const session = await ort.InferenceSession.create(new Uint8Array(readFileSync(path)), {
				executionProviders: ['wasm']
			});
			const inputName = session.inputNames[0];
			const policyName =
				session.outputNames.find((n) => n.toLowerCase().includes('policy')) ?? session.outputNames[0];
			return { session, inputName, policyName };
		})();
		loads.set(band, p);
	}
	return p;
}

// download all requested bands up front so a run fails fast if HF is unreachable
export async function preloadMaiaBands(bands: number[]): Promise<void> {
	await Promise.all(bands.map((b) => loadBand(b)));
}

/** The move Maia plays. `fenHistory` is oldest-first (last = current position). */
export async function maiaMoveNode(
	fenHistory: string[],
	band: number,
	temperature = 0
): Promise<string | null> {
	const fen = fenHistory[fenHistory.length - 1];
	if (!fen) return null;
	const legal = new Chess(fen)
		.moves({ verbose: true })
		.map((m) => m.from + m.to + (m.promotion ?? ''));
	if (legal.length === 0) return null;
	const { session, inputName, policyName } = await loadBand(band);
	const planes = encodeFenHistory(fenHistory);
	const out = await session.run({
		[inputName]: new ort.Tensor('float32', planes, [1, 112, 8, 8])
	});
	const policy = new Float32Array(out[policyName].data as ArrayLike<number>);
	return decodePolicyOutput(policy, legal, fen.split(' ')[1] === 'b', temperature).best.move;
}
