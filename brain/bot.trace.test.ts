// The optional decision trace (#149): shapedBotMove can explain itself.
//
// The lichess bot reads this to narrate its own moves in game chat. It arrived
// as a SECOND, traced copy of shapedBotMove on an unmerged branch — 144
// duplicated lines of the choice layer every bot in the product depends on,
// live on one server for two weeks with no test. This is the same feature as
// one function plus a callback, and these are the properties that make that
// safe.
import { describe, expect, it } from 'vitest';

import { shapedBotMove, type DecisionTrace } from './bot';
import type { EngineMove } from './engine/types';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

function line(multipv: number, score: number, move: string, mate: number | null = null): EngineMove {
	return { multipv, score, mate, pv: [move], depth: 12 };
}

/** Collect the trace for one decision. */
function traced(lines: EngineMove[], label = 900, seed = 'test-seed') {
	let t: DecisionTrace | null = null;
	const move = shapedBotMove(lines, label, undefined, seed, undefined, undefined, undefined, (x) => {
		t = x;
	});
	return { move, trace: t as DecisionTrace | null };
}

describe('the decision trace', () => {
	it('fires exactly once, and describes the move actually returned', () => {
		let calls = 0;
		let last: DecisionTrace | null = null;
		const move = shapedBotMove(
			[line(1, 2.0, 'e2e4'), line(2, 0.1, 'd2d4'), line(3, -0.2, 'g1f3')],
			900,
			undefined,
			'seed-1',
			undefined,
			undefined,
			undefined,
			(t) => {
				calls++;
				last = t;
			}
		);
		expect(calls, 'one decision, one trace').toBe(1);
		expect(last!.playedMove).toBe(move);
	});

	it('reports the engine\'s best move even when the bot did not play it', () => {
		// The whole point for chat: "I should have played X, I played Y."
		// label 600 misses often, so this samples both outcomes.
		const lines = [line(1, 6.0, 'e2e4'), line(2, -1.0, 'd2d4'), line(3, -1.2, 'g1f3')];
		const seen = new Set<string>();
		for (let i = 0; i < 200; i++) {
			const { move, trace } = traced(lines, 600, `s${i}`);
			expect(trace).not.toBeNull();
			expect(trace!.bestMove, 'best is always the engine top line').toBe('e2e4');
			expect(trace!.playedMove).toBe(move);
			seen.add(trace!.branch);
		}
		expect(seen.has('tactical-seen') || seen.has('tactical-miss'), [...seen].join()).toBe(true);
	});

	it('is silent when nobody asks — and changes nothing', () => {
		// The callback must be pure overhead-free observation. If omitting it
		// changed the decision, every bot in the product would depend on
		// whether the lichess bot happened to be watching.
		const lines = [line(1, 3.0, 'e2e4'), line(2, 0.5, 'd2d4'), line(3, 0.4, 'g1f3')];
		for (let i = 0; i < 300; i++) {
			const seed = `pair-${i}`;
			const withCb = shapedBotMove(lines, 900, undefined, seed, undefined, undefined, undefined, () => {});
			const without = shapedBotMove(lines, 900, undefined, seed);
			// Both are stochastic, so this is not a strict equality claim about
			// one call — it is that both stay inside the same candidate set.
			expect(lines.map((l) => l.pv[0])).toContain(withCb!);
			expect(lines.map((l) => l.pv[0])).toContain(without!);
		}
	});

	it('traces the only-move case, which returns before the rest of the machinery', () => {
		const { move, trace } = traced([line(1, 1.0, 'e2e4')]);
		expect(move).toBe('e2e4');
		expect(trace!.branch).toBe('only-move');
		expect(trace!.candidates).toBe(1);
		expect(trace!.playedMove).toBe('e2e4');
	});

	it('carries the miss coin it actually rolled, in scan mode', () => {
		// effectiveP and roll are what the chat renders as a D&D-style DC and
		// roll; missProb alone would misdescribe it, because visibility and the
		// opening damp reshape the probability before it is used.
		const lines = [line(1, 8.0, 'd1h5'), line(2, -0.5, 'd2d4'), line(3, -0.6, 'g1f3')];
		let withCoin = 0;
		for (let i = 0; i < 120; i++) {
			let t: DecisionTrace | null = null;
			shapedBotMove(lines, 900, { scan: true }, `c${i}`, START, undefined, undefined, (x) => {
				t = x;
			});
			const tr = t as DecisionTrace | null;
			if (tr && (tr.branch === 'tactical-seen' || tr.branch === 'tactical-miss')) {
				expect(tr.effectiveP, 'the probability actually used').toBeGreaterThanOrEqual(0);
				expect(tr.roll, 'and the roll against it').toBeGreaterThanOrEqual(0);
				expect(tr.roll!).toBeLessThanOrEqual(1);
				// missed iff the roll came in under the bar
				if (tr.branch === 'tactical-miss') expect(tr.roll!).toBeLessThan(tr.effectiveP!);
				else expect(tr.roll!).toBeGreaterThanOrEqual(tr.effectiveP!);
				withCoin++;
			}
		}
		expect(withCoin, 'the tactical branch was reached at all').toBeGreaterThan(0);
	});

	it('never claims a played move the caller did not receive', () => {
		// Guards the class of bug that a duplicated decision function invites:
		// a trace describing one code path while another returns the move.
		const shapes: EngineMove[][] = [
			[line(1, 9.0, 'e2e4'), line(2, -3.0, 'd2d4')],
			[line(1, 0.1, 'e2e4'), line(2, 0.05, 'd2d4'), line(3, 0.0, 'g1f3')],
			[line(1, 0.0, 'e2e4', 2), line(2, -5.0, 'd2d4')],
			[line(1, -4.0, 'e2e4'), line(2, -4.2, 'd2d4'), line(3, -9.0, 'g1f3')],
		];
		for (const lines of shapes) {
			for (const label of [600, 900, 1200, 1500]) {
				for (let i = 0; i < 25; i++) {
					const { move, trace } = traced(lines, label, `x${label}-${i}`);
					expect(trace, `${label} ${i}`).not.toBeNull();
					expect(trace!.playedMove).toBe(move);
				}
			}
		}
	});
});
