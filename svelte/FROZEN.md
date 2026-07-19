# This app is frozen

Decided 2026-07-19. **No new features here.** Effort goes to `flutter/`, which
is to own every target including web.

Frozen does not mean dead. Until Flutter web can replace it, this app:

- still serves **botvinnik.app** — it is the shipping product, not a legacy copy
- still gets **bug fixes**, and still has to keep working when `brain/` changes
- still runs in CI (`web-e2e`), which is what makes that last point true

## Why it is still here

Flutter web cannot replace it yet, on two measured counts (see ROADMAP.md for
the numbers): it is usable 16s after a cold click on fast 4G against this
app's 0.5s — because Flutter's splash blocks on the whole 17MB, where this
app paints a board after 0.4MB — and it plays 22 of the 35 personas. *Offline was the third and closed on 2026-07-19* — Flutter web is
now a real PWA that also makes no third-party requests.

And a fourth reason that is easy to miss: **this app is the reference
implementation** for the persona families Flutter still lacks — Maia
(`lib/engine/maia.ts`), retro (`lib/engine/retro.ts`), Garbo
(`lib/engine/garbo.ts`) and Dala (`lib/engine/dala.ts`). Porting those to
Flutter means porting *from here*. Deleting this app while M5 is in flight
would delete the source.

## If you are about to add something

Add it to `flutter/` instead. If it genuinely has to ship on the web this
week, that is a real reason — do it, and note it here so the freeze stays
honest rather than quietly untrue.
