import { describe, expect, it } from 'vitest';
import { findThreat, judgeTacticalWin } from './threats';
import type { EngineMove, EngineResult } from './types';

// build a fake analyze() that returns a canned line, and records the fen it saw
function fakeAnalyze(pv: string[], opts: { mate?: number | null; score?: number } = {}) {
	const seen: string[] = [];
	const move: EngineMove = {
		pv,
		score: opts.score ?? 1,
		mate: opts.mate ?? null,
		depth: 14,
		multipv: 1
	};
	const fn = async (fen: string): Promise<EngineResult> => {
		seen.push(fen);
		return { moves: pv.length ? [move] : [], bestmove: pv[0] ?? '', depth: 14 };
	};
	return Object.assign(fn, { seen });
}

describe('findThreat', () => {
	it('flags a free capture the opponent would make on their move', async () => {
		// White to move; if Black had the move, e6xd5 wins the undefended knight
		const fen = '4k3/8/4p3/3N4/8/8/8/4K3 w - - 0 1';
		const analyze = fakeAnalyze(['e6d5', 'e1e2']); // capture, then a quiet move settles net
		const t = await findThreat(fen, analyze);
		expect(t).not.toBeNull();
		expect(t!.uci).toBe('e6d5');
		expect(t!.san).toBe('exd5');
		expect(t!.gain).toBe(3);
		expect(t!.targets).toEqual(['d5']); // the victim: a direct capture, so it is also the arrow's tip
		expect(t!.fen).toBe(fen); // tagged with the original position, not the flipped probe
		// probed the flipped (Black-to-move) position, not the original
		expect(analyze.seen[0]).toContain(' b ');
	});

	it('ignores an equal trade (bishop for a defended knight)', async () => {
		// Nd5 is defended by c4; Bxd5 cxd5 is a wash → not a threat
		const fen = '4k3/1b6/8/3N4/2P5/8/8/4K3 w - - 0 1';
		const analyze = fakeAnalyze(['b7d5', 'c4d5', 'e8e7']); // Bxd5 cxd5 Ke7 → net 0
		const t = await findThreat(fen, analyze);
		expect(t).toBeNull();
	});

	it('returns null when the side to move is in check (no free move to give away)', async () => {
		const fen = '4k3/8/8/8/7b/8/8/4K3 w - - 0 1'; // Bh4+ checks Ke1
		const analyze = fakeAnalyze(['h4e1']);
		const t = await findThreat(fen, analyze);
		expect(t).toBeNull();
		expect(analyze.seen).toHaveLength(0); // bailed before probing
	});

	it('treats a forced mate as a threat with infinite gain, targeting the king', async () => {
		const fen = '4k3/8/4p3/3N4/8/8/8/4K3 w - - 0 1';
		const analyze = fakeAnalyze(['e6d5'], { mate: 2 });
		const t = await findThreat(fen, analyze);
		expect(t).not.toBeNull();
		expect(t!.gain).toBe(Infinity);
		expect(t!.targets).toEqual(['e1']); // White is the side being probed against — their king falls
	});

	it('is silent when the free move still LOSES to forced mate (negative mate)', async () => {
		// Black's best "free move" grabs the bishop, but White mates anyway:
		// best-resistance material grabs are delaying tactics, not threats
		const fen = '4k3/8/8/7n/5B2/8/8/4K3 w - - 0 1';
		const analyze = fakeAnalyze(['h5f4', 'e1e2'], { mate: -3 });
		expect(await findThreat(fen, analyze)).toBeNull();
	});

	it('targets the square the doomed piece stands on NOW, not where it is caught', async () => {
		// Black's free move c6 attacks the d5 queen; in the line she runs to b5
		// and the a6 pawn takes her there. The arrow shows c7c6 (an empty
		// square); the target must say d5 — where the queen is actually standing.
		const fen = '4k3/2p5/p7/3Q4/8/8/8/4K3 w - - 0 1';
		const analyze = fakeAnalyze(['c7c6', 'd5b5', 'a6b5', 'e1e2']); // quiet Ke2 settles the count
		const t = await findThreat(fen, analyze);
		expect(t).not.toBeNull();
		expect(t!.uci).toBe('c7c6');
		expect(t!.gain).toBe(9);
		expect(t!.targets).toEqual(['d5']);
	});

	it('rings every forked piece that FALLS, not the one that escapes', async () => {
		// Ryan's screenshot: Ng5 in place, Black to move — White's free move
		// Nxf7 forks queen and rook. In the line the queen saves herself and
		// the rook dies at home: targets are the f7 pawn and the h8 rook,
		// never the queen (attacked is not lost).
		const fen = '3qk2r/5p2/8/6N1/8/8/8/4K3 b k - 0 1';
		const analyze = fakeAnalyze(['g5f7', 'd8d5', 'f7h8', 'e8e7']); // NxP, Q runs, NxR, quiet
		const t = await findThreat(fen, analyze);
		expect(t).not.toBeNull();
		expect(t!.uci).toBe('g5f7');
		expect(t!.gain).toBe(6); // pawn + rook
		expect(t!.targets).toEqual(['f7', 'h8']);
	});

	it('does not ring a piece that trades itself off evenly (captured ≠ lost)', async () => {
		// Ryan's screenshot: Nc3 double-attacks the e4 bishop and the d5 pawn.
		// In the line the bishop CHOOSES Bxf3 and is recaptured — an even
		// trade, not a loss — and the pawn falls later. Ring d5 only: the
		// claim "you lose this piece" must not cover "this piece gets traded".
		const fen = '3qk3/8/8/3p4/4b3/5N2/6B1/1N2K3 b - - 0 1';
		const analyze = fakeAnalyze([
			'b1c3', // the double attack (quiet)
			'e4f3', // bishop trades itself for the knight
			'g2f3', // recaptured — fair, no ring on e4
			'e8d7',
			'f3d5', // the pawn falls
			'd7e7' // quiet, settles the count
		]);
		const t = await findThreat(fen, analyze);
		expect(t).not.toBeNull();
		expect(t!.uci).toBe('b1c3');
		expect(t!.gain).toBe(1); // -N +B +P
		expect(t!.targets).toEqual(['d5']);
	});

	it('still rings a trapped piece whose desperado grab is worth less than itself', async () => {
		// Ryan's b5 screenshot: the free move b5 attacks the c4 bishop; its
		// best is Bxb5 axb5 — it died for a pawn. That recapture is NOT a
		// fair trade (1 < 3): the bishop was lost, ring it where it stands.
		const fen = '4k3/1p6/p7/8/2B5/8/8/4K3 w - - 0 1';
		const analyze = fakeAnalyze(['b7b5', 'c4b5', 'a6b5', 'e1e2']); // quiet Ke2 settles
		const t = await findThreat(fen, analyze);
		expect(t).not.toBeNull();
		expect(t!.uci).toBe('b7b5');
		expect(t!.gain).toBe(2); // bishop for a pawn
		expect(t!.targets).toEqual(['c4']);
	});

	it('drops a small gain that names no victim (gambit-horizon noise)', async () => {
		// The "threat: Nc6 costs 1.0" mirage: after the free move Nc6, the
		// line goes d4 exd4 — the pawn dies only because it ADVANCED into the
		// capture, so Nc6 attacks nothing and there is no victim to ring. A
		// quiet window is not a settled one (a gambit is quiet and a pawn
		// down on purpose): victimless +1 is choreography, not a threat.
		const fen = 'rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 2';
		const analyze = fakeAnalyze(['b8c6', 'd2d4', 'e5d4', 'g1f3']); // quiet Nf3 settles the count
		expect(await findThreat(fen, analyze)).toBeNull();
	});

	it('keeps a victimless gain that clears the higher bar (promotion push)', async () => {
		// Black's free move promotes: no capture, so no square to ring, but
		// +8 is no one's horizon noise — the threat shows, arrow only.
		const fen = '4k3/8/8/8/8/8/p3K3/8 w - - 0 1';
		const analyze = fakeAnalyze(['a2a1q', 'e2f3']); // promote, quiet king step settles
		const t = await findThreat(fen, analyze);
		expect(t).not.toBeNull();
		expect(t!.uci).toBe('a2a1q');
		expect(t!.gain).toBe(8);
		expect(t!.targets).toEqual([]);
	});

	it('ignores a truncated pv that "wins" a defended piece (mid-exchange horizon)', async () => {
		// Ryan's report: Nh5xf4 flagged as a threat although the f4 bishop was
		// queen-protected — the 1-ply pv never showed the recapture. White to
		// move; Black's free move Nxf4 trades knight for defended bishop: no gain.
		const fen = '4k3/8/8/7n/3Q1B2/8/8/4K3 w - - 0 1';
		const analyze = fakeAnalyze(['h5f4']); // pv ends on the capture
		expect(await findThreat(fen, analyze)).toBeNull();
	});

	it('still flags a truncated pv that grabs an UNDEFENDED piece', async () => {
		const fen = '4k3/8/8/7n/5B2/8/8/4K3 w - - 0 1'; // no queen: Bf4 hangs to Nxf4
		const analyze = fakeAnalyze(['h5f4']);
		const t = await findThreat(fen, analyze);
		expect(t).not.toBeNull();
		expect(t!.gain).toBe(3);
		expect(t!.targets).toEqual(['f4']); // fallback path: the bare capture names its own victim
	});

	it('returns null on a finished game', async () => {
		const fen = '4k3/8/8/8/8/8/8/4K3 w - - 0 1'; // bare kings → insufficient material → over
		const analyze = fakeAnalyze([]);
		expect(await findThreat(fen, analyze)).toBeNull();
		expect(analyze.seen).toHaveLength(0); // bailed on isGameOver, before ever probing
	});
});

// the green mirror: the same judgment on the mover's OWN top line
describe('judgeTacticalWin', () => {
	it('rings the hanging piece the top line just takes', () => {
		const fen = '4k3/8/8/3b4/8/8/3R4/4K3 w - - 0 1'; // Bd5 hangs to the rook
		const w = judgeTacticalWin(fen, { pv: ['d2d5', 'e8e7'], mate: null });
		expect(w).not.toBeNull();
		expect(w!.gain).toBe(3);
		expect(w!.targets).toEqual(['d5']);
	});

	it('rings the fork victims of your own line — no turn flip', () => {
		// image 16 with White to move: Nxf7 forks queen and rook; the queen
		// escapes, the pawn and rook fall
		const fen = '3qk2r/5p2/8/6N1/8/8/8/4K3 w k - 0 1';
		const w = judgeTacticalWin(fen, {
			pv: ['g5f7', 'd8d5', 'f7h8', 'e8e7'],
			mate: null
		});
		expect(w).not.toBeNull();
		expect(w!.uci).toBe('g5f7');
		expect(w!.gain).toBe(6);
		expect(w!.targets).toEqual(['f7', 'h8']);
	});

	it('rings the OPPONENT king when your line mates', () => {
		const fen = '4k3/8/8/3b4/8/8/3R4/4K3 w - - 0 1';
		const w = judgeTacticalWin(fen, { pv: ['d2d5'], mate: 3 });
		expect(w).not.toBeNull();
		expect(w!.gain).toBe(Infinity);
		expect(w!.targets).toEqual(['e8']);
	});

	it('is silent on a quiet line that wins nothing', () => {
		const fen = '4k3/8/8/3b4/8/8/3R4/4K3 w - - 0 1';
		expect(judgeTacticalWin(fen, { pv: ['d2c2', 'e8e7'], mate: null })).toBeNull();
	});
});
