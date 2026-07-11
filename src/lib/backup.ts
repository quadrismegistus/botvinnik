// Export/import of the data that can't be recreated: practice items and the
// game archive. Doubles as migration between origins (localhost vs deployed).

import { listGames, saveGame, type StoredGame } from './gameStore';
import { loadItems, saveItems, type PracticeItem } from './practice';

interface Backup {
	app: 'botvinnik';
	version: 1;
	exportedAt: string;
	practice: PracticeItem[];
	games: StoredGame[];
}

export async function downloadBackup(): Promise<void> {
	const backup: Backup = {
		app: 'botvinnik',
		version: 1,
		exportedAt: new Date().toISOString(),
		practice: loadItems(),
		games: await listGames()
	};
	const blob = new Blob([JSON.stringify(backup)], { type: 'application/json' });
	const a = document.createElement('a');
	a.href = URL.createObjectURL(blob);
	a.download = `botvinnik-backup-${backup.exportedAt.slice(0, 10)}.json`;
	document.body.appendChild(a); // detached-anchor clicks are ignored in some browsers
	a.click();
	a.remove();
	URL.revokeObjectURL(a.href);
}

// Merge, never clobber: practice items dedupe by id keeping the copy with more
// attempts (= the one that has been trained); games dedupe by id.
export async function importBackup(file: File): Promise<{ practice: number; games: number }> {
	const data = JSON.parse(await file.text()) as Backup;
	if (data.app !== 'botvinnik' || !Array.isArray(data.practice) || !Array.isArray(data.games)) {
		throw new Error('Not a botvinnik backup file');
	}

	const byId = new Map(loadItems().map((i) => [i.id, i]));
	let practiceAdded = 0;
	for (const item of data.practice) {
		const cur = byId.get(item.id);
		if (!cur) {
			byId.set(item.id, item);
			practiceAdded++;
		} else if ((item.attempts ?? 0) > (cur.attempts ?? 0)) {
			byId.set(item.id, item);
		}
	}
	saveItems([...byId.values()]);

	const have = new Set((await listGames()).map((g) => g.id));
	let gamesAdded = 0;
	for (const g of data.games) {
		if (have.has(g.id)) continue;
		await saveGame(g);
		gamesAdded++;
	}

	return { practice: practiceAdded, games: gamesAdded };
}
