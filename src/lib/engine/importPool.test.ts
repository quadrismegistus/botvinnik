import { describe, expect, it } from 'vitest';
import { PoolEngine, type Pipe } from './importPool';
import { createLineSplitter } from './lineSplitter';

// a fake UCI pipe: captures sends, lets the test speak as the engine
function fakePipe() {
	const sent: string[] = [];
	let emit: (line: string) => void = () => {};
	const open = (onLine: (line: string) => void): Pipe => {
		emit = onLine;
		return { send: (cmd) => sent.push(cmd), dispose: () => sent.push('<disposed>') };
	};
	return { sent, open, engine: (line: string) => emit(line) };
}

describe('PoolEngine', () => {
	it('handshakes and becomes ready on readyok', async () => {
		const pipe = fakePipe();
		const e = new PoolEngine(pipe.open);
		await new Promise((r) => setTimeout(r, 0)); // let the async open settle
		expect(pipe.sent).toEqual([
			'uci',
			'setoption name Threads value 1',
			'setoption name Hash value 32',
			'isready'
		]);
		pipe.engine('readyok');
		await e.ready; // resolves
	});

	it('resolves an analysis with the last non-bound info line', async () => {
		const pipe = fakePipe();
		const e = new PoolEngine(pipe.open);
		await new Promise((r) => setTimeout(r, 0));
		pipe.engine('readyok');
		await e.ready;

		const result = e.analyze('some-fen w - - 0 1', 300000);
		expect(e.busy).toBe(true);
		expect(pipe.sent.at(-2)).toBe('position fen some-fen w - - 0 1');
		expect(pipe.sent.at(-1)).toBe('go nodes 300000');

		pipe.engine('info depth 10 score cp 31 nodes 1000 pv e2e4 e7e5');
		pipe.engine('info depth 12 score cp 25 nodes 5000 pv d2d4 d7d5 c2c4');
		// bound line near the stop must not clobber the real one
		pipe.engine('info depth 13 score cp 90 upperbound nodes 6000 pv d2d4');
		pipe.engine('bestmove d2d4');

		const r = await result;
		expect(r.cp).toBe(25);
		expect(r.pv).toEqual(['d2d4', 'd7d5', 'c2c4']);
		expect(e.busy).toBe(false);
	});

	it('reports mate scores', async () => {
		const pipe = fakePipe();
		const e = new PoolEngine(pipe.open);
		await new Promise((r) => setTimeout(r, 0));
		pipe.engine('readyok');
		await e.ready;
		const result = e.analyze('fen', 100);
		pipe.engine('info depth 5 score mate 2 nodes 100 pv h5f7');
		pipe.engine('bestmove h5f7');
		expect(await result).toEqual({ cp: undefined, mate: 2, pv: ['h5f7'] });
	});
});

describe('createLineSplitter', () => {
	it('reassembles lines across chunks and strips CR', () => {
		const lines: string[] = [];
		const push = createLineSplitter((l) => lines.push(l));
		push('info depth 5 sco');
		push('re cp 10 pv e2e4\r\nbest');
		push('move e2e4\n\n');
		expect(lines).toEqual(['info depth 5 score cp 10 pv e2e4', 'bestmove e2e4']);
	});
});
