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
// ONLY `without` IS A GATE. Both modes assert, but only one discriminates:
//
//   `with`    — diagnostic, not gated. On an engine carrying the fix it is
//               `without` plus a `ucinewgame`, and `without` already passes,
//               so it cannot fail whatever that line does. Mutation-tested:
//               delete the send it exists to exercise and it still reports
//               4/4. Useful for telling apart "the engine regressed" from
//               "the client stopped protecting us" once something IS red, and
//               worthless as a gate before that. The client's real contract
//               is flutter/test/retro_commands_test.dart's job.
//   `without` — that the committed wasm carries the ENGINE fix
//               (herohde/morlock#6, upstream 63db3e6a). It used to be a
//               demonstration that could not be a gate, because it asserted a
//               bug and would start failing the day upstream fixed it. That
//               day came, so it flips from documenting the bug to detecting
//               its return.
//
// To be exact about what fails what, since this file's own first draft got it
// wrong: the only input here is vendor/retro/, so what trips `without` is a
// rollback of the WASM. Editing vendor/retro/MORLOCK_REV trips
// scripts/check-retro-provenance.sh instead. Behaviour and label are checked
// by different gates, which is the point of having both.

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
// Check the handshake rather than discarding it. A missing, truncated or
// non-wasm artefact used to spend 35s failing and then report "engine gone" —
// wrong, and wrong in a way that sends you looking at the engine instead of at
// the file. The real cause (`__boot_failed__ CompileError: … expected magic
// word`) was already on stdout and ignored. Distinct exit code: this is an
// infrastructure failure, not a verdict about the engine.
// Resolve on the failure too, not just the success: the worker already posts
// `__boot_failed__` the moment the wasm will not compile, so waiting the full
// 30s for a uciok that provably is not coming is dead time in every CI run
// that has a broken artefact.
const booted = () => out.includes('uciok');
const bootFailed = () => out.some((l) => l.startsWith('__boot_failed__'));
if (!(await waitFor(() => booted() || bootFailed(), 30000)) || bootFailed()) {
  console.error('FAIL: the engine never started. Last lines:');
  console.error(out.slice(-5).join('\n'));
  process.exit(2);
}

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
// ENGINE regressed — the committed wasm no longer carries herohde/morlock#6.
// A failure in both means the CLIENT's `ucinewgame` stopped being sent.
if (survived < 4) {
  console.error(`FAIL (${mode}): only ${survived}/4 searches answered`);
  process.exit(1);
}
process.exit(0);
