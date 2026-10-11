# DigiByte DEX roadmap — live status

**Rewritten in place, not appended.** This is the current picture; the per-milestone
narrative is in `2026-09-29-session-handoff.md`, and the authoritative plan of record is
§10 of `specs/2026-09-27-digibyte-wallet-design.md`.

Last updated: 2026-10-11, after an iOS/Apple readiness audit (M1-D3 merged as PR #8 on 2026-10-10).

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
| **M1-E — iOS pass, TestFlight** | **Not scoped.** Audited 2026-10-11; see "iOS / Apple readiness" | — |

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
