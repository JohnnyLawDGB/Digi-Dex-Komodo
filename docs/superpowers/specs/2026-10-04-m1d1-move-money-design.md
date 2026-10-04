# M1-D1 "Move money": design spec

- **Date:** 2026-10-04
- **Status:** design approved in conversation; this written spec is pending owner review.
- **Parent spec:** `2026-09-27-digibyte-wallet-design.md`, §5.1 (Send, Asset detail, Receive URIs) and §8 (Security).
- **SDK research:** `.superpowers/research/m1d-sdk-send.md`, plus `m1c-sdk-api.md`.
- **Repos:**
  - app `JohnnyLawDGB/digibyte-wallet`, branch `feat/m1d1-move-money`;
  - SDK fork `digibyte/main`, only if a patch proves necessary.

## 1. Purpose and scope

M1 ends with a wallet that is "usable on mainnet". M1-C gave create, restore, unlock, balances and receive. The owner split the remainder of M1 into two milestones:

- **M1-D1 (this spec)** lets a user send DGB/BTC/LTC safely. It covers:
  - send;
  - asset detail with transaction history;
  - `digibyte:` payment links and QR scanning;
  - the M1-C follow-ups that touch security or the send path.
- **M1-D2 (later spec)** covers:
  - prices and fiat values, the portfolio total and sparklines;
  - Settings: fiat currency, theme, view seed, biometric toggle, auto-lock timeout, delete wallet, about, assets on/off;
  - log export;
  - the remaining follow-ups.

**Out of scope:**
- swaps (M2);
- iOS verification (the owner's Mac pass; iOS code paths are wired but untested);
- translations beyond English;
- fiat amounts anywhere (M1-D2);
- fee tiers;
- multi-transaction sends;
- consolidation.

**Success criteria:**
1. On the Moto, version 0.3.0 is installed from Play internal testing. A funded test wallet sends 1 DGB to an owner-chosen address, and makes one Max send.
2. The fee shown on Confirm equals the on-chain fee shown by digiexplorer.info.
3. The sends show in history as pending, then confirmed. The explorer link opens the right transaction.
4. A `digibyte:` link opened in Chrome lands on a prefilled Send, after unlock if the app was locked. A QR scan prefills Send.
5. No seed or password appears in logs. The task reviews and the whole-branch review are clean.

## 2. Decisions (owner, 2026-10-04)

| # | Decision |
|---|---|
| D1 | M1-D is split into D1 (move money) and D2 (polish). |
| D2 | Re-authenticate on **every** send at Confirm: biometric if enabled, otherwise the password through the shared lockout gate. |
| D3 | An HD send spends from **one address**: the one with the largest balance. Max means that address's balance. When the requested amount is higher, the app explains the limit. There is no multi-transaction send and no consolidation in D1. |
| D4 | The DGB explorer is `https://digiexplorer.info/tx/<txid>`. BTC uses `https://mempool.space/tx/<txid>` and LTC uses `https://litecoinspace.org/tx/<txid>`. |
| D5 | Only `digibyte:` is registered as an OS link handler. The in-app QR scanner understands `digibyte:`, `bitcoin:` and `litecoin:`. |
| D6 | The send flow is a form screen, then a Confirm screen built from the **signed preview**, then a Result screen. |
| D7 | Acceptance uses a fresh test wallet funded with about 5 DGB from the **M0 test-mule wallet**. The controller does the funding with a local KDF on the workstation, reading the seed from `~/.config/dgb-dex/m0-phone-seed`; the seed never goes to the phone or through adb. The owner confirmed the mule is expendable. There is no live LTC/BTC send; those are covered by unit and widget tests only. |
| D8 | Recipient addresses may be bech32 (`dgb1…` etc.) if the SDK validates them for the listed ticker. This must be verified on the device. |

## 3. Send

### 3.1 Entry points and route

- **Entry points:** the Send button on Asset detail, a Home row action, a `digibyte:` link (§5), or a QR scan (§5).
- **Route:** `/home/send/:ticker`. The router passes an optional prefill of address and amount through `extra` or a pending-request holder; it is never encoded into the URL.
- **Routing guards:** the existing auth/lock redirect applies. Send is reachable only while signed in and unlocked.

### 3.2 Form (`SendCubit`, editing)

**Address field:**
- trimmed; a pasted payment URI is parsed (§5.1);
- a URI for a different coin is rejected with a message;
- validated with `sdk.addresses.validateAddress`, debounced (about 400 ms);
- inline states: empty, checking, valid, invalid with a mapped reason ("Not a DigiByte address" and similar);
- a QR button opens the scanner (§5.2).

**Amount field:**
- a decimal with at most 8 places;
- must be at least the coin's dust (5460 sat for DGB/LTC; KDF's default for BTC);
- "Max" sets the amount to the source address's balance, and the fee is deducted by KDF (`isMax: true`).

**Available:**
- HD wallets: the balance of the **source address**, i.e. the HD address with the largest balance (from the pubkeys snapshot);
- iguana wallets: the single address's balance.

If the amount exceeds the source address balance but not the total, the form shows: "Up to X can be sent in one transaction. The rest is on other addresses."

**Next:** enabled when the address is valid and the amount is within limits. It calls the preview.

### 3.3 Preview

`sdk.withdrawals.previewWithdrawal(WithdrawParameters)`. This builds and signs the transaction without broadcasting it. The parameters:
- `asset`, `toAddress`, and either `amount` or `isMax: true`;
- `from`: `WithdrawalSource.hdWalletId(accountId: 0, addressId: n, chain: external)` for HD; **omitted** for iguana (KDF rejects it there);
- no `fee`, so the coin config default applies: DGB fixed 0.1 DGB/kB, LTC fixed, BTC electrum `estimatefee`.

SDK errors map to app failures:
- insufficient funds;
- below dust / amount too low;
- invalid address;
- fee estimate unavailable (BTC; retryable);
- network/engine (retryable);
- unknown.

### 3.4 Confirm screen

Shows, all taken from the signed preview:
- the recipient, rendered in groups of 4 characters for checking;
- the amount;
- the **fee from the preview** (the real fee of the signed transaction);
- the total;
- the source address.

**Warnings (§3.6):** a look-alike of a recent address, or sending to your own address. A warning needs an explicit "I've checked the address" acknowledgement before Send is enabled.

**Send button:**
1. Re-authenticate. Biometric (`BiometricStore.read`) if enabled; on cancel or failure fall back to the password field. Password attempts go through `PasswordGate`/`PasswordAttempts`, the shared lockout.
2. Run `executeWithdrawal(preview, assetId)` and wait for complete or error.

The screen is a `SecureScreen` (no screenshots of payment details) and shows no seed.

### 3.5 Result

- **Success:** the txid with copy, "View in explorer" (D4), and Done back to Asset detail. The balance is force-refreshed and history syncs.
- **Broadcast failure:** a mapped message, and "Back to edit", which discards the preview. A failed broadcast is never re-sent without a fresh preview.

### 3.6 Address-safety checks (parent spec §8.2)

**Recent addresses:** the counterparty addresses of the last 50 history entries for the asset, plus addresses the user has sent to.

**Poisoning:** the destination is not exactly a recent address, but shares its first 4 and last 4 characters with one. The warning shows both addresses with the differing middle highlighted.

**Self-send:** the destination is one of the wallet's own addresses (from the pubkeys). This is a warning only; it is allowed.

The checker is a pure, unit-tested function.

### 3.7 Safety rules

- **One send in flight per wallet.** A guard covers the span from preview to execute completion; KDF has no input reservation, so this prevents double-spend races. Double taps are ignored.
- **Discarding the preview.** Leaving Confirm, a lock (manual or auto), or sign-out discards the signed preview. It is held only in memory, in the cubit.
- **No logging.** Amounts, addresses and txids are not logged beyond what the SDK does. The password is never logged.

## 4. Asset detail and history

**Route:** `/home/asset/:ticker`, opened from the Home rows. The Home row tap goes here, and Receive moves to a button on this page.

**Header:**
- name and ticker;
- total balance, plus spendable when it differs;
- Send and Receive buttons.

**History** (`AssetHistoryCubit` over a `HistoryRepository` port):
- **Source:** `sdk.transactions.watchTransactionHistoryMerged(asset)`, which gives stored history, then fetched history, then live updates. HD covers account 0 across all addresses; iguana uses its single address.
- **Row:**
  - direction: received when `netChange > 0`; to self when `spentByMe > 0 && receivedByMe > 0 && netChange == -fee`; otherwise sent;
  - signed net amount;
  - local date and time;
  - status: Pending (0 confirmations), "Confirming n/N" (N is the coin config's `required_confirmations`, 7 for DGB), or Confirmed.
- **Paging:** 25 per page, with load-more on scroll.
- **States:** loading, empty ("No transactions yet"), and error with retry. The balance still shows during an error.
- **Pull-to-refresh:** `syncTransactionHistory` plus a forced balance refresh.

**Transaction detail** (a page or sheet):
- txid with copy;
- direction, amount, fee, confirmations, block height, date;
- counterparty addresses, excluding the wallet's own;
- View in explorer (D4).

## 5. Payment links and QR

### 5.1 `PaymentUri` (pure)

**Parses:**
- `digibyte:`, `bitcoin:` and `litecoin:` URIs (the scheme is case-insensitive), BIP21 style: `scheme:ADDRESS[?amount=..&label=..&message=..]`;
- a bare address with no scheme.

**Rules:**
- `amount` must match `^\d+(\.\d{1,8})?$`; otherwise the amount is dropped and the address kept;
- percent-decoding is applied;
- unknown parameters are ignored; any `req-*` parameter rejects the URI;
- the output is `{coin?, address, amount?, label?, message?}`;
- the parser checks shape only; validity comes from `validateAddress` on the form.

### 5.2 QR scanner

- **Package:** `mobile_scanner`. It runs on the device and offline (Android bundled ML Kit, iOS Vision), using the existing `CAMERA` permission. No new permission is added.
- **Page:** a full-screen scan page with a torch toggle and a cancel button. It stops at the first readable code.
- **Same coin:** the result fills the address and the amount (if present).
- **Different coin:** the page asks "This is a Bitcoin address. Open BTC send?" and never switches silently.
- **Not a payment code:** "Not a payment code".

### 5.3 OS links

**Android:**
- an intent filter for scheme `digibyte` (`VIEW`, `BROWSABLE`, `DEFAULT`) on `MainActivity`;
- the URI is delivered to Dart over the existing platform channel, both at cold start (the launch intent) and from `onNewIntent`;
- Flutter's automatic deep linking is disabled (`flutter_deeplinking_enabled=false`), so the router never receives raw external URLs.

**iOS:** `CFBundleURLTypes` with `digibyte` and the matching `AppDelegate` hook, wired up but verified only in the iOS pass.

**Pending request:**
- **Unlocked:** open `/home/send/DGB` with the request prefilled.
- **Locked or signed out:** keep a single in-memory pending request. It opens Send after the next unlock or sign-in, for whichever wallet signs in. It is dropped after 10 minutes or if the app is killed, and a newer link replaces it.
- **No wallet exists:** it is dropped, with a message on the welcome screen.

**Rules:**
- A link only **prefills**. Nothing is sent without the Confirm screen and re-authentication.
- `label` and `message` appear as "Payment request note" text. It is untrusted, plain, and truncated to 100 characters.

## 6. M1-C follow-ups included in D1

1. **Restore seed field.**
   - Turn off interactive selection, so the accessibility copy and cut actions are gone, and add an explicit Paste button.
   - Set `autofillHints: null`.
   - Redact `SeedTextController.toString`.
2. **Biometric opt-in.**
   - `isAvailable` requires a strong biometric (local_auth `getAvailableBiometrics` contains `strong`, or the equivalent).
   - `enable` returns an outcome. A failure shows a message in the UI rather than failing silently. This applies to Lock, Sign-in, Create and Restore.
   - Add a first-time opt-in widget test from the Lock page.
3. **One password gate.** The backup page's password prompt and the Send confirm both use `PasswordGate`/`PasswordAttempts`, so the lockout counts all attempts.
4. **Secure-storage warning.**
   - Find out which flutter_secure_storage namespace logs "EncryptedSharedPreferences initialization failed. Falling back to custom ciphers" on every cold start.
   - Then either fix it, or document it as the plugin's migration probe.
   - Either way, add a test that persisted state survives a restart.
5. **Port-fix leftovers.**
   - The orphan stop applies to any KDF status other than `notRunning`.
   - Dispose the SDK when startup fails after `startSdk`.
   - Comment the one-engine-per-process assumption.
6. **`tool/play_upload.py`.**
   - Use a long HTTP timeout (about 20 minutes) and a chunked resumable upload with retries. The 210 MB AAB failed under the 60 s default.
   - Document the 403 and the service-account permission ("Release apps to testing tracks").
7. **Acceptance tooling.** Never type real seeds via `adb shell input text`, because adbd logs it to logcat. Clear logcat after any secret entry and scan it at the end.

**Deferred to D2:**
- portfolio rows driven by `watchActivationStates`;
- the `revealSeed` whitespace split (it ships with View seed);
- the PassphraseMismatch message;
- `_guard` diagnostics;
- the newAddress partial-success message;
- seeding the LockCubit initial lifecycle and rewording the I2 comment;
- deleting `bio_pw_*` (it ships with Delete wallet);
- the remaining test-hygiene minors.

## 7. Architecture

The app's layering stays as it is (§4.2 of the parent spec): pages, then cubits, then app repositories (an `abstract interface class`, an `Sdk*` implementation, and fakes in `test/support/`), then SDK "ports" for types the SDK doesn't export.

**New units:**

| Unit | Responsibility |
|---|---|
| `domain/payment_uri.dart` | Pure parser (§5.1). |
| `domain/send_rules.dart` | Pure: amount precision, dust, the max/limit message, the source-address picker. |
| `domain/address_safety.dart` | Pure poisoning and self-send detector (§3.6). |
| `data/repositories/send_repository.dart` | `validate`, `sourceAddress`, `preview`, `broadcast`. Holds the per-wallet in-flight guard and the SDK error mapping. |
| `data/repositories/history_repository.dart` | Watch, page and sync history. Maps SDK `Transaction` to an app `TxView`. |
| `data/payment_links.dart` | Platform channel intake and the pending-request holder with its TTL. |
| `features/send/` | `SendCubit` (editing → previewing → confirming → broadcasting → done/failed), plus the form, confirm, result and scanner pages. |
| `features/asset/` | `AssetHistoryCubit`, the asset detail page, and the tx detail. |
| `config/explorers.dart` | URL templates per ticker (D4). |

**State machine (`SendCubit`):**
1. `editing` goes to `previewing` on Next.
2. `previewing` goes to `confirming(preview)` on success, or back to `editing(error)` on failure.
3. `confirming` goes to `authenticating`, then `broadcasting`.
4. `broadcasting` goes to `done(txid)` or `failed(reason)`.
5. From `confirming`, a lock, Back or sign-out discards the preview and returns to `editing`.

**Strings and identifiers:**
- All strings go in ARB. Every interactive widget is wrapped in `Tagged(id)` for acceptance.
- Ids use the prefixes `send.*`, `confirm.*`, `result.*`, `asset.*`, `tx.*` and `scan.*`.

## 8. Testing

**TDD.** Every unit gets RED then GREEN. Analyze must be clean (very_good_analysis; infos are fatal), and format must be clean.

**Pure units:**
- `PaymentUri`: BIP21 cases, bad amounts, `req-*` parameters, percent-encoding, a bare address, scheme case;
- `send_rules`: 8 decimals, dust, max, the over-limit message, the source picker with ties;
- `address_safety`: look-alike positive and negative cases, self-send.

**Repositories over fake ports:**
- `from` is set for HD and omitted for iguana;
- `isMax`;
- error mapping;
- the in-flight guard;
- history mapping: incoming, outgoing, self, pending.

**Cubits:**
- `SendCubit` through every transition, including:
  - double tap;
  - a lock while confirming, which discards the preview;
  - a preview error;
  - a broadcast error;
  - re-auth fallback, biometric then password;
  - re-auth attempts counted by the shared lockout.
- `AssetHistoryCubit`: paging and states.

**Widgets:**
- the form validation hints;
- the confirm warnings and their acknowledgement;
- the result explorer link;
- asset detail;
- the scanner result handling, with the scanner faked;
- a pending link opening Send after unlock;
- each D1 follow-up.

**Review:** subagent-driven execution, with a task review per task and one whole-branch review before the release build.

**On-device acceptance (Moto, 0.3.0 from Play internal testing):**
1. Create a test wallet `send1` on the device. The controller funds it with about 5 DGB from the M0 test mule, using a local KDF withdraw on the workstation (D7).
2. Send 1 DGB back to the M0 test-mule address, or to another address the owner chooses.
   - Check that the Confirm fee equals the digiexplorer.info fee.
   - Check that history shows pending, then confirmed.
   - Check that the explorer link opens the right transaction.
3. Make a Max send from the source address back to the M0 test mule, and check the balance and history.
4. Open a `digibyte:` link from Chrome, both while locked and while unlocked, and check that Send is prefilled.
5. Scan a QR code with the in-app scanner; a QR shown on another screen or the owner's other phone is fine. Check that Send is prefilled.
6. Check the poisoning warning with a crafted look-alike of a recent address. Send nothing; cancel at Confirm.
7. Verify on the device that a bech32 `dgb1…` recipient validates (D8).
8. Scan logcat: no seed, password or secret. Clear logcat after every secret entry. Real seeds are never typed through adb.

## 9. Release

- **Version:** 0.3.0, with a new versionCode from the local release lane. targetSdk stays 36.
- **Upload:** `tool/play_upload.py` once the service-account permission allows it. Otherwise the owner uploads manually to internal testing.
- **PR:** one PR, `feat/m1d1-move-money` → `main`, merged after the final review and green CI.

## 10. Risks and open items

- **Unconfirmed balances.** Whether spendable includes unconfirmed UTXOs, and whether KDF spends them, needs a live check. The Confirm and Available numbers follow the SDK either way.
- **BTC fee estimation.** `estimatefee` can fail on electrum; the app shows a retryable error.
- **Play API 403.** Uploads need the owner to grant the service account "Release apps to testing tracks". This only matters for automation; manual upload works.
- **iOS.** The URL scheme and scanner are unverified until the Mac pass.
