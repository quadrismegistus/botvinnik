// Persist fetched Maia ONNX model bytes in IndexedDB so we download each band's
// weights (~3.5 MB) only once. Keyed by band id. All failures are non-fatal —
// a miss just means re-fetching from the network.

const DB_NAME = 'botvinnik-maia';
const STORE = 'models';
const VERSION = 1;

function open(): Promise<IDBDatabase | null> {
	if (typeof indexedDB === 'undefined') return Promise.resolve(null);
	return new Promise((resolve) => {
		try {
			const req = indexedDB.open(DB_NAME, VERSION);
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

export async function getCachedModel(key: string): Promise<ArrayBuffer | null> {
	const db = await open();
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

export async function putCachedModel(key: string, bytes: ArrayBuffer): Promise<void> {
	const db = await open();
	if (!db) return;
	try {
		db.transaction(STORE, 'readwrite').objectStore(STORE).put(bytes, key);
	} catch {
		// storage failures are never fatal
	}
}
