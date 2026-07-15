import { readFileSync } from 'node:fs';
import './wasm_exec.js';

globalThis.retroConfig = { engine: 'bernstein', ply: 2 };
const lines = [];
globalThis.onRetroLine = (l) => {
	lines.push(l);
	if (l.startsWith('bestmove')) {
		console.log('OK:', l);
		process.exit(0);
	}
};

const go = new Go();
const { instance } = await WebAssembly.instantiate(readFileSync('./retro.wasm'), go.importObject);
go.run(instance); // resolves when Go exits; engine runs on its own goroutines
await new Promise((r) => setTimeout(r, 300));
retroSend('uci');
await new Promise((r) => setTimeout(r, 300));
console.log('handshake:', lines.filter((l) => l.startsWith('id') || l === 'uciok').join(' | '));
retroSend('isready');
retroSend('position startpos moves e2e4 e7e5');
retroSend('go movetime 1000');
setTimeout(() => { console.log('TIMEOUT', lines.slice(-5)); process.exit(1); }, 15000);
