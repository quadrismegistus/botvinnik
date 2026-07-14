// Maia-3 as a bot for the calibration harness. Unlike Maia-1 (nine bunched
// per-band nets), Maia-3 is a single ELO-CONDITIONED model — one net, dial the
// rating — and (per the spike) actually varies strength down to beginner level.
// Bot ids look like "maia3:900". No history (Maia-3 uses only the current
// position: 64x12 piece tokens + two scalar ELO inputs). Encoding ported from
// CSSLab/maia-platform-frontend (src/lib/engine/tensor.ts).

import * as ort from 'onnxruntime-web';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { Chess, type Move } from 'chess.js';

ort.env.wasm.numThreads = 1;

const MODEL_PATH = 'data/maia-models/maia3.onnx';
const MODEL_URL =
	'https://raw.githubusercontent.com/CSSLab/maia-platform-frontend/main/public/maia3/maia3_simplified.onnx';
const DATA = new URL('./maia3-data/', import.meta.url);
const MOVES: Record<string, number> = JSON.parse(
	readFileSync(new URL('all_moves_maia3.json', DATA), 'utf8')
);
const MOVES_REV: Record<string, string> = JSON.parse(
	readFileSync(new URL('all_moves_maia3_reversed.json', DATA), 'utf8')
);

export function isMaia3Id(id: string): boolean {
	return id.startsWith('maia3:');
}
export function maia3EloOf(id: string): number {
	return Number(id.split(':')[1]);
}

// ---- encoding (white-POV tokens; mirror the FEN when black to move) ----
const mirrorSq = (s: string) => s[0] + (9 - parseInt(s[1]));
const mirrorMove = (m: string) => mirrorSq(m.slice(0, 2)) + mirrorSq(m.slice(2, 4)) + m.slice(4);
const swapRank = (r: string) =>
	[...r].map((c) => (/[A-Z]/.test(c) ? c.toLowerCase() : /[a-z]/.test(c) ? c.toUpperCase() : c)).join('');
function swapCastling(c: string): string {
	if (c === '-') return '-';
	let o = '';
	if (c.includes('k')) o += 'K';
	if (c.includes('q')) o += 'Q';
	if (c.includes('K')) o += 'k';
	if (c.includes('Q')) o += 'q';
	return o || '-';
}
function mirrorFEN(fen: string): string {
	const [p, a, c, e, h, f] = fen.split(' ');
	const mp = p.split('/').reverse().map(swapRank).join('/');
	return `${mp} ${a === 'w' ? 'b' : 'w'} ${swapCastling(c)} ${e !== '-' ? mirrorSq(e) : '-'} ${h} ${f}`;
}
function tokens(fen: string): Float32Array {
	const order = 'PNBRQKpnbrqk';
	const t = new Float32Array(64 * 12);
	const rows = fen.split(' ')[0].split('/');
	for (let rank = 0; rank < 8; rank++) {
		const row = 7 - rank;
		let file = 0;
		for (const ch of rows[rank]) {
			if (isNaN(+ch)) {
				const idx = order.indexOf(ch);
				if (idx >= 0) t[(row * 8 + file) * 12 + idx] = 1;
				file++;
			} else file += +ch;
		}
	}
	return t;
}

let loadP: Promise<ort.InferenceSession> | null = null;
async function load(): Promise<ort.InferenceSession> {
	if (!loadP) {
		loadP = (async () => {
			if (!existsSync(MODEL_PATH)) {
				const res = await fetch(MODEL_URL);
				if (!res.ok) throw new Error(`maia3 download failed: ${res.status}`);
				mkdirSync('data/maia-models', { recursive: true });
				writeFileSync(MODEL_PATH, Buffer.from(await res.arrayBuffer()));
			}
			return ort.InferenceSession.create(new Uint8Array(readFileSync(MODEL_PATH)), {
				executionProviders: ['wasm']
			});
		})();
	}
	return loadP;
}
export async function preloadMaia3(): Promise<void> {
	await load();
}

// onnxruntime-web run() isn't reentrant — serialize (harness runs games in parallel)
let queue: Promise<unknown> = Promise.resolve();
function serialize<T>(fn: () => Promise<T>): Promise<T> {
	const run = queue.then(fn, fn);
	queue = run.then(
		() => {},
		() => {}
	);
	return run;
}

/**
 * The move Maia-3 plays at the given rating (self and opponent set equal).
 * temperature 0 = argmax (deterministic); >0 samples the policy — used for
 * calibration so games vary (else deterministic Maia-vs-Maia repeats), and it's
 * the more human behavior anyway (real players don't always play the modal move).
 */
export async function maiaMove3Node(fen: string, elo: number, temperature = 0.5): Promise<string | null> {
	const black = fen.split(' ')[1] === 'b';
	const board = new Chess(black ? mirrorFEN(fen) : fen);
	const legalIdx: number[] = [];
	for (const m of board.moves({ verbose: true }) as Move[]) {
		const i = MOVES[m.from + m.to + (m.promotion ?? '')];
		if (i !== undefined) legalIdx.push(i);
	}
	if (legalIdx.length === 0) return null;

	const session = await load();
	const out = await serialize(() =>
		session.run({
			tokens: new ort.Tensor('float32', tokens(board.fen()), [1, 64, 12]),
			elo_self: new ort.Tensor('float32', Float32Array.from([elo]), [1]),
			elo_oppo: new ort.Tensor('float32', Float32Array.from([elo]), [1])
		})
	);
	const logits = out.logits_move.data as Float32Array;
	let idx = legalIdx[0];
	if (temperature <= 0) {
		for (const i of legalIdx) if (logits[i] > logits[idx]) idx = i;
	} else {
		const ll = legalIdx.map((i) => logits[i] / temperature);
		const mx = Math.max(...ll);
		const ex = ll.map((l) => Math.exp(l - mx));
		const sum = ex.reduce((a, b) => a + b, 0);
		let r = Math.random() * sum;
		idx = legalIdx[legalIdx.length - 1];
		for (let k = 0; k < legalIdx.length; k++) {
			r -= ex[k];
			if (r <= 0) {
				idx = legalIdx[k];
				break;
			}
		}
	}
	const uci = MOVES_REV[idx];
	return black ? mirrorMove(uci) : uci;
}
