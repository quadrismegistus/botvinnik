# App Store submission — status and checklist

Tracks the App Store compliance work (issue #72). The **code side is done**;
what remains needs an Apple Developer account and Apple's web console, so it is
yours, not the repo's.

## Done in code (this repo)

- [x] **GPLv3-on-App-Store decision** — the Lichess posture (issue #76, closed).
- [x] **Source public and linked in-app** — Settings → About → Source code.
- [x] **Licence + third-party notices bundled and viewable offline** — Settings
      → About (kept in sync by `flutter/stage-legal.sh`, CI drift guard).
- [x] **`ITSAppUsesNonExemptEncryption = false`** — both `Info.plist` files.
- [x] **`PrivacyInfo.xcprivacy`** — `ios/Runner/` and `macos/Runner/`, wired
      into each Xcode project and **verified in the built bundle**. Declares no
      tracking, no collected data, and the required-reason APIs the local
      storage uses (UserDefaults `CA92.1`, file timestamp `C617.1`).

## Content drafted here (paste / host as-is)

- [ ] **Privacy policy** — [`privacy-policy.md`](privacy-policy.md). Host it at
      a stable URL (botvinnik.app can serve it) and give App Store Connect that
      URL.
- [ ] **App Privacy answers** — [`nutrition-label.md`](nutrition-label.md).
      "Data Not Collected".
- [ ] **Review notes** — [`review-notes.md`](review-notes.md).

## Needs you (Apple account + console; cannot be done from the repo)

- [ ] An **Apple Developer Program** membership, a bundle ID, and signing.
- [ ] A **support URL** (a page or the repo's issues is fine).
- [ ] **Screenshots** at the required device sizes, an **app icon** in the
      store sizes, **description / keywords / subtitle**, age rating.
- [ ] The **actual submission** in App Store Connect.

## Related, separate issues

- **#67 — notarization layout**: DONE structurally (2026-07-20). The engines
  are copied to `Contents/MacOS` and signed with the app's own identity in the
  same build phase, so the layout is submittable. What remains is not code: a
  paid Apple Developer Program membership, without which there is no Developer
  ID certificate to sign with and nothing to submit to. Local builds sign
  ad-hoc through the identical code path.
- **#80 — retro on iOS**: DONE (2026-07-20). iOS runs the same engines from a
  Go c-archive over `dart:ffi`, so the roster no longer differs by platform.

## A note on validation

The privacy manifest and plist changes are verified as far as they can be
without an actual Apple upload: both files lint, and `PrivacyInfo.xcprivacy`
is confirmed present in the built iOS and macOS bundles. Apple's final
"missing privacy manifest / invalid reason code" checks only run at upload
time — if it flags anything, it will name the exact API and reason, and the
fix is a one-line addition to the manifest.
