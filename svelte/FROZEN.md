# This app is frozen

Decided 2026-07-19. **No new features here.** Effort goes to `flutter/`, which
is to own every target including web.

**It no longer serves botvinnik.app.** The Flutter web app took the apex on
2026-07-19, once the roster reached parity. This app:

- is **no longer the shipping product** — `pages.yml` deploys `flutter/`
- still gets **bug fixes**, and still has to keep working when `brain/` changes
- still runs in CI (`web-e2e`), which is what makes that last point true
- is still the **reference implementation for Dala**, which no browser can run

Rolling back is a two-line revert of `pages.yml` (`npm run build`, `path:
build`) — nothing about the switch is one-way.

Note `flutter/web/service-worker.js`: a tombstone at THIS app's worker path,
which unregisters it and drops its caches. It is not optional. This app's
worker is cache-first for the app shell, so without it a returning browser
keeps serving the cached Svelte `index.html` forever and the new app never
loads. Verified by simulating the deploy on one origin: with the tombstone,
the browser lands on Flutter immediately; without it, it was still serving
Svelte after a full reload.

## Why it is still here

**As of 2026-07-19 (#38), Flutter web is at parity.** It plays 32 of the 35
personas, and 32 is the ceiling for any browser: Dala needs a native lc0
sidecar and is desktop-only here too. It is also a real PWA that works
offline, makes no third-party request unless you pick a Maia, and has a
cold-load payload accepted as fine for an installable chess app (see
ROADMAP.md for the numbers).

So this app is now kept for the **switch**, not for the gap. What is left is
deploying Flutter web in its place — `pages.yml` still builds this one — and
whatever soak-testing that deserves.

It is still the reference implementation for **Dala**
(`lib/engine/dala.ts`), which no browser can run, and for the desktop build
generally. That is the last thing here that exists nowhere else.

Everything else has a Flutter counterpart now, each a direct translation with
comments pointing back: `retro.ts` → `retro_engine_web.dart`, `garbo.ts` →
`garbo_engine_web.dart`, `maia.ts` → `flutter/web_src/maia-worker.ts`. Maia
went further — its pure half (`encoding`, `decoding`, `policyIndex`) moved
into `brain/maia/` and is now shared by both apps rather than duplicated, so
this app imports it from `$brain` too.

## If you are about to add something

Add it to `flutter/` instead. If it genuinely has to ship on the web this
week, that is a real reason — do it, and note it here so the freeze stays
honest rather than quietly untrue.
