<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import { browser } from '$app/environment';
	import { botDelay, selectBotMove, shapedBotMove, shapedLabelFor, shapedSearchDepth } from '$lib/bot';
	import { personaById, personaInternalElo, type BotPersona } from '$lib/bots';
	import { estimatePlayerElo } from '$lib/playerElo';
	import Board from '$lib/components/Board.svelte';
	import MaterialBar from '$lib/components/MaterialBar.svelte';
	import BottomSheet from '$lib/components/BottomSheet.svelte';
	import BotPanel from '$lib/components/BotPanel.svelte';
	import ModeBar, { type SideView } from '$lib/components/ModeBar.svelte';
	import RosterPicker, { type PersonaRecord } from '$lib/components/RosterPicker.svelte';
	import { CLASS } from '$lib/classifications';
	import AnalysisPanel from '$lib/components/AnalysisPanel.svelte';
	import InsightsPanel from '$lib/components/InsightsPanel.svelte';
	import MoveList from '$lib/components/MoveList.svelte';
	import LinesTree from '$lib/components/LinesTree.svelte';
	import WinChanceChart from '$lib/components/WinChanceChart.svelte';
	import { downloadBackup, importBackup } from '$lib/backup';
	import { startChesscomImport, type CcImportHandle, type CcImportProgress } from '$lib/chesscomImport';
	import { importLichessGames } from '$lib/lichessImport';
	import CommentaryPanel from '$lib/components/CommentaryPanel.svelte';
	import GamesPanel from '$lib/components/GamesPanel.svelte';
	import PracticePanel from '$lib/components/PracticePanel.svelte';
	import SidePanel from '$lib/components/SidePanel.svelte';
	import UnifiedMovesPanel from '$lib/components/UnifiedMovesPanel.svelte';
	import { getCommentary, type CommentaryEntry } from '$lib/commentary';
	import { getFenAfter, getPgn, getSan, getState, isPromotionMove, loadFen, makeMove, reset, undo } from '$lib/engine/chess';
	import {
		deleteGame,
		gameAccuracy,
		labelCounts,
		LABEL_VERSION,
		listGames,
		sanitizeStoredGames,
		saveGame,
		type StoredGame,
		type StoredMove
	} from '$lib/gameStore';
	import { explainGoodMove, explainMove, motifTags, type Explanation } from '$lib/engine/explain';
	import {
		backfillGrade,
		gradeMove,
		whitePovWinChance,
		winChance,
		type MoveGrade,
		type MoveLabel
	} from '$lib/engine/insights';
	import {
		analyze,
		analyzeBotMove,
		analyzeMove,
		analyzeShapedMove,
		getAnalysisBudget,
		stopEngine,
		type EngineMove
	} from '$lib/engine/stockfish';
	import { botSpec, botEloMax, botEloMin } from '$lib/engine/botRecipe';
	import { maiaMove, inMaiaRange, preloadMaia } from '$lib/engine/maia';
	import { retroMove, preloadRetro } from '$lib/engine/retro';
	import { dalaMove, preloadDala, onDalaDownload } from '$lib/engine/dala';
	import { jsceMove } from '$lib/engine/jsce';
	import { garboMove, preloadGarbo } from '$lib/engine/garbo';
	import { computeControl } from '$lib/engine/control';
	import { findThreat, type Threat } from '$lib/engine/threats';
	import {
		addItem,
		dueCount,
		enPassantSetup,
		itemDataFromStoredMove,
		loadItems,
		nextItem,
		puzzleSetupMove,
		recordResult,
		removeItem,
		type AttemptResult,
		type PracticeItem
	} from '$lib/practice';

	let game = $state(getState());
	let engineMoves: EngineMove[] = $state([]);
	let analyzing = $state(false);
	let showArrows = $state(true);
	let lastMove: [string, string] | null = $state(null);
	let panelsHidden = $state(false);
	// which sidebar the user is looking at — the app's three modes as real
	// navigation (ModeBar). Distinct from `mode`: sideView 'practice' shows the
	// practice lobby while mode is still 'play'; Start flips mode to 'practice'.
	let sideView: SideView = $state('play');
	let rosterOpen = $state(false); // the grouped opponent picker (RosterPicker)
	let gearOpen = $state(false); // narrow: board-toggle popover in the sheet header
	// remaining collapsibles: the engine-lines tree and the opening book
	let treeOpen = $state(false);
	let bookOpen = $state(false);
	let commentaryOpen = $state(false); // desktop play: commentary card via footer link
	let commentary: CommentaryEntry[] = $state([]);

	// switching away from an active practice/review session ends it (the mode
	// switcher is the only way in AND out; the guards keep a lobby visit from
	// resetting a live game)
	function setView(v: SideView) {
		if (v === sideView) return;
		if (mode === 'review') exitReview();
		if (mode === 'practice') exitPractice();
		sideView = v;
		gearOpen = false;
	}

	// human commentary for the position on the board (placement-keyed, lazy-loaded)
	$effect(() => {
		const fen = game.fen;
		void getCommentary(fen).then((c) => {
			if (fen === game.fen) commentary = c;
		});
	});
	let blindMode = $state(false);
	let showThreats = $state(true);
	let threat: Threat | null = $state(null);
	let showControl = $state(false);
	let pendingPromotion: { from: string; to: string } | null = $state(null);
	let boardResetKey = $state(0);
	// seed from the real window: bind:innerWidth only corrects these on resize
	// events, and a phone that never fires one would keep the SSR defaults
	let viewportH = $state(browser ? window.innerHeight : 900);
	let viewportW = $state(browser ? window.innerWidth : 1280);
	// the board fills the window height; everything else lives in the right sidebar,
	// which soaks up the remaining width
	const TREE_HEIGHT = 200; // LinesTree svg
	const CHROME_V = 100; // page padding + title
	const MATERIAL_H = 44; // the two material strips above & below the board
	const SIDEBAR_MIN = 340; // sidebar min width + gap
	// below this the sidebar can't sit beside the board: phone/narrow layout —
	// board pinned at the top, panels live as tabs in a draggable bottom sheet
	const isNarrow = $derived(viewportW < 860);

	// bottom-sheet shell (narrow layout only)
	type SheetDetent = 'peek' | 'half' | 'full';
	const SHEET_PEEK = 118; // collapsed sheet: handle + grade strip + mode bar + view tabs
	let sheetDetent: SheetDetent = $state('peek');
	let sheetTab = $state('insights');
	// the board shrinks so the sheet's resting position never hides a rank.
	// 'full' sizes like 'half': the sheet covers the board region there anyway,
	// and resizing to a thumbnail behind it helps nobody
	const sheetRestH = $derived(
		sheetDetent === 'peek' ? SHEET_PEEK : Math.round(viewportH * 0.5)
	);
	const boardSize = $derived(
		isNarrow
			? Math.max(200, Math.min(viewportW - 16, viewportH - sheetRestH - 44 - MATERIAL_H))
			: Math.max(
					360,
					Math.min(
						viewportH - CHROME_V - MATERIAL_H,
						viewportW - (panelsHidden ? 120 : SIDEBAR_MIN + 60)
					)
				)
	);
	// narrow-layout view tabs: readouts only. Modes live in the ModeBar, the
	// board toggles behind the gear, the bot card is pinned above the tab body.
	const narrowTabs = [
		{ id: 'insights', label: 'Insights' },
		{ id: 'lines', label: 'Lines' },
		{ id: 'chart', label: 'Chart' },
		{ id: 'moves', label: 'Moves' },
		{ id: 'book', label: 'Book' }
	];
	const activeTab = $derived(narrowTabs.some((t) => t.id === sheetTab) ? sheetTab : 'insights');
	function selectTab(id: string) {
		sheetTab = id;
		if (sheetDetent === 'peek') sheetDetent = 'half';
	}

	const playedSans = $derived(game.moves.map((m) => m.san));
	const topMoves = $derived(engineMoves.slice(0, 3));

	// one grade per played move, judged against the pre-move analysis
	let moveHistory: MoveGrade[] = $state([]);
	const insightWhite = $derived(moveHistory.findLast((g) => g.color === 'w') ?? null);
	const insightBlack = $derived(moveHistory.findLast((g) => g.color === 'b') ?? null);

	// the sheet's one-line grade strip: your latest graded move (vs a bot), or
	// simply the last move in free analysis — visible at peek height so the
	// move → verdict loop survives on a phone without lifting the sheet
	const lastGrade = $derived.by(() => {
		if (mode !== 'play' || moveHistory.length === 0) return null;
		if (!botEnabled) return moveHistory.at(-1) ?? null;
		const humanSide = botColor === 'w' ? 'b' : 'w';
		return moveHistory.findLast((g) => g.color === humanSide) ?? null;
	});

	// your W–L–D per persona, from the archive (display only — the rating fit
	// applies its own exclusions in playerElo.ts)
	const personaRecords = $derived.by(() => {
		const rec: Record<string, PersonaRecord> = {};
		for (const g of storedGames) {
			if (!g.botPersona || g.botColor === null) continue;
			if (g.result !== '1-0' && g.result !== '0-1' && g.result !== '1/2-1/2') continue;
			const r = (rec[g.botPersona] ??= { w: 0, l: 0, d: 0 });
			if (g.result === '1/2-1/2') r.d++;
			else if ((g.result === '1-0') === (g.botColor === 'b')) r.w++;
			else r.l++;
		}
		return rec;
	});

	// White-POV win chance per played move, for the win-chance chart
	const wcChartPoints = $derived(
		moveHistory.map((g) => ({
			ply: g.ply,
			wcWhite: whitePovWinChance(g.color, g.evalPawns, g.mate),
			label: g.label,
			san: g.san
		}))
	);

	// practice list + mode
	// pass = the move labels "good" or better — under 5% win-chance loss, the
	// same boundary where the insight chip turns to "inaccuracy"
	const PASS_DROP = 5;
	const THRESHOLD_KEY = 'botvinnik-collect-threshold';
	let collectThreshold = $state(15); // win% drop that makes a move practice-worthy
	let practiceItems: PracticeItem[] = $state([]);
	let collectedPlies = $state(new Set<number>());
	let mode: 'play' | 'practice' | 'review' = $state('play');
	let currentItem: PracticeItem | null = $state(null);
	let attempt: AttemptResult | null = $state(null);
	let grading = $state(false);
	let revealBest = $state(false);
	let practiceMotif: string | null = $state(null); // drill filter: only items with this motif
	let hintTier = $state(0); // 0 none, 1 text, 2 origin square, 3 full reveal
	// drill kind: 'find-best' = the classic "find the strong move" puzzle;
	// 'blundercheck' = the DEFENSIVE drill — from the position after your played
	// mistake, find how the opponent punishes it (trains the pre-move scan).
	let drill: 'find-best' | 'blundercheck' = $state('find-best');
	let blundercheckActive = $state(false); // this puzzle is currently a blundercheck
	let puzzleLoading = $state(false); // computing the refutation for a blundercheck
	let puzzleToken = 0; // guards the async blundercheck load against supersession
	let easeIn = $state(true); // bias each session toward easier puzzles first (morale on-ramp)
	let sessionSolved = $state(0); // passes this practice session (for the progress readout)
	let sessionStreak = $state(0); // consecutive cold passes this session
	const practiceDue = $derived(dueCount(practiceItems));

	// tier-1 hint text, drawn from the same motif detectors — names the fact
	// family without giving the move away
	const hint = $derived.by((): string | null => {
		if (hintTier < 1 || !practiceRef) return null;
		const ref = practiceRef;
		if (ref.mateBest !== null && ref.mateBest > 0) return "There's a forced mate.";
		const m = motifTags(ref.fen, ref.bestUci, ref.bestPv, ref.mateBest)[0];
		if (!m) return 'Look for the strongest move.';
		if (m === 'free capture') return 'You can win a piece.';
		if (m === 'material') return 'You can win material.';
		return `There's a ${m} available.`;
	});

	// what the current practice position is graded against — the stored item at
	// first, then live analysis when "Continue" extends the line
	interface PracticeRef {
		fen: string;
		bestUci: string;
		bestSan: string;
		evalBest: number; // mover's perspective, pawns
		mateBest: number | null;
		wcBest: number;
		bestPv: string[];
		depth: number;
	}
	let practiceRef: PracticeRef | null = $state(null);
	let lineDepth = $state(0); // how many "Continue" steps past the stored puzzle
	let attemptGrade: MoveGrade | null = $state(null); // insight card for the attempt
	let continuing = $state(false); // engine playing the opponent reply
	let lineNote: string | null = $state(null); // e.g. the line ended in mate

	// data backup
	let importInput: HTMLInputElement | null = $state(null);
	let importMsg = $state('');

	async function handleImportFile(e: Event) {
		const file = (e.currentTarget as HTMLInputElement).files?.[0];
		if (!file) return;
		try {
			const { practice, games } = await importBackup(file);
			practiceItems = loadItems();
			storedGames = await listGames();
			importMsg = `Imported ${practice} practice position${practice === 1 ? '' : 's'}, ${games} game${games === 1 ? '' : 's'}.`;
		} catch {
			importMsg = 'Import failed — not a botvinnik backup file.';
		}
		if (importInput) importInput.value = '';
	}

	// lichess import
	let lichessImporting = $state(false);
	let lichessStatus = $state('');

	async function handleLichessImport(username: string) {
		lichessImporting = true;
		lichessStatus = '';
		try {
			const existing = new Set(storedGames.map((g) => g.id));
			const result = await importLichessGames(username, existing, collectThreshold);
			for (const g of result.games) {
				g.labelVersion = LABEL_VERSION; // freshly analyzed with the current ruleset
				await saveGame(g);
			}
			let added = 0;
			for (const p of result.practice) {
				const next = addItem(practiceItems, {
					...p,
					motifs: motifTags(p.fen, p.bestUci, p.bestPv ?? [p.bestUci], p.mateBest)
				});
				if (next) {
					practiceItems = next;
					added++;
				}
			}
			storedGames = await listGames();
			lichessStatus =
				result.games.length === 0
					? `No new analysed games for ${result.username}${result.skipped ? ` (${result.skipped} already imported or unanalysed)` : ''}.`
					: `Imported ${result.games.length} game${result.games.length === 1 ? '' : 's'}, ${added} practice position${added === 1 ? '' : 's'}.`;
		} catch (e) {
			lichessStatus = e instanceof Error ? e.message : 'Import failed.';
		} finally {
			lichessImporting = false;
		}
	}

	// chess.com archive import — background analysis on the import engine pool
	const PRACTICE_CAP = 1000;
	let ccImport: CcImportProgress | null = $state(null);
	let ccHandle: CcImportHandle | null = null;

	function startCcImport(username: string, maxGames?: number) {
		if (ccHandle) return;
		ccHandle = startChesscomImport({
			username,
			maxGames,
			existingIds: new Set(storedGames.map((g) => g.id)),
			onProgress: (p) => (ccImport = p),
			onGame: async (stored, practice) => {
				stored.labelVersion = LABEL_VERSION; // freshly analyzed with the current ruleset
				await saveGame(stored);
				storedGames = [stored, ...storedGames].sort(
					(a, b) => Date.parse(b.endedAt) - Date.parse(a.endedAt)
				);
				let added = 0;
				for (const p of practice) {
					if (practiceItems.length >= PRACTICE_CAP) break;
					if (p.drop < collectThreshold) continue;
					const next = addItem(practiceItems, {
						...p,
						motifs: motifTags(p.fen, p.bestUci, p.bestPv ?? [p.bestUci], p.mateBest)
					});
					if (next) {
						practiceItems = next;
						added++;
					}
				}
				return added;
			}
		});
		void ccHandle.finished.then(() => (ccHandle = null));
	}

	function cancelCcImport() {
		ccHandle?.cancel();
	}

	// game archive + review
	let storedGames: StoredGame[] = $state([]);
	let reviewGame: StoredGame | null = $state(null);
	let reviewPly = $state(0);
	let gameSaved = false; // current game already archived

	// White-POV win chance per stored move, for the review win-chance chart
	const reviewWcPoints = $derived.by(() => {
		const g = reviewGame;
		if (!g || g.moves.length <= 1) return [];
		return g.moves.map((m) => ({
			ply: m.ply,
			wcWhite: whitePovWinChance(m.color, m.evalPawns, m.mate),
			label: m.label,
			san: m.san
		}));
	});

	// bot opponent
	const BOT_KEY = 'botvinnik-bot-v1';
	let botEnabled = $state(false);
	let botColor: 'w' | 'b' = $state('b'); // side the bot plays
	let botElo = $state(1500); // custom-mode slider (app-internal WASM scale)
	let botHuman = $state(false); // custom mode: human-like (Maia) in the 1100–1900 band
	let botPersonaId: string | null = $state('square-1000'); // roster bot; null = custom slider
	let botThinking = $state(false);
	let botConsidering: string | null = $state(null); // uci the bot is eyeing right now
	// true once ANY move this game came from the Stockfish stand-in rather than
	// the persona's own engine (net failed to load, worker died…) — shown in the
	// panel and recorded on the saved game so those results can be excluded
	let botFellBack = $state(false);
	let botSettingsLoaded = false;
	const botPersona: BotPersona | null = $derived(personaById(botPersonaId));
	// player rating fit from persona-game results (display scale, bots fixed)
	const playerEloEstimate = $derived(estimatePlayerElo(storedGames));
	// per-game seed for the shaped bot's sticky tactic-misses (what it doesn't
	// see this game, it keeps not seeing); re-rolled on every board reset
	let botGameSeed = $state(`s${Math.floor(Math.random() * 1e9)}`);
	// a dala net is downloading (Rust emits start/done around the fetch) —
	// shown as "downloading…" in the panel instead of a mute stall
	let botDownloading = $state(false);
	// takebacks used against the bot this game — an assisted result is real
	// practice but not a clean measurement (chess.com's crowns distinction),
	// so it's recorded on the game and excluded from the rating fit
	let botUndos = $state(0);
	$effect(() => onDalaDownload((active) => (botDownloading = active)));

	$effect(() => {
		practiceItems = loadItems();
		const t = Number(localStorage.getItem(THRESHOLD_KEY));
		if (t >= 5 && t <= 50) collectThreshold = t;
		try {
			const bot = JSON.parse(localStorage.getItem(BOT_KEY) ?? 'null');
			if (bot) {
				botEnabled = !!bot.enabled;
				botColor = bot.color === 'w' ? 'w' : 'b';
				// clamp legacy stored values into this substrate's calibrated range
				// (the old slider went to 3600; the honest ceiling is now botEloMax)
				if (typeof bot.elo === 'number' && bot.elo >= 100)
					botElo = Math.max(botEloMin(), Math.min(botEloMax(), bot.elo));
				botHuman = !!bot.human;
				// personaId absent in legacy settings ⇒ they were using the slider
				botPersonaId =
					'personaId' in bot && personaById(bot.personaId) ? bot.personaId : null;
			}
		} catch {
			// ignore malformed settings
		}
		drill = localStorage.getItem('botvinnik-practice-drill') === 'blundercheck' ? 'blundercheck' : 'find-best';
		easeIn = localStorage.getItem('botvinnik-practice-easein') !== '0';
		blindMode = localStorage.getItem('botvinnik-blind') === '1';
		showThreats = localStorage.getItem('botvinnik-threats') !== '0';
		showControl = localStorage.getItem('botvinnik-control') === '1';
		botSettingsLoaded = true;
		// re-verify stored prose + accuracies against current code BEFORE handing
		// the games to $state (plain objects → safe IDB puts)
		void listGames().then(async (g) => {
			await sanitizeStoredGames(g);
			storedGames = g;
		});
	});

	$effect(() => {
		const on = blindMode;
		if (botSettingsLoaded) localStorage.setItem('botvinnik-blind', on ? '1' : '0');
	});

	$effect(() => {
		const on = showThreats;
		if (botSettingsLoaded) localStorage.setItem('botvinnik-threats', on ? '1' : '0');
		if (!on) threat = null;
	});

	$effect(() => {
		const on = showControl;
		if (botSettingsLoaded) localStorage.setItem('botvinnik-control', on ? '1' : '0');
	});


	$effect(() => {
		const settings = {
			enabled: botEnabled,
			color: botColor,
			elo: botElo,
			human: botHuman,
			personaId: botPersonaId
		};
		if (botSettingsLoaded) localStorage.setItem(BOT_KEY, JSON.stringify(settings));
	});

	// warm the Maia net / retro wasm ahead of the first move
	$effect(() => {
		if (!botEnabled) return;
		if (botPersona?.maiaBand) preloadMaia(botPersona.maiaBand);
		else if (botPersona?.retro) preloadRetro(botPersona.retro);
		else if (botPersona?.dalaBand) preloadDala(botPersona.dalaBand);
		else if (botPersona?.garboMs) preloadGarbo();
		else if (!botPersona && botHuman && inMaiaRange(botElo)) preloadMaia(botElo);
	});

	function setCollectThreshold(n: number) {
		collectThreshold = n;
		localStorage.setItem(THRESHOLD_KEY, String(n));
	}

	function maybeCollect(g: MoveGrade, minDepth = 16) {
		if (mode !== 'play' || !g.backfilled || g.depth < minDepth || collectedPlies.has(g.ply)) return;
		if (botEnabled && g.color === botColor) return; // only collect the human's mistakes
		const wcBest = winChance(g.bestEval, g.bestMate);
		const drop = wcBest - winChance(g.evalPawns, g.mate);
		if (drop < collectThreshold) return;
		collectedPlies = new Set([...collectedPlies, g.ply]);
		const next = addItem(practiceItems, {
			fen: g.fenBefore,
			playedSan: g.san,
			playedUci: g.uci,
			bestSan: g.bestSan,
			bestUci: g.bestUci,
			bestPv: g.bestPv,
			setupUci: moveHistory.find((h) => h.ply === g.ply - 1)?.uci ?? enPassantSetup(g.fenBefore) ?? undefined,
			motifs: motifTags(g.fenBefore, g.bestUci, g.bestPv ?? [g.bestUci], g.bestMate),
			evalBestPawns: g.bestEval,
			mateBest: g.bestMate,
			wcBest,
			drop,
			depth: g.depth
		});
		if (next) practiceItems = next;
	}

	function recordGrade(uci: string, san: string, color: 'w' | 'b', fenBefore: string, lines: EngineMove[]) {
		// the previous move will never be backfilled again — collect it now if
		// its search got at least somewhat deep (covers fast play)
		const prev = moveHistory.at(-1);
		if (prev) maybeCollect(prev, 8);
		const grade = gradeMove(game.moves.length, fenBefore, san, uci, color, lines);
		if (grade) moveHistory = [...moveHistory, grade];
	}

	// refine the last move's grade from the search of the position it created
	function backfillLast(childLines: EngineMove[]) {
		const last = moveHistory.at(-1);
		if (!last || last.ply !== game.moves.length) return;
		const updated = backfillGrade(last, childLines);
		moveHistory = [...moveHistory.slice(0, -1), updated];
		maybeCollect(updated);
	}

	function refresh() {
		game = getState();
	}

	let analysisToken = 0;

	async function runAnalysis() {
		if (mode === 'practice') return;
		const token = ++analysisToken;
		stopEngine();
		if (game.isGameOver) {
			engineMoves = [];
			analyzing = false;
			return;
		}
		analyzing = true;
		engineMoves = [];
		const budget = getAnalysisBudget();
		await analyze(
			game.fen,
			budget.depth,
			(moves) => {
				if (token === analysisToken) {
					engineMoves = moves;
					backfillLast(moves);
				}
			},
			budget.movetimeMs
		);
		if (token === analysisToken) {
			analyzing = false;
			maybeBotMove(token);
			void computeThreat(token, game.fen);
		}
	}

	// after the main analysis settles, probe what the opponent threatens (a
	// null-move search) on the same engine. NEVER when the bot is about to
	// reply: the engine is a single-slot supersede queue, so the probe would
	// `stop` the bot's strength-limited search a few ms in and wreck its ELO
	// calibration — and the position is transient anyway; the probe runs once
	// the bot has moved and that analysis settles.
	async function computeThreat(token: number, fen: string) {
		if (!showThreats || blindMode || (mode !== 'play' && mode !== 'review')) {
			threat = null;
			return;
		}
		if (botEnabled && mode === 'play' && !game.isGameOver && game.turn === botColor) return;
		const t = await findThreat(fen, analyze, { depth: 14, movetimeMs: 500 });
		if (token === analysisToken) threat = t;
	}

	// pick the bot's reply with a dedicated strength-limited search (runs
	// concurrently with the thinking delay); softmax over the full-strength
	// lines is the fallback if that search yields nothing
	// the game's FENs oldest-first, for Maia's history planes (chess.js moves
	// carry before/after FENs, so no replay needed)
	function maiaFenHistory(): string[] {
		const ms = game.moves;
		return ms.length === 0 ? [game.fen] : [ms[0].before, ...ms.map((m) => m.after)];
	}

	// the Stockfish path: strength-limited search, then sample per the band spec
	async function stockfishBotMove(elo: number = botElo): Promise<string | null> {
		const res = await analyzeBotMove(game.fen, elo, (moves) => {
			botConsidering = moves[0]?.pv[0] ?? null;
		});
		botConsidering = null;
		const spec = botSpec(elo);
		const specAlpha = spec.kind === 'sampler' ? spec.alpha : undefined;
		return spec.kind === 'sampler' && res.moves.length > 0
			? selectBotMove(res.moves, elo, spec.alpha)
			: res.bestmove && res.bestmove !== '(none)'
				? res.bestmove
				: selectBotMove(engineMoves, elo, specAlpha);
	}

	// the shaped path (Squares): full-strength wide search at the label's
	// calibrated depth, then the miss-the-tactic choice layer with this game's
	// sticky-miss seed
	async function shapedAppMove(label: number): Promise<string | null> {
		const res = await analyzeShapedMove(game.fen, shapedSearchDepth(label), (moves) => {
			botConsidering = moves[0]?.pv[0] ?? null;
		});
		botConsidering = null;
		return shapedBotMove(res.moves, label, undefined, botGameSeed);
	}

	async function maybeBotMove(token: number) {
		if (!botEnabled || mode !== 'play' || game.isGameOver || game.turn !== botColor) return;
		botThinking = true;
		// roster personas bind the mechanism directly; custom mode keeps the old
		// slider behavior (Maia toggle in its band, else numeric Stockfish).
		// Maia falls back to Stockfish at the persona's strength if its net
		// can't load.
		const p = botPersona;
		// engines that can fail to produce a move (net not loaded, worker down)
		// fall back to Stockfish at the persona's strength
		const fallible = p
			? !!p.maiaBand || !!p.retro || !!p.dalaBand || !!p.jsceLevel || !!p.garboMs
			: botHuman && inMaiaRange(botElo);
		// square labels resolve at MOVE time, not roster-build time: the label
		// depends on the active substrate's measured curve (web wasm vs the
		// desktop big-net sidecar), and the substrate flips after module load
		const compute = p?.shapedLabel
			? shapedAppMove(shapedLabelFor(personaInternalElo(p)))
			: p?.retro
				? retroMove(game.fen, p.retro).catch(() => null)
				: p?.jsceLevel
					? jsceMove(game.fen, p.jsceLevel).catch(() => null)
					: p?.garboMs
						? garboMove(game.fen, p.garboMs).catch(() => null)
				: p?.dalaBand
					? dalaMove(game.fen, p.dalaBand).catch(() => null)
					: p?.maiaBand
						? maiaMove(maiaFenHistory(), p.maiaBand, p.maiaTemp ?? 0).catch(() => null)
						: p
							? stockfishBotMove(personaInternalElo(p))
							: fallible
								? maiaMove(maiaFenHistory(), botElo).catch(() => null)
								: stockfishBotMove();
		const [primary] = await Promise.all([compute, new Promise((r) => setTimeout(r, botDelay()))]);
		let uci = primary;
		if (fallible && !uci) {
			uci = await stockfishBotMove(p ? personaInternalElo(p) : botElo);
			botFellBack = true; // surface it — a silent stand-in corrupts the rating fit
		}
		botThinking = false;
		botConsidering = null;
		if (token !== analysisToken || !botEnabled || mode !== 'play') return;
		if (game.isGameOver || game.turn !== botColor) return;
		if (uci) applyUci(uci);
	}

	// kick the bot when it's enabled (or switched sides) mid-position
	$effect(() => {
		botEnabled;
		botColor;
		untrack(() => {
			if (botEnabled && !analyzing && !botThinking) maybeBotMove(analysisToken);
		});
	});

	function handleMove(from: string, to: string) {
		if (mode === 'review') return; // review board is read-only
		if (mode === 'play' && botEnabled && game.turn === botColor) return; // bot's turn
		if (isPromotionMove(from, to)) {
			pendingPromotion = { from, to };
			return;
		}
		completeMove(from, to, undefined);
	}

	function completeMove(from: string, to: string, promotion: string | undefined) {
		if (mode === 'practice') {
			practiceAttempt(from, to, promotion);
			return;
		}
		const fenBefore = game.fen;
		const linesBefore = engineMoves;
		const sansBefore = playedSans;
		const move = makeMove(from, to, promotion);
		if (move) {
			lastMove = [from, to];
			refresh();
			recordGrade(from + to + (move.promotion ?? ''), move.san, move.color, fenBefore, linesBefore);
			if (game.isGameOver) void saveCurrentGame();
			runAnalysis();
		}
	}

	function choosePromotion(piece: string | null) {
		const pending = pendingPromotion;
		pendingPromotion = null;
		if (!pending) return;
		if (piece) completeMove(pending.from, pending.to, piece);
		else boardResetKey++; // cancelled — snap the dragged pawn back
	}

	// ---- practice mode ----

	async function loadPuzzle(item: PracticeItem, forceDrill?: 'find-best' | 'blundercheck') {
		const token = ++puzzleToken;
		currentItem = item;
		lineDepth = 0;
		attempt = null;
		attemptGrade = null;
		lineNote = null;
		revealBest = false;
		hintTier = 0;

		// Blundercheck: set up the position AFTER the played mistake and make the
		// opponent's best reply (the punishment) the target — the whole grade /
		// hint / explain / spaced-rep path then works unchanged, just from the
		// defensive side. Needs a live search for the refutation (not stored).
		if ((forceDrill ?? drill) === 'blundercheck') {
			const afterFen = getFenAfter(item.fen, item.playedUci);
			if (afterFen) {
				blundercheckActive = true;
				practiceRef = null;
				puzzleLoading = true;
				// show the position BEFORE your mistake (opponent's setup highlighted)…
				loadFen(item.fen);
				const setup = puzzleSetupMove(item);
				lastMove = setup ? [setup.slice(0, 2), setup.slice(2, 4)] : null;
				refresh();
				const searchP = analyze(afterFen, 16, () => {}); // find the punishment meanwhile
				// …then animate YOUR mistake sliding into place, so you SEE what you played
				await new Promise((r) => setTimeout(r, 550));
				if (token !== puzzleToken) return; // a newer puzzle superseded this load
				const pm = makeMove(
					item.playedUci.slice(0, 2),
					item.playedUci.slice(2, 4),
					item.playedUci.length > 4 ? item.playedUci[4] : undefined
				);
				if (pm) {
					lastMove = [pm.from, pm.to];
					refresh();
				}
				const res = await searchP;
				if (token !== puzzleToken) return;
				puzzleLoading = false;
				const top = res.moves[0];
				if (pm && top?.pv[0]) {
					practiceRef = {
						fen: afterFen,
						bestUci: top.pv[0],
						bestSan: getSan(afterFen, top.pv[0]),
						evalBest: top.mate === null ? top.score : top.mate > 0 ? 15 : -15,
						mateBest: top.mate,
						wcBest: winChance(top.mate === null ? top.score : null, top.mate),
						bestPv: top.pv,
						depth: top.depth
					};
					return;
				}
				// no usable reply / illegal replay — fall through to the classic puzzle
			}
			blundercheckActive = false;
		} else {
			blundercheckActive = false;
		}

		practiceRef = {
			fen: item.fen,
			bestUci: item.bestUci,
			bestSan: item.bestSan,
			evalBest: item.evalBestPawns,
			mateBest: item.mateBest,
			wcBest: item.wcBest,
			bestPv: item.bestPv ?? [item.bestUci],
			depth: item.depth
		};
		loadFen(item.fen);
		// replay the opponent's last move so the setup is visible — essential for
		// en-passant puzzles, where the legal capture is otherwise unknowable
		const setup = puzzleSetupMove(item);
		lastMove = setup ? [setup.slice(0, 2), setup.slice(2, 4)] : null;
		refresh();
	}

	function setDrill(d: 'find-best' | 'blundercheck') {
		if (d === drill) return;
		drill = d;
		if (botSettingsLoaded) localStorage.setItem('botvinnik-practice-drill', d);
		if (mode === 'practice' && currentItem) void loadPuzzle(currentItem);
	}

	// after nailing the punishment, drop into the classic puzzle on the SAME
	// position: "now find the move you should have played instead"
	function learnBest() {
		if (currentItem) void loadPuzzle(currentItem, 'find-best');
	}

	function startPractice() {
		const item = nextItem(practiceItems, undefined, undefined, practiceMotif ?? undefined, Math.random, easeIn);
		if (!item) return;
		sessionSolved = 0;
		sessionStreak = 0;
		analysisToken++; // orphan any in-flight play analysis
		stopEngine();
		analyzing = false;
		engineMoves = [];
		mode = 'practice';
		sideView = 'practice';
		loadPuzzle(item);
	}

	function exitPractice() {
		mode = 'play';
		sideView = 'play';
		currentItem = null;
		practiceRef = null;
		attempt = null;
		attemptGrade = null;
		lineNote = null;
		revealBest = false;
		handleReset();
	}

	async function practiceAttempt(from: string, to: string, promotion?: string) {
		const ref = practiceRef;
		if (!currentItem || !ref || attempt || grading || continuing || puzzleLoading) return;
		const move = makeMove(from, to, promotion);
		if (!move) return;
		lastMove = [from, to];
		refresh();
		const uci = from + to + (move.promotion ?? '');

		let evalPawns: number | null;
		let mate: number | null;
		let depth = ref.depth;
		let refutationPv: string[] = [];
		if (uci === ref.bestUci) {
			evalPawns = ref.evalBest;
			mate = ref.mateBest;
		} else {
			grading = true;
			const res = await analyzeMove(ref.fen, uci, 14);
			grading = false;
			evalPawns = res.moves[0]?.score ?? null;
			mate = res.moves[0]?.mate ?? null;
			depth = res.moves[0]?.depth ?? 14;
			refutationPv = res.moves[0]?.pv.slice(1) ?? [];
			if (evalPawns === null && mate === null) {
				// grading got superseded somehow — reset the puzzle rather than guess
				retryPuzzle();
				return;
			}
		}
		const drop = ref.wcBest - winChance(evalPawns, mate);
		const pass = drop < PASS_DROP; // strict: drop = 5 is already an inaccuracy
		const isBest = uci === ref.bestUci;
		const explanation = pass
			? {}
			: explainMove({
					fenBefore: ref.fen,
					playedUci: uci,
					refutationPv,
					bestUci: ref.bestUci,
					bestPv: ref.bestPv,
					playedMate: mate,
					bestMate: ref.mateBest,
					isBest: false
				});
		const refutationUci = refutationPv[0] ?? null;
		const goodPoint = pass
			? explainGoodMove(ref.fen, uci, isBest ? ref.bestPv : [uci, ...refutationPv], mate)
			: undefined;
		const evidence = explanation.evidence ?? goodPoint?.evidence;
		attemptGrade = buildAttemptGrade(ref, move.san, uci, evalPawns, mate, depth, drop, {
			playedIssue: explanation.playedIssue,
			bestPoint: explanation.bestPoint,
			playedPoint: goodPoint?.text,
			lineStory: explanation.lineStory,
			evidence
		});
		attempt = {
			san: move.san,
			pass,
			label: attemptGrade.label,
			drop,
			evalPawns,
			mate,
			refutationUci: pass ? null : refutationUci,
			refutationSan: !pass && refutationUci ? getSan(game.fen, refutationUci) : null,
			playedIssue: explanation.playedIssue,
			bestPoint: explanation.bestPoint,
			playedPoint: goodPoint?.text,
			lineStory: explanation.lineStory,
			evidence
		};
		// only the stored puzzle counts toward spaced repetition, not line continuations;
		// a hinted pass holds its box rather than promoting
		if (lineDepth === 0) {
			practiceItems = recordResult(practiceItems, currentItem.id, pass, hintTier > 0);
			// session progress: solves count passes; the streak is COLD passes only
			if (pass) {
				sessionSolved++;
				sessionStreak = hintTier > 0 ? 0 : sessionStreak + 1;
			} else {
				sessionStreak = 0;
			}
		}
	}

	// an InsightsPanel-compatible grade for a practice attempt; pctBest is the
	// same τ=100cp softmax ratio the play-mode grades use, over the two evals
	function buildAttemptGrade(
		ref: PracticeRef,
		san: string,
		uci: string,
		evalPawns: number | null,
		mate: number | null,
		depth: number,
		drop: number,
		explanation: Explanation
	): MoveGrade {
		const cpOf = (pawns: number | null, m: number | null) =>
			m !== null ? (m > 0 ? 9999 : -9999) : (pawns ?? 0) * 100;
		const isBest = uci === ref.bestUci;
		const pctBest = isBest
			? 100
			: Math.min(100, Math.exp((cpOf(evalPawns, mate) - cpOf(ref.evalBest, ref.mateBest)) / 100) * 100);
		let label: MoveLabel;
		if (isBest) label = 'best';
		else if (drop >= 20) label = 'blunder';
		else if (drop >= 10) label = 'mistake';
		else if (drop >= 5) label = 'inaccuracy';
		else label = drop <= 2 ? 'excellent' : 'good';
		const hasExplanation =
			explanation.playedIssue ||
			explanation.bestPoint ||
			explanation.playedPoint ||
			explanation.lineStory;
		return {
			ply: 0,
			fenBefore: ref.fen,
			san,
			uci,
			color: ref.fen.split(' ')[1] === 'b' ? 'b' : 'w',
			depth,
			rank: isBest ? 1 : null,
			evalPawns,
			mate,
			pctBest,
			isBest,
			bestSan: ref.bestSan,
			bestUci: ref.bestUci,
			bestEval: ref.evalBest,
			bestMate: ref.mateBest,
			totalLines: 0,
			offList: false,
			backfilled: true,
			preLines: [],
			bestPv: ref.bestPv,
			explanation: hasExplanation ? explanation : undefined,
			label
		};
	}

	// play the engine's reply to the attempt, turning the position one move
	// later into a fresh (temporary) puzzle
	async function continueLine() {
		if (!attempt || continuing || grading || mode !== 'practice') return;
		continuing = true;
		attempt = null;
		attemptGrade = null;
		revealBest = false;
		hintTier = 0;
		try {
			const replyRes = await analyze(game.fen, 14, () => {});
			const reply = replyRes.moves[0]?.pv[0];
			if (!reply) return;
			const m = makeMove(reply.slice(0, 2), reply.slice(2, 4), reply.length > 4 ? reply[4] : undefined);
			if (!m) return;
			lastMove = [reply.slice(0, 2), reply.slice(2, 4)];
			refresh();
			lineDepth++;
			if (game.isGameOver) {
				practiceRef = null;
				lineNote = `Line over after ${m.san} — ${game.result}.`;
				return;
			}
			const posRes = await analyze(game.fen, 14, () => {});
			const best = posRes.moves[0];
			if (!best) {
				practiceRef = null;
				return;
			}
			practiceRef = {
				fen: game.fen,
				bestUci: best.pv[0],
				bestSan: getSan(game.fen, best.pv[0]),
				evalBest: best.score,
				mateBest: best.mate,
				wcBest: winChance(best.mate !== null ? null : best.score, best.mate),
				bestPv: best.pv,
				depth: best.depth
			};
		} finally {
			continuing = false;
		}
	}

	function nextPuzzle() {
		const item = nextItem(practiceItems, currentItem?.id, undefined, practiceMotif ?? undefined, Math.random, easeIn);
		if (item) loadPuzzle(item);
		else {
			currentItem = null;
			practiceRef = null;
			attempt = null;
			attemptGrade = null;
			lineNote = null;
			hintTier = 0;
		}
	}

	// tiered hints: click 1 shows text, 2 circles the origin square, 3 reveals
	function practiceHint() {
		if (hintTier >= 2) revealBest = true; // tier 3 reuses the existing reveal
		hintTier++;
	}

	function retryPuzzle() {
		if (!practiceRef) return;
		loadFen(practiceRef.fen);
		// keep the played move on the board as context in a blundercheck drill
		lastMove =
			blundercheckActive && currentItem
				? [currentItem.playedUci.slice(0, 2), currentItem.playedUci.slice(2, 4)]
				: null;
		attempt = null;
		attemptGrade = null;
		revealBest = false;
		hintTier = 0;
		refresh();
	}

	function removePracticeItem(id: string) {
		practiceItems = removeItem(practiceItems, id);
		if (currentItem?.id === id) nextPuzzle();
	}

	// ---- game review ----

	function practiceFromReview(move: StoredMove) {
		// the opponent's move that set up this position (the ply before the mistake)
		const prev = reviewGame?.moves[move.ply - 2]?.uci;
		const data = itemDataFromStoredMove(move, prev);
		if (!data) return;
		const next = addItem(practiceItems, data);
		if (next) practiceItems = next;
	}

	function openReview(g: StoredGame) {
		if (mode === 'play' && !gameSaved && game.moves.length >= 10) void saveCurrentGame();
		analysisToken++; // orphan any in-flight analysis
		stopEngine();
		analyzing = false;
		engineMoves = [];
		mode = 'review';
		sideView = 'review';
		reviewGame = g;
		gotoReviewPly(g.moves.length);
	}

	function gotoReviewPly(ply: number) {
		if (!reviewGame) return;
		reviewPly = Math.max(0, Math.min(reviewGame.moves.length, ply));
		const fen =
			reviewPly === 0 ? reviewGame.moves[0].fenBefore : reviewGame.moves[reviewPly - 1].fenAfter;
		loadFen(fen);
		const m = reviewPly > 0 ? reviewGame.moves[reviewPly - 1] : null;
		lastMove = m ? [m.uci.slice(0, 2), m.uci.slice(2, 4)] : null;
		refresh();
		runAnalysis(); // live (cache-assisted) analysis of the reviewed position
	}

	function exitReview() {
		mode = 'play';
		reviewGame = null;
		handleReset();
	}

	function exportPgn(g: StoredGame) {
		if (!g.pgn) return;
		const seg = (s: string) => s.replace(/[^A-Za-z0-9_-]/g, '');
		const name = `botvinnik-${seg(g.white ?? 'game')}-vs-${seg(g.black ?? 'bot')}-${seg(g.endedAt.slice(0, 10))}.pgn`;
		const blob = new Blob([g.pgn], { type: 'application/x-chess-pgn' });
		const a = document.createElement('a');
		a.href = URL.createObjectURL(blob);
		a.download = name;
		document.body.appendChild(a); // detached-anchor clicks are ignored in some browsers
		a.click();
		a.remove();
		URL.revokeObjectURL(a.href);
	}

	function deleteStoredGame(id: string) {
		void deleteGame(id);
		storedGames = storedGames.filter((g) => g.id !== id);
		if (reviewGame?.id === id) exitReview();
	}

	// board helpers for practice mode
	const boardOrientation: 'white' | 'black' = $derived.by(() => {
		// pin to the puzzle's side to move — game.turn flips after the attempt
		if (mode === 'practice') return currentItem?.fen.split(' ')[1] === 'b' ? 'black' : 'white';
		if (mode === 'review') return reviewGame?.botColor === 'w' ? 'black' : 'white';
		if (botEnabled) return botColor === 'w' ? 'black' : 'white'; // human's side up
		return 'white';
	});
	// material strips: bottom = side facing the viewer, top = opponent
	const bottomColor: 'w' | 'b' = $derived(boardOrientation === 'white' ? 'w' : 'b');
	const topColor: 'w' | 'b' = $derived(boardOrientation === 'white' ? 'b' : 'w');
	const boardLegalMoves = $derived.by(() => {
		if (mode === 'review') return []; // read-only
		if (pendingPromotion) return []; // waiting on the piece choice
		if (mode === 'practice' && (attempt || grading || continuing || !practiceRef)) return []; // answered/waiting — lock the board
		if (botEnabled && mode === 'play' && game.turn === botColor) return [];
		return game.legalMoves;
	});
	const boardArrows: EngineMove[] = $derived.by(() => {
		if (mode === 'practice') {
			return revealBest && practiceRef
				? [{ pv: [practiceRef.bestUci], score: 0, mate: null, depth: 0, multipv: 1 }]
				: [];
		}
		if (blindMode) return [];
		return showArrows ? topMoves : [];
	});
	// the opponent's threat (null-move probe), drawn as a warning arrow; gated
	// on the fen it was computed for, so a stale arrow never survives a move
	const threatArrow = $derived.by(() => {
		if (!showThreats || blindMode || mode === 'practice') return null;
		return threat && threat.fen === game.fen ? threat.uci : null;
	});
	// square-control tint — pure chess.js, recomputed per position
	const controlMap = $derived.by(() => {
		if (!showControl || blindMode || mode === 'practice') return null;
		return computeControl(game.fen);
	});
	// hints the panels/tree see — blanked in blind mode so nothing leaks
	const visibleLines = $derived(blindMode && mode === 'play' ? [] : engineMoves);

	// The tree always ingests live lines so its map accumulates each position's
	// alternatives; in blind mode LinesTree hides everything anchored at the
	// CURRENT position instead (hideCurrent), so past possibility space stays
	// visible without hinting at the move to make now.
	const treeView = $derived({ fen: game.fen, sans: playedSans, lines: engineMoves });

	function applyUci(uci: string) {
		const fenBefore = game.fen;
		const linesBefore = engineMoves;
		const sansBefore = playedSans;
		const move = makeMove(uci.slice(0, 2), uci.slice(2, 4), uci.length > 4 ? uci[4] : undefined);
		if (move) {
			lastMove = [move.from, move.to];
			refresh();
			recordGrade(uci, move.san, move.color, fenBefore, linesBefore);
			if (game.isGameOver) void saveCurrentGame();
			runAnalysis();
		}
	}

	function handlePlayUci(uci: string) {
		if (botEnabled && game.turn === botColor) return; // bot's turn
		applyUci(uci);
	}

	// archive the current game with its per-move grades
	async function saveCurrentGame(resultOverride?: string) {
		const moves = game.moves;
		if (moves.length === 0 || gameSaved) return;
		gameSaved = true;
		const grades = new Map(moveHistory.map((g) => [g.ply, g]));
		const stored: StoredMove[] = moves.map((m, i) => {
			const g = grades.get(i + 1);
			const wcDrop = g
				? Math.max(0, winChance(g.bestEval, g.bestMate) - winChance(g.evalPawns, g.mate))
				: 0;
			return {
				ply: i + 1,
				san: m.san,
				uci: m.from + m.to + (m.promotion ?? ''),
				color: m.color,
				fenBefore: m.before,
				fenAfter: m.after,
				evalPawns: g?.evalPawns ?? null,
				mate: g?.mate ?? null,
				pctBest: g?.pctBest ?? null,
				wcDrop,
				label: g?.label,
				bestSan: g?.bestSan,
				bestUci: g?.bestUci,
				explanation: g?.explanation
			};
		});
		const result = resultOverride ?? game.result ?? '*';
		const youAre = botEnabled ? (botColor === 'w' ? 'Black' : 'White') : null;
		const botName = botEnabled
			? botPersona
				? `${botPersona.name} (${botPersona.elo})`
				: `Bot (${botElo})`
			: 'Analysis';
		const record: StoredGame = {
			id: `g-${Date.now()}-${moves.length}`,
			endedAt: new Date().toISOString(),
			result,
			pgn: getPgn({
				White: youAre === 'White' ? 'You' : botEnabled ? botName : 'White',
				Black: youAre === 'Black' ? 'You' : botEnabled ? botName : 'Black',
				Date: new Date().toISOString().slice(0, 10).replaceAll('-', '.'),
				Result: result
			}),
			// always the app-internal WASM scale, persona or slider — one scale
			// for the future player-ELO fit over stored results
			botElo: botEnabled ? (botPersona ? personaInternalElo(botPersona) : botElo) : null,
			botPersona: botEnabled && botPersona ? botPersona.id : undefined,
			botFallback: botEnabled && botFellBack ? true : undefined,
			botUndos: botEnabled && botUndos > 0 ? botUndos : undefined,
			botColor: botEnabled ? botColor : null,
			moveCount: moves.length,
			whiteAccuracy: gameAccuracy(stored, 'w'),
			blackAccuracy: gameAccuracy(stored, 'b'),
			labelCounts: { w: labelCounts(stored, 'w'), b: labelCounts(stored, 'b') },
			labelVersion: LABEL_VERSION,
			moves: stored
		};
		// strip $state proxies — IndexedDB's structured clone rejects them
		const plain = $state.snapshot(record) as StoredGame;
		await saveGame(plain);
		storedGames = [plain, ...storedGames];
	}

	function handleUndo() {
		if (!undo()) return;
		gameSaved = false; // game continues — allow re-archiving at its new end
		if (mode === 'play' && botEnabled) botUndos++;
		// vs the bot, take back its reply too so it's your turn again
		if (botEnabled && getState().turn === botColor) undo();
		const last = getState().moves.at(-1);
		lastMove = last ? [last.from, last.to] : null;
		refresh();
		moveHistory = moveHistory.filter((g) => g.ply <= game.moves.length);
		runAnalysis();
	}

	function handleReset() {
		// archive abandoned games of meaningful length before wiping them
		if (mode === 'play' && !gameSaved && game.moves.length >= 10) void saveCurrentGame();
		reset();
		botGameSeed = `s${Math.floor(Math.random() * 1e9)}`; // fresh eyes for the shaped bot
		botFellBack = false;
		botUndos = 0;
		gameSaved = false;
		lastMove = null;
		refresh();
		moveHistory = [];
		collectedPlies = new Set();
		runAnalysis();
	}

	async function handleResign() {
		// bot game: the human resigns; solo game: the side to move resigns
		const loser = botEnabled ? (botColor === 'w' ? 'b' : 'w') : game.turn;
		await saveCurrentGame(loser === 'w' ? '0-1' : '1-0');
		// gameSaved is now true, so handleReset's save guard is a no-op — reuse its reset
		handleReset();
	}

	function handleKeydown(e: KeyboardEvent) {
		const tag = (e.target as HTMLElement)?.tagName;
		if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
		if (e.metaKey || e.ctrlKey || e.altKey) return;
		if (mode === 'practice') {
			if (e.key === 'n' && !grading && !continuing) {
				e.preventDefault();
				nextPuzzle();
			} else if (e.key === 'r' && attempt && !attempt.pass) {
				e.preventDefault();
				retryPuzzle();
			}
		} else if (mode === 'review') {
			if (e.key === 'ArrowLeft') {
				e.preventDefault();
				gotoReviewPly(reviewPly - 1);
			} else if (e.key === 'ArrowRight') {
				e.preventDefault();
				gotoReviewPly(reviewPly + 1);
			} else if (e.key === 'Escape') {
				e.preventDefault();
				exitReview();
			}
		} else if (e.key === 'ArrowLeft') {
			e.preventDefault();
			handleUndo();
		}
	}

	// analysis runs are explicit (every mutation path calls runAnalysis);
	// a reactive effect here would re-fire on refresh() and supersede
	// practice-mode searchmoves grading
	onMount(() => {
		runAnalysis();
	});
</script>

<svelte:window bind:innerHeight={viewportH} bind:innerWidth={viewportW} onkeydown={handleKeydown} />

<div class="app" class:narrow={isNarrow}>
	<h1 class="title">Botvinnik</h1>

	<div class="main">
		<div class="board-col" style:width="{boardSize}px">
			<MaterialBar fen={game.fen} color={topColor} />
			<Board
				fen={game.fen}
				turn={game.turn}
				legalMoves={boardLegalMoves}
				orientation={boardOrientation}
				engineMoves={boardArrows}
				botArrow={botThinking ? botConsidering : null}
				threatArrow={threatArrow}
				control={controlMap}
				refutationArrow={mode === 'practice' && attempt && !attempt.pass ? (attempt.refutationUci ?? null) : null}
				hintSquare={mode === 'practice' && hintTier >= 2 && !attempt && practiceRef
					? practiceRef.bestUci.slice(0, 2)
					: null}
				resetKey={boardResetKey}
				{lastMove}
				size={boardSize}
				boundsKey={panelsHidden}
				onmove={handleMove}
			/>
			<MaterialBar fen={game.fen} color={bottomColor} />
			{#if !isNarrow && mode === 'play'}
				<!-- the board toggles live with the board they modify -->
				<div class="quick-toggles under-board">
					{@render toggleRow()}
				</div>
			{/if}
		</div>

		{#if pendingPromotion}
			{@const promoGlyphs =
				game.turn === 'w'
					? [['q', '♕'], ['r', '♖'], ['b', '♗'], ['n', '♘']]
					: [['q', '♛'], ['r', '♜'], ['b', '♝'], ['n', '♞']]}
			<div class="promo-overlay" role="dialog" aria-label="Choose promotion piece">
				<div class="promo-box">
					{#each promoGlyphs as [piece, glyph] (piece)}
						<button class="promo-piece" onclick={() => choosePromotion(piece)}>{glyph}</button>
					{/each}
					<button class="promo-cancel" onclick={() => choosePromotion(null)}>×</button>
				</div>
			</div>
		{/if}

		<!-- panel bodies are declared once and rendered either in the desktop
		     sidebar or in the narrow layout's bottom-sheet tabs -->
		{#snippet insightsBody()}
			{#if mode === 'practice'}
				{#if attemptGrade && (attempt?.pass || revealBest)}
					<InsightsPanel
						white={attemptGrade.color === 'w' ? attemptGrade : null}
						black={attemptGrade.color === 'b' ? attemptGrade : null}
						orientation={boardOrientation}
					/>
				{/if}
			{:else}
				<InsightsPanel
					white={insightWhite}
					black={insightBlack}
					{collectedPlies}
					orientation={boardOrientation}
				/>
			{/if}
		{/snippet}

		{#snippet botBody()}
			<BotPanel
				bind:enabled={botEnabled}
				bind:color={botColor}
				bind:elo={botElo}
				minElo={botEloMin()}
				maxElo={botEloMax()}
				bind:human={botHuman}
				bind:personaId={botPersonaId}
				playerElo={playerEloEstimate}
				record={botPersonaId ? (personaRecords[botPersonaId] ?? null) : null}
				fellBack={botFellBack}
				downloading={botDownloading}
				thinking={botThinking}
				onchangebot={() => (rosterOpen = true)}
			/>
		{/snippet}

		<!-- the engine's top-3 with the full tree folded behind a toggle: one
		     Lines card instead of Engine Analysis + Lines Tree showing the same
		     data two ways -->
		{#snippet treeToggle()}
			<button class="tree-toggle" onclick={() => (treeOpen = !treeOpen)}>
				{treeOpen ? '▾ hide tree' : '▸ expand tree'}
			</button>
			{#if treeOpen}
				{@render linesBody()}
			{/if}
		{/snippet}

		{#snippet engineBody()}
			<AnalysisPanel
				moves={visibleLines.slice(0, 3)}
				fen={game.fen}
				{analyzing}
				orientation={boardOrientation}
				footer={treeToggle}
			/>
		{/snippet}

		{#snippet toggleRow()}
			<button
				class:on={showArrows && !blindMode}
				disabled={blindMode}
				onclick={() => (showArrows = !showArrows)}
				title="Draw the engine's top moves on the board"
			>
				Arrows
			</button>
			<button
				class:on={blindMode}
				onclick={() => (blindMode = !blindMode)}
				title="Hide engine hints until you've moved"
			>
				Blind
			</button>
			<button
				class:on={showThreats && !blindMode}
				disabled={blindMode}
				onclick={() => (showThreats = !showThreats)}
				title="Draw what your opponent threatens (a move that wins material or mates) in red"
			>
				Threats
			</button>
			<button
				class:on={showControl && !blindMode}
				disabled={blindMode}
				onclick={() => (showControl = !showControl)}
				title="Tint squares by who can safely use them: green = you'd win or hold the exchange there, red = they would"
			>
				Control
			</button>
		{/snippet}

		{#snippet movesBody()}
			<MoveList
				moves={game.moves}
				onundo={handleUndo}
				onresign={game.moves.length >= 2 && !game.isGameOver ? handleResign : undefined}
				onreset={handleReset}
				startOpen={isNarrow}
			/>
		{/snippet}

		{#snippet linesBody()}
			<LinesTree
				lines={treeView.lines}
				fen={treeView.fen}
				playedSans={treeView.sans}
				height={TREE_HEIGHT}
				hideCurrent={blindMode && mode === 'play'}
				onplay={blindMode ? undefined : handlePlayUci}
			/>
		{/snippet}

		{#snippet bookBody()}
			<UnifiedMovesPanel
				fen={game.fen}
				lines={visibleLines}
				blind={blindMode && mode === 'play'}
				onplay={blindMode ? undefined : handlePlayUci}
			/>
		{/snippet}

		{#snippet chartBody()}
			{#if mode === 'review'}
				{#if reviewGame && reviewGame.moves.length > 1}
					<WinChanceChart points={reviewWcPoints} currentPly={reviewPly} onselect={gotoReviewPly} />
				{/if}
			{:else}
				<WinChanceChart points={wcChartPoints} />
			{/if}
		{/snippet}

		{#snippet commentaryBody()}
			<CommentaryPanel entries={commentary} />
		{/snippet}

		{#snippet practiceBody()}
			<PracticePanel
				{mode}
				orientation={boardOrientation}
				items={practiceItems}
				current={currentItem}
				{attempt}
				{grading}
				{revealBest}
				{lineDepth}
				{lineNote}
				{continuing}
				{hintTier}
				{hint}
				{drill}
				blundercheck={blundercheckActive}
				loading={puzzleLoading}
				playedSan={currentItem?.playedSan ?? null}
				drop={currentItem?.drop ?? null}
				{easeIn}
				{sessionSolved}
				{sessionStreak}
				threshold={collectThreshold}
				motif={practiceMotif}
				onmotif={(m) => (practiceMotif = m)}
				oneasein={(on) => {
					easeIn = on;
					if (botSettingsLoaded) localStorage.setItem('botvinnik-practice-easein', on ? '1' : '0');
				}}
				ondrill={setDrill}
				onlearnbest={learnBest}
				onstart={startPractice}
				onexit={exitPractice}
				onnext={nextPuzzle}
				onretry={retryPuzzle}
				onreveal={() => (revealBest = true)}
				onhint={practiceHint}
				oncontinue={continueLine}
				onremove={removePracticeItem}
				onthreshold={setCollectThreshold}
			/>
		{/snippet}

		{#snippet gamesBody()}
			<GamesPanel
				games={storedGames}
				orientation={boardOrientation}
				reviewing={mode === 'review' ? reviewGame : null}
				{reviewPly}
				importing={lichessImporting}
				importStatus={lichessStatus}
				{ccImport}
				onreview={openReview}
				onclose={exitReview}
				ongoto={gotoReviewPly}
				ondelete={deleteStoredGame}
				onimport={handleLichessImport}
				onccimport={startCcImport}
				onccancel={cancelCcImport}
				onpractice={practiceFromReview}
				onexport={exportPgn}
			/>
		{/snippet}

		{#snippet gameOverNote()}
			{#if game.isGameOver}
				<div class="game-over">
					Game over: {game.result}
				</div>
			{/if}
		{/snippet}

		{#snippet dataRow()}
			<div class="data-row">
				<button onclick={() => void downloadBackup()} title="Download practice positions + game archive as JSON">
					Export data
				</button>
				<button onclick={() => importInput?.click()} title="Merge a botvinnik backup file into this browser's data">
					Import data
				</button>
				<input
					type="file"
					accept="application/json"
					bind:this={importInput}
					onchange={handleImportFile}
					hidden
				/>
				{#if importMsg}<span class="import-msg">{importMsg}</span>{/if}
			</div>
		{/snippet}

		{#if isNarrow}
			<BottomSheet bind:detent={sheetDetent} peek={SHEET_PEEK}>
				{#snippet header()}
					<!-- the move → verdict loop survives at peek height: last graded
					     move on one line, board still fully visible above -->
					{#if sideView === 'play'}
						<button
							class="grade-strip"
							onclick={() => {
								sheetTab = 'insights';
								if (sheetDetent === 'peek') sheetDetent = 'half';
							}}
						>
							{#if lastGrade}
								<span class="gs-san">{lastGrade.san}</span>
								{#if lastGrade.label}
									<span class="gs-verdict" style:color={CLASS[lastGrade.label].color}>
										{CLASS[lastGrade.label].glyph}
										{CLASS[lastGrade.label].noun}
									</span>
								{:else}
									<span class="gs-verdict muted">grading…</span>
								{/if}
								{#if lastGrade.pctBest !== null}
									<span class="gs-pct">{Math.round(lastGrade.pctBest)}% of best</span>
								{/if}
							{:else}
								<span class="gs-verdict muted">
									{botEnabled ? 'your moves are graded as you play' : 'play a move to see its grade'}
								</span>
							{/if}
						</button>
					{/if}
					<div class="sheet-head">
						<ModeBar
							view={sideView}
							practiceBadge={practiceDue > 0 ? String(practiceDue) : ''}
							onchange={(v) => {
								setView(v);
								if (sheetDetent === 'peek' && v !== 'play') sheetDetent = 'half';
							}}
						/>
						{#if sideView === 'play' && mode === 'play'}
							<button
								class="gear"
								class:on={gearOpen}
								onclick={() => (gearOpen = !gearOpen)}
								title="Board options"
							>
								⚙
							</button>
						{/if}
					</div>
					{#if gearOpen && sideView === 'play'}
						<div class="toggle-pop quick-toggles">
							{@render toggleRow()}
						</div>
					{/if}
					{#if sideView === 'play'}
						<nav class="tab-strip">
							{#each narrowTabs as t (t.id)}
								<button class:active={activeTab === t.id} onclick={() => selectTab(t.id)}>
									{t.label}
								</button>
							{/each}
						</nav>
					{/if}
				{/snippet}
				{#if sideView === 'practice'}
					{#if mode === 'practice'}
						<div class="practice-note">Practicing — analysis is hidden until you move.</div>
					{/if}
					{@render practiceBody()}
					{#if mode === 'practice'}
						{@render insightsBody()}
					{/if}
				{:else if sideView === 'review'}
					{@render gamesBody()}
					{#if reviewGame && reviewGame.moves.length > 1}
						{@render chartBody()}
					{/if}
					{@render commentaryBody()}
					{@render dataRow()}
				{:else}
					{@render gameOverNote()}
					{@render botBody()}
					{#if activeTab === 'lines'}
						{@render engineBody()}
					{:else if activeTab === 'book'}
						{@render bookBody()}
					{:else if activeTab === 'moves'}
						{@render movesBody()}
					{:else if activeTab === 'chart'}
						{@render chartBody()}
					{:else}
						{@render insightsBody()}
					{/if}
				{/if}
			</BottomSheet>
		{:else}
		<div class="sidebar" class:collapsed={panelsHidden}>
			<div class="sidebar-top">
				{#if !panelsHidden}
					<ModeBar
						view={sideView}
						practiceBadge={practiceDue > 0 ? String(practiceDue) : ''}
						onchange={setView}
					/>
				{/if}
				<button
					class="collapse-btn"
					onclick={() => (panelsHidden = !panelsHidden)}
					title={panelsHidden ? 'Show panels' : 'Hide panels'}
				>
					{panelsHidden ? '⟨ panels' : 'hide ⟩'}
				</button>
			</div>

			{#if !panelsHidden}
				{#if sideView === 'play'}
					{@render botBody()}
					{@render movesBody()}
					{@render insightsBody()}
					{@render engineBody()}
					<SidePanel title="Win chance" open={true}>
						{@render chartBody()}
					</SidePanel>
					<SidePanel title="Opening Book" bind:open={bookOpen}>
						{@render bookBody()}
					</SidePanel>

					{@render gameOverNote()}

					{#if commentaryOpen}
						<SidePanel
							title="Commentary"
							badge={commentary.length > 0 ? `${commentary.length} from YouTube` : ''}
							open={true}
						>
							{@render commentaryBody()}
						</SidePanel>
					{/if}
					<!-- the quiet footer: archives and plumbing, out of the scroll -->
					<div class="library">
						<button onclick={() => setView('review')}>
							Games{storedGames.length > 0 ? ` (${storedGames.length})` : ''}
						</button>
						<button class:lit={commentaryOpen} onclick={() => (commentaryOpen = !commentaryOpen)}>
							Commentary{commentary.length > 0 ? ` (${commentary.length})` : ''}
						</button>
						{@render dataRow()}
					</div>
				{:else if sideView === 'practice'}
					{#if mode === 'practice'}
						<div class="practice-note">
							Practicing — analysis is hidden until you move.
						</div>
					{/if}
					<SidePanel title="Practice">
						{@render practiceBody()}
					</SidePanel>
					{#if mode === 'practice'}
						{@render insightsBody()}
					{/if}
				{:else}
					{#if reviewGame && reviewGame.moves.length > 1}
						<SidePanel title="Win chance">
							{@render chartBody()}
						</SidePanel>
					{/if}
					<SidePanel title="Game review">
						{@render gamesBody()}
					</SidePanel>
					<SidePanel
						title="Commentary"
						badge={commentary.length > 0 ? `${commentary.length} from YouTube` : ''}
						open={commentary.length > 0}
					>
						{@render commentaryBody()}
					</SidePanel>
					{@render dataRow()}
				{/if}
			{/if}
		</div>
		{/if}
	</div>
</div>

<RosterPicker
	open={rosterOpen}
	personaId={botPersonaId}
	records={personaRecords}
	playerElo={playerEloEstimate}
	onpick={(id) => (botPersonaId = id)}
	onclose={() => (rosterOpen = false)}
/>

<style>
	.app {
		display: flex;
		flex-direction: column;
		align-items: center;
		padding: 12px 20px;
		min-height: 100vh;
		box-sizing: border-box;
	}
	.title {
		font-size: 20px;
		font-weight: 700;
		margin: 0 0 12px;
		color: var(--text-primary);
		letter-spacing: 2px;
		text-transform: uppercase;
	}
	.main {
		display: flex;
		gap: 16px;
		align-items: flex-start;
		flex-wrap: wrap;
		justify-content: center;
		width: 100%;
	}
	.board-col {
		display: flex;
		flex-direction: column;
		gap: 2px;
		flex-shrink: 0;
		/* the SSR-rendered width comes from default viewport state; without this
		   cap it overflows a phone, the browser expands the layout viewport to
		   fit, and hydration then reads the inflated innerWidth — permanently,
		   since bind:innerWidth only corrects on a resize event */
		max-width: calc(100dvw - 16px);
	}
	.sidebar {
		display: flex;
		flex-direction: column;
		gap: 12px;
		flex: 1 1 320px;
		min-width: 320px;
		max-height: calc(100vh - 88px);
		overflow-y: auto;
	}
	.sidebar.collapsed {
		flex: 0 0 auto;
		min-width: 0;
	}
	.sidebar-top {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		gap: 8px;
	}
	.sidebar-top :global(.modebar) {
		flex: 1;
	}
	.quick-toggles {
		display: flex;
		gap: 6px;
		margin-right: auto;
	}
	.quick-toggles.under-board {
		margin: 6px 0 0;
		justify-content: flex-end;
		width: 100%;
	}
	/* the play sidebar's quiet footer: archives and plumbing */
	.library {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 10px;
		flex-wrap: wrap;
		padding: 4px 0;
	}
	.library > button {
		background: transparent;
		color: var(--text-secondary);
		border: none;
		border-bottom: 1px dotted var(--text-secondary);
		border-radius: 0;
		font-size: 12px;
		padding: 0 0 1px;
		cursor: pointer;
	}
	.library > button:hover,
	.library > button.lit {
		color: var(--text-primary);
	}
	/* the expand-tree toggle inside the Lines card */
	:global(.tree-toggle) {
		background: transparent;
		color: var(--text-secondary);
		border: none;
		font-size: 12px;
		padding: 6px 0 2px;
		cursor: pointer;
	}
	:global(.tree-toggle:hover) {
		color: var(--text-primary);
	}
	.quick-toggles button {
		background: transparent;
		color: var(--text-secondary);
		border: 1px solid var(--border);
		border-radius: 12px;
		font-size: 11px;
		padding: 2px 10px;
		cursor: pointer;
	}
	.quick-toggles button.on {
		color: var(--color-win);
		border-color: var(--color-win);
	}
	.quick-toggles button:disabled {
		opacity: 0.4;
		cursor: default;
	}
	.collapse-btn {
		background: transparent;
		color: var(--text-secondary);
		border: 1px solid var(--border);
		border-radius: 4px;
		font-size: 11px;
		padding: 2px 8px;
		cursor: pointer;
	}
	.collapse-btn:hover {
		color: var(--text-primary);
	}
	/* the bottom sheet's header (narrow layout): grade strip, mode bar + gear,
	   then the view tabs — all visible at peek height */
	.grade-strip {
		display: flex;
		align-items: baseline;
		gap: 8px;
		width: 100%;
		background: transparent;
		border: none;
		padding: 0 14px 6px;
		font-size: 13px;
		text-align: left;
		cursor: pointer;
		box-sizing: border-box;
	}
	.gs-san {
		font-weight: 700;
		color: var(--text-primary);
	}
	.gs-verdict {
		font-weight: 600;
	}
	.gs-verdict.muted {
		color: var(--text-secondary);
		font-weight: 400;
	}
	.gs-pct {
		margin-left: auto;
		color: var(--text-secondary);
		font-size: 12px;
		font-variant-numeric: tabular-nums;
	}
	.sheet-head {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 0 10px 8px;
		flex-shrink: 0;
	}
	.sheet-head :global(.modebar) {
		flex: 1;
	}
	.gear {
		flex-shrink: 0;
		width: 34px;
		height: 34px;
		background: var(--bg-panel);
		color: var(--text-secondary);
		border: 1px solid var(--border);
		border-radius: 8px;
		font-size: 15px;
		line-height: 1;
		cursor: pointer;
	}
	.gear.on {
		color: var(--color-win);
		border-color: var(--color-win);
	}
	.toggle-pop {
		padding: 0 10px 8px;
		flex-wrap: wrap;
	}
	/* tab strip inside the bottom sheet's header (narrow layout) */
	.tab-strip {
		display: flex;
		gap: 6px;
		overflow-x: auto;
		padding: 2px 10px 8px;
		flex-shrink: 0;
		-webkit-overflow-scrolling: touch;
	}
	.tab-strip button {
		background: transparent;
		color: var(--text-secondary);
		border: 1px solid var(--border);
		border-radius: 12px;
		font-size: 12px;
		padding: 4px 12px;
		white-space: nowrap;
		cursor: pointer;
	}
	.tab-strip button.active {
		background: var(--bg-highlight);
		color: var(--text-primary);
		border-color: var(--text-secondary);
	}
	@media (max-width: 860px) {
		/* board pinned at the top; the bottom sheet owns all scrolling */
		.app.narrow {
			height: 100dvh;
			overflow: hidden;
			padding: 8px;
		}
		.title {
			font-size: 15px;
			margin-bottom: 6px;
		}
		.main {
			gap: 8px;
		}
	}

	.data-row {
		display: flex;
		align-items: center;
		gap: 6px;
		flex-wrap: wrap;
	}
	.data-row button {
		background: transparent;
		color: var(--text-secondary);
		border: 1px solid var(--border);
		border-radius: 4px;
		font-size: 11px;
		padding: 2px 10px;
		cursor: pointer;
	}
	.data-row button:hover {
		color: var(--text-primary);
	}
	.import-msg {
		font-size: 11px;
		color: var(--text-secondary);
	}
	.game-over {
		text-align: center;
		font-size: 16px;
		font-weight: 600;
		padding: 12px;
		background: var(--bg-panel);
		border-radius: 6px;
		color: var(--color-win);
	}
	.practice-note {
		background: var(--bg-panel);
		border-radius: 6px;
		padding: 12px;
		font-size: 13px;
		color: var(--text-secondary);
	}
	.promo-overlay {
		position: fixed;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		background: rgba(0, 0, 0, 0.35);
		z-index: 100;
	}
	.promo-box {
		display: flex;
		align-items: center;
		gap: 6px;
		background: var(--bg-panel);
		border: 1px solid var(--border);
		border-radius: 8px;
		padding: 10px;
	}
	.promo-piece {
		font-size: 40px;
		line-height: 1;
		width: 60px;
		height: 60px;
		background: var(--bg-highlight);
		color: var(--text-primary);
		border: 1px solid var(--border);
		border-radius: 6px;
		cursor: pointer;
	}
	.promo-piece:hover {
		background: var(--bg-button);
	}
	.promo-cancel {
		align-self: flex-start;
		background: none;
		border: none;
		color: var(--text-secondary);
		font-size: 16px;
		cursor: pointer;
	}
</style>
