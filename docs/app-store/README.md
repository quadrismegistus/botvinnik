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

- **#67 — notarization layout**: the bundled engine is ad-hoc signed in
  `Contents/Resources`; it should move to `Contents/MacOS` for a macOS App
  Store / notarized build. Not required for iOS.
- **#80 — retro on iOS**: retro is macOS-only. iOS ships a complete roster
  without it (it is simply not offered there), so this does not block an iOS
  submission — it is an enhancement.

## A note on validation

The privacy manifest and plist changes are verified as far as they can be
without an actual Apple upload: both files lint, and `PrivacyInfo.xcprivacy`
is confirmed present in the built iOS and macOS bundles. Apple's final
"missing privacy manifest / invalid reason code" checks only run at upload
time — if it flags anything, it will name the exact API and reason, and the
fix is a one-line addition to the manifest.
