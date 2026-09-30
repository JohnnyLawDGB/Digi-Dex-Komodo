# M1-A: KDF Release 2 — P2P Redial Fix, Fee-Key Rotation, Pinned CI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship KDF fork release `dgb-v3.0.0-beta.2`, roll it out to the seed, the bot and the probe phone, and prove it with one mainnet swap. The release does four things:
- the app reconnects to the seed immediately after a sign-in restart;
- DEX fees go to a new offline-held key;
- makers are proven to reject wrong fees;
- the release is built by a fully pinned pipeline.

**Architecture:** Changes stay inside the thin KDF fork (`mm2_p2p` dial throttle, `common` fee constants, `coins` tests, the release workflow).
- The SDK fork only re-pins `build_config.json` to the new release.
- The seed, the bot and the M0 probe app are upgraded **together**. Fee enforcement is symmetric, so any old-key node would reject a new-key taker's fee (and vice versa).

**Tech Stack:** Rust 1.94.0 (pinned), GitHub Actions, Flutter 3.41.4 (probe rebuild), systemd.

**Spec:** `docs/superpowers/specs/2026-09-27-digibyte-wallet-design.md`:
- §6.2 fee enforcement
- §7.3 build pipeline
- §8.3 supply chain
- §10a M1 decisions

It also carries over from `digibyte-wallet/docs/m0-report.md` ("Findings" 2, "Final review").

## Global Constraints

- **Base:**
  - KDF fork `JohnnyLawDGB/komodo-defi-framework`, branch `digibyte/main`, at `dgb-v3.0.0-beta.1` = `4715f29ee5cd78fd6ff9e023df65479f02f9f7ba`.
  - Upstream has no new commits or tags since `d56a7bc` (checked 2026-09-30), so no rebase is needed.
- **Protected branch:** `digibyte/main` rejects force-pushes and deletion on all three forks. Every change is a normal commit.
- **Toolchain:** Rust `1.94.0` via `rust-toolchain.toml`. For every local KDF build, export:
  - `PROTOC=/tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/01d56841-7970-4b28-ba34-65645351704c/scratchpad/protoc/bin/protoc`
  - `PROTOC_INCLUDE=…/protoc/include`
- **Cargo test invocations:**
  - `coins`: `cargo test -p coins --lib <filter>`
  - `mm2_p2p` / `mm2_main`: `cargo test -p mm2_p2p -p mm2_main -p chain --lib <filter>`. A single-package `-p mm2_p2p` fails on chrono feature unification.
- **Network ID** stays `2014`. **DEX fee rates** stay at 1% on `DGB`/`DGB-*` pairs and 2% otherwise.
- **New fee key:**
  - The owner generates it offline (Task 1). Only the compressed pubkey and its hash160 enter the repo.
  - The M0 key `036f27a4…a52a` / hash160 `5e6bb724…873c` is retired: no new release may carry it.
- **Test phone:** the Moto G 5G `ZY22HVMNKZ` only.
  - Never touch the Galaxy Note 8 `ce061716640b191c017e`.
  - Never restart adb.
  - No scripted Buy/Sell taps without the owner's "go" for that swap.
- **Commit messages:** subject line, blank line, then:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb
  ```
- **Secrets** stay in `~/.config/dgb-dex/` (mode 600) and are never committed. Update `~/.config/dgb-dex/SECRETS-INDEX.md` whenever a key changes.

## Review Focus

1. **A sign-in restart must not delay reconnecting to the seed.** When the SDK stops the no-auth KDF and starts wallet mode in the same process, the wallet instance must dial `seed1` right away, not after 5 minutes.
   - Unit test: Task 2 `dial_guard_resets_on_restart`.
   - Device check: Task 9 Step 4 (the orderbook reachable within 60 s of unlock after a force-stop and relaunch, with no workaround).
2. **A fee paid to the old or any wrong address is rejected by the maker.** Otherwise a stale client could "pay" the DEX fee to an address DigiByte no longer controls. → Task 4 `dgb_validate_fee_rejects_wrong_receiver`.
3. **An underpaid fee is rejected.** → Task 4 `dgb_validate_fee_rejects_underpaid`.
4. **Mixed versions during rollout.** An old-key app trading against a new-key bot fails at fee validation, and the taker's fee is lost to the old address. No swaps may run while the bot and the phone are on different releases. → Task 8 stops the bot before any upgrade and restarts it only after the phone runs the new build. Task 9 Step 3 asserts that both run `3.0.0-beta_<new short sha>` before trading.
5. **Pipeline drift.** A release must be reproducible from pinned inputs. → Task 6 Step 4 asserts that there are no floating `@vN` action refs, no `:latest` container, and `--locked` on every cargo build.

## Not in M1-A

- GPG signing: M1-B CI.
- `PRICE_ENDPOINTS`: M2.
- The ZHTLC and Sia fee destinations. These are documented in the fork's `DIGIBYTE.md` in Task 5; they are replaced only before any such pair is listed.

---

### Task 1: New offline fee key (owner)

**Files:**
- Create: `~/.config/dgb-dex/m1a-inputs.env` (mode 600)

**Interfaces:**
- Produces: `NEW_FEE_PUBKEY`, `NEW_FEE_HASH160`, `NEW_FEE_DGB_ADDRESS`, `NEW_FEE_LTC_ADDRESS`

- [ ] **Step 1: The owner generates the key on an air-gapped DigiByte Core.** Create a new wallet used only for DEX fees, run `getnewaddress "" legacy`, then `getaddressinfo <address>`. Copy `pubkey` and `scriptPubKey` to the dev machine; the private key stays offline.

- [ ] **Step 2: Validate the key and write the inputs file**

```bash
python3 ~/digibyte-dex/digibyte-wallet/ops/tools/check_fee_key.py "<pubkey>" "<scriptPubKey>" | tee /tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/01d56841-7970-4b28-ba34-65645351704c/scratchpad/newkey.txt
umask 077
{ grep -E '^FEE_(PUBKEY|HASH160|DGB_ADDRESS)=' /tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/01d56841-7970-4b28-ba34-65645351704c/scratchpad/newkey.txt | sed 's/^FEE_/NEW_FEE_/'
  echo "NEW_FEE_LTC_ADDRESS=$(awk '/^LTC address:/{print $3}' /tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/01d56841-7970-4b28-ba34-65645351704c/scratchpad/newkey.txt)"; } > ~/.config/dgb-dex/m1a-inputs.env
cat ~/.config/dgb-dex/m1a-inputs.env
```
Expected:
- the checker exits 0;
- the file has four lines;
- `NEW_FEE_PUBKEY` differs from `036f27a4e83ddf1239d545887d7dadd5aad8ab0a45518ff2c9fd2721e2d40da52a`.

- [ ] **Step 3: Update `~/.config/dgb-dex/SECRETS-INDEX.md`.** Add the new fee-key line: offline, public values only. Mark the `dgb-dex-fees` node wallet as "retired after `dgb-v3.0.0-beta.2`".

---

### Task 2: Reset the dial throttle on every P2P start

**Files:**
- Modify: `mm2src/mm2_p2p/src/behaviours/atomicdex.rs`:
  - add `pub fn reset_recently_dialed_peers()` after `check_and_mark_dialed` (~l.212);
  - call it in `start_gossipsub` just before the initial dial loop (~l.806);
  - add a `#[cfg(test)] mod tests` at the end of the file.

**Interfaces:**
- Produces: `pub fn reset_recently_dialed_peers()`. It replaces the global `TimedMap` wholesale. `TimedMap::clear()` is not enough: it leaves the internal `expiries` index behind, and stale buckets can evict fresh entries.

- [ ] **Step 1: Write the failing test.** Append to `atomicdex.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dial_guard_resets_on_restart() {
        // Unique non-memory address: RECENTLY_DIALED_PEERS is process-global and shared with the in-memory swarm tests.
        let addr: Multiaddr = "/ip4/192.0.2.77/tcp/7777".parse().unwrap();
        {
            let mut guard = RECENTLY_DIALED_PEERS.lock().unwrap();
            assert!(check_and_mark_dialed(&mut guard, &addr));
            assert!(!check_and_mark_dialed(&mut guard, &addr), "second dial within DIAL_RETRY_DELAY must be suppressed");
        }
        reset_recently_dialed_peers();
        let mut guard = RECENTLY_DIALED_PEERS.lock().unwrap();
        assert!(check_and_mark_dialed(&mut guard, &addr), "a fresh P2P start must be allowed to dial again");
    }
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cargo test -p mm2_p2p -p mm2_main -p chain --lib dial_guard`
Expected: a compile error, `cannot find function reset_recently_dialed_peers`.

- [ ] **Step 3: Implement.** After `check_and_mark_dialed`, add:

```rust
/// Forgets every recorded dial attempt.
///
/// `RECENTLY_DIALED_PEERS` is process-global, but its entries belong to one swarm. When a host
/// stops KDF and starts it again in the same process (the Flutter SDK does this on sign-in), the new
/// swarm must be able to dial its seed nodes immediately instead of waiting `DIAL_RETRY_DELAY`.
pub fn reset_recently_dialed_peers() {
    *RECENTLY_DIALED_PEERS.lock().unwrap() = TimedMap::new_with_map_kind(MapKind::FxHashMap);
}
```
In `start_gossipsub`, immediately before `let mut recently_dialed_peers = RECENTLY_DIALED_PEERS.lock().unwrap();` (just above the `for relay in bootstrap.choose_multiple(...)` loop), add:
```rust
    // A new swarm starts with a clean dial history (see `reset_recently_dialed_peers`).
    reset_recently_dialed_peers();
```

- [ ] **Step 4: Run it and confirm it passes, and that the swarm tests still pass**

Run: `cargo test -p mm2_p2p -p mm2_main -p chain --lib dial_guard && cargo test -p mm2_p2p -p mm2_main -p chain --lib behaviours::tests`
Expected: `dial_guard_resets_on_restart ... ok`, and every `behaviours::tests::*` passes.

- [ ] **Step 5: Commit**

```bash
git add mm2src/mm2_p2p/src/behaviours/atomicdex.rs
git commit -m "fix(p2p): reset dial throttle when a new swarm starts (in-process restart redials seeds)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 3: Only mark bootstrap addresses that are actually dialed

**Files:**
- Modify: `mm2src/mm2_p2p/src/behaviours/atomicdex.rs`:
  - `maintain_connection_to_relays`, the bootstrap block at ~l.944-960;
  - add a pure helper, plus tests in the `mod tests` from Task 2.

**Interfaces:**
- Consumes: `check_and_mark_dialed`, `RECENTLY_DIALED_PEERS` (Task 2 test module).
- Produces: `fn pick_bootstrap_to_dial(candidates: &[Multiaddr], n: usize, is_connected: impl Fn(&Multiaddr) -> bool, guard: &mut MutexGuard<TimedMap<Multiaddr, ()>>, rng: &mut impl rand::Rng) -> Vec<Multiaddr>`

**The bug:** the current `.filter(|addr| !connected && check_and_mark_dialed(..))` runs **before** `.choose_multiple(n)`. So every unconnected bootstrap address is marked as dialed, but only `n` of them are dialed, and the rest are blocked for 5 minutes without any attempt.

- [ ] **Step 1: Write the failing test.** Add to `mod tests`:

```rust
    #[test]
    fn dgb_pick_bootstrap_marks_only_chosen() {
        let a: Multiaddr = "/ip4/192.0.2.81/tcp/1".parse().unwrap();
        let b: Multiaddr = "/ip4/192.0.2.82/tcp/1".parse().unwrap();
        let c: Multiaddr = "/ip4/192.0.2.83/tcp/1".parse().unwrap();
        let candidates = vec![a.clone(), b.clone(), c.clone()];
        let mut rng = rand::thread_rng();

        let mut guard = RECENTLY_DIALED_PEERS.lock().unwrap();
        let chosen = pick_bootstrap_to_dial(&candidates, 1, |_| false, &mut guard, &mut rng);
        assert_eq!(chosen.len(), 1);
        // The two addresses that were not chosen must still be dialable.
        let not_chosen: Vec<_> = candidates.iter().filter(|x| !chosen.contains(x)).cloned().collect();
        for addr in &not_chosen {
            assert!(guard.get(addr).is_none(), "unchosen {addr} must not be marked as dialed");
        }
        // The chosen address is marked.
        assert!(guard.get(&chosen[0]).is_some());
    }

    #[test]
    fn dgb_pick_bootstrap_skips_connected_and_recent() {
        let a: Multiaddr = "/ip4/192.0.2.91/tcp/1".parse().unwrap();
        let b: Multiaddr = "/ip4/192.0.2.92/tcp/1".parse().unwrap();
        let mut rng = rand::thread_rng();
        let mut guard = RECENTLY_DIALED_PEERS.lock().unwrap();
        assert!(check_and_mark_dialed(&mut guard, &b)); // b dialed recently
        let chosen = pick_bootstrap_to_dial(&[a.clone(), b.clone()], 2, |x| x == &a, &mut guard, &mut rng);
        assert!(chosen.is_empty(), "a is connected and b was dialed recently: nothing to dial");
    }
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cargo test -p mm2_p2p -p mm2_main -p chain --lib dgb_pick_bootstrap`
Expected: a compile error, `cannot find function pick_bootstrap_to_dial`.

- [ ] **Step 3: Implement.** Add the helper next to `check_and_mark_dialed`:

```rust
/// Chooses up to `n` bootstrap addresses to dial and marks only those as dialed.
///
/// Candidates that are connected or were dialed within `DIAL_RETRY_DELAY` are skipped.
fn pick_bootstrap_to_dial(
    candidates: &[Multiaddr],
    n: usize,
    is_connected: impl Fn(&Multiaddr) -> bool,
    guard: &mut MutexGuard<TimedMap<Multiaddr, ()>>,
    rng: &mut impl rand::Rng,
) -> Vec<Multiaddr> {
    let eligible: Vec<&Multiaddr> = candidates
        .iter()
        .filter(|addr| !is_connected(addr) && guard.get(*addr).is_none())
        .collect();
    let chosen: Vec<Multiaddr> = eligible.choose_multiple(rng, n).map(|a| (*a).clone()).collect();
    for addr in &chosen {
        check_and_mark_dialed(guard, addr);
    }
    chosen
}
```
In `maintain_connection_to_relays`, replace the bootstrap block, which starts `let connect_bootstrap_num = to_connect_num - to_connect.len();` and ends after the `for addr in ... { if let Err(e) = libp2p::Swarm::dial(...) ... }` loop, with:
```rust
            let connect_bootstrap_num = to_connect_num - to_connect.len();
            let chosen = {
                let gossipsub = &swarm.behaviour().core.gossipsub;
                pick_bootstrap_to_dial(
                    bootstrap_addresses,
                    connect_bootstrap_num,
                    |addr| gossipsub.is_connected_to_addr(addr),
                    &mut recently_dialed_peers,
                    &mut rng,
                )
            };
            for addr in chosen {
                if let Err(e) = libp2p::Swarm::dial(swarm, addr.clone()) {
                    error!("Bootstrap addr {} dial error {}", addr, e);
                }
            }
```
Keep everything else in the function unchanged. If the borrow checker rejects borrowing `swarm.behaviour()` inside the closure while `recently_dialed_peers` is held, first collect `let connected: Vec<bool> = bootstrap_addresses.iter().map(|a| swarm.behaviour().core.gossipsub.is_connected_to_addr(a)).collect();` and pass `|addr| bootstrap_addresses.iter().position(|b| b == addr).map_or(false, |i| connected[i])`.

- [ ] **Step 4: Run it and confirm it passes, including the existing swarm tests**

Run: `cargo test -p mm2_p2p -p mm2_main -p chain --lib dgb_pick_bootstrap && cargo test -p mm2_p2p -p mm2_main -p chain --lib behaviours::tests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add mm2src/mm2_p2p/src/behaviours/atomicdex.rs
git commit -m "fix(p2p): mark only bootstrap addresses that are actually dialed" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 4: Prove the maker rejects wrong-receiver and underpaid fees

**Files:**
- Modify: `mm2src/coins/utxo/utxo_tests.rs`. Add two tests after `test_validate_fee_wrong_sender` (~l.2893).

**Interfaces:**
- Consumes: the existing MARTY fixture tx used by `test_validate_old_fee_tx` (~l.2845). Its first output pays 0.0001 MARTY to the **upstream legacy** fee address, sender pubkey `03242d9c…953c`.
- Also consumes: `DEX_FEE_ADDR_RAW_PUBKEY_LEGACY`, `INVALID_RECEIVER_ERR_LOG`, and `mocktopus` `mock_safe`, as the neighbouring tests use them.

These tests use a live MARTY electrum (`MARTY_ELECTRUM_ADDRS`, cipig), exactly like the neighbouring upstream tests. The `dgb_` prefix puts them in the release gate.

- [ ] **Step 1: Write the tests**

```rust
// DigiByte fork: a fee paid to any address other than the fork's fee key must be rejected by the maker.
#[test]
fn dgb_validate_fee_rejects_wrong_receiver() {
    let rpc_client = electrum_client_for_test(MARTY_ELECTRUM_ADDRS, ChainVariant::MORTY);
    let coin = utxo_coin_for_test(UtxoRpcClientEnum::Electrum(rpc_client), None, false);
    // Same fixture as test_validate_old_fee_tx: pays 0.0001 to the upstream legacy fee address.
    let tx_bytes = hex::decode("0400008085202f8901033aedb3c3c02fc76c15b393c7b1f638cfa6b4a1d502e00d57ad5b5305f12221000000006a473044022074879aabf38ef943eba7e4ce54c444d2d6aa93ac3e60ea1d7d288d7f17231c5002205e1671a62d8c031ac15e0e8456357e54865b7acbf49c7ebcba78058fd886b4bd012103242d9cb2168968d785f6914c494c303ff1c27ba0ad882dbc3c15cfa773ea953cffffffff0210270000000000001976a914ca1e04745e8ca0c60d8c5881531d51bec470743f88ac4802d913000000001976a914902053231ef0541a7628c11acac40d30f2a127bd88ac008e3765000000000000000000000000000000").unwrap();
    let taker_fee_tx = coin.tx_enum_from_bytes(&tx_bytes).unwrap();
    let amount: MmNumber = "0.0001".parse::<BigDecimal>().unwrap().into();
    // No dex_pubkey mock: the maker validates against the DigiByte fork's own fee key.
    let validate_fee_args = ValidateFeeArgs {
        fee_tx: &taker_fee_tx,
        expected_sender: &hex::decode("03242d9cb2168968d785f6914c494c303ff1c27ba0ad882dbc3c15cfa773ea953c").unwrap(),
        dex_fee: &DexFee::Standard(amount),
        min_block_number: 0,
        uuid: &[],
    };
    let error = block_on(coin.validate_fee(validate_fee_args)).unwrap_err().into_inner();
    match error {
        ValidatePaymentError::WrongPaymentTx(err) => assert!(err.contains(INVALID_RECEIVER_ERR_LOG), "{err}"),
        other => panic!("Expected WrongPaymentTx with invalid receiver, found {other:?}"),
    }
}

// DigiByte fork: a fee to the right address but below the expected amount must be rejected.
#[test]
fn dgb_validate_fee_rejects_underpaid() {
    let rpc_client = electrum_client_for_test(MARTY_ELECTRUM_ADDRS, ChainVariant::MORTY);
    let coin = utxo_coin_for_test(UtxoRpcClientEnum::Electrum(rpc_client), None, false);
    let tx_bytes = hex::decode("0400008085202f8901033aedb3c3c02fc76c15b393c7b1f638cfa6b4a1d502e00d57ad5b5305f12221000000006a473044022074879aabf38ef943eba7e4ce54c444d2d6aa93ac3e60ea1d7d288d7f17231c5002205e1671a62d8c031ac15e0e8456357e54865b7acbf49c7ebcba78058fd886b4bd012103242d9cb2168968d785f6914c494c303ff1c27ba0ad882dbc3c15cfa773ea953cffffffff0210270000000000001976a914ca1e04745e8ca0c60d8c5881531d51bec470743f88ac4802d913000000001976a914902053231ef0541a7628c11acac40d30f2a127bd88ac008e3765000000000000000000000000000000").unwrap();
    let taker_fee_tx = coin.tx_enum_from_bytes(&tx_bytes).unwrap();
    // The receiver matches (mocked to the fixture's address) but we expect twice what was paid.
    <UtxoStandardCoin as SwapOps>::dex_pubkey
        .mock_safe(|_| MockResult::Return(DEX_FEE_ADDR_RAW_PUBKEY_LEGACY.as_slice()));
    let expected: MmNumber = "0.0002".parse::<BigDecimal>().unwrap().into();
    let validate_fee_args = ValidateFeeArgs {
        fee_tx: &taker_fee_tx,
        expected_sender: &hex::decode("03242d9cb2168968d785f6914c494c303ff1c27ba0ad882dbc3c15cfa773ea953c").unwrap(),
        dex_fee: &DexFee::Standard(expected),
        min_block_number: 0,
        uuid: &[],
    };
    let result = block_on(coin.validate_fee(validate_fee_args));
    <UtxoStandardCoin as SwapOps>::dex_pubkey.clear_mock();
    match result.unwrap_err().into_inner() {
        ValidatePaymentError::WrongPaymentTx(err) => assert!(err.contains("less than expected"), "{err}"),
        other => panic!("Expected WrongPaymentTx underpaid, found {other:?}"),
    }
}
```
If `DEX_FEE_ADDR_RAW_PUBKEY_LEGACY` or `INVALID_RECEIVER_ERR_LOG` isn't already imported in `utxo_tests.rs`, import them from where `test_validate_old_fee_tx` and `test_validate_fee_wrong_sender` get them.

- [ ] **Step 2: Run the tests.** They should pass, because they characterise existing enforcement.

Run: `cargo test -p coins --lib dgb_validate_fee`
Expected: `2 passed`.

- [ ] **Step 3: Prove they bite.** Temporarily change `if out.script_pubkey != expected_script_pubkey {` in `utxo_common.rs` `validate_dex_output` (~l.2474) to `if false {` and run `cargo test -p coins --lib dgb_validate_fee_rejects_wrong_receiver`. Expected: FAIL, with the unwrap_err panic. Revert, then confirm that `git diff mm2src/coins/utxo/utxo_common.rs` is empty.

- [ ] **Step 4: Commit**

```bash
git add mm2src/coins/utxo/utxo_tests.rs
git commit -m "test(fee): maker rejects wrong-receiver and underpaid DEX fee" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 5: Rotate the DEX fee key

**Files:**
- Modify: `mm2src/common/common.rs:222-227`: the two constant values and the doc line.
- Modify: `mm2src/coins/lp_coins.rs`: the `dgb_dex_fee_pubkey_matches_owner_fee_address` test literal.
- Create: `DIGIBYTE.md` at the repo root, the fork notes.

**Interfaces:**
- Consumes: `NEW_FEE_PUBKEY` and `NEW_FEE_HASH160` from Task 1.

- [ ] **Step 1: Update the test to the new hash160** (RED first). In `lp_coins.rs`, `dgb_dex_fee_pubkey_matches_owner_fee_address`, set `const DGB_FEE_HASH160: &str = "<NEW_FEE_HASH160>";`, using the literal 40-hex value.

- [ ] **Step 2: Run it and confirm it fails**

Run: `cargo test -p coins --lib dgb_dex_fee_pubkey`
Expected: FAIL. The left side is `5e6bb7240aecd5138d3b5922b57233b3b491873c`, the old key.

- [ ] **Step 3: Set the constants.** In `common.rs`, set both `DEX_FEE_ADDR_PUBKEY` and `DEX_BURN_ADDR_PUBKEY` to `"<NEW_FEE_PUBKEY>"`, and set the doc line to:
```rust
/// DigiByte DEX fee key (owner-controlled, private key held offline since dgb-v3.0.0-beta.2).
```

- [ ] **Step 4: Run it and confirm it passes, along with the other fee tests**

Run: `cargo test -p coins --lib dgb_ && cargo test -p coins --lib taker_fee_tx_outputs && cargo test -p coins --lib dex_fee -- --skip validate_dex_fee_eth_confirmed_before_min_block`
Expected: all pass.

- [ ] **Step 5: Confirm the old key is gone.**
Run: `git grep -n "036f27a4e83ddf1239d545887d7dadd5aad8ab0a45518ff2c9fd2721e2d40da52a\|5e6bb7240aecd5138d3b5922b57233b3b491873c" -- mm2src`
Expected: no output.

- [ ] **Step 6: Create `DIGIBYTE.md`**

```markdown
# DigiByte fork of the Komodo DeFi Framework

This fork differs from upstream `GLEECBTC/komodo-defi-framework` in these ways only:

| Area | Change | Where |
|---|---|---|
| Network | `DEFAULT_NETID = 2014` (P2P 15847 / WSS 15857) | `mm2src/mm2_p2p/src/behaviours/atomicdex.rs` |
| P2P | Dial throttle reset on each swarm start; bootstrap marking only for dialed addrs | same file |
| DEX fee key | `DEX_FEE_ADDR_PUBKEY` = `DEX_BURN_ADDR_PUBKEY` = DigiByte key (offline) | `mm2src/common/common.rs` |
| DEX fee rate | 1% when either ticker root is `DGB`, else 2% | `mm2src/coins/lp_coins.rs` `dex_fee_rate` |
| Release | `dgb-release.yml`, pinned actions/container, `--locked`, fee-test gate | `.github/workflows/` |

**Not changed (known):**
- ZHTLC coins pay to upstream `DEX_BURN_Z_ADDR` (`mm2src/coins/z_coin.rs`).
- Sia uses upstream `DEX_FEE_PUBKEY_ED25519` (`mm2src/common/common.rs`).
- Do not list ARRR/ZEC-shielded or SC pairs until these are replaced.
- `PRICE_ENDPOINTS` (`mm2src/coins/lp_price.rs`) still point at GLEEC price services.
```

- [ ] **Step 7: Commit**

```bash
git add mm2src/common/common.rs mm2src/coins/lp_coins.rs DIGIBYTE.md
git commit -m "feat(fee): rotate DigiByte DEX fee key to offline key; add fork notes" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 6: Pin the release pipeline

**Files:**
- Modify: `.github/workflows/dgb-release.yml`
- Modify: `.github/actions/deps-install/action.yml` (the `setup-python` ref)

**Interfaces:**
- Produces: a workflow in which every external input is immutable.

Pins (resolved 2026-09-30):

| Ref | Pin |
|---|---|
| `actions/checkout@v4` | `actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0` |
| `actions/upload-artifact@v4` | `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2` |
| `actions/download-artifact@v4` | `actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093 # v4.3.0` |
| `actions/setup-python@v5` (deps-install) | `actions/setup-python@a26af69be951a213d495a4c3e4e4022e16d87065 # v5` |
| `komodoofficial/ci-container:latest` | `komodoofficial/ci-container@sha256:12c3051c751b99c5c6cad08e1c4ab9298be213e1f9d58c6b8c18e21ef9d6a8e4` |

- [ ] **Step 1: Re-verify the pins still resolve.** They must not have drifted since planning:

```bash
for r in checkout:v4.4.0 upload-artifact:v4.6.2 download-artifact:v4.3.0 setup-python:v5; do n=${r%%:*}; t=${r#*:}; echo "$n $t $(gh api repos/actions/$n/git/ref/tags/$t -q .object.sha)"; done
curl -s https://hub.docker.com/v2/repositories/komodoofficial/ci-container/tags/latest | jq -r .digest
```
Expected: the same SHAs and digest as the table. If `latest` moved, keep pinning the table's digest: it is the image that built `dgb-v3.0.0-beta.1`.

- [ ] **Step 2: Apply the pins**
  - Replace every `uses: actions/checkout@v4`, `actions/upload-artifact@v4` and `actions/download-artifact@v4` with the pinned forms from the table, keeping the `# vX.Y.Z` comment.
  - Change `container: komodoofficial/ci-container:latest` to the digest form.
  - In `deps-install/action.yml`, pin `actions/setup-python@v5`.
  - Add `--locked` to every cargo build and test command: `cargo build --release --locked`, `cargo rustc --locked ...`, and each `cargo test ... --locked` in `fee-tests`.
  - Add `dgb_validate_fee` to the fee-tests gate: `cargo test -p coins --lib dgb_ --locked` already covers it through the `dgb_` prefix. Confirm by running it locally.
  - Add `dial_guard` and `dgb_pick_bootstrap`: `cargo test -p mm2_p2p -p mm2_main -p chain --lib dial_guard --locked` and `cargo test -p mm2_p2p -p mm2_main -p chain --lib dgb_pick_bootstrap --locked`.

- [ ] **Step 3: Lint**

Run: `/tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/01d56841-7970-4b28-ba34-65645351704c/scratchpad/actionlint .github/workflows/dgb-release.yml`
Expected: no output, exit 0.

- [ ] **Step 4: Assert that no floating refs remain (Review Focus 5)**

```bash
! grep -nE 'uses: [^ ]+@v[0-9]+(\s|$)' .github/workflows/dgb-release.yml .github/actions/deps-install/action.yml
! grep -n ':latest' .github/workflows/dgb-release.yml
test "$(grep -cE 'cargo (build|rustc|test)' .github/workflows/dgb-release.yml)" = "$(grep -cE 'cargo (build|rustc|test).*--locked' .github/workflows/dgb-release.yml)"
echo OK
```
Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/dgb-release.yml .github/actions/deps-install/action.yml
git commit -m "ci: pin actions by SHA and container by digest; build with --locked; gate p2p and fee-enforcement tests" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 7: Release `dgb-v3.0.0-beta.2`

**Files:**
- Create: `~/.config/dgb-dex/kdf-release-2.env` (mode 600)

**Interfaces:**
- Produces: `KDF2_SHA` (40 hex), `KDF2_SHORT` (7), and `SHA2_ANDROID_AARCH64`, `SHA2_ANDROID_ARMV7`, `SHA2_IOS_AARCH64`, `SHA2_LINUX_X86_64`

- [ ] **Step 1: Push and tag**

```bash
cd ~/digibyte-dex/kdf
git push origin refs/heads/digibyte/main:refs/heads/digibyte/main
git tag -a dgb-v3.0.0-beta.2 -m "DigiByte KDF: P2P redial fix, offline fee key, pinned CI"
git push origin refs/tags/dgb-v3.0.0-beta.2
```

- [ ] **Step 2: Watch CI.** Run it in the background with `gh run watch <id> -R JohnnyLawDGB/komodo-defi-framework --exit-status`.
Expected: `fee-tests`, `linux-x86-64`, `ios-aarch64`, both `android` jobs and `release` all succeed.
If a pinned-container or `--locked` step fails, fix it in a new commit and re-tag. A re-tag deletes and recreates the tag and release; tags are not protected. Never move `dgb-v3.0.0-beta.1`.

- [ ] **Step 3: Verify the release and record the pins**

```bash
D=/tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/01d56841-7970-4b28-ba34-65645351704c/scratchpad/release2; mkdir -p $D
gh release download dgb-v3.0.0-beta.2 -R JohnnyLawDGB/komodo-defi-framework -D $D --clobber
(cd $D && sha256sum -c SHA256SUMS)
unzip -p $D/kdf_*-android-aarch64.zip libkdf.a | strings | grep -c -e "<NEW_FEE_PUBKEY>"
unzip -p $D/kdf_*-android-aarch64.zip libkdf.a | strings | grep -c "036f27a4e83ddf1239d545887d7dadd5aad8ab0a45518ff2c9fd2721e2d40da52a"
umask 077; { echo "KDF2_SHA=$(git rev-parse dgb-v3.0.0-beta.2^{commit})"; echo "KDF2_SHORT=$(git rev-parse --short=7 dgb-v3.0.0-beta.2^{commit})"; awk '{n=$2; gsub(/^kdf_[0-9a-f]+-|\.zip$/,"",n); gsub(/-/,"_",n); print "SHA2_" toupper(n) "=" $1}' $D/SHA256SUMS; } > ~/.config/dgb-dex/kdf-release-2.env
cat ~/.config/dgb-dex/kdf-release-2.env
```
Expected: 4 `OK`s. The new pubkey is found (count ≥ 1) and the old pubkey is not (count 0). The env file has 6 lines.

---

### Task 8: Upgrade the seed and the bot (bot stays stopped)

**Files:**
- none in git; this task operates the VPS and the workstation.

**Interfaces:**
- Consumes: `kdf-release-2.env`
- Produces: the seed running `3.0.0-beta_<KDF2_SHORT>`; the bot binary replaced but **stopped** until Task 9 Step 3.

- [ ] **Step 1: Stop the bot first** (Review Focus 4):
```bash
systemctl --user stop kdf-bot
PW=$(jq -r .rpc_password ~/.config/dgb-dex/bot/MM2.json); curl -s -m 5 http://127.0.0.1:7790 --data-binary @- <<<"{\"userpass\":\"$PW\",\"method\":\"version\"}" || echo "bot stopped"
```
- [ ] **Step 2: Upgrade the seed.** `install.sh` restarts the service and keeps the existing `MM2.json`.
```bash
source ~/.config/dgb-dex/kdf-release-2.env; source ~/.config/dgb-dex/kdf-release.env
cd ~/digibyte-dex/digibyte-wallet
sed -i 's#releases/download/dgb-v3.0.0-beta.1/#releases/download/${KDF_TAG:-dgb-v3.0.0-beta.2}/#' ops/seed/install.sh
scp -q -r ops/seed/* root@134.199.198.90:/root/kdf-seed-install/
ssh root@134.199.198.90 "KDF_TAG=dgb-v3.0.0-beta.2 bash /root/kdf-seed-install/install.sh $KDF2_SHORT $COINS_SHA" | tail -5
ssh root@134.199.198.90 'systemctl is-active kdf-seed; grep -m1 "Version:" <(tac /var/lib/kdf-seed/kdf.log); systemctl is-active electrumx'
```
Expected: `active`; a version line containing `3.0.0-beta_<KDF2_SHORT>`; ElectrumX `active`.
Commit the `install.sh` tag parameterisation in digibyte-wallet: `ops: seed installer takes KDF_TAG`.
- [ ] **Step 3: Replace the bot's binary. Do not start it.**
```bash
D=/tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/01d56841-7970-4b28-ba34-65645351704c/scratchpad/release2
unzip -o -q $D/kdf_${KDF2_SHORT}-linux-x86-64.zip kdf -d ~/.local/bin && ~/.local/bin/kdf --version
```
Expected: `Komodo DeFi Framework: 3.0.0-beta_<KDF2_SHORT>`.

---

### Task 9: Re-pin the SDK, rebuild the probe, verify on device

**Files:**
- Modify (SDK fork): `packages/komodo_defi_framework/app_build/build_config.json` (`api_commit_hash`, the 4 `valid_zip_sha256_checksums`)
- Modify (digibyte-wallet): the submodule pointer `third_party/komodo-defi-sdk-flutter`

**Interfaces:**
- Consumes: `kdf-release-2.env`

- [ ] **Step 1: SDK pins.** In `~/digibyte-dex/sdk`:
  - Set `api.api_commit_hash` to `KDF2_SHA`.
  - Set each platform's `valid_zip_sha256_checksums` to `[SHA2_…]`: `android-armv7`, `android-aarch64`, `ios`, `linux`.
  - Validate with `jq -e '.api.api_commit_hash=="'$KDF2_SHA'"' packages/komodo_defi_framework/app_build/build_config.json`, then run `cd packages/komodo_wallet_build_transformer && fvm flutter test`.
  - Commit `build: pin KDF dgb-v3.0.0-beta.2` and push `digibyte/main`.
- [ ] **Step 2: Rebuild the probe.**
  - In `~/digibyte-dex/digibyte-wallet`, run `git -C third_party/komodo-defi-sdk-flutter fetch origin digibyte/main && git -C third_party/komodo-defi-sdk-flutter checkout <new SDK sha>`.
  - Then run `cd m0_probe && GITHUB_API_PUBLIC_READONLY_TOKEN=$(gh auth token) fvm flutter build apk --debug`.
  - Verify: `unzip -p build/app/outputs/flutter-apk/app-debug.apk lib/arm64-v8a/libkomodo_defi_framework.so | strings | grep -c "3.0.0-beta_$KDF2_SHORT"` must be ≥ 1. The same command with the new pubkey must be ≥ 1, and with the old pubkey must be 0.
  - Commit `build(m0): SDK submodule @ <short>` and push.
- [ ] **Step 3: Install on the Moto, then start the bot.**
  - Run `adb -s ZY22HVMNKZ install -r m0_probe/build/app/outputs/flutter-apk/app-debug.apk`.
  - Only then run `systemctl --user start kdf-bot`.
  - Confirm the bot logs `Version: 3.0.0-beta_<KDF2_SHORT>` and that `my_orders` shows 2 orders within ~2 minutes.
- [ ] **Step 4: Check the reconnect fix on the device** (Review Focus 1). No orderbook-trick workaround is allowed.
  - Force-stop the app: `adb -s ZY22HVMNKZ shell am force-stop me.digiscope.wallet.m0`.
  - Relaunch it, enter the password from `~/.config/dgb-dex/m0-phone-password` in 8-character chunks (see the M0 lessons), and tap **Unlock + activate**.
  - Wait **60 s without touching the app**, then check the phone's sockets:
    ```bash
    U=$(adb -s ZY22HVMNKZ shell pm list packages -U me.digiscope.wallet.m0 | sed 's/.*uid://' | tr -d '\r')
    adb -s ZY22HVMNKZ shell cat /proc/net/tcp /proc/net/tcp6 | awk -v u=$U '$8==u && $4=="01" {print $3}' | grep -ci ':3DE7$'
    ```
    It must print `1`: an established connection to remote port 15847 (hex `3DE7`).
  - Tap **Network info**. Expected: `Network: netid=2014 asks=1 bids=1`.
  - With `dgb-v3.0.0-beta.1`, this check failed until about 5 minutes had passed.

---

### Task 10: Verification swap and fee-key cutover evidence

**Files:**
- Modify (digibyte-wallet): `docs/m0-report.md`, adding an "M1-A verification" section

- [ ] **Step 1: The owner says "go".** Then set the volume to 300 and tap **Buy DGB with LTC** once, by label. Monitor the bot side until `Finished`, as in M0.
- [ ] **Step 2: Fee evidence.** Read the `TakerFeeValidated` tx hash from the bot's `my_swap_status` and look it up on litecoinspace (`/api/tx/<hash>`).
  - Expected: one output with `scriptpubkey == "76a914<NEW_FEE_HASH160>88ac"` and value = floor(1% of the taker amount) in litoshis.
  - No output may go to `5e6bb724…873c`.
- [ ] **Step 3: Append the report section and commit.** Record the swap uuid, all four tx hashes, the fee output, the release tag and SHAs, and the Task 9 Step 4 reconnect timing. Commit `docs: M1-A verification (dgb-v3.0.0-beta.2)` and push.
- [ ] **Step 4: Retire the M0 fee wallet** (owner decision, recorded).
  - The old `dgb-dex-fees` wallet keeps its 3 DGB (M0 fees). The owner may sweep it to `NEW_FEE_DGB_ADDRESS` with `digibyte-cli -rpcwallet=dgb-dex-fees sendtoaddress <NEW_FEE_DGB_ADDRESS> 2.999 "" "" true`, but only on their explicit instruction.
  - The 0.00020167 LTC at `LTqCpSaa…` stays: it is below a sensible sweep fee.
  - Update `SECRETS-INDEX.md` to mark the wallet retired.
