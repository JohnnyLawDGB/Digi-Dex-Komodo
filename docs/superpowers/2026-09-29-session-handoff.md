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
