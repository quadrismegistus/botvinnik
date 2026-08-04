// Per-game extractor: turns one raw game-text block (as yielded by
// stream.mjs) into a structured record, or a `{ skip: reason }` verdict.
//
// Textual only — no chess.js replay. We never need board legality here: SAN
// tokens are stored as-is (after stripping lichess's engine-annotation
// glyphs), ply/color come from position in the movetext, and the opening
// book match (book.mjs) and the win-chance math (aggregate.mjs) both work
// off that same textual stream. Keeping extraction textual is also what
// keeps a production month's aggregation pass cheap: no position replay per
// move, of any game, ever.

const HEADER_RE = /^\[(\w+)\s+"((?:[^"\\]|\\.)*)"\]$/;

function parseHeaders(lines) {
	const headers = {};
	const bodyLines = [];
	for (const line of lines) {
		const m = HEADER_RE.exec(line);
		if (m) headers[m[1]] = m[2];
		else bodyLines.push(line);
	}
	return { headers, movetext: bodyLines.join(' ') };
}

// Lichess's own engine-annotation glyphs (?!, ??, !!, !?, ?, !) ride along on
// SAN tokens whenever a game has `%eval` comments (e.g. "Nf6??"). They are
// never part of real SAN, which only ever carries a trailing +/# for
// check/mate — so stripping a trailing run of ! and ? is safe and leaves any
// genuine check/mate marker untouched.
export function cleanSan(token) {
	return token.replace(/[!?]+$/, '');
}

const MOVE_NUM_RE = /^\d+\.+$/;
const RESULT_RE = /^(1-0|0-1|1\/2-1\/2|\*)$/;
const NAG_RE = /^\$\d+$/;
const TOKEN_RE = /\{[^}]*\}|\S+/g;
const EVAL_RE = /\[%eval\s+(#?-?\d+(?:\.\d+)?)]/;
const CLK_RE = /\[%clk\s+(\d+):(\d{2}):(\d{2}(?:\.\d+)?)]/;

function parseComment(text) {
	let eval_ = null;
	const em = EVAL_RE.exec(text);
	if (em) {
		const raw = em[1];
		eval_ = raw.startsWith('#')
			? { pawns: null, mate: parseInt(raw.slice(1), 10) }
			: { pawns: parseFloat(raw), mate: null };
	}
	let clk = null;
	const cm = CLK_RE.exec(text);
	if (cm) clk = Number(cm[1]) * 3600 + Number(cm[2]) * 60 + Number(cm[3]);
	return { eval: eval_, clk };
}

/**
 * Parse movetext into `{ ply, color, san, clk, eval }` records. `clk` is
 * seconds remaining (after the move, increment already applied — the value
 * lichess itself displays), or null. `eval` is `{ pawns, mate }` in
 * centipawn-derived pawns/plies, ALWAYS from White's point of view (lichess's
 * own `%eval` convention — see aggregate.mjs for where this gets flipped to
 * the mover's perspective), or null when the move has no eval comment.
 */
export function parseMovetext(text) {
	const moves = [];
	let ply = 0;
	const tokens = text.match(TOKEN_RE) ?? [];
	for (const tok of tokens) {
		if (tok[0] === '{') {
			if (moves.length === 0) continue; // stray comment before any move
			const { eval: ev, clk } = parseComment(tok.slice(1, -1));
			const last = moves[moves.length - 1];
			if (ev) last.eval = ev;
			if (clk !== null) last.clk = clk;
			continue;
		}
		if (MOVE_NUM_RE.test(tok) || RESULT_RE.test(tok) || NAG_RE.test(tok)) continue;
		ply++;
		moves.push({
			ply,
			color: ply % 2 === 1 ? 'w' : 'b',
			san: cleanSan(tok),
			clk: null,
			eval: null
		});
	}
	return moves;
}

// Standard lichess speed names for a non-variant game's Event tag (the
// database dump always spells it "Rated <Speed> game" or "... tournament
// <url>"; variant games spell it "Rated <Variant name> game" instead, e.g.
// "Rated Chess960 game", which does not match here).
const RATED_STANDARD_EVENT_RE =
	/^Rated\s+(UltraBullet|Bullet|Blitz|Rapid|Classical|Correspondence)\b/;
const CASUAL_EVENT_RE = /^Casual\b/;

function eventSkipReason(headers) {
	if (headers.Variant && headers.Variant.toLowerCase() !== 'standard') return 'variant';
	const event = headers.Event ?? '';
	if (CASUAL_EVENT_RE.test(event)) return 'unrated';
	if (RATED_STANDARD_EVENT_RE.test(event)) return null;
	// Doesn't start "Casual" and doesn't match a known standard speed name
	// after "Rated " — either a variant Event string (e.g. "Rated Chess960
	// game") or a shape we don't recognize. Skip conservatively either way.
	return 'variant';
}

// lichess's own Speed classification (Speed.scala): estimated total game
// seconds = initial + 40 * increment, then bucketed. TimeControl "-" (no
// clock at all) is Correspondence and is rejected earlier by
// parseTimeControl. Source: the TimeControl tag, per the README.
function parseTimeControl(tc) {
	if (!tc) return null;
	const m = /^(\d+)\+(\d+)$/.exec(tc);
	if (!m) return null; // "-" (correspondence) or an unrecognized shape
	return { initial: Number(m[1]), increment: Number(m[2]) };
}

function classifyTimeClass({ initial, increment }) {
	const estimate = initial + 40 * increment;
	if (estimate < 30) return 'ultrabullet';
	if (estimate < 180) return 'bullet';
	if (estimate < 480) return 'blitz';
	if (estimate < 1500) return 'rapid';
	return 'classical';
}

/**
 * @param {string} rawBlock one game's worth of lines, as yielded by
 *   stream.mjs's streamGames/splitGameBlocks (header lines + movetext line,
 *   joined by "\n")
 * @returns {{ skip: string }|{ skip: null, timeClass: string, whiteElo: number,
 *   blackElo: number, termination: string|null, initial: number,
 *   increment: number, moves: object[] }}
 */
export function extractGame(rawBlock) {
	const lines = rawBlock.split('\n');
	const { headers, movetext } = parseHeaders(lines);

	const reason = eventSkipReason(headers);
	if (reason) return { skip: reason };

	const tc = parseTimeControl(headers.TimeControl);
	if (!tc) return { skip: 'no-time-control' };
	const timeClass = classifyTimeClass(tc);
	if (timeClass === 'bullet' || timeClass === 'ultrabullet') return { skip: 'bullet' };
	// blitz/rapid/classical only — v1 has no correspondence table either
	if (timeClass !== 'blitz' && timeClass !== 'rapid' && timeClass !== 'classical') {
		return { skip: 'time-class' };
	}

	// Engines wear a BOT title, not a special rating — unfiltered, they OWN
	// the top bands (#293 review, measured on the real month: 2600/rapid was
	// 95.6% bot by clocked moves, rendered as "Typical 2600"). A peer table
	// is a claim about players; a game with an engine in it is out.
	if (headers.WhiteTitle === 'BOT' || headers.BlackTitle === 'BOT') {
		return { skip: 'bot' };
	}
	const whiteElo = Number(headers.WhiteElo);
	const blackElo = Number(headers.BlackElo);
	if (!Number.isFinite(whiteElo) || !Number.isFinite(blackElo)) return { skip: 'no-elo' };

	const moves = parseMovetext(movetext);
	if (moves.length === 0) return { skip: 'no-moves' };

	return {
		skip: null,
		timeClass,
		whiteElo,
		blackElo,
		termination: headers.Termination ?? null,
		initial: tc.initial,
		increment: tc.increment,
		moves
	};
}
