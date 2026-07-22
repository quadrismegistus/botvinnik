// The Maia bots for Flutter web, in a Worker.
//
// Maia (McIlroy-Young et al.) is a human-imitation net: no search and no eval,
// just one ONNX policy forward pass returning the move a human of a given
// rating band would most likely play. That makes it unlike every other engine
// here, and it is why this is a worker rather than anything UCI-shaped.
//
// Why a worker at all, when Garbo and retro needed one for their own reasons:
// ort-web's runtime is ~13MB of WebAssembly to compile and a forward pass is
// real work. Doing either on the main thread stutters the board.
//
// The encoding and decoding are NOT here — they live in brain/maia/, because
// they are pure functions over a FEN history and the Svelte app needs exactly
// the same ones. This file is only the parts that touch the outside world:
// ort, the network, and IndexedDB. Keeping that line intact is what stops the
// two apps' Maia from quietly diverging.
//
// Protocol (this worker serialises; Dart also cancels before re-asking):
//   ← {id, fenHistory, band, temperature}
//   → {id, status: 'fetching', received, total}   while pulling the weights
//   → {id, status: 'starting'}                    while ORT compiles/builds
//   → {id, move: string | null}     the answer
//   → {id, error: string}           gave up; the caller falls back to Stockfish

import { Chess } from 'chess.js';
import * as ort from 'onnxruntime-web/wasm';

import { decodePolicyOutput } from '../../brain/maia/decoding';
import { encodeFenHistory } from '../../brain/maia/encoding';

declare const self: DedicatedWorkerGlobalScope;

// Community pre-conversions of the CSSLab lc0 weights, one repo per band.
// GPL-3.0, which is why they are fetched rather than redistributed with the
// app — see ARCHITECTURE.md. This is the app's ONLY third-party request, and
// it happens only when someone actually picks a Maia.
const modelUrl = (band: number) =>
	`https://huggingface.co/shermansiu/maia-${band}/resolve/main/model.onnx`;

// Same-origin, staged beside this worker by stage-web-assets.sh. The Svelte
// app points this at jsDelivr; we do not, because a CDN request would undo
// the offline guarantee for anyone who has already used a Maia once.
ort.env.wasm.wasmPaths = './';
// one policy eval — no threads, therefore no SharedArrayBuffer and no
// cross-origin-isolation headers to arrange
ort.env.wasm.numThreads = 1;

// A 3.5MB fetch that has not landed in 30s is stalled, not slow — abort it and
// (only this one) latch the band. This is the sole timeout worth giving up a
// band for a session over.
const FETCH_TIMEOUT_MS = 30_000;
// ORT compiles ~13MB of WebAssembly into a session here. That is LOCAL work
// that will finish, just slowly on a weak phone, so it gets its own far more
// generous cap. A short shared timeout used to fire on a perfectly good —
// often already-cached — band mid-compile and strand it as Stockfish for the
// rest of the page session, which is the "downloaded but still a stand-in"
// complaint this whole change answers.
const INIT_TIMEOUT_MS = 90_000;
const RUN_TIMEOUT_MS = 15_000;

function withTimeout<T>(p: Promise<T>, ms: number, what: string): Promise<T> {
	return Promise.race([
		p,
		new Promise<T>((_, reject) =>
			setTimeout(() => reject(new Error(`maia ${what} timed out`)), ms)
		)
	]);
}

// ---- model cache (IndexedDB) ----------------------------------------------
// A copy of the Svelte app's modelCache, deliberately: it is storage, so it
// cannot live in brain/, and it is 40 lines of IndexedDB boilerplate whose
// only contract is "a miss just means re-fetching". Every failure is
// non-fatal by construction.

const DB_NAME = 'botvinnik-maia';
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

// ---- sessions --------------------------------------------------------------

interface Loaded {
	session: ort.InferenceSession;
	inputName: string;
	policyName: string;
}

const loads = new Map<number, Promise<Loaded>>();

/// Bands whose network FETCH timed out this session. Those are not re-fetched.
///
/// The point is to kill a retry storm that can never be cheap: a network that
/// ACCEPTS and never answers — captive portal, stalled hotspot — costs a full
/// FETCH_TIMEOUT_MS on every move, forever, because each move re-enters a
/// deleted `loads` entry. Measured before this existed: three moves, three
/// attempts, 60s each.
///
/// Three things about the shape of it, each learned by getting it wrong first
/// (a global `broken` flag, checked before the cache lookup, latching on any
/// failure):
///
///   * **Per band, not global.** A 401 on one band used to kill a DIFFERENT
///     band that had a live in-memory session and cached weights.
///   * **Checked only on a cache MISS**, so a band whose 3.5MB already
///     downloaded keeps working no matter what the network did afterwards. This
///     gate now sits INSIDE `load`, after the cache read, precisely so — it
///     used to sit ahead of it and strand a fully-downloaded band as Stockfish.
///   * **Network-fetch timeouts only.** A fast failure (404, a corrupt cached
///     model, an ort init error) and a SLOW LOCAL COMPILE both cost nothing to
///     give up on: the first is cheap to retry, the second will finish given
///     time. Latching either buys nothing and silently substitutes Stockfish
///     for the rest of the session — the "different opponent wearing the
///     persona's name" the roster picker exists to prevent.
const timedOutBands = new Set<number>();

/// Bands whose weights are cached but whose SESSION would not start — the
/// runtime failed hard, not slowly. On a phone that is mobile Safari's
/// WebAssembly memory ceiling: ort-web cannot instantiate its ~13MB runtime
/// alongside Flutter's, and throws `RangeError: Out of memory` / `no available
/// backend`. It fails identically every time, so once is enough: retire the
/// band for the session and fall back to Stockfish cleanly, rather than paying
/// (and re-OOMing on) the instantiation on every single move. A page reload
/// clears it, so a genuinely one-off failure gets one fresh try per visit.
const deadBands = new Set<number>();

/** What the UI is told while a move waits on something other than inference. */
type Progress = { phase: 'fetching' | 'starting'; received?: number; total?: number };

/**
 * Read a response body, reporting as it arrives.
 *
 * Falls back to arrayBuffer() when the body is not streamable — some
 * browsers, and any response that has already been consumed. A download with
 * no progress is worse than one with; a download that FAILS because we
 * insisted on streaming it would be worse still.
 */
async function readWithProgress(
	res: Response,
	report: (p: Progress) => void
): Promise<ArrayBuffer> {
	const total = Number(res.headers.get('content-length')) || 0;
	const reader = res.body?.getReader();
	if (!reader) return res.arrayBuffer();

	const chunks: Uint8Array[] = [];
	let received = 0;
	// Report every ~4% rather than every chunk: a 3.5MB body arrives in
	// hundreds of pieces, and each postMessage crosses into Dart and rebuilds
	// a widget. The last chunk always reports, so the line always finishes.
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

/**
 * A stalled network FETCH specifically (AbortSignal.timeout), as opposed to a
 * slow local compile or inference. Only the fetch is worth latching a band for:
 * a compile and a cached band both finish given time, so retrying them is cheap
 * and right, whereas a network that accepts and never answers costs its full
 * timeout on every attempt forever.
 */
function isFetchTimeout(e: unknown): boolean {
	return e instanceof DOMException && e.name === 'TimeoutError';
}

/** The ORT compile timing out (a slow phone), as opposed to a hard start
 * failure (out of memory, no backend) — a timeout can succeed on a retry, so it
 * must not retire the band the way a hard failure does. */
function isInitTimeout(e: unknown): boolean {
	return e instanceof Error && e.message.includes('ort init timed out');
}

/** Whether this band's weights are already on disk — decides the UI message. */
async function isCached(band: number): Promise<boolean> {
	return (await getCached(`maia-${band}`)) !== null;
}

function load(band: number, report: (p: Progress) => void): Promise<Loaded> {
	let p = loads.get(band);
	if (!p) {
		p = (async () => {
			const key = `maia-${band}`;
			// The cache FIRST, ahead of any give-up gate: a band whose weights are
			// already on disk must always load, whatever a slow first attempt did
			// to the network latch. The gate used to sit in front of this, so once
			// a band timed out it stayed Stockfish for the session even after its
			// 3.5MB had finished downloading and been cached — the exact
			// "downloaded but still a stand-in" bug.
			let bytes = await getCached(key);
			if (!bytes) {
				// Only a real network fetch is gated, and only here — a cache hit
				// never reaches this line.
				if (timedOutBands.has(band)) {
					throw new Error(`maia-${band} network timed out earlier this session`);
				}
				const res = await fetch(modelUrl(band), {
					signal: AbortSignal.timeout(FETCH_TIMEOUT_MS)
				});
				if (!res.ok) throw new Error(`maia-${band} fetch failed: ${res.status}`);
				bytes = await readWithProgress(res, report);
				await putCached(key, bytes);
			}
			// The weights are in hand; from here a failure is the RUNTIME failing,
			// not the download. A band that already died that way this session
			// (mobile Safari's memory ceiling) will die identically — skip the
			// ~13MB instantiation and let it fall back to Stockfish.
			if (deadBands.has(band)) {
				throw new Error(`maia-${band} could not start earlier this session`);
			}
			// ORT fetches and compiles ~13MB of WebAssembly here, on the first
			// session of the page. It reports nothing and there is no total to
			// divide by, so this phase gets a NAME rather than a bar. Without
			// it the progress line runs to 100% and the app then sits silent
			// through the longest part of the wait, which reads as a hang —
			// which is the whole complaint this is answering.
			report({ phase: 'starting' });
			let session: ort.InferenceSession;
			try {
				session = await withTimeout(
					ort.InferenceSession.create(new Uint8Array(bytes), {
						executionProviders: ['wasm'],
						// Trim ORT's memory. On a policy net this small the optimiser
						// and the memory arena buy nothing measurable, and mobile
						// Safari's WASM ceiling is exactly what turns "load Maia" into
						// RangeError: Out of memory. A long shot against a runtime
						// that is itself ~13MB, but free to try and harmless.
						graphOptimizationLevel: 'basic',
						enableCpuMemArena: false,
						enableMemPattern: false
					}),
					INIT_TIMEOUT_MS,
					'ort init'
				);
			} catch (e) {
				// A compile TIMEOUT can succeed on a retry (a slow phone), so it does
				// not retire the band. A hard start failure — the memory ceiling, no
				// backend — will recur, so retire it for the session: the next move
				// falls back to Stockfish at once instead of re-OOMing.
				if (!isInitTimeout(e)) deadBands.add(band);
				throw e;
			}
			const inputName = session.inputNames[0];
			const policyName =
				session.outputNames.find((n) => n.toLowerCase().includes('policy')) ??
				session.outputNames[0];
			return { session, inputName, policyName };
		})();
		loads.set(band, p);
		p.catch((e) => {
			loads.delete(band);
			// Latch ONLY a stalled network fetch. A slow local compile and a
			// cached band both finish given time, so a warm-up or the next move
			// retries them cheaply; latching them is what turned one slow first
			// move on a phone into Stockfish for the whole session.
			if (isFetchTimeout(e)) timedOutBands.add(band);
		});
	}
	return p;
}

async function move(
	fenHistory: string[],
	band: number,
	temperature: number,
	report: (p: Progress) => void
): Promise<string | null> {
	const fen = fenHistory[fenHistory.length - 1];
	if (!fen) return null;
	const legal = new Chess(fen)
		.moves({ verbose: true })
		.map((m) => m.from + m.to + (m.promotion ?? ''));
	if (legal.length === 0) return null;

	const { session, inputName, policyName } = await load(band, report);
	const planes = encodeFenHistory(fenHistory);
	const out = await withTimeout(
		session.run({ [inputName]: new ort.Tensor('float32', planes, [1, 112, 8, 8]) }),
		RUN_TIMEOUT_MS,
		'inference'
	);
	const policy = new Float32Array(out[policyName].data as ArrayLike<number>);
	const isBlack = fen.split(' ')[1] === 'b';
	return decodePolicyOutput(policy, legal, isBlack, temperature).best.move;
}

/// Requests are handled one at a time.
///
/// Dart cancels its side before posting a new request, but cancelling is not
/// the same as not sending: `postMessage` still fires, so this worker can
/// receive a second request while the first is inside `session.run()`. ORT's
/// wasm bridge brackets a run with a process-global stack save/restore, so
/// overlapping runs on one InferenceSession is exactly the hazard the
/// protocol comment above claims does not exist. Now it does not.
let chain: Promise<unknown> = Promise.resolve();

self.onmessage = (e: MessageEvent) => {
	const req = e.data as {
		id: number;
		fenHistory?: string[];
		band: number;
		temperature?: number;
		preload?: boolean;
	};
	if (!req || typeof req.id !== 'number') return;
	chain = chain.then(() => handle(req)).catch(() => {});
};

async function handle(req: {
	id: number;
	fenHistory?: string[];
	band: number;
	temperature?: number;
	preload?: boolean;
}): Promise<void> {
	try {
		// A preload warms a band's weights and session the moment it is CHOSEN,
		// off any move's clock, so a later move for it answers at once instead of
		// standing in while a phone pulls 3.5MB and compiles the runtime. No move
		// runs and none is expected back; the same load()/progress path a move
		// uses does the work, and a move that arrives mid-warm-up joins it via
		// the per-band `loads` cache rather than starting a second download.
		if (req.preload) {
			await load(req.band, (p) => self.postMessage({ id: req.id, ...p, status: p.phase }));
			self.postMessage({ id: req.id, ready: true });
			return;
		}
		const uci = await move(req.fenHistory ?? [], req.band, req.temperature ?? 0, (p) =>
			self.postMessage({ id: req.id, ...p, status: p.phase })
		);
		self.postMessage({ id: req.id, move: uci });
	} catch (err) {
		self.postMessage({ id: req.id, error: String(err) });
	}
}
