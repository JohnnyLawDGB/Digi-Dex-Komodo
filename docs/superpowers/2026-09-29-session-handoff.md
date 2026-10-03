# Session Handoff: DigiByte Wallet Rebuild

- **Date:** 2026-09-29
- **Branch:** `docs/digibyte-wallet-design` (local only, not pushed)
- **Spec:** [`specs/2026-09-27-digibyte-wallet-design.md`](specs/2026-09-27-digibyte-wallet-design.md)

## Where we are

| Stage | Status |
|---|---|
| Assessment of the legacy app | Done (§1 below) |
| Strategy decision | Done: path **A1**, a new app on `komodo-defi-sdk-flutter` with thin forks |
| Design, all 6 sections | Approved section by section in conversation |
| Written spec | **Approved by the owner 2026-09-29.** |
| Implementation plan | **M0 plan written:** [`plans/2026-09-29-m0-proving-the-stack.md`](plans/2026-09-29-m0-proving-the-stack.md). Awaiting owner review and choice of execution method. |
| Code | **M0 complete (2026-09-30).** Four repos are published under JohnnyLawDGB. Mainnet swaps are proven; see `digibyte-wallet/docs/m0-report.md`. |

**Paused because:** ElectrumX is restarting on `digiscope.me`, which is being opened up as `electrum.digiscope.me`.

## 1. Assessment of the legacy app (summary)

**What it is:**
- Komodo `atomicdex-mobile` / `komodo-wallet-mobile`, with 30 cosmetic DigiByte commits (Oct–Nov 2023). Last commit Feb 2024.
- Flutter 2.8.1, Dart <3, no null safety. About 57k hand-written LOC plus 17k generated l10n.
- Three state-management patterns and about 25 global singletons.
- A god-class RPC layer (`lib/services/mm.dart`) making v1 mm2 calls over localhost HTTP.
- All backends belong to Komodo/Gleec.

**Upstream status:**
- The legacy mobile app is dead: trading disabled Jan 2025, last release 0.9.2 in Feb 2025.
- The stack moved to the **GLEECBTC** GitHub org.
- KDF v3 changed the default network ID to 6133 and the fee to 2% (1% on GLEEC pairs).

**Build and CI are broken:**
- It uses actions v3 artifacts.
- It downloads `libmm2.a` from a GitLab artifact that returns 404.
- Android targetSdk 31, below the Play minimum.

**Security problems in the legacy repo (still open):**
- `android/app/key.jks` and `android/key.properties`, including passwords, are committed (commit `53632202`).
- The wallet password is used in secure-storage key names (`lib/utils/encryption_tool.dart:15-16`).
- The seed phrase and PIN are also stored in plaintext.

## 2. Decisions made with the owner

| Topic | Decision |
|---|---|
| Strategy | Path A1: new app, high-level SDK, thin forks of KDF, the SDK and coins |
| Product | Multi-coin wallet and DEX, DigiByte-branded |
| Swap network | DigiByte's own network ID and seed nodes, with a DigiByte DEX fee |
| KDF | Thin fork: fee and burn public keys, rate, DGB discount ticker, default network ID |
| Platforms | Android and iOS at launch |
| Existing users | New store listings; users restore from their seed phrase; no migration code |
| Branding | DigiByte only; all branding in one config (`lib/config/brand.dart`) |
| App IDs | Root `me.digiscope` (owner can prove digiscope.me ownership); proposed `me.digiscope.wallet` |
| Coins | DGB pairs only (DGB/X) |
| Operations | DigiByte runs the seed nodes, market makers and DGB electrum servers; prices come from public APIs (CoinGecko/Binance) |
| v1 scope | Taker-only swaps; English only; deferred and dropped lists are in spec §5 |

## 3. Facts verified in source

Full table in spec §3.

**KDF (`GLEECBTC/komodo-defi-framework@d56a7bc`):**
- Fee address and rate are compile-time constants, so a DigiByte fee needs the fork.
- There is no `start_swap` handler, so the app calls legacy `buy`/`sell` through `executeRpc`.

**SDK (`GLEECBTC/komodo-defi-sdk-flutter@0a94d03`):**
- The network ID is locked to `kDefaultNetId = 6133`, which is why the SDK needs a patch.
- It requires Flutter ≥3.35 and Dart ≥3.9.

**Coins (`GLEECBTC/coins@2b0aefb`):**
- cipi runs electrums for 34 coins.
- There are no DGB or LTC testnet entries.

## 4. Electrum infrastructure

| Server | Status | Notes |
|---|---|---|
| `electrum.digiscope.me` (VPS 134.199.198.90) | **Live, verified 2026-09-29** | Primary. SSL 50002 / WSS 50004, ElectrumX 1.16.0. See spec §7.2. |
| Dev workstation ElectrumX 1.19.0 (`~/electrumx-dgb`, systemd `electrumx.service`) | Synced to mainnet | TCP 50001 only, not publicly reachable. Cost limits are 0, i.e. off. Dev/M0 only. |
| `dgb.electrum1/2.cipig.net` | Live | electrum3 refused connections for DGB, BTC, LTC and DOGE on 2026-09-28 |

**When `electrum.digiscope.me` is up,** run the check used in this session:
- TLS certificate CN and expiry;
- `server.version`;
- `blockchain.headers.subscribe` height compared with a public explorer;
- genesis hash `7497ea1b465e…` (DGB mainnet).

## 5. Roadmap

Details in spec §10.

- **Next (gate):** the owner approves the spec, then write the implementation plan starting with M0.
- **M0: Proving the stack.**
  - Build the KDF fork (fee and network ID) for Android and iOS, the SDK patch (injectable network ID and seed nodes), and the coins fork.
  - First swap `DOC`↔`MARTY` on a private test network; then `tDGB`↔`TESTBTC` using a DigiByte testnet ElectrumX.
  - **Exit:** a swap on a phone pays the DigiByte fee address.
- **M1: Wallet.** Skeleton, CI, onboarding and unlock, portfolio, send, receive, settings. Internal store builds.
- **M2: Swaps.** Swap screen, tracking, recovery. Mainnet seed nodes; market makers for DGB/BTC and DGB/LTC.
- **M3: Production.** Remaining pairs, monitoring, external security review, store listings, legacy sunset release. Launch.

## 6. Waiting on the owner

- [x] Review and approve the spec (approved 2026-09-29)
- [x] Bring `electrum.digiscope.me` online. Done and verified 2026-09-29 (spec §7.2)
- [ ] Seed-node list for the DigiByte swap network (the owner said a list exists)
- [ ] DEX fee rate, discount rule, fee and burn public keys
- [ ] DigiByte network ID value (engineering proposes one; the owner confirms)
- [ ] Initial DGB/X pairs and market-maker inventory
- [ ] Check whether the committed legacy keystore matches the Play upload key

## 7. How to resume

1. Open `docs/superpowers/specs/2026-09-27-digibyte-wallet-design.md` on branch `docs/digibyte-wallet-design`.
2. If `electrum.digiscope.me` is up, verify it (§4) and update spec §7.2.
3. Once the spec is approved, invoke `superpowers:writing-plans` for M0.
4. The upstream checkouts used for verification were in a temporary scratchpad. Re-clone them with `git clone --depth 1` from `github.com/GLEECBTC/{komodo-defi-framework,komodo-defi-sdk-flutter,coins}`, and re-check the facts in spec §3 if upstream has moved.

## Update 2026-09-30 — M0 complete

**Result:** the exit criterion is met. Two mainnet DGB↔LTC swaps ran on netid 2014 from the Moto G 5G (`ZY22HVMNKZ`). The DEX fee was verified on-chain in LTC (`fee10120…`) and in DGB (`c8dc5fa9…`).

**Published:**

| Repo (branch) | Head |
|---|---|
| `JohnnyLawDGB/komodo-defi-framework` (`digibyte/main`, tag `dgb-v3.0.0-beta.1`) | `4715f29` |
| `JohnnyLawDGB/komodo-defi-sdk-flutter` (`digibyte/main`) | `6dfe132` |
| `JohnnyLawDGB/coins` (`digibyte/main`) | `a7bce7e` |
| `JohnnyLawDGB/digibyte-wallet` (private) | `e11f6cf` |

**Running infrastructure:**
- The seed `seed1.digiscope.me` (VPS, `kdf-seed`).
- On the dev workstation: the bot (`kdf-bot`) and the price feed (`dgb-price-feed`).

**Secrets:** index at `~/.config/dgb-dex/SECRETS-INDEX.md`.

**Execution record:** `docs/superpowers/2026-09-30-m0-execution-ledger.md`, covering rulings, parked findings and the final-review triage.

**Next:** write the M1 plan (superpowers `writing-plans`). Fold in:
- **Next KDF release (key rotation):**
  - rotate the fee key to an offline key;
  - the P2P redial fix;
  - CI pinning: container digest, action SHAs, `--locked`.
- **M1 bootstrap:**
  - disable the Gleec market-data provider;
  - make the SDK runtime-config fallback fail fast or point at the forks;
  - pin or disable runtime coin updates.
- **M2 swap repository:**
  - adopt running swaps found via `my_recent_swaps`;
  - use `base_*` volumes only;
  - subscribe to the orderbook topic after sign-in.
- **Before any ARRR/SC pair:** replace the ZHTLC and Sia fee destinations.

**M1 decisions (2026-09-30):**
- App ID `me.digiscope.wallet`.
- The owner has Play Console access, plus an Apple Developer account and a Mac.
- The fee key is rotated in M1, together with the P2P fix and CI pinning.
- Branding uses official DigiByte assets.
- The docs branch stays local while M1 is planned.

## Update 2026-10-02: M1-B done, M1-C planned

**Status**

| Milestone | State | Record |
|---|---|---|
| M1-A (KDF release 2) | Parked; waiting on the owner's offline fee key. T2–T6 are pushed to `digibyte/main` with no tag. | `.superpowers/sdd/2026-09-30-m1a-kdf-release-2/progress.md` |
| M1-B (app foundation) | Merged to `JohnnyLawDGB/digibyte-wallet` main via PR #1 (CI) and PR #2 (local Android release lane) | `.superpowers/sdd/2026-09-30-m1b-app-foundation/progress.md` |

**M1-B release state**
- Release 0.1.0 (versionCode 393798) is at `~/digibyte-dex/release-artifacts/digibyte-dex-0.1.0-393798.aab`.
- It was device-tested on the Moto and then uninstalled. The owner is uploading it manually to Play internal testing.
- After that first manual upload, later uploads go through `tool/play_upload.py`.
- **iOS/TestFlight is deferred**: the owner chose Play first.

**Owner preferences**
- Release lanes run locally, not through GitHub Actions.
- Claude may merge reviewed, CI-green PRs on `digibyte-wallet`. Use `--merge`, not squash.

**M1-C (wallet core)**
- Plan: `docs/superpowers/plans/2026-10-01-m1c-wallet-core.md`, 14 tasks.
- Inputs: `.superpowers/research/m1c-design-notes.md` (decisions) and `.superpowers/research/m1c-sdk-api.md` (SDK API research).
- The owner reviewed the summary. Execution is subagent-driven.
- **Next:** on the owner's "go", run superpowers:subagent-driven-development on that plan. Its workspace and ledger don't exist yet, and Task 1 is the SDK fork patch.

**Open items**
- Signed-out KDF does not dial `seed1`. Verify P2P after sign-in.
- M1-D scope: send, asset detail, history, sparkline, prices/fiat, settings (including the asset on/off toggle), log export and `digibyte:` URIs.

## Update 2026-10-03: M1-C done (PR #3 merged)

**Status**

| Milestone | State | Record |
|---|---|---|
| M1-A (KDF release 2) | Still parked; waiting on the owner's offline fee key | `.superpowers/sdd/2026-09-30-m1a-kdf-release-2/progress.md` |
| M1-B (app foundation) | Merged (PRs #1, #2) | — |
| M1-C (wallet core) | **Merged**: PR #3, merge commit 455a131 on `JohnnyLawDGB/digibyte-wallet` main. SDK fork `digibyte/main` is at 2480d261 (pushed). | This section, and `docs/release.md` in the app repo ("M1-C acceptance (0.2.0)") |

**Release 0.2.0**
- versionCode 395391, at `~/digibyte-dex/release-artifacts/digibyte-dex-0.2.0-395391.aab`.
- It is sideloaded on the Moto; Play upload is at the owner's discretion.
- Uninstall the sideloaded build before installing from Play.

**What M1-C added beyond the plan** (found in review or on the device):
- **KDF RPC port collision.** Any other KDF app on 127.0.0.1:7783 (the M0 probe, Komodo Wallet) aborted the app at launch, and the old setup sent our RPC password to the foreign KDF.
  - Fix: a free loopback port plus a per-launch RPC password chosen at startup. The leftover in-process KDF is stopped at startup.
  - SDK guard: refuse a local KDF on a port the client does not dial.
- **Restore seed field.** The hidden field (`obscureText`) stripped newlines, so a multi-line legacy seed was silently mangled. It is now a multi-line, masked field with copy and cut disabled.
- **Lock.** An adopted session now starts Locked. A sign-in that finishes in the background starts the auto-lock clock.
- **Biometrics.** A keystore lockout or cancel keeps the entry. The reset sentinel is not treated as a password, and there is no double prompt.
- **Lockout and backup.** Lockout counting fails open on keystore errors and attempts are serialised per wallet. The backup flag is cleared only on a definite rejection, and the restore flag ordering is safe.
- **Receive.** Shows the newest External address (never a change address), refreshes the pubkey cache after a create, and the clipboard clear is lifecycle-aware.

**Acceptance on the Moto (0.2.0): all steps PASS**
- Create plus a 24-word backup quiz.
- Kill, then sign in.
- Lock and auto-lock.
- Biometrics, warm (local_auth) and cold (Keystore).
- Lockout that survives a kill.
- Receive, with the clipboard clear checked by hand by the owner.
- M0 restore read-only: 746.8875 DGB, 0.05062037 LTC.
- Legacy restore.
- App logcat secret scan clean.
- Not run on the device: the adopted-session relaunch, which is covered by tests.

**SECURITY INCIDENT (owner decision pending)**
- The acceptance helper typed secrets with `adb shell input text`, and `adbd` logs those commands to logcat.
- Chunks of the real `m0-phone-seed`, the iguana test seed and the accept password were in the Moto's in-memory logcat for about 7 minutes (10-03, 05:03–05:10 device time).
- The log was cleared, log persistence is off, and a re-check found 0 leaked lines. Host-side raw dumps were shredded.
- Exposure: anything with adb or READ_LOGS during that window.
- Owner decides whether to sweep the M0 wallet (≈747 DGB) to a fresh seed.
- **Future acceptance must never type real seeds through `adb shell input text`.** Options: type only throwaway seeds, or clear logcat immediately after each secret entry.

**M1-D follow-ups (parked in M1-C review; none blocked M1-C):**
- **Seed field hardening:**
  - the accessibility Copy/Cut action can still copy (`enableInteractiveSelection:false` plus an explicit Paste button);
  - `autofillHints: null`;
  - redact `SeedTextController.toString`.
- **Biometric opt-in:**
  - a failure is silent (`enable`→false with no feedback);
  - `isAvailable` is weaker than the Keystore's strong-biometric requirement;
  - add a first-time Lock-page opt-in widget test;
  - local_auth re-prompts accept weaker biometrics (owner call).
- **flutter_secure_storage** logs "EncryptedSharedPreferences initialization failed… Falling back to custom ciphers" (bad base-64 / could not decrypt key) on every cold start. State persists; investigate which namespace.
- **Backup page password prompt** bypasses PasswordAttempts. The view-seed page must use PasswordGate.
- **Portfolio:** drive rows from `sdk.watchActivationStates()` (a mid-session KDF drop leaves a row "active").
- **Port fix:**
  - the orphan check stops only `rpcIsUp` (a mid-startup leftover gives one error screen, and Retry recovers);
  - the pick-to-bind race recurs per SDK restart;
  - the one-engine-per-process assumption needs a comment;
  - the SDK is not disposed if `seeds.init` throws after `startSdk`.
- **Other:**
  - `revealSeed` splits on a single space;
  - `PassphraseMismatch`→`weakPassword` message;
  - `_guard` has no diagnostics;
  - `newAddress` partial-success message;
  - LockCubit initial lifecycle seed;
  - the I2 adopted-session code is now defense in depth (reword it);
  - delete-wallet and disable-biometrics must delete `bio_pw_*`.
- **Acceptance tooling:**
  - the brief's gradle-cache bundletool jar isn't runnable; use the official bundletool-all-1.18.1.jar;
  - screencap of a FLAG_SECURE screen returns 0 bytes on the Moto;
  - "Don't keep activities" must be toggled by hand, not over adb;
  - read checkbox state before tapping.

**Open owner questions**
- Departure 13: a biometric success during a lockout resets it.
- Whether to sweep the M0 wallet after the log incident.
- Play upload of 0.2.0.

**Next**
- M1-D plan: send, asset detail and history, prices/fiat, settings (asset toggle), log export, `digibyte:` URIs, plus the follow-ups above.
- M1-A is still waiting on the fee key.
