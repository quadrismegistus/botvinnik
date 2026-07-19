import { describe, it, expect } from 'vitest';
import { readFileSync, existsSync } from 'node:fs';
import { CLASS } from './classifications';

// The brain ships display strings that the FLUTTER app renders in its own
// bundled font. That makes an exotic glyph here a network request there:
// Flutter web downloads a Noto fallback from fonts.gstatic.com for any
// codepoint no bundled font covers, so `★` (best), `✔` (excellent) and `✓`
// (good) each pulled a third-party font on the verdict line under the board —
// on every graded move, and unservable on a cold offline start.
//
// That was found only after shipping, because the audit had covered
// flutter/lib and stopped there. The rule has to hold wherever a display
// string ORIGINATES, which includes here.
//
// Flutter now substitutes icons for those three (ClassTable.glyphSpan), so
// this test does not demand Roboto coverage — it demands that any glyph
// WITHOUT coverage is one Flutter knows to substitute. Add a glyph Roboto
// lacks and forget the substitution, and this fails.

const FONT = 'flutter/assets/fonts/Roboto-Regular.ttf';
/** Kept in step with ClassTable._iconGlyphs in flutter/lib/ui/grade_strip.dart. */
const SUBSTITUTED = new Set(['best', 'excellent', 'good']);

/** Codepoints in a TrueType cmap, read directly so there is no font tooling dep. */
function cmapCodepoints(path: string): Set<number> {
	const b = readFileSync(path);
	const numTables = b.readUInt16BE(4);
	let cmapOff = 0;
	for (let i = 0; i < numTables; i++) {
		const rec = 12 + i * 16;
		if (b.toString('ascii', rec, rec + 4) === 'cmap') cmapOff = b.readUInt32BE(rec + 8);
	}
	if (!cmapOff) throw new Error('no cmap table');
	const out = new Set<number>();
	const n = b.readUInt16BE(cmapOff + 2);
	for (let i = 0; i < n; i++) {
		const enc = cmapOff + 4 + i * 8;
		const sub = cmapOff + b.readUInt32BE(enc + 4);
		if (b.readUInt16BE(sub) !== 4) continue; // format 4 covers the BMP
		const segX2 = b.readUInt16BE(sub + 6);
		const ends = sub + 14;
		const starts = ends + segX2 + 2;
		const deltas = starts + segX2;
		const ranges = deltas + segX2;
		for (let s = 0; s < segX2 / 2; s++) {
			const end = b.readUInt16BE(ends + s * 2);
			const start = b.readUInt16BE(starts + s * 2);
			const delta = b.readInt16BE(deltas + s * 2);
			const rangeOff = b.readUInt16BE(ranges + s * 2);
			if (start === 0xffff) continue;
			for (let c = start; c <= end && c !== 0x10000; c++) {
				let g: number;
				if (rangeOff === 0) g = (c + delta) & 0xffff;
				else {
					const gi = ranges + s * 2 + rangeOff + (c - start) * 2;
					if (gi + 1 >= b.length) continue;
					g = b.readUInt16BE(gi);
					if (g !== 0) g = (g + delta) & 0xffff;
				}
				if (g !== 0) out.add(c);
			}
		}
	}
	return out;
}

describe('CLASS glyphs vs the font Flutter bundles', () => {
	it.skipIf(!existsSync(FONT))('every glyph is covered or deliberately substituted', () => {
		const covered = cmapCodepoints(FONT);
		const offenders: string[] = [];
		for (const [label, entry] of Object.entries(CLASS)) {
			if (SUBSTITUTED.has(label)) continue;
			for (const ch of entry.glyph) {
				if (!covered.has(ch.codePointAt(0)!)) {
					offenders.push(`${label}: ${ch} (U+${ch.codePointAt(0)!.toString(16).toUpperCase()})`);
				}
			}
		}
		expect(
			offenders,
			'these glyphs are in no bundled font, so Flutter web will fetch one from ' +
				'fonts.gstatic.com to draw them — either pick a covered character or add ' +
				'the label to ClassTable._iconGlyphs and to SUBSTITUTED here'
		).toEqual([]);
	});

	it('the substituted set is exactly the glyphs Roboto lacks — no more, no less', () => {
		if (!existsSync(FONT)) return;
		const covered = cmapCodepoints(FONT);
		// a label that no longer needs substituting should be un-substituted, so
		// the icon mapping does not quietly outlive its reason
		for (const label of SUBSTITUTED) {
			const glyph = CLASS[label as keyof typeof CLASS]?.glyph;
			if (!glyph) continue;
			const missing = [...glyph].some((ch) => !covered.has(ch.codePointAt(0)!));
			expect(missing, `${label} (${glyph}) is covered by Roboto now — drop the substitution`)
				.toBe(true);
		}
	});
});
