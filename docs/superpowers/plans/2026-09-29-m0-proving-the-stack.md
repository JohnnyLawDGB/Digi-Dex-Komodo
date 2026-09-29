# M0: Proving the Stack — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A bare Flutter app on a physical Android phone completes a small mainnet DGB↔LTC swap on DigiByte's own KDF network ID, and the DEX fee lands at a DigiByte-controlled fee address.

**Architecture:** Three thin forks and one new repo.
- The **KDF fork** changes four things: the fee public key, the fee rate with DGB as the discount ticker, the default network ID, and a release workflow.
- The **SDK fork** makes the network ID and seed nodes injectable through `KomodoDefiSdkConfig`, and points binary and coin downloads at the forks.
- The **coins fork** carries DigiByte's seed node and SSL-first DGB electrums.
- The **new `digibyte-wallet` repo** holds the M0 probe app, plus the ops files for one seed node, one market-maker bot and a price feed.

**Tech Stack:** Rust stable (KDF), Dart ≥3.9 / Flutter 3.41.4 (SDK and app), Python 3 (coins generator, price feed), GitHub Actions, systemd.

**Spec:** `docs/superpowers/specs/2026-09-27-digibyte-wallet-design.md` (in `JohnnyLawDGB/Digi-Dex-Komodo`, branch `docs/digibyte-wallet-design`). Read §3, §4.1, §6, §7.2, §7.3, §9 and §10 before starting.

## Global Constraints

- **Upstream bases:**
  - KDF: tag `v3.0.0-beta` = `d56a7bc5028f10b9c1bb8370bb2ee16444796a23`
  - SDK: `main` @ `a96398ba9ae72efbe654de7c3edc0bfe2b05dda0`
  - coins: `master` @ `2490e55837d796f990d31a1e272b53acea616b24`
- **Forks** live under GitHub user `JohnnyLawDGB`. Each fork's DigiByte branch is `digibyte/main`. Pin everything by full commit hash.
- **Local workspace:** `~/digibyte-dex/{kdf,sdk,coins,digibyte-wallet}`.
- **DigiByte network ID: `2014`.** The owner confirms it in Task 1. From it, KDF derives P2P TCP port **15847** and WSS port **15857**.
  - M0 uses 2014 directly: it is unpublished until M2, so it is a private network.
  - It must never be 6133, 8762 or 7777.
- **Seed node:** `seed1.digiscope.me` → 134.199.198.90 (the digiscope VPS). The owner confirms it in Task 1.
- **DEX fee:** base rate 2%; pairs that include DGB (any `DGB` or `DGB-*` ticker) pay 1%. The owner confirms the rates in Task 1. The fee and burn public keys are one compressed secp256k1 key that the owner generates.
- **App ID for M0:** `me.digiscope.wallet.m0`. The production ID `me.digiscope.wallet` stays unused until M1.
- **Electrums are SSL only.** DGB order: `electrum.digiscope.me:50002`, `dgb.electrum1.cipig.net:20059`, `dgb.electrum2.cipig.net:20059`.
- **Real-money caps:**
  - Bot inventory is at most 2,000 DGB and at most 0.5 LTC.
  - The phone wallet holds at most 1,000 DGB and at most 0.1 LTC.
  - Test swaps are sized at about US$2–5.
- **No secrets in git:** no passphrases, RPC passwords, fee private keys or keystores. Secrets live in `~/.config/dgb-dex/` (mode 600) or on the VPS under `/etc/kdf-seed/` (mode 600).
- **Toolchain:**
  - Flutter 3.41.4 is pinned with `.fvmrc` in the app repo.
  - Android NDK r23c and API 21 clang for the KDF static libs, matching upstream CI.

## Owner Inputs (collected in Task 1)

| Input | Proposed value | How it's produced |
|---|---|---|
| `NETID` | `2014` | Owner confirms |
| `SEED_HOST` | `seed1.digiscope.me` | Owner adds a DNS A record → 134.199.198.90 and opens TCP 15847 |
| `FEE_PUBKEY` | — | Owner, offline: new DigiByte Core wallet → `getnewaddress "" legacy` → `getaddressinfo <addr>` → `.pubkey` (66 hex chars, starts `02`/`03`) |
| `FEE_HASH160` | — | Same `getaddressinfo` output: `.scriptPubKey` is `76a914<40 hex>88ac`; the 40 hex chars in the middle |
| `FEE_DGB_ADDRESS` | — | The address from that step. The LTC fee address is the same hash160 with LTC's prefix; import the private key into an LTC wallet to spend it. |
| Fee rates | 2% base, 1% DGB pairs | Owner confirms |

## Review Focus

> **Execution note (2026-09-29):** KDF enforces a password policy on `rpc_password` (≥8 chars, digit, lower, upper, special, no char 3× in a row). Plain `openssl rand -hex` values fail it and KDF refuses to start. The ops scripts use `ops/tools/gen_rpc_password.sh`, and the seed installer inlines the same function.

Five inputs or conditions the spec implies but no task's own feature tests cover. Each one has a pinning test in the task named.

1. **`DGB-segwit` as a ticker.** The discount must apply to `DGB-segwit` (and any `DGB-*`) exactly as to `DGB`. Upstream compares exact tickers, so a segwit taker would silently pay 2%. → Task 4 test `dgb_segwit_gets_discount`.
2. **The quoted order vanishes before the taker request lands.** The phone must not be left holding a live maker order (the spec's v1 is taker-only). Every taker request must be `FillOrKill` and `match_by` the quoted uuid. → Task 13 test `taker request is fill-or-kill and pinned to the quoted order`.
3. **Slippage bound.** The price limit sent to KDF must never exceed quote × (1 + slippage) for buys, or fall below quote × (1 − slippage) for sells. It must be exact decimal, not float. → Task 13 tests `buy price limit` / `sell price limit`.
4. **Seed fetch failure while a custom network ID is set.** The SDK must never fall back to the 6133 seeds (`seed01.kmdefi.net`) or report netid 6133 when a DigiByte network ID is configured. With explicit seed nodes it must not fetch remotely at all. → Task 8 tests.
5. **The 4am digiscope restart and monthly compaction.** DGB must keep working when `electrum.digiscope.me` is down, so the coins fork must list at least 3 SSL DGB servers. → Task 6 verification `jq` check.

## Not in M0 (deferred, per spec §10)

- GPG signing of KDF releases (M1 CI).
- Replacing KDF's GLEEC-hosted `PRICE_ENDPOINTS` (used for watcher rewards; M2).
- Trimming the coins fork to listed assets (M1).
- iOS on-device run. M0 builds and publishes the iOS static lib, and the device run needs a Mac with an Apple developer account; if one is available, Task 15 Step 6 covers it.
- DOC/MARTY CI network (M1).
- KDF fork test that a maker rejects a taker fee paid to the wrong address or at the wrong rate (spec §9, "KDF fork" row). It lands with the fork's M1 CI; M0's on-chain check in Task 15 proves the correct-fee path.

---

## Part A — Setup

### Task 1: Owner inputs, forks and workspace

**Files:**
- Create: `~/digibyte-dex/` (directory)
- Create: `~/.config/dgb-dex/m0-inputs.env` (mode 600; never committed)

**Interfaces:**
- Produces: the env file below. Every later task reads it with `source ~/.config/dgb-dex/m0-inputs.env`.
```bash
NETID=2014
SEED_HOST=seed1.digiscope.me
FEE_PUBKEY=<66 hex from owner>
FEE_HASH160=<40 hex from owner>
FEE_DGB_ADDRESS=<D... address from owner>
```

- [ ] **Step 1: Get the owner inputs.** Ask the owner for each row of the Owner Inputs table. Do not continue until `FEE_PUBKEY` and `FEE_HASH160` are provided and the owner has confirmed `NETID`, `SEED_HOST` and the rates.

- [ ] **Step 2: Write the inputs file**

```bash
mkdir -p ~/.config/dgb-dex && chmod 700 ~/.config/dgb-dex
cat > ~/.config/dgb-dex/m0-inputs.env <<'EOF'
NETID=2014
SEED_HOST=seed1.digiscope.me
FEE_PUBKEY=REPLACE_WITH_OWNER_VALUE
FEE_HASH160=REPLACE_WITH_OWNER_VALUE
FEE_DGB_ADDRESS=REPLACE_WITH_OWNER_VALUE
EOF
chmod 600 ~/.config/dgb-dex/m0-inputs.env
```
Then edit the three `REPLACE_WITH_OWNER_VALUE` values.

- [ ] **Step 3: Validate the inputs**

```bash
source ~/.config/dgb-dex/m0-inputs.env
python3 - <<EOF
import hashlib, re, sys
pk = bytes.fromhex("$FEE_PUBKEY"); assert len(pk) == 33 and pk[0] in (2, 3), "not a compressed pubkey"
h = hashlib.new("ripemd160", hashlib.sha256(pk).digest()).hexdigest()
assert h == "$FEE_HASH160".lower(), f"hash160 mismatch: {h}"
print("fee key OK", h)
EOF
```
Expected: `fee key OK <hash160>`. If your OpenSSL build lacks `ripemd160`, run `pip install pycryptodome` and use `Crypto.Hash.RIPEMD160` instead.

- [ ] **Step 4: Create the forks and the app repo.** These are outward-facing; confirm with the owner before running.

```bash
gh repo fork GLEECBTC/komodo-defi-framework --clone=false
gh repo fork GLEECBTC/komodo-defi-sdk-flutter --clone=false
gh repo fork GLEECBTC/coins --clone=false
gh repo create JohnnyLawDGB/digibyte-wallet --private --description "DigiByte wallet and DEX (KDF/SDK based)"
```

- [ ] **Step 5: Clone and branch**

```bash
mkdir -p ~/digibyte-dex && cd ~/digibyte-dex
git clone git@github.com:JohnnyLawDGB/komodo-defi-framework.git kdf
git -C kdf remote add upstream https://github.com/GLEECBTC/komodo-defi-framework.git
git -C kdf fetch upstream --tags
git -C kdf checkout -b digibyte/main d56a7bc5028f10b9c1bb8370bb2ee16444796a23

git clone git@github.com:JohnnyLawDGB/komodo-defi-sdk-flutter.git sdk
git -C sdk remote add upstream https://github.com/GLEECBTC/komodo-defi-sdk-flutter.git
git -C sdk checkout -b digibyte/main a96398ba9ae72efbe654de7c3edc0bfe2b05dda0

git clone git@github.com:JohnnyLawDGB/coins.git coins
git -C coins remote add upstream https://github.com/GLEECBTC/coins.git
git -C coins checkout -b digibyte/main 2490e55837d796f990d31a1e272b53acea616b24

git clone git@github.com:JohnnyLawDGB/digibyte-wallet.git
```
Expected: four directories. `git -C kdf log -1 --format=%H` prints `d56a7bc5…`.

- [ ] **Step 6: Disable the upstream workflows the coins fork inherits.** `gen_configs.yml` runs a daily cron that opens PRs with `cipig` as reviewer, and `validate_seed_nodes.yml` posts to a Discord webhook.

```bash
gh workflow disable gen_configs.yml -R JohnnyLawDGB/coins
gh workflow disable validate_seed_nodes.yml -R JohnnyLawDGB/coins
```

---

## Part B — KDF fork (`~/digibyte-dex/kdf`, branch `digibyte/main`)

### Task 2: DigiByte default network ID

**Files:**
- Modify: `mm2src/mm2_p2p/src/behaviours/atomicdex.rs:64`
- Modify: `mm2src/adex_cli/src/scenarios/init_mm2_cfg.rs:17`
- Modify: `mm2src/mm2_main/src/lp_network.rs` (append test module)

**Interfaces:**
- Produces: `pub const DEFAULT_NETID: u16 = 2014` in `mm2_p2p::behaviours::atomicdex`. KDF only uses this value to switch behaviour. On `DEFAULT_NETID`, floodsub forwarding and PEERS gossip are off, which is the production-network behaviour.

- [ ] **Step 1: Write the failing tests.** Append to `mm2src/mm2_main/src/lp_network.rs`:

```rust
#[cfg(test)]
mod dgb_netid_tests {
    use super::*;
    use mm2_p2p::behaviours::atomicdex::{DEFAULT_NETID, DEPRECATED_NETID_LIST};

    #[test]
    fn dgb_default_netid_is_2014_and_not_deprecated() {
        assert_eq!(DEFAULT_NETID, 2014);
        assert!(!DEPRECATED_NETID_LIST.contains(&DEFAULT_NETID));
    }

    #[test]
    fn dgb_netid_ports() {
        let ports = lp_network_ports(2014).unwrap();
        assert_eq!(ports.tcp, 15847);
        assert_eq!(ports.wss, 15857);
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cargo test -p mm2_main --lib dgb_netid`
Expected: compile error `DEFAULT_NETID is private`. If `mm2_p2p::behaviours` is not a public path, check `mm2src/mm2_p2p/src/lib.rs` for the re-export and use that path instead.

- [ ] **Step 3: Implement.** In `mm2src/mm2_p2p/src/behaviours/atomicdex.rs` replace line 64:

```rust
/// DigiByte DEX network. KDF enables floodsub forwarding and PEERS gossip on any other netid.
pub const DEFAULT_NETID: u16 = 2014;
```
In `mm2src/adex_cli/src/scenarios/init_mm2_cfg.rs:17`:
```rust
const DEFAULT_NET_ID: u16 = 2014;
```
Also change the help text on line 131 from `6133 is the current main network` to `2014 is the DigiByte DEX network`.

- [ ] **Step 4: Run to verify pass**

Run: `cargo test -p mm2_main --lib dgb_netid && cargo test -p mm2_p2p --lib`
Expected: both `dgb_netid` tests pass, and the `mm2_p2p` tests pass.

- [ ] **Step 5: Commit**

```bash
git add mm2src/mm2_p2p/src/behaviours/atomicdex.rs mm2src/adex_cli/src/scenarios/init_mm2_cfg.rs mm2src/mm2_main/src/lp_network.rs
git commit -m "feat(p2p): DigiByte DEX default netid 2014"
```

### Task 3: DigiByte DEX fee public key

**Files:**
- Modify: `mm2src/common/common.rs:222-227`
- Test: `mm2src/coins/lp_coins.rs` (module `tests`, line ~6361)

**Interfaces:**
- Consumes: `FEE_PUBKEY` and `FEE_HASH160` from Task 1.
- Produces: `DEX_FEE_ADDR_PUBKEY == DEX_BURN_ADDR_PUBKEY == FEE_PUBKEY`. Burn stays disabled for UTXO (`utxo_common::should_burn_dex_fee() == false`), so every UTXO fee is one P2PKH output to `hash160(FEE_PUBKEY)`.

- [ ] **Step 1: Write the failing test.** Inside `mod tests` in `mm2src/coins/lp_coins.rs`, add the following, pasting the owner's `FEE_HASH160` literally:

```rust
    #[test]
    fn dgb_dex_fee_pubkey_matches_owner_fee_address() {
        use bitcrypto::dhash160;
        // hash160 of the DigiByte-controlled fee key (owner input FEE_HASH160).
        const DGB_FEE_HASH160: &str = "<FEE_HASH160>";
        assert_eq!(hex::encode(dhash160(&DEX_FEE_ADDR_RAW_PUBKEY).as_slice()), DGB_FEE_HASH160);
        assert_eq!(*DEX_FEE_ADDR_RAW_PUBKEY, *DEX_BURN_ADDR_RAW_PUBKEY);
    }
```
The test's own value is the owner's literal hash160. It is the only place the hash160 appears.

- [ ] **Step 2: Run to verify failure**

Run: `cargo test -p coins --lib dgb_dex_fee_pubkey`
Expected: FAIL with `assertion left == right`: the left side is the hash160 of the upstream key `03a778d9…`.

- [ ] **Step 3: Implement.** In `mm2src/common/common.rs` replace the two constant values (keep the doc comments, and add one line):

```rust
/// Dex fee public key for chains where SECP256K1 is supported
/// DigiByte DEX fee key (owner-controlled; private key held offline).
pub const DEX_FEE_ADDR_PUBKEY: &str = "<FEE_PUBKEY>";
/// Public key to collect the burn part of dex fee, for chains where SECP256K1 is supported
/// Burn currently disabled - using same address as fee address in case there is a bug that enables burn (can be re-enabled later)
pub const DEX_BURN_ADDR_PUBKEY: &str = "<FEE_PUBKEY>";
```
Replace `<FEE_PUBKEY>` with the owner's 66-hex value.

- [ ] **Step 4: Run to verify pass, and that the fee-output tests still pass**

Run: `cargo test -p coins --lib dgb_dex_fee_pubkey && cargo test -p coins --lib taker_fee_tx_outputs && cargo test -p coins --lib dex_fee`
Expected: all pass. The utxo, tendermint and qrc20 tests mock `dex_pubkey` with the `*_LEGACY` fixtures, so they don't depend on the constant.

- [ ] **Step 5: Commit**

```bash
git add mm2src/common/common.rs mm2src/coins/lp_coins.rs
git commit -m "feat(fee): DigiByte DEX fee public key"
```

### Task 4: DEX fee rate with DGB discount

**Files:**
- Modify: `mm2src/coins/lp_coins.rs:4111-4128` (`dex_fee_rate`)
- Modify tests: `mm2src/coins/lp_coins.rs:6594-6611`, `mm2src/mm2_main/src/lp_swap.rs` (`test_dex_fee_burn_split_with_discount_and_standard_coins`, ~l.2387), `mm2src/mm2_main/src/lp_swap/taker_swap.rs` (`test_max_taker_vol_from_available`, ~l.3392-3471)

**Interfaces:**
- Produces: `DexFee::dex_fee_rate(base: &str, rel: &str) -> MmNumber`. It returns `1/100` when either ticker's root (the text before the first `-`) is `DGB`, and `2/100` otherwise. The signature is unchanged, so every caller keeps working.

- [ ] **Step 1: Write the failing tests.** In `lp_coins.rs` `mod tests`, add:

```rust
    #[test]
    fn dgb_pairs_pay_one_percent() {
        assert_eq!(DexFee::dex_fee_rate("DGB", "LTC"), MmNumber::from("0.01"));
        assert_eq!(DexFee::dex_fee_rate("LTC", "DGB"), MmNumber::from("0.01"));
    }

    #[test]
    fn dgb_segwit_gets_discount() {
        assert_eq!(DexFee::dex_fee_rate("DGB-segwit", "LTC"), MmNumber::from("0.01"));
        assert_eq!(DexFee::dex_fee_rate("LTC-segwit", "DGB-segwit"), MmNumber::from("0.01"));
    }

    #[test]
    fn non_dgb_pairs_pay_two_percent() {
        assert_eq!(DexFee::dex_fee_rate("BTC", "LTC"), MmNumber::from("0.02"));
        assert_eq!(DexFee::dex_fee_rate("GLEEC", "BTC"), MmNumber::from("0.02"));
        assert_eq!(DexFee::dex_fee_rate("DGBX", "LTC"), MmNumber::from("0.02"));
    }
```
`DGBX` guards against a prefix match: only the root before `-` counts.

- [ ] **Step 2: Run to verify failure**

Run: `cargo test -p coins --lib dgb_ -- --nocapture` and `cargo test -p coins --lib non_dgb_pairs`
Expected: `dgb_pairs_pay_one_percent` and `dgb_segwit_gets_discount` FAIL (they get 0.02). `non_dgb_pairs_pay_two_percent` FAILs on `GLEEC`.

- [ ] **Step 3: Implement.** Replace the body of `dex_fee_rate` (lp_coins.rs:4111-4128):

```rust
    /// Returns DEX fee rate. Pairs that include DGB (any `DGB` or `DGB-*` ticker) get 1%; others pay 2%.
    pub fn dex_fee_rate(base: &str, rel: &str) -> MmNumber {
        #[cfg(any(feature = "for-tests", test))]
        let fee_discount_tickers: &[&str] = match std::env::var("MYCOIN_FEE_DISCOUNT") {
            Ok(_) => &["DGB", "MYCOIN"],
            Err(_) => &["DGB"],
        };
        #[cfg(not(any(feature = "for-tests", test)))]
        let fee_discount_tickers: &[&str] = &["DGB"];

        let root = |ticker: &str| ticker.split('-').next().unwrap_or(ticker).to_owned();
        if fee_discount_tickers.contains(&root(base).as_str()) || fee_discount_tickers.contains(&root(rel).as_str()) {
            // 1% fee (DigiByte pairs)
            BigRational::new(1.into(), 100.into()).into()
        } else {
            // 2% fee (standard rate)
            BigRational::new(2.into(), 100.into()).into()
        }
    }
```

- [ ] **Step 4: Update the upstream GLEEC-discount tests to DGB.** Three existing tests assert the GLEEC discount.
  - In `lp_coins.rs:6594-6611`, replace `TestCoin::new("GLEEC")` with `TestCoin::new("DGB")`, `let rel = "GLEEC";` with `let rel = "DGB";`, and the comments `GLEEC` with `DGB`.
  - For the other two, run `grep -n 'GLEEC' mm2src/mm2_main/src/lp_swap.rs mm2src/mm2_main/src/lp_swap/taker_swap.rs` and replace each `"GLEEC"` ticker literal inside `test_dex_fee_burn_split_with_discount_and_standard_coins` and `test_max_taker_vol_from_available` with `"DGB"`. Do not touch any `GLEEC` outside those test functions.

- [ ] **Step 5: Run all fee tests**

Run:
```bash
cargo test -p coins --lib dex_fee && cargo test -p coins --lib dgb_ && cargo test -p coins --lib non_dgb_pairs \
 && cargo test -p mm2_main --lib dex_fee && cargo test -p mm2_main --lib max_taker_vol_from_available
```
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add mm2src/coins/lp_coins.rs mm2src/mm2_main/src/lp_swap.rs mm2src/mm2_main/src/lp_swap/taker_swap.rs
git commit -m "feat(fee): 1% DEX fee on DGB pairs, 2% otherwise; match DGB-* tickers"
```

### Task 5: Release workflow and first release

**Files:**
- Create: `.github/workflows/dgb-release.yml`

**Interfaces:**
- Produces: GitHub Release `dgb-v3.0.0-beta.1` on `JohnnyLawDGB/komodo-defi-framework`, tagged at the fork's HEAD commit (`<KDF_SHA>`, 40 hex). Its assets are named exactly as the SDK's matching patterns expect, with 7-char short hash `<KDF_SHORT>`:
  - `kdf_<KDF_SHORT>-android-aarch64.zip` (contains `libkdf.a`)
  - `kdf_<KDF_SHORT>-android-armv7.zip` (contains `libkdf.a`)
  - `kdf_<KDF_SHORT>-ios-aarch64.zip` (contains `libkdf.a`)
  - `kdf_<KDF_SHORT>-linux-x86-64.zip` (contains `kdf`)
  - `SHA256SUMS`

  Task 9 consumes `<KDF_SHA>` and each zip's sha256.

- [ ] **Step 1: Write the workflow.** The commands are copied from upstream `release-build.yml`, the Android container and NDK script are upstream's, and the fee tests gate the build.

```yaml
name: dgb-release
on:
  push:
    tags: ['dgb-v*']
  workflow_dispatch:

permissions:
  contents: write

jobs:
  fee-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: rustup toolchain install stable --profile minimal
      - run: sudo apt-get update && sudo apt-get install -y protobuf-compiler libclang-dev
      - run: |
          cargo test -p coins --lib dex_fee
          cargo test -p coins --lib dgb_
          cargo test -p coins --lib non_dgb_pairs
          cargo test -p mm2_main --lib dex_fee
          cargo test -p mm2_main --lib dgb_netid

  linux-x86-64:
    needs: fee-tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: rustup toolchain install stable --profile minimal
      - run: sudo apt-get update && sudo apt-get install -y protobuf-compiler libclang-dev
      - run: cargo build --release
      - run: |
          TAG=$(git rev-parse --short=7 HEAD)
          zip -j kdf_${TAG}-linux-x86-64.zip target/release/kdf
      - uses: actions/upload-artifact@v4
        with: { name: linux-x86-64, path: 'kdf_*.zip' }

  ios-aarch64:
    needs: fee-tests
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: rustup toolchain install stable --profile minimal && rustup target add aarch64-apple-ios
      - run: brew install protobuf
      - run: cargo rustc --target aarch64-apple-ios --lib --release --package mm2_bin_lib --crate-type=staticlib
      - run: |
          TAG=$(git rev-parse --short=7 HEAD)
          mv target/aarch64-apple-ios/release/libkdflib.a target/aarch64-apple-ios/release/libkdf.a
          zip -j kdf_${TAG}-ios-aarch64.zip target/aarch64-apple-ios/release/libkdf.a
      - uses: actions/upload-artifact@v4
        with: { name: ios-aarch64, path: 'kdf_*.zip' }

  android:
    needs: fee-tests
    runs-on: ubuntu-latest
    container: komodoofficial/ci-container:latest
    strategy:
      matrix:
        include:
          - arch: aarch64
            target: aarch64-linux-android
            cc_var: CC_aarch64_linux_android
            linker_var: CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER
            clang: aarch64-linux-android21-clang
          - arch: armv7
            target: armv7-linux-androideabi
            cc_var: CC_armv7_linux_androideabi
            linker_var: CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER
            clang: armv7a-linux-androideabi21-clang
    steps:
      - uses: actions/checkout@v4
      - run: git config --global --add safe.directory "$GITHUB_WORKSPACE"
      - run: rustup toolchain install stable --profile minimal && rustup target add ${{ matrix.target }}
      - run: ./scripts/ci/android-ndk.sh x86 23
      - run: |
          export PATH=$PATH:/android-ndk/bin
          export ${{ matrix.cc_var }}=${{ matrix.clang }}
          export ${{ matrix.linker_var }}=${{ matrix.clang }}
          cargo rustc --target=${{ matrix.target }} --lib --release --crate-type=staticlib --package mm2_bin_lib
      - run: |
          TAG=$(git rev-parse --short=7 HEAD)
          mv target/${{ matrix.target }}/release/libkdflib.a target/${{ matrix.target }}/release/libkdf.a
          zip -j kdf_${TAG}-android-${{ matrix.arch }}.zip target/${{ matrix.target }}/release/libkdf.a
      - uses: actions/upload-artifact@v4
        with: { name: android-${{ matrix.arch }}, path: 'kdf_*.zip' }

  release:
    needs: [linux-x86-64, ios-aarch64, android]
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/dgb-v')
    steps:
      - uses: actions/download-artifact@v4
        with: { path: dist, merge-multiple: true }
      - run: cd dist && sha256sum kdf_*.zip > SHA256SUMS && cat SHA256SUMS
      - env: { GH_TOKEN: '${{ github.token }}' }
        run: gh release create "$GITHUB_REF_NAME" dist/* -R "$GITHUB_REPOSITORY" --title "$GITHUB_REF_NAME" --notes "DigiByte KDF fork build of $GITHUB_SHA"
```

- [ ] **Step 2: Check the NDK script accepts these arguments, and match build deps**

If `fee-tests` or `linux-x86-64` fail on missing system packages, copy the dependency-install step from upstream `.github/workflows/test.yml` (unit-test job) into both jobs.


Run: `sed -n 1,40p scripts/ci/android-ndk.sh`
Expected: it takes an arch and an API level and installs to `/android-ndk`. If it differs, copy the exact NDK setup lines from `.github/workflows/release-build.yml`'s `android-aarch64` job instead.

- [ ] **Step 3: Commit, push, tag**

```bash
git add .github/workflows/dgb-release.yml
git commit -m "ci: DigiByte release workflow (android, ios, linux) gated on fee tests"
git push -u origin digibyte/main
git tag dgb-v3.0.0-beta.1 && git push origin dgb-v3.0.0-beta.1
```

- [ ] **Step 4: Watch the run and verify the release**

Run: `gh run watch -R JohnnyLawDGB/komodo-defi-framework $(gh run list -R JohnnyLawDGB/komodo-defi-framework -w dgb-release -L1 --json databaseId -q '.[0].databaseId')`
Then: `gh release view dgb-v3.0.0-beta.1 -R JohnnyLawDGB/komodo-defi-framework --json assets -q '.assets[].name'`
Expected: 4 zips plus `SHA256SUMS`, all with the same 7-char hash as `git rev-parse --short=7 HEAD`.

If a job fails, fix it and commit. Move the tag with `git tag -f dgb-v3.0.0-beta.1 && git push -f origin dgb-v3.0.0-beta.1` (safe: only the fork uses it), then delete and re-run the release.

- [ ] **Step 5: Record the pins.** Write `~/.config/dgb-dex/kdf-release.env`:

```bash
KDF_SHA=$(git rev-parse HEAD)
gh release download dgb-v3.0.0-beta.1 -R JohnnyLawDGB/komodo-defi-framework -p SHA256SUMS -O - > /tmp/SHA256SUMS
{ echo "KDF_SHA=$KDF_SHA"; awk '{n=$2; gsub(/^kdf_[0-9a-f]+-|\.zip$/,"",n); gsub(/-/,"_",n); print "SHA_" toupper(n) "=" $1}' /tmp/SHA256SUMS; } > ~/.config/dgb-dex/kdf-release.env
cat ~/.config/dgb-dex/kdf-release.env
```
Expected: `KDF_SHA=…` plus `SHA_ANDROID_AARCH64`, `SHA_ANDROID_ARMV7`, `SHA_IOS_AARCH64` and `SHA_LINUX_X86_64`.

---

## Part C — coins fork (`~/digibyte-dex/coins`, branch `digibyte/main`)

### Task 6: DigiByte seed node and SSL-first DGB electrums

**Files:**
- Modify: `seed-nodes.json` (replace contents)
- Modify: `electrums/DGB` (replace contents)
- Regenerate: `utils/coins_config*.json`, `utils/electrum_scan_report.json`

**Interfaces:**
- Produces:
  - `seed-nodes.json`: exactly one node, netid `2014`.
  - `utils/coins_config_ssl.json` `.DGB.electrum`: at least 3 SSL entries, including `electrum.digiscope.me:50002`.
  - The commit hash `<COINS_SHA>` of this change, which Task 9 consumes.

- [ ] **Step 1: Write `seed-nodes.json`**

```json
[
  {
    "name": "dgb-seed-1",
    "host": "seed1.digiscope.me",
    "type": "domain",
    "wss": false,
    "netid": 2014,
    "contact": [{ "email": "mark@aroundtheblock.us" }]
  }
]
```
`wss` is false because M0 serves plain TCP 15847 only. WSS needs TLS on the seed and is an M2 item.

- [ ] **Step 2: Write `electrums/DGB`**

```json
[
  { "url": "electrum.digiscope.me:50002", "protocol": "SSL", "ws_url": "electrum.digiscope.me:50004", "contact": [{ "email": "mark@aroundtheblock.us" }] },
  { "url": "dgb.electrum1.cipig.net:20059", "protocol": "SSL", "ws_url": "dgb.electrum1.cipig.net:30059", "contact": [{ "email": "cipi@komodoplatform.com" }, { "discord": "cipi#4502" }] },
  { "url": "dgb.electrum2.cipig.net:20059", "protocol": "SSL", "ws_url": "dgb.electrum2.cipig.net:30059", "contact": [{ "email": "cipi@komodoplatform.com" }, { "discord": "cipi#4502" }] },
  { "url": "dgb.electrum3.cipig.net:20059", "protocol": "SSL", "ws_url": "dgb.electrum3.cipig.net:30059", "contact": [{ "email": "cipi@komodoplatform.com" }, { "discord": "cipi#4502" }] }
]
```
electrum3 stays listed. The scan drops it while it's down and restores it automatically when it comes back.

- [ ] **Step 3: Validate the seed file against the upstream schema** (no network needed)

```bash
python3 -m venv .venv && . .venv/bin/activate && pip install -r utils/requirements.txt
python3 - <<'EOF'
import json, jsonschema
schema = json.load(open("utils/seed_nodes_schema.json"))
nodes = json.load(open("seed-nodes.json"))
if schema.get("type") == "array":
    jsonschema.validate(nodes, schema)
else:
    for n in nodes:
        jsonschema.validate(n, schema)
print("seed-nodes OK")
EOF
```
Expected: `seed-nodes OK`.

- [ ] **Step 4: Regenerate the configs with a live electrum scan**

Run: `python3 utils/generate_app_configs.py`
Expected: the run completes, and `utils/coins_config_ssl.json` and the other generated files change.

- [ ] **Step 5: Verify DGB electrums (Review Focus 5)**

```bash
jq -r '.DGB.electrum[] | "\(.protocol) \(.url)"' utils/coins_config_ssl.json
jq -e '[.DGB.electrum[] | select(.protocol=="SSL")] | length >= 3' utils/coins_config_ssl.json
jq -e '[.DGB.electrum[] | select(.url=="electrum.digiscope.me:50002")] | length == 1' utils/coins_config_ssl.json
jq -e '[.LTC.electrum[] | select(.protocol=="SSL")] | length >= 2' utils/coins_config_ssl.json
```
Expected: every `jq -e` exits 0.
- If digiscope is missing, it failed the scan. Probe it with the command in `docs/superpowers/2026-09-29-session-handoff.md` §4, fix it, and re-run Step 4.
- Also record in the commit message whether the generator kept the file's order (digiscope first) or sorted by URL. M1 needs to know.

- [ ] **Step 6: Commit and push**

```bash
deactivate; echo ".venv/" >> .git/info/exclude
git add seed-nodes.json electrums/DGB utils/
git commit -m "feat: DigiByte DEX seed node (netid 2014) and SSL-first DGB electrums"
git push -u origin digibyte/main
echo "COINS_SHA=$(git rev-parse HEAD)" >> ~/.config/dgb-dex/kdf-release.env
```

---

## Part D — SDK fork (`~/digibyte-dex/sdk`, branch `digibyte/main`)

Setup, once: `cd ~/digibyte-dex/sdk && fvm use 3.41.4 --force && fvm flutter pub get`. The SDK's CI uses 3.41.4. Use `fvm flutter` for every command in Part D.

### Task 7: `KdfNetworkConfig` and a netid-aware `SeedNodeUpdater`

**Files:**
- Create: `packages/komodo_defi_types/lib/src/kdf_network_config.dart`
- Modify: `packages/komodo_defi_types/lib/komodo_defi_types.dart:18` (add export)
- Modify: `packages/komodo_coin_updates/lib/src/seed_node_updater.dart:28-79`
- Test: `packages/komodo_coin_updates/test/seed_node_updater_mock_test.dart`

**Interfaces:**
- Produces:
```dart
class KdfNetworkConfig {
  const KdfNetworkConfig({this.netId = kDefaultNetId, this.seedNodes});
  final int netId;               // KDF `netid`
  final List<String>? seedNodes; // explicit seeds; non-empty => no remote fetch
  bool get hasExplicitSeedNodes => seedNodes != null && seedNodes!.isNotEmpty;
}
```
- `SeedNodeUpdater.fetchSeedNodes({required AssetRuntimeUpdateConfig config, int netId = kDefaultNetId, bool filterForWeb = kIsWeb, http.Client? httpClient, Duration timeout})` returns `({List<SeedNode> seedNodes, int netId})`, where `netId` is the argument.

- [ ] **Step 1: Write the failing test.** Add inside the `group` in `seed_node_updater_mock_test.dart`:

```dart
    test('filters and reports the requested netId', () async {
      final mockResponse = MockResponse();
      const responseBody = '''[
        {"name":"dgb-seed-1","host":"seed1.digiscope.me","type":"domain","wss":false,"netid":2014,"contact":[{"email":""}]},
        {"name":"kmd-seed","host":"seed01.kmdefi.net","type":"domain","wss":true,"netid":6133,"contact":[{"email":""}]}
      ]''';
      when(() => mockResponse.statusCode).thenReturn(200);
      when(() => mockResponse.body).thenReturn(responseBody);
      when(() => mockClient.get(any())).thenAnswer((_) async => mockResponse);

      final result = await SeedNodeUpdater.fetchSeedNodes(
        config: config,
        netId: 2014,
        httpClient: mockClient,
      );

      expect(result.netId, 2014);
      expect(result.seedNodes.map((n) => n.host), ['seed1.digiscope.me']);
    });

    test('error names the requested netId when none match', () async {
      final mockResponse = MockResponse();
      when(() => mockResponse.statusCode).thenReturn(200);
      when(() => mockResponse.body).thenReturn(
        '[{"name":"kmd","host":"seed01.kmdefi.net","type":"domain","wss":true,"netid":6133,"contact":[{"email":""}]}]',
      );
      when(() => mockClient.get(any())).thenAnswer((_) async => mockResponse);

      await expectLater(
        () => SeedNodeUpdater.fetchSeedNodes(config: config, netId: 2014, httpClient: mockClient),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('netid 2014'))),
      );
    });
```
And a unit test for the new type in `packages/komodo_defi_types/test/kdf_network_config_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

void main() {
  test('defaults to the upstream netid with no explicit seeds', () {
    const c = KdfNetworkConfig();
    expect(c.netId, kDefaultNetId);
    expect(c.hasExplicitSeedNodes, isFalse);
  });

  test('explicit seeds are detected; empty list is not explicit', () {
    expect(const KdfNetworkConfig(netId: 2014, seedNodes: ['seed1.digiscope.me']).hasExplicitSeedNodes, isTrue);
    expect(const KdfNetworkConfig(netId: 2014, seedNodes: []).hasExplicitSeedNodes, isFalse);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/komodo_coin_updates && fvm flutter test test/seed_node_updater_mock_test.dart; cd ../komodo_defi_types && fvm flutter test test/kdf_network_config_test.dart`
Expected: compile errors: `No named parameter with the name 'netId'` and `KdfNetworkConfig isn't defined`.

- [ ] **Step 3: Implement.** Create `packages/komodo_defi_types/lib/src/kdf_network_config.dart`:

```dart
import 'package:komodo_defi_types/src/constants.dart';

/// Which KDF P2P network to join.
///
/// [netId] is passed to KDF as `netid`. When [seedNodes] is non-empty the SDK
/// uses exactly those seeds and never fetches or falls back to others.
class KdfNetworkConfig {
  const KdfNetworkConfig({this.netId = kDefaultNetId, this.seedNodes});

  final int netId;
  final List<String>? seedNodes;

  bool get hasExplicitSeedNodes => seedNodes != null && seedNodes!.isNotEmpty;
}
```
In `packages/komodo_defi_types/lib/komodo_defi_types.dart`, add after line 18 (`export 'src/constants.dart';`):
```dart
export 'src/kdf_network_config.dart';
```
In `seed_node_updater.dart`:
- Add `int netId = kDefaultNetId,` to the `fetchSeedNodes` parameters, after `required AssetRuntimeUpdateConfig config,`.
- Replace lines 66-79 with:
```dart
      // Filter nodes to the requested netId
      seedNodes = seedNodes.where((e) => e.netId == netId).toList();

      if (filterForWeb && kIsWeb) {
        seedNodes = seedNodes.where((e) => e.wss).toList();
      }

      if (seedNodes.isEmpty) {
        throw _SeedNodeFetchFailure('No seed nodes found for netid $netId');
      }

      return (seedNodes: seedNodes, netId: netId);
```
(The `const` on `_SeedNodeFetchFailure` is dropped because the message is no longer constant.)

- [ ] **Step 4: Run to verify pass, including the existing 6133 tests**

Run: `cd packages/komodo_coin_updates && fvm flutter test && cd ../komodo_defi_types && fvm flutter test`
Expected: all PASS. The existing `No seed nodes found for netid 6133` test still passes through the default.

- [ ] **Step 5: Commit**

```bash
git add packages/komodo_defi_types packages/komodo_coin_updates
git commit -m "feat(types,updates): KdfNetworkConfig; SeedNodeUpdater filters by requested netId"
```

### Task 8: `SeedNodeService` honours the network (no 6133 fallback)

**Files:**
- Modify: `packages/komodo_defi_framework/lib/src/services/seed_node_service.dart:35-101`
- Test: `packages/komodo_defi_framework/test/seed_node_service_test.dart`

**Interfaces:**
- Consumes: `KdfNetworkConfig` (Task 7) and `SeedNodeUpdater.fetchSeedNodes(netId:)` (Task 7).
- Produces:
  - `SeedNodeService.fetchSeedNodes({KdfNetworkConfig network = const KdfNetworkConfig(), bool filterForWeb = kIsWeb})` returns `({List<String> seedNodes, int netId})`, and `netId` always equals `network.netId`.
  - `loadBundledSeedNodes({int netId = kDefaultNetId, bool filterForWeb, AssetBundle? bundle})`.
  - The hard-coded `SeedNodeValidator.getDefaultSeedNodes()` (6133 seeds) is only used when `network.netId == kDefaultNetId`. For any other netid, when every source fails, it throws.

- [ ] **Step 1: Write the failing tests.** Add to `seed_node_service_test.dart` (reusing its `_FakeBundle`):

```dart
  group('SeedNodeService with a custom network', () {
    test('explicit seeds are returned as-is with the configured netId', () async {
      final result = await SeedNodeService.fetchSeedNodes(
        network: const KdfNetworkConfig(netId: 2014, seedNodes: ['seed1.digiscope.me']),
      );
      expect(result.seedNodes, ['seed1.digiscope.me']);
      expect(result.netId, 2014);
    });

    test('bundled seeds are filtered by the requested netId', () async {
      final bundle = _FakeBundle({
        'packages/komodo_defi_framework/assets/config/seed_nodes.json': '''
[
  {"name":"dgb-seed-1","host":"seed1.digiscope.me","type":"domain","wss":false,"netid":2014,"contact":[{"email":""}]},
  {"name":"kmd","host":"seed01.kmdefi.net","type":"domain","wss":true,"netid":6133,"contact":[{"email":""}]}
]
''',
      });
      final seeds = await SeedNodeService.loadBundledSeedNodes(netId: 2014, bundle: bundle);
      expect(seeds, ['seed1.digiscope.me']);
    });

    test('never falls back to 6133 defaults for a custom netId', () async {
      final bundle = _FakeBundle({}); // no bundled asset
      await expectLater(
        SeedNodeService.fetchSeedNodesWith(
          network: const KdfNetworkConfig(netId: 2014),
          remote: (netId) async => throw Exception('offline'),
          bundle: bundle,
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('2014'))),
      );
    });
  });
```
Add `import 'package:komodo_defi_types/komodo_defi_types.dart';` at the top of the test file.

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/komodo_defi_framework && fvm flutter test test/seed_node_service_test.dart`
Expected: compile errors for `network:`, `netId:` and `fetchSeedNodesWith`.

- [ ] **Step 3: Implement.** Replace `fetchSeedNodes` and `loadBundledSeedNodes` (lines 35-101) with:

```dart
  /// Fetches seed nodes for [network].
  ///
  /// Explicit seeds in [network] are returned as-is. Otherwise: remote
  /// `seed-nodes.json` filtered by `network.netId`, then the bundled asset,
  /// then (only for [kDefaultNetId]) the hard-coded defaults.
  static Future<({List<String> seedNodes, int netId})> fetchSeedNodes({
    KdfNetworkConfig network = const KdfNetworkConfig(),
    bool filterForWeb = kIsWeb,
  }) {
    return fetchSeedNodesWith(
      network: network,
      filterForWeb: filterForWeb,
      remote: (netId) async {
        final config = await _getRuntimeConfig();
        final (seedNodes: nodes, netId: _) = await SeedNodeUpdater.fetchSeedNodes(
          config: config,
          netId: netId,
          filterForWeb: filterForWeb,
        );
        return SeedNodeUpdater.seedNodesToStringList(nodes);
      },
    );
  }

  /// Test seam for [fetchSeedNodes]: [remote] replaces the network fetch.
  @visibleForTesting
  static Future<({List<String> seedNodes, int netId})> fetchSeedNodesWith({
    required KdfNetworkConfig network,
    required Future<List<String>> Function(int netId) remote,
    bool filterForWeb = kIsWeb,
    AssetBundle? bundle,
  }) async {
    final netId = network.netId;
    if (network.hasExplicitSeedNodes) {
      return (seedNodes: List<String>.unmodifiable(network.seedNodes!), netId: netId);
    }
    try {
      return (seedNodes: await remote(netId), netId: netId);
    } catch (e) {
      _logger.warning('Remote seed node fetch failed for netid $netId: $e');
    }
    try {
      final bundled = await loadBundledSeedNodes(
        netId: netId,
        filterForWeb: filterForWeb,
        bundle: bundle,
      );
      return (seedNodes: bundled, netId: netId);
    } catch (e) {
      if (netId != kDefaultNetId) {
        throw Exception('No seed nodes available for netid $netId: $e');
      }
      return (seedNodes: SeedNodeValidator.getDefaultSeedNodes(), netId: netId);
    }
  }

  static Future<List<String>> loadBundledSeedNodes({
    int netId = kDefaultNetId,
    bool filterForWeb = kIsWeb,
    AssetBundle? bundle,
  }) async {
    const assetKey = 'packages/$_packageName/$_seedNodesAssetPath';
    final content = await (bundle ?? rootBundle).loadString(assetKey);
    var seedNodes = SeedNode.fromJsonList(
      jsonListFromString(content),
    ).where((node) => node.netId == netId).toList();

    if (filterForWeb && kIsWeb) {
      seedNodes = seedNodes.where((node) => node.wss).toList();
    }

    if (seedNodes.isEmpty) {
      throw Exception('No bundled seed nodes found for netid $netId');
    }

    return SeedNodeUpdater.seedNodesToStringList(seedNodes);
  }
```
Before editing, check the existing catch blocks (lines 52-73) for the logger name they use. Reuse it for `_logger`; if they call `debugPrint`, use `debugPrint` instead. Add `import 'package:flutter/foundation.dart' show visibleForTesting;` if it isn't imported. `getSeedNodes` (lines 113-139) calls `fetchSeedNodes()` with no arguments and keeps working.

- [ ] **Step 4: Run to verify pass**

Run: `fvm flutter test test/seed_node_service_test.dart && fvm flutter test`
Expected: all PASS, including the original `filters bundled seed nodes by the current net id`.

- [ ] **Step 5: Commit**

```bash
git add packages/komodo_defi_framework
git commit -m "feat(framework): SeedNodeService honours KdfNetworkConfig; no 6133 fallback for custom netids"
```

### Task 9: Thread the network from `KomodoDefiSdkConfig` to KDF start, and point builds at the forks

**Files:**
- Modify: `packages/komodo_defi_framework/lib/src/config/kdf_startup_config.dart:76-99, 173-210` (`generateWithDefaults` keeps its `netid` parameter; `noAuthStartup` gains `network`)
- Modify: `packages/komodo_defi_local_auth/lib/src/auth/auth_service.dart:173-185, 1095-1099`
- Modify: `packages/komodo_defi_local_auth/lib/src/auth/auth_service_kdf_extension.dart:481-517`
- Modify: `packages/komodo_defi_local_auth/lib/src/komodo_defi_local_auth.dart:364-371`
- Modify: `packages/komodo_defi_sdk/lib/src/sdk/komodo_defi_sdk_config.dart:15-148`
- Modify: `packages/komodo_defi_sdk/lib/src/bootstrap.dart:162-171`
- Modify: `packages/komodo_defi_framework/app_build/build_config.json`
- Test: `packages/komodo_defi_local_auth/test/src/kdf_network_startup_test.dart` (new)

**Interfaces:**
- Consumes: `KdfNetworkConfig`, `SeedNodeService.fetchSeedNodes(network:)`.
- Produces:
  - `KomodoDefiSdkConfig({..., KdfNetworkConfig network = const KdfNetworkConfig()})`, with a matching field and a `copyWith(network:)` parameter.
  - `KomodoDefiLocalAuth({required kdf, required hostConfig, bool allowRegistrations = true, KdfNetworkConfig network = const KdfNetworkConfig()})`.
  - `KdfAuthService(kdf, hostConfig, {SecureLocalStorage? secureStorage, KdfNetworkConfig network = const KdfNetworkConfig()})`.
  - `KdfStartupConfig.noAuthStartup({..., KdfNetworkConfig network = const KdfNetworkConfig()})`.
  - The KDF start params for both the no-auth and wallet starts carry `netid == network.netId`, and `seednodes == network.seedNodes` when explicit.

- [ ] **Step 1: Write the failing test.** Create `packages/komodo_defi_local_auth/test/src/kdf_network_startup_test.dart`. Copy the `_StartupKdfOperations` class verbatim from `kdf_startup_failure_auth_test.dart` (lines 15 to the end of that class) and the same imports, then add:

```dart
void main() {
  test('no-auth KDF start uses the configured DigiByte network', () async {
    final hostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');
    final operations = _StartupKdfOperations(
      noAuthResult: KdfStartupResult.initError,
      walletResult: KdfStartupResult.ok,
    );
    final service = KdfAuthService(
      KomodoDefiFramework.createWithOperations(
        hostConfig: hostConfig,
        kdfOperations: operations,
      ),
      hostConfig,
      network: const KdfNetworkConfig(netId: 2014, seedNodes: ['seed1.digiscope.me']),
    );
    addTearDown(service.dispose);

    await expectLater(service.getUsers(), throwsA(isA<AuthException>()));

    final params = operations.startParams.single;
    expect(params['netid'], 2014);
    expect(params['seednodes'], ['seed1.digiscope.me']);
  });

  test('default network is unchanged (6133)', () async {
    final hostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');
    final operations = _StartupKdfOperations(
      noAuthResult: KdfStartupResult.initError,
      walletResult: KdfStartupResult.ok,
    );
    final service = KdfAuthService(
      KomodoDefiFramework.createWithOperations(hostConfig: hostConfig, kdfOperations: operations),
      hostConfig,
    );
    addTearDown(service.dispose);

    await expectLater(service.getUsers(), throwsA(isA<AuthException>()));
    expect(operations.startParams.single['netid'], kDefaultNetId);
  });
}
```
The second test may attempt a remote seed fetch in the test environment. The fetch fails and falls back as upstream does, and `netid` is still 6133.

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/komodo_defi_local_auth && fvm flutter test test/src/kdf_network_startup_test.dart`
Expected: compile error `No named parameter with the name 'network'`.

- [ ] **Step 3: Implement the threading.**

**1. `kdf_startup_config.dart` `noAuthStartup`:**
- Add the parameter `KdfNetworkConfig network = const KdfNetworkConfig(),`.
- Replace `await SeedNodeService.fetchSeedNodes();` with `await SeedNodeService.fetchSeedNodes(network: network);`.
- Nothing else changes: `netid: netId` and `seedNodes: seeds` already flow into `encodeStartParams`.

**2. `auth_service.dart`:**
- Change the constructor to:
```dart
  KdfAuthService(
    this._kdfFramework,
    this._hostConfig, {
    SecureLocalStorage? secureStorage,
    KdfNetworkConfig network = const KdfNetworkConfig(),
  }) : _network = network,
```
  keeping the existing initializer list after `_network = network,`.
- Add the field `final KdfNetworkConfig _network;` next to `_hostConfig`.
- Change `_noAuthConfig` (l.1095-1099) to:
```dart
  late final Future<KdfStartupConfig> _noAuthConfig =
      KdfStartupConfig.noAuthStartup(
        rpcPassword: _hostConfig.rpcPassword,
        rpcPort: _hostConfig.port,
        network: _network,
      );
```

**3. `auth_service_kdf_extension.dart` `_generateStartupConfig`:** replace
```dart
    final (seedNodes: seedNodes, netId: netId) =
        await SeedNodeService.fetchSeedNodes();
```
with
```dart
    final (seedNodes: seedNodes, netId: netId) =
        await SeedNodeService.fetchSeedNodes(network: _network);
```

**4. `komodo_defi_local_auth.dart` constructor (l.364-371):**
```dart
  KomodoDefiLocalAuth({
    required KomodoDefiFramework kdf,
    required IKdfHostConfig hostConfig,
    bool allowRegistrations = true,
    KdfNetworkConfig network = const KdfNetworkConfig(),
  }) : _allowRegistrations = allowRegistrations,
       _authService = KdfAuthService(kdf, hostConfig, network: network) {
```

**5. `komodo_defi_sdk_config.dart`:**
- Add the constructor parameter `this.network = const KdfNetworkConfig(),`.
- Add the field:
```dart
  /// KDF P2P network (netid and optional explicit seed nodes).
  final KdfNetworkConfig network;
```
- Add a `KdfNetworkConfig? network,` parameter to `copyWith`, and pass `network: network ?? this.network,` in its body.

**6. `bootstrap.dart` (l.164-168):**
```dart
    final auth = KomodoDefiLocalAuth(
      kdf: framework,
      hostConfig:
          hostConfig ?? LocalConfig(https: false, rpcPassword: rpcPassword),
      network: config.network,
    );
```

Add `import 'package:komodo_defi_types/komodo_defi_types.dart';` where a file lacks it.

- [ ] **Step 4: Run to verify pass, then the full test suites of the touched packages**

Run:
```bash
cd ~/digibyte-dex/sdk
for p in komodo_defi_types komodo_coin_updates komodo_defi_framework komodo_defi_local_auth komodo_defi_sdk; do (cd packages/$p && fvm flutter test) || echo "FAIL $p"; done
fvm dart analyze packages/komodo_defi_types packages/komodo_coin_updates packages/komodo_defi_framework packages/komodo_defi_local_auth packages/komodo_defi_sdk
```
Expected: no `FAIL` lines and no analyzer errors.

- [ ] **Step 5: Commit the threading**

```bash
git add packages
git commit -m "feat(sdk): inject KDF netid and seed nodes via KomodoDefiSdkConfig.network"
```

- [ ] **Step 6: Point `build_config.json` at the forks.** Use the values from `~/.config/dgb-dex/kdf-release.env`. Edit `packages/komodo_defi_framework/app_build/build_config.json`:
  - **`api`:**
    - `"api_commit_hash": "<KDF_SHA>"`
    - `"branch": "digibyte/main"`
    - `"source_urls": ["https://api.github.com/repos/JohnnyLawDGB/komodo-defi-framework"]`
    - `"required_platforms": ["ios", "android-armv7", "android-aarch64", "linux"]`
  - **`api.platforms`:**
    - Delete `web`, `macos` and `windows`.
    - Set `valid_zip_sha256_checksums` to `["<SHA_ANDROID_ARMV7>"]` for `android-armv7`, `["<SHA_ANDROID_AARCH64>"]` for `android-aarch64`, `["<SHA_IOS_AARCH64>"]` for `ios`, and `["<SHA_LINUX_X86_64>"]` for `linux`.
  - **`coins`:**
    - `"bundled_coins_repo_commit": "<COINS_SHA>"`
    - `"coins_repo_api_url": "https://api.github.com/repos/JohnnyLawDGB/coins"`
    - `"coins_repo_content_url": "https://raw.githubusercontent.com/JohnnyLawDGB/coins"`
    - `"coins_repo_branch": "digibyte/main"`
    - `"update_commit_on_build": false` (pins the coins commit)
    - `"cdn_branch_mirrors": {}` (otherwise the GLEEC CDN wins)
  - **`coins.mapped_files`:** `"assets/config/coins_config.json": "utils/coins_config_ssl.json"` (SSL-only, spec §7.2).
  - If `ios`'s `matching_pattern` doesn't match `kdf_<hash>-ios-aarch64.zip`, add that alternative to the regex.

Validate:
```bash
jq -e '.api.source_urls == ["https://api.github.com/repos/JohnnyLawDGB/komodo-defi-framework"] and .coins.cdn_branch_mirrors == {} and (.api.platforms | keys | sort) == ["android-aarch64","android-armv7","ios","linux"]' packages/komodo_defi_framework/app_build/build_config.json
cd packages/komodo_wallet_build_transformer && fvm flutter test
```
Expected: `true`, and the transformer tests pass. A test that asserts the upstream `source_urls` policy may fail. If it does, update its expected value to the fork URL; if it is a pure upstream policy check, mark it `skip: 'DigiByte fork sources'`. Say which in the commit message.

- [ ] **Step 7: Commit and push**

```bash
git add packages/komodo_defi_framework/app_build/build_config.json packages/komodo_wallet_build_transformer
git commit -m "build: fetch KDF from DigiByte fork release and coins from DigiByte coins fork"
git push -u origin digibyte/main
echo "SDK_SHA=$(git rev-parse HEAD)" >> ~/.config/dgb-dex/kdf-release.env
```

---

## Part E — Network operations (`~/digibyte-dex/digibyte-wallet/ops/`)

### Task 10: Price feed for the market-maker bot

KDF's bot defaults to GLEEC-hosted price URLs. This feed serves the same `TickerInfos` shape from CoinGecko, on localhost next to the bot.

**Files:**
- Create: `ops/price_feed/price_feed.py`
- Create: `ops/price_feed/test_price_feed.py`
- Create: `ops/price_feed/dgb-price-feed.service` (systemd user unit)

**Interfaces:**
- Produces: `GET http://127.0.0.1:8765/api/v2/tickers` returns `{"DGB": TickerInfos, "LTC": TickerInfos}`. TickerInfos has the fields KDF's `lp_price.rs:62-78` requires: `ticker, last_price, last_updated, last_updated_timestamp, volume24h, price_provider, volume_provider, sparkline_7d, sparkline_provider, change_24h, change_24h_provider`.
- `build_tickers(cg: dict, now: int) -> dict` is a pure function.

- [ ] **Step 1: Write the failing test**

```python
# ops/price_feed/test_price_feed.py
from price_feed import build_tickers

CG = {
    "digibyte": {"usd": 0.0123, "usd_24h_vol": 4567890.1, "usd_24h_change": -1.5, "last_updated_at": 1790000000},
    "litecoin": {"usd": 101.25, "usd_24h_vol": 3.2e8, "usd_24h_change": 0.8, "last_updated_at": 1790000030},
}

def test_shape_matches_kdf_ticker_infos():
    t = build_tickers(CG, now=1790000100)
    assert set(t) == {"DGB", "LTC"}
    required = {"ticker", "last_price", "last_updated", "last_updated_timestamp", "volume24h",
                "price_provider", "volume_provider", "sparkline_7d", "sparkline_provider",
                "change_24h", "change_24h_provider"}
    for info in t.values():
        assert required <= set(info)
        assert info["price_provider"] == "coingecko"

def test_prices_are_decimal_strings_not_floats():
    t = build_tickers(CG, now=1790000100)
    assert t["DGB"]["last_price"] == "0.0123"
    assert t["LTC"]["last_price"] == "101.25"

def test_timestamp_is_coingecko_update_time():
    t = build_tickers(CG, now=1790000100)
    assert t["DGB"]["last_updated_timestamp"] == 1790000000

def test_missing_coin_is_omitted_not_zero_priced():
    t = build_tickers({"digibyte": CG["digibyte"]}, now=1790000100)
    assert set(t) == {"DGB"}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ~/digibyte-dex/digibyte-wallet/ops/price_feed && python3 -m pytest -q`
Expected: `ModuleNotFoundError: No module named 'price_feed'`.

- [ ] **Step 3: Implement (stdlib only)**

```python
# ops/price_feed/price_feed.py
"""Serves CoinGecko prices in KDF's TickerInfos format for the market-maker bot."""
import json
import threading
import time
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

COINS = {"digibyte": "DGB", "litecoin": "LTC"}
CG_URL = ("https://api.coingecko.com/api/v3/simple/price?ids=" + ",".join(COINS)
          + "&vs_currencies=usd&include_24hr_vol=true&include_24hr_change=true&include_last_updated_at=true")
REFRESH_SECONDS = 60


def _dec(x) -> str:
    return format(float(x), "f").rstrip("0").rstrip(".") if "e" in repr(x) else repr(x)


def build_tickers(cg: dict, now: int) -> dict:
    out = {}
    for cg_id, ticker in COINS.items():
        row = cg.get(cg_id)
        if not row or "usd" not in row:
            continue
        ts = int(row.get("last_updated_at", now))
        out[ticker] = {
            "ticker": ticker,
            "last_price": _dec(row["usd"]),
            "last_updated": datetime.fromtimestamp(ts, timezone.utc).isoformat(),
            "last_updated_timestamp": ts,
            "volume24h": _dec(row.get("usd_24h_vol", 0)),
            "price_provider": "coingecko",
            "volume_provider": "coingecko",
            "sparkline_7d": None,
            "sparkline_provider": "unknown",
            "change_24h": _dec(row.get("usd_24h_change", 0)),
            "change_24h_provider": "coingecko",
        }
    return out


_cache = {"body": b"{}"}


def _refresh_forever():
    while True:
        try:
            with urllib.request.urlopen(CG_URL, timeout=15) as r:
                _cache["body"] = json.dumps(build_tickers(json.load(r), int(time.time()))).encode()
        except Exception as e:  # keep serving the last good prices
            print(f"refresh failed: {e}", flush=True)
        time.sleep(REFRESH_SECONDS)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/api/v2/tickers":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(_cache["body"])

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    threading.Thread(target=_refresh_forever, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
```
`_dec` uses `repr` so `0.0123` stays `"0.0123"`. Values in scientific notation are expanded.

- [ ] **Step 4: Run to verify pass**

Run: `python3 -m pytest -q`
Expected: `4 passed`.

- [ ] **Step 5: systemd user unit, then run it**

```ini
# ops/price_feed/dgb-price-feed.service
[Unit]
Description=DGB DEX price feed (CoinGecko -> KDF TickerInfos)

[Service]
ExecStart=/usr/bin/python3 %h/digibyte-dex/digibyte-wallet/ops/price_feed/price_feed.py
Restart=always

[Install]
WantedBy=default.target
```
```bash
mkdir -p ~/.config/systemd/user && cp dgb-price-feed.service ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now dgb-price-feed
sleep 5; curl -s http://127.0.0.1:8765/api/v2/tickers | jq '.DGB.last_price, .LTC.last_price'
```
Expected: two non-null price strings.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet
git add ops/price_feed && git commit -m "ops: CoinGecko price feed in KDF TickerInfos format"
```

### Task 11: Seed node on `seed1.digiscope.me`

**Files:**
- Create: `ops/seed/kdf-seed.service`
- Create: `ops/seed/MM2.json.example` (no secrets)
- Create: `ops/seed/install.sh`
- On the VPS only: `/etc/kdf-seed/MM2.json` (mode 600) and `/var/lib/kdf-seed/`

**Interfaces:**
- Consumes: the linux zip from Task 5 and `coins` from the coins fork at `<COINS_SHA>`.
- Produces: a KDF seed and bootstrap node on netid 2014 that accepts TCP on `seed1.digiscope.me:15847`.

The VPS also runs the public ElectrumX with its firewall caps and watchdog (spec §7.2 notes). **Get the owner's go-ahead before touching the VPS.** Add rules only: do not edit or reload the existing ElectrumX, ufw connlimit or watchdog config.

- [ ] **Step 1: Write the example config and unit**

`ops/seed/MM2.json.example`:
```json
{
  "gui": "dgb-seed",
  "mm2": 1,
  "netid": 2014,
  "i_am_seed": true,
  "is_bootstrap_node": true,
  "seednodes": [],
  "myipaddr": "134.199.198.90",
  "rpcip": "127.0.0.1",
  "rpcport": 7783,
  "rpc_password": "GENERATED_AT_INSTALL",
  "passphrase": "GENERATED_AT_INSTALL",
  "dbdir": "/var/lib/kdf-seed/db"
}
```
`ops/seed/kdf-seed.service`:
```ini
[Unit]
Description=KDF seed node (DigiByte DEX, netid 2014)
After=network-online.target
Wants=network-online.target

[Service]
User=kdf
WorkingDirectory=/var/lib/kdf-seed
Environment=MM_CONF_PATH=/etc/kdf-seed/MM2.json
Environment=MM_COINS_PATH=/var/lib/kdf-seed/coins
Environment=MM_LOG=/var/lib/kdf-seed/kdf.log
ExecStart=/usr/local/bin/kdf
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/lib/kdf-seed
MemoryMax=1G

[Install]
WantedBy=multi-user.target
```
`ops/seed/install.sh`:
```bash
#!/usr/bin/env bash
# Run on the VPS as root: install.sh <KDF_SHORT> <COINS_SHA>
set -euo pipefail
KDF_SHORT=$1; COINS_SHA=$2
id kdf >/dev/null 2>&1 || useradd --system --home /var/lib/kdf-seed --shell /usr/sbin/nologin kdf
install -d -o kdf -g kdf -m 700 /var/lib/kdf-seed /var/lib/kdf-seed/db
install -d -m 700 /etc/kdf-seed
cd /tmp
curl -fsSLO "https://github.com/JohnnyLawDGB/komodo-defi-framework/releases/download/dgb-v3.0.0-beta.1/kdf_${KDF_SHORT}-linux-x86-64.zip"
curl -fsSLO "https://github.com/JohnnyLawDGB/komodo-defi-framework/releases/download/dgb-v3.0.0-beta.1/SHA256SUMS"
grep "kdf_${KDF_SHORT}-linux-x86-64.zip" SHA256SUMS | sha256sum -c -
unzip -o "kdf_${KDF_SHORT}-linux-x86-64.zip" kdf -d /usr/local/bin && chmod 755 /usr/local/bin/kdf
curl -fsSL "https://raw.githubusercontent.com/JohnnyLawDGB/coins/${COINS_SHA}/coins" -o /var/lib/kdf-seed/coins
chown kdf:kdf /var/lib/kdf-seed/coins
if [ ! -f /etc/kdf-seed/MM2.json ]; then
  RPC=$(openssl rand -hex 16); PASS=$(openssl rand -hex 32)
  sed -e "s/\"rpc_password\": \"GENERATED_AT_INSTALL\"/\"rpc_password\": \"$RPC\"/" \
      -e "s/\"passphrase\": \"GENERATED_AT_INSTALL\"/\"passphrase\": \"$PASS\"/" \
      "$(dirname "$0")/MM2.json.example" > /etc/kdf-seed/MM2.json
  chmod 600 /etc/kdf-seed/MM2.json; chown kdf:kdf /etc/kdf-seed/MM2.json
fi
install -m 644 "$(dirname "$0")/kdf-seed.service" /etc/systemd/system/kdf-seed.service
systemctl daemon-reload && systemctl enable --now kdf-seed
```
The seed's passphrase fixes its P2P identity, so back up `/etc/kdf-seed/MM2.json`. The seed holds no funds.

- [ ] **Step 2: Commit the ops files**

```bash
chmod +x ops/seed/install.sh
git add ops/seed && git commit -m "ops: KDF seed node unit, config template and installer"
git push -u origin HEAD
```

- [ ] **Step 3: Owner prerequisites.** Confirm with the owner that both are done:
  - DNS A record `seed1.digiscope.me` → `134.199.198.90`. Check with `getent hosts seed1.digiscope.me`.
  - A firewall rule allowing inbound TCP 15847, for example `ufw allow 15847/tcp comment 'kdf seed netid 2014'`. It must not change the ElectrumX connlimit rules.

- [ ] **Step 4: Install on the VPS** (with the owner's go-ahead)

```bash
source ~/.config/dgb-dex/kdf-release.env
scp -r ops/seed root@134.199.198.90:/root/kdf-seed-install
ssh root@134.199.198.90 "bash /root/kdf-seed-install/install.sh ${KDF_SHA:0:7} $COINS_SHA"
```

- [ ] **Step 5: Verify**

```bash
ssh root@134.199.198.90 'systemctl is-active kdf-seed; ss -ltnp | grep -E ":(15847|7783)\b"; tail -n 20 /var/lib/kdf-seed/kdf.log'
nc -vz -w 5 seed1.digiscope.me 15847
ssh root@134.199.198.90 'systemctl is-active electrumx 2>/dev/null || true'
```
Expected:
- `active`, with `kdf` listening on `0.0.0.0:15847` and `127.0.0.1:7783`.
- The log shows no `panic`.
- `nc` succeeds from the workstation.
- ElectrumX is still active.

### Task 12: Market-maker bot (workstation)

**Files:**
- Create: `ops/bot/MM2.json.example`
- Create: `ops/bot/kdf-bot.service` (systemd user unit)
- Create: `ops/bot/start_bot.sh`
- Local only: `~/.config/dgb-dex/bot/MM2.json` (mode 600)

**Interfaces:**
- Consumes: the seed (Task 11), the price feed (Task 10), and the linux KDF from Task 5.
- Produces:
  - Maker orders on netid 2014: `DGB/LTC` (bot sells DGB) and `LTC/DGB` (bot sells LTC).
  - A captured legacy `orderbook` response, `~/digibyte-dex/digibyte-wallet/m0_probe/test/fixtures/orderbook_dgb_ltc.json`, which Task 13 consumes.

- [ ] **Step 1: Write the files**

`ops/bot/MM2.json.example`:
```json
{
  "gui": "dgb-mm-bot",
  "mm2": 1,
  "netid": 2014,
  "seednodes": ["seed1.digiscope.me"],
  "rpcip": "127.0.0.1",
  "rpcport": 7790,
  "rpc_password": "GENERATED",
  "passphrase": "GENERATED",
  "dbdir": "/home/polloloco/.local/share/dgb-bot/db"
}
```
`ops/bot/kdf-bot.service`:
```ini
[Unit]
Description=KDF market-maker bot (DigiByte DEX, netid 2014)
After=dgb-price-feed.service

[Service]
WorkingDirectory=%h/.local/share/dgb-bot
Environment=MM_CONF_PATH=%h/.config/dgb-dex/bot/MM2.json
Environment=MM_COINS_PATH=%h/.local/share/dgb-bot/coins
Environment=MM_LOG=%h/.local/share/dgb-bot/kdf.log
ExecStart=%h/.local/bin/kdf
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```
Port 7790 avoids clashing with any local KDF on 7783.

`ops/bot/start_bot.sh`:
```bash
#!/usr/bin/env bash
# Activates DGB and LTC over SSL electrums and starts the simple market maker.
set -euo pipefail
CONF=~/.config/dgb-dex/bot/MM2.json
PW=$(jq -r .rpc_password "$CONF"); URL=http://127.0.0.1:7790
rpc() { curl -fsS "$URL" -d "$1"; echo; }

rpc "{\"userpass\":\"$PW\",\"method\":\"electrum\",\"coin\":\"DGB\",\"servers\":[
  {\"url\":\"electrum.digiscope.me:50002\",\"protocol\":\"SSL\"},
  {\"url\":\"dgb.electrum1.cipig.net:20059\",\"protocol\":\"SSL\"},
  {\"url\":\"dgb.electrum2.cipig.net:20059\",\"protocol\":\"SSL\"}]}"
rpc "{\"userpass\":\"$PW\",\"method\":\"electrum\",\"coin\":\"LTC\",\"servers\":[
  {\"url\":\"ltc.electrum1.cipig.net:20063\",\"protocol\":\"SSL\"},
  {\"url\":\"ltc.electrum2.cipig.net:20063\",\"protocol\":\"SSL\"}]}"

rpc "{\"userpass\":\"$PW\",\"mmrpc\":\"2.0\",\"method\":\"start_simple_market_maker_bot\",\"params\":{
  \"price_url\":\"http://127.0.0.1:8765/api/v2/tickers\",
  \"bot_refresh_rate\":60,
  \"cfg\":{
    \"DGB/LTC\":{\"base\":\"DGB\",\"rel\":\"LTC\",\"enable\":true,\"spread\":\"1.02\",
      \"max_volume\":{\"usd\":\"20\"},\"min_volume\":{\"usd\":\"1\"},
      \"base_confs\":7,\"base_nota\":false,\"rel_confs\":2,\"rel_nota\":false,\"price_elapsed_validity\":600},
    \"LTC/DGB\":{\"base\":\"LTC\",\"rel\":\"DGB\",\"enable\":true,\"spread\":\"1.02\",
      \"max_volume\":{\"usd\":\"20\"},\"min_volume\":{\"usd\":\"1\"},
      \"base_confs\":2,\"base_nota\":false,\"rel_confs\":7,\"rel_nota\":false,\"price_elapsed_validity\":600}}}}"
```
`price_elapsed_validity` is 600 s because the feed passes CoinGecko's update time, which can lag a few minutes.

- [ ] **Step 2: Install and start KDF for the bot**

```bash
source ~/.config/dgb-dex/kdf-release.env
mkdir -p ~/.local/bin ~/.local/share/dgb-bot/db ~/.config/dgb-dex/bot && cd /tmp
gh release download dgb-v3.0.0-beta.1 -R JohnnyLawDGB/komodo-defi-framework -p "kdf_*-linux-x86-64.zip" -p SHA256SUMS --clobber
grep linux-x86-64 SHA256SUMS | sha256sum -c - && unzip -o kdf_*-linux-x86-64.zip kdf -d ~/.local/bin
curl -fsSL "https://raw.githubusercontent.com/JohnnyLawDGB/coins/${COINS_SHA}/coins" -o ~/.local/share/dgb-bot/coins
~/digibyte-dex/digibyte-wallet/ops/bot/init_config.sh   # creates MM2.json (600) with a KDF-policy-compliant rpc_password; no-op if it exists
cp ~/digibyte-dex/digibyte-wallet/ops/bot/kdf-bot.service ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now kdf-bot
sleep 10; tail -n 30 ~/.local/share/dgb-bot/kdf.log
```
Expected: the log shows the bot connected to the seed, with no `panic`. **Back up `~/.config/dgb-dex/bot/MM2.json` offline now: its passphrase controls the bot's funds.**

- [ ] **Step 3: Get the bot's addresses and fund it (owner)**

```bash
chmod +x ~/digibyte-dex/digibyte-wallet/ops/bot/start_bot.sh
PW=$(jq -r .rpc_password ~/.config/dgb-dex/bot/MM2.json)
~/digibyte-dex/digibyte-wallet/ops/bot/start_bot.sh 2>&1 | head -c 2000   # activates coins; bot start may fail on zero balance, that's fine
for c in DGB LTC; do curl -s http://127.0.0.1:7790 -d "{\"userpass\":\"$PW\",\"method\":\"my_balance\",\"coin\":\"$c\"}" | jq '{coin,address,balance}'; done
```
The owner sends at most 2,000 DGB and at most 0.5 LTC to those addresses. Wait for confirmations: DGB 7, LTC 2.

- [ ] **Step 4: Start the bot and verify orders**

```bash
curl -s http://127.0.0.1:7790 -d "{\"userpass\":\"$PW\",\"mmrpc\":\"2.0\",\"method\":\"stop_simple_market_maker_bot\",\"params\":{}}"
sleep 5; ~/digibyte-dex/digibyte-wallet/ops/bot/start_bot.sh | tail -n 1
sleep 90
curl -s http://127.0.0.1:7790 -d "{\"userpass\":\"$PW\",\"method\":\"my_orders\"}" | jq '.result.maker_orders | length'
```
Expected: `2`.

- [ ] **Step 5: Verify the orders propagate through the seed.** Query the **seed's** orderbook view so the check doesn't just echo the bot's own orders:

```bash
SPW=$(ssh root@134.199.198.90 "jq -r .rpc_password /etc/kdf-seed/MM2.json")
ssh root@134.199.198.90 "curl -s http://127.0.0.1:7783 -d '{\"userpass\":\"$SPW\",\"method\":\"orderbook\",\"base\":\"DGB\",\"rel\":\"LTC\"}'" | tee /tmp/orderbook_dgb_ltc.json | jq '{netid, numasks, numbids, ask: .asks[0] | {price, uuid, maxvolume, min_volume}}'
```
Expected: `netid: 2014`, `numasks ≥ 1`, `numbids ≥ 1`. The seed only sees orders for coins in its coins file, which is all of them.

If the seed returns `Coin DGB is not activated`, activate DGB and LTC on the seed with the two `electrum` calls from `start_bot.sh`, pointed at port 7783 with the seed's password, and re-run.

- [ ] **Step 6: Save the fixture and commit**

```bash
mkdir -p ~/digibyte-dex/digibyte-wallet/m0_probe/test/fixtures
jq . /tmp/orderbook_dgb_ltc.json > ~/digibyte-dex/digibyte-wallet/m0_probe/test/fixtures/orderbook_dgb_ltc.json
cd ~/digibyte-dex/digibyte-wallet
git add ops/bot m0_probe/test/fixtures && git commit -m "ops: market-maker bot (DGB/LTC) and captured orderbook fixture"
```

---

## Part F — M0 probe app (`~/digibyte-dex/digibyte-wallet/m0_probe/`)

### Task 13: Swap request builder and status parser (pure Dart)

**Files:**
- Create: `m0_probe/pubspec.yaml`
- Create: `m0_probe/lib/swap_probe.dart`
- Test: `m0_probe/test/swap_probe_test.dart`
- Create: `.fvmrc` (repo root) and `.gitmodules`
- Add: submodule `third_party/komodo-defi-sdk-flutter` at `<SDK_SHA>`

**Interfaces:**
- Produces, in `lib/swap_probe.dart`:
```dart
enum TakerSide { buy, sell }
class OrderQuote { const OrderQuote({required this.uuid, required this.price, required this.maxVolume, required this.minVolume}); final String uuid; final Decimal price; final Decimal maxVolume; final Decimal minVolume; }
OrderQuote? bestAsk(Map<String, dynamic> orderbook);   // lowest-price ask, excluding is_mine
OrderQuote? bestBid(Map<String, dynamic> orderbook);   // highest-price bid, excluding is_mine
Map<String, dynamic> buildTakerRequest({required TakerSide side, required String base, required String rel, required OrderQuote quote, required Decimal volume, Decimal? slippage});
enum SwapPhase { running, finished, failed }
({SwapPhase phase, List<String> steps, String? takerFeeTxHash}) parseSwapStatus(Map<String, dynamic> mySwapStatusResult);
```

- [ ] **Step 1: Scaffold the app and add the SDK submodule**

```bash
cd ~/digibyte-dex/digibyte-wallet
echo '{"flutter": "3.41.4"}' > .fvmrc
source ~/.config/dgb-dex/kdf-release.env
git submodule add -b digibyte/main git@github.com:JohnnyLawDGB/komodo-defi-sdk-flutter.git third_party/komodo-defi-sdk-flutter
git -C third_party/komodo-defi-sdk-flutter checkout "$SDK_SHA"
fvm install && fvm flutter create --org me.digiscope.wallet --project-name m0_probe --platforms android,ios m0_probe
```
Replace the dependencies in `m0_probe/pubspec.yaml` with:
```yaml
environment:
  sdk: '>=3.9.0 <4.0.0'
  flutter: '>=3.35.0'

dependencies:
  flutter:
    sdk: flutter
  decimal: ^3.2.1
  komodo_defi_sdk:
    path: ../third_party/komodo-defi-sdk-flutter/packages/komodo_defi_sdk
  komodo_defi_types:
    path: ../third_party/komodo-defi-sdk-flutter/packages/komodo_defi_types

dev_dependencies:
  flutter_test:
    sdk: flutter
```
If `fvm flutter pub get` reports a workspace-resolution conflict with the SDK's path packages, add `dependency_overrides` pointing every `komodo_*` package the resolver names at `../third_party/komodo-defi-sdk-flutter/packages/<name>`. Record the final list in the commit message.

- [ ] **Step 2: Write the failing tests**

```dart
// m0_probe/test/swap_probe_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m0_probe/swap_probe.dart';

Decimal d(String s) => Decimal.parse(s);

Map<String, dynamic> book({List<Map<String, dynamic>> asks = const [], List<Map<String, dynamic>> bids = const []}) =>
    {'base': 'DGB', 'rel': 'LTC', 'netid': 2014, 'asks': asks, 'bids': bids};

Map<String, dynamic> entry(String uuid, String price, {bool mine = false}) =>
    {'uuid': uuid, 'price': price, 'maxvolume': '500', 'min_volume': '10', 'is_mine': mine};

OrderQuote q({String price = '0.0001', String max = '500', String min = '10'}) =>
    OrderQuote(uuid: 'u-1', price: d(price), maxVolume: d(max), minVolume: d(min));

void main() {
  group('bestAsk / bestBid', () {
    test('picks lowest ask and highest bid, ignoring my own orders', () {
      final b = book(
        asks: [entry('a1', '0.00012'), entry('a2', '0.00011'), entry('mine', '0.00001', mine: true)],
        bids: [entry('b1', '0.00009'), entry('b2', '0.000095')],
      );
      expect(bestAsk(b)!.uuid, 'a2');
      expect(bestBid(b)!.uuid, 'b2');
    });

    test('empty book gives null', () {
      expect(bestAsk(book()), isNull);
      expect(bestBid(book()), isNull);
    });

    test('parses the real orderbook captured from the seed', () {
      final real = jsonDecode(File('test/fixtures/orderbook_dgb_ltc.json').readAsStringSync()) as Map<String, dynamic>;
      final ask = bestAsk(real);
      expect(ask, isNotNull);
      expect(ask!.price > Decimal.zero, isTrue);
      expect(ask.maxVolume >= ask.minVolume, isTrue);
    });
  });

  group('buildTakerRequest', () {
    test('taker request is fill-or-kill and pinned to the quoted order', () {
      final r = buildTakerRequest(side: TakerSide.buy, base: 'DGB', rel: 'LTC', quote: q(), volume: d('100'));
      expect(r['method'], 'buy');
      expect(r['order_type'], {'type': 'FillOrKill'});
      expect(r['match_by'], {'type': 'Orders', 'data': ['u-1']});
      expect(r['base'], 'DGB');
      expect(r['rel'], 'LTC');
      expect(r['volume'], '100');
    });

    test('buy price limit is quote x 1.01 by default, exact decimal', () {
      final r = buildTakerRequest(side: TakerSide.buy, base: 'DGB', rel: 'LTC', quote: q(price: '0.0001'), volume: d('100'));
      expect(r['price'], '0.000101');
    });

    test('sell price limit is quote x 0.99 by default', () {
      final r = buildTakerRequest(side: TakerSide.sell, base: 'DGB', rel: 'LTC', quote: q(price: '0.0001'), volume: d('100'));
      expect(r['method'], 'sell');
      expect(r['price'], '0.000099');
    });

    test('volume outside the order limits is rejected', () {
      expect(() => buildTakerRequest(side: TakerSide.buy, base: 'DGB', rel: 'LTC', quote: q(), volume: d('5')), throwsArgumentError);
      expect(() => buildTakerRequest(side: TakerSide.buy, base: 'DGB', rel: 'LTC', quote: q(), volume: d('501')), throwsArgumentError);
    });
  });

  group('parseSwapStatus', () {
    Map<String, dynamic> status(List<String> types, {String? feeHash}) => {
          'uuid': 'u-1',
          'success_events': ['Started', 'Negotiated', 'TakerFeeSent', 'MakerPaymentReceived', 'TakerPaymentSent', 'TakerPaymentSpent', 'MakerPaymentSpent', 'Finished'],
          'error_events': ['StartFailed', 'NegotiateFailed', 'TakerFeeSendFailed', 'MakerPaymentValidateFailed', 'TakerPaymentTransactionFailed', 'MakerPaymentSpendFailed', 'TakerPaymentRefunded'],
          'events': [
            for (final t in types)
              {'timestamp': 1, 'event': {'type': t, if (t == 'TakerFeeSent' && feeHash != null) 'data': {'tx_hash': feeHash, 'tx_hex': '00'}}},
          ],
        };

    test('running swap lists steps so far and exposes the fee tx', () {
      final s = parseSwapStatus(status(['Started', 'Negotiated', 'TakerFeeSent'], feeHash: 'abc'));
      expect(s.phase, SwapPhase.running);
      expect(s.steps, ['Started', 'Negotiated', 'TakerFeeSent']);
      expect(s.takerFeeTxHash, 'abc');
    });

    test('Finished after only success events is finished', () {
      expect(parseSwapStatus(status(['Started', 'Negotiated', 'TakerFeeSent', 'MakerPaymentReceived', 'TakerPaymentSent', 'MakerPaymentSpent', 'Finished'])).phase, SwapPhase.finished);
    });

    test('any error event makes the swap failed, even if Finished follows', () {
      expect(parseSwapStatus(status(['Started', 'NegotiateFailed', 'Finished'])).phase, SwapPhase.failed);
    });
  });
}
```
- [ ] **Step 3: Run to verify failure**

Run: `cd m0_probe && fvm flutter test test/swap_probe_test.dart`
Expected: compile error `Target of URI doesn't exist: 'package:m0_probe/swap_probe.dart'`.

- [ ] **Step 4: Implement `lib/swap_probe.dart`**

```dart
import 'package:decimal/decimal.dart';

enum TakerSide { buy, sell }

class OrderQuote {
  const OrderQuote({
    required this.uuid,
    required this.price,
    required this.maxVolume,
    required this.minVolume,
  });

  final String uuid;
  final Decimal price;
  final Decimal maxVolume;
  final Decimal minVolume;
}

OrderQuote _quote(Map<String, dynamic> e) => OrderQuote(
      uuid: e['uuid'] as String,
      price: Decimal.parse(e['price'].toString()),
      maxVolume: Decimal.parse(e['maxvolume'].toString()),
      minVolume: Decimal.parse((e['min_volume'] ?? '0').toString()),
    );

List<OrderQuote> _side(Map<String, dynamic> book, String key) => [
      for (final e in (book[key] as List? ?? const []).cast<Map<String, dynamic>>())
        if (e['is_mine'] != true) _quote(e),
    ];

/// Lowest-priced ask from a legacy `orderbook` response, excluding my orders.
OrderQuote? bestAsk(Map<String, dynamic> orderbook) {
  final asks = _side(orderbook, 'asks');
  if (asks.isEmpty) return null;
  return asks.reduce((a, b) => b.price < a.price ? b : a);
}

/// Highest-priced bid from a legacy `orderbook` response, excluding my orders.
OrderQuote? bestBid(Map<String, dynamic> orderbook) {
  final bids = _side(orderbook, 'bids');
  if (bids.isEmpty) return null;
  return bids.reduce((a, b) => b.price > a.price ? b : a);
}

/// Legacy `buy`/`sell` request that can only fill [quote] and never rests as a maker order.
Map<String, dynamic> buildTakerRequest({
  required TakerSide side,
  required String base,
  required String rel,
  required OrderQuote quote,
  required Decimal volume,
  Decimal? slippage,
}) {
  final slip = slippage ?? Decimal.parse('0.01');
  if (volume < quote.minVolume || volume > quote.maxVolume) {
    throw ArgumentError.value(
      volume,
      'volume',
      'must be within ${quote.minVolume}..${quote.maxVolume}',
    );
  }
  final limit = side == TakerSide.buy
      ? quote.price * (Decimal.one + slip)
      : quote.price * (Decimal.one - slip);
  return {
    'method': side == TakerSide.buy ? 'buy' : 'sell',
    'base': base,
    'rel': rel,
    'price': limit.toString(),
    'volume': volume.toString(),
    'order_type': {'type': 'FillOrKill'},
    'match_by': {'type': 'Orders', 'data': [quote.uuid]},
  };
}

enum SwapPhase { running, finished, failed }

/// Reads a legacy `my_swap_status` `result` object.
({SwapPhase phase, List<String> steps, String? takerFeeTxHash}) parseSwapStatus(
  Map<String, dynamic> result,
) {
  final errors = (result['error_events'] as List? ?? const []).cast<String>().toSet();
  final events = (result['events'] as List? ?? const []).cast<Map<String, dynamic>>();
  final steps = <String>[];
  String? feeHash;
  for (final e in events) {
    final event = e['event'] as Map<String, dynamic>;
    final type = event['type'] as String;
    steps.add(type);
    if (type == 'TakerFeeSent') {
      feeHash = (event['data'] as Map<String, dynamic>?)?['tx_hash'] as String?;
    }
  }
  final phase = steps.any(errors.contains)
      ? SwapPhase.failed
      : steps.contains('Finished')
          ? SwapPhase.finished
          : SwapPhase.running;
  return (phase: phase, steps: steps, takerFeeTxHash: feeHash);
}
```

- [ ] **Step 5: Run to verify pass**

Run: `fvm flutter test test/swap_probe_test.dart`
Expected: all PASS.

The `real orderbook` test fails if the captured fixture uses different field names. Inspect them with `jq '.asks[0] | keys' test/fixtures/orderbook_dgb_ltc.json`, change only `_quote`'s keys to match, and re-run.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet
git add .fvmrc .gitmodules third_party m0_probe
git commit -m "feat(m0): probe app scaffold; fill-or-kill taker request builder and swap status parser"
```

### Task 14: Probe screen wired to the SDK on netid 2014

**Files:**
- Create: `m0_probe/lib/brand.dart`
- Modify: `m0_probe/lib/main.dart` (replace)
- Modify: `m0_probe/android/app/build.gradle` or `build.gradle.kts` (`applicationId`, `minSdk`)

**Interfaces:**
- Consumes:
  - `KomodoDefiSdk({KomodoDefiSdkConfig? config})` with `KomodoDefiSdkConfig(network:, defaultAssets:)` (Task 9).
  - `sdk.auth.getUsers()`, `sdk.auth.register(walletName:, password:)`, `sdk.auth.signIn(walletName:, password:)` and `sdk.auth.getMnemonicPlainText(password)`.
  - `sdk.assets.findAssetsByConfigId(ticker)`, `sdk.assets.activateAsset(asset).last` and `sdk.pubkeys.getPubkeys(asset)`.
  - `sdk.client.executeRpc(Map)`, and Task 13's functions.
- Produces: an installable debug APK, `me.digiscope.wallet.m0`.

- [ ] **Step 1: `lib/brand.dart`**

```dart
/// M0 brand/network constants (spec §4.2: one place for identity).
abstract final class Brand {
  static const appName = 'DigiByte DEX M0';
  static const netId = 2014;
  static const seedNodes = ['seed1.digiscope.me'];
  static const base = 'DGB';
  static const rel = 'LTC';
}
```

- [ ] **Step 2: `lib/main.dart`**

```dart
import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:m0_probe/brand.dart';
import 'package:m0_probe/swap_probe.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sdk = KomodoDefiSdk(
    config: const KomodoDefiSdkConfig(
      defaultAssets: {Brand.base, Brand.rel},
      network: KdfNetworkConfig(netId: Brand.netId, seedNodes: Brand.seedNodes),
    ),
  );
  await sdk.initialize();
  runApp(MaterialApp(title: Brand.appName, home: ProbePage(sdk: sdk)));
}

class ProbePage extends StatefulWidget {
  const ProbePage({required this.sdk, super.key});
  final KomodoDefiSdk sdk;
  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  final _password = TextEditingController();
  final _volume = TextEditingController(text: '200');
  final _log = <String>[];
  String? _swapUuid;
  Timer? _poll;

  KomodoDefiSdk get sdk => widget.sdk;
  void _say(String s) => setState(() => _log.insert(0, s));

  Future<void> _unlock() async {
    const name = 'm0';
    final users = await sdk.auth.getUsers();
    if (users.any((u) => u.walletId.name == name)) {
      await sdk.auth.signIn(walletName: name, password: _password.text);
    } else {
      await sdk.auth.register(walletName: name, password: _password.text);
      _say('New wallet created. Tap "Show seed" and write it down before funding.');
    }
    for (final t in [Brand.base, Brand.rel]) {
      final asset = sdk.assets.findAssetsByConfigId(t).first;
      await sdk.assets.activateAsset(asset).last;
      final keys = await sdk.pubkeys.getPubkeys(asset);
      _say('$t ${keys.keys.first.address}  balance ${keys.balance}');
    }
  }

  Future<void> _showSeed() async {
    final m = await sdk.auth.getMnemonicPlainText(_password.text);
    _say('SEED (write down, then clear screen): ${m.plaintextMnemonic}');
  }

  Future<Map<String, dynamic>> _book() async => Map<String, dynamic>.from(
        await sdk.client.executeRpc({'method': 'orderbook', 'base': Brand.base, 'rel': Brand.rel}),
      );

  Future<void> _trade(TakerSide side) async {
    final book = await _book();
    _say('orderbook netid=${book['netid']} asks=${book['numasks']} bids=${book['numbids']}');
    final quote = side == TakerSide.buy ? bestAsk(book) : bestBid(book);
    if (quote == null) return _say('No ${side == TakerSide.buy ? 'ask' : 'bid'} to take.');
    final req = buildTakerRequest(
      side: side, base: Brand.base, rel: Brand.rel, quote: quote, volume: Decimal.parse(_volume.text),
    );
    final res = await sdk.client.executeRpc(req);
    final uuid = (res['result'] as Map?)?['uuid'] as String?;
    if (uuid == null) return _say('Order rejected: $res');
    _swapUuid = uuid;
    _say('Swap started $uuid at limit ${req['price']}');
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final uuid = _swapUuid;
    if (uuid == null) return;
    final res = await sdk.client.executeRpc({'method': 'my_swap_status', 'params': {'uuid': uuid}});
    final result = res['result'] as Map<String, dynamic>?;
    if (result == null) return;
    final s = parseSwapStatus(result);
    _say('${s.phase.name}: ${s.steps.last}${s.takerFeeTxHash == null ? '' : '  fee tx ${s.takerFeeTxHash}'}');
    if (s.phase != SwapPhase.running) _poll?.cancel();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text(Brand.appName)),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Wallet password')),
            TextField(controller: _volume, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'DGB volume')),
            Wrap(spacing: 8, children: [
              ElevatedButton(onPressed: _unlock, child: const Text('Unlock + activate')),
              ElevatedButton(onPressed: _showSeed, child: const Text('Show seed')),
              ElevatedButton(onPressed: () => _trade(TakerSide.buy), child: const Text('Buy DGB with LTC')),
              ElevatedButton(onPressed: () => _trade(TakerSide.sell), child: const Text('Sell DGB for LTC')),
              ElevatedButton(onPressed: _refresh, child: const Text('Refresh swap')),
            ]),
            const Divider(),
            Expanded(child: ListView(children: [for (final l in _log) SelectableText(l)])),
          ]),
        ),
      );
}
```
The keep-app-open banner and swap recovery are M2 (spec §6.1). The probe only needs to drive one swap while in the foreground.

- [ ] **Step 3: Android app ID and minSdk.** In `m0_probe/android/app/build.gradle(.kts)`, set `applicationId = "me.digiscope.wallet.m0"` and `minSdk = 28`, matching the SDK example.

- [ ] **Step 4: Static checks**

Run: `cd m0_probe && fvm flutter analyze && fvm flutter test`
Expected: no errors, and Task 13's tests still pass.
- If an SDK member name differs from the Interfaces list (for example `KdfUser.walletId.name` or `AssetPubkeys.balance`), follow the analyzer to the real member in `third_party/komodo-defi-sdk-flutter` and fix it here only.
- Do not change the SDK for the probe.

- [ ] **Step 5: Debug build**

Run: `fvm flutter build apk --debug`
Expected:
- The build transformer downloads `kdf_<KDF_SHORT>-android-*.zip` from `JohnnyLawDGB/komodo-defi-framework` and logs a matching SHA-256.
- The build ends with `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.
- If the transformer asks to re-run because it fetched assets, run the same command again (upstream behaviour).
- Run `grep -r "gleecbtc.github.io\|devbuilds.gleec.com" build/ | head`. Expected: no output, so nothing was fetched from GLEEC.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet
git add m0_probe && git commit -m "feat(m0): probe screen on netid 2014 (unlock, activate, take DGB/LTC order, track swap)"
git push
```

### Task 15: The M0 exit swap on a physical phone

**Files:**
- Create: `docs/m0-report.md` (in `digibyte-wallet`)

**Interfaces:**
- Consumes: everything above.
- Produces: the M0 exit evidence (spec §10): two completed mainnet swaps and fee outputs to the DigiByte fee address on both chains.

- [ ] **Step 1: Pre-flight**

```bash
nc -vz -w 5 seed1.digiscope.me 15847
curl -s http://127.0.0.1:8765/api/v2/tickers | jq -r '.DGB.last_price, .LTC.last_price'
PW=$(jq -r .rpc_password ~/.config/dgb-dex/bot/MM2.json); curl -s http://127.0.0.1:7790 -d "{\"userpass\":\"$PW\",\"method\":\"my_orders\"}" | jq '.result.maker_orders | length'
```
Expected: the port is open, there are two prices, and the bot has `2` orders.

- [ ] **Step 2: Install and fund the phone**
  1. `fvm flutter install -d ZY22HVMNKZ` from `m0_probe/` (the Moto G 5G; never the Note 8 `ce061716640b191c017e`).
  2. Enter a password, tap **Unlock + activate**, then **Show seed**. The owner writes the seed down, because this wallet holds real funds.
  3. The owner sends at most 1,000 DGB and at most 0.1 LTC to the two addresses shown. Wait for confirmations, then tap **Unlock + activate** again and check the balances.

- [ ] **Step 3: Swap 1: buy DGB with LTC.** The taker pays the DEX fee in LTC.
  - Set the volume to about US$3 of DGB, within the ask's `min_volume..maxvolume` (the log shows the limits if rejected).
  - Tap **Buy DGB with LTC** and keep the app in the foreground.
  - Expected: the log steps through `Started → Negotiated → TakerFeeSent … → Finished` with phase `finished`, in about 15–25 min given DGB 7 and LTC 2 confirmations. It shows the fee tx hash.

- [ ] **Step 4: Swap 2: sell DGB for LTC.** The taker pays the DEX fee in DGB. Same procedure with **Sell DGB for LTC**. Expected: phase `finished` and a fee tx hash.

- [ ] **Step 5: Verify the fee outputs on chain.** For each fee tx hash, check that one output's scriptPubKey is `76a914<FEE_HASH160>88ac` and that its value is about 1% of the taker amount (or the coin's dust minimum, if larger):

```bash
source ~/.config/dgb-dex/m0-inputs.env
# DGB fee tx (swap 2), via the local node:
digibyte-cli getrawtransaction <DGB_FEE_TX> true | jq --arg s "76a914${FEE_HASH160}88ac" '.vout[] | select(.scriptPubKey.hex==$s) | .value'
# LTC fee tx (swap 1), via the public explorer API:
curl -s https://litecoinspace.org/api/tx/<LTC_FEE_TX> | jq --arg s "76a914${FEE_HASH160}88ac" '.vout[] | select(.scriptpubkey==$s) | .value'
```
Expected: each command prints one value: DGB in coins, LTC in litoshis.

- [ ] **Step 6 (optional, needs a Mac and an Apple developer account):** run `fvm flutter run -d <iphone>` from `m0_probe/` and repeat Step 2 to prove the iOS lib loads. Skip it if no Mac is available, and note that in the report.

- [ ] **Step 7: Write `docs/m0-report.md` and commit.** The report records:
  - The fork commits (`KDF_SHA`, `SDK_SHA`, `COINS_SHA`) and the release tag.
  - Both swap uuids, and every tx hash from `my_swap_status` (taker fee, maker payment, taker payment, both spends).
  - The fee values from Step 5.
  - Durations.
  - Anything that needed a workaround, for example transformer re-runs, analyzer-driven renames, or whether the coins generator kept the electrum order.

```bash
git add docs/m0-report.md && git commit -m "docs: M0 exit report — mainnet DGB/LTC swaps on netid 2014" && git push
```

- [ ] **Step 8: Update the spec repo.** In `Digi-Dex-Komodo` on branch `docs/digibyte-wallet-design`:
  - Update spec §3 with the new upstream hashes (KDF `d56a7bc`, SDK `a96398b`, coins `2490e55`) and the facts found here: `DEFAULT_NETID` only switches behaviour; the bot's default price URLs are GLEEC-hosted; the SDK's CDN mirror overrides `coins_repo_content_url`.
  - Mark M0 done in the handoff doc, with a link to `digibyte-wallet/docs/m0-report.md`.
  - Commit.

- [ ] **Step 9: Spend-down.** The bot and phone keep their small balances for M2 testing. The owner decides whether to sweep them now. The fee-address funds stay with the owner's offline key.
