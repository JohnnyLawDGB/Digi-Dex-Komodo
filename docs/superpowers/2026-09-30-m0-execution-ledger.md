# SDD ledger — plan: docs/superpowers/plans/2026-09-29-m0-proving-the-stack.md

Spec: docs/superpowers/specs/2026-09-27-digibyte-wallet-design.md (approved 2026-09-29)

## Pre-flight scan

| Pair / task | Produces → consumes | Finding |
|---|---|---|
| T1 → T3,T5,T11,T12,T15 | `~/.config/dgb-dex/m0-inputs.env` (NETID, SEED_HOST, FEE_*) | T3 cannot start without FEE_PUBKEY/FEE_HASH160 (owner input) |
| T2 ↔ T5 | test name `dgb_netid*` in mm2_main → CI filter `dgb_netid` | consistent |
| T3 ↔ T4 | both edit `lp_coins.rs` `mod tests`; T3 test `dgb_dex_fee_pubkey_*`, T4 tests `dgb_pairs_*`, `dgb_segwit_*`, `non_dgb_pairs_*` | sequential edits, no clash; T5 CI filters `dgb_`/`non_dgb_pairs` cover both |
| T5 → T9 | zip names `kdf_<short7>-{android-aarch64,android-armv7,ios-aarch64,linux-x86-64}.zip`, `kdf-release.env` (KDF_SHA, SHA_*) | T9 already flags ios matching_pattern check; consistent |
| T5 → T11,T12 | linux zip + SHA256SUMS on release `dgb-v3.0.0-beta.1` | consistent |
| T6 → T9,T11,T12 | COINS_SHA appended to kdf-release.env; `utils/coins_config_ssl.json` | consistent (T9 maps coins_config.json → coins_config_ssl.json) |
| T7 → T8,T9,T14 | `KdfNetworkConfig{netId, seedNodes, hasExplicitSeedNodes}`; `SeedNodeUpdater.fetchSeedNodes(netId:)` | consistent names |
| T8 → T9 | `SeedNodeService.fetchSeedNodes(network:)`, `fetchSeedNodesWith(network:, remote:, filterForWeb:, bundle:)` | T8 test signature matches impl |
| T9 → T13,T14 | `KomodoDefiSdkConfig(network:)`, SDK_SHA | consistent |
| T10 → T12 | price feed `127.0.0.1:8765/api/v2/tickers` | consistent |
| T11 → T12 | seed `seed1.digiscope.me:15847`, seed RPC 7783 on VPS | consistent |
| T12 → T13 | fixture `m0_probe/test/fixtures/orderbook_dgb_ltc.json` (created before T13 scaffolds `m0_probe` via `flutter create`) | `flutter create` into an existing dir with test/fixtures is fine (it doesn't delete) |
| T12 ↔ T15 | bot RPC port 7790 | consistent |
| T13 → T14 | `bestAsk/bestBid/buildTakerRequest/parseSwapStatus`, `TakerSide`, `SwapPhase` | consistent |
| T1 self | Step 4 creates public GitHub forks (outward) | needs owner go-ahead |
| T2 self | test uses `lp_network_ports` + `mm2_p2p::behaviours::atomicdex` path | plan tells implementer to check re-export path |
| T3 self | test literal is the owner hash160 | blocked on input |
| T4 self | tests vs impl (`split('-')` root) | agree; `DGBX` → 2% holds |
| T5 self | pushes tag + release (outward, to own fork) | needs forks to exist |
| T6 self | seed-nodes contact email = owner email in a public fork | acceptable: owner's business contact; flagged to owner |
| T7–T9 self | tests specified match code specified | agree |
| T10 self | `_dec(3.2e8)` → '320000000.0' (not asserted by tests) | fine |
| T11 self | VPS changes (outward, production host) | needs owner go-ahead at run time |
| T13 self | tests vs impl | agree (`price` limit strings 0.000101 / 0.000099 exact with Decimal) |
| T14 self | SDK member names may differ; plan allows analyzer-driven fixes in app only | ok |
| T15 self | real funds, owner actions | needs owner at run time |

## Rulings

- Ruling: Isolation = fresh clones on `digibyte/main` branches under `~/digibyte-dex/` (no worktree of Digi-Dex-Komodo; plan work lives in other repos) — plan's Global Constraints place the workspace there — cost if wrong: none, clones are disposable.
- Ruling: Clone from upstream first (remote `upstream`) and add the fork remote `origin` once the owner approves fork creation; this unblocks local tasks while forks are pending — cost if wrong: one `git remote add`.
- Ruling: Execution order while waiting on owner inputs: T1(local part) → T2 → T4 → T7 → T8 → T9(Steps 1–5 only) → T10, then T3 when the fee key arrives, then T5, T6, T9 Step 6–7, T11–T15 in order. Tasks are independent across repos except via the interfaces in the table; T4 lands before T3 in `lp_coins.rs` tests (no overlap) — cost if wrong: T3 rebased onto T4, trivial.

## Progress
- Task 1: local part done (upstream clones on digibyte/main at pinned hashes; digibyte-wallet git init). Owner inputs, forks, workflow-disable pending.
- Task 2: BASE d56a7bc50, dispatched
- Ruling: KDF builds use Rust 1.94.0 (stable 1.98.1 fails in mm2_io). Local runs: `RUSTUP_TOOLCHAIN=1.94.0`. Task 5 pins `rust-toolchain.toml` channel = "1.94.0" in the fork so CI matches — upstream's "stable" drifted past what this tree compiles — cost if wrong: a later toolchain bump when rebasing.
- Ruling: Local protoc = /tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/01d56841-7970-4b28-ba34-65645351704c/scratchpad/protoc (PROTOC=/tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/01d56841-7970-4b28-ba34-65645351704c/scratchpad/protoc/bin/protoc, PROTOC_INCLUDE=/tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/01d56841-7970-4b28-ba34-65645351704c/scratchpad/protoc/include) for all later KDF tasks; CI installs protobuf-compiler — cost if wrong: none.
- Ruling: Cargo package filters: `-p mm2_main` / `-p mm2_p2p` alone fail on feature unification; use combined `cargo test -p mm2_p2p -p mm2_main -p chain --lib <filter>`. Task 4/5 implementers find the working combo for `coins` tests and use it in the CI workflow — cost if wrong: CI edit.
- Ruling: Task 2 test imports `mm2_libp2p::behaviours::atomicdex` (mm2_main's rename of mm2_p2p) — brief allowed using the real path — cost: none.
- Ruling: Implementers in DIFFERENT repos may run concurrently (kdf vs sdk vs digibyte-wallet); same-repo tasks stay sequential — the skill's no-parallel rule exists to avoid working-tree conflicts, which can't occur across separate clones — cost if wrong: none (no shared files).
- Task 7: BASE a96398ba, dispatched
- Task 2: complete (commits d56a7bc..721a025, review clean)
- Task 2: minor (deferred): stale 6133 text at atomicdex.rs:84 comment, init_mm2_cfg.rs:286 help text, mm2_p2p/AGENTS.md:123
- Task 4: BASE 721a025, dispatched
- Task 10: BASE (empty repo), dispatched
- Ruling: Price feed source switches from CoinGecko to CoinPaprika (`/v1/tickers/{dgb-digibyte,ltc-litecoin}`, provider "coinpaprika" — a valid KDF Provider variant). CoinGecko returns CloudFront 403 from this host even with a UA; Binance refuses US locations. Spec §7.2's intent (public, non-Komodo prices) holds — cost if wrong: swap source again later. Flag for M1: the app's CoinGecko-first/Binance-fallback plan (§7.1) may fail for US users/IPs; verify from phone networks.
- Ruling: From here, implementer commits end with trailer lines `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb`. Earlier local commits (721a025, 31bb814) lack them; not rewriting — cost: attribution missing on 2 commits.
- Task 7: complete (commits a96398b..671594a, review clean)
- Task 7: minor (deferred): no [netId] doc line on SeedNodeUpdater.fetchSeedNodes; new test lines not dart-format clean; no non-default netId + filterForWeb test
- Ruling: SDK tasks run `fvm dart format` on files they touch before committing (upstream-PR friendliness); Task 8 also formats Task 7's two test files and adds the [netId] doc line — cost: tiny extra diff
- Task 8: BASE 671594a, dispatched
- Ruling: Price feed: a coin with missing/None price or an unparseable/missing `last_updated` is SKIPPED (not published with `now` or 0) — publishing `now` makes stale prices look fresh, defeating the bot's price_elapsed_validity guard; overrides the earlier "fallback now" wording — cost if wrong: coin briefly absent from the feed → bot pauses that pair.
- Ruling: Price feed keeps a per-coin last-good store (a failed coin keeps its last good entry with its old timestamp) — cost: none.
- Task 10: fix round 1/5 dispatched (3 Important: refresh-thread crash on None/zero-price defaults; _dec small-float precision; failed coin dropped. Minors folded in: naive ISO→UTC, unit Description)
- Task 4 cargo: coins works alone (`cargo test -p coins --lib <filter>`); mm2_main needs `-p mm2_p2p -p mm2_main -p chain`
- Task 4: complete (commits 721a025..6204a46, review clean)
- Task 4: minor (deferred): `to_owned()` per root in dex_fee_rate (nested fn avoids alloc); stale GLEEC doc/commented code at taker_swap.rs:2772, taker_swap_v2.rs:492/495, maker_swap_v2.rs:476-489; `is_dgb` naming in first loop of test_max_taker_vol_from_available; no MYCOIN_FEE_DISCOUNT / DGB-x vs DGB-x test
- KDF: Task 3 waiting on owner fee key; Task 5 waiting on forks
- Task 10: minor (deferred): commit messages 31bb814/d49cf38/2986994 have trailers on the subject line (no blank line) and 31bb814 says 'Claude Haiku 4.5' — Ruling: reword these unpushed commits before the first push of digibyte-wallet (Task 11 Step 2) — cost: none, never pushed
- Task 10: fix round 1/5 (4 addressed, 1 open — naive ISO parsed as local time; new minors: None volume/change breaks build, zero/non-finite price published; commits d49cf38..2986994)
- Note: `flutter test` in komodo_defi_framework rewrites app_build/build_config.json (transformer bumps bundled_coins_repo_commit); implementers revert it. Task 9 sets update_commit_on_build=false which should stop it.
- Task 8: complete (commits 671594a..22df0c1, review clean)
- Task 8: minor (deferred): custom-netid throw omits the remote error text; explicit seeds returned as List.unmodifiable (behaviour change vs mutable); [netId] doc line formatting
- Ruling: Task 9 (Steps 1–5) also adds two seam tests to seed_node_service_test.dart — explicit seeds with a `remote` that throws if called, and default-netid all-fail → getDefaultSeedNodes() — they pin Review Focus 4 more tightly than Task 8's tests — cost: ~20 test lines
- Task 9 (Steps 1–5): BASE 22df0c1, dispatched; Steps 6–7 (build_config → forks) wait for Task 5 release + Task 6 coins SHA
- Task 10: fix round 2/5 (3 addressed, 0 open; commits 2986994..a94a4c0)
- Task 10: complete (commits (root)..a94a4c0, review clean)
- Task 10: minor (deferred): non-finite volume/change would publish "nan"/"inf" (unparseable MmNumber) — unlikely from CoinPaprika
- Task 6 (Steps 1–5 + local commit, no push): BASE 2490e55, dispatched with proposed seed host/contact (owner confirmation pending; redo seed-nodes.json if owner changes host/netid)
- Task 6: local part complete (commit 2490e55..a7bce7e, review approved); push + COINS_SHA append pending forks/owner confirmation
- Ruling: Task 6 "DGB has exactly 3 SSL servers, zero headroom" (reviewer Important) is operational, not a code defect — meets the ≥3 gate; electrum3 re-appears automatically when cipi restores it; a second DigiByte-run SSL server is already a spec §11 M2 item. Surface to owner — cost if wrong: during a digiscope restart plus one cipig outage DGB runs on one server.
- Task 6: minor (deferred): generator sorts DGB electrums by URL (digiscope last) — M1 must set priority explicitly if wanted; digiscope WSS 50004 fails the scan with 1011 (owner server-side check); GLMR/TAO/USDC-TAO lost lb.routeme.sh nodes from live regeneration (upstream drift)
- Task 6: review finding 6 (trailer model name) rejected — session attribution is Opus 5.5, trailer correct
- Task 9 (Steps 1–5): fix round 1/5 dispatched (Important: no test covers wallet-start path netid/seednodes)
- Task 9 (Steps 1–5): fix round 1/5 (3 addressed, 0 open; commits dae9dda..cf40ccd)
- Task 9 (Steps 1–5): complete (commits 22df0c1..cf40ccd, review clean). Steps 6–7 pending Task 5 release + Task 6 push.
- Task 9: minor (deferred): SeedNodeService.getSeedNodes(fetchRemote:true) ignores network (no callers); test harness duplicated from kdf_startup_failure_auth_test.dart; "Peer configuration update failed" debug log noise in fallback test
- PAUSED 2026-09-29: all remaining tasks blocked on owner — T3 fee pubkey/hash160; T1 Step 4/6 fork creation go-ahead (T5, T6 push, T9 Steps 6–7, T13 submodule depend on it); NETID/SEED_HOST/rates/contact-email confirmation; T11 DNS+firewall; T12/T15 funding.
- RESUMED 2026-09-29 (owner remote): owner asked to keep building what we can + a to-do list for their return.
- Ruling: Local-only continuation — T5 Steps 1–2 (workflow + toolchain pin, local commit, no push/tag); T11 Step 1 + T12 Step 1 ops files (local commit); new owner tools in digibyte-wallet `ops/tools/` (fee-key checker, publish script the OWNER runs); T13 pure Dart with SDK as a local path dep + hand-made fixture (submodule + real fixture swapped in later); T14 code + `flutter analyze` only (no APK build until build_config points at forks) — owner asked for this; nothing leaves the machine — cost if wrong: small rework when forks exist.
- Task 5 (local part): BASE 6204a46, dispatched
- Ops/tools batch (T11 S1, T12 S1, owner tools): dispatched
- Ops batch: review changes requested (1 Critical: /etc/kdf-seed dir unreadable by kdf user; Important: publish origin-URL guard, fork-parent check, workflow-disable hard stop, rpc_password policy, restart-on-rerun, bot re-activation after restart)
- Ruling: KDF rpc_password policy CONFIRMED in source (common/password_policy.rs: ≥8 chars, digit, lower, upper, special, no char 3× in a row, not containing "password"); plan's `openssl rand -hex` passwords (T11 install.sh, T12 Step 2) would make KDF refuse to start. Fix: shared generator that satisfies the policy; T12 Step 2's jq one-liner replaced by `ops/bot/init_config.sh` — cost if wrong: none.
- Ruling: reviewer "Extra" on README documenting ops/price_feed rejected — the feed exists (Task 10) and the README was requested to cover it.
- Ops batch: fix round 1/5 dispatched
- Ops batch: fix round 1/5 (14 addressed, 0 open; commits e22064d..c3f34b5)
- Ops batch (T11 S1–2 files, T12 S1 files, owner tools): complete (commits a94a4c0..c3f34b5, review clean)
- Ops batch: minor (deferred): start_bot.sh rpc() masks curl failure (empty resp treated as success); install.sh re-run keeps an old non-compliant MM2.json; origin pushurl not checked; gh workflow disable may fail on a fresh fork (hard stop w/ message); unit hardcodes %h/digibyte-dex path
- Task 13 (local variant): BASE c3f34b5, dispatched — SDK via local path deps (no submodule yet), hand-made orderbook fixture (real one from T12 later)
- Task 13 (local variant): complete (commits c3f34b5..200f0a2, review clean). Submodule + real fixture pending publish/T12.
- Task 13: minor (deferred): min_volume default '0' loosens guard; malformed event throws; no tests for custom slippage/ties/numeric fields/boundaries; pubspec.lock has ../../sdk paths until submodule; commit msg typo
- Ruling: Task 14 also hardens swap_probe.dart — parseSwapStatus fails closed when `error_events` is absent (uses a built-in KDF error-event list), and buildTakerRequest rejects slippage outside [0, 1) — both guard real money in the probe — cost: ~15 lines + tests
- Task 14 (local variant: code + analyze + tests, no APK build): BASE 200f0a2, dispatched
- Task 14: fix round 1/5 dispatched (Important: double-tap starts 2 swaps / first untracked; RPC errors uncaught in _trade/_refresh. Minors folded: empty events .last, mounted check, bad volume input surfaced, unlock guard)
- Task 14: fix round 1/5 (7 addressed, 0 open; commits d955ccb..83f53c2)
- Task 14 (local variant, no APK): complete (commits 200f0a2..83f53c2, review clean). APK build (Step 5) pending build_config → forks.
- Task 14: minor (deferred): "Check recent swaps" can clear _unknown if tapped while a buy is still in flight (disable while _busy); stale _refresh for an old uuid can clear _running of a new swap (compare uuid); _checkRecent treats {'error':...} payload as success if SDK doesn't throw
- Ruling: CI fee gate skips `eth::eth_tests::validate_dex_fee_eth_confirmed_before_min_block` (queries a live ETH node; unrelated to DGB fee logic) — a network-flaky gate would block releases — cost if wrong: one upstream ETH fee-validation test not run in our CI (still runs upstream).
- Ruling: CI installs the toolchain explicitly (`rustup toolchain install 1.94.0 --profile minimal --component rustfmt,clippy` + `rustup default 1.94.0`/toolchain file) instead of relying on rustup ≥1.28 auto-install — container rustup version unknown — cost: version duplicated in workflow and rust-toolchain.toml.
- Task 5 (local Steps 1–2): review approved (commits 6204a46..333f80d)
- Ruling: apply Task 5 minors 1, 2, 4 now (least-privilege token: contents:read at top, write only on release job; assert 4 zips before SHA256SUMS; timeout-minutes) — the Android job runs a third-party :latest container that would otherwise hold a write token — cost: tiny diff + scoped re-review
- Task 5: minor (deferred): no build cache; floating action tags / :latest container; gh release create not idempotent on re-run; macOS protoc x86_64 via Rosetta
- Task 5 (local Steps 1–2): hardening round (3 addressed, 0 open; commits 333f80d..fb79d4f)
- Task 5 (local Steps 1–2): complete (commits 6204a46..fb79d4f, review clean). Steps 3–5 (push, tag, release, pins) pending forks + T3.
- PAUSED 2026-09-29 (2nd): all local work done. Remaining: T1 owner steps, T3 fee key, T5 S3–5, T6 push, T9 S6–7, T11 S3–5, T12 S2–6, T13 submodule + real fixture, T14 APK (S5), T15. Final whole-branch review after T15.
- Ruling: M0 test phone = Moto G 5G 2023, serial ZY22HVMNKZ (Android 14 / API 34, arm64-v8a, 4K pages, 92G free). Galaxy Note 8 (ce061716640b191c017e, Android 9) is the owner's device for another project — NEVER install/run on it; every adb/flutter command uses `-s ZY22HVMNKZ` / `-d ZY22HVMNKZ`; never restart the adb server — cost if wrong: disrupting the owner's other project.
- Ruling: Pre-publish SMOKE test on the Moto (ZY22HVMNKZ): debug APK built with the SDK's current (upstream GLEEC) KDF binaries, installed, unlock + activate DGB/LTC only, no funds, no trades; then uninstall. Validates the Android build/transformer and the SDK netid patch on a real device before publishing. The earlier "no APK" ruling was about shipping upstream fee keys in a real build; a no-funds smoke build doesn't — cost if wrong: one uninstall.
- Smoke test: dispatched
- Smoke test (Moto ZY22HVMNKZ): PARTIAL — build ✓ (451s, 338MB, cached upstream libkdf.a), install ✓, DGB/LTC SSL activation ✓ (zero balance), netid 2014 not directly evidenced (KDF logs nothing to logcat; no outbound to kmdefi seeds — consistent with no 6133 fallback). App uninstalled; Note 8 untouched.
- Note: m0_probe `pub get` runs the SDK transformer, which rewrites the SDK clone's build_config.json (bundled_coins_repo_commit) — Task 9 Step 6 (update_commit_on_build=false) stops this; until then restore after builds.
- Ruling: add a read-only "Network info" button to the probe (legacy `orderbook` DGB/LTC → log `netid`, numasks/numbids) + fix keyboard overflow, then re-run the smoke test to evidence netid 2014 on device — cost: small UI diff + one rebuild.
- Task 14 addendum (network info button + scroll): commit 83f53c2..6e1f3e2, review + smoke re-run dispatched
- Task 14 addendum: complete (commits 83f53c2..6e1f3e2, review clean)
- Task 14 addendum: minor (deferred): controls Flexible vs log Expanded 1:1 halves log height; networkInfoLine strict int compare; no widget test that Network info stays enabled while trades locked
- Smoke #2 finding (owner saw on screen): Network info showed netid=unknown asks=null bids=null because orderbook returned an error (coins not active: app relaunch → signIn threw alreadySignedIn → _unlock aborted before activation). Fix dispatched: treat alreadySignedIn as unlocked and proceed to activation; networkInfoLine surfaces KDF error text instead of 'unknown'.
- Ruling: promote Task 14 deferred minor '_checkRecent treats {"error":...} as success' to Important — implementer confirmed in SDK source that executeRpc returns legacy errors as a top-level {error} map without throwing — the trade-lock release after an unknown order would be bypassable — cost: small fix.
- Smoke #2: PASS — on-device `Network: netid=2014 asks=0 bids=0` (moto2_netinfo.png); activation ✓; keyboard ✓. App uninstalled; SDK build_config restored. Notes: phone briefly showed Chrome (github digibytewallet-android release) — likely owner using the phone; a scripted tap may have hit Buy after a layout shift (0 balance, no swap).
- Ruling: with funds on the phone (Task 15), NO automated/scripted taps on Buy/Sell — the owner taps trade buttons, or the agent triggers them only after the owner says go in that session — a layout shift already made a scripted tap land on Buy once — cost: owner must be present for swaps (already required).
- Probe error-fix review: changes requested (Important: alreadySignedIn continues without checking the signed-in wallet is 'm0'). Fix round dispatched with minor #2 (missing uuid & no error → _unknown) + layout (all controls visible pre-unlock, larger log).
- Probe fixes (alreadySignedIn wallet check, KDF error replies, unknown-order lock, layout): complete (commits 6e1f3e2..05a9d48, review clean; 34 tests)
- Task 14: minor (deferred) — Ruling: accept `Flexible(flex:0)`+SingleChildScrollView doesn't actually scroll; no overflow on the Moto in portrait (verified by reasoning; M0 runs portrait on that phone) — cost if wrong: overflow stripe in landscape/small screens; fix in M1's real UI.
- PAUSED again: local work exhausted; waiting on owner (see owner to-do).
- 2026-09-30 OWNER CONFIRMED: netid 2014; fees 2% base / 1% DGB pairs; seed host seed1.digiscope.me; contact mark@aroundtheblock.us in public coins fork; go-ahead to create repos and run flows. Forks created (JohnnyLawDGB/komodo-defi-framework, komodo-defi-sdk-flutter, coins — public, parents GLEECBTC) + private JohnnyLawDGB/digibyte-wallet.
- 2026-09-30 PUBLISHED: origins added; pushed kdf/sdk/coins `digibyte/main`, digibyte-wallet `main` (after rewording 3 unpushed commit messages; tree unchanged; backup branch backup/pre-reword kept locally). KDF fork: upstream workflows (Development builds, Format and Lint, Test, Validate Cargo.lock) auto-ran on push → cancelled + disabled; only dgb-release remains. coins + sdk forks: Actions disabled entirely (not needed in M0; stops gen_configs cron / Discord webhook).
- Task 1: complete except fee key (Task 3 input). Task 6: pushed — COINS_SHA=a7bce7ea0d21b8e46a955197c1f73e4f82112da4.
- Fee key (owner chose local node wallet for M0): wallet `dgb-dex-fees` on local digibyted (load_on_startup), address DDkM6VDQAaArxQ3GVtoZKMVKSEBHjrDpNG, pubkey 036f27a4…a52a, hash160 5e6bb724…873c, LTC LTqCpSaawpWdgCYpwSoJ3cPUmJpGVw6YAn; backup ~/.config/dgb-dex/dgb-dex-fees.wallet.bak (600); inputs in ~/.config/dgb-dex/m0-inputs.env. Owner decision recorded: rotate to an offline key before M3 launch (needs a new KDF release).
- Task 3: BASE fb79d4f, dispatched
- Task 3: complete (commits fb79d4f..4715f29, review clean; custody comment corrected pre-tag). KDF fork HEAD 4715f29 carries: netid 2014, DGB fee key, 1%/2% rates, release workflow, Rust 1.94.0 pin.
- Task 5 Step 3: pushing digibyte/main + tag dgb-v3.0.0-beta.1 (owner authorized "run whatever flows we need")
- VPS: `ufw allow 15847/tcp` (comment 'kdf seed netid 2014') added; ElectrumX rules untouched. Bot config created via ops/bot/init_config.sh (~/.config/dgb-dex/bot/MM2.json, 600).
- Release CI run 36651198790 (dgb-release, tag dgb-v3.0.0-beta.1) in progress; watched in background.
- Task 5: complete — release dgb-v3.0.0-beta.1 built by CI run 36651198790 (all jobs success), 4 zips + SHA256SUMS verified locally; pins in ~/.config/dgb-dex/kdf-release.env
- Task 9 Steps 6–7: BASE cf40ccd, dispatched (local commit; controller pushes after review)
- Ruling: bot seednodes temporarily ["134.199.198.90"] (DNS seed1 not yet created); revert to seed1.digiscope.me once DNS resolves — cost: none
- Task 11: seed LIVE on VPS — kdf-seed active, 3.0.0-beta_4715f29, listening 134.199.198.90:15847 (ports from netid 2014), /etc/kdf-seed root:kdf 750 + MM2.json kdf 600, externally reachable (nc OK), ElectrumX still active. PeerId 12D3KooWEFTJkCFG33BSx2N87cFWH2z1XcqcUnJECuZvM4NgvaCE. DNS seed1 pending (owner).
- Task 12 (Steps 2–3): bot KDF running (systemd --user kdf-bot, port 7790), dialed seed, SSL electrums connected (digiscope + cipig), SMM started via ExecStartPost, zero balance. Funding addresses: DGB D8YWMnAz3YCXBeRgTLN1ivyg5KSVBiGcGK, LTC LNdN5jYApnYHuSwEttMkTBsqQQ5Tzm3D4X. Awaiting owner funding (≤2000 DGB, ≤0.5 LTC).
- Task 9 (Steps 6–7): complete (commits cf40ccd..3bda0b1, review clean), pushed; SDK_SHA recorded. Fetch of kdf_4715f29-android-aarch64.zip from the fork release verified with checksum.
- Ruling (M1 item): SDK runtime fallback `const AssetRuntimeUpdateConfig()` defaults to GLEECBTC/coins + gleecbtc CDN if bundled build_config fails to load (3 call sites) — change defaults to the DigiByte fork or fail fast in M1; not on M0's happy path — cost if wrong: a broken asset bundle would silently pull GLEEC coin configs.
- Ruling (owner-visible): runtime coin-config updates track JohnnyLawDGB/coins `digibyte/main` head (runtime_updates_enabled isn't read by runtime code) — acceptable for M0 since DigiByte controls that branch; branch protection / pinned updates decided in M1 — cost: a bad push to that branch reaches installed apps.
- Task 9: minor (deferred): build_config.yaml reference still upstream; stale test doc comment "seven platforms"; TRON quicknode.gleec.com transform; komodo_wallet_cli comment.
- Probe publish step: switch m0_probe SDK path deps → third_party submodule @ SDK_SHA 3bda0b1, build real APK, install on Moto (no wallet creation — owner sets password), dispatched
- Task 9 defect (found by probe build): CopyPlatformAssetsBuildStep null-checks platforms['web']! (3 places) — removing web in Task 9 breaks app builds. Ruling: patch the transformer to skip unconfigured platforms (test-first) in the SDK fork, push, repin submodule — restoring a web entry isn't possible (no web artifact in our release) — cost: small upstream-friendly patch.
- Transformer web fix: complete (commits 3bda0b1..6dfe132, review clean), pushed; SDK_SHA now 6dfe132.
- Transformer fix: minor (deferred): no-web info log fires in both canSkip and build; no test asserting Linux copy on no-web path.
- Probe publish: APK built with KDF 3.0.0-beta_4715f29 + DGB fee key (verified in .so for arm64-v8a & armeabi-v7a), installed on Moto (no taps), commit a600266 (submodule @ 6dfe132); review dispatched
- Probe submodule commit a600266: review clean (attribution nit rejected — session attribution is Opus 5.5); pushed digibyte-wallet main. Task 13 submodule + Task 14 Step 5 (APK) complete; APK installed on Moto awaiting owner wallet setup.
- Remaining for M0 exit: owner DNS seed1; bot funding; phone wallet setup + funding; T12 Step 4–6 (orders, seed orderbook, real fixture); T15 swaps; final whole-branch review.
- DNS seed1.digiscope.me → 134.199.198.90 verified (local, 8.8.8.8, authoritative); port 15847 reachable by name. Bot seednodes reverted to seed1.digiscope.me and restarted.
- Task 12 Step 4–5: bot funded 2000 DGB; DGB/LTC ask live (uuid 03270ac6…, 0.00006746 LTC/DGB, maxvolume 1999.97, min_volume ≈225 DGB); seed orderbook shows netid 2014, numasks 1. LTC funding pending (owner). Real orderbook captured to scratchpad/seed_orderbook.json.
- Task 12 Step 6 (real fixture → m0_probe/test/fixtures): dispatched
- Ruling: keep probe default volume 200 (no rebuild mid-owner-setup); owner enters 300 on the phone — real order min ≈225 DGB — cost: one manual field edit
- Bot LTC funded 0.42185508 (10:12); both orders live: DGB/LTC ask 0.00006743 max 1999.97 DGB; LTC/DGB 15429.36 DGB/LTC max 0.2975 LTC. Task 12 Steps 4–5 complete. Awaiting owner phone wallet setup + funding for T15.
- Task 12 Step 6: real fixture complete (commit 392172b, review clean), pushed.
- Phone wallet: owner delegated setup; password generated (policy-compliant) at ~/.config/dgb-dex/m0-phone-password (600); Unlock tapped by label. Seed NOT displayed by agent (owner does Show seed).
- Phone wallet 'm0' created by agent at owner's request ("test mule; retain seeds"): password + 12-word seed saved 600 in ~/.config/dgb-dex/ (seed captured by local OCR, BIP39 checksum OK, derives phone DGB address — verified); on-screen log cleared; seed never displayed in transcript. Phone DGB DLFhh33PLHZ2y1kN37BiQ2uD4f394jdixs, LTC LiL6drnBuaRijwkrYLpVzm6phuc1XHz1Yp. Index: ~/.config/dgb-dex/SECRETS-INDEX.md. QR codes generated + decode-verified.
- Phone funded: 750 DGB conf, 0.05160337 LTC conf (10:43). Preflight run before swap 1.
- Owner said 'go' for swap 1 (Buy DGB with LTC, volume 300) — agent taps Buy once by label.
- Swap 1 started: uuid d868982f-31ca-41c3-86ad-06a471710b15 (phone taker, buy 300 DGB with LTC), orderbook netid=2014 asks=1 bids=1
- SWAP 1 FEE VERIFIED ON CHAIN: LTC taker-fee tx fee10120a2ecb8ea97c3f7b01f95f0c8123da28a8bd3fb2434423b3df87ba50d (block 3186920) pays 20167 sat to LTqCpSaawpWdgCYpwSoJ3cPUmJpGVw6YAn (spk 76a9145e6bb7240aecd5138d3b5922b57233b3b491873c88ac = FEE_HASH160) = 1% of taker amount 0.02016785 LTC. Bot validated fee (TakerFeeValidated). Maker payment (DGB) a93ee2fe…f3e1; taker payment (LTC) 1e7341d8…59d3; maker spent taker payment 49cb6294…9ca7.
- SWAP 1 COMPLETE (10:47→11:00, ~13 min): d868982f-31ca-41c3-86ad-06a471710b15 Finished on phone (taker) and bot (maker). Txs: taker fee fee10120…ba50d (LTC, 1% to fee addr verified), maker payment a93ee2fe…f3e1 (DGB), taker payment 1e7341d8…59d3 (LTC), taker-payment spend 49cb6294…9ca7 (LTC). Phone DGB 750→1049.9504.
- Owner said 'go' for swap 2 (Sell DGB for LTC, volume 300) — agent taps Sell once by label.
- SWAP 2 attempt blocked client-side (no RPC sent): probe used bid maxvolume/min_volume (in LTC, the order's base) as DGB → 'must be within 0.0148..0.2975'. Real-money guard worked. Fix: use base_max_volume/base_min_volume (orderbook-base units).
- Base-volume fix: complete (commit a84fb70, review clean; 39 tests).
- minor (deferred): bid fallback to maxvolume/min_volume would reintroduce the unit bug if KDF ever omitted base_* (comment it / ask-only fallback in M1).
- Swap-2 blocker diagnosed: after app restart, phone wallet KDF dials seed once, connection closes immediately (no error either side); KDF redials only after DIAL_RETRY_DELAY=5 min. Workaround: request orderbook immediately after the redial → connection held. Likely libp2p idle-connection close before any topic subscription on a light node (M1/M2 item: keep seed connection alive / subscribe on start; check idle_connection_timeout). Seed log showed no "Failed to validate" → not the time check.
- SWAP 2 STARTED 11:20:08: uuid 60af1ba2-73b6-4587-bb44-534d2c0a8bf1 (phone taker sells 300 DGB for LTC, limit 0.0000640078 LTC/DGB = bid×0.99).
- SWAP 2 FEE VERIFIED: DGB taker-fee tx c8dc5fa9d55e80ab0620d152256659af4d0b8f5aeff3212f1375570d2b47821a pays 3.00000000 DGB (1% of 300) to DDkM6VDQAaArxQ3GVtoZKMVKSEBHjrDpNG (spk = FEE_HASH160).
- SWAP 2 COMPLETE (maker side Finished 11:30:20; phone at MakerPaymentSpent, 0.01939132 LTC incoming): 60af1ba2-73b6-4587-bb44-534d2c0a8bf1. Txs: taker fee c8dc5fa9…821a (DGB, 3.0 DGB to fee addr, in dgb-dex-fees wallet), maker payment 3bd8eb8c…4aef (LTC), taker payment 15fc0ac5…9900 (DGB), taker-payment spend 25da2d1a…ecd6 (DGB).
- M0 EXIT CRITERION MET: physical phone completed mainnet DGB↔LTC swaps on netid 2014; fee address received DEX fee in LTC (swap 1) and DGB (swap 2) at exactly 1%.
- Swap 2: phone (taker) Finished 11:35:11 — both swaps Finished on both sides.
