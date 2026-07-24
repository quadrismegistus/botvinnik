// Maia-3 for Flutter web — the moves-by-rating chart engine, in a Worker.
//
// Maia-3 (CSSLab) is a single ELO-conditioned ONNX model: one net, dial the
// rating. Unlike Maia-1's nine per-band nets, one forward pass over a BATCHED
// ELO ladder returns a policy + WDL at every rung simultaneously. That is what
// makes the chart affordable — 21 distributions in one inference, not 21.
//
// The encoding (board → tensor) lives in brain/maia3/encoding.ts. This file
// is only the parts that touch the outside world: ORT, the network, and
// IndexedDB. Masking, softmax, and the chart-friendly shape are done on the
// main thread via brain/maia3/decoding.ts — the worker returns RAW logits
// only, keeping one source of truth for that math and avoiding chess.js here.
//
// Protocol (structured objects, not UCI text):
//   ← { type: 'init' }
//   → { type: 'fetching', received?, total? }   while pulling the model
//   → { type: 'starting' }                      while ORT compiles
//   → { type: 'ready' }
//   ← { type: 'analyze', id, fen, eloInputs: number[] }
//   → { id, rawPolicyByElo: [{elo, policy: Float32Array}],
//        rawWdlByElo:   [{elo, wdl:   Float32Array}] }
//   → { id, error: string }

import * as ort from 'onnxruntime-web/wasm';
import { encodeBoard } from '../../brain/maia3/encoding';

declare const self: DedicatedWorkerGlobalScope;

// The model: CSSLab's "simplified" export (no history planes, 64×12 tokens).
// Fetched on first use, cached in IndexedDB. Same pattern as the Maia-1
// worker — the model is ~6MB and too large to bundle in the repo.
const MODEL_URL =
	'https://raw.githubusercontent.com/CSSLab/maia-platform-frontend/main/public/maia3/maia3_simplified.onnx';
const MODEL_KEY = 'maia3';

// Same-origin, staged beside this worker by stage-web-assets.sh.
ort.env.wasm.wasmPaths = './';
// No threads → no SharedArrayBuffer → no cross-origin-isolation headers.
ort.env.wasm.numThreads = 1;

const FETCH_TIMEOUT_MS = 60_000; // 6MB on a slow connection
const INIT_TIMEOUT_MS = 90_000; // ORT compiles ~13MB of wasm
const RUN_TIMEOUT_MS = 15_000;

function withTimeout<T>(p: Promise<T>, ms: number, what: string): Promise<T> {
	return Promise.race([
		p,
		new Promise<T>((_, reject) =>
			setTimeout(() => reject(new Error(`maia3 ${what} timed out`)), ms),
		),
	]);
}

// ─── IndexedDB cache (separate DB from Maia-1) ────────────────────────────

const DB_NAME = 'botvinnik-maia3';
const STORE = 'models';

function openDb(): Promise<IDBDatabase | null> {
	if (typeof indexedDB === 'undefined') return Promise.resolve(null);
	return new Promise((resolve) => {
		try {
			const req = indexedDB.open(DB_NAME, 1);
			req.onupgradeneeded = () => {
				if (!req.result.objectStoreNames.contains(STORE)) req.result.createObjectStore(STORE);
			};
			req.onsuccess = () => resolve(req.result);
			req.onerror = () => resolve(null);
		} catch {
			resolve(null);
		}
	});
}

async function getCached(key: string): Promise<ArrayBuffer | null> {
	const db = await openDb();
	if (!db) return null;
	return new Promise((resolve) => {
		try {
			const req = db.transaction(STORE, 'readonly').objectStore(STORE).get(key);
			req.onsuccess = () => resolve((req.result as ArrayBuffer) ?? null);
			req.onerror = () => resolve(null);
		} catch {
			resolve(null);
		}
	});
}

async function putCached(key: string, bytes: ArrayBuffer): Promise<void> {
	const db = await openDb();
	if (!db) return;
	try {
		db.transaction(STORE, 'readwrite').objectStore(STORE).put(bytes, key);
	} catch {
		// storage failures are never fatal
	}
}

// ─── Progress reporting for the download ──────────────────────────────────

type Progress = { phase: 'fetching' | 'starting'; received?: number; total?: number };

async function readWithProgress(res: Response, report: (p: Progress) => void): Promise<ArrayBuffer> {
	const total = Number(res.headers.get('content-length')) || 0;
	const reader = res.body?.getReader();
	if (!reader) return res.arrayBuffer();

	const chunks: Uint8Array[] = [];
	let received = 0;
	const step = total > 0 ? Math.max(total / 25, 65536) : 262144;
	let reported = 0;
	report({ phase: 'fetching', received: 0, total });
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		chunks.push(value);
		received += value.length;
		if (received - reported >= step) {
			reported = received;
			report({ phase: 'fetching', received, total });
		}
	}
	report({ phase: 'fetching', received, total: total || received });

	const out = new Uint8Array(received);
	let at = 0;
	for (const c of chunks) {
		out.set(c, at);
		at += c.length;
	}
	return out.buffer;
}

// ─── Session lifecycle ────────────────────────────────────────────────────

let sessionP: Promise<ort.InferenceSession> | null = null;
let sessionFailed = false;

async function initSession(report: (p: Progress) => void): Promise<ort.InferenceSession> {
	if (sessionP) return sessionP;
	if (sessionFailed) throw new Error('maia3: session failed earlier this session');

	sessionP = (async () => {
		let bytes = await getCached(MODEL_KEY);
		if (!bytes) {
			const res = await fetch(MODEL_URL, { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
			if (!res.ok) throw new Error(`maia3 fetch failed: ${res.status}`);
			bytes = await readWithProgress(res, report);
			await putCached(MODEL_KEY, bytes);
		}
		report({ phase: 'starting' });
		return withTimeout(
			ort.InferenceSession.create(new Uint8Array(bytes), {
				executionProviders: ['wasm'],
				graphOptimizationLevel: 'basic',
				enableCpuMemArena: false,
				enableMemPattern: false,
			}),
			INIT_TIMEOUT_MS,
			'ort init',
		);
	})();

	sessionP.catch(() => {
		sessionFailed = true;
		sessionP = null;
	});

	return sessionP;
}

// ─── Batched-ladder inference ─────────────────────────────────────────────

const NUM_SQUARES = 64;
const PLANES_PER_SQUARE = 12;
const POLICY_VOCAB_SIZE = 4352;
const WDL_SIZE = 3;

/**
 * Runs ONE batched inference across the ELO ladder: the same board tensor is
 * repeated B times, only elo_self/elo_oppo vary per batch item. Returns raw
 * policy + WDL logits per rung — masking and softmax happen on the main
 * thread via brain/maia3/decoding.ts.
 */
async function analyze(
	session: ort.InferenceSession,
	fen: string,
	eloInputs: readonly number[],
): Promise<{
	rawPolicyByElo: { elo: number; policy: Float32Array }[];
	rawWdlByElo: { elo: number; wdl: Float32Array }[];
}> {
	const batchSize = eloInputs.length;
	const boardTokens = encodeBoard(fen);
	const tokens = new Float32Array(batchSize * NUM_SQUARES * PLANES_PER_SQUARE);
	for (let b = 0; b < batchSize; b++) {
		tokens.set(boardTokens, b * NUM_SQUARES * PLANES_PER_SQUARE);
	}

	const feeds = {
		tokens: new ort.Tensor('float32', tokens, [batchSize, NUM_SQUARES, PLANES_PER_SQUARE]),
		elo_self: new ort.Tensor('float32', Float32Array.from(eloInputs), [batchSize]),
		elo_oppo: new ort.Tensor('float32', Float32Array.from(eloInputs), [batchSize]),
	};

	let outputs: Record<string, ort.Tensor> | undefined;
	try {
		outputs = (await withTimeout(session.run(feeds), RUN_TIMEOUT_MS, 'inference')) as Record<
			string,
			ort.Tensor
		>;
		const policyFlat = new Float32Array(outputs.logits_move.data as ArrayLike<number>);
		const wdlFlat = new Float32Array(outputs.logits_value.data as ArrayLike<number>);

		// .slice() copies the logits out of wasm memory so tensors can be
		// disposed in finally without invalidating what we return.
		const rawPolicyByElo = eloInputs.map((elo, i) => ({
			elo,
			policy: policyFlat.slice(i * POLICY_VOCAB_SIZE, (i + 1) * POLICY_VOCAB_SIZE),
		}));
		const rawWdlByElo = eloInputs.map((elo, i) => ({
			elo,
			wdl: wdlFlat.slice(i * WDL_SIZE, (i + 1) * WDL_SIZE),
		}));

		return { rawPolicyByElo, rawWdlByElo };
	} finally {
		// Dispose every tensor after each run — ORT wasm heap grows otherwise
		// (flawchess hit OOM at ~270k calls in calibration). Per-call disposal
		// keeps the heap flat.
		for (const t of Object.values(feeds)) t.dispose?.();
		if (outputs) for (const t of Object.values(outputs)) t.dispose?.();
	}
}

// ─── Message handling (one at a time — ORT can't overlap runs) ─────────────

let chain: Promise<unknown> = Promise.resolve();

self.onmessage = (e: MessageEvent) => {
	const msg = e.data;
	if (!msg || typeof msg !== 'object') return;

	if (msg.type === 'init') {
		// Re-key phase → type on the wire: the protocol (and the Dart client)
		// speak `type`; posting the Progress object verbatim shipped a message
		// nobody could read and the first-use narration was silently dead.
		initSession((p) =>
			self.postMessage({ type: p.phase, received: p.received, total: p.total }),
		).then(
			() => self.postMessage({ type: 'ready' }),
			(err) => self.postMessage({ type: 'error', message: String(err) }),
		);
		return;
	}

	if (msg.type === 'analyze' && typeof msg.id !== 'undefined') {
		const req = msg as { id: number; fen: string; eloInputs: number[] };
		chain = chain
			.then(async () => {
				const session = await initSession(() => {});
				const result = await analyze(session, req.fen, req.eloInputs);
				self.postMessage({ id: req.id, ...result });
			})
			.catch((err) => {
				self.postMessage({ id: req.id, error: String(err) });
			});
		return;
	}
};
