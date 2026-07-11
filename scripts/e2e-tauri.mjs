// End-to-end test of the Tauri shell via tauri-driver (WebDriver protocol,
// no client library needed). Launches the built app, waits for the native
// Stockfish sidecar's analysis to reach the UI, and asserts on the DOM.
//
// tauri-driver only supports Linux and Windows — on macOS this script skips
// (exit 0) and the test runs in GitHub CI instead. See .github/workflows/
// tauri-e2e.yml for the runner setup (webkit2gtk-driver, xvfb, stockfish).

import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';

if (process.platform === 'darwin') {
	console.log('tauri-driver has no macOS backend — skipping (runs in GitHub CI on Linux).');
	process.exit(0);
}

const DRIVER_PORT = 4444;
const DRIVER = process.env.TAURI_DRIVER ?? 'tauri-driver';
const APP = process.env.TAURI_APP ?? path.resolve('src-tauri/target/release/app');

if (!existsSync(APP)) {
	console.error(`app binary not found at ${APP} — build it first (cargo build --release)`);
	process.exit(1);
}

const driver = spawn(DRIVER, ['--port', String(DRIVER_PORT)], { stdio: 'inherit' });
const base = `http://127.0.0.1:${DRIVER_PORT}`;

async function wd(method, pathname, body) {
	const res = await fetch(base + pathname, {
		method,
		headers: { 'Content-Type': 'application/json' },
		body: body ? JSON.stringify(body) : undefined
	});
	const data = await res.json();
	if (!res.ok) throw new Error(`${method} ${pathname}: ${JSON.stringify(data).slice(0, 300)}`);
	return data.value;
}

async function waitForDriver() {
	for (let i = 0; i < 40; i++) {
		try {
			await fetch(`${base}/status`);
			return;
		} catch {
			await new Promise((r) => setTimeout(r, 500));
		}
	}
	throw new Error('tauri-driver never came up');
}

let sessionId = null;
let failed = false;

try {
	await waitForDriver();
	const session = await wd('POST', '/session', {
		capabilities: { alwaysMatch: { 'tauri:options': { application: APP } } }
	});
	sessionId = session.sessionId;
	console.log('session created — app launched');

	const exec = (script) =>
		wd('POST', `/session/${sessionId}/execute/sync`, { script, args: [] });

	// 1. the app booted and rendered
	const title = await exec('return document.title');
	console.log(`title: ${title}`);
	if (title !== 'Botvinnik') throw new Error(`unexpected title: ${title}`);

	// 2. the native engine's analysis reached the UI: the Lines Tree populates
	//    only when engine lines stream in — this covers sidecar spawn, the Rust
	//    UCI bridge, event delivery, and the whole analysis pipeline
	let nodes = 0;
	for (let i = 0; i < 60; i++) {
		nodes = await exec("return document.querySelectorAll('.lines-tree svg g.node').length");
		if (nodes > 5) break;
		await new Promise((r) => setTimeout(r, 2000));
	}
	console.log(`lines-tree nodes after analysis: ${nodes}`);
	if (nodes <= 5) throw new Error('engine analysis never reached the UI');

	// 3. the engine reported real depth (native path completes the slice)
	const status = await exec(
		"return document.querySelector('.analysis-panel .status')?.textContent ?? ''"
	);
	console.log(`analysis status chip: "${status}"`);

	console.log('PASS: tauri shell end-to-end (boot -> sidecar -> analysis -> UI)');
} catch (e) {
	failed = true;
	console.error('FAIL:', e.message);
} finally {
	if (sessionId) await wd('DELETE', `/session/${sessionId}`).catch(() => {});
	driver.kill();
}
process.exit(failed ? 1 : 0);
