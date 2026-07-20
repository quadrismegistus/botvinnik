# App Review notes

Paste into App Store Connect → the version's "Notes for Review". These
pre-empt the two things a reviewer on a restricted network might otherwise
misread.

---

botvinnik is an offline chess trainer. A few things worth knowing for review:

- **No account or login is required.** Open the app and play immediately.
  There is nothing to sign into and no server to reach.

- **It works fully offline.** Every chess engine runs on-device (Stockfish is
  embedded; the other bots are on-device code). You can review the whole app
  in airplane mode.

- **No data is collected.** Games, settings and practice progress are stored
  only on the device. The App Privacy label is "Data Not Collected".

- **The app is free software (GPL-3.0-or-later).** The complete source is
  public at github.com/quadrismegistus/botvinnik, linked from inside the app
  (Settings → About → Source code), and the licence and third-party notices
  are viewable in-app (Settings → About).

(If a future version adds the "Maia" bots on iOS, those download a small
neural-net model from HuggingFace on first use — a file download, no data
sent, and the app falls back to its built-in engine if the network is
unavailable. As of this submission, Maia is not offered on iOS and the app
makes no network requests.)
