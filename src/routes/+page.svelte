<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import { botDelay, selectBotMove } from '$lib/bot';
	import Board from '$lib/components/Board.svelte';
	import BotPanel from '$lib/components/BotPanel.svelte';
	import AnalysisPanel from '$lib/components/AnalysisPanel.svelte';
	import InsightsPanel from '$lib/components/InsightsPanel.svelte';
	import MoveList from '$lib/components/MoveList.svelte';
	import LinesTree from '$lib/components/LinesTree.svelte';
	import { downloadBackup, importBackup } from '$lib/backup';
	import CommentaryPanel from '$lib/components/CommentaryPanel.svelte';
	import GamesPanel from '$lib/components/GamesPanel.svelte';
	import PracticePanel from '$lib/components/PracticePanel.svelte';
	import SidePanel from '$lib/components/SidePanel.svelte';
	import { getCommentary, type CommentaryEntry } from '$lib/commentary';
	import { getPgn, getSan, getState, isPromotionMove, loadFen, makeMove, reset, undo } from '$lib/engine/chess';
	import {
		deleteGame,
		gameAccuracy,
		labelCounts,
		listGames,
		saveGame,
		type StoredGame,
		type StoredMove
	} from '$lib/gameStore';
	import { explainGoodMove, explainMove } from '$lib/engine/explain';
	import {
		backfillGrade,
		gradeMove,
		winChance,
		type MoveGrade,
		type MoveLabel
	} from '$lib/engine/insights';
	import { analyze, analyzeBotMove, analyzeMove, stopEngine, type EngineMove } from '$lib/engine/stockfish';
	import {
		addItem,
		dueCount,
		loadItems,
		nextItem,
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
	let treeOpen = $state(true);
	let practiceOpen = $state(false);
	let gamesOpen = $state(false);
	let commentaryOpen = $state(true);
	let commentary: CommentaryEntry[] = $state([]);

	// human commentary for the position on the board (placement-keyed, lazy-loaded)
	$effect(() => {
		const fen = game.fen;
		void getCommentary(fen).then((c) => {
			if (fen === game.fen) commentary = c;
		});
	});
	let blindMode = $state(false);
	let pendingPromotion: { from: string; to: string } | null = $state(null);
	let boardResetKey = $state(0);
	let viewportH = $state(900);
	let viewportW = $state(1280);
	// the board fills the window height; everything else lives in the right sidebar,
	// which soaks up the remaining width
	const TREE_HEIGHT = 200; // LinesTree svg
	const CHROME_V = 100; // page padding + title
	const SIDEBAR_MIN = 340; // sidebar min width + gap
	const boardSize = $derived(
		Math.max(
			360,
			Math.min(viewportH - CHROME_V, viewportW - (panelsHidden ? 120 : SIDEBAR_MIN + 60))
		)
	);

	const playedSans = $derived(game.moves.map((m) => m.san));
	const topMoves = $derived(engineMoves.slice(0, 3));

	// one grade per played move, judged against the pre-move analysis
	let moveHistory: MoveGrade[] = $state([]);
	const insightWhite = $derived(moveHistory.findLast((g) => g.color === 'w') ?? null);
	const insightBlack = $derived(moveHistory.findLast((g) => g.color === 'b') ?? null);

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
	const practiceDue = $derived(dueCount(practiceItems));

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

	// game archive + review
	let storedGames: StoredGame[] = $state([]);
	let reviewGame: StoredGame | null = $state(null);
	let reviewPly = $state(0);
	let gameSaved = false; // current game already archived

	// bot opponent
	const BOT_KEY = 'botvinnik-bot-v1';
	let botEnabled = $state(false);
	let botColor: 'w' | 'b' = $state('b'); // side the bot plays
	let botElo = $state(1500);
	let botThinking = $state(false);
	let botConsidering: string | null = $state(null); // uci the bot is eyeing right now
	let botSettingsLoaded = false;

	$effect(() => {
		practiceItems = loadItems();
		const t = Number(localStorage.getItem(THRESHOLD_KEY));
		if (t >= 5 && t <= 50) collectThreshold = t;
		try {
			const bot = JSON.parse(localStorage.getItem(BOT_KEY) ?? 'null');
			if (bot) {
				botEnabled = !!bot.enabled;
				botColor = bot.color === 'w' ? 'w' : 'b';
				if (bot.elo >= 100 && bot.elo <= 3600) botElo = bot.elo;
			}
		} catch {
			// ignore malformed settings
		}
		blindMode = localStorage.getItem('botvinnik-blind') === '1';
		botSettingsLoaded = true;
		void listGames().then((g) => (storedGames = g));
	});

	$effect(() => {
		const on = blindMode;
		if (botSettingsLoaded) localStorage.setItem('botvinnik-blind', on ? '1' : '0');
	});


	$effect(() => {
		const settings = { enabled: botEnabled, color: botColor, elo: botElo };
		if (botSettingsLoaded) localStorage.setItem(BOT_KEY, JSON.stringify(settings));
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
		await analyze(game.fen, 20, (moves) => {
			if (token === analysisToken) {
				engineMoves = moves;
				backfillLast(moves);
			}
		});
		if (token === analysisToken) {
			analyzing = false;
			maybeBotMove(token);
		}
	}

	// pick the bot's reply with a dedicated strength-limited search (runs
	// concurrently with the thinking delay); softmax over the full-strength
	// lines is the fallback if that search yields nothing
	async function maybeBotMove(token: number) {
		if (!botEnabled || mode !== 'play' || game.isGameOver || game.turn !== botColor) return;
		botThinking = true;
		const [res] = await Promise.all([
			analyzeBotMove(game.fen, botElo, (moves) => {
				botConsidering = moves[0]?.pv[0] ?? null;
			}),
			new Promise((r) => setTimeout(r, botDelay()))
		]);
		botThinking = false;
		botConsidering = null;
		if (token !== analysisToken || !botEnabled || mode !== 'play') return;
		if (game.isGameOver || game.turn !== botColor) return;
		// beginner band: sample flat-softmax over the wide shallow eval;
		// otherwise trust the strength-limited search's own choice
		const uci =
			botElo < 800 && res.moves.length > 0
				? selectBotMove(res.moves, botElo)
				: res.bestmove && res.bestmove !== '(none)'
					? res.bestmove
					: selectBotMove(engineMoves, botElo);
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
			prevAnalysis = { fen: fenBefore, sans: sansBefore, lines: linesBefore };
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

	function loadPuzzle(item: PracticeItem) {
		currentItem = item;
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
		lineDepth = 0;
		attempt = null;
		attemptGrade = null;
		lineNote = null;
		revealBest = false;
		loadFen(item.fen);
		lastMove = null;
		refresh();
	}

	function startPractice() {
		const item = nextItem(practiceItems);
		if (!item) return;
		analysisToken++; // orphan any in-flight play analysis
		stopEngine();
		analyzing = false;
		engineMoves = [];
		mode = 'practice';
		practiceOpen = true;
		loadPuzzle(item);
	}

	function exitPractice() {
		mode = 'play';
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
		if (!currentItem || !ref || attempt || grading || continuing) return;
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
		const playedPoint = pass
			? explainGoodMove(ref.fen, uci, isBest ? ref.bestPv : [uci, ...refutationPv], mate)
			: undefined;
		attemptGrade = buildAttemptGrade(ref, move.san, uci, evalPawns, mate, depth, drop, {
			playedIssue: explanation.playedIssue,
			bestPoint: explanation.bestPoint,
			playedPoint
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
			playedPoint
		};
		// only the stored puzzle counts toward spaced repetition, not line continuations
		if (lineDepth === 0) practiceItems = recordResult(practiceItems, currentItem.id, pass);
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
		explanation: { playedIssue?: string; bestPoint?: string; playedPoint?: string }
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
			explanation.playedIssue || explanation.bestPoint || explanation.playedPoint;
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
		const item = nextItem(practiceItems, currentItem?.id);
		if (item) loadPuzzle(item);
		else {
			currentItem = null;
			practiceRef = null;
			attempt = null;
			attemptGrade = null;
			lineNote = null;
		}
	}

	function retryPuzzle() {
		if (!practiceRef) return;
		loadFen(practiceRef.fen);
		lastMove = null;
		attempt = null;
		attemptGrade = null;
		revealBest = false;
		refresh();
	}

	function removePracticeItem(id: string) {
		practiceItems = removeItem(practiceItems, id);
		if (currentItem?.id === id) nextPuzzle();
	}

	// ---- game review ----

	function openReview(g: StoredGame) {
		if (mode === 'play' && !gameSaved && game.moves.length >= 10) void saveCurrentGame();
		analysisToken++; // orphan any in-flight analysis
		stopEngine();
		analyzing = false;
		engineMoves = [];
		mode = 'review';
		reviewGame = g;
		gamesOpen = true;
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
	// hints the panels/tree see — blanked in blind mode so nothing leaks
	const visibleLines = $derived(blindMode && mode === 'play' ? [] : engineMoves);

	// last completed position's analysis — in blind mode the tree can show
	// everything up to the previous move without hinting at the current one
	let prevAnalysis: { fen: string; sans: string[]; lines: EngineMove[] } | null = $state(null);
	const treeView = $derived(
		blindMode && mode === 'play'
			? (prevAnalysis ?? { fen: game.fen, sans: playedSans, lines: [] as EngineMove[] })
			: { fen: game.fen, sans: playedSans, lines: visibleLines }
	);

	function applyUci(uci: string) {
		const fenBefore = game.fen;
		const linesBefore = engineMoves;
		const sansBefore = playedSans;
		const move = makeMove(uci.slice(0, 2), uci.slice(2, 4), uci.length > 4 ? uci[4] : undefined);
		if (move) {
			lastMove = [move.from, move.to];
			prevAnalysis = { fen: fenBefore, sans: sansBefore, lines: linesBefore };
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
	async function saveCurrentGame() {
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
		const result = game.result ?? '*';
		const youAre = botEnabled ? (botColor === 'w' ? 'Black' : 'White') : null;
		const botName = botEnabled ? `Bot (${botElo})` : 'Analysis';
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
			botElo: botEnabled ? botElo : null,
			botColor: botEnabled ? botColor : null,
			moveCount: moves.length,
			whiteAccuracy: gameAccuracy(stored, 'w'),
			blackAccuracy: gameAccuracy(stored, 'b'),
			labelCounts: { w: labelCounts(stored, 'w'), b: labelCounts(stored, 'b') },
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
		// vs the bot, take back its reply too so it's your turn again
		if (botEnabled && getState().turn === botColor) undo();
		const last = getState().moves.at(-1);
		lastMove = last ? [last.from, last.to] : null;
		prevAnalysis = null; // stale after undo
		refresh();
		moveHistory = moveHistory.filter((g) => g.ply <= game.moves.length);
		runAnalysis();
	}

	function handleReset() {
		// archive abandoned games of meaningful length before wiping them
		if (mode === 'play' && !gameSaved && game.moves.length >= 10) void saveCurrentGame();
		reset();
		gameSaved = false;
		lastMove = null;
		prevAnalysis = null;
		refresh();
		moveHistory = [];
		collectedPlies = new Set();
		runAnalysis();
	}

	// analysis runs are explicit (every mutation path calls runAnalysis);
	// a reactive effect here would re-fire on refresh() and supersede
	// practice-mode searchmoves grading
	onMount(() => {
		runAnalysis();
	});
</script>

<svelte:window bind:innerHeight={viewportH} bind:innerWidth={viewportW} />

<div class="app">
	<h1 class="title">Botvinnik</h1>

	<div class="main">
		<Board
			fen={game.fen}
			turn={game.turn}
			legalMoves={boardLegalMoves}
			orientation={boardOrientation}
			engineMoves={boardArrows}
			botArrow={botThinking ? botConsidering : null}
			refutationArrow={mode === 'practice' && attempt && !attempt.pass ? (attempt.refutationUci ?? null) : null}
			resetKey={boardResetKey}
			{lastMove}
			size={boardSize}
			boundsKey={panelsHidden}
			onmove={handleMove}
		/>

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

		<div class="sidebar" class:collapsed={panelsHidden}>
			<div class="sidebar-top">
				{#if !panelsHidden && mode === 'play'}
					<div class="quick-toggles">
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
							Blind mode
						</button>
					</div>
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
				{#if mode === 'play'}
					<InsightsPanel white={insightWhite} black={insightBlack} {collectedPlies} />
					<BotPanel
						bind:enabled={botEnabled}
						bind:color={botColor}
						bind:elo={botElo}
						thinking={botThinking}
						startOpen={false}
					/>
					<AnalysisPanel moves={visibleLines.slice(0, 3)} fen={game.fen} {analyzing} startOpen={false} />
					<MoveList moves={game.moves} onundo={handleUndo} onreset={handleReset} startOpen={false} />

					<SidePanel title="Lines Tree" bind:open={treeOpen}>
						<LinesTree
							lines={treeView.lines}
							fen={treeView.fen}
							playedSans={treeView.sans}
							height={TREE_HEIGHT}
							onplay={blindMode ? undefined : handlePlayUci}
						/>
					</SidePanel>
					<SidePanel
						title="Commentary"
						badge={commentary.length > 0 ? `${commentary.length} from YouTube` : ''}
						bind:open={commentaryOpen}
					>
						<CommentaryPanel entries={commentary} />
					</SidePanel>
					<SidePanel
						title="Practice"
						badge={practiceItems.length > 0 ? `${practiceDue} due / ${practiceItems.length}` : ''}
						bind:open={practiceOpen}
					>
						<PracticePanel
							{mode}
							items={practiceItems}
							current={currentItem}
							{attempt}
							{grading}
							{revealBest}
							threshold={collectThreshold}
							onstart={startPractice}
							onexit={exitPractice}
							onnext={nextPuzzle}
							onretry={retryPuzzle}
							onreveal={() => (revealBest = true)}
							onremove={removePracticeItem}
							onthreshold={setCollectThreshold}
						/>
					</SidePanel>
					<SidePanel
						title="Games"
						badge={storedGames.length > 0 ? String(storedGames.length) : ''}
						bind:open={gamesOpen}
					>
						<GamesPanel
							games={storedGames}
							reviewing={null}
							{reviewPly}
							onreview={openReview}
							onclose={exitReview}
							ongoto={gotoReviewPly}
							ondelete={deleteStoredGame}
						/>
					</SidePanel>

					{#if game.isGameOver}
						<div class="game-over">
							Game over: {game.result}
						</div>
					{/if}

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
				{:else if mode === 'practice'}
					<div class="practice-note">
						Practicing — analysis is hidden until you move.
					</div>
					<SidePanel title="Practice">
						<PracticePanel
							{mode}
							items={practiceItems}
							current={currentItem}
							{attempt}
							{grading}
							{revealBest}
							{lineDepth}
							{lineNote}
							{continuing}
							threshold={collectThreshold}
							onstart={startPractice}
							onexit={exitPractice}
							onnext={nextPuzzle}
							onretry={retryPuzzle}
							onreveal={() => (revealBest = true)}
							oncontinue={continueLine}
							onremove={removePracticeItem}
							onthreshold={setCollectThreshold}
						/>
					</SidePanel>
					{#if attemptGrade && (attempt?.pass || revealBest)}
						<InsightsPanel
							white={attemptGrade.color === 'w' ? attemptGrade : null}
							black={attemptGrade.color === 'b' ? attemptGrade : null}
						/>
					{/if}
				{:else}
					<SidePanel title="Game review">
						<GamesPanel
							games={storedGames}
							reviewing={reviewGame}
							{reviewPly}
							onreview={openReview}
							onclose={exitReview}
							ongoto={gotoReviewPly}
							ondelete={deleteStoredGame}
						/>
					</SidePanel>
				{/if}
			{/if}
		</div>
	</div>
</div>

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
	.quick-toggles {
		display: flex;
		gap: 6px;
		margin-right: auto;
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
