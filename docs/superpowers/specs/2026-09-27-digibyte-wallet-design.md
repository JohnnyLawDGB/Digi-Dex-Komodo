# DigiByte Wallet — Design Spec

- **Date:** 2026-09-27
- **Status:** Approved by the product owner 2026-09-29
- **Replaces:** the legacy `Digi-Dex-Komodo` app (Komodo `atomicdex-mobile` white-label, Flutter 2.8.1)

## 1. Context

The current app is a thin rebrand of Komodo's legacy mobile wallet. It has 30 cosmetic commits over upstream, all from 2023. It runs Flutter 2.8.1 and Dart <3 with no null safety, and every backend it uses belongs to Komodo/Gleec.

Upstream has abandoned it. `komodo-wallet-mobile` stopped at 0.9.2 in Feb 2025, and trading was disabled in Jan 2025. The maintained successor stack is:

- `GLEECBTC/komodo-defi-framework` (KDF, formerly mm2)
- `GLEECBTC/komodo-defi-sdk-flutter`
- `GLEECBTC/coins`

The legacy repo also has two security defects:

1. **A signing keystore and its passwords are committed to git.** `android/app/key.jks` and `android/key.properties` came in with commit `53632202`.
2. **Seed and PIN storage is weak.** The wallet password is embedded in secure-storage key names (`lib/utils/encryption_tool.dart:15-16`), and the seed phrase and PIN are also stored in plaintext.

**Decision:** build a new app on `komodo-defi-sdk-flutter` (path A1: the high-level SDK plus thin forks). Do not upgrade the legacy code in place.

## 2. Product definition

**Agreed with the product owner:**

- **Product:** a DigiByte-branded multi-coin wallet and DEX.
- **Platforms:** Android and iOS at launch.
- **Swap pairs:** every pair includes DGB. The wallet also holds the other side of each pair.
- **Swap network:** a DigiByte-operated swap network (its own network ID and seed nodes) with a DigiByte-controlled DEX fee, implemented as a thin KDF fork.
- **Store listings:** new listings. Existing users move by restoring their seed phrase. No legacy-storage migration code.
- **Branding:** DigiByte only, with no multi-brand tooling. All branding sits in one config file so a rebrand is easy.
- **Operations:** DigiByte runs the seed/relay nodes, the market-maker bots and the DGB electrum servers. Prices and charts come from public APIs, and non-DGB chains use public electrum/RPC servers.

**Assumptions, all accepted:**

- **Fee rate and discounted pair:** DigiByte chooses them. They are fork parameters and are not fixed in this spec.
- **Market making:** KDF's built-in `simple_market_maker` bot, running on DigiByte servers with DigiByte-controlled inventory.

**Launch success criteria:** a user can do all of the following on the production network:

1. create or restore a wallet;
2. send and receive every listed asset;
3. complete a DGB↔X swap against a non-empty order book.

## 3. Verified technical facts

These were checked against source on 2026-09-27.

| Fact | Source |
|---|---|
| KDF network ID and seed nodes are start-up config | KDF `d56a7bc`: `mm2_core/src/mm_ctx.rs:443`, `mm2_main/src/lp_native_dex.rs:509` |
| KDF DEX fee and burn addresses are compile-time constants | `mm2src/common/common.rs:233-236` |
| KDF fee rate (2%, 1% for GLEEC pairs) is hard-coded | `mm2src/coins/lp_coins.rs:4112` (`dex_fee_rate`) |
| KDF default network ID is 6133; 8762 is deprecated | `mm2_p2p/src/behaviours/atomicdex.rs:64,81-84` |
| The SDK always starts KDF with `kDefaultNetId` (a const, 6133) and filters seed nodes to that ID | SDK `0a94d03`: `komodo_defi_types/lib/src/constants.dart:5`, `komodo_defi_local_auth/.../auth_service_kdf_extension.dart:545-561`, `komodo_defi_framework/.../seed_node_service.dart:90` |
| Binary and coin sources are plain config | `komodo_defi_framework/app_build/build_config.json` |
| The SDK needs Dart ≥3.9 and Flutter ≥3.35 | `komodo_defi_sdk/pubspec.yaml` |
| The SDK's `startSwap` sends v2 `start_swap`, which KDF does not dispatch; KDF only has legacy `buy`/`sell`/`recover_funds_of_swap` | `komodo_defi_rpc_methods/.../trading/start_swap.dart:16`; KDF `rpc/dispatcher/dispatcher_legacy.rs:71,106,107` |
| The SDK provides a raw RPC escape hatch | `komodo_defi_framework/lib/komodo_defi_framework.dart:273` (`executeRpc`) |
| KDF keeps the seed encrypted under the wallet password; the SDK uses `flutter_secure_storage` ^10 and `local_auth` ^2.3 | `komodo_defi_local_auth/pubspec.yaml`, `auth_service_kdf_extension.dart:172-176` |

## 4. Architecture

### 4.1 Repositories

Each repo is pinned by full commit hash.

| Repo | Contents | Syncing with upstream |
|---|---|---|
| `digibyte-wallet` (new) | The Flutter app. All DigiByte-specific code. | — |
| `kdf` (fork of GLEECBTC/komodo-defi-framework) | One patch series: fee and burn public keys, fee rate, DGB as the discount ticker, default network ID. CI builds, checksums and signs the Android armv7/arm64 and iOS aarch64 binaries, with 16 KB page alignment on Android. | Rebased onto each upstream release tag |
| `komodo-defi-sdk-flutter` (fork) | One patch: network ID and seed nodes injectable through `KomodoDefiSdkConfig`, default unchanged (6133). Offered upstream as a PR; if merged, this fork is retired. | Rebased as needed |
| `coins` (fork of GLEECBTC/coins) | Only the listed assets, `seed-nodes.json` for the DigiByte network ID, electrum servers (§7.2), and the `DOC`/`MARTY` test coins for CI (§9). | Selective cherry-picks |

### 4.2 App layering

```
UI (screens, widgets)            Material 3, DigiByte theme
  ↓ reads state from
Feature blocs/cubits             flutter_bloc only; one per feature
  ↓ call
Repositories (app-owned)         wallet, assets, swap, prices, settings
  ↓ wrap
KomodoDefiSdk managers           auth, assets, balances, withdrawals,
                                 transactions, trading, marketData, fees
  ↓ drives
KDF fork (static lib)            local RPC; P2P on DigiByte network ID
```

**Rules:**

- **No top-level mutable singletons.** Dependencies are wired once at start-up through `RepositoryProvider`/`MultiBlocProvider`.
- **Widgets never touch the SDK or RPC directly.** They go through repositories, which have fakes for testing.
- **Brand identity in one place:** `lib/config/brand.dart` holds the app name, colors, URLs, fee display text, network ID and seed nodes. Native IDs (package/bundle ID, display name, icons) live in Android/iOS build config, with a checklist in the README.
- **App IDs sit under `digiscope.me`**, the domain the owner can prove ownership of for Google Play developer verification and Android App Links:
  - Android `applicationId` and iOS bundle ID: `me.digiscope.wallet`. The suffix is a proposal; the `me.digiscope` root is decided.
  - A Play package name can never change after the first upload, so the ID is fixed before the first internal build (M1).
  - `https://digiscope.me/.well-known/assetlinks.json` carries the release signing-key fingerprint. It is only needed if the app uses verified links.
  - This replaces the legacy `io.digibyte.dex` / `io.digibyte.dex.dgb`, which matches the decision to publish as new store listings.
- **Navigation:** `go_router` with an auth redirect guard.
- **Toolchain:** Flutter pinned in `.fvmrc` to the version the SDK fork commit requires (≥3.35), Dart 3 with sound null safety, `very_good_analysis` lints.
- **Layout by feature:**
  - `lib/features/{onboarding,wallet,send,receive,swap,swap_history,settings}/{bloc,view,widgets}`
  - `lib/data/repositories/`
  - `lib/config/`

## 5. v1 scope

### 5.1 Included

- **Onboarding:**
  - Create a wallet: 24-word BIP39 seed via SDK auth, HD enabled.
  - Seed backup check: the user selects words back in order.
  - Restore from seed.
  - Set a password.
- **Unlock:** password, or biometrics (see §8.1).
- **Portfolio:**
  - Listed assets with balance, fiat value and a total; DGB pinned first.
  - Assets can be turned on or off from the curated list only.
  - No custom tokens.
- **Asset detail:** balance, transaction history (SDK), and a 24h/7d/30d price sparkline.
- **Send:**
  - Address entry with QR scanning; amount entry.
  - Address validation (`validateaddress`) and address-poisoning warning (§8.2).
  - Fee preview via the SDK fee manager.
  - Confirm screen, then broadcast.
- **Receive:**
  - Address display, QR code, copy and share.
  - New HD address.
  - `digibyte:` URI handling, registered as an Android intent filter and an iOS URL scheme.
- **Swap:**
  - One simple screen, taker-only.
  - Details in §6.1.
- **Swap history:** status, per-step detail, and recovering funds from failed swaps.
- **Settings:**
  - Fiat currency; theme (light/dark/system); language.
  - View seed (password required); biometric toggle; auto-lock timeout.
  - Delete wallet; about/version.
  - Export logs with secrets redacted.
- **Translations:** English at launch, using `gen_l10n` ARB files so more languages can be added without code changes.

### 5.2 Deferred

- Placing maker orders
- Pro and multi-order trade modes
- Candlestick charts
- Address book
- Decoy PIN
- Encrypted backup export
- News feed
- Push notifications
- Hardware wallets
- Custom tokens
- More languages

### 5.3 Dropped

KMD rewards, the test-coin faucet, ZHTLC/Pirate activation, the in-app update checker, and the legacy rebranding notice.

**Rationale for taker-only:** a mobile maker order only works while the app is open and online. In the legacy app this caused stuck and expired orders. The market-maker bots provide all maker liquidity in v1.

## 6. Swaps and the DigiByte network

### 6.1 Taker flow

1. **Pick a pair.** One side must be DGB. If either asset isn't active, the app activates it through the SDK.
2. **Quote.**
   - `best_orders` (through `komodo_defi_rpc_methods`) gives the best price for the entered amount.
   - `maxTakerVolume` and `minTradingVolume` set the input limits.
   - `trading.watchOrderbook` refreshes the quote live.
   - Pairs with no active order are hidden.
3. **Fee breakdown.**
   - `trading.tradePreimage` gives the DEX fee plus network fees on both chains.
   - The confirm screen shows *you send / you receive / total fees*.
   - It warns when total fees are over 5% of the trade value.
4. **Start the swap.**
   - Legacy `buy` or `sell` via `executeRpc`, wrapped in a typed `SwapRepository.startTakerSwap(...)`.
   - The request uses `match_by` limited to the quoted order and a price limit derived from a user-set slippage (default 1%).
   - The swap uuid is saved.
   - This wrapper is replaced by the SDK's `startSwap` if KDF gains `start_swap`.
5. **Track progress.**
   - `trading.watchSwapStatus(uuid)` drives the step list: fee paid → maker payment seen → taker payment sent → maker payment spent → complete.
   - The swap keeps running when the user leaves the screen.
   - On launch, unfinished swaps are reloaded from `recentSwaps` and tracking resumes.
   - A "keep the app open" banner shows while any swap is running.
6. **Recover a failed swap.**
   - A failed swap is marked "needs action", with a button that calls `recover_funds_of_swap`.
   - The app retries automatically once the swap's locktime has passed.

### 6.2 Network topology

```
                 ┌──── seed/relay nodes (≥3, geographically separate) ────┐
 app (KDF fork) ─┤  KDF fork, i_am_seed=true, DigiByte network ID, TCP+WSS │
                 └────────────────────────────────────────────────────────┘
                              ▲
 market makers:   KDF fork + simple_market_maker bot; one config per DGB/X
                  pair; prices from CoinGecko/Binance; spread and max volume
                  per pair
 DGB electrum:    ≥2 DigiByte-operated SSL servers + cipi's servers (§7.2)
```

- **Network ID:** one unused value, set in three places: the KDF fork default, the app's `brand.dart` (via the SDK patch), and the coins fork's `seed-nodes.json`. It must not be 6133, 8762 or 7777.
- **Fee enforcement:** the maker's KDF validates the taker fee against the fork's constants. That requires every participant (apps and bots) to run the fork.
- **Liquidity is a launch requirement:** a pair ships in the app only once it has an active market-maker order.

### 6.3 Seed nodes

**Open input:** the product owner will supply the approved list of seed nodes. §6.2 applies to it:

- run the KDF fork with `i_am_seed: true`;
- publicly reachable over TCP;
- WSS preferred.

The list is written to `coins` fork `seed-nodes.json` and `lib/config/brand.dart`.

## 7. Data sources, build and release

### 7.1 Market data

- **Prices:** the SDK's `marketData` (`komodo_cex_market_data`), using CoinGecko first and Binance as fallback, rather than the Gleec/Komodo price API.
  - If providers can't be selected by config, the SDK fork patch gains a provider override.
- **Caching:** sparkline data is cached for 10 minutes.
- **Failure:** if both providers fail, the app shows "price unavailable" and all wallet functions keep working.

### 7.2 Electrum and RPC servers

**Starting point:** cipi (Komodo/Gleec) runs ElectrumX servers for 34 coins, listed in `GLEECBTC/coins/electrums/` (checked at commit `2b0aefb`, 2026-09-25). Each coin has 3 hosts, `<coin>.electrum{1,2,3}.cipig.net`, serving TCP, SSL and WSS.

| Coin | TCP / SSL / WSS ports | Live on 2026-09-28 (ElectrumX 2.0.0) |
|---|---|---|
| DGB | 10059 / 20059 / 30059 | electrum1 ✓, electrum2 ✓, electrum3 ✗ (connection refused) |
| BTC | 10000 / 20000 / 30000 | electrum1 ✓, electrum2 ✓, electrum3 ✗ |
| LTC | 10063 / 20063 / 30063 | electrum1 ✓, electrum2 ✓, electrum3 ✗ |
| DOGE | 10060 / 20060 / 30060 | electrum1 ✓, electrum2 ✓, electrum3 ✗ |

Other cipig-covered coins that could become DGB pairs later: BCH, DASH, ZEC, RVN, SYS, QTUM, LBC, FTC, VIA and others (see `electrums/`).

**DGB server list, in priority order:**

| # | Host | Operator | Status on 2026-09-29 |
|---|---|---|---|
| 1 | `electrum.digiscope.me` — `ssl://electrum.digiscope.me:50002`, `wss://electrum.digiscope.me:50004` | DigiByte (VPS at 134.199.198.90) | **Live.** Verified from outside the VPS: Let's Encrypt cert valid until 2026-12-28 with auto-renewal, ElectrumX 1.16.0 on protocol 1.4, DGB genesis `7497ea1b465e…` matches, tip equal to both cipig servers, WSS upgrade returns 101. |
| 2 | Second DigiByte-operated server (the ElectrumX 1.19.0 on the dev workstation) | DigiByte | Synced to mainnet tip. TCP 50001 only, not reachable from the internet. M0/dev use only until it gets a DNS name, SSL and a port-forward. |
| 3–4 | `dgb.electrum1.cipig.net`, `dgb.electrum2.cipig.net` (SSL 20059, WSS 30059) | cipi | Live |

**`electrum.digiscope.me` operating notes (owner's setup, 2026-09-29):**
- The firewall caps public connections at 800 in total and 16 per IP, below ElectrumX's 1,000-session cap. When ElectrumX hits that cap it closes every port, including the internal one DigiScope's tx-monitor uses, so public traffic must never reach it.
- A watchdog runs every 5 minutes. It restarts ElectrumX and tx-monitor if the internal port stops listening, and it alerts above 700 public connections.
- The server is down for about a minute at the daily 4am restart and during the monthly compaction. The app must fail over to the cipig servers for those gaps, so KDF's electrum list needs at least 2 more servers after this one.
- `REPORT_SERVICES` announces the server to ElectrumX peers, so third-party DGB wallets may find it. The 800-connection cap bounds that load.

**Requirements before a DigiByte-operated server goes into the coins fork:**
- A DNS name and a valid public TLS certificate (Let's Encrypt), with automatic renewal.
- `SERVICES` includes `ssl://:50002` and `wss://:50004`. Plain TCP is optional and never used by the app.
- Firewall allows 50002/50004. The ElectrumX `rpc://` admin port stays on localhost.
- ElectrumX cost limits are enabled (`COST_SOFT_LIMIT`/`COST_HARD_LIMIT` not 0) and `MAX_SESSIONS` is sized for expected users.
- It passes the nightly probe: SSL handshake, `server.version`, and a height within 2 blocks of the other servers.
- `digibyted` fee estimation is optional. KDF uses the fixed `txfee` of 0.1 DGB/kB from the DGB coin entry and doesn't call `blockchain.estimatefee`.

**Rules for the coins fork:**
- **SSL only in the app.** The TCP entries are dropped, per §8.2.
- **DGB:** the servers in the table above, in that order.
- **Non-DGB UTXO chains:** cipi's servers, plus at least one other public operator per chain where one exists, so no chain depends on a single operator.
- **ETH/BSC (USDT/USDC):** at least 2 public RPC servers per chain.
- **Nightly CI probe** (`server.version` over SSL) against every server; it opens a PR when one is down. The electrum3 outage above is the kind of thing it should catch.
- **Contact:** cipi (`cipi@komodoplatform.com`, Discord `cipi#4502`), from the coins repo. Tell cipi before launch that a DigiByte app will depend on these servers.

### 7.3 Build pipeline (GitHub Actions)

**`kdf` fork:**
- On each upstream tag, rebase the patch series.
- Run upstream tests plus the fee tests (§9).
- Cross-compile the Android and iOS binaries.
- Publish a GitHub Release with the zips, `SHA256SUMS` and a GPG signature.

**App:**
- Override `build_config.json`:
  - `source_urls` point at the fork's releases;
  - pinned commit hash and sha256 values;
  - the coins config points at the coins fork.
- The build fails if a checksum doesn't match.
- On every PR: `flutter analyze`, unit, widget, golden and engine-integration tests, and debug builds for both platforms.
- On `main`: signed release builds, an AAB to Play internal testing and an IPA to TestFlight.

**Signing:**
- Keys are held only in CI secrets and never committed.
- The Android upload key is new, with Play App Signing enabled.
- iOS uses App Store Connect API keys.

**Store requirements:**
- Android: targetSdk 35 and 16 KB page alignment.
- iOS: 13 or later, with `PrivacyInfo.xcprivacy`.
- The only permissions requested are camera and biometrics.

**Releases:**
- Semantic versions, git tags and a changelog.
- Play staged rollout at 10% → 50% → 100%.
- TestFlight external testing before App Store release.

## 8. Security

### 8.1 Secrets

- **Seed:** stored only by KDF, encrypted under the wallet password (SDK auth). The app never keeps the plaintext seed. It shows the seed only in the backup check and in "view seed", which requires the password again.
- **Password:** never stored in plaintext and never used in storage key names.
- **Biometric unlock:**
  - The wallet password is stored in Keychain/Keystore with biometric-bound access control: iOS `biometryCurrentSet`, Android a Keystore key that requires `BiometricPrompt` and is invalidated when new biometrics are enrolled.
  - If biometrics change or fail, the app falls back to the password.
  - If `flutter_secure_storage` 10 can't express these flags on both platforms, write a minimal platform channel.
- **Password policy:** at least 8 characters, a strength meter, and `allowWeakPassword` left false.

### 8.2 App hardening

- **Screen protection:** screenshots blocked on seed and private-key screens (Android `FLAG_SECURE`, iOS secure overlay); app-switcher preview blurred everywhere.
- **Auto-lock:** 2 minutes in the background by default (configurable), plus "lock now". Unlocking reuses a running KDF session.
- **Wrong-password lockout:** after 5 failures, exponential lockout of 30s, 1m, 5m and so on. There is no auto-wipe.
- **Transport:** HTTPS/WSS only. Android `usesCleartextTraffic=false`; iOS keeps the ATS defaults.
- **KDF RPC:** bound to `127.0.0.1` with a random 32-character RPC password per session.
- **Backups:** Android `allowBackup=false`; app data excluded from iCloud backup.
- **Log export:** mnemonics, private keys, WIFs, passwords, `userpass` and swap `secret` fields are removed. Fixture tests cover each of them.
- **Clipboard:** addresses are cleared after 60 seconds. The seed can't be copied.
- **Address-poisoning warning:** shown when a destination matches the start and end of a recent address but differs in the middle, and when a user sends to their own address.

### 8.3 Supply chain and operations

- **Pinning:**
  - forks by full commit hash;
  - KDF binaries by sha256 plus signature check;
  - Flutter version in `.fvmrc`.
- **Dependency updates:** Dependabot on, with PRs reviewed by hand.
- **Fee keys:** the fork embeds only the fee and burn public keys. The private keys are held offline or in a multisig, never on the seed or market-maker servers.
- **Market-maker wallets:** they hold only operating inventory, swept to cold storage on a schedule, with alerts when balances cross thresholds.
- **Before launch:**
  - an external security review of the KDF fork diff, app auth and biometrics, and the market-maker setup;
  - `SECURITY.md` with a disclosure and bounty policy.

### 8.4 Legacy app sunset

**Final release of the legacy app:** only if DigiByte controls the real Play upload key. It:
- shows a notice with a link to the new app;
- reminds users to view their seed phrase so they can restore in the new app;
- stops starting new swaps.

**Legacy repo cleanup:** purge `android/app/key.jks` and `android/key.properties` from its history. If the committed key matches the Play upload key, treat it as compromised and rotate it.

## 9. Testing

| Layer | Scope | Runs |
|---|---|---|
| Unit | Blocs (`bloc_test`), repositories against a fake SDK, typed `buy`/`sell`/recovery wrapper, fee math, address-poisoning check, log redaction | Every PR |
| Widget / golden | Every screen in light and dark themes, phone sizes, error/empty/loading states | Every PR |
| Engine integration | Repositories against a real KDF (`komodo_defi_harness`) on a CI network ID with `DOC`/`MARTY` | Every PR (Linux runner) |
| End-to-end on device | `integration_test` on Android emulator and iOS simulator: create/restore → activate → receive → send → swap against a test market-maker bot | Nightly; required before any release |
| KDF fork | Upstream swap tests, plus: the correct fee address and rate are paid; a swap with the wrong fee is rejected by the maker | Every fork rebase |

**Test network:** one seed node and one market-maker bot on a private network ID, separate from production.
- **The coins repo has no DGB or LTC testnet entries** (checked 2026-09-28). The testnet coins it does have include `TESTBTC`, `DOC` and `MARTY`, which are served by cipig electrums.
- **M0 staging (owner decision 2026-09-29: test on mainnet with small real amounts, no DGB testnet):**
  1. Swap `DGB`↔`LTC` on **mainnet coins** over a **private DigiByte network ID** (1 seed node, 1 market-maker bot, both owner-run). LTC is chosen for low fees and live cipig electrums, and DGB/LTC is a launch pair.
  2. Amounts stay small: the bot's inventory is capped (e.g. ≤ 2,000 DGB and ≤ 0.5 LTC), and each test swap is sized just above KDF's minimum trade volume.
  3. The DEX fee goes to the fork's fee address, which DigiByte controls, so the only real cost is on-chain network fees.
  4. No `tDGB` coin entry or DGB testnet ElectrumX is built.
- **Per-PR engine integration (M1 CI):** uses the free Komodo test coins `DOC`/`MARTY` on a separate CI network ID, so CI never spends real funds.

## 10. Milestones

Ordered by risk, riskiest first. Each milestone ends with an installable demo.

- **M0: Proving the stack.** Build the KDF fork patch and its Android/iOS builds, the SDK patch that makes the network ID injectable, and the coins fork with a test network (1 seed node, 1 bot).
  - **Exit:** a bare Flutter app on a physical phone completes a small mainnet DGB↔LTC swap on a private DigiByte network ID, and the fork's fee address receives the DEX fee.
  - Calendar estimates for M1–M3 are set only after M0.
- **M1: Wallet.** App skeleton (§4.2, `brand.dart`, theme, routing, CI), onboarding, unlock and biometrics, portfolio, asset detail, send, receive, settings.
  - **Exit:** internal TestFlight and Play builds, usable on mainnet as a wallet.
- **M2: Swaps.** Swap screen, quotes and fees, progress tracking, history and recovery. Mainnet seed nodes; market makers for DGB/BTC and DGB/LTC.
  - **Exit:** internal testers complete small mainnet swaps.
- **M3: Production.** Remaining pairs and market makers, server monitoring and alerts, external security review, store listings and privacy manifests, legacy sunset release.
  - **Exit:** public launch.

## 11. Open inputs and verification items

| Item | Owner | Needed by |
|---|---|---|
| Approved seed node list (§6.3) | Product owner | M0 (test network), M2 (mainnet) |
| DEX fee rate, discount rule, fee/burn public keys | Product owner | M0 |
| DigiByte network ID value | Engineering, confirmed with product owner | M0 |
| Initial DGB/X pair list and market-maker inventory per pair | Product owner | M2 |
| Whether `komodo_cex_market_data` providers can be selected by config (§7.1) | Engineering | M1 |
| Whether `flutter_secure_storage` 10 supports biometric-bound access control on both platforms (§8.1) | Engineering | M1 |
| Notify cipi of the dependency; ask whether the electrum3 hosts are being retired (§7.2) | Product owner | M2 |
| ~~Open `electrum.digiscope.me` publicly (§7.2)~~ Done 2026-09-29; verified | Product owner | M0 |
| Make the dev-workstation ElectrumX public (DNS, TLS, port-forward) or replace it with a second VPS (§7.2) | Product owner | M2 |
| Confirm the app ID suffix under `me.digiscope` (proposed `me.digiscope.wallet`) (§4.2) | Product owner | M1 (before first Play upload) |
| Whether the legacy committed key matches the Play upload key (§8.4) | Product owner (Play Console access) | Before any legacy release |
