// The shapes that cross between the brain and whatever is driving a search.
//
// These live here, not in a transport, because both consumers depend on them
// and neither should depend on the other: the Svelte app's WASM worker
// (svelte/src/lib/engine/stockfish.ts) and the Flutter app's arbiter both
// produce these, and the brain's grading and explanation code consumes them.

export interface EngineMove {
	pv: string[];
	score: number;
	mate: number | null;
	depth: number;
	multipv: number;
}

export interface EngineResult {
	moves: EngineMove[];
	bestmove: string;
	depth: number;
}

/// Which historical engine a "retro" bot re-implements, and how deep it looks.
/// The roster (bots.ts) needs this shape; the wasm worker that runs it lives
/// on the app side.
export type RetroEngineName = 'bernstein' | 'sargon' | 'turochamp';

export interface RetroSpec {
	engine: RetroEngineName;
	ply: number;
}

/// One engine's verdict on a position, as an importer needs it: the score from
/// the side to move and the line it saw.
///
/// It lived in the Svelte app's engine pool until that app was retired
/// (2026-07-20). Nothing in the brain produces it — the importers take it from
/// whatever evaluator they are given, a browser worker or a native process —
/// but both importers speak it, so it belongs here rather than in either.
export interface UciEval {
	cp?: number; // side-to-move perspective
	mate?: number;
	pv: string[];
}
