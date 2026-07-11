// Shared IndexedDB handle for the app's stores.

const DB_NAME = 'botvinnik';
const VERSION = 2;
export const ANALYSIS_STORE = 'analysis';
export const GAMES_STORE = 'games';

let dbPromise: Promise<IDBDatabase | null> | null = null;

export function openDb(): Promise<IDBDatabase | null> {
	if (typeof indexedDB === 'undefined') return Promise.resolve(null);
	if (dbPromise) return dbPromise;
	dbPromise = new Promise((resolve) => {
		try {
			const req = indexedDB.open(DB_NAME, VERSION);
			req.onupgradeneeded = () => {
				const db = req.result;
				if (!db.objectStoreNames.contains(ANALYSIS_STORE)) {
					const s = db.createObjectStore(ANALYSIS_STORE, { keyPath: 'key' });
					s.createIndex('lastUsedAt', 'lastUsedAt');
				}
				if (!db.objectStoreNames.contains(GAMES_STORE)) {
					const s = db.createObjectStore(GAMES_STORE, { keyPath: 'id' });
					s.createIndex('endedAt', 'endedAt');
				}
			};
			req.onsuccess = () => resolve(req.result);
			req.onerror = () => resolve(null);
		} catch {
			resolve(null);
		}
	});
	// opportunistically ask the browser to make this origin's storage durable
	try {
		navigator.storage?.persist?.();
	} catch {
		// not supported — fine
	}
	return dbPromise;
}
