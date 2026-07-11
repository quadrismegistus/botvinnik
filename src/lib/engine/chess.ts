import { Chess, type Move, type Square } from 'chess.js';

export type { Move, Square };

export interface GameState {
	fen: string;
	turn: 'w' | 'b';
	moves: Move[];
	isGameOver: boolean;
	result: string | null;
	legalMoves: { from: Square; to: Square }[];
}

let game = new Chess();

export function getState(): GameState {
	const moves = game.history({ verbose: true });
	const legalMoves = game.moves({ verbose: true }).map((m) => ({ from: m.from, to: m.to }));

	let result: string | null = null;
	if (game.isCheckmate()) result = game.turn() === 'w' ? '0-1' : '1-0';
	else if (game.isDraw()) result = '1/2-1/2';
	else if (game.isStalemate()) result = '1/2-1/2';

	return {
		fen: game.fen(),
		turn: game.turn(),
		moves,
		isGameOver: game.isGameOver(),
		result,
		legalMoves
	};
}

export function makeMove(from: string, to: string, promotion?: string): Move | null {
	try {
		return game.move({ from: from as Square, to: to as Square, promotion: promotion || undefined });
	} catch {
		return null;
	}
}

export function reset() {
	game = new Chess();
}

export function undo(): Move | null {
	return game.undo();
}

export function loadFen(fen: string) {
	game = new Chess(fen);
}

export function getPgn(headers: Record<string, string> = {}): string {
	// chess.js 1.x renamed header() to setHeader() — support both
	const g = game as unknown as {
		setHeader?: (k: string, v: string) => void;
		header?: (...args: string[]) => void;
		pgn: () => string;
	};
	for (const [k, v] of Object.entries(headers)) {
		if (typeof g.setHeader === 'function') g.setHeader(k, v);
		else g.header?.(k, v);
	}
	return g.pgn();
}

export function isPromotionMove(from: string, to: string): boolean {
	const piece = game.get(from as Square);
	return piece?.type === 'p' && (to[1] === '8' || to[1] === '1');
}

export function uciToSquares(uci: string): { from: Square; to: Square } {
	return {
		from: uci.slice(0, 2) as Square,
		to: uci.slice(2, 4) as Square
	};
}

export interface SanStep {
	san: string;
	uci: string;
	color: 'w' | 'b';
	piece: string;
}

export function getSanLine(fen: string, ucis: string[]): SanStep[] {
	const steps: SanStep[] = [];
	try {
		const tmp = new Chess(fen);
		for (const uci of ucis) {
			const move = tmp.move({
				from: uci.slice(0, 2) as Square,
				to: uci.slice(2, 4) as Square,
				promotion: uci.length > 4 ? uci[4] : undefined
			});
			if (!move) break;
			steps.push({ san: move.san, uci, color: move.color, piece: move.piece });
		}
	} catch {
		// stop at first illegal move; return what we have
	}
	return steps;
}

export function getFenAfter(fen: string, uci: string): string | null {
	try {
		const tmp = new Chess(fen);
		tmp.move({
			from: uci.slice(0, 2) as Square,
			to: uci.slice(2, 4) as Square,
			promotion: uci.length > 4 ? uci[4] : undefined
		});
		return tmp.fen();
	} catch {
		return null;
	}
}

// standard numbered notation from an arbitrary position:
// "3...Nxd5 4.Bc4 Qe7+ 5.Kf1" (leading "N..." when Black moves first)
export function getNumberedSanLine(fen: string, ucis: string[], max = 12): string {
	const parts: string[] = [];
	try {
		const tmp = new Chess(fen);
		for (const uci of ucis.slice(0, max)) {
			const num = Number(tmp.fen().split(' ')[5]);
			const move = tmp.move({
				from: uci.slice(0, 2) as Square,
				to: uci.slice(2, 4) as Square,
				promotion: uci.length > 4 ? uci[4] : undefined
			});
			if (!move) break;
			if (move.color === 'w') parts.push(`${num}.${move.san}`);
			else if (parts.length === 0) parts.push(`${num}...${move.san}`);
			else parts.push(move.san);
		}
	} catch {
		// stop at first illegal move; return what we have
	}
	return parts.join(' ');
}

export function getSan(fen: string, uci: string): string {
	try {
		const tmp = new Chess(fen);
		const from = uci.slice(0, 2) as Square;
		const to = uci.slice(2, 4) as Square;
		const promotion = uci.length > 4 ? uci[4] : undefined;
		const move = tmp.move({ from, to, promotion });
		return move?.san || uci;
	} catch {
		return uci;
	}
}
