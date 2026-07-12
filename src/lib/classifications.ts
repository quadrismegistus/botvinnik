// Shared presentation for the chess.com-style move classifications: the glyph,
// colour and display noun for each MoveLabel. Used by the review panel, the
// move table and the win-chance graph so they never drift apart.
import type { MoveLabel } from './engine/insights';

export interface Classification {
	glyph: string;
	color: string;
	noun: string; // "a blunder", "the best move" — reads in "Nf6 is {noun}"
	/** dotted on the eval graph (the ones that carry signal) */
	graphed: boolean;
}

export const CLASS: Record<MoveLabel, Classification> = {
	brilliant: { glyph: '‼', color: '#1baca6', noun: 'brilliant', graphed: true },
	great: { glyph: '!', color: '#5b8bb0', noun: 'a great move', graphed: true },
	best: { glyph: '★', color: '#81b64c', noun: 'the best move', graphed: false },
	excellent: { glyph: '✔', color: '#81b64c', noun: 'excellent', graphed: false },
	good: { glyph: '✓', color: '#95b776', noun: 'a good move', graphed: false },
	inaccuracy: { glyph: '?!', color: '#f0c15c', noun: 'an inaccuracy', graphed: true },
	mistake: { glyph: '?', color: '#e6912c', noun: 'a mistake', graphed: true },
	blunder: { glyph: '??', color: '#ca3431', noun: 'a blunder', graphed: true }
};

export const LABEL_ORDER: MoveLabel[] = [
	'brilliant',
	'great',
	'best',
	'excellent',
	'good',
	'inaccuracy',
	'mistake',
	'blunder'
];
