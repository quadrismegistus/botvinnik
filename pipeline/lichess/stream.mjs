// Streaming reader: spawns `zstd -dc <file>` and splits the decompressed PGN
// stream into individual game blocks (header lines + movetext, unparsed) —
// one line at a time via readline, never buffering the whole file. A
// multi-GB monthly dump must run at O(1) memory; only the current game's
// lines and the next line off the pipe are ever held.
//
// The zstd CLI, NOT node:zlib's built-in zstd — measured, not preference: a
// real lichess dump is a multi-frame file with skippable frames interleaved
// (2013-01: 6 frames + 3 skips, per `zstd -l`), and `createZstdDecompress`
// dies on the first skippable frame ("Unknown frame descriptor") after
// emitting zero bytes. The fixture e2e-multiframe.pgn.zst pins exactly this
// shape so the dependency never silently regresses to a decoder that cannot
// read the production input.
//
// A lichess dump's games look like:
//
//   [Event "Rated Blitz game"]
//   [Site "..."]
//   ...
//   [Termination "Normal"]
//                              <- exactly one blank line
//   1. e4 e5 2. Nf3 ... 1-0
//                              <- exactly one blank line before the next game
//   [Event "Rated Blitz game"]
//   ...
//
// so a game is complete once a blank line follows at least one non-header
// (movetext) line. That rule is what `splitGameBlocks` implements; it takes
// plain lines so it can be tested without spawning zstd.
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';

/** @param {AsyncIterable<string>|Iterable<string>} lines */
export async function* splitGameBlocks(lines) {
	let buf = [];
	let sawMoveLine = false;
	for await (const line of lines) {
		if (line.trim() === '') {
			if (sawMoveLine) {
				if (buf.length > 0) yield buf.join('\n');
				buf = [];
				sawMoveLine = false;
			}
			// a blank line between headers and movetext (or stray blank lines
			// before the first game) carries no information — skip it
			continue;
		}
		buf.push(line);
		if (line[0] !== '[') sawMoveLine = true;
	}
	if (sawMoveLine && buf.length > 0) yield buf.join('\n');
}

/**
 * Decompress `zstFile` with the zstd CLI and yield one raw game-text block
 * per game.
 *
 * Exit handling carries a scar: the first version killed the child in its
 * `finally` even after the stream had ended NATURALLY, then judged the
 * self-inflicted signal exit ("exited null") as a decompression failure —
 * green locally, red on CI, purely a race on how fast zstd exits after
 * closing stdout. The rule now: only kill when the CONSUMER abandoned the
 * loop early, and only judge the exit code of a process we did not signal.
 *
 * @param {string} zstFile
 */
export async function* streamGames(zstFile) {
	const proc = spawn('zstd', ['-dc', zstFile], { stdio: ['ignore', 'pipe', 'pipe'] });
	let stderrBuf = '';
	proc.stderr.on('data', (d) => {
		stderrBuf += d.toString();
	});
	// spawn() failures (ENOENT: no zstd on PATH, permissions) surface as an
	// 'error' event, not a throw — capture it so the code below can report it
	// instead of hanging or failing silently.
	let spawnError = null;
	proc.on('error', (err) => {
		spawnError = err;
	});
	const closed = new Promise((resolve) => proc.once('close', (code) => resolve(code)));

	const rl = createInterface({ input: proc.stdout, crlfDelay: Infinity });
	let ranDry = false;
	try {
		yield* splitGameBlocks(rl);
		ranDry = true; // the pipe ended on its own — zstd is done or dying, not abandoned
	} finally {
		rl.close();
		if (!ranDry) proc.kill(); // early break (--max-games): the kill is ours
	}

	if (spawnError) throw new Error(`streamGames: failed to spawn zstd: ${spawnError.message}`);
	if (ranDry) {
		const code = await closed;
		// A corrupt or truncated file ends the pipe early with a nonzero exit —
		// that must FAIL LOUDLY here, never write plausible tables from a
		// partial read. (The node:zlib experiment failed worse: zero bytes, no
		// error surfaced, "done: 0 streamed" — silent truncation in person.)
		if (code !== 0) {
			throw new Error(`streamGames: zstd -dc ${zstFile} exited ${code}: ${stderrBuf.trim()}`);
		}
	}
}
