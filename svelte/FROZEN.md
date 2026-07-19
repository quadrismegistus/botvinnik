# This app is frozen

Decided 2026-07-19. **No new features here.** Effort goes to `flutter/`, which
is to own every target including web.

Frozen does not mean dead. Until Flutter web can replace it, this app:

- still serves **botvinnik.app** — it is the shipping product, not a legacy copy
- still gets **bug fixes**, and still has to keep working when `brain/` changes
- still runs in CI (`web-e2e`), which is what makes that last point true

## Why it is still here

Flutter web cannot replace it yet for one remaining reason: it plays **26 of
the 35 personas** (retro #36, Garbo #37) — and parity is 32, not 35, because
Dala is desktop-only here too. So the gap is **Maia, and only Maia**. The
other two gaps closed on
2026-07-19 — it is now a real PWA that works offline and makes no third-party
requests, and its cold-load payload was accepted as fine for an installable
chess app (see ROADMAP.md for the numbers).

And a fourth reason that is easy to miss: **this app is the reference
implementation** for what Flutter still lacks — Maia (`lib/engine/maia.ts`),
and Dala (`lib/engine/dala.ts`) for the desktop build. Porting those to
Flutter means porting *from here*. Deleting this app while M5 is in flight
would delete the source.

`lib/engine/retro.ts` and `lib/engine/garbo.ts` are the worked examples of
what that porting looks like: `flutter/lib/engine/retro_engine_web.dart` and
`garbo_engine_web.dart` are direct translations of them, down to the worker
protocols and the timeouts, and the comments in each point at the other.

## If you are about to add something

Add it to `flutter/` instead. If it genuinely has to ship on the web this
week, that is a real reason — do it, and note it here so the freeze stays
honest rather than quietly untrue.
