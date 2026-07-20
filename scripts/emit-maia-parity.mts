// The reference answers the native Maia must reproduce.
//
// Native (macOS/iOS) runs Maia through package:onnxruntime and an embedded JS
// runtime; the web runs it through ort-web in a Worker. Both call the same
// brain/maia/ encode/decode, so a disagreement is a marshalling bug in the
// native path — precisely the class of bug the golden brain fixtures exist to
// catch, and the reason this emits fixtures rather than eyeballing a move.
//
//   npx tsx scripts/emit-maia-parity.mts
//
// Paste the output into flutter/integration_test/maia_native_test.dart. It is
// small and changes only when a net does, so it is inlined there rather than
// carried as another asset — see that file's header.

import { maiaMoveNode } from './maia-node.mts';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

// One case per thing that can go wrong in the encoding: the plain start, a
// position reached WITH history (the history planes are populated), the same
// kind of position with NO history (they are not), and black to move (the
// board is flipped and the policy index is looked up from the other side).
const cases: { name: string; history: string[] }[] = [
	{ name: 'start', history: [START] },
	{
		name: 'after 1.e4, with history',
		history: [START, 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1']
	},
	{
		name: 'italian, no history',
		history: ['r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 5 4']
	},
	{
		name: 'black to move, midgame',
		history: ['r2q1rk1/ppp2ppp/2np1n2/2b1p3/2B1P1b1/2NP1N2/PPP2PPP/R1BQ1RK1 b - - 6 8']
	}
];

for (const band of [1100, 1500, 1900]) {
	for (const c of cases) {
		const move = await maiaMoveNode(c.history, band, 0);
		console.log(
			`  (${band}, [${c.history.map((f) => `'${f}'`).join(', ')}], '${move}'), // ${c.name}`
		);
	}
}
