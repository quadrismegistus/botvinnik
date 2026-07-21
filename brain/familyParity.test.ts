// Bot family strings are hardcoded in Dart and compared against values that
// cross the JS bridge from here. Nothing in either language's type system spans
// that gap, so a rename on one side is silent on the other.
//
// It is not a small silence: `_playableFamilies` is the `.where` filter on the
// roster picker, so a stale literal drops every persona of that family out of
// the picker entirely, and `_familyMark` falls through to a default glyph. The
// #139 rename changed both correctly — and reverting either one left all 126
// Flutter tests green, which is why this file exists.
//
// Reading Dart from a TypeScript test is unusual. It lives here because this is
// where the source of truth is: BotFamily and PERSONAS are defined in bots.ts.

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { PERSONAS } from './bots';

const ROSTER_PICKER = resolve(__dirname, '../flutter/lib/ui/roster_picker.dart');

/** Every family the real roster actually emits. */
const realFamilies = new Set(PERSONAS.map((p) => p.family));

/** Single-quoted strings inside a named Dart block, brace-matched. */
function dartStringsIn(source: string, marker: string): string[] {
	// The marker must name the DEFINITION, not the symbol: each of these is
	// both defined and used in this file, and indexOf/lastIndexOf pick the
	// wrong one for opposite reasons.
	const start = source.indexOf(marker);
	expect(start, `${marker} not found — did it get renamed?`).toBeGreaterThan(-1);
	let depth = 0;
	let i = source.indexOf('{', start);
	const open = i;
	for (; i < source.length; i++) {
		if (source[i] === '{') depth++;
		else if (source[i] === '}' && --depth === 0) break;
	}
	return [...source.slice(open, i).matchAll(/'([a-z][a-z0-9_]*)'/g)].map((m) => m[1]);
}

describe('Dart family literals match the roster', () => {
	const src = readFileSync(ROSTER_PICKER, 'utf8');

	it('_playableFamilies names only families that exist', () => {
		const named = dartStringsIn(src, 'final _playableFamilies');
		expect(named.length).toBeGreaterThan(0);
		for (const f of named) {
			expect(realFamilies, `roster_picker lists '${f}', which no persona has`).toContain(f);
		}
	});

	it('_familyMark has a glyph for every playable family', () => {
		// A family in the filter but missing from the switch renders the silent
		// default glyph rather than failing, so this cannot be caught by eye.
		const playable = dartStringsIn(src, 'final _playableFamilies');
		const marked = new Set(dartStringsIn(src, 'Widget _familyMark'));
		for (const f of playable) {
			expect(marked, `no _familyMark case for '${f}'`).toContain(f);
		}
	});
});
