// In-app chess.com archive import: fetch monthly archives, analyze every game
// on the dedicated import engine pool (native pool in the desktop shell, one
// WASM worker on the web), grade with the shared code, and hand each finished
// game to the caller. Runs in the background — live play keeps its own engine.

import { ccGameToAnalysed, fetchChesscomArchives, fetchChesscomMonth } from './chesscomCore';
import { createImportPool } from './engine/importPool';
import { analysedGameToStored, type PracticeCandidate } from './lichessImport';
import type { StoredGame } from './gameStore';

export interface CcImportProgress {
	phase: 'fetching' | 'analyzing' | 'done' | 'cancelled' | 'error';
	monthsDone: number;
	monthsTotal: number;
	currentMonth: string;
	gamesDone: number;
	gamesPlanned: number; // games seen so far across fetched months (grows)
	gamesAdded: number;
	practiceAdded: number;
	gamesPerMin: number;
	engines: number;
	error?: string;
}

export interface CcImportHandle {
	cancel(): void;
	finished: Promise<CcImportProgress>;
}

const NODES = 300_000;

export function startChesscomImport(opts: {
	username: string;
	maxGames?: number;
	existingIds: Set<string>;
	fullMovesFor?: number; // keep per-move data for the N newest games (default 500)
	onProgress: (p: CcImportProgress) => void;
	// caller persists the game and decides what to do with practice candidates;
	// returns how many practice items it actually added
	onGame: (stored: StoredGame, practice: PracticeCandidate[]) => Promise<number>;
}): CcImportHandle {
	const signal = { aborted: false };
	const progress: CcImportProgress = {
		phase: 'fetching',
		monthsDone: 0,
		monthsTotal: 0,
		currentMonth: '',
		gamesDone: 0,
		gamesPlanned: 0,
		gamesAdded: 0,
		practiceAdded: 0,
		gamesPerMin: 0,
		engines: 0
	};
	const report = () => opts.onProgress({ ...progress });

	const finished = (async (): Promise<CcImportProgress> => {
		const pool = await createImportPool(NODES);
		progress.engines = pool.size;
		const t0 = Date.now();
		const fullMovesFor = opts.fullMovesFor ?? 500;
		let fullKept = 0;
		try {
			const months = await fetchChesscomArchives(opts.username);
			progress.monthsTotal = months.length;
			report();

			for (const monthUrl of months) {
				if (signal.aborted) break;
				if (opts.maxGames && progress.gamesDone >= opts.maxGames) break;
				progress.currentMonth = monthUrl.split('/games/')[1] ?? '';
				progress.phase = 'analyzing';
				const games = await fetchChesscomMonth(monthUrl);
				progress.gamesPlanned += games.length;
				report();

				for (const cc of games) {
					if (signal.aborted) break;
					if (opts.maxGames && progress.gamesDone >= opts.maxGames) break;
					if (opts.existingIds.has(`chesscom-${cc.uuid}`)) {
						progress.gamesDone++;
						continue;
					}
					const analysed = await ccGameToAnalysed(cc, pool.evalPosition, signal);
					progress.gamesDone++;
					if (analysed) {
						const mapped = analysedGameToStored(analysed, opts.username, 'chesscom');
						if (mapped) {
							if (fullKept >= fullMovesFor) mapped.stored.moves = [];
							else fullKept++;
							progress.practiceAdded += await opts.onGame(mapped.stored, mapped.practice);
							opts.existingIds.add(mapped.stored.id);
							progress.gamesAdded++;
						}
					}
					progress.gamesPerMin = progress.gamesDone / ((Date.now() - t0) / 60000);
					report();
				}
				progress.monthsDone++;
				report();
			}
			progress.phase = signal.aborted ? 'cancelled' : 'done';
		} catch (e) {
			progress.phase = 'error';
			progress.error = e instanceof Error ? e.message : String(e);
		} finally {
			pool.dispose();
		}
		report();
		return { ...progress };
	})();

	return {
		cancel: () => {
			signal.aborted = true;
		},
		finished
	};
}
