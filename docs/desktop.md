# Desktop

**Flutter owns desktop.** The macOS app is `flutter/`, the same codebase as
iOS and Android — a feature added for the phone lands on the desktop for free,
which is the whole argument.

```sh
cd flutter && flutter run -d macos
```

### Iterate in the browser, not on macOS

For UI work, run the web target instead:

```sh
cd flutter && ./stage-web-assets.sh && flutter run -d chrome
```

**Web is the only target with working hot reload** — measured at ~150ms,
against a ~78s cold rebuild for macOS. The Stockfish isolate on the native
targets hangs hot reload, so every change there costs a full restart.

The rendering is the same Skia either way, so layout and theming work
translates directly. What does NOT translate, and still needs a native run
before you trust it: `ProcessEngine` (desktop spawns a real binary, web talks
to a Worker), sqflite (native SQLite vs sqlite3 WASM), and anything about
window management or the macOS sandbox. The engine also differs — web runs
the calibrated WASM lite build, macOS runs whatever binary it finds — so
compare bot strength on the target you mean.

The engine is a real Stockfish binary talking UCI over stdin/stdout
(`lib/engine/process_engine.dart`), looked up in the app bundle first so it
works under the macOS sandbox. Stage it once:

```sh
cp "$(which stockfish)" flutter/macos/Runner/Resources/stockfish
```

Without it the app falls back to a Homebrew install, which **works but is not
the calibrated engine** — bot strength is budgeted by movetime, so a different
engine build silently plays at a different strength. Fine for development,
wrong for any calibration run.

## The Tauri shell is gone

`svelte/src-tauri` wrapped the SvelteKit app as a desktop binary. It worked,
and it had one genuine advantage the Flutter build does not: it ran the same
Stockfish WASM the web app ran, so persona calibration was correct by
construction, where the Flutter desktop build spawns a native binary instead.

It lost anyway, because sharing one UI across phone, tablet and desktop is
worth more than that, and maintaining two desktop shells for one person is
not. It was parked on 2026-07-19 and removed with the rest of the Svelte app
on 2026-07-20.

Everything is preserved at the `svelte-eol` tag, including `src-tauri/`, its
Rust sidecar code and its two CI workflows:

```sh
git checkout svelte-eol
```

The calibration point it raised did not go away with it — see #104, which is
the Flutter app running WASM-calibrated personas against a native engine.

## Known gaps in the Flutter desktop build

- The bundled engines sit in `Contents/MacOS` and are signed in the same build
  phase as they are copied, which is the layout notarization requires —
  executable code in `Contents/Resources` is treated as data and rejected.
  Locally that signature is ad-hoc, through the identical code path; a real one
  needs a Developer ID certificate, and therefore a paid Apple Developer
  Program membership.
- Windows and Linux targets are not scaffolded. The engine side is the easy
  part (`ProcessEngine` already looks for `stockfish.exe` next to the
  executable); `sqflite` is the real work, since it is Android/iOS/macOS only
  and desktop-beyond-macOS needs `sqflite_common_ffi`.
