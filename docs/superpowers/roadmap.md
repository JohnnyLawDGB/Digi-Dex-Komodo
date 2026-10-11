# DigiByte DEX roadmap — live status

**Rewritten in place, not appended.** This is the current picture; the per-milestone
narrative is in `2026-09-29-session-handoff.md`, and the authoritative plan of record is
§10 of `specs/2026-09-27-digibyte-wallet-design.md`.

Last updated: 2026-10-11, after a store-readiness audit of **both** platforms (M1-D3 merged as PR #8 on 2026-10-10).

## Where we are

| Milestone | Status |
| --- | --- |
| **M0 — Proving the stack** | **Done** (2026-09-30). Mainnet DGB↔LTC swap on the DigiByte network ID, fee received by the fork's address. Four repos published under JohnnyLawDGB. |
| **M1 — Wallet** | **In progress.** See the lane table below. |
| **M2 — Swaps** | Not started. The actual DEX: swap screen, quotes and fees, progress, history and recovery. Needs mainnet seed nodes and market makers for DGB/BTC and DGB/LTC. |
| **M3 — Production** | Not started. Remaining pairs, monitoring, external security review, store listings, legacy sunset. |

## M1 lanes

| Lane | Status | Released as |
| --- | --- | --- |
| M1-A — KDF fork, fee key rotation | **Parked** on the owner's offline fee key | — |
| M1-B — App foundation, CI | Done | 0.1.0 |
| M1-C — Wallet core (onboarding, unlock, biometrics, portfolio) | Done, PR merged | 0.2.0 / 0.2.1 |
| M1-D1 — Move money (send, receive, history, QR, links) | Done, PR #5 | 0.3.0 / 0.3.1 |
| M1-D2 — Prices and USD | Done, PR #6 | 0.4.0 |
| 0.4.1 — large-font row, 2 min biometric backstop, DGB electrum order | Done, PR #7 | 0.4.1 |
| **M1-D3 — Settings** | **Done, PR #8** (merge 72262b5), accepted on device 13/14 | **0.5.0** |
| M1-D4 — Fiat currency | **Next candidate.** Not scoped | — |
| M1-D5 — Log export | **Next candidate.** Not scoped | — |
| **M1-E — iOS pass, TestFlight** | **Not scoped.** Audited 2026-10-11; Mac environment ready | — |

**M1 exit criterion:** internal TestFlight and Play builds, usable on mainnet as a wallet.
Play internal is live; TestFlight and the iOS device pass are outstanding.

## The two candidate lanes

Both were split out of M1-D3 deliberately, because each is a subsystem rather than a control.

**Fiat currency.** The price layer is USD-only (`UsdFormat`, CoinGecko `usd`). Multi-fiat
reaches the price repository, its cache, the portfolio total, the sparklines and Send's
"≈ $". It is not a dropdown.

**Log export.** There is nothing to export yet — about 55 ad-hoc `debugPrint` sites and no
buffer. Needs capture plus redaction. Redaction deserves real care: this project has already
found seed words exposed as `content-desc` in `uiautomator` dumps and an Equatable state
printing them through `toString`.

*Recommendation: log export first*, because it decides what can safely be collected from
testers. Fiat is the more visible product gap, so this is a judgement call, not an obvious one.

## iOS / Apple readiness — audited 2026-10-11

Everything shipped so far is Android-only in practice: Play internal has 0.1.0 through 0.5.0,
and **no build has ever run on a Mac**. CI compiles iOS on every PR (`build-ios`, ~3m44s), so
the code builds — but no pods are installed locally, no device has run it, and nothing has been
through App Review. The M1 exit criterion includes TestFlight, so this is the gap between where
we are and where M1 ends.

**In good shape already:** `PrivacyInfo.xcprivacy` exists with `NSPrivacyTracking` and two
required-reason API declarations; `NSFaceIDUsageDescription` and `NSCameraUsageDescription` are
present; `SceneDelegate.swift` means the modern UIScene lifecycle rather than the legacy
AppDelegate-only path; `CFBundleURLSchemes` carries the `digibyte:` scheme; and the Keychain
already uses `first_unlock_this_device`.

### Gaps, worst first

1. **No screenshot or recording protection on iOS at all.** `setSecureWindow` invokes a
   `setSecure` method channel that only `MainActivity.kt` implements; on iOS the
   `MissingPluginException` is swallowed by design (design note 11). So the seed reveal, the
   onboarding backup page and the delete screen are fully capturable on iOS — screenshots and
   screen recording both. This is precisely the protection we spent a fix round hardening on
   Android, where it now blacks out from the first frame. iOS has no `FLAG_SECURE` equivalent;
   it needs a deliberate implementation.
2. **The app-switcher snapshot is unprotected.** iOS captures the window when the app
   backgrounds. Without covering the window on resign-active, a seed screen or balances land in
   that snapshot. Android gets this free with `FLAG_SECURE`; iOS does not.
3. **Exchange rules are a milestone risk, not a detail.** M1 is a wallet, which Apple permits
   when the developer is enrolled as an **organization**. M2 adds swap functionality, and
   Apple's guideline 3.1.5 has historically required appropriate licensing and permissions per
   region for exchange features, with rejections citing the exchange itself as the expected
   submitter. **Confirm the Apple Developer account is an organization, and get a reading on the
   exchange rule, before M2's UI is built** — not after.
4. **`ITSAppUsesNonExemptEncryption` is absent**, so every upload prompts for export compliance,
   and a wallet needs a deliberate, defensible answer rather than a click-through.
5. **Deployment target is iOS 13.0** — very old for 2026, and it costs access to modern APIs
   (including the cleaner routes to items 1 and 2). Worth raising deliberately.
6. **The privacy manifest is thin.** It declares only `UserDefaults` and `FileTimestamp`
   required-reason categories and *no* collected data types. That needs auditing against what
   the plugins actually call (`local_auth`, `mobile_scanner`, `package_info_plus`, `share_plus`,
   `url_launcher`, `flutter_secure_storage`), and against Apple's rule that commonly-used
   third-party SDKs ship their own manifest and signature.
   **A question that is ours specifically:** we operate `electrum.digiscope.me`, so the app's
   primary DGB server is first-party infrastructure that observes user addresses and IP
   addresses. Whether that counts as developer data collection for privacy labels is a real
   question, not a formality.
7. **Build-toolchain deadline.** Secondary sources indicate uploads require Xcode 26 / SDK 26
   from April 2026. Not confirmed against Apple's own pages — **verify before the Mac session**,
   because it gates whether anything can be uploaded at all.
8. **`digibyte:` is a custom scheme.** Correct for the payment-URI standard, but Universal Links
   are the modern complement for any https entry points.
9. **Cold-start link delivery on iOS** is still unverified (carried from M1-D1).

### Suggested shape

A dedicated **M1-E: iOS pass** lane, specced like any other, rather than a grab-bag during the
first Mac session. Items 1, 2 and 4 are code and belong in that lane. Items 3 and 7 are
questions to answer *first*, because they can change what is worth building.

## Android / Play readiness — audited 2026-10-11

Android is where the users are: 0.1.0 through 0.5.0 are on Play internal testing and the Moto
runs every acceptance pass. The security posture is **good**, better than the iOS side.

**Already right, and worth not regressing:** `allowBackup=false` and `fullBackupContent=false`
with a `data_extraction_rules.xml` — the classic wallet leak, where a seed or keystore rides a
cloud backup off the device, is closed. `usesCleartextTraffic=false`. Only four permissions
(INTERNET, CAMERA, USE_BIOMETRIC, USE_FINGERPRINT). minSdk 28, targetSdk and compileSdk 36, so
current against Play's floor. 16 KB page alignment is verified on every release build, and the
release script refuses a bundle not signed by the upload key.

### Gaps, worst first

1. **R8 is off.** `isMinifyEnabled` is never set, so release builds are not shrunk and the
   Kotlin/Java layer is not obfuscated — class and method names ship intact. Dart is AOT
   compiled so the Dart logic is not readable, but `--obfuscate --split-debug-info` is not used
   either, so Dart symbol names remain. Obfuscation is not a primary control, but for a wallet
   it is expected practice and it raises the cost of attack. Enabling R8 under Flutter needs
   keep rules for the plugins, so this is a small lane, not a flag flip.
2. **No native debug symbols uploaded.** `debugSymbolLevel` is unset, so Play Console crash
   reports for `libkomodo_defi_framework.so` arrive unsymbolicated. For a wallet whose hardest
   failures live in the KDF native layer, that is an operational blind spot — and it is close to
   free to fix.
3. **`flutter build appbundle` alone can produce a debug-signed "release".** The release config
   falls back to debug signing when `key.properties` is absent, deliberately, so contributors
   can run release builds. `tool/release_android.sh` refuses to ship one — but only that path is
   guarded.
4. **`USE_FINGERPRINT` is deprecated** and redundant at minSdk 28, where `USE_BIOMETRIC` covers
   it. Cosmetic, but it is a permission on the store listing.
5. **No network security config.** Largely moot since cleartext is off — and worth understanding
   why it would not help anyway: **KDF opens its electrum connections through its own Rust TLS
   stack, so Android's network security config does not govern them.** Certificate pinning for
   `electrum.digiscope.me` would have to happen inside KDF, not in the Android layer.
6. **`taskAffinity` was deliberately removed** (StrandHogg). Largely mitigated at minSdk 28 since
   StrandHogg 2.0 targets below Android 9, but it is a standing decision rather than a fix.

## Both stores — policy, which is an M2 problem

The two platforms converge on the same distinction, and it is the one that matters for this
project: **a wallet is treated differently from an exchange.**

- **Google Play** requires a **Financial Features Declaration** under App Content, stating
  whether the app is a cryptocurrency exchange and/or a software wallet, with per-country
  licensing requirements behind it. After 2025 backlash Google stated that **non-custodial
  wallets are not in scope** of the Cryptocurrency Exchanges and Software Wallets policy — which
  is the good case for us, since the user holds the seed. Swap functionality is where that stops
  being obviously true.
- **Apple** guideline 3.1.5 permits wallets from organization-enrolled developers, and has
  historically wanted licensing and permissions per region for exchange features.

So M2 carries a **store-policy question on both platforms simultaneously**, not a technical one.
Settle it before the swap UI exists. Both readings above come from secondary sources and Google's
help pages rather than a definitive reading of current policy text — **verify against the primary
policy pages before acting**, and before any production (rather than internal) release.

**A question that is ours on both stores:** the data-safety form and the privacy labels both ask
what the developer collects. We operate `electrum.digiscope.me`, so the app's primary DGB server
is first-party infrastructure that sees user addresses and IP addresses. That needs a deliberate,
consistent answer in both forms, not a default.

## Carried debt, none blocking

From 0.5.0:
- Asset deactivation generation check through `activate`/`activateListed` (a stale `active`
  marker; the row is filtered out and electrum genuinely disconnects, so it is cosmetic).
- A known-failed asset cannot be switched off, because the balance check fails closed. A safe
  escape needs SDK-private `hydratedPubkeys` and its own spec.
- `PasswordGate.tryBiometrics` reports a generic `unknown` where `wrongPassword` with
  `biometricsEnabled: true` would be clearer.
- A wallet with a **pending backup** cannot reach Settings at all, so it cannot be deleted
  in-app until backed up. Behaviour, not a defect — but surprising.

From 0.4.1 and earlier:
- The biometric prompt stays on screen after the backstop fires (flutter_secure_storage
  cannot cancel it).
- `Confirming n/7` does not advance live on an open asset screen.

## Standing blockers and owner inputs

| Item | Needed for |
| --- | --- |
| Offline fee key | M1-A (rotation), and it gates the DEX fee path |
| Approved mainnet seed node list | M2 |
| Market makers for DGB/BTC and DGB/LTC | M2 |
| A Mac session | iOS pass, TestFlight, M1 exit |

## Beyond M1

**DigiDollar as a swap peg.** The owner confirmed (2026-10-10) that DigiDollar is an asset on
the DigiByte blockchain and is **protocol level** in `digibyted` — not a DigiAssets token and
not a separate chain. That means KDF must understand its outputs and mint/redeem transactions
before it can swap them: real work in the KDF fork, on top of what M1-A already carries.
**Scope it as a milestone, not a ticket**, and establish first whether it is live on mainnet or
still in the 9.26.x release candidates, and which digibyted version carries it.
