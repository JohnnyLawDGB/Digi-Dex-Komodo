# M1-E "iOS pass": design spec

- **Date:** 2026-10-11
- **Status:** design approved by the owner in conversation 2026-10-11; written spec awaiting review.
- **Parent spec:** `2026-09-27-digibyte-wallet-design.md` §10 (M1 exit: internal TestFlight and Play builds) and design note 11 (iOS has no `setSecure` handler).
- **Previous milestone:** `2026-10-10-m1d3-settings-design.md`. M1-D3 merged as PR #8; 0.5.0 is on Play internal.
- **Audit this follows:** `docs/superpowers/roadmap.md` → "iOS / Apple readiness", 2026-10-11.
- **Repo:** app `JohnnyLawDGB/digibyte-wallet`, branch `feat/m1e-ios-pass`. No SDK fork change is expected.

## 1. Purpose and scope

Everything shipped so far is Android in practice. CI compiles iOS on every PR, but no build has run on a Mac, no pods are installed, no device has run the app, and nothing has been through App Review. The sharpest consequence is a security asymmetry: the seed reveal, the onboarding backup page and the delete screen are hardened on Android with `FLAG_SECURE` — which this project spent a fix round making land on the first frame — and are **completely unprotected on iOS**, for screenshots and screen recording alike.

M1-E closes that asymmetry and gets the app onto TestFlight.

**In scope:**
- A device smoke test that gates the lane (§3).
- Capture protection on iOS, reusing the existing `setSecure` channel (§4).
- App-switcher snapshot protection (§5).
- Submission readiness: export compliance, privacy manifest, deployment target (§6).
- A TestFlight release path mirroring the Android one (§7).
- A focused device acceptance pass (§8).

**Explicitly out of scope:**
- **Re-accepting all of M1 on iOS.** Onboarding, send, receive, QR, links, biometrics and settings each had an Android acceptance; repeating all of it on iOS belongs in its own lane if the smoke test and focused pass turn up breadth problems.
- Android behaviour changes. §5 raises a question about matching always-blur on Android; it is recorded, not implemented here.
- Store policy work. Both stores' wallet-versus-exchange question is an M2 problem (roadmap → "Both stores").

## 2. Decisions (owner, 2026-10-11)

| # | Question | Decision |
| --- | --- | --- |
| 1 | Lane scope | Parity plus submission readiness, then TestFlight and a focused device pass. Not a full M1 re-acceptance. |
| 2 | How to block capture | The secure-layer approach **plus** capture detection, not detection alone. |
| 3 | Hardware | Mac and a physical iPhone are both available. |
| 4 | App-switcher blur | **Always**, on every screen — not only on secure screens. Balances and addresses should not sit in the switcher either. |
| 5 | KDF smoke test | **A gate.** If KDF does not run on the device, the lane stops and is re-scoped rather than continuing. |

## 3. The gate: does KDF run on an iPhone at all?

The native Komodo DeFi Framework is this project's riskiest dependency, and M0 proved the stack on **Android**. Nothing has demonstrated that `libkomodo_defi_framework` starts, binds its port and activates a coin on iOS hardware.

**Gate criterion:** on the physical iPhone, the app launches, a wallet can be created, KDF starts, and **DGB reaches `active`** with a balance read from an electrum server.

If that fails, **stop**. Do not continue to §4-§8. Report what failed, and re-scope: a KDF-on-iOS investigation is a different lane with a different shape, and the capture work is worthless if the app cannot run.

This is deliberately the first task, so a fundamental problem surfaces in the first hour rather than after the submission work is done.

## 4. Capture protection

### 4.1 Reuse the existing seam

`setSecureWindow` (`lib/platform/secure_window.dart`) already invokes a `setSecure` method on the shared platform channel, catches `MissingPluginException`, and is driven by the `SecureScreen` widget. Android implements it in `MainActivity.kt`.

**iOS implements the same method on the same channel.** Consequences, all deliberate:
- **No Dart changes.** `SecureScreen`, `setSecureWindow` and every widget test that uses them are untouched. The missing-plugin catch simply stops firing on iOS.
- The call sites that already wrap the seed screens (`backup_page.dart`, `view_seed_page.dart`) gain protection with no edit.
- The Dart-level tests continue to prove what they always proved — that the widget calls the channel — and **nothing more**. They do not prove the native side works; §9 covers that.

### 4.2 Mechanism

A `UITextField` with `isSecureTextEntry = true` owns a secure `CALayer` that the system excludes from screenshots and screen recordings. Hosting the window's content in that layer extends the exclusion to the whole window. `setSecure(true)` attaches it; `setSecure(false)` detaches it.

**This behaviour is undocumented.** It is widely used by banking and wallet apps, but Apple does not specify it and a future iOS could change it. That is accepted with mitigations, not ignored:
- A native XCTest asserting the secure layer is attached after `setSecure(true)` and gone after `setSecure(false)`, so a silent regression fails the build rather than the user.
- A device check in acceptance (§8) that a real recording is black.
- A documented fallback: if the layer approach ever stops working, §4.3's detection still blanks during recordings, and the product degrades to detect-and-warn rather than losing protection silently. That degradation must be visible in the logs, not silent.

### 4.3 Capture detection, as a second layer

The layer approach protects a capture started **while** the screen is open. A recording already running when the user navigates to the seed is a different case. Observe `UIScreen.isCaptured` (and its change notification): while captured, cover the secure content with an opaque view and tell the user why.

This is documented API and future-safe, so it is the floor the product never falls below.

## 5. App-switcher snapshot

iOS snapshots the window when the app backgrounds, and that snapshot appears in the app switcher and persists on disk. Cover the window on `sceneWillResignActive` and uncover on `sceneDidBecomeActive`.

**Applied always, on every screen** (owner decision 4) — not only while a secure screen is open. A balance, an address or a transaction list in the switcher is a privacy leak too, and an always-on rule has no state to get wrong.

Android currently blurs only via `FLAG_SECURE` on secure screens. **Open question, recorded not decided:** whether Android should match this always-on behaviour. It is a separate lane; it is not implemented here.

## 6. Submission readiness

### 6.1 Export compliance

`ITSAppUsesNonExemptEncryption` is absent, so every upload prompts, and a wallet deserves a deliberate answer rather than a click-through.

**This needs the owner's decision and is not a technical default.** The two readings:
- **Exempt.** The app uses encryption only in ways commonly treated as exempt — platform TLS, standard algorithms through the OS — so the key is set to `false` and no annual self-classification report is filed.
- **Not exempt.** KDF bundles its own cryptographic implementations rather than only calling platform APIs, which can take an app outside the common exemptions. The key is `true`, and the corresponding compliance obligations follow.

The spec does not choose. It records that **the key must be set explicitly** before the first upload, with the owner's answer, and that the honest input to that answer is: KDF ships its own crypto in a bundled Rust library.

### 6.2 Privacy manifest

`ios/Runner/PrivacyInfo.xcprivacy` exists and declares `NSPrivacyTracking` plus two required-reason categories (`UserDefaults`, `FileTimestamp`), and **no collected data types**.

Audit it against what the app actually links: `local_auth`, `mobile_scanner`, `package_info_plus`, `share_plus`, `url_launcher`, `flutter_secure_storage`, `path_provider` and the KDF framework. Apple's review scans the binary, so a dependency's use of a required-reason API counts as ours, and commonly-used third-party SDKs are expected to ship their own manifest and signature.

**The question that is ours specifically:** we operate `electrum.digiscope.me`, which is the app's first DGB server and therefore sees user addresses and IP addresses. Whether that is developer data collection for privacy-label purposes is a real question. Whatever answer is given here must match the Google Play data-safety form — one answer, used consistently.

### 6.3 Deployment target

Currently `IPHONEOS_DEPLOYMENT_TARGET = 13.0`, which is old for 2026 and limits the APIs available for §4 and §5.

Raise it. The recommendation is **iOS 15.0**, but the lane must first confirm Flutter 3.41.4's actual supported floor from the toolchain rather than assume, and record what the chosen floor drops.

## 7. TestFlight

A `tool/release_ios.sh` mirroring `tool/release_android.sh`'s posture: build, then **verify before shipping** rather than trusting the build. The Android script's guards that have analogues — correct signing identity, the archive actually containing what it should, the version and build number matching what was intended — should have them. Where there is no analogue, say so in the script rather than leave a silent gap.

Upload to TestFlight internal testing, the same shape as the Play internal track.

## 8. Device acceptance (physical iPhone)

Focused on what changed and what has never run, not a full M1 re-run.

| # | Check |
| --- | --- |
| 1 | **Gate (§3): KDF starts, DGB reaches `active` with a balance** |
| 2 | Seed reveal with a screen recording running: black for the whole reveal |
| 3 | A recording started **before** opening the seed screen: content covered, user told why |
| 4 | Screenshot of the seed screen: excluded or blank |
| 5 | App switcher on every screen type (Home, asset, seed): no readable content |
| 6 | **Face ID** opt-in, unlock, and the re-auth on send — a different flow from fingerprint |
| 7 | Camera/QR scan |
| 8 | `digibyte:` link on a **cold start** — the gap M1-D1 left unverified on iOS |
| 9 | Delete wallet end to end on a throwaway wallet |
| 10 | Installed from TestFlight, not a local build |

Carry the Android tooling discipline across: **never dump UI node text on a seed screen**, and treat any capture of a seed as a leak.

## 9. Testing

- **Native XCTest** for the secure layer (§4.2) and the app-switcher cover (§5). This is the only automated proof of the native behaviour; the Dart tests cannot reach it.
- **Existing Dart tests unchanged.** If a Dart test needs editing to accommodate iOS, that is a signal the seam in §4.1 was not reused properly.
- **Device acceptance** (§8) for everything neither can reach.

## 10. Risks and open items

- **The gate may fail.** KDF on iOS is unproven. §3 exists so that is discovered first.
- **The secure-layer behaviour is undocumented** (§4.2), mitigated by a test, a device check and a visible fallback.
- **Breadth surprises.** The app has never run on iOS hardware, so expect unrelated issues — fonts, layout, keyboard behaviour, permission prompt timing. Record them; do not absorb an unbounded tail into this lane. If the focused pass turns up broad breakage, that is a second lane.
- **Export compliance (§6.1) needs the owner's answer** before the first upload.
- **The privacy-label answer (§6.2) must match the Play data-safety form.**
- **Toolchain deadline.** Secondary sources indicate uploads require a recent Xcode and platform SDK as of 2026. Verify against Apple's own developer pages at the start of the lane, since it gates whether anything can be uploaded at all.

## 11. Release

0.6.0, as the first release of M1-E. Android keeps shipping from the same branch point, so the Play build and the TestFlight build are the same version.
