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
// Protocol (one request in flight, Dart serialises):
//   ← {id, fenHistory, band, temperature}
//   → {id, status: 'fetching'}      once, only when the weights are NOT cached
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

const LOAD_TIMEOUT_MS = 60_000;
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

/** Whether this band's weights are already on disk — decides the UI message. */
async function isCached(band: number): Promise<boolean> {
	return (await getCached(`maia-${band}`)) !== null;
}

function load(band: number): Promise<Loaded> {
	let p = loads.get(band);
	if (!p) {
		p = (async () => {
			const key = `maia-${band}`;
			let bytes = await getCached(key);
			if (!bytes) {
				const res = await fetch(modelUrl(band), {
					signal: AbortSignal.timeout(LOAD_TIMEOUT_MS)
				});
				if (!res.ok) throw new Error(`maia-${band} fetch failed: ${res.status}`);
				bytes = await res.arrayBuffer();
				await putCached(key, bytes);
			}
			const session = await withTimeout(
				ort.InferenceSession.create(new Uint8Array(bytes), { executionProviders: ['wasm'] }),
				LOAD_TIMEOUT_MS,
				'ort init'
			);
			const inputName = session.inputNames[0];
			const policyName =
				session.outputNames.find((n) => n.toLowerCase().includes('policy')) ??
				session.outputNames[0];
			return { session, inputName, policyName };
		})();
		loads.set(band, p);
		// a failed load must not be remembered as a load — the next attempt
		// deserves a clean try (a flaky network is the likely cause)
		p.catch(() => loads.delete(band));
	}
	return p;
}

async function move(
	fenHistory: string[],
	band: number,
	temperature: number,
	announce: () => void
): Promise<string | null> {
	const fen = fenHistory[fenHistory.length - 1];
	if (!fen) return null;
	const legal = new Chess(fen)
		.moves({ verbose: true })
		.map((m) => m.from + m.to + (m.promotion ?? ''));
	if (legal.length === 0) return null;

	if (!(await isCached(band))) announce();

	const { session, inputName, policyName } = await load(band);
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

self.onmessage = async (e: MessageEvent) => {
	const req = e.data as {
		id: number;
		fenHistory: string[];
		band: number;
		temperature?: number;
	};
	if (!req || typeof req.id !== 'number') return;
	try {
		const uci = await move(req.fenHistory, req.band, req.temperature ?? 0, () =>
			self.postMessage({ id: req.id, status: 'fetching' })
		);
		self.postMessage({ id: req.id, move: uci });
	} catch (err) {
		self.postMessage({ id: req.id, error: String(err) });
	}
};
