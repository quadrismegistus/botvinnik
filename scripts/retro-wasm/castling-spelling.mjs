// morlock accepts exactly ONE spelling of castling, and the app can produce two.
//
//   node scripts/retro-wasm/castling-spelling.mjs
//
// dartchess builds its legal-move map with `includeAlternateCastlingMoves`, so
// chessground offers the king both g1 and h1 and `MoveRecord.uci` stores
// whichever square the player dropped on. A PGN import stores `e1h1` too, that
// being dartchess's own normal form. morlock generates castling only as
// king-two-squares (`position.go` → `BitMask(G1)`), compares moves by from/to
// (`move.go` `Move.Equals`), and rejects an unmatched one by RETURNING from its
// UCI driver — which ends the Go program, exactly as the repeated `position`
// line did in #245.
//
// So until #244 started sending a move list this was harmless, and the moment
// it did, one castle-by-dragging killed the engine for the rest of the game and
// handed every later turn to a Stockfish stand-in wearing the persona's name.
//
// `GameController.engineUci` converts the spelling; this asserts the fact that
// makes it necessary, against the real committed wasm. It lives here rather
// than in the Dart suite because no Dart test can watch morlock reject a move —
// the whole failure is inside the engine, and the Dart side sees only silence.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const dir = fileURLToPath(new URL('../../vendor/retro/', import.meta.url));

const g = globalThis;
g.self = g;
g.importScripts = (f) => (0, eval)(readFileSync(`${dir}/${f}`, 'utf8'));
g.fetch = async () =>
  new Response(readFileSync(`${dir}/retro.wasm`), {
    headers: { 'content-type': 'application/wasm' },
  });

const out = [];
g.postMessage = (m) => out.push(String(m));
let onmsg = null;
Object.defineProperty(g, 'onmessage', { get: () => onmsg, set: (f) => (onmsg = f) });
(0, eval)(readFileSync(`${dir}/retro-worker.js`, 'utf8'));

const send = (d) => onmsg({ data: d });
const waitFor = (p, ms) =>
  new Promise((res) => {
    const t = setInterval(() => p() && (clearInterval(t), res(true)), 20);
    setTimeout(() => (clearInterval(t), res(false)), ms);
  });
const bests = () => out.filter((l) => l.startsWith('bestmove')).length;

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const PRELUDE = 'e2e4 e7e5 g1f3 b8c6 f1c4 f8c5';

send({ engine: 'sargon', ply: 1 });
send('uci');
if (!(await waitFor(() => out.includes('uciok'), 30000))) {
  console.error('FAIL: the engine never started');
  process.exit(2);
}

/** Two searches after a castle spelled `castle`; how many answered. */
const play = async (castle) => {
  let ok = 0;
  for (let i = 0; i < 2; i++) {
    const before = bests();
    send('ucinewgame');
    send(`position fen ${START} moves ${PRELUDE} ${castle}`);
    send('go movetime 300');
    if (await waitFor(() => bests() > before, 6000)) ok++;
  }
  return ok;
};

const standard = await play('e1g1');
console.log(`e1g1 (king two squares): ${standard}/2 searches answered`);

// Deliberately NOT asserted as lethal. It is lethal today, and pinning that
// would be asserting a bug — the same trap `repeat-position.mjs --without` fell
// into, which had to be flipped the day upstream fixed it. What matters is that
// the spelling we SEND works; if morlock ever learns the other one, this still
// passes and simply reports it.
const alternate = await play('e1h1');
console.log(
  `e1h1 (king takes rook):  ${alternate}/2 searches answered` +
    (alternate === 0 ? '   <- rejected, hence GameController.engineUci' : '   <- now tolerated')
);

if (standard < 2) {
  console.error(
    'FAIL: morlock did not accept e1g1, the spelling engineUci converts TO.\n' +
      '      Every castle in a retro game now kills the engine.'
  );
  process.exit(1);
}
process.exit(0);
