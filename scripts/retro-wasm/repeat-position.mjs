// Regression probe for the bug that made TUROCHAMP hand its game to a
// Stockfish stand-in: morlock's UCI driver treats a `position` line that
// prefixes the last one as a continuation and parses the remainder as moves,
// so an IDENTICAL line leaves "", fails, and RETURNS from the driver — which
// ends main() and the Go program. Starting a second game re-sends the same
// opening FEN, so it took exactly one new game to hit.
//
// Runs the real worker outside a browser, no build required:
//   node scripts/retro-wasm/repeat-position.mjs with      # the client's half
//   node scripts/retro-wasm/repeat-position.mjs without   # the engine's half
//
// The client sends `ucinewgame` before every position, which resets the
// driver's lastPosition and takes the reset path it would have taken anyway.
//
// BOTH MODES NOW ASSERT, and they assert different halves of the fix:
//
//   `with`    — the client's contract. Four searches from an identical
//               position must all answer. This is the one that would still
//               matter if morlock had never been patched.
//   `without` — that the committed wasm carries the ENGINE fix
//               (herohde/morlock#6, upstream 63db3e6a). It used to be a
//               demonstration that could not be a gate, because it asserted a
//               bug and would start failing the day upstream fixed it. That
//               day came, so it flips from documenting the bug to detecting
//               its return — a rollback of vendor/retro/MORLOCK_REV fails
//               here. That is a behavioural check on the artefact, where
//               scripts/check-retro-provenance.sh only checks its label.

// Drive vendor/retro/retro-worker.js outside a browser: shim `self`,
// importScripts and fetch, then ask the SAME worker for two searches in a row.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// fileURLToPath, not .pathname: the latter stays percent-encoded, so any
// checkout under a directory with a space in it reads 'a%20b' and ENOENTs.
const dir = fileURLToPath(new URL('../../vendor/retro/', import.meta.url));

globalThis.self = globalThis;
globalThis.importScripts = (f) => {
  (0, eval)(readFileSync(`${dir}/${f}`, 'utf8'));
};
globalThis.fetch = async () =>
  new Response(readFileSync(`${dir}/retro.wasm`), {
    headers: { 'content-type': 'application/wasm' },
  });

const out = [];
globalThis.postMessage = (m) => {
  const s = String(m);
  out.push(s);
  if (s.startsWith('bestmove') || s.startsWith('__') || s === 'uciok')
    console.log('  <-', s);
};

let onmsg = null;
Object.defineProperty(globalThis, 'onmessage', {
  get: () => onmsg,
  set: (f) => (onmsg = f),
});

(0, eval)(readFileSync(`${dir}/retro-worker.js`, 'utf8'));

const send = (data) => onmsg({ data });
const waitFor = (pred, ms) =>
  new Promise((res) => {
    const t = setInterval(() => {
      if (pred()) {
        clearInterval(t);
        res(true);
      }
    }, 20);
    setTimeout(() => {
      clearInterval(t);
      res(false);
    }, ms);
  });


const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const mode = process.argv[2] || 'without';
send({ engine: 'turochamp', ply: 1 });
send('uci');
await waitFor(() => out.includes('uciok'), 30000);

const search = async (n) => {
  const before = out.filter((l) => l.startsWith('bestmove')).length;
  if (mode === 'with') send('ucinewgame');       // the fix
  send(`position fen ${START}`);                  // IDENTICAL line each time
  send('go movetime 300');
  const ok = await waitFor(
    () => out.filter((l) => l.startsWith('bestmove')).length > before, 5000);
  console.log(`  search ${n} (same position): ${ok ? 'bestmove ok' : 'NO bestmove — engine gone'}`);
  return ok;
};

console.log(`--- ${mode} ucinewgame ---`);
let survived = 0;
for (let i = 1; i <= 4; i++) {
  await new Promise((r) => setTimeout(r, 250));
  if (!(await search(i))) break;
  survived++;
}

// EXIT CODES, so this can gate rather than merely narrate. It used to
// `process.exit(0)` unconditionally, which meant a run that watched the engine
// die still reported success — the exact shape of green-for-the-wrong-reason
// this repo has been bitten by before.
//
// Both modes now demand all four searches; see the header for why they are
// separate assertions rather than one. A failure in `without` alone means the
// ENGINE regressed — the pin moved off a revision carrying herohde/morlock#6.
// A failure in both means the CLIENT's `ucinewgame` stopped being sent.
if (survived < 4) {
  console.error(`FAIL (${mode}): only ${survived}/4 searches answered`);
  process.exit(1);
}
process.exit(0);
