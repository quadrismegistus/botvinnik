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
const PLAYABLE_FAMILIES = resolve(
	__dirname,
	'../flutter/lib/engine/playable_families.dart'
);

/** Every family the real roster actually emits. */
const realFamilies = new Set(PERSONAS.map((p) => p.family));

/** Families that exist only at RUNTIME on the Dart side (user-added engines,
 * #183), never in the brain PERSONAS. They still need a `_familyMark` glyph,
 * but by definition no persona here carries them. */
const dynamicFamilies = new Set(['custom', 'rodent', 'brainlearn']);

/** Single-quoted strings inside a named Dart block, brace-matched.
 *
 * `marker` must name the DEFINITION, not the symbol: each of these is both
 * defined and used in its file, and indexOf/lastIndexOf pick the wrong one for
 * opposite reasons.
 *
 * The brace must open within `maxGap` characters of the marker. Without that
 * bound this function silently matched the WRONG BLOCK: when
 * `_playableFamilies` briefly became a one-line alias with no braces of its
 * own, `indexOf('{')` ran on to the next class body and this returned the
 * family names it found in a DOC COMMENT there — one string, so even
 * `toBeGreaterThan(0)` passed, and both tests went green while the regression
 * they exist to catch was live in the file.
 */
function dartStringsIn(source: string, marker: string, maxGap = 24): string[] {
	// EVERY occurrence is considered, not just the first. These markers also
	// appear in doc comments — roster_picker's own comment says the declaration
	// "has to keep starting `Widget _familyMark`" — and indexOf lands there.
	//
	// The chosen occurrence is the first whose block opens within maxGap: 24
	// covers a literal (` = {`, 3) and a signature (`(String family) {`, 16),
	// while rejecting both a doc-comment mention and an alias, whose next brace
	// is some other declaration hundreds of characters away. That alias case is
	// not hypothetical — it silently pointed this parser at a neighbouring
	// class, where it matched family names in a comment and passed.
	let open = -1;
	for (let at = source.indexOf(marker); at !== -1; at = source.indexOf(marker, at + 1)) {
		const brace = source.indexOf('{', at);
		if (brace !== -1 && brace - (at + marker.length) <= maxGap) {
			open = brace;
			break;
		}
	}
	expect(
		open,
		`${marker}: no declaration found whose block opens within ${maxGap} ` +
			`chars — renamed, or turned into an alias?`
	).toBeGreaterThan(-1);
	let depth = 0;
	let i = open;
	for (; i < source.length; i++) {
		if (source[i] === '{') depth++;
		else if (source[i] === '}' && --depth === 0) break;
	}
	const block = source.slice(open, i);
	// KEYS only. _familyNeeds is a map from family to the capability it needs,
	// so a plain string match also returns 'ort', 'process' and friends — which
	// are not families and have no persona and no glyph.
	const keys = [...block.matchAll(/'([a-z][a-z0-9_]*)'\s*:/g)].map((m) => m[1]);
	if (keys.length) return keys;
	return [...block.matchAll(/'([a-z][a-z0-9_]*)'/g)].map((m) => m[1]);
}

describe('Dart family literals match the roster', () => {
	const src = readFileSync(ROSTER_PICKER, 'utf8');
	const families = readFileSync(PLAYABLE_FAMILIES, 'utf8');

	// The capability whitelist moved out of roster_picker into its own file so
	// both pickers and the roster itself read one answer, and it is a literal
	// map there precisely so this stays readable from here.
	const MARKER = 'const _familyNeeds';

	it('the playable whitelist names only families that exist', () => {
		const named = dartStringsIn(families, MARKER);
		expect(named.length).toBeGreaterThan(3);
		for (const f of named) {
			if (dynamicFamilies.has(f)) continue; // Dart-only; has no brain persona
			expect(realFamilies, `roster_picker lists '${f}', which no persona has`).toContain(f);
		}
	});

	it('_familyMark has a glyph for every playable family', () => {
		// A family in the filter but missing from the switch renders the silent
		// default glyph rather than failing, so this cannot be caught by eye.
		const playable = dartStringsIn(families, MARKER);
		const marked = new Set(dartStringsIn(src, 'Widget _familyMark'));
		for (const f of playable) {
			expect(marked, `no _familyMark case for '${f}'`).toContain(f);
		}
	});

	it('every family the brain ships is in the whitelist', () => {
		// THE OTHER DIRECTION, and it was missing: the test that used to sit here
		// had a body identical to the first one, so both checked whitelist ->
		// PERSONAS and nothing checked PERSONAS -> whitelist. Deleting a family
		// from _familyNeeds was therefore caught by nothing in either language —
		// the Flutter suite stayed green and so did this file — while every
		// persona of that family vanished from both pickers on the platforms
		// that can play it.
		const named = new Set(dartStringsIn(families, MARKER));
		for (const f of realFamilies) {
			// dala is nativeOnly AND unimplemented (#45: it wants an lc0 sidecar
			// nobody built), so it is deliberately absent. Whitelisting it would
			// offer three personas that quietly play as a Stockfish stand-in
			// under Dala's name, which is the substitution #117 exists to stop.
			if (f === 'dala') continue;
			expect(named, `no persona family '${f}' in the Dart whitelist`).toContain(f);
		}
	});

	it('no capability is the AND of two different engines', () => {
		// Source-level, because no test platform can see this one. `ort` was
		// `MaiaEngine.supported && ChessGptEngine.supported` — two engines with
		// DIFFERENT web answers collapsed onto one flag. On macOS both are true
		// and on CI's ubuntu both are false, so every Dart test agreed with the
		// broken expression; only the browser disagreed, where Maia has a wasm
		// worker (true) and ChessGPT has nothing (false). Result: `true && false`
		// and BOTH families dropped out of every picker on botvinnik.app, the
		// deploy Flutter owns.
		//
		// The invariant that survives it: each capability argument is exactly one
		// `Something.supported`, so two engines can never share a fate again.
		// Anchored on the DEFINITION, not the bare symbol — the same trap
		// dartStringsIn documents at length. A plain indexOf lands in the doc
		// comment above [wantsNativeRoster], and the slice from there ran through
		// prose ("Rodent", "Stockfish") that looks enough like Dart to fail for
		// the wrong reason.
		const DEF = '_realPlayableFamilies = familiesFor(';
		const at = families.indexOf(DEF);
		expect(at, `${DEF} not found`).toBeGreaterThan(-1);
		const call = families.slice(at + DEF.length, families.indexOf(');', at));
		const args = call
			.split(',')
			.map((a) => a.trim())
			.filter(Boolean);
		expect(args.length).toBeGreaterThan(3);
		for (const arg of args) {
			const value = arg.slice(arg.indexOf(':') + 1).trim();
			expect(
				value,
				`'${arg}' combines engines; give each capability its own key in _familyNeeds instead`
			).toMatch(/^[A-Za-z]+\.supported$/);
		}
	});
});
