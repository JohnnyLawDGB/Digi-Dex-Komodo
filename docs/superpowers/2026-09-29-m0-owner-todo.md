# M0 — Owner To-Do (for when you're back at the dev machine)

Updated: 2026-09-29. Plan: `docs/superpowers/plans/2026-09-29-m0-proving-the-stack.md`. Local clones: `~/digibyte-dex/{kdf,sdk,coins,digibyte-wallet}` (nothing pushed yet).

The tasks are in order. Each one says what it unblocks.

## 1. Decisions (5 min, can be answered from your phone)

- [ ] **Network ID `2014`**: confirm or change. It is baked into the KDF fork, the coins fork and the app.
- [ ] **Seed host `seed1.digiscope.me`** → 134.199.198.90: confirm or change.
- [ ] **Fee rates**: 2% base, 1% on any pair that includes DGB. Confirm or change.
- [ ] **Contact email** in the public coins fork (seed-node and electrum entries): `mark@aroundtheblock.us`. OK?
- [ ] **Go-ahead to create GitHub repos** under `JohnnyLawDGB`: public forks of `komodo-defi-framework`, `komodo-defi-sdk-flutter` and `coins`, plus a private `digibyte-wallet`.

## 2. Fee key (15 min, offline machine) → unblocks Task 3 (fee key in KDF)

1. On an **offline** machine, create a new DigiByte Core wallet used only for DEX fees.
2. Run `getnewaddress "" legacy`, then `getaddressinfo <that address>`.
3. Copy `pubkey` (66 hex chars) and `scriptPubKey` (`76a914…88ac`).
4. Check them on the dev machine:
   ```bash
   python3 ~/digibyte-dex/digibyte-wallet/ops/tools/check_fee_key.py <pubkey> <scriptPubKey>
   ```
   It prints the hash160 and the DGB and LTC fee addresses, plus the lines for `~/.config/dgb-dex/m0-inputs.env`.
5. Back up the wallet's private key offline. The LTC fee address uses the same key: import the WIF into an LTC wallet to spend LTC fees.

## 3. Publish (10 min) → unblocks Task 5 (KDF release), Task 6 push, Task 9 Steps 6–7, Task 13

- [ ] Run `bash ~/digibyte-dex/digibyte-wallet/ops/tools/m0_publish.sh`. It asks before each step and does the following:
  - creates the forks and the private repo;
  - adds the `origin` remotes;
  - disables the coins fork's cron and Discord workflows;
  - pushes the branches.
- [ ] Then tell Claude "forks are up". Claude then:
  - commits the fee key (Task 3);
  - tags `dgb-v3.0.0-beta.1` and watches the release CI (Task 5);
  - pins the SDK's `build_config.json` to the release and coins hashes (Task 9 Steps 6–7).

## 4. VPS (15 min) → unblocks Task 11 (seed node)

- [ ] DNS A record: `seed1.digiscope.me` → `134.199.198.90`.
- [ ] Firewall: allow inbound TCP 15847, e.g. `ufw allow 15847/tcp comment 'kdf seed netid 2014'`. **Do not touch** the ElectrumX connlimit rules or the watchdog.
- [ ] Tell Claude it can install the seed. Claude runs `ops/seed/install.sh` over ssh and checks the result: the service is active, 15847 is reachable, and ElectrumX is still healthy.

## 5. Funding (real money, small) → unblocks Task 12 (bot) and Task 15 (phone swaps)

- [ ] **Bot wallet** (addresses printed during Task 12): ≤ 2,000 DGB and ≤ 0.5 LTC.
- [ ] **Phone wallet** (addresses shown in the probe app): ≤ 1,000 DGB and ≤ 0.1 LTC.
- [ ] Write down the phone wallet's seed (the app's "Show seed" button) and back up `~/.config/dgb-dex/bot/MM2.json` offline. Both control funds.

## 6. Phone (30–60 min) → M0 exit (Task 15)

- [x] Android phone connected: Moto G 5G 2023 (`ZY22HVMNKZ`, Android 14). The Note 8 is left alone for your other project.
- [ ] Two small swaps: buy DGB with LTC, then sell DGB for LTC. Keep the app in the foreground for about 20 minutes each.
- [ ] Optional: an iPhone plus a Mac with an Apple developer account, for the iOS check.

## Already built and reviewed (all local, nothing pushed)

| Repo (`~/digibyte-dex/…`) | Head | What's there |
|---|---|---|
| `kdf` | `fb79d4f` | Netid 2014 default; 1% fee on `DGB`/`DGB-*` pairs (2% otherwise); release workflow (Android arm64/armv7, iOS, Linux) gated on fee tests, least-privilege token; Rust pinned 1.94.0. Linux release build verified locally. **Waiting:** fee key (Task 3). |
| `sdk` | `cf40ccd` | `KomodoDefiSdkConfig(network: KdfNetworkConfig(netId, seedNodes))` threaded to both KDF start paths; never falls back to 6133 seeds for a custom netid. **Waiting:** `build_config.json` → your KDF release + coins fork (needs publish). |
| `coins` | `a7bce7e` | Seed `seed1.digiscope.me` (netid 2014), SSL-only DGB servers incl. digiscope; configs regenerated. **Waiting:** push. |
| `digibyte-wallet` | `83f53c2` | Price feed (live); seed-node installer + unit; bot config/unit/start script (auto re-applies after restart); `ops/tools/` fee-key checker, KDF-compliant password generator, publish script; M0 probe app (fill-or-kill orders only, double-tap guarded, fail-closed swap status). **Waiting:** APK build after publish; real orderbook fixture from the bot. |

Every piece passed an independent review. The rulings and deferred minor findings are recorded in the local ledger. Claude resumes from that ledger.

## Things found while you were away (FYI)

- **KDF password rule.** KDF refuses to start unless `rpc_password` has at least 8 characters, including an uppercase letter, a lowercase letter, a digit and a special character, and no character three times in a row. The original plan used plain hex, which would have failed. The scripts now use `ops/tools/gen_rpc_password.sh`.
- **Seed install permissions.** Review also caught that `/etc/kdf-seed` would have been unreadable by the seed's service user. This is fixed.

- **Price feed source.** CoinGecko blocks the dev machine (403) and Binance refuses US locations, so the bot's price feed uses **CoinPaprika**. It is running as a user service: `systemctl --user status dgb-price-feed`, `curl -s 127.0.0.1:8765/api/v2/tickers`. The app's planned CoinGecko → Binance price sources (spec §7.1) may hit the same blocks for US users, so check this in M1.
- **Digiscope WSS.** The coins repo's electrum scanner got a WebSocket **1011 internal error** from `electrum.digiscope.me:50004`, although a plain handshake returns 101. The phone app uses SSL (50002), so this is not blocking, but web wallets would fail. Worth a look in the ElectrumX logs.
- **DGB SSL headroom.** DGB has exactly 3 SSL servers, because cipig's `dgb.electrum3` has been down since 2026-09-28. During digiscope's daily 4am restart, only cipig's two servers remain.
  - Asking cipi about electrum3 would help.
  - A second DigiByte-run SSL server is already planned for M2.
- **Server order.** The coins generator sorts servers by URL, so digiscope ends up **last** in the generated DGB list. If the app should prefer digiscope, M1 has to set that explicitly.
- **Rust version.** KDF doesn't compile with the newest Rust (1.98.1). The fork pins 1.94.0.
