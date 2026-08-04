// Streaming reader: spawns `zstd -dc <file>` and splits the decompressed PGN
// stream into individual game blocks (header lines + movetext, unparsed) —
// one line at a time via readline, never buffering the whole file. A
// multi-GB monthly dump must run at O(1) memory; only the current game's
// lines and the next line off the pipe are ever held.
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
 * per game. Stops the child process cleanly if the consumer breaks out of
 * the loop early (e.g. `--max-games`).
 *
 * @param {string} zstFile
 */
export async function* streamGames(zstFile) {
	const proc = spawn('zstd', ['-dc', zstFile], { stdio: ['ignore', 'pipe', 'pipe'] });
	let stderrBuf = '';
	proc.stderr.on('data', (d) => {
		stderrBuf += d.toString();
	});
	// spawn() failures (e.g. ENOENT: no zstd on PATH, or the file is missing)
	// surface as an 'error' event, not a throw — capture it so the loop below
	// can report it instead of hanging or failing silently.
	let spawnError = null;
	proc.on('error', (err) => {
		spawnError = err;
	});

	const rl = createInterface({ input: proc.stdout, crlfDelay: Infinity });

	try {
		yield* splitGameBlocks(rl);
	} finally {
		rl.close();
		if (proc.exitCode === null && !proc.killed) proc.kill();
	}

	if (spawnError) throw new Error(`streamGames: failed to spawn zstd: ${spawnError.message}`);

	const exitCode = await new Promise((resolve) => {
		if (proc.exitCode !== null) resolve(proc.exitCode);
		else proc.once('close', resolve);
	});
	if (exitCode !== 0) {
		throw new Error(`streamGames: zstd -dc ${zstFile} exited ${exitCode}: ${stderrBuf.trim()}`);
	}
}
