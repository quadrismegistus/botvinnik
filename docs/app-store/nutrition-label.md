# App Privacy answers (App Store Connect → App Privacy)

The answers to paste into the "App Privacy" questionnaire. They are simple
because the iOS app collects nothing and makes no network requests.

## Data collection

**"Do you or your third-party partners collect data from this app?"** → **No.**

That is the whole questionnaire. Selecting "No" yields a **"Data Not
Collected"** privacy label, which is accurate: no accounts, no analytics, no
ads, no identifiers, and (on iOS) no network requests at all.

## Why "No" is correct even though there's a database

Saved games, settings and practice progress live in on-device storage
(`sqflite` / `UserDefaults`). Data that stays on the device and is never
transmitted to you or a third party is **not** "collected" in Apple's sense.
The `PrivacyInfo.xcprivacy` manifest declares the required-reason APIs behind
that local storage (UserDefaults `CA92.1`, file timestamp `C617.1`) — those
are about *how* the app uses system APIs, separate from data collection.

## If Maia ever ships on iOS

Today Maia (the neural-net bots) is web-only, so the iOS app makes no network
request. If native Maia is added later (issue #44), the app would fetch a
model file from HuggingFace on first use of a Maia — still **no data
collected** (it's a download, nothing is sent), but the privacy policy's
network section already covers it, and the review notes should mention it.

## Encryption

`ITSAppUsesNonExemptEncryption = false` is set in Info.plist. The app uses only
standard HTTPS (and on iOS, not even that), which qualifies for the standard
exemption — no export-compliance documentation needed.
