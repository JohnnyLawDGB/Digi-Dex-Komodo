# M1-E bootstrap for the Mac session

You are starting the iOS lane on a Mac. The Linux session that wrote the spec and plan cannot
build iOS, so this lane runs entirely on your machine. Read this once, then work from the plan.

## What to read, in order

1. **Spec:** `docs/superpowers/specs/2026-10-11-m1e-ios-pass-design.md` — owner-approved 2026-10-11.
2. **Plan:** `docs/superpowers/plans/2026-10-11-m1e-ios-pass.md` — 7 tasks, 37 steps.
3. **Guardrails:** `CLAUDE.md` in the app repo. It loads automatically, but read the iOS section
   deliberately; it records what the audit found.
4. Background, only if you need it: `docs/superpowers/roadmap.md` → "iOS / Apple readiness".

## Clone

```bash
# The design record (specs, plans, roadmap, ledgers). PUBLIC repo.
git clone -b docs/digibyte-wallet-design git@github.com:JohnnyLawDGB/Digi-Dex-Komodo.git

# The app. PRIVATE repo. The SDK fork is a submodule and is required.
git clone --recurse-submodules git@github.com:JohnnyLawDGB/digibyte-wallet.git
cd digibyte-wallet && git checkout -b feat/m1e-ios-pass   # off main, currently 0.5.0
```

If you clone without `--recurse-submodules`, run `git submodule update --init --recursive`. The
submodule is `third_party/komodo-defi-sdk-flutter` on branch `digibyte/main`; the app will not
build without it.

## Toolchain

- **Flutter 3.41.4, pinned via fvm.** The repo has `.fvmrc`. Always invoke
  `.fvm/flutter_sdk/bin/flutter`, never a bare `flutter`. A wrong-toolchain failure looks like a
  project error and is not one.
- **Xcode and CocoaPods.** Pods have never been installed in this repo on any machine, so expect
  the first build to resolve them. Record anything unusual.
- **Coin assets are fetched at build time** and are gitignored. Run `tool/prime_assets.sh` after
  cloning.
- Confirm the full Dart suite passes before you change anything:
  `cd app && ../.fvm/flutter_sdk/bin/flutter test` (expect 1036 passing) and `flutter analyze`.

## Task 1 is a gate — honour it

Before any Swift is written, prove KDF runs on the physical iPhone: launch, create a throwaway
wallet, and see **DGB reach `active` with a balance**.

If it does not, **stop the lane**. Do not start Task 2. Report what failed with the device log.
KDF has only ever been proven on Android, and if it cannot run on iOS then the capture work is
worthless and the lane needs re-scoping. This is deliberate: fail in the first hour, not the
second week.

## Two things the owner must answer, not you

- **Export compliance** (`ITSAppUsesNonExemptEncryption`, plan Task 5 Step 3). This is a
  compliance statement, not a technical default. The honest input: KDF bundles its own
  cryptography in a Rust library rather than only calling platform APIs. **Ask before writing
  the key.**
- **The privacy-label collected-data answer** (Task 5 Step 4). We operate
  `electrum.digiscope.me`, so the app's first DGB server sees user addresses and IP addresses.
  Whatever answer is given must match the Google Play data-safety form — one answer, both stores.

## Rules that are not negotiable

- **Never log, print, screenshot or transcribe a seed word, a password or a `bio_pw_*` value** —
  in Swift, Dart, tests or device tooling. On iOS a *successful* capture of a seed screen is the
  failure this lane exists to prevent; if one succeeds, that is the headline finding, not a note.
- **`lib/platform/secure_window.dart` does not change.** iOS implements the same `setSecure`
  method on the same channel Android already uses, so Dart needs no edit. `secure_screen.dart`
  changes in exactly one way, in Task 3 (the capture notice). If other Dart edits seem necessary,
  the seam was not reused — stop and say so.
- **Never amend a commit that has already been reviewed.** Add a new one.
- Conventional Commit subjects, each message ending with:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
- Merge with `--merge`, not squash.

## Scope discipline

The app has never run on iOS hardware, so expect unrelated surprises — fonts, layout, keyboard,
permission prompt timing. **Record them; do not absorb them.** If the focused device pass turns
up broad breakage, that is a second lane, not an extension of this one.

Out of scope entirely: re-accepting all of M1 on iOS, Android behaviour changes, and store policy
work (the wallet-versus-exchange question is M2, for both stores).

## Known context worth having

- `AppDelegate.swift` already wires the platform channel, handles `digibyte:` links through the
  scene lifecycle, and excludes data directories from backup. `setSecure` is the missing case.
- `SceneDelegate.swift` is empty; the app-switcher cover goes there.
- `PrivacyInfo.xcprivacy` exists but declares only two required-reason categories and no
  collected data types.
- Deployment target is `IPHONEOS_DEPLOYMENT_TARGET = 13.0` in three places.
- A separate iOS effort is porting the *other* DigiByte mobile wallet. The owner decided on
  2026-10-11 that **M1-E does not coordinate with it**. Do not take a dependency on it.

## When the lane finishes

Record the device acceptance in the app repo's `docs/release.md`, in the same table shape as
"M1-D3 acceptance (0.5.0)". A check that did not pass is **FAIL** or **NOT OBSERVED** — never
rounded up. Then open the PR, wait for all four checks, and merge.

Update `docs/superpowers/roadmap.md` (rewritten in place, not appended) and append a milestone
section to `docs/superpowers/2026-09-29-session-handoff.md`.
