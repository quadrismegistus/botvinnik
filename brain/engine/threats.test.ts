import { describe, expect, it } from 'vitest';
import { findThreat } from './threats';
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

	it('treats a forced mate as a threat with infinite gain', async () => {
		const fen = '4k3/8/4p3/3N4/8/8/8/4K3 w - - 0 1';
		const analyze = fakeAnalyze(['e6d5'], { mate: 2 });
		const t = await findThreat(fen, analyze);
		expect(t).not.toBeNull();
		expect(t!.gain).toBe(Infinity);
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
	});

	it('returns null on a finished game', async () => {
		const fen = '4k3/8/8/8/8/8/8/4K3 w - - 0 1'; // bare kings → insufficient material → over
		const analyze = fakeAnalyze([]);
		expect(await findThreat(fen, analyze)).toBeNull();
		expect(analyze.seen).toHaveLength(0); // bailed on isGameOver, before ever probing
	});
});
