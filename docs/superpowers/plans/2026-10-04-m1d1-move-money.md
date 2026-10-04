# M1-D1: Move Money Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the Moto, DigiByte DEX 0.3.0 from Play internal testing sends DGB/BTC/LTC safely: a signed-preview Confirm with re-authentication on every send, asset detail with history and explorer links, `digibyte:` payment links and QR scanning, plus the M1-C follow-ups that touch security or the send path.

**Architecture:**
- The app's layering is unchanged (parent spec §4.2): pages → cubits → app-owned repositories (`abstract interface class` + `Sdk*` implementation over a small ports object + hand-written fakes in `test/support/`) → SDK.
- Pure rules live in `lib/domain/`: `payment_uri.dart` (BIP21 parser), `send_rules.dart` (precision, dust, source picker, one-transaction limit), `address_safety.dart` (look-alike and self-send).
- `SendRepository` validates, picks the HD source address (largest spendable balance), signs a preview with `previewWithdrawal`, broadcasts with `executeWithdrawal`, and holds the one-send-in-flight guard. `HistoryRepository` maps the SDK's merged history stream to app `TxView`s.
- `SendCubit` runs editing → previewing → confirming → authenticating → broadcasting → done/failed. Re-authentication goes through the existing `PasswordGate` (shared lockout, biometrics); the signed preview lives only in the cubit and the repository guard, and a lock, Back or sign-out drops it.
- `digibyte:` links arrive over the existing platform channel (`takePaymentLink` / `paymentLinkAvailable`). `PaymentLinkDispatcher` opens a prefilled DGB Send when unlocked, or holds one request (10-minute TTL) until the next unlock or sign-in. Flutter's own deep linking is off.

**Tech Stack:**
- Flutter 3.41.4 (fvm), Dart ≥3.9, flutter_bloc 9.1.1, go_router 17.5.0, equatable, decimal, intl, very_good_analysis 10.2.0, gen_l10n.
- New direct dependencies: `url_launcher: ^6.3.2` (resolves 6.3.3; Android 6.3.30, iOS 6.4.2) and `mobile_scanner: ^7.4.2` (already resolved transitively at 7.4.2 through `komodo_ui`; bundled ML Kit barcode model, CameraX). Neither adds an Android permission: the merged manifest still matches `tool/check_permissions.sh`.
- Tests: flutter_test, bloc_test 10, mocktail 1.0; Python `unittest` for `tool/play_upload.py` (in `tool/.venv`).

**Spec:** `docs/superpowers/specs/2026-10-04-m1d1-move-money-design.md` (binding, owner-approved). Parent: `docs/superpowers/specs/2026-09-27-digibyte-wallet-design.md` §5.1 and §8. SDK facts with file:line citations: `.superpowers/research/m1d-sdk-send.md` and `m1c-sdk-api.md`. All paths are relative to `~/Digi-Dex-Komodo`.

**Code base:** `~/digibyte-dex/digibyte-wallet` (`JohnnyLawDGB/digibyte-wallet`), branch `main` at `d750118` (M1-C + targetSdk 36). The Flutter app is `app/`. The SDK fork is the submodule `third_party/komodo-defi-sdk-flutter` at `2480d261` (`digibyte/main`). This plan needs **no SDK patch**: every API below exists in that pin. SDK citations are paths under `third_party/komodo-defi-sdk-flutter/packages/`.

**Execution:** subagent-driven (spec §8): one fresh implementer and one fresh reviewer per task, then one whole-branch review before the release build (Task 13).

### Where this plan departs from the spec, and why

1. **Look-alike check (spec §3.6).** The spec exempts a destination that is "exactly a recent address". A poisoning attack works by putting its own look-alike into your history with a dust transaction, so that exemption would wave through exactly the address the attacker wants copied. `AddressSafety.check` warns whenever the destination shares the first and last 4 characters with a *different* recent address, whether or not the destination is itself in history. An exact match with no other look-alike is still no warning.
2. **HD `from` (spec §3.3).** The spec names `WithdrawalSource.hdWalletId(accountId: 0, addressId: n, chain: external)`. KDF sends change back to the `from` address (kdf `coins/utxo/utxo_common.rs` ~740-760), so the largest balance can sit on a change (`Internal`) address. The plan passes `WithdrawalSource.hdDerivationPath(path)` with the source address's own derivation path (`komodo_defi_types/lib/src/withdrawal/withdrawal_types.dart:507-511`), which KDF accepts as `HDAddressSelector::DerivationPath` (kdf `coins/hd_wallet/mod.rs:537-546`). It names the same address and also covers change addresses. Iguana still omits `from`.
3. **History paging (spec §4).** `watchTransactionHistoryMerged` (`komodo_defi_sdk/lib/src/transaction_history/transaction_history_manager.dart:508-541`) already walks every page and emits whole lists. The 25-per-page paging is therefore done on screen: 25 rows, and 25 more each time the list is scrolled near its end. No extra RPC per page.
4. **Orphaned-KDF stop (spec §6.5).** "Any status other than `notRunning`" needs `KomodoDefiFramework.kdfMainStatus()` (`komodo_defi_framework/lib/komodo_defi_framework.dart:154-170`). When the native status says `notRunning`, that call also probes `version` over HTTP on this launch's own, freshly picked port, where nothing listens. M1-C's test asserted no HTTP at all; it now asserts that this probe is the only one.
5. **Task count.** 13 tasks instead of about 11: the §6 follow-ups are split where a reviewer could accept one and reject another (seed field, biometrics, backup gate, startup and storage, Play upload).

**Pre-verification (2026-10-04).** The code of Tasks 1–12 was applied, exactly as written in this plan (every "Create" and every "Replace … with …", in task order), to a fresh copy of `main` at `d750118` by a script, with these checks after each task:
- the task's new tests failed before its implementation and passed after it;
- `fvm dart format` changed nothing, and `fvm flutter analyze` reported `No issues found!`;
- the full suite passed: 348 tests at `d750118`, then 406, 433, 446, 466, 513, 522, 546, 551, 563, 567 and finally **573** after Task 11;
- Task 12's Python tests (5) failed before and passed after.

The result was byte-identical to the hand-verified tree. `fvm flutter build apk --debug` then built, Kotlin included, and `tool/check_permissions.sh` printed `permissions OK: 5 entries match allowlist`. The funding script of Task 13 was dry-run against the workstation's KDF (`3.0.0-beta_4715f29`) with a public BIP39 test vector: HD activation with a scan, the address list, and `task::withdraw::init` with `from.derivation_path` were all accepted; it stopped at `NotSufficientBalance`, then KDF stopped and its scratch directory was removed. Not verifiable here: the Swift code (no Mac; CI's `build-ios` compiles it) and everything on the device. Executors still follow every TDD step; a deviation from an expected output is a real finding.

### Known gaps (accepted for M1-D1)

- **iOS** (spec §1 out of scope): the `digibyte:` URL type, the scene-delegate link hook and the scanner are wired and compiled by CI, and verified only in the owner's Mac pass.
- **Unconfirmed funds** (spec §10): whether `spendable` includes unconfirmed coins and whether KDF spends them is checked live in Task 13; the app shows what the SDK reports either way.
- **ML Kit** ships Google Play services components (`MlKitInitProvider`, `GoogleApiActivity`) in the merged manifest; no new permission. See the owner question at the end of Task 13.

## Global Constraints

- **Identity:**
  - App name **DigiByte DEX**. Android `applicationId` and iOS bundle ID **`me.digiscope.wallet`**; this can never change.
  - Dart package name `digibyte_dex`; every app import is `package:digibyte_dex/...`.
- **Network:** netid `2014`, seed nodes `['seed1.digiscope.me']`, set only in `lib/config/brand.dart`.
- **Assets:** listed wallet assets are exactly the legacy P2PKH tickers `DGB`, `BTC`, `LTC` (`Brand.listedAssets`); DGB is pinned first. Every SDK asset lookup goes through `findListedAsset` (`lib/data/sdk/asset_lookup.dart`).
- **No Gleec or Komodo services at runtime:** `MarketDataConfig(enableKomodoPrice: false)`, coin-config auto-update off.
- **Toolchain:**
  - Flutter `3.41.4` via `.fvmrc`; always `fvm flutter` / `fvm dart`.
  - `very_good_analysis` 10.2.0 with `public_member_api_docs` off. `fvm flutter analyze` must report **`No issues found!`**: infos are fatal.
  - Run `fvm dart format lib test` before every analyze. The formatter does not wrap comments or strings; keep those under 80 columns by hand.
  - After changing `app_en.arb`, run `fvm flutter gen-l10n`. `lib/l10n/gen/` is gitignored.
- **Android:** targetSdk 36 and compileSdk 36, minSdk 28, 16 KB page alignment. Permissions stay `INTERNET`, `CAMERA` and `USE_BIOMETRIC` (`USE_FINGERPRINT` removed); the merged manifest's allowlist is `tool/check_permissions.sh` (it also lists `ACCESS_NETWORK_STATE` and `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`). Predictive back is enabled (`enableOnBackInvokedCallback="true"`). `allowBackup="false"`, `usesCleartextTraffic="false"`.
- **iOS:** 13+; Swift must compile on CI's `build-ios` (macOS). New Swift goes into existing files only: a new file would need `project.pbxproj` edits.
- **Branch:** app tasks commit on **`feat/m1d1-move-money`** in `~/digibyte-dex/digibyte-wallet`, created from `main` in Task 1.
- **SDK:** fork patches only if truly needed (none are in this plan). They would commit on `digibyte/main`, and the controller pushes.
- **Code style:** match the existing app:
  - repositories are `abstract interface class` + `Sdk*` implementation over a "ports" object built from the SDK (`XxxSdkPorts.of(sdk)`), with hand-written fakes in `test/support/`;
  - every interactive widget is wrapped in `Tagged(id)` with the same string as its `Key`; every id the acceptance task uses is tagged;
  - re-authentication goes through the existing `PasswordGate` / `PasswordAttempts`, never a second lockout counter;
  - timers are injectable (`TimerFactory`, `test/support/fake_timers.dart`); tests capture expected logs with `captureDebugPrint`;
  - `on Object catch` only; `unawaited(...)` for fire-and-forget futures;
  - logs carry only `runtimeType`, never an address, amount, txid, link, seed or password;
  - Equatable states and values that hold anything sensitive (addresses, amounts, signed transactions, seed words) turn `stringify` off.
- **Strings:** every user-facing string is in `lib/l10n/arb/app_en.arb`, read through `context.l10n`. The only exceptions are the biometric prompt texts (M1-C departure 8).
- **Secrets:** signing material, Play credentials, test seeds and passwords live only in `~/.config/dgb-dex/` (mode 600) and are never committed, echoed or put in test names. Test fixtures use dummies (`DAbc1111…wxyz`, `Correct-Horse-9`) or public BIP39 vectors.
- **Devices:** the Moto `ZY22HVMNKZ` only, always as `adb -s ZY22HVMNKZ`. Never touch the Note 8 `ce061716640b191c017e`. Never restart adb.
  - **Never type a real seed via `adb shell input text`**: adbd logs it to logcat. Throwaway values only.
  - Run `adb -s ZY22HVMNKZ logcat -c` right after any secret entry; scan the log at the end.
  - Read a checkbox's `checked` state before tapping it.
  - The Moto's fingerprint sensor is on the power button.
  - Use the official bundletool at `/tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/eab8c964-9b1e-44ec-b157-ec18db695089/scratchpad/tools/bundletool-all-1.18.1.jar`, not the gradle-cache jar.
- **Release:** version **0.3.0**, installed on the Moto through **Play internal testing** for acceptance (opt-in link https://play.google.com/apps/internaltest/4700509738211946340). `tool/play_upload.py` may get HTTP 403; then the owner uploads by hand.
- **Spending:** only the acceptance wallet `send1` and the M0 test mule move funds (spec D7; the owner confirmed the mule is expendable). No LTC or BTC is sent live.
- **Commit trailer:** every commit message ends with a blank line and then exactly these two lines (the commands below add them with a second `-m`):
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD
  ```
- **PR:** one PR `feat/m1d1-move-money` → `main`, opened in Task 13; its body ends with the line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. The **controller** merges it after the final whole-branch review and green CI; implementers never merge.
- **Scratch files:** `$SCRATCH` is the executing session's scratchpad directory. Put `export SCRATCH=<that path>` at the start of any command block that uses it.
- **Waiting:** foreground `sleep` is blocked in Claude Code. Waits longer than a few seconds run as a background `sleep N`; `ui.py pause N` (at most 10 s) covers short UI settles.

## Review Focus

1. **A pasted or scanned payment request that is malformed or for another coin** must never fill the form silently: more than 8 decimals or a non-number drops the amount and keeps the address; any `req-*` parameter rejects the whole request; `bitcoin:` on DGB Send is refused with a message, and a scan asks before opening BTC Send.
   - Task 1 `payment_uri_test.dart`: the "amounts" and "rejected" groups.
   - Task 5 `send_cubit_test.dart`: "a URI for another coin is refused, never switched"; `send_page_test.dart`: "a pasted URI for another coin is refused".
   - Task 6 `send_page_test.dart`: "a code for another coin asks; Cancel stays here".
2. **Double taps and retries** must never send twice: two taps on Next sign one preview, two taps on Send broadcast once, and a failed broadcast is never re-sent from the same signed transaction.
   - Task 2 `sdk_send_repository_test.dart`: "a double tap while previewing is refused", "a broadcast double tap sends once", "a failed broadcast is never re-sent from the same preview".
   - Task 5 `send_cubit_test.dart`: "a double tap on Next previews once", "a double tap on Send broadcasts once".
3. **A lock (auto or manual) while Confirm is open, the preview is being signed, or the biometric prompt is up** must drop the signed preview and send nothing; a lock during the broadcast must not cut it off.
   - Task 5 `send_cubit_test.dart`: the "discarding the preview" group; `send_page_test.dart`: "a lock while confirming drops the preview".
4. **An HD wallet whose coins are spread over several addresses, including change addresses**: the send comes from the richest address (change included), and an amount above it but within the total is explained, not sent.
   - Task 1 `send_rules_test.dart`: "over the source address but within the wallet: one-tx limit", `pickSource` ties.
   - Task 2 `sdk_send_repository_test.dart`: "HD sends from the source derivation path" (an `Internal` path).
   - Task 5 `send_page_test.dart`: "amount hints, including the one-transaction limit".
5. **A `digibyte:` link that arrives while locked, signed out, before any wallet exists, or more than 10 minutes before the unlock**: Send opens only after unlock or sign-in; with no wallet it is dropped with a message; an expired one opens nothing.
   - Task 7 `payment_link_dispatcher_test.dart` (every state, including "an adopted (locked) session never opens before unlock"); `app_test.dart`: the "digibyte: links" group.

Also pinned, though less likely to be missed: a poison address already in history still warns (Task 1); the shared lockout counts Confirm and backup attempts (Tasks 5 and 10); the seed field offers no accessibility Copy or Cut (Task 8).

## File map

| Unit | Responsibility | Task |
|---|---|---|
| `lib/domain/payment_uri.dart` | BIP21 / bare-address parser, payment note | 1 |
| `lib/domain/send_rules.dart` | amount rules, dust, source picker, preview amount | 1 |
| `lib/domain/address_safety.dart` | look-alike and self-send warnings, 4-character groups | 1 |
| `lib/data/repositories/send_repository.dart` | validate, source, preview, broadcast, in-flight guard, error mapping | 2 |
| `lib/data/repositories/history_repository.dart` | `TxView` mapping, history watch / sync, recent counterparties | 3 |
| `lib/config/explorers.dart`, `lib/platform/url_opener.dart` | explorer URLs (D4), opening them | 4 |
| `lib/features/asset/` | `AssetHistoryCubit`, asset detail page, tx detail sheet | 4 |
| `lib/features/send/` | `SendCubit`, Send page (form, Confirm, Result), scanner | 5, 6 |
| `lib/platform/qr_scanner.dart` | the camera scan as a replaceable service | 6 |
| `lib/data/payment_links.dart`, `lib/app/payment_link_dispatcher.dart` | OS link intake, pending request, routing | 7 |

---

### Task 1: Branch, and the pure rules: `PaymentUri`, `SendRules`, `AddressSafety`

Pure Dart with exhaustive unit tests: the BIP21 parser (spec §5.1), the send rules (spec §3.2, D3) and the address-safety checks (spec §3.6, departure 1). Nothing here touches the SDK or Flutter widgets.

**Files:**
- Create: `app/lib/domain/payment_uri.dart`
- Create: `app/lib/domain/send_rules.dart`
- Create: `app/lib/domain/address_safety.dart`
- Test (create): `app/test/domain/payment_uri_test.dart`
- Test (create): `app/test/domain/send_rules_test.dart`
- Test (create): `app/test/domain/address_safety_test.dart`

**Interfaces:**
- Consumes: `package:decimal`, `package:equatable` only.
- Produces (`lib/domain/payment_uri.dart`):
  - `class PaymentUri extends Equatable { const PaymentUri({required String address, String? ticker, Decimal? amount, String? label, String? message}); static PaymentUri? parse(String input); String? get note; static const noteLimit = 100; static const schemes = {'digibyte': 'DGB', 'bitcoin': 'BTC', 'litecoin': 'LTC'}; }` — `ticker` is null for a bare address; `stringify` off.
- Produces (`lib/domain/send_rules.dart`):
  - `class SpendableAddress extends Equatable { const SpendableAddress({required String address, required Decimal spendable, String? derivationPath}); }`
  - `enum AmountProblem { empty, malformed, tooPrecise, belowDust, overSource, overBalance }`
  - `abstract final class SendRules { static const maxDecimals = 8; static Decimal dust(String ticker); static bool hasDynamicFee(String ticker); static Decimal? parseAmount(String text); static AmountProblem? checkAmount(String text, {required String ticker, required Decimal source, required Decimal total}); static AmountProblem? checkMax(String ticker, Decimal source); static SpendableAddress? pickSource(List<SpendableAddress> addresses); static Decimal previewAmount({required Decimal? requested, required Decimal spentByMe, required Decimal receivedByMe, required Decimal fee}); }`
- Produces (`lib/domain/address_safety.dart`):
  - `sealed class AddressWarning extends Equatable`; `final class LookalikeWarning extends AddressWarning { const LookalikeWarning(String recent); }`; `final class OwnAddressWarning extends AddressWarning { const OwnAddressWarning(); }`
  - `abstract final class AddressSafety { static const edge = 4; static const recentLimit = 50; static List<AddressWarning> check({required String destination, required Iterable<String> recent, required Iterable<String> own}); static bool isLookalike(String a, String b); static List<String> groups(String address); static Set<int> differingGroups(String a, String b); }`

- [ ] **Step 1: Create the branch**

```bash
cd ~/digibyte-dex/digibyte-wallet
git status --short            # clean
git fetch origin
git checkout main && git pull --ff-only
git log --oneline -1          # d750118 Merge pull request #4 ... (or newer)
git checkout -b feat/m1d1-move-money
git submodule status          # 2480d261... third_party/komodo-defi-sdk-flutter
cd app && fvm flutter pub get && fvm flutter gen-l10n && fvm flutter test
```
Expected: `+348: All tests passed!` (the M1-C baseline).

- [ ] **Step 2: Write the failing tests**

Create `app/test/domain/payment_uri_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/domain/payment_uri.dart';
import 'package:flutter_test/flutter_test.dart';

// Shape-valid dummies, not real addresses.
const _dgb = 'DDummyAddress000000000000000000001';
const _btc = 'bc1qdummyaddress0000000000000000000000';

void main() {
  Decimal d(String s) => Decimal.parse(s);

  group('BIP21 URIs', () {
    test('address only', () {
      expect(
        PaymentUri.parse('digibyte:$_dgb'),
        const PaymentUri(ticker: 'DGB', address: _dgb),
      );
    });

    test('amount, label and message', () {
      final uri = PaymentUri.parse(
        'digibyte:$_dgb?amount=12.5&label=Coffee&message=Table%204',
      );
      expect(uri?.ticker, 'DGB');
      expect(uri?.address, _dgb);
      expect(uri?.amount, d('12.5'));
      expect(uri?.label, 'Coffee');
      expect(uri?.message, 'Table 4');
    });

    test('bitcoin: and litecoin: map to BTC and LTC', () {
      expect(PaymentUri.parse('bitcoin:$_btc')?.ticker, 'BTC');
      expect(PaymentUri.parse('litecoin:$_btc')?.ticker, 'LTC');
    });

    test('the scheme is case-insensitive', () {
      expect(PaymentUri.parse('DigiByte:$_dgb')?.ticker, 'DGB');
      expect(PaymentUri.parse('DIGIBYTE:$_dgb')?.ticker, 'DGB');
    });

    test('digibyte:// is accepted', () {
      expect(PaymentUri.parse('digibyte://$_dgb')?.address, _dgb);
    });

    test('surrounding whitespace is ignored', () {
      expect(PaymentUri.parse('  digibyte:$_dgb \n')?.address, _dgb);
    });

    test('percent-encoding is decoded; + is a space in parameters', () {
      final uri = PaymentUri.parse(
        'digibyte:$_dgb?label=Caf%C3%A9+Bleu&message=a%26b',
      );
      expect(uri?.label, 'Café Bleu');
      expect(uri?.message, 'a&b');
    });

    test('unknown parameters are ignored', () {
      final uri = PaymentUri.parse('digibyte:$_dgb?foo=bar&amount=1');
      expect(uri?.amount, d('1'));
    });

    test('the first of a repeated parameter wins', () {
      final uri = PaymentUri.parse('digibyte:$_dgb?amount=1&amount=2');
      expect(uri?.amount, d('1'));
    });
  });

  group('amounts', () {
    test('up to 8 decimals are kept', () {
      expect(
        PaymentUri.parse('digibyte:$_dgb?amount=0.00000001')?.amount,
        d('0.00000001'),
      );
    });

    for (final bad in [
      '1.123456789',
      '-1',
      '1e3',
      '1,5',
      '.5',
      '1.',
      'abc',
      '',
    ]) {
      test('"$bad" is dropped and the address kept', () {
        final uri = PaymentUri.parse('digibyte:$_dgb?amount=$bad');
        expect(uri?.address, _dgb);
        expect(uri?.amount, isNull);
      });
    }
  });

  group('rejected', () {
    test('any req-* parameter rejects the URI', () {
      expect(PaymentUri.parse('digibyte:$_dgb?req-foo=1'), isNull);
      expect(PaymentUri.parse('digibyte:$_dgb?amount=1&REQ-x=y'), isNull);
    });

    test('unknown schemes', () {
      expect(PaymentUri.parse('ethereum:$_dgb'), isNull);
      expect(PaymentUri.parse('https://example.com/$_dgb'), isNull);
    });

    test('malformed percent-encoding', () {
      expect(PaymentUri.parse('digibyte:$_dgb?label=%zz'), isNull);
      expect(PaymentUri.parse('digibyte:%zz$_dgb'), isNull);
    });

    test('no address, or not an address shape', () {
      expect(PaymentUri.parse('digibyte:'), isNull);
      expect(PaymentUri.parse('digibyte:?amount=1'), isNull);
      expect(PaymentUri.parse('digibyte:short'), isNull);
      expect(PaymentUri.parse('digibyte:$_dgb!x'), isNull);
    });

    test('empty input or plain text', () {
      expect(PaymentUri.parse(''), isNull);
      expect(PaymentUri.parse('   '), isNull);
      expect(PaymentUri.parse('hello world'), isNull);
    });
  });

  group('bare addresses', () {
    test('an address with no scheme has no coin', () {
      expect(PaymentUri.parse(_dgb), const PaymentUri(address: _dgb));
      expect(PaymentUri.parse(' $_btc '), const PaymentUri(address: _btc));
    });

    test('a bare address cannot carry parameters', () {
      expect(PaymentUri.parse('$_dgb?amount=1'), isNull);
    });
  });

  group('note', () {
    test('label and message, joined', () {
      expect(
        const PaymentUri(address: _dgb, label: 'Shop', message: 'Order 7').note,
        'Shop — Order 7',
      );
      expect(const PaymentUri(address: _dgb).note, isNull);
    });

    test('line breaks collapse and the note stops at 100 characters', () {
      final long = 'x' * 150;
      final note = PaymentUri(address: _dgb, message: 'a\nb $long').note!;
      expect(note.startsWith('a b x'), isTrue);
      expect(note.runes.length, PaymentUri.noteLimit);
      expect(note.endsWith('…'), isTrue);
    });
  });

  test('a request never prints its address', () {
    expect(const PaymentUri(address: _dgb).toString(), isNot(contains(_dgb)));
  });
}
```

Create `app/test/domain/send_rules_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/domain/send_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Decimal d(String s) => Decimal.parse(s);

  AmountProblem? check(String text, {String source = '10', String? total}) =>
      SendRules.checkAmount(
        text,
        ticker: 'DGB',
        source: d(source),
        total: d(total ?? source),
      );

  group('checkAmount', () {
    test('a plain amount within the source balance is fine', () {
      expect(check('1'), isNull);
      expect(check('1.5'), isNull);
      expect(check('.5'), isNull);
      expect(check('10'), isNull);
      expect(check(' 2 '), isNull);
      expect(check('2.'), isNull);
    });

    test('empty and malformed', () {
      expect(check(''), AmountProblem.empty);
      expect(check('  '), AmountProblem.empty);
      for (final bad in ['abc', '1,5', '-1', '1e3', '1.2.3', '+1']) {
        expect(check(bad), AmountProblem.malformed, reason: bad);
      }
    });

    test('at most 8 decimals', () {
      expect(check('0.00010000'), isNull);
      expect(check('0.000100001'), AmountProblem.tooPrecise);
    });

    test('dust: 5460 sat for DGB and LTC, 1000 sat for BTC', () {
      expect(SendRules.dust('DGB'), d('0.0000546'));
      expect(SendRules.dust('LTC'), d('0.0000546'));
      expect(SendRules.dust('BTC'), d('0.00001'));
      expect(check('0'), AmountProblem.belowDust);
      expect(check('0.00005459'), AmountProblem.belowDust);
      expect(check('0.0000546'), isNull);
    });

    test('over the source address but within the wallet: one-tx limit', () {
      expect(check('11', total: '15'), AmountProblem.overSource);
      expect(check('15', total: '15'), AmountProblem.overSource);
    });

    test('over the whole wallet', () {
      expect(check('16', total: '15'), AmountProblem.overBalance);
      expect(check('11'), AmountProblem.overBalance);
    });
  });

  test('Max needs more than dust on the source address', () {
    expect(SendRules.checkMax('DGB', d('1')), isNull);
    expect(SendRules.checkMax('DGB', d('0.0000546')), AmountProblem.belowDust);
    expect(SendRules.checkMax('DGB', Decimal.zero), AmountProblem.belowDust);
  });

  test('only BTC has a dynamic fee', () {
    expect(SendRules.hasDynamicFee('BTC'), isTrue);
    expect(SendRules.hasDynamicFee('DGB'), isFalse);
    expect(SendRules.hasDynamicFee('LTC'), isFalse);
  });

  group('pickSource', () {
    SpendableAddress a(String address, String spendable, [int? index]) =>
        SpendableAddress(
          address: address,
          spendable: d(spendable),
          derivationPath: index == null ? null : "m/44'/20'/0'/0/$index",
        );

    test('the largest spendable balance wins', () {
      final picked = SendRules.pickSource([
        a('A', '1', 0),
        a('B', '5', 1),
        a('C', '3', 2),
      ]);
      expect(picked?.address, 'B');
    });

    test('a tie goes to the lowest address index', () {
      final picked = SendRules.pickSource([
        a('A', '5', 3),
        a('B', '5', 1),
        a('C', '5', 2),
      ]);
      expect(picked?.address, 'B');
    });

    test('a tie without paths goes to the earlier entry', () {
      expect(SendRules.pickSource([a('A', '5'), a('B', '5')])?.address, 'A');
    });

    test('all empty: the first address, with nothing to spend', () {
      final picked = SendRules.pickSource([a('A', '0', 0), a('B', '0', 1)]);
      expect(picked?.address, 'A');
      expect(picked?.spendable, Decimal.zero);
    });

    test('no addresses: none', () {
      expect(SendRules.pickSource(const []), isNull);
    });
  });

  group('previewAmount', () {
    test('inputs minus change minus fee went to the recipient', () {
      expect(
        SendRules.previewAmount(
          requested: d('1'),
          spentByMe: d('10'),
          receivedByMe: d('8.9774'),
          fee: d('0.0226'),
        ),
        d('1'),
      );
    });

    test('Max: inputs minus the fee', () {
      expect(
        SendRules.previewAmount(
          requested: null,
          spentByMe: d('5'),
          receivedByMe: Decimal.zero,
          fee: d('0.0226'),
        ),
        d('4.9774'),
      );
    });

    test('back to the source address itself: the requested amount', () {
      expect(
        SendRules.previewAmount(
          requested: d('1'),
          spentByMe: d('10'),
          receivedByMe: d('9.9774'),
          fee: d('0.0226'),
        ),
        d('1'),
      );
      expect(
        SendRules.previewAmount(
          requested: null,
          spentByMe: d('5'),
          receivedByMe: d('4.9774'),
          fee: d('0.0226'),
        ),
        d('4.9774'),
      );
    });
  });
}
```

Create `app/test/domain/address_safety_test.dart`:

```dart
import 'package:digibyte_dex/domain/address_safety.dart';
import 'package:flutter_test/flutter_test.dart';

// Dummies, not real addresses.
const _payee = 'DAbc1111111111111111111111111wxyz';
const _poison = 'DAbc2222222222222222222222222wxyz';
const _other = 'DQrs3333333333333333333333333tuvw';
const _mine = 'DMine444444444444444444444444mine';

void main() {
  List<AddressWarning> check(
    String destination, {
    List<String> recent = const [_payee, _other],
    List<String> own = const [_mine],
  }) => AddressSafety.check(destination: destination, recent: recent, own: own);

  group('look-alikes (address poisoning)', () {
    test('same first and last 4 characters as a recent address', () {
      expect(check(_poison), [const LookalikeWarning(_payee)]);
    });

    test('exactly a recent address is no warning', () {
      expect(check(_payee), isEmpty);
    });

    test('a poison address in history still warns against the payee', () {
      // The attacker's dust transaction put _poison into history.
      expect(check(_poison, recent: const [_payee, _poison]), [
        const LookalikeWarning(_payee),
      ]);
      expect(check(_payee, recent: const [_payee, _poison]), [
        const LookalikeWarning(_poison),
      ]);
    });

    test('a new address that resembles nothing is no warning', () {
      expect(check('DNew5555555555555555555555555nnnn'), isEmpty);
    });

    test('same start but a different end is no warning', () {
      expect(check('DAbc2222222222222222222222222wxyQ'), isEmpty);
    });

    test('same end but a different start is no warning', () {
      expect(check('DAbQ2222222222222222222222222wxyz'), isEmpty);
    });

    test('the comparison is case-sensitive (base58)', () {
      expect(check('dabc2222222222222222222222222wxyz'), isEmpty);
    });

    test('very short strings never match', () {
      expect(AddressSafety.isLookalike('DAbcwxyz', 'DAbcwxyz'), isFalse);
      expect(AddressSafety.isLookalike('DAbcxyz', 'DAbcQxyz'), isFalse);
    });

    test('no recent addresses, no warning', () {
      expect(check(_poison, recent: const []), isEmpty);
    });
  });

  group('own addresses', () {
    test('sending to one of my addresses warns but is allowed', () {
      expect(check(_mine), [const OwnAddressWarning()]);
    });

    test('my own addresses are never look-alike candidates', () {
      expect(
        check('DMine999999999999999999999999mine', recent: const [_mine]),
        isEmpty,
      );
    });
  });

  group('display helpers', () {
    test('groups of 4 characters', () {
      expect(AddressSafety.groups('DAbc1111wxy'), ['DAbc', '1111', 'wxy']);
    });

    test('the differing middle groups are found', () {
      expect(AddressSafety.differingGroups(_payee, _poison), {
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      });
      expect(AddressSafety.differingGroups(_payee, _payee), isEmpty);
    });
  });

  test('warnings never print an address', () {
    expect(const LookalikeWarning(_payee).toString(), isNot(contains('DAbc')));
  });
}
```

- [ ] **Step 3: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/domain/payment_uri_test.dart \
  test/domain/send_rules_test.dart \
  test/domain/address_safety_test.dart
```

Expected: FAIL. The test files do not compile: `Error when reading 'lib/domain/payment_uri.dart': No such file or directory`, `Undefined name 'AddressSafety'`, `Couldn't find constructor 'LookalikeWarning'`.

- [ ] **Step 4: Implement**

Create `app/lib/domain/payment_uri.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

/// A payment request read from a link, a QR code or a paste (spec §5.1):
/// `scheme:ADDRESS[?amount=..&label=..&message=..]` (BIP21 style), or a
/// bare address.
///
/// The parser checks shape only. Whether [address] is valid for a coin is
/// decided later by `validateAddress`.
///
/// `stringify` is off: a request holds an address and an amount, which are
/// never logged.
class PaymentUri extends Equatable {
  const PaymentUri({
    required this.address,
    this.ticker,
    this.amount,
    this.label,
    this.message,
  });

  /// The coin the scheme names (`DGB`, `BTC` or `LTC`), or null for a bare
  /// address.
  final String? ticker;
  final String address;

  /// At most 8 decimal places; null when absent or malformed.
  final Decimal? amount;
  final String? label;
  final String? message;

  /// The longest "Payment request note" shown (spec §5.3).
  static const noteLimit = 100;

  /// Lower-case URI scheme to ticker (spec D5).
  static const schemes = {
    'digibyte': 'DGB',
    'bitcoin': 'BTC',
    'litecoin': 'LTC',
  };

  static final _scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*):(.*)$');
  static final _addressShape = RegExp(r'^[A-Za-z0-9]{20,100}$');
  static final _amountShape = RegExp(r'^\d+(\.\d{1,8})?$');

  /// Parses [input], or returns null when it is not a payment request: an
  /// unknown scheme, a malformed address or encoding, or any `req-*`
  /// parameter (BIP21: a required parameter we do not understand).
  static PaymentUri? parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final match = _scheme.firstMatch(text);
    if (match == null) {
      return _addressShape.hasMatch(text) ? PaymentUri(address: text) : null;
    }
    final ticker = schemes[match.group(1)!.toLowerCase()];
    if (ticker == null) return null;
    var rest = match.group(2)!;
    // Some wallets write `digibyte://ADDRESS`.
    if (rest.startsWith('//')) rest = rest.substring(2);
    final question = rest.indexOf('?');
    final rawAddress = question < 0 ? rest : rest.substring(0, question);
    final query = question < 0 ? '' : rest.substring(question + 1);
    final String address;
    final Map<String, String> params;
    try {
      address = Uri.decodeComponent(rawAddress).trim();
      params = _params(query);
    } on Object {
      // Malformed percent-encoding.
      return null;
    }
    if (!_addressShape.hasMatch(address)) return null;
    if (params.keys.any((key) => key.startsWith('req-'))) return null;
    final amount = params['amount'];
    return PaymentUri(
      ticker: ticker,
      address: address,
      amount: amount != null && _amountShape.hasMatch(amount)
          ? Decimal.parse(amount)
          : null,
      label: _nonEmpty(params['label']),
      message: _nonEmpty(params['message']),
    );
  }

  /// The query parameters, percent-decoded; the first of a repeated key
  /// wins. Keys are matched case-insensitively.
  static Map<String, String> _params(String query) {
    final params = <String, String>{};
    if (query.isEmpty) return params;
    for (final part in query.split('&')) {
      if (part.isEmpty) continue;
      final equals = part.indexOf('=');
      final key = Uri.decodeQueryComponent(
        equals < 0 ? part : part.substring(0, equals),
      ).toLowerCase();
      final value = equals < 0
          ? ''
          : Uri.decodeQueryComponent(part.substring(equals + 1));
      params.putIfAbsent(key, () => value);
    }
    return params;
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// [label] and [message] as one untrusted, plain line of at most
  /// [noteLimit] characters, or null when the request has neither.
  String? get note {
    final parts = [?label, ?message];
    if (parts.isEmpty) return null;
    final joined = parts.join(' — ').replaceAll(RegExp(r'\s+'), ' ');
    final runes = joined.runes.toList();
    if (runes.length <= noteLimit) return joined;
    return '${String.fromCharCodes(runes.take(noteLimit - 1))}…';
  }

  @override
  List<Object?> get props => [ticker, address, amount, label, message];

  @override
  bool? get stringify => false;
}
```

Create `app/lib/domain/send_rules.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

/// One wallet address and what can be spent from it now.
///
/// `stringify` is off: addresses and amounts are never logged.
class SpendableAddress extends Equatable {
  const SpendableAddress({
    required this.address,
    required this.spendable,
    this.derivationPath,
  });

  final String address;

  /// `m/44'/20'/0'/0/3` for an HD address; null for an iguana wallet.
  final String? derivationPath;
  final Decimal spendable;

  @override
  List<Object?> get props => [address, derivationPath, spendable];

  @override
  bool? get stringify => false;
}

/// Why an amount cannot be sent (spec §3.2).
enum AmountProblem {
  /// Nothing typed.
  empty,

  /// Not a plain decimal number.
  malformed,

  /// More than 8 decimal places.
  tooPrecise,

  /// Zero, or below the coin's dust limit.
  belowDust,

  /// More than the source address holds, but not more than the wallet
  /// holds in total (spec D3).
  overSource,

  /// More than the wallet holds.
  overBalance,
}

/// The pure send rules (spec §3.2, D3).
abstract final class SendRules {
  static const maxDecimals = 8;

  static final _number = RegExp(r'^(\d+(\.\d*)?|\.\d+)$');

  /// The smallest output KDF accepts. DGB and LTC set `dust: 5460` in the
  /// coin config; BTC has none, so KDF's default of 1000 sat applies
  /// (kdf `coins/utxo.rs:146`, `utxo_coin_builder.rs:595-596`).
  static Decimal dust(String ticker) => switch (ticker) {
    'DGB' || 'LTC' => Decimal.parse('0.0000546'),
    _ => Decimal.parse('0.00001'),
  };

  /// BTC's coin config has `txfee: 0`, so KDF asks electrum for a fee
  /// estimate, which can fail on its own (spec §10). DGB and LTC use a
  /// fixed per-kB fee.
  static bool hasDynamicFee(String ticker) => ticker == 'BTC';

  /// [text] as a number, or null when it is not a plain decimal.
  static Decimal? parseAmount(String text) {
    final trimmed = text.trim();
    if (!_number.hasMatch(trimmed)) return null;
    final whole = trimmed.startsWith('.') ? '0$trimmed' : trimmed;
    return Decimal.parse(whole.endsWith('.') ? '${whole}0' : whole);
  }

  /// The problem with sending [text] of [ticker], or null when it can be
  /// previewed. [source] is what the source address can spend; [total] is
  /// what the whole wallet can spend.
  static AmountProblem? checkAmount(
    String text, {
    required String ticker,
    required Decimal source,
    required Decimal total,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return AmountProblem.empty;
    final amount = parseAmount(trimmed);
    if (amount == null) return AmountProblem.malformed;
    final dot = trimmed.indexOf('.');
    if (dot >= 0 && trimmed.length - dot - 1 > maxDecimals) {
      return AmountProblem.tooPrecise;
    }
    if (amount < dust(ticker)) return AmountProblem.belowDust;
    if (amount > source) {
      return amount > total
          ? AmountProblem.overBalance
          : AmountProblem.overSource;
    }
    return null;
  }

  /// The problem with "Max" from a source holding [source], or null. KDF
  /// deducts the fee from the output, which must stay above dust.
  static AmountProblem? checkMax(String ticker, Decimal source) =>
      source <= dust(ticker) ? AmountProblem.belowDust : null;

  /// The address an HD send spends from: the one with the largest
  /// spendable balance (spec D3). Ties go to the lowest address index,
  /// then to the earlier entry. Null for an empty list.
  static SpendableAddress? pickSource(List<SpendableAddress> addresses) {
    SpendableAddress? best;
    for (final candidate in addresses) {
      if (best == null ||
          candidate.spendable > best.spendable ||
          (candidate.spendable == best.spendable &&
              _index(candidate) < _index(best))) {
        best = candidate;
      }
    }
    return best;
  }

  static int _index(SpendableAddress address) {
    final last = address.derivationPath?.split('/').last.replaceAll("'", '');
    return int.tryParse(last ?? '') ?? 1 << 30;
  }

  /// What the recipient gets, from a signed preview. KDF reports
  /// `spent_by_me` (the inputs) and `received_by_me` (outputs back to the
  /// source address, i.e. change), so the rest minus the fee went out
  /// (kdf `coins/utxo/utxo_withdraw.rs:229-234`). A send to the source
  /// address itself nets zero; then the requested amount is shown, or for
  /// Max the inputs minus the fee.
  static Decimal previewAmount({
    required Decimal? requested,
    required Decimal spentByMe,
    required Decimal receivedByMe,
    required Decimal fee,
  }) {
    final sent = spentByMe - receivedByMe - fee;
    if (sent > Decimal.zero) return sent;
    return requested ?? spentByMe - fee;
  }
}
```

Create `app/lib/domain/address_safety.dart`:

```dart
import 'package:equatable/equatable.dart';

/// A reason to double-check a destination before sending (spec §3.6,
/// parent spec §8.2). `stringify` is off: addresses are never logged.
sealed class AddressWarning extends Equatable {
  const AddressWarning();

  @override
  bool? get stringify => false;
}

/// The destination looks like [recent] (same first and last
/// [AddressSafety.edge] characters) but is not it: possible address
/// poisoning.
final class LookalikeWarning extends AddressWarning {
  const LookalikeWarning(this.recent);

  final String recent;

  @override
  List<Object?> get props => [recent];
}

/// The destination is one of this wallet's own addresses. Allowed.
final class OwnAddressWarning extends AddressWarning {
  const OwnAddressWarning();

  @override
  List<Object?> get props => [];
}

/// The pure address-safety checks.
abstract final class AddressSafety {
  /// How many leading and trailing characters a look-alike shares.
  static const edge = 4;

  /// How many history entries feed the recent-address list.
  static const recentLimit = 50;

  /// Every warning for sending to [destination]. [recent] holds the
  /// counterparties of recent history and earlier sends; [own] holds the
  /// wallet's addresses.
  ///
  /// A look-alike is any *other* recent address sharing the first and last
  /// [edge] characters. The destination itself being in [recent] does not
  /// clear it: a poisoning attack puts its address into history with a
  /// dust transaction, hoping it is copied from there.
  static List<AddressWarning> check({
    required String destination,
    required Iterable<String> recent,
    required Iterable<String> own,
  }) {
    final warnings = <AddressWarning>[];
    final ownSet = own.toSet();
    if (ownSet.contains(destination)) warnings.add(const OwnAddressWarning());
    for (final candidate in recent.toSet()) {
      if (candidate != destination &&
          !ownSet.contains(candidate) &&
          isLookalike(destination, candidate)) {
        warnings.add(LookalikeWarning(candidate));
        break;
      }
    }
    return warnings;
  }

  /// Different addresses that share their first and last [edge]
  /// characters.
  static bool isLookalike(String a, String b) {
    if (a == b || a.length < edge * 2 || b.length < edge * 2) return false;
    return a.substring(0, edge) == b.substring(0, edge) &&
        a.substring(a.length - edge) == b.substring(b.length - edge);
  }

  /// [address] in groups of 4 characters, for reading aloud.
  static List<String> groups(String address) => [
    for (var i = 0; i < address.length; i += 4)
      address.substring(i, i + 4 > address.length ? address.length : i + 4),
  ];

  /// The indexes of the 4-character groups where [a] and [b] differ, so
  /// the differing middle can be highlighted.
  static Set<int> differingGroups(String a, String b) {
    final left = groups(a);
    final right = groups(b);
    final count = left.length > right.length ? left.length : right.length;
    return {
      for (var i = 0; i < count; i++)
        if (i >= left.length || i >= right.length || left[i] != right[i]) i,
    };
  }
}
```

- [ ] **Step 5: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/domain/payment_uri_test.dart \
  test/domain/send_rules_test.dart \
  test/domain/address_safety_test.dart
```

Expected: `+58: All tests passed!`

- [ ] **Step 6: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```

Expected: the formatter changes 0 files; `No issues found!`; `+406: All tests passed!`.

- [ ] **Step 7: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/domain/address_safety.dart \
  lib/domain/payment_uri.dart \
  lib/domain/send_rules.dart \
  test/domain/address_safety_test.dart \
  test/domain/payment_uri_test.dart \
  test/domain/send_rules_test.dart
git commit -m "feat(domain): payment URIs, send rules and address safety" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 2: `SendRepository`: validate, source address, signed preview, broadcast, one send in flight

The only code that talks to the SDK's withdraw, address and pubkey APIs. SDK facts used (paths under `third_party/komodo-defi-sdk-flutter/packages/`):
- `sdk.addresses.validateAddress({asset, address})` never throws; an RPC failure is `isValid: false` with `invalidReason` "Validation failed: …" (`komodo_defi_sdk/lib/src/addresses/address_operations.dart:12-36`). That case is `AddressCheck.unverified`.
- `sdk.pubkeys.refreshPubkeys(asset)` / `getPubkeys(asset)` → `AssetPubkeys.keys[*]` with `address`, `derivationPath`, `chain` and `balance.spendable` (`komodo_defi_rpc_methods/lib/src/common_structures/general/new_address_info.dart:30-49`). The cache has no expiry, so the source refreshes first and falls back to the cache.
- `sdk.withdrawals.previewWithdrawal(WithdrawParameters)` builds and signs without broadcasting and throws `SdkError` (`komodo_defi_sdk/lib/src/withdrawals/withdrawal_manager.dart:1108-1205`). `executeWithdrawal(preview, assetId)` broadcasts the signed hex (`:1248`, `:1369`) and yields `WithdrawalStatus.complete` with `withdrawalResult.txHash` (`:1548-1556`); errors arrive as a stream error carrying `SdkError` (`:1576-1578`).
- `WithdrawParameters` (`komodo_defi_types/lib/src/withdrawal/withdrawal_types.dart:396-471`): exactly one of `amount` / `isMax: true`; no `fee`, so the coin config's default applies (DGB fixed 0.1 DGB/kB, LTC fixed, BTC electrum estimate). `WithdrawResult` (`:99-190`): `from`, `balanceChanges{spentByMe, receivedByMe}`, `fee.totalFee` (`komodo_defi_types/lib/src/transactions/fee_info.dart:416`).
- `SdkError.code` values (`komodo_defi_types/lib/src/errors/sdk_error.dart:17-41`) come from `komodo_defi_sdk/lib/src/errors/sdk_error_mapper.dart:587-760`. KDF reports a failed BTC fee estimate as `Transport` (kdf `coins/utxo.rs:225-235`), hence `feeUnavailable` for BTC network failures.
- HD needs `from`, iguana must not send it (kdf `coins/utxo/utxo_common.rs:3548-3578`); see departure 2.

**Files:**
- Create: `app/lib/data/repositories/send_repository.dart`
- Create: `app/test/support/fake_send_repository.dart`
- Test (create): `app/test/data/repositories/sdk_send_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 `SpendableAddress`, `SendRules.pickSource`, `SendRules.previewAmount`, `SendRules.hasDynamicFee`; `findListedAsset(sdk, ticker)` (`lib/data/sdk/asset_lookup.dart`).
- Produces (`lib/data/repositories/send_repository.dart`):
  - `enum SendFailure { insufficientFunds, amountTooLow, invalidAddress, feeUnavailable, network, busy, unknown; bool get retryable; }`
  - `final class SendException implements Exception { const SendException(SendFailure failure); }` and `SendFailure sendFailureOf(Object error, {bool dynamicFee = false})`
  - `enum AddressCheck { valid, invalid, unverified }`
  - `class SendSource extends Equatable { const SendSource({required SpendableAddress source, required Decimal total, required List<String> ownAddresses, required bool isHd}); }`
  - `class SendRequest extends Equatable { const SendRequest({required String ticker, required String toAddress, Decimal? amount}); bool get isMax; }` — `amount` null means Max.
  - `class SendPreview extends Equatable { const SendPreview({required String ticker, required String toAddress, required String fromAddress, required Decimal amount, required Decimal fee, required Object signed}); Decimal get total; }`
  - `abstract interface class SendRepository { Future<AddressCheck> validate(String ticker, String address); Future<SendSource> source(String ticker); Future<SendPreview> preview(SendRequest request, SendSource source); Future<String> broadcast(SendPreview preview); void release(SendPreview preview); bool get busy; List<String> sentTo(String ticker); }`
  - `typedef AddressSnapshot = ({List<SpendableAddress> keys, bool isHd});`
  - `class SendSdkPorts { const SendSdkPorts({required validate, required addresses, required preview, required broadcast}); factory SendSdkPorts.of(KomodoDefiSdk sdk); }`
  - `class SdkSendRepository implements SendRepository { SdkSendRepository(KomodoDefiSdk sdk); SdkSendRepository.withPorts(SendSdkPorts ports); }`
- Test support: `FakeSendRepository` (`test/support/fake_send_repository.dart`) with the real in-flight rules and fields `invalid`, `unverified`, `sourceResult`, `sourceFailure`, `previewFailure`, `broadcastFailure`, `fee`, `previewGate`, `broadcastGate`, `validated`, `requests`, `broadcasts`, `released`, `sent`; constants `fakeSourceAddress`, `fakeOtherOwnAddress`. Its txids are 64 hex characters (`aaaa…1`).

- [ ] **Step 1: Write the failing tests**

Create `app/test/data/repositories/sdk_send_repository_test.dart`:

```dart
import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/repositories/send_repository.dart';
import 'package:digibyte_dex/domain/send_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

import '../../support/capture_debug_print.dart';

// Dummies, not real addresses.
const _to = 'DRecipient0000000000000000000000001';
const _a0 = 'DSource00000000000000000000000000000';
const _a1 = 'DSource00000000000000000000000000001';

Decimal _d(String s) => Decimal.parse(s);

SdkError _sdkError(SdkErrorCode code) => SdkError(
  code: code,
  category: SdkErrorCategory.unknown,
  messageKey: 'k',
  fallbackMessage: 'secret detail never shown',
);

WithdrawResult _signed({
  String spent = '10',
  String received = '8.9774',
  String fee = '0.0226',
  List<String> from = const [_a1],
}) => WithdrawResult(
  txHex: 'deadbeef',
  txHash: 'abc123',
  from: from,
  to: const [_to],
  balanceChanges: BalanceChanges(
    netChange: _d(received) - _d(spent),
    receivedByMe: _d(received),
    spentByMe: _d(spent),
    totalAmount: _d(spent),
  ),
  blockHeight: 0,
  timestamp: 0,
  fee: FeeInfo.utxoFixed(coin: 'DGB', amount: _d(fee)),
  coin: 'DGB',
);

Matcher _throwsFailure(SendFailure failure) => throwsA(
  isA<SendException>().having((e) => e.failure, 'failure', failure),
);

void main() {
  late List<WithdrawParameters> previews;
  late List<WithdrawResult> broadcasts;
  late Future<WithdrawResult> Function() nextPreview;
  late Future<String> Function() nextBroadcast;
  late AddressSnapshot addresses;

  setUp(() {
    previews = [];
    broadcasts = [];
    nextPreview = () async => _signed();
    nextBroadcast = () async => 'txid-1';
    addresses = (
      keys: [
        SpendableAddress(
          address: _a0,
          derivationPath: "m/44'/20'/0'/0/0",
          spendable: _d('2'),
        ),
        SpendableAddress(
          address: _a1,
          derivationPath: "m/44'/20'/0'/1/0",
          spendable: _d('10'),
        ),
      ],
      isHd: true,
    );
  });

  SdkSendRepository build({
    Future<AddressCheck> Function(String, String)? validate,
    Future<AddressSnapshot> Function(String)? addressesPort,
  }) => SdkSendRepository.withPorts(
    SendSdkPorts(
      validate: validate ?? (ticker, address) async => AddressCheck.valid,
      addresses: addressesPort ?? (ticker) async => addresses,
      preview: (params) {
        previews.add(params);
        return nextPreview();
      },
      broadcast: (preview, ticker) {
        broadcasts.add(preview);
        return nextBroadcast();
      },
    ),
  );

  group('source', () {
    test('HD: the address with the largest balance, and the total', () async {
      final source = await build().source('DGB');
      expect(source.source.address, _a1);
      expect(source.source.spendable, _d('10'));
      expect(source.total, _d('12'));
      expect(source.ownAddresses, [_a0, _a1]);
      expect(source.isHd, isTrue);
    });

    test('iguana: the single address', () async {
      addresses = (
        keys: [SpendableAddress(address: _a0, spendable: _d('3'))],
        isHd: false,
      );
      final source = await build().source('DGB');
      expect(source.source.address, _a0);
      expect(source.total, _d('3'));
      expect(source.isHd, isFalse);
    });

    test('a failed lookup is a SendException', () async {
      final repo = build(
        addressesPort: (_) async => throw _sdkError(SdkErrorCode.transport),
      );
      await expectLater(
        repo.source('DGB'),
        _throwsFailure(SendFailure.network),
      );
    });

    test('no addresses at all is unknown', () async {
      addresses = (keys: const <SpendableAddress>[], isHd: true);
      await expectLater(
        build().source('DGB'),
        _throwsFailure(SendFailure.unknown),
      );
    });
  });

  group('preview', () {
    test('HD sends from the source derivation path', () async {
      final repo = build();
      final source = await repo.source('DGB');
      final preview = await repo.preview(
        SendRequest(ticker: 'DGB', toAddress: _to, amount: _d('1')),
        source,
      );
      final params = previews.single;
      expect(params.asset, 'DGB');
      expect(params.toAddress, _to);
      expect(params.amount, _d('1'));
      expect(params.isMax, isNull);
      expect(
        params.from,
        WithdrawalSource.hdDerivationPath("m/44'/20'/0'/1/0"),
      );
      expect(params.fee, isNull);
      expect(preview.amount, _d('1'));
      expect(preview.fee, _d('0.0226'));
      expect(preview.total, _d('1.0226'));
      expect(preview.fromAddress, _a1);
    });

    test('iguana omits from', () async {
      addresses = (
        keys: [SpendableAddress(address: _a0, spendable: _d('3'))],
        isHd: false,
      );
      final repo = build();
      await repo.preview(
        SendRequest(ticker: 'DGB', toAddress: _to, amount: _d('1')),
        await repo.source('DGB'),
      );
      expect(previews.single.from, isNull);
    });

    test('Max sends isMax and no amount', () async {
      nextPreview = () async => _signed(received: '0');
      final repo = build();
      final preview = await repo.preview(
        const SendRequest(ticker: 'DGB', toAddress: _to),
        await repo.source('DGB'),
      );
      expect(previews.single.isMax, isTrue);
      expect(previews.single.amount, isNull);
      expect(previews.single.toJson()['max'], isTrue);
      expect(preview.amount, _d('9.9774'));
    });

    final cases = {
      SdkErrorCode.insufficientFunds: SendFailure.insufficientFunds,
      SdkErrorCode.zeroBalance: SendFailure.insufficientFunds,
      SdkErrorCode.amountTooLow: SendFailure.amountTooLow,
      SdkErrorCode.invalidAddress: SendFailure.invalidAddress,
      SdkErrorCode.invalidFee: SendFailure.feeUnavailable,
      SdkErrorCode.networkUnavailable: SendFailure.network,
      SdkErrorCode.timeout: SendFailure.network,
      SdkErrorCode.general: SendFailure.unknown,
    };
    for (final entry in cases.entries) {
      test('${entry.key.name} maps to ${entry.value.name}', () async {
        nextPreview = () async => throw _sdkError(entry.key);
        final repo = build();
        await expectLater(
          repo.preview(
            SendRequest(ticker: 'DGB', toAddress: _to, amount: _d('1')),
            await repo.source('DGB'),
          ),
          _throwsFailure(entry.value),
        );
        expect(repo.busy, isFalse);
      });
    }

    test('a BTC network failure is the fee estimate (retryable)', () async {
      nextPreview = () async => throw _sdkError(SdkErrorCode.transport);
      final repo = build();
      await expectLater(
        repo.preview(
          SendRequest(ticker: 'BTC', toAddress: _to, amount: _d('1')),
          await repo.source('BTC'),
        ),
        _throwsFailure(SendFailure.feeUnavailable),
      );
      expect(SendFailure.feeUnavailable.retryable, isTrue);
    });

    test('a non-SDK error is unknown', () async {
      nextPreview = () async => throw StateError('boom');
      final repo = build();
      await expectLater(
        repo.preview(
          SendRequest(ticker: 'DGB', toAddress: _to, amount: _d('1')),
          await repo.source('DGB'),
        ),
        _throwsFailure(SendFailure.unknown),
      );
    });
  });

  group('one send in flight', () {
    test('a second preview while one is held is refused', () async {
      final repo = build();
      final source = await repo.source('DGB');
      final request = SendRequest(
        ticker: 'DGB',
        toAddress: _to,
        amount: _d('1'),
      );
      await repo.preview(request, source);
      expect(repo.busy, isTrue);
      await expectLater(
        repo.preview(request, source),
        _throwsFailure(SendFailure.busy),
      );
      expect(previews, hasLength(1));
    });

    test('a double tap while previewing is refused', () async {
      final gate = Completer<WithdrawResult>();
      nextPreview = () => gate.future;
      final repo = build();
      final source = await repo.source('DGB');
      final request = SendRequest(
        ticker: 'DGB',
        toAddress: _to,
        amount: _d('1'),
      );
      final first = repo.preview(request, source);
      await expectLater(
        repo.preview(request, source),
        _throwsFailure(SendFailure.busy),
      );
      gate.complete(_signed());
      await first;
      expect(previews, hasLength(1));
    });

    test('broadcast returns the txid, ends the span and remembers the '
        'destination', () async {
      final repo = build();
      final preview = await repo.preview(
        SendRequest(ticker: 'DGB', toAddress: _to, amount: _d('1')),
        await repo.source('DGB'),
      );
      expect(await repo.broadcast(preview), 'txid-1');
      expect(broadcasts.single.txHex, 'deadbeef');
      expect(repo.busy, isFalse);
      expect(repo.sentTo('DGB'), [_to]);
      expect(repo.sentTo('BTC'), isEmpty);
    });

    test('a broadcast double tap sends once', () async {
      final gate = Completer<String>();
      nextBroadcast = () => gate.future;
      final repo = build();
      final preview = await repo.preview(
        SendRequest(ticker: 'DGB', toAddress: _to, amount: _d('1')),
        await repo.source('DGB'),
      );
      final first = repo.broadcast(preview);
      await expectLater(
        repo.broadcast(preview),
        _throwsFailure(SendFailure.busy),
      );
      gate.complete('txid-1');
      expect(await first, 'txid-1');
      expect(broadcasts, hasLength(1));
    });

    test('a failed broadcast is never re-sent from the same preview', () async {
      nextBroadcast = () async => throw _sdkError(SdkErrorCode.transport);
      final repo = build();
      final preview = await repo.preview(
        SendRequest(ticker: 'DGB', toAddress: _to, amount: _d('1')),
        await repo.source('DGB'),
      );
      await expectLater(
        repo.broadcast(preview),
        _throwsFailure(SendFailure.network),
      );
      expect(repo.busy, isFalse);
      nextBroadcast = () async => 'txid-2';
      await expectLater(
        repo.broadcast(preview),
        _throwsFailure(SendFailure.busy),
      );
      expect(broadcasts, hasLength(1));
    });

    test('release drops the preview and frees the wallet', () async {
      final repo = build();
      final source = await repo.source('DGB');
      final request = SendRequest(
        ticker: 'DGB',
        toAddress: _to,
        amount: _d('1'),
      );
      final preview = await repo.preview(request, source);
      repo.release(preview);
      expect(repo.busy, isFalse);
      await expectLater(
        repo.broadcast(preview),
        _throwsFailure(SendFailure.busy),
      );
      await repo.preview(request, source);
      expect(previews, hasLength(2));
    });

    test('release during a broadcast does not end it early', () async {
      final gate = Completer<String>();
      nextBroadcast = () => gate.future;
      final repo = build();
      final preview = await repo.preview(
        SendRequest(ticker: 'DGB', toAddress: _to, amount: _d('1')),
        await repo.source('DGB'),
      );
      final sending = repo.broadcast(preview);
      repo.release(preview);
      expect(repo.busy, isTrue);
      gate.complete('txid-1');
      await sending;
      expect(repo.busy, isFalse);
    });
  });

  group('validate', () {
    test('passes the port result through', () async {
      final repo = build(validate: (_, _) async => AddressCheck.invalid);
      expect(await repo.validate('DGB', 'x'), AddressCheck.invalid);
    });

    test('a throwing port is unverified, logged by type only', () async {
      final logs = captureDebugPrint();
      final repo = build(validate: (_, _) async => throw StateError(_to));
      expect(await repo.validate('DGB', _to), AddressCheck.unverified);
      expect(logs.single, 'Address check failed: StateError');
    });
  });

  test('exceptions and values never print addresses or amounts', () {
    expect(
      const SendException(SendFailure.network).toString(),
      'SendException(network)',
    );
    expect(
      SendRequest(ticker: 'DGB', toAddress: _to, amount: _d('1')).toString(),
      isNot(contains(_to)),
    );
  });
}
```

Create `app/test/support/fake_send_repository.dart`:

```dart
import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/repositories/send_repository.dart';
import 'package:digibyte_dex/domain/send_rules.dart';

/// Dummy addresses for send tests; not real addresses.
const fakeSourceAddress = 'DSource00000000000000000000000000001';
const fakeOtherOwnAddress = 'DSource00000000000000000000000000000';

/// Hand-written [SendRepository] with the real in-flight rules.
class FakeSendRepository implements SendRepository {
  /// Addresses [validate] calls invalid, or unverified.
  Set<String> invalid = {};
  Set<String> unverified = {};

  SendSource sourceResult = SendSource(
    source: SpendableAddress(
      address: fakeSourceAddress,
      derivationPath: "m/44'/20'/0'/0/1",
      spendable: Decimal.parse('10'),
    ),
    total: Decimal.parse('12'),
    ownAddresses: const [fakeOtherOwnAddress, fakeSourceAddress],
    isHd: true,
  );
  SendFailure? sourceFailure;
  SendFailure? previewFailure;
  SendFailure? broadcastFailure;
  Decimal fee = Decimal.parse('0.0226');

  /// When set, [preview] / [broadcast] wait for it.
  Completer<void>? previewGate;
  Completer<void>? broadcastGate;

  final validated = <String>[];
  final requests = <SendRequest>[];
  final broadcasts = <SendPreview>[];
  final released = <SendPreview>[];
  final sent = <String, List<String>>{};
  SendPreview? _held;
  bool _working = false;

  @override
  bool get busy => _working || _held != null;

  @override
  List<String> sentTo(String ticker) => sent[ticker] ?? const [];

  @override
  Future<AddressCheck> validate(String ticker, String address) async {
    validated.add(address);
    if (unverified.contains(address)) return AddressCheck.unverified;
    return invalid.contains(address)
        ? AddressCheck.invalid
        : AddressCheck.valid;
  }

  @override
  Future<SendSource> source(String ticker) async {
    final failure = sourceFailure;
    if (failure != null) throw SendException(failure);
    return sourceResult;
  }

  @override
  Future<SendPreview> preview(SendRequest request, SendSource source) async {
    if (busy) throw const SendException(SendFailure.busy);
    _working = true;
    try {
      requests.add(request);
      await previewGate?.future;
      final failure = previewFailure;
      if (failure != null) throw SendException(failure);
      final amount = request.amount ?? source.source.spendable - fee;
      return _held = SendPreview(
        ticker: request.ticker,
        toAddress: request.toAddress,
        fromAddress: source.source.address,
        amount: amount,
        fee: fee,
        signed: Object(),
      );
    } finally {
      _working = false;
    }
  }

  @override
  Future<String> broadcast(SendPreview preview) async {
    if (_working || !identical(preview, _held)) {
      throw const SendException(SendFailure.busy);
    }
    _working = true;
    try {
      broadcasts.add(preview);
      await broadcastGate?.future;
      final failure = broadcastFailure;
      if (failure != null) throw SendException(failure);
      (sent[preview.ticker] ??= []).add(preview.toAddress);
      // 64 hex characters, like a real txid (see tx_views.dart fakeTxid).
      return broadcasts.length.toRadixString(16).padLeft(64, 'a');
    } finally {
      _working = false;
      _held = null;
    }
  }

  @override
  void release(SendPreview preview) {
    released.add(preview);
    if (!_working && identical(preview, _held)) _held = null;
  }
}
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/data/repositories/sdk_send_repository_test.dart
```

Expected: FAIL. `Error when reading 'lib/data/repositories/send_repository.dart': No such file or directory`, then `Undefined name 'SendFailure'`, `Method not found: 'SendRequest'`.

- [ ] **Step 3: Implement**

Create `app/lib/data/repositories/send_repository.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/sdk/asset_lookup.dart';
import 'package:digibyte_dex/domain/send_rules.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Every send error the UI tells apart (spec §3.3).
enum SendFailure {
  insufficientFunds,
  amountTooLow,
  invalidAddress,

  /// BTC's electrum fee estimate failed. Retryable.
  feeUnavailable,

  /// Network or engine trouble. Retryable.
  network,

  /// Another send is between preview and broadcast, or this preview was
  /// already used or discarded.
  busy,
  unknown;

  bool get retryable => this == feeUnavailable || this == network;
}

/// Thrown by [SendRepository]. Carries only the category, never an
/// address, amount or SDK message.
final class SendException implements Exception {
  const SendException(this.failure);

  final SendFailure failure;

  @override
  String toString() => 'SendException(${failure.name})';
}

/// The only mapping from SDK withdraw errors to [SendFailure].
/// `previewWithdrawal` throws an `SdkError`
/// (withdrawal_manager.dart:1199-1203) and `executeWithdrawal` emits one
/// (:1576-1578); the codes come from `sdk_error_mapper.dart:587-760`.
/// With [dynamicFee] (BTC), a network failure is the fee estimate: KDF
/// asks electrum for it and reports a failure as `Transport`
/// (kdf `coins/utxo.rs:225-235`).
SendFailure sendFailureOf(Object error, {bool dynamicFee = false}) {
  if (error is SendException) return error.failure;
  if (error is! SdkError) return SendFailure.unknown;
  final failure = switch (error.code) {
    SdkErrorCode.insufficientFunds ||
    SdkErrorCode.insufficientGas ||
    SdkErrorCode.insufficientFeeBalance ||
    SdkErrorCode.zeroBalance => SendFailure.insufficientFunds,
    SdkErrorCode.amountTooLow => SendFailure.amountTooLow,
    SdkErrorCode.invalidAddress => SendFailure.invalidAddress,
    SdkErrorCode.invalidFee => SendFailure.feeUnavailable,
    SdkErrorCode.networkUnavailable ||
    SdkErrorCode.timeout ||
    SdkErrorCode.transport ||
    SdkErrorCode.invalidResponse ||
    SdkErrorCode.assetNotActivated ||
    SdkErrorCode.activationFailed => SendFailure.network,
    _ => SendFailure.unknown,
  };
  return failure == SendFailure.network && dynamicFee
      ? SendFailure.feeUnavailable
      : failure;
}

/// What `validateAddress` said about a destination.
enum AddressCheck {
  valid,
  invalid,

  /// The check itself failed (engine or network); try again.
  unverified,
}

/// Where a send can come from (spec §3.2, D3).
///
/// `stringify` is off: addresses and amounts are never logged.
class SendSource extends Equatable {
  const SendSource({
    required this.source,
    required this.total,
    required this.ownAddresses,
    required this.isHd,
  });

  /// The address a send spends from: for HD the one with the largest
  /// spendable balance, for iguana the only one.
  final SpendableAddress source;

  /// What the whole wallet can spend, across all addresses.
  final Decimal total;

  /// Every address of this wallet (receiving and change), for the
  /// self-send check.
  final List<String> ownAddresses;
  final bool isHd;

  @override
  List<Object?> get props => [source, total, ownAddresses, isHd];

  @override
  bool? get stringify => false;
}

/// What the user asked to send. [amount] is null for Max.
class SendRequest extends Equatable {
  const SendRequest({
    required this.ticker,
    required this.toAddress,
    this.amount,
  });

  final String ticker;
  final String toAddress;
  final Decimal? amount;

  bool get isMax => amount == null;

  @override
  List<Object?> get props => [ticker, toAddress, amount];

  @override
  bool? get stringify => false;
}

/// A built and signed, not yet broadcast, transaction (spec §3.3). Every
/// number on the Confirm screen comes from here.
///
/// `stringify` is off: it holds addresses, amounts and the signed hex.
class SendPreview extends Equatable {
  const SendPreview({
    required this.ticker,
    required this.toAddress,
    required this.fromAddress,
    required this.amount,
    required this.fee,
    required this.signed,
  });

  final String ticker;
  final String toAddress;
  final String fromAddress;

  /// What the recipient gets.
  final Decimal amount;

  /// The fee of the signed transaction.
  final Decimal fee;

  /// The SDK's signed preview; only the ports read it.
  final Object signed;

  Decimal get total => amount + fee;

  @override
  List<Object?> get props => [ticker, toAddress, fromAddress, amount, fee];

  @override
  bool? get stringify => false;
}

/// Sends one listed asset: validate, source, preview, broadcast.
///
/// One send is in flight at a time (spec §3.7): from [preview] until
/// [broadcast] completes or [release] is called, another [preview] fails
/// with [SendFailure.busy]. KDF does not reserve inputs between a preview
/// and its broadcast (kdf `coins/utxo/utxo_withdraw.rs:171`), so two
/// previews could spend the same coins.
abstract interface class SendRepository {
  /// Never throws; a failed check is [AddressCheck.unverified].
  Future<AddressCheck> validate(String ticker, String address);

  /// Throws [SendException].
  Future<SendSource> source(String ticker);

  /// Builds and signs [request] from [source]. Throws [SendException].
  Future<SendPreview> preview(SendRequest request, SendSource source);

  /// Broadcasts [preview] and returns the txid. A preview is broadcast at
  /// most once, success or not. Throws [SendException].
  Future<String> broadcast(SendPreview preview);

  /// Drops [preview] without broadcasting it (Back, lock, sign-out).
  void release(SendPreview preview);

  /// True from a preview until its broadcast ends or it is released.
  bool get busy;

  /// Destinations sent to in this session, for the look-alike check.
  List<String> sentTo(String ticker);
}

typedef AddressSnapshot = ({List<SpendableAddress> keys, bool isHd});

/// The SDK calls [SdkSendRepository] needs. A seam for tests, because the
/// SDK's `PubkeyManager` and `AddressOperations` are not exported.
class SendSdkPorts {
  const SendSdkPorts({
    required this.validate,
    required this.addresses,
    required this.preview,
    required this.broadcast,
  });

  factory SendSdkPorts.of(KomodoDefiSdk sdk) {
    Asset asset(String ticker) => findListedAsset(sdk, ticker);
    AddressSnapshot snapshot(AssetPubkeys pubkeys, {required bool isHd}) => (
      keys: [
        for (final key in pubkeys.keys)
          SpendableAddress(
            address: key.address,
            derivationPath: key.derivationPath,
            spendable: key.balance.spendable,
          ),
      ],
      isHd: isHd,
    );
    return SendSdkPorts(
      // `AddressOperations.validateAddress` never throws; an RPC failure
      // is `isValid: false` with "Validation failed: …"
      // (komodo_defi_sdk/lib/src/addresses/address_operations.dart:12-36).
      validate: (ticker, address) async {
        final result = await sdk.addresses.validateAddress(
          asset: asset(ticker),
          address: address,
        );
        if (result.isValid) return AddressCheck.valid;
        final reason = result.invalidReason ?? '';
        return reason.startsWith('Validation failed')
            ? AddressCheck.unverified
            : AddressCheck.invalid;
      },
      // Fresh balances (the pubkey cache has no expiry,
      // pubkey_manager.dart:37); the cache if the refresh fails.
      addresses: (ticker) async {
        final isHd = (await sdk.auth.currentUser)?.isHd ?? false;
        AssetPubkeys pubkeys;
        try {
          pubkeys = await sdk.pubkeys.refreshPubkeys(asset(ticker));
        } on Object {
          pubkeys = await sdk.pubkeys.getPubkeys(asset(ticker));
        }
        return snapshot(pubkeys, isHd: isHd);
      },
      preview: sdk.withdrawals.previewWithdrawal,
      // Broadcasts the signed hex (withdrawal_manager.dart:1248, :1369);
      // the txid arrives with `WithdrawalStatus.complete` (:1548-1556).
      broadcast: (preview, ticker) async {
        await for (final progress in sdk.withdrawals.executeWithdrawal(
          preview,
          ticker,
        )) {
          if (progress.status == WithdrawalStatus.complete) {
            final txid = progress.withdrawalResult?.txHash;
            if (txid != null) return txid;
          }
          if (progress.status == WithdrawalStatus.error) {
            throw progress.sdkError ?? const SendException(SendFailure.unknown);
          }
        }
        throw const SendException(SendFailure.unknown);
      },
    );
  }

  final Future<AddressCheck> Function(String ticker, String address) validate;
  final Future<AddressSnapshot> Function(String ticker) addresses;
  final Future<WithdrawalPreview> Function(WithdrawParameters parameters)
  preview;
  final Future<String> Function(WithdrawalPreview preview, String ticker)
  broadcast;
}

class SdkSendRepository implements SendRepository {
  SdkSendRepository(KomodoDefiSdk sdk) : this.withPorts(SendSdkPorts.of(sdk));

  @visibleForTesting
  SdkSendRepository.withPorts(this._ports);

  final SendSdkPorts _ports;
  final _sentTo = <String, List<String>>{};
  bool _previewing = false;
  bool _broadcasting = false;
  SendPreview? _held;

  @override
  bool get busy => _previewing || _broadcasting || _held != null;

  @override
  List<String> sentTo(String ticker) => List.unmodifiable(
    _sentTo[ticker] ?? const <String>[],
  );

  @override
  Future<AddressCheck> validate(String ticker, String address) async {
    try {
      return await _ports.validate(ticker, address);
    } on Object catch (error) {
      debugPrint('Address check failed: ${error.runtimeType}');
      return AddressCheck.unverified;
    }
  }

  @override
  Future<SendSource> source(String ticker) async {
    final AddressSnapshot snapshot;
    try {
      snapshot = await _ports.addresses(ticker);
    } on Object catch (error) {
      throw SendException(sendFailureOf(error));
    }
    // HD change goes back to the address it came from (kdf
    // utxo_common.rs ~740-760), so Internal addresses can hold funds too.
    final source = SendRules.pickSource(snapshot.keys);
    if (source == null) throw const SendException(SendFailure.unknown);
    return SendSource(
      source: source,
      total: snapshot.keys.fold(
        Decimal.zero,
        (sum, key) => sum + key.spendable,
      ),
      ownAddresses: [for (final key in snapshot.keys) key.address],
      isHd: snapshot.isHd,
    );
  }

  @override
  Future<SendPreview> preview(SendRequest request, SendSource source) async {
    if (busy) throw const SendException(SendFailure.busy);
    _previewing = true;
    try {
      final path = source.source.derivationPath;
      final signed = await _ports.preview(
        WithdrawParameters(
          asset: request.ticker,
          toAddress: request.toAddress,
          amount: request.amount,
          isMax: request.isMax ? true : null,
          // HD needs `from` or KDF answers FromAddressNotFound; iguana
          // must not send it (kdf utxo_common.rs:3555-3578). KDF accepts
          // a derivation path (coins/hd_wallet/mod.rs:537-546), which also
          // covers change (Internal) addresses.
          from: source.isHd && path != null
              ? WithdrawalSource.hdDerivationPath(path)
              : null,
        ),
      );
      final fee = signed.fee.totalFee;
      final changes = signed.balanceChanges;
      final preview = SendPreview(
        ticker: request.ticker,
        toAddress: request.toAddress,
        fromAddress: signed.from.isEmpty
            ? source.source.address
            : signed.from.first,
        amount: SendRules.previewAmount(
          requested: request.amount,
          spentByMe: changes.spentByMe,
          receivedByMe: changes.receivedByMe,
          fee: fee,
        ),
        fee: fee,
        signed: signed,
      );
      _held = preview;
      return preview;
    } on Object catch (error) {
      throw SendException(
        sendFailureOf(
          error,
          dynamicFee: SendRules.hasDynamicFee(request.ticker),
        ),
      );
    } finally {
      _previewing = false;
    }
  }

  @override
  Future<String> broadcast(SendPreview preview) async {
    final signed = preview.signed;
    if (_broadcasting ||
        !identical(preview, _held) ||
        signed is! WithdrawalPreview) {
      throw const SendException(SendFailure.busy);
    }
    _broadcasting = true;
    try {
      final txid = await _ports.broadcast(signed, preview.ticker);
      (_sentTo[preview.ticker] ??= []).add(preview.toAddress);
      return txid;
    } on Object catch (error) {
      throw SendException(sendFailureOf(error));
    } finally {
      // Never re-sent: a retry needs a fresh preview (spec §3.5).
      _broadcasting = false;
      _held = null;
    }
  }

  @override
  void release(SendPreview preview) {
    if (!_broadcasting && identical(preview, _held)) _held = null;
  }
}
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/data/repositories/sdk_send_repository_test.dart
```

Expected: `+27: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```

Expected: the formatter changes 0 files; `No issues found!`; `+433: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/data/repositories/send_repository.dart \
  test/data/repositories/sdk_send_repository_test.dart \
  test/support/fake_send_repository.dart
git commit -m "feat(send): SendRepository with signed preview, broadcast and in-flight guard" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 3: `HistoryRepository` and `TxView`; `AssetsRepository.refreshBalance`

History for asset detail and the look-alike check, and a forced balance refresh for pull-to-refresh and after a send. SDK facts:
- `sdk.transactions.watchTransactionHistoryMerged(asset)` emits stored, then fetched, then live history as whole reconciled lists (`komodo_defi_sdk/lib/src/transaction_history/transaction_history_manager.dart:508-541`); HD covers account 0 across all addresses, iguana its single address. `syncTransactionHistory` (`:573`), `getTransactionHistory(asset, pagination: PagePagination(...))` (`:277`).
- `Transaction` (`komodo_defi_types/lib/src/transactions/transaction.dart:8-57`): `internalId`, `txHash`, `balanceChanges{netChange, receivedByMe, spentByMe}`, `timestamp`, `confirmations`, `blockHeight`, `from`, `to`, `fee?.totalFee`.
- `required_confirmations` comes from the coin config through `asset.protocol.config` (`komodo_defi_types/lib/src/coin_classes/protocol_class.dart:102`): DGB 7, BTC 1, LTC 2.
- `sdk.balances.getBalance(id, forceRefresh: true)` re-reads the pubkeys from KDF (`komodo_defi_sdk/lib/src/balances/balance_manager.dart:550-587`).

**Files:**
- Create: `app/lib/data/repositories/history_repository.dart`
- Create: `app/test/support/fake_history_repository.dart`
- Modify: `app/lib/data/repositories/assets_repository.dart`
- Modify: `app/test/support/fake_assets_repository.dart`
- Test (create): `app/test/data/repositories/sdk_history_repository_test.dart`
- Test (modify): `app/test/data/repositories/sdk_assets_repository_test.dart`

**Interfaces:**
- Consumes: `AddressSafety.recentLimit` (Task 1); `findListedAsset`; `BalanceView` (`lib/data/repositories/assets_repository.dart`).
- Produces (`lib/data/repositories/history_repository.dart`):
  - `enum TxDirection { received, sent, toSelf }`
  - `class TxView extends Equatable { const TxView({required String id, required TxDirection direction, required Decimal amount, required DateTime timestamp, required int confirmations, required int blockHeight, required List<String> counterparties, String? txid, Decimal? fee}); bool get pending; }` — `amount` is the signed net change; `stringify` off.
  - `TxView txViewOf(Transaction tx, Set<String> own)` — received when `netChange > 0`; to self when `spentByMe > 0 && receivedByMe > 0 && netChange == -fee`; otherwise sent. Counterparties exclude `own`.
  - `abstract interface class HistoryRepository { Stream<List<TxView>> watch(String ticker); Future<void> sync(String ticker); Future<List<String>> recentCounterparties(String ticker); int requiredConfirmations(String ticker); }` — `watch` lists pending first, then newest first.
  - `class HistorySdkPorts { const HistorySdkPorts({required watch, required sync, required latest, required ownAddresses, required requiredConfirmations}); factory HistorySdkPorts.of(KomodoDefiSdk sdk); }`
  - `class SdkHistoryRepository implements HistoryRepository { SdkHistoryRepository(KomodoDefiSdk sdk); SdkHistoryRepository.withPorts(HistorySdkPorts ports); }`
- Changes `AssetsRepository`: adds `Future<BalanceView> refreshBalance(String ticker)` (throws on failure); `AssetsSdkPorts` gains `required Future<BalanceView> Function(String ticker) refreshBalance`.
- Test support: `FakeHistoryRepository` (`emit`, `fail`, `watching`, `recent`, `synced`, `syncError`; `requiredConfirmations` is 7 for DGB, 2 otherwise); `FakeAssetsRepository` gains `refreshed` (ticker → `BalanceView`) and `refreshCalls`.

- [ ] **Step 1: Write the failing tests**

Create `app/test/data/repositories/sdk_history_repository_test.dart`:

```dart
import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

import '../../support/capture_debug_print.dart';

// Dummies, not real addresses.
const _mine = 'DMine0000000000000000000000000000';
const _change = 'DMine0000000000000000000000000001';
const _them = 'DThem0000000000000000000000000000';

Decimal _d(String s) => Decimal.parse(s);

final _assetId = AssetId(
  id: 'DGB',
  name: 'DigiByte',
  symbol: AssetSymbol(assetConfigId: 'DGB'),
  chainId: AssetChainId(chainId: 0),
  derivationPath: null,
  subClass: CoinSubClass.utxo,
);

Transaction _tx({
  required String id,
  required String net,
  String spent = '0',
  String received = '0',
  String? fee,
  int confirmations = 3,
  DateTime? at,
  List<String> from = const [_them],
  List<String> to = const [_mine],
}) => Transaction(
  id: id,
  internalId: 'internal-$id',
  assetId: _assetId,
  balanceChanges: BalanceChanges(
    netChange: _d(net),
    receivedByMe: _d(received),
    spentByMe: _d(spent),
    totalAmount: _d(spent),
  ),
  timestamp: at ?? DateTime.utc(2026, 10, 2),
  confirmations: confirmations,
  blockHeight: confirmations == 0 ? 0 : 100,
  from: from,
  to: to,
  txHash: 'hash-$id',
  fee: fee == null ? null : FeeInfo.utxoFixed(coin: 'DGB', amount: _d(fee)),
);

void main() {
  const own = {_mine, _change};

  group('txViewOf', () {
    test('incoming: net change above zero; senders are counterparties', () {
      final view = txViewOf(
        _tx(id: '1', net: '5', received: '5', from: [_them], to: [_mine]),
        own,
      );
      expect(view.direction, TxDirection.received);
      expect(view.amount, _d('5'));
      expect(view.counterparties, [_them]);
      expect(view.txid, 'hash-1');
      expect(view.id, 'internal-1');
    });

    test('outgoing: recipients minus my change address', () {
      final view = txViewOf(
        _tx(
          id: '2',
          net: '-1.0226',
          spent: '10',
          received: '8.9774',
          fee: '0.0226',
          from: [_mine],
          to: [_them, _change],
        ),
        own,
      );
      expect(view.direction, TxDirection.sent);
      expect(view.amount, _d('-1.0226'));
      expect(view.fee, _d('0.0226'));
      expect(view.counterparties, [_them]);
    });

    test('to self: spent and received, lost exactly the fee', () {
      final view = txViewOf(
        _tx(
          id: '3',
          net: '-0.0226',
          spent: '10',
          received: '9.9774',
          fee: '0.0226',
          from: [_mine],
          to: [_change],
        ),
        own,
      );
      expect(view.direction, TxDirection.toSelf);
      expect(view.counterparties, isEmpty);
    });

    test('pending: zero confirmations', () {
      final view = txViewOf(_tx(id: '4', net: '1', confirmations: 0), own);
      expect(view.pending, isTrue);
      expect(txViewOf(_tx(id: '5', net: '1'), own).pending, isFalse);
    });

    test('a view never prints its addresses', () {
      final view = txViewOf(_tx(id: '6', net: '1'), own);
      expect(view.toString(), isNot(contains(_them)));
    });
  });

  late StreamController<List<Transaction>> feed;
  late List<Transaction> latest;
  late List<String> synced;
  late Exception? ownError;

  setUp(() {
    feed = StreamController<List<Transaction>>.broadcast();
    latest = [];
    synced = [];
    ownError = null;
  });
  tearDown(() => feed.close());

  SdkHistoryRepository build({int Function(String)? confirmations}) =>
      SdkHistoryRepository.withPorts(
        HistorySdkPorts(
          watch: (ticker) => feed.stream,
          sync: (ticker) async => synced.add(ticker),
          latest: (ticker, count) async {
            expect(count, 50);
            return latest;
          },
          ownAddresses: (ticker) async {
            final error = ownError;
            if (error != null) throw error;
            return own;
          },
          requiredConfirmations: confirmations ?? (ticker) => 7,
        ),
      );

  test('watch maps every list; pending first, then newest first', () async {
    final lists = <List<TxView>>[];
    final sub = build().watch('DGB').listen(lists.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    feed.add([
      _tx(id: 'old', net: '1', at: DateTime.utc(2026)),
      _tx(id: 'new', net: '1', at: DateTime.utc(2026, 9)),
      _tx(id: 'pending', net: '1', confirmations: 0, at: DateTime.utc(2025)),
    ]);
    await pumpEventQueue();
    expect(lists.single.map((v) => v.id), [
      'internal-pending',
      'internal-new',
      'internal-old',
    ]);
  });

  test('watch passes stream errors through', () async {
    final errors = <Object>[];
    final sub = build().watch('DGB').listen((_) {}, onError: errors.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    feed.addError(StateError('activation failed'));
    await pumpEventQueue();
    expect(errors.single, isA<StateError>());
  });

  test('an own-address lookup failure still shows history', () async {
    final logs = captureDebugPrint();
    ownError = Exception('pubkeys');
    final lists = <List<TxView>>[];
    final sub = build().watch('DGB').listen(lists.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    feed.add([_tx(id: '1', net: '1')]);
    await pumpEventQueue();
    expect(lists.single, hasLength(1));
    expect(logs.single, 'Own address lookup failed: _Exception');
  });

  test('recent counterparties: the latest 50, distinct, never mine', () async {
    latest = [
      _tx(id: '1', net: '1', from: [_them], to: [_mine]),
      _tx(
        id: '2',
        net: '-1.1',
        spent: '2',
        received: '0.9',
        fee: '0.1',
        from: [_mine],
        to: [_them, _change],
      ),
    ];
    expect(await build().recentCounterparties('DGB'), [_them]);
  });

  test('recent counterparties are empty when history fails', () async {
    final logs = captureDebugPrint();
    final repo = SdkHistoryRepository.withPorts(
      HistorySdkPorts(
        watch: (_) => const Stream.empty(),
        sync: (_) async {},
        latest: (_, _) async => throw StateError('rpc'),
        ownAddresses: (_) async => own,
        requiredConfirmations: (_) => 7,
      ),
    );
    expect(await repo.recentCounterparties('DGB'), isEmpty);
    expect(logs.single, 'Recent addresses failed: StateError');
  });

  test('sync and required confirmations go to the SDK', () async {
    final repo = build(confirmations: (t) => t == 'DGB' ? 7 : 2);
    await repo.sync('DGB');
    expect(synced, ['DGB']);
    expect(repo.requiredConfirmations('DGB'), 7);
    expect(repo.requiredConfirmations('LTC'), 2);
  });

  test('a failing confirmations lookup falls back to 1', () {
    final repo = build(confirmations: (_) => throw StateError('no asset'));
    expect(repo.requiredConfirmations('DGB'), 1);
  });
}
```

Create `app/test/support/fake_history_repository.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/repositories/history_repository.dart';

/// Hand-written [HistoryRepository]: push lists or errors per ticker.
class FakeHistoryRepository implements HistoryRepository {
  final _feeds = <String, StreamController<List<TxView>>>{};

  /// What [recentCounterparties] returns.
  List<String> recent = const [];

  /// Every [sync] call, in order.
  final synced = <String>[];

  /// When set, [sync] throws it.
  Exception? syncError;

  StreamController<List<TxView>> _feed(String ticker) =>
      _feeds.putIfAbsent(ticker, StreamController<List<TxView>>.broadcast);

  void emit(String ticker, List<TxView> list) => _feed(ticker).add(list);

  void fail(String ticker, Object error) => _feed(ticker).addError(error);

  /// Whether a page currently watches [ticker].
  bool watching(String ticker) => _feeds[ticker]?.hasListener ?? false;

  @override
  Stream<List<TxView>> watch(String ticker) => _feed(ticker).stream;

  @override
  Future<void> sync(String ticker) async {
    synced.add(ticker);
    final error = syncError;
    if (error != null) throw error;
  }

  @override
  Future<List<String>> recentCounterparties(String ticker) async => recent;

  @override
  int requiredConfirmations(String ticker) => ticker == 'DGB' ? 7 : 2;
}
```

Edit `app/test/data/repositories/sdk_assets_repository_test.dart` (3 replacements, top to bottom):

1. Replace:

```dart
  late List<StreamController<BalanceView>> feeds;
  late FakeTimers timers;

  setUp(() {
    activations = [];
    failing = {};
```

   with:

```dart
  late List<StreamController<BalanceView>> feeds;
  late FakeTimers timers;
  late List<String> refreshed;

  setUp(() {
    refreshed = [];
    activations = [];
    failing = {};
```

2. Replace:

```dart
        feeds.add(feed);
        return feed.stream;
      },
    ),
```

   with:

```dart
        feeds.add(feed);
        return feed.stream;
      },
      refreshBalance: (ticker) async {
        refreshed.add(ticker);
        return BalanceView(
          total: Decimal.parse('7'),
          spendable: Decimal.parse('6'),
        );
      },
    ),
```

3. Replace:

```dart
    );
  });
}
```

   with:

```dart
    );
  });

  test('refreshBalance asks the SDK for a fresh balance', () async {
    final balance = await build().refreshBalance('DGB');
    expect(refreshed, ['DGB']);
    expect(balance.total, Decimal.parse('7'));
    expect(balance.spendable, Decimal.parse('6'));
  });
}
```


In `app/test/support/fake_assets_repository.dart`, replace:

```dart
  }

  @override
  Stream<BalanceView> watchBalance(String ticker) => _balances
```

with:

```dart
  }

  /// What [refreshBalance] returns per ticker; tickers without one fail.
  final refreshed = <String, BalanceView>{};

  /// Every [refreshBalance] call, in order.
  final refreshCalls = <String>[];

  @override
  Future<BalanceView> refreshBalance(String ticker) async {
    refreshCalls.add(ticker);
    final balance = refreshed[ticker];
    if (balance == null) throw StateError('no balance');
    return balance;
  }

  @override
  Stream<BalanceView> watchBalance(String ticker) => _balances
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/data/repositories/sdk_history_repository_test.dart \
  test/data/repositories/sdk_assets_repository_test.dart
```

Expected: FAIL. `history_repository.dart` is missing (`No such file or directory`), and `sdk_assets_repository_test.dart` fails with `No named parameter with the name 'refreshBalance'` / `The method 'refreshBalance' isn't defined for the type 'SdkAssetsRepository'`.

- [ ] **Step 3: Implement**

Create `app/lib/data/repositories/history_repository.dart`:

```dart
import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/sdk/asset_lookup.dart';
import 'package:digibyte_dex/domain/address_safety.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

enum TxDirection { received, sent, toSelf }

/// One history row (spec §4). `stringify` is off: addresses and amounts
/// are never logged.
class TxView extends Equatable {
  const TxView({
    required this.id,
    required this.direction,
    required this.amount,
    required this.timestamp,
    required this.confirmations,
    required this.blockHeight,
    required this.counterparties,
    this.txid,
    this.fee,
  });

  /// Stable row id (KDF `internal_id`).
  final String id;
  final String? txid;
  final TxDirection direction;

  /// The signed net change of the wallet balance.
  final Decimal amount;
  final Decimal? fee;
  final DateTime timestamp;
  final int confirmations;
  final int blockHeight;

  /// The other side's addresses: senders for a receive, recipients for a
  /// send. The wallet's own addresses are left out.
  final List<String> counterparties;

  bool get pending => confirmations == 0;

  @override
  List<Object?> get props => [
    id,
    txid,
    direction,
    amount,
    fee,
    timestamp,
    confirmations,
    blockHeight,
    counterparties,
  ];

  @override
  bool? get stringify => false;
}

/// Maps an SDK [Transaction] to a [TxView] (spec §4): received when the
/// net change is positive; to self when the wallet both spent and received
/// and lost exactly the fee; otherwise sent.
TxView txViewOf(Transaction tx, Set<String> own) {
  final changes = tx.balanceChanges;
  final fee = tx.fee?.totalFee;
  final TxDirection direction;
  if (changes.netChange > Decimal.zero) {
    direction = TxDirection.received;
  } else if (changes.spentByMe > Decimal.zero &&
      changes.receivedByMe > Decimal.zero &&
      fee != null &&
      changes.netChange == -fee) {
    direction = TxDirection.toSelf;
  } else {
    direction = TxDirection.sent;
  }
  final side = direction == TxDirection.received ? tx.from : tx.to;
  return TxView(
    id: tx.internalId.isEmpty ? tx.id : tx.internalId,
    txid: tx.txHash,
    direction: direction,
    amount: changes.netChange,
    fee: fee,
    timestamp: tx.timestamp,
    confirmations: tx.confirmations,
    blockHeight: tx.blockHeight,
    counterparties: [
      for (final address in side.toSet())
        if (!own.contains(address)) address,
    ],
  );
}

/// Pending first, then newest first.
int _newestFirst(TxView a, TxView b) {
  if (a.pending != b.pending) return a.pending ? -1 : 1;
  return b.timestamp.compareTo(a.timestamp);
}

/// One asset's transaction history.
abstract interface class HistoryRepository {
  /// Stored history, then fetched history, then live updates, as whole
  /// lists, pending first then newest first. Errors are delivered as
  /// stream errors.
  Stream<List<TxView>> watch(String ticker);

  /// Fetches anything newer than the stored history.
  Future<void> sync(String ticker);

  /// The counterparties of the latest [AddressSafety.recentLimit] entries,
  /// for the look-alike check. Empty when history cannot be read.
  Future<List<String>> recentCounterparties(String ticker);

  /// Confirmations after which a transaction counts as confirmed.
  int requiredConfirmations(String ticker);
}

/// The SDK calls [SdkHistoryRepository] needs. A seam for tests, because
/// the SDK's `TransactionHistoryManager` and `PubkeyManager` are not
/// exported.
class HistorySdkPorts {
  const HistorySdkPorts({
    required this.watch,
    required this.sync,
    required this.latest,
    required this.ownAddresses,
    required this.requiredConfirmations,
  });

  factory HistorySdkPorts.of(KomodoDefiSdk sdk) {
    Asset asset(String ticker) => findListedAsset(sdk, ticker);
    return HistorySdkPorts(
      // transaction_history_manager.dart:508-541: storage, then the API,
      // then live transactions, reconciled into one ordered list.
      watch: (ticker) =>
          sdk.transactions.watchTransactionHistoryMerged(asset(ticker)),
      sync: (ticker) => sdk.transactions.syncTransactionHistory(asset(ticker)),
      latest: (ticker, count) async =>
          (await sdk.transactions.getTransactionHistory(
            asset(ticker),
            pagination: PagePagination(pageNumber: 1, itemsPerPage: count),
          )).transactions,
      ownAddresses: (ticker) async => {
        for (final key in (await sdk.pubkeys.getPubkeys(asset(ticker))).keys)
          key.address,
      },
      // The coin config's `required_confirmations` (DGB 7, BTC 1, LTC 2).
      requiredConfirmations: (ticker) =>
          asset(
            ticker,
          ).protocol.config.valueOrNull<int>('required_confirmations') ??
          1,
    );
  }

  final Stream<List<Transaction>> Function(String ticker) watch;
  final Future<void> Function(String ticker) sync;
  final Future<List<Transaction>> Function(String ticker, int count) latest;
  final Future<Set<String>> Function(String ticker) ownAddresses;
  final int Function(String ticker) requiredConfirmations;
}

class SdkHistoryRepository implements HistoryRepository {
  SdkHistoryRepository(KomodoDefiSdk sdk)
    : this.withPorts(HistorySdkPorts.of(sdk));

  @visibleForTesting
  SdkHistoryRepository.withPorts(this._ports);

  final HistorySdkPorts _ports;

  Future<Set<String>> _own(String ticker) async {
    try {
      return await _ports.ownAddresses(ticker);
    } on Object catch (error) {
      debugPrint('Own address lookup failed: ${error.runtimeType}');
      return const {};
    }
  }

  @override
  Stream<List<TxView>> watch(String ticker) async* {
    final own = await _own(ticker);
    yield* _ports
        .watch(ticker)
        .map(
          (txs) =>
              [for (final tx in txs) txViewOf(tx, own)]..sort(_newestFirst),
        );
  }

  @override
  Future<void> sync(String ticker) => _ports.sync(ticker);

  @override
  Future<List<String>> recentCounterparties(String ticker) async {
    try {
      final own = await _own(ticker);
      final txs = await _ports.latest(ticker, AddressSafety.recentLimit);
      return {
        for (final tx in txs) ...txViewOf(tx, own).counterparties,
      }.toList();
    } on Object catch (error) {
      debugPrint('Recent addresses failed: ${error.runtimeType}');
      return const [];
    }
  }

  @override
  int requiredConfirmations(String ticker) {
    try {
      return _ports.requiredConfirmations(ticker);
    } on Object {
      return 1;
    }
  }
}
```

Edit `app/lib/data/repositories/assets_repository.dart` (5 replacements, top to bottom):

1. Replace:

```dart
  /// screen, and the stream recovers by itself when the source fails.
  Stream<BalanceView> watchBalance(String ticker);
}

```

   with:

```dart
  /// screen, and the stream recovers by itself when the source fails.
  Stream<BalanceView> watchBalance(String ticker);

  /// Fetches the balance from KDF now, bypassing the SDK's pubkey cache,
  /// which has no expiry (after a send, pull-to-refresh). Throws on
  /// failure.
  Future<BalanceView> refreshBalance(String ticker);
}

```

2. Replace:

```dart
    required this.activate,
    required this.watchBalance,
  });

```

   with:

```dart
    required this.activate,
    required this.watchBalance,
    required this.refreshBalance,
  });

```

3. Replace:

```dart
          .watchBalance(asset(ticker).id, activateIfNeeded: false)
          .map((b) => BalanceView(total: b.total, spendable: b.spendable)),
    );
  }
```

   with:

```dart
          .watchBalance(asset(ticker).id, activateIfNeeded: false)
          .map((b) => BalanceView(total: b.total, spendable: b.spendable)),
      // forceRefresh re-reads the pubkeys from KDF
      // (balance_manager.dart:550-587).
      refreshBalance: (ticker) async {
        final b = await sdk.balances.getBalance(
          asset(ticker).id,
          forceRefresh: true,
        );
        return BalanceView(total: b.total, spendable: b.spendable);
      },
    );
  }
```

4. Replace:

```dart
  final Future<bool> Function(String ticker) activate;
  final Stream<BalanceView> Function(String ticker) watchBalance;
}

```

   with:

```dart
  final Future<bool> Function(String ticker) activate;
  final Stream<BalanceView> Function(String ticker) watchBalance;
  final Future<BalanceView> Function(String ticker) refreshBalance;
}

```

5. Replace:

```dart
  }

  /// Errors never reach the listener, so the last balance stays on
  /// screen. On an error or the end of the SDK stream the repository
```

   with:

```dart
  }

  @override
  Future<BalanceView> refreshBalance(String ticker) =>
      _ports.refreshBalance(ticker);

  /// Errors never reach the listener, so the last balance stays on
  /// screen. On an error or the end of the SDK stream the repository
```


- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/data/repositories/sdk_history_repository_test.dart \
  test/data/repositories/sdk_assets_repository_test.dart
```

Expected: `+25: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```

Expected: the formatter changes 0 files; `No issues found!`; `+446: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/data/repositories/assets_repository.dart \
  lib/data/repositories/history_repository.dart \
  test/data/repositories/sdk_assets_repository_test.dart \
  test/data/repositories/sdk_history_repository_test.dart \
  test/support/fake_assets_repository.dart \
  test/support/fake_history_repository.dart
git commit -m "feat(history): HistoryRepository with TxView mapping; forced balance refresh" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 4: Asset detail: balance, history with paging, tx detail, explorer links; Home row opens it

`/home/asset/:ticker` (spec §4). The Home row tap now opens asset detail, and Receive moves to a button there (Send is added in Task 5). The tx detail is a bottom sheet; the explorer URLs are spec D4.

**Files:**
- Create: `app/lib/config/explorers.dart`
- Create: `app/lib/platform/url_opener.dart`
- Create: `app/test/support/fake_url_opener.dart`
- Create: `app/lib/features/asset/bloc/asset_history_cubit.dart`
- Create: `app/lib/features/asset/view/asset_detail_page.dart`
- Create: `app/lib/features/asset/view/tx_detail_sheet.dart`
- Create: `app/lib/l10n/history_messages.dart`
- Create: `app/test/support/tx_views.dart`
- Modify: `app/lib/app/routes.dart`
- Modify: `app/lib/app/router.dart`
- Modify: `app/lib/features/wallet/view/home_page.dart`
- Modify: `app/lib/app/app_scope.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/test/support/test_app.dart`
- Modify: `app/lib/l10n/arb/app_en.arb`
- Test (create): `app/test/config/explorers_test.dart`
- Test (create): `app/test/features/asset/asset_history_cubit_test.dart`
- Test (create): `app/test/features/asset/asset_detail_page_test.dart`
- Test (modify): `app/test/features/wallet/home_page_test.dart`
- Test (modify): `app/test/app/app_scope_test.dart`
- Test (modify): `app/test/app/router_test.dart`

**Interfaces:**
- Consumes: Task 3 `HistoryRepository`, `TxView`, `TxDirection`, `AssetsRepository.refreshBalance`; `ClipboardGuard.copy` (M1-C); `Routes.receive`.
- Produces:
  - `abstract final class Explorers { static Uri? tx(String ticker, String txid); }` — DGB `https://digiexplorer.info/tx/<txid>`, BTC `https://mempool.space/tx/<txid>`, LTC `https://litecoinspace.org/tx/<txid>`; null for an unknown ticker or a txid that is not 64 hex characters.
  - `class UrlOpener { const UrlOpener(); Future<bool> open(Uri url); }` (url_launcher, external application).
  - `enum HistoryStatus { loading, ready, failed }`; `class AssetHistoryState { String? name; BalanceView? balance; HistoryStatus status; List<TxView> transactions; int visible; List<TxView> get shown; bool get hasMore; }`
  - `class AssetHistoryCubit extends Cubit<AssetHistoryState> { AssetHistoryCubit({required String ticker, required AssetsRepository assets, required HistoryRepository history}); static const pageSize = 25; int get requiredConfirmations; Future<void> start(); void retry(); void loadMore(); Future<void> refresh(); }`
  - `class AssetDetailPage extends StatelessWidget { const AssetDetailPage({required String ticker}); }`
  - `Future<void> showTxDetail(BuildContext context, {required String ticker, required TxView tx, required int required})`; `Future<void> openExplorer(BuildContext context, Uri url)` (SnackBar when nothing opens it).
  - `extension TxViewText on TxView { String directionLabel(AppLocalizations); String status(AppLocalizations, int required); String get signedAmount; String localTime(String locale); }` (`lib/l10n/history_messages.dart`)
  - `Routes.asset(String ticker)` → `/home/asset/<ticker>`.
  - `AppServices` gains `required HistoryRepository history` and `required UrlOpener urls`, both provided by `AppScope`.
  - Widget ids: `asset.balance`, `asset.spendable`, `asset.receive`, `asset.refresh`, `asset.list`, `asset.retry`, `asset.empty`, `asset.tx.<index>`; sheet: `tx.direction`, `tx.fee`, `tx.status`, `tx.confirmations`, `tx.block`, `tx.date`, `tx.counterparties`, `tx.txid`, `tx.copy`, `tx.explorer`.
- Test support: `FakeUrlOpener` (`opened`, `result`); `test/support/tx_views.dart` with `TxView txView(int n, {...})` and `String fakeTxid(int n)`; `TestApp.history`, `TestApp.urls`.

- [ ] **Step 1: Write the failing tests**

Create `app/test/config/explorers_test.dart`:

```dart
import 'package:digibyte_dex/config/explorers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final txid = 'a' * 64;

  test('DGB, BTC and LTC explorers (spec D4)', () {
    expect(
      Explorers.tx('DGB', txid).toString(),
      'https://digiexplorer.info/tx/$txid',
    );
    expect(
      Explorers.tx('BTC', txid).toString(),
      'https://mempool.space/tx/$txid',
    );
    expect(
      Explorers.tx('LTC', txid).toString(),
      'https://litecoinspace.org/tx/$txid',
    );
  });

  test('unknown tickers and non-hex txids get no link', () {
    expect(Explorers.tx('ETH', txid), isNull);
    expect(Explorers.tx('DGB', 'txid-1'), isNull);
    expect(Explorers.tx('DGB', '${'a' * 63}/'), isNull);
  });
}
```

Create `app/test/support/fake_url_opener.dart`:

```dart
import 'package:digibyte_dex/platform/url_opener.dart';

class FakeUrlOpener implements UrlOpener {
  final opened = <Uri>[];

  /// What [open] answers.
  bool result = true;

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return result;
  }
}
```

Create `app/test/features/asset/asset_history_cubit_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/features/asset/bloc/asset_history_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/capture_debug_print.dart';
import '../../support/fake_assets_repository.dart';
import '../../support/fake_history_repository.dart';
import '../../support/tx_views.dart';

void main() {
  late FakeAssetsRepository assets;
  late FakeHistoryRepository history;

  setUp(() {
    assets = FakeAssetsRepository();
    history = FakeHistoryRepository();
  });

  Future<AssetHistoryCubit> start() async {
    final cubit = AssetHistoryCubit(
      ticker: 'DGB',
      assets: assets,
      history: history,
    );
    addTearDown(cubit.close);
    await cubit.start();
    await pumpEventQueue();
    return cubit;
  }

  BalanceView balance(String total, [String? spendable]) => BalanceView(
    total: Decimal.parse(total),
    spendable: Decimal.parse(spendable ?? total),
  );

  test('loading, then the name, then rows', () async {
    final cubit = await start();
    expect(cubit.state.status, HistoryStatus.loading);
    expect(cubit.state.name, 'DigiByte');
    history.emit('DGB', [txView(1), txView(2)]);
    await pumpEventQueue();
    expect(cubit.state.status, HistoryStatus.ready);
    expect(cubit.state.shown, hasLength(2));
  });

  test('empty history is ready with no rows', () async {
    final cubit = await start();
    history.emit('DGB', const []);
    await pumpEventQueue();
    expect(cubit.state.status, HistoryStatus.ready);
    expect(cubit.state.transactions, isEmpty);
  });

  test('25 rows per page; load more shows the next 25', () async {
    final cubit = await start();
    history.emit('DGB', [for (var i = 0; i < 60; i++) txView(i)]);
    await pumpEventQueue();
    expect(cubit.state.shown, hasLength(25));
    expect(cubit.state.hasMore, isTrue);
    cubit.loadMore();
    expect(cubit.state.shown, hasLength(50));
    cubit.loadMore();
    expect(cubit.state.shown, hasLength(60));
    expect(cubit.state.hasMore, isFalse);
    cubit.loadMore();
    expect(cubit.state.visible, 75);
  });

  test('an error keeps the balance; retry watches again', () async {
    final logs = captureDebugPrint();
    final cubit = await start();
    assets.emitBalance('DGB', balance('5'));
    await pumpEventQueue();
    history.fail('DGB', StateError('activation'));
    await pumpEventQueue();
    expect(cubit.state.status, HistoryStatus.failed);
    expect(cubit.state.balance, balance('5'));
    expect(logs, ['History failed: StateError']);
    cubit.retry();
    expect(cubit.state.status, HistoryStatus.loading);
    history.emit('DGB', [txView(1)]);
    await pumpEventQueue();
    expect(cubit.state.status, HistoryStatus.ready);
  });

  test('pull-to-refresh syncs history and forces a balance refresh', () async {
    final cubit = await start();
    assets.refreshed['DGB'] = balance('9', '8');
    await cubit.refresh();
    expect(history.synced, ['DGB']);
    expect(assets.refreshCalls, ['DGB']);
    expect(cubit.state.balance, balance('9', '8'));
  });

  test('a failed refresh keeps what is shown and logs types only', () async {
    final logs = captureDebugPrint();
    final cubit = await start();
    assets.emitBalance('DGB', balance('5'));
    await pumpEventQueue();
    history.syncError = Exception('electrum');
    await cubit.refresh();
    expect(cubit.state.balance, balance('5'));
    expect(
      logs,
      containsAll(<String>[
        'History sync failed: _Exception',
        'Balance refresh failed: StateError',
      ]),
    );
  });

  test('closing stops watching', () async {
    final cubit = await start();
    expect(history.watching('DGB'), isTrue);
    await cubit.close();
    expect(history.watching('DGB'), isFalse);
  });

  test('required confirmations come from the history repository', () async {
    final cubit = await start();
    expect(cubit.requiredConfirmations, 7);
  });
}
```

Create `app/test/features/asset/asset_detail_page_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/features/asset/view/asset_detail_page.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/url_opener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_assets_repository.dart';
import '../../support/fake_history_repository.dart';
import '../../support/fake_timers.dart';
import '../../support/fake_url_opener.dart';
import '../../support/pump_app.dart';
import '../../support/tx_views.dart';

void main() {
  late FakeAssetsRepository assets;
  late FakeHistoryRepository history;
  late FakeUrlOpener urls;
  late List<String> copied;
  late ClipboardGuard clipboard;

  setUp(() {
    assets = FakeAssetsRepository();
    history = FakeHistoryRepository();
    urls = FakeUrlOpener();
    copied = [];
    clipboard = ClipboardGuard(
      write: (text) async => copied.add(text),
      read: () async => null,
      timer: FakeTimers().create,
    );
  });
  tearDown(() => clipboard.dispose());

  Future<void> pump(WidgetTester t) async {
    await pumpPage(
      t,
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AssetsRepository>.value(value: assets),
          RepositoryProvider<HistoryRepository>.value(value: history),
          RepositoryProvider<UrlOpener>.value(value: urls),
          RepositoryProvider.value(value: clipboard),
        ],
        child: const AssetDetailPage(ticker: 'DGB'),
      ),
      stubs: [Routes.receive('DGB')],
    );
  }

  Future<void> show(WidgetTester t, List<TxView> list) async {
    history.emit('DGB', list);
    await t.pump();
    await t.pump();
  }

  testWidgets('name, balance and spendable when it differs', (t) async {
    await pump(t);
    expect(find.text('DigiByte (DGB)'), findsOneWidget);
    assets.emitBalance(
      'DGB',
      BalanceView(total: Decimal.parse('10'), spendable: Decimal.parse('7')),
    );
    await t.pump();
    await t.pump();
    expect(
      t.widget<Text>(find.byKey(const Key('asset.balance'))).data,
      '10 DGB',
    );
    expect(find.byKey(const Key('asset.spendable')), findsOneWidget);
  });

  testWidgets('loading, then the empty state', (t) async {
    await pump(t);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await show(t, const []);
    expect(find.text('No transactions yet'), findsOneWidget);
  });

  testWidgets('rows show direction, signed amount and status', (t) async {
    await pump(t);
    await show(t, [
      txView(1, confirmations: 0),
      txView(
        2,
        direction: TxDirection.sent,
        amount: '-1.0226',
        confirmations: 3,
      ),
      txView(3, direction: TxDirection.toSelf, amount: '-0.0226'),
    ]);
    final first = find.byKey(const Key('asset.tx.0'));
    expect(
      find.descendant(of: first, matching: find.textContaining('Pending')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('+1 DGB')),
      findsOneWidget,
    );
    final second = find.byKey(const Key('asset.tx.1'));
    expect(
      find.descendant(of: second, matching: find.text('Sent')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: second,
        matching: find.textContaining('Confirming 3/7'),
      ),
      findsOneWidget,
    );
    final third = find.byKey(const Key('asset.tx.2'));
    expect(
      find.descendant(of: third, matching: find.text('To yourself')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: third, matching: find.textContaining('Confirmed')),
      findsOneWidget,
    );
  });

  testWidgets('scrolling to the end loads the next page', (t) async {
    await pump(t);
    await show(t, [for (var i = 0; i < 30; i++) txView(i)]);
    expect(find.byKey(const Key('asset.tx.29')), findsNothing);
    await t.scrollUntilVisible(
      find.byKey(const Key('asset.tx.29')),
      300,
      scrollable: find.descendant(
        of: find.byKey(const Key('asset.list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.byKey(const Key('asset.tx.29')), findsOneWidget);
  });

  testWidgets('an error shows retry and keeps the balance', (t) async {
    await pump(t);
    assets.emitBalance(
      'DGB',
      BalanceView(total: Decimal.parse('3'), spendable: Decimal.parse('3')),
    );
    history.fail('DGB', StateError('activation'));
    await t.pump();
    await t.pump();
    expect(find.text("Couldn't load transactions."), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const Key('asset.balance'))).data,
      '3 DGB',
    );
    await tapKey(t, 'asset.retry');
    await show(t, [txView(1)]);
    expect(find.byKey(const Key('asset.tx.0')), findsOneWidget);
  });

  testWidgets('pull-to-refresh syncs history and refreshes the balance', (
    t,
  ) async {
    await pump(t);
    await show(t, [txView(1)]);
    await t.fling(
      find.byKey(const Key('asset.list')),
      const Offset(0, 400),
      1000,
    );
    await t.pumpAndSettle();
    expect(history.synced, ['DGB']);
    expect(assets.refreshCalls, ['DGB']);
  });

  testWidgets('Receive opens the receive page', (t) async {
    await pump(t);
    await tapKey(t, 'asset.receive');
    await t.pumpAndSettle();
    expect(find.text('route:${Routes.receive('DGB')}'), findsOneWidget);
  });

  testWidgets('a row opens its detail: copy txid and open the explorer', (
    t,
  ) async {
    await pump(t);
    await show(t, [
      txView(1, direction: TxDirection.sent, amount: '-1.0226', fee: '0.0226'),
    ]);
    await tapKey(t, 'asset.tx.0');
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('tx.txid'))).data, fakeTxid(1));
    expect(
      t.widget<Text>(find.byKey(const Key('tx.fee'))).data,
      '0.0226 DGB',
    );
    expect(
      t.widget<Text>(find.byKey(const Key('tx.counterparties'))).data,
      'DThem0000000000000000000000000000',
    );
    await tapKey(t, 'tx.copy');
    await t.pump();
    expect(copied, [fakeTxid(1)]);
    await tapKey(t, 'tx.explorer');
    await t.pump();
    expect(urls.opened, [
      Uri.parse('https://digiexplorer.info/tx/${fakeTxid(1)}'),
    ]);
  });

  testWidgets('an explorer that cannot open says so', (t) async {
    urls.result = false;
    await pump(t);
    await show(t, [txView(1)]);
    await tapKey(t, 'asset.tx.0');
    await t.pumpAndSettle();
    await tapKey(t, 'tx.explorer');
    await t.pump();
    expect(find.text("Couldn't open the explorer."), findsOneWidget);
  });
}
```

Create `app/test/support/tx_views.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';

/// A 64-hex dummy txid, unique per [n].
String fakeTxid(int n) => n.toRadixString(16).padLeft(64, 'a');

/// A history row for tests. Addresses are dummies.
TxView txView(
  int n, {
  TxDirection direction = TxDirection.received,
  String amount = '1',
  String? fee,
  int confirmations = 10,
  List<String> counterparties = const ['DThem0000000000000000000000000000'],
}) => TxView(
  id: 'tx-$n',
  txid: fakeTxid(n),
  direction: direction,
  amount: Decimal.parse(amount),
  fee: fee == null ? null : Decimal.parse(fee),
  timestamp: DateTime.utc(2026, 10, 2).subtract(Duration(minutes: n)),
  confirmations: confirmations,
  blockHeight: confirmations == 0 ? 0 : 1000 - n,
  counterparties: counterparties,
);
```

Edit `app/test/features/wallet/home_page_test.dart` (2 replacements, top to bottom):

1. Replace:

```dart
        ),
      ),
      stubs: [Routes.receive('DGB')],
    );
  }
```

   with:

```dart
        ),
      ),
      stubs: [Routes.asset('DGB')],
    );
  }
```

2. Replace:

```dart
  });

  testWidgets('an active row opens its receive page', (t) async {
    await pump(t);
    await tapKey(t, 'home.row.DGB');
    await t.pumpAndSettle();
    expect(find.text('route:${Routes.receive('DGB')}'), findsOneWidget);
  });
}
```

   with:

```dart
  });

  testWidgets('an active row opens its asset page', (t) async {
    await pump(t);
    await tapKey(t, 'home.row.DGB');
    await t.pumpAndSettle();
    expect(find.text('route:${Routes.asset('DGB')}'), findsOneWidget);
  });
}
```


Edit `app/test/support/test_app.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'fake_assets_repository.dart';
import 'fake_biometric_store.dart';
import 'fake_receive_repository.dart';
import 'fake_seed_validator.dart';
import 'fake_text_sharer.dart';
import 'fake_timers.dart';
import 'fake_wallet_repository.dart';
import 'in_memory_key_value_store.dart';
```

   with:

```dart
import 'fake_assets_repository.dart';
import 'fake_biometric_store.dart';
import 'fake_history_repository.dart';
import 'fake_receive_repository.dart';
import 'fake_seed_validator.dart';
import 'fake_text_sharer.dart';
import 'fake_timers.dart';
import 'fake_url_opener.dart';
import 'fake_wallet_repository.dart';
import 'in_memory_key_value_store.dart';
```

2. Replace:

```dart
  final session = PendingBackupSession();
  final receive = FakeReceiveRepository();
  final clipboardWrites = <String>[];

```

   with:

```dart
  final session = PendingBackupSession();
  final receive = FakeReceiveRepository();
  final history = FakeHistoryRepository();
  final urls = FakeUrlOpener();
  final clipboardWrites = <String>[];

```

3. Replace:

```dart
    assets: assets,
    receive: receive,
    backups: backups,
    attempts: attempts,
```

   with:

```dart
    assets: assets,
    receive: receive,
    history: history,
    backups: backups,
    attempts: attempts,
```

4. Replace:

```dart
    clipboard: clipboard,
    sharer: sharer,
    session: session,
  );
```

   with:

```dart
    clipboard: clipboard,
    sharer: sharer,
    urls: urls,
    session: session,
  );
```


Edit `app/test/app/app_scope_test.dart` (6 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
```

   with:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
```

2. Replace:

```dart
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
```

   with:

```dart
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:digibyte_dex/platform/url_opener.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
```

3. Replace:

```dart
import '../support/fake_assets_repository.dart';
import '../support/fake_biometric_store.dart';
import '../support/fake_receive_repository.dart';
import '../support/fake_seed_validator.dart';
import '../support/fake_text_sharer.dart';
import '../support/fake_wallet_repository.dart';
import '../support/in_memory_key_value_store.dart';
```

   with:

```dart
import '../support/fake_assets_repository.dart';
import '../support/fake_biometric_store.dart';
import '../support/fake_history_repository.dart';
import '../support/fake_receive_repository.dart';
import '../support/fake_seed_validator.dart';
import '../support/fake_text_sharer.dart';
import '../support/fake_url_opener.dart';
import '../support/fake_wallet_repository.dart';
import '../support/in_memory_key_value_store.dart';
```

4. Replace:

```dart
      assets: FakeAssetsRepository(),
      receive: FakeReceiveRepository(),
      backups: BackupStatusStore(storage),
      attempts: PasswordAttempts(LockoutStore(storage)),
```

   with:

```dart
      assets: FakeAssetsRepository(),
      receive: FakeReceiveRepository(),
      history: FakeHistoryRepository(),
      backups: BackupStatusStore(storage),
      attempts: PasswordAttempts(LockoutStore(storage)),
```

5. Replace:

```dart
      clipboard: ClipboardGuard(write: (_) async {}, read: () async => null),
      sharer: FakeTextSharer(),
    );
  });
```

   with:

```dart
      clipboard: ClipboardGuard(write: (_) async {}, read: () async => null),
      sharer: FakeTextSharer(),
      urls: FakeUrlOpener(),
    );
  });
```

6. Replace:

```dart
    expect(probe.read<ClipboardGuard>(), same(services.clipboard));
    expect(probe.read<TextSharer>(), same(services.sharer));
    expect(probe.read<AuthCubit>(), same(cubits.auth));
    expect(probe.read<LockCubit>(), same(cubits.lock));
```

   with:

```dart
    expect(probe.read<ClipboardGuard>(), same(services.clipboard));
    expect(probe.read<TextSharer>(), same(services.sharer));
    expect(probe.read<HistoryRepository>(), same(services.history));
    expect(probe.read<UrlOpener>(), same(services.urls));
    expect(probe.read<AuthCubit>(), same(cubits.auth));
    expect(probe.read<LockCubit>(), same(cubits.lock));
```


Edit `app/test/app/router_test.dart` (2 replacements, top to bottom):

1. Replace:

```dart
      Routes.home,
      '/home/receive/DGB',
      '/nonexistent',
      '',
```

   with:

```dart
      Routes.home,
      '/home/receive/DGB',
      '/home/asset/DGB',
      '/nonexistent',
      '',
```

2. Replace:

```dart
  });

  test('receive paths are built from the ticker', () {
    expect(Routes.receive('DGB'), '/home/receive/DGB');
  });

```

   with:

```dart
  });

  test('receive and asset paths are built from the ticker', () {
    expect(Routes.receive('DGB'), '/home/receive/DGB');
    expect(Routes.asset('DGB'), '/home/asset/DGB');
  });

  test('asset pages need an unlocked session', () {
    expect(go(signedIn, Routes.asset('DGB')), isNull);
    expect(go(signedIn, Routes.asset('DGB'), locked), Routes.locked);
    expect(go(pending, Routes.asset('DGB')), Routes.backup);
    expect(go(returning, Routes.asset('DGB')), Routes.signIn);
  });

```


- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/config/explorers_test.dart \
  test/features/asset/asset_history_cubit_test.dart \
  test/features/asset/asset_detail_page_test.dart \
  test/features/wallet/home_page_test.dart \
  test/app/app_scope_test.dart \
  test/app/router_test.dart
```

Expected: FAIL. Missing files (`explorers.dart`, `asset_history_cubit.dart`, `asset_detail_page.dart`, `url_opener.dart`), `Member not found: 'Routes.asset'`, and `No named parameter with the name 'history'` in `AppServices`.

- [ ] **Step 3: Implement**

First add the dependency:

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter pub add 'url_launcher:^6.3.2'
grep -n '^  url_launcher:' pubspec.yaml
```
Expected: `url_launcher: ^6.3.2` under `dependencies`, after `share_plus`; the lock resolves `url_launcher` 6.3.3, `url_launcher_android` 6.3.30, `url_launcher_ios` 6.4.2, `url_launcher_macos` 3.2.6.

Create `app/lib/config/explorers.dart`:

```dart
/// Block explorers per listed asset (spec D4).
abstract final class Explorers {
  static const _tx = {
    'DGB': 'https://digiexplorer.info/tx/',
    'BTC': 'https://mempool.space/tx/',
    'LTC': 'https://litecoinspace.org/tx/',
  };

  /// The explorer page of [txid] on [ticker]'s chain, or null for an
  /// unknown ticker or a txid that is not hex.
  static Uri? tx(String ticker, String txid) {
    final base = _tx[ticker];
    if (base == null || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(txid)) {
      return null;
    }
    return Uri.parse('$base$txid');
  }
}
```

Create `app/lib/platform/url_opener.dart`:

```dart
import 'package:url_launcher/url_launcher.dart';

/// Opens a web page in the browser (explorer links, spec D4).
class UrlOpener {
  const UrlOpener();

  /// False when no app could open [url].
  Future<bool> open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}
```

Create `app/lib/features/asset/bloc/asset_history_cubit.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';

enum HistoryStatus { loading, ready, failed }

/// Asset detail: name, balance and history (spec §4).
///
/// `stringify` is off: it holds amounts and addresses.
class AssetHistoryState extends Equatable {
  const AssetHistoryState({
    this.name,
    this.balance,
    this.status = HistoryStatus.loading,
    this.transactions = const [],
    this.visible = AssetHistoryCubit.pageSize,
  });

  final String? name;
  final BalanceView? balance;
  final HistoryStatus status;

  /// Every known transaction, pending first then newest first.
  final List<TxView> transactions;

  /// How many of [transactions] are on screen.
  final int visible;

  List<TxView> get shown => transactions.take(visible).toList();

  bool get hasMore => transactions.length > visible;

  AssetHistoryState copyWith({
    String? name,
    BalanceView? balance,
    HistoryStatus? status,
    List<TxView>? transactions,
    int? visible,
  }) => AssetHistoryState(
    name: name ?? this.name,
    balance: balance ?? this.balance,
    status: status ?? this.status,
    transactions: transactions ?? this.transactions,
    visible: visible ?? this.visible,
  );

  @override
  List<Object?> get props => [name, balance, status, transactions, visible];

  @override
  bool? get stringify => false;
}

/// Follows one asset's balance and history, 25 rows at a time.
class AssetHistoryCubit extends Cubit<AssetHistoryState> {
  AssetHistoryCubit({
    required this.ticker,
    required AssetsRepository assets,
    required HistoryRepository history,
  }) : _assets = assets,
       _history = history,
       super(const AssetHistoryState());

  static const pageSize = 25;

  final String ticker;
  final AssetsRepository _assets;
  final HistoryRepository _history;
  StreamSubscription<BalanceView>? _balance;
  StreamSubscription<List<TxView>>? _transactions;

  int get requiredConfirmations => _history.requiredConfirmations(ticker);

  Future<void> start() async {
    _balance ??= _assets.watchBalance(ticker).listen(_onBalance);
    _watchHistory();
    try {
      final listed = await _assets.listed();
      for (final asset in listed) {
        if (asset.ticker == ticker) _emit(state.copyWith(name: asset.name));
      }
    } on Object catch (error) {
      debugPrint('Asset name lookup failed: ${error.runtimeType}');
    }
  }

  void _watchHistory() {
    unawaited(_transactions?.cancel());
    _transactions = _history
        .watch(ticker)
        .listen(
          (list) => _emit(
            state.copyWith(status: HistoryStatus.ready, transactions: list),
          ),
          onError: (Object error) {
            debugPrint('History failed: ${error.runtimeType}');
            _emit(state.copyWith(status: HistoryStatus.failed));
          },
        );
  }

  /// Error state's Retry: watches the history again.
  void retry() {
    _emit(state.copyWith(status: HistoryStatus.loading));
    _watchHistory();
  }

  /// Shows the next page, if any.
  void loadMore() {
    if (!state.hasMore) return;
    _emit(state.copyWith(visible: state.visible + pageSize));
  }

  /// Pull-to-refresh: fetches newer history and a fresh balance. Each
  /// failure is only logged; the screen keeps what it has.
  Future<void> refresh() async {
    await Future.wait([
      _guard('History sync', () => _history.sync(ticker)),
      _guard('Balance refresh', () async {
        _onBalance(await _assets.refreshBalance(ticker));
      }),
    ]);
  }

  Future<void> _guard(String what, Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error) {
      debugPrint('$what failed: ${error.runtimeType}');
    }
  }

  void _onBalance(BalanceView balance) =>
      _emit(state.copyWith(balance: balance));

  void _emit(AssetHistoryState next) {
    if (!isClosed) emit(next);
  }

  @override
  Future<void> close() async {
    await _balance?.cancel();
    await _transactions?.cancel();
    return super.close();
  }
}
```

Create `app/lib/features/asset/view/asset_detail_page.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/features/asset/bloc/asset_history_cubit.dart';
import 'package:digibyte_dex/features/asset/view/tx_detail_sheet.dart';
import 'package:digibyte_dex/l10n/history_messages.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// One listed asset: balance, Send and Receive, and history (spec §4).
class AssetDetailPage extends StatelessWidget {
  const AssetDetailPage({required this.ticker, super.key});

  final String ticker;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) {
      final cubit = AssetHistoryCubit(
        ticker: ticker,
        assets: context.read<AssetsRepository>(),
        history: context.read<HistoryRepository>(),
      );
      unawaited(cubit.start());
      return cubit;
    },
    child: _AssetDetailView(ticker: ticker),
  );
}

class _AssetDetailView extends StatelessWidget {
  const _AssetDetailView({required this.ticker});

  final String ticker;

  /// Rows left below the fold when the next page is shown.
  static const _loadMoreExtent = 400.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<AssetHistoryCubit>();
    return BlocBuilder<AssetHistoryCubit, AssetHistoryState>(
      builder: (context, state) {
        final name = state.name;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              name == null ? ticker : l10n.assetTitle(name, ticker),
            ),
          ),
          body: SafeArea(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.extentAfter < _loadMoreExtent) {
                  cubit.loadMore();
                }
                return false;
              },
              child: Tagged(
                'asset.refresh',
                child: RefreshIndicator(
                  key: const Key('asset.refresh'),
                  onRefresh: cubit.refresh,
                  child: ListView(
                    key: const Key('asset.list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _Header(ticker: ticker, state: state),
                      const Divider(height: 1),
                      ..._history(context, state),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _history(BuildContext context, AssetHistoryState state) {
    final l10n = context.l10n;
    switch (state.status) {
      case HistoryStatus.loading:
        return const [
          Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        ];
      case HistoryStatus.failed:
        return [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(l10n.historyFailed, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Tagged(
                  'asset.retry',
                  child: TextButton(
                    key: const Key('asset.retry'),
                    onPressed: context.read<AssetHistoryCubit>().retry,
                    child: Text(l10n.retry),
                  ),
                ),
              ],
            ),
          ),
        ];
      case HistoryStatus.ready:
        if (state.transactions.isEmpty) {
          return [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Tagged(
                'asset.empty',
                child: Text(
                  l10n.historyEmpty,
                  key: const Key('asset.empty'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ];
        }
        final required = context
            .read<AssetHistoryCubit>()
            .requiredConfirmations;
        return [
          for (final (index, tx) in state.shown.indexed)
            _TxRow(
              id: 'asset.tx.$index',
              ticker: ticker,
              tx: tx,
              required: required,
            ),
          if (state.hasMore)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ];
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.ticker, required this.state});

  final String ticker;
  final AssetHistoryState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final balance = state.balance;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.balanceLabel, style: Theme.of(context).textTheme.bodySmall),
          Tagged(
            'asset.balance',
            child: Text(
              balance == null
                  ? l10n.balanceLoading
                  : '${balance.total} $ticker',
              key: const Key('asset.balance'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (balance != null && balance.hasLockedFunds)
            Tagged(
              'asset.spendable',
              child: Text(
                l10n.spendableAmount(balance.spendable.toString()),
                key: const Key('asset.spendable'),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Tagged(
                  'asset.receive',
                  child: OutlinedButton.icon(
                    key: const Key('asset.receive'),
                    onPressed: () =>
                        unawaited(context.push(Routes.receive(ticker))),
                    icon: const Icon(Icons.call_received),
                    label: Text(l10n.receiveAction),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({
    required this.id,
    required this.ticker,
    required this.tx,
    required this.required,
  });

  final String id;
  final String ticker;
  final TxView tx;
  final int required;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final icon = switch (tx.direction) {
      TxDirection.received => Icons.south_west,
      TxDirection.sent => Icons.north_east,
      TxDirection.toSelf => Icons.sync_alt,
    };
    return Tagged(
      id,
      child: ListTile(
        key: Key(id),
        leading: Icon(icon),
        title: Text(tx.directionLabel(l10n)),
        subtitle: Text(
          '${tx.localTime(locale)} · ${tx.status(l10n, required)}',
        ),
        trailing: Text(
          '${tx.signedAmount} $ticker',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        onTap: () => unawaited(
          showTxDetail(context, ticker: ticker, tx: tx, required: required),
        ),
      ),
    );
  }
}
```

Create `app/lib/features/asset/view/tx_detail_sheet.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/config/explorers.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/l10n/history_messages.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/url_opener.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Shows one transaction's details in a bottom sheet (spec §4). The sheet
/// is a route of its own, so the services it uses are handed over from
/// [context].
Future<void> showTxDetail(
  BuildContext context, {
  required String ticker,
  required TxView tx,
  required int required,
}) {
  final clipboard = context.read<ClipboardGuard>();
  final urls = context.read<UrlOpener>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: clipboard),
        RepositoryProvider.value(value: urls),
      ],
      child: TxDetailSheet(ticker: ticker, tx: tx, required: required),
    ),
  );
}

class TxDetailSheet extends StatelessWidget {
  const TxDetailSheet({
    required this.ticker,
    required this.tx,
    required this.required,
    super.key,
  });

  final String ticker;
  final TxView tx;
  final int required;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final txid = tx.txid;
    final explorer = txid == null ? null : Explorers.tx(ticker, txid);
    final fee = tx.fee;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          Text(
            l10n.txDetailTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _Field(
            id: 'tx.direction',
            label: tx.directionLabel(l10n),
            value: '${tx.signedAmount} $ticker',
          ),
          if (fee != null)
            _Field(id: 'tx.fee', label: l10n.txFeeLabel, value: '$fee $ticker'),
          _Field(
            id: 'tx.status',
            label: l10n.txStatusLabel,
            value: tx.status(l10n, required),
          ),
          _Field(
            id: 'tx.confirmations',
            label: l10n.txConfirmationsLabel,
            value: '${tx.confirmations}',
          ),
          if (tx.blockHeight > 0)
            _Field(
              id: 'tx.block',
              label: l10n.txBlockLabel,
              value: '${tx.blockHeight}',
            ),
          _Field(
            id: 'tx.date',
            label: l10n.txDateLabel,
            value: tx.localTime(locale),
          ),
          if (tx.counterparties.isNotEmpty)
            _Field(
              id: 'tx.counterparties',
              label: tx.direction == TxDirection.received
                  ? l10n.txFromLabel
                  : l10n.txToLabel,
              value: tx.counterparties.join('\n'),
              monospace: true,
            ),
          if (txid != null) ...[
            _Field(
              id: 'tx.txid',
              label: l10n.txIdLabel,
              value: txid,
              monospace: true,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Tagged(
                    'tx.copy',
                    child: OutlinedButton.icon(
                      key: const Key('tx.copy'),
                      onPressed: () => unawaited(_copy(context, txid)),
                      icon: const Icon(Icons.copy),
                      label: Text(l10n.copy),
                    ),
                  ),
                ),
                if (explorer != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Tagged(
                      'tx.explorer',
                      child: FilledButton.icon(
                        key: const Key('tx.explorer'),
                        onPressed: () =>
                            unawaited(openExplorer(context, explorer)),
                        icon: const Icon(Icons.open_in_new),
                        label: Text(l10n.viewInExplorer),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, String txid) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    var message = l10n.txIdCopied;
    try {
      await context.read<ClipboardGuard>().copy(txid);
    } on Object {
      message = l10n.copyFailed;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Opens [url] in the browser; a SnackBar says so when nothing can.
Future<void> openExplorer(BuildContext context, Uri url) async {
  final messenger = ScaffoldMessenger.of(context);
  final failed = context.l10n.explorerFailed;
  var opened = false;
  try {
    opened = await context.read<UrlOpener>().open(url);
  } on Object {
    opened = false;
  }
  if (!opened) messenger.showSnackBar(SnackBar(content: Text(failed)));
}

class _Field extends StatelessWidget {
  const _Field({
    required this.id,
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String id;
  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.bodySmall),
          Tagged(
            id,
            child: Text(
              value,
              key: Key(id),
              style: monospace
                  ? theme.bodyMedium?.copyWith(fontFamily: 'monospace')
                  : theme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
```

Create `app/lib/l10n/history_messages.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:intl/intl.dart';

extension TxViewText on TxView {
  String directionLabel(AppLocalizations l10n) => switch (direction) {
    TxDirection.received => l10n.txReceived,
    TxDirection.sent => l10n.txSent,
    TxDirection.toSelf => l10n.txToSelf,
  };

  /// Pending, Confirming n/N, or Confirmed (spec §4).
  String status(AppLocalizations l10n, int required) {
    if (pending) return l10n.txPending;
    if (confirmations < required) {
      return l10n.txConfirming(confirmations, required);
    }
    return l10n.txConfirmed;
  }

  /// The net change with its sign: `+5`, `-1.0226`.
  String get signedAmount => amount > Decimal.zero ? '+$amount' : '$amount';

  /// Local date and time, e.g. `Oct 4, 2026 14:05`.
  String localTime(String locale) =>
      DateFormat.yMMMd(locale).add_Hm().format(timestamp.toLocal());
}
```

In `app/lib/app/routes.dart`, replace:

```dart
  /// The receive screen of one listed asset.
  static String receive(String ticker) => '/home/receive/$ticker';
}
```

with:

```dart
  /// The receive screen of one listed asset.
  static String receive(String ticker) => '/home/receive/$ticker';

  /// Balance, Send, Receive and history of one listed asset.
  static String asset(String ticker) => '/home/asset/$ticker';
}
```

Edit `app/lib/app/router.dart` (2 replacements, top to bottom):

1. Replace:

```dart

import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
```

   with:

```dart

import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/features/asset/view/asset_detail_page.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
```

2. Replace:

```dart
            ReceivePage(ticker: state.pathParameters['ticker']!),
      ),
    ],
  ),
```

   with:

```dart
            ReceivePage(ticker: state.pathParameters['ticker']!),
      ),
      GoRoute(
        path: 'asset/:ticker',
        builder: (_, state) =>
            AssetDetailPage(ticker: state.pathParameters['ticker']!),
      ),
    ],
  ),
```


In `app/lib/features/wallet/view/home_page.dart`, replace:

```dart
        ),
        trailing: trailing,
        onTap: active ? () => context.go(Routes.receive(row.ticker)) : null,
      ),
    );
```

with:

```dart
        ),
        trailing: trailing,
        onTap: active ? () => context.go(Routes.asset(row.ticker)) : null,
      ),
    );
```

Edit `app/lib/app/app_scope.dart` (8 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
```

   with:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
```

2. Replace:

```dart
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
```

   with:

```dart
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:digibyte_dex/platform/url_opener.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
```

3. Replace:

```dart
    required this.assets,
    required this.receive,
    required this.backups,
    required this.attempts,
```

   with:

```dart
    required this.assets,
    required this.receive,
    required this.history,
    required this.backups,
    required this.attempts,
```

4. Replace:

```dart
    required this.clipboard,
    required this.sharer,
    PendingBackupSession? session,
  }) : session = session ?? PendingBackupSession();
```

   with:

```dart
    required this.clipboard,
    required this.sharer,
    required this.urls,
    PendingBackupSession? session,
  }) : session = session ?? PendingBackupSession();
```

5. Replace:

```dart
  final AssetsRepository assets;
  final ReceiveRepository receive;
  final BackupStatusStore backups;
  final PasswordAttempts attempts;
```

   with:

```dart
  final AssetsRepository assets;
  final ReceiveRepository receive;
  final HistoryRepository history;
  final BackupStatusStore backups;
  final PasswordAttempts attempts;
```

6. Replace:

```dart
  final ClipboardGuard clipboard;
  final TextSharer sharer;
  final PendingBackupSession session;
}
```

   with:

```dart
  final ClipboardGuard clipboard;
  final TextSharer sharer;
  final UrlOpener urls;
  final PendingBackupSession session;
}
```

7. Replace:

```dart
      RepositoryProvider<AssetsRepository>.value(value: services.assets),
      RepositoryProvider<ReceiveRepository>.value(value: services.receive),
      RepositoryProvider.value(value: services.backups),
      RepositoryProvider.value(value: services.attempts),
```

   with:

```dart
      RepositoryProvider<AssetsRepository>.value(value: services.assets),
      RepositoryProvider<ReceiveRepository>.value(value: services.receive),
      RepositoryProvider<HistoryRepository>.value(value: services.history),
      RepositoryProvider.value(value: services.backups),
      RepositoryProvider.value(value: services.attempts),
```

8. Replace:

```dart
      RepositoryProvider.value(value: services.clipboard),
      RepositoryProvider<TextSharer>.value(value: services.sharer),
    ],
    child: MultiBlocProvider(
```

   with:

```dart
      RepositoryProvider.value(value: services.clipboard),
      RepositoryProvider<TextSharer>.value(value: services.sharer),
      RepositoryProvider<UrlOpener>.value(value: services.urls),
    ],
    child: MultiBlocProvider(
```


Edit `app/lib/main.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
```

   with:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
```

2. Replace:

```dart
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
```

   with:

```dart
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:digibyte_dex/platform/url_opener.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
```

3. Replace:

```dart
      assets: SdkAssetsRepository(sdk),
      receive: SdkReceiveRepository(sdk),
      backups: BackupStatusStore(storage),
      attempts: PasswordAttempts(LockoutStore(storage)),
```

   with:

```dart
      assets: SdkAssetsRepository(sdk),
      receive: SdkReceiveRepository(sdk),
      history: SdkHistoryRepository(sdk),
      backups: BackupStatusStore(storage),
      attempts: PasswordAttempts(LockoutStore(storage)),
```

4. Replace:

```dart
      clipboard: ClipboardGuard(),
      sharer: const TextSharer(),
    );
    // App-lifetime cubits: never closed, the process ends with them.
```

   with:

```dart
      clipboard: ClipboardGuard(),
      sharer: const TextSharer(),
      urls: const UrlOpener(),
    );
    // App-lifetime cubits: never closed, the process ends with them.
```


`app_en.arb` grows at the end in every task that adds strings. The replacement below adds a comma to the current last entry and appends this task's entries.

In `app/lib/l10n/arb/app_en.arb`, replace:

```json
  "receiveAddressLimit": "Use one of your unused addresses first.",
  "receiveUnsupported": "This wallet has a single address.",
  "receiveFailed": "Couldn't create a new address. Try again."
}
```

with:

```json
  "receiveAddressLimit": "Use one of your unused addresses first.",
  "receiveUnsupported": "This wallet has a single address.",
  "receiveFailed": "Couldn't create a new address. Try again.",
  "assetTitle": "{name} ({ticker})",
  "@assetTitle": {"placeholders": {"name": {"type": "String"}, "ticker": {"type": "String"}}},
  "balanceLabel": "Balance",
  "receiveAction": "Receive",
  "historyEmpty": "No transactions yet",
  "historyFailed": "Couldn't load transactions.",
  "txReceived": "Received",
  "txSent": "Sent",
  "txToSelf": "To yourself",
  "txPending": "Pending",
  "txConfirming": "Confirming {count}/{required}",
  "@txConfirming": {"placeholders": {"count": {"type": "int"}, "required": {"type": "int"}}},
  "txConfirmed": "Confirmed",
  "txDetailTitle": "Transaction",
  "txFeeLabel": "Network fee",
  "txStatusLabel": "Status",
  "txConfirmationsLabel": "Confirmations",
  "txBlockLabel": "Block",
  "txDateLabel": "Date",
  "txFromLabel": "From",
  "txToLabel": "To",
  "txIdLabel": "Transaction ID",
  "txIdCopied": "Transaction ID copied.",
  "viewInExplorer": "View in explorer",
  "explorerFailed": "Couldn't open the explorer."
}
```

Then regenerate the localizations:

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter gen-l10n
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/config/explorers_test.dart \
  test/features/asset/asset_history_cubit_test.dart \
  test/features/asset/asset_detail_page_test.dart \
  test/features/wallet/home_page_test.dart \
  test/app/app_scope_test.dart \
  test/app/router_test.dart
```

Expected: `+39: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```

Expected: the formatter changes 0 files; `No issues found!`; `+466: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/app/app_scope.dart \
  lib/app/router.dart \
  lib/app/routes.dart \
  lib/config/explorers.dart \
  lib/features/asset/bloc/asset_history_cubit.dart \
  lib/features/asset/view/asset_detail_page.dart \
  lib/features/asset/view/tx_detail_sheet.dart \
  lib/features/wallet/view/home_page.dart \
  lib/l10n/arb/app_en.arb \
  lib/l10n/history_messages.dart \
  lib/main.dart \
  lib/platform/url_opener.dart \
  pubspec.lock \
  pubspec.yaml \
  test/app/app_scope_test.dart \
  test/app/router_test.dart \
  test/config/explorers_test.dart \
  test/features/asset/asset_detail_page_test.dart \
  test/features/asset/asset_history_cubit_test.dart \
  test/features/wallet/home_page_test.dart \
  test/support/fake_url_opener.dart \
  test/support/test_app.dart \
  test/support/tx_views.dart
git commit -m "feat(asset): asset detail with history, tx detail and explorer links" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 5: The send flow: `SendCubit`, form, Confirm (warnings, acknowledgement, re-authentication) and Result

`/home/send/:ticker` (spec §3). One page with three views chosen by the cubit's step: the form (editing, previewing), Confirm on a `SecureScreen` (confirming, authenticating, broadcasting) and Result (done, failed). The route's `extra` may carry a `PaymentUri` prefill; it is never in the URL. Re-authentication on every send (D2) uses `PasswordGate`: biometrics when enabled (cancel or failure falls back to the password), otherwise the password through the shared lockout. Confirm never offers to turn biometrics on. A lock (`LockCubit` emits `Locked`), Back and closing the page drop the signed preview.

**Files:**
- Create: `app/lib/features/send/bloc/send_cubit.dart`
- Create: `app/lib/features/send/view/send_page.dart`
- Create: `app/lib/features/send/view/send_form_view.dart`
- Create: `app/lib/features/send/view/send_confirm_view.dart`
- Create: `app/lib/features/send/view/send_result_view.dart`
- Create: `app/lib/l10n/send_messages.dart`
- Modify: `app/lib/features/asset/view/asset_detail_page.dart`
- Modify: `app/lib/app/routes.dart`
- Modify: `app/lib/app/router.dart`
- Modify: `app/lib/features/wallet/view/home_page.dart`
- Modify: `app/lib/app/app_scope.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/test/support/test_app.dart`
- Modify: `app/lib/l10n/arb/app_en.arb`
- Test (modify): `app/test/features/asset/asset_detail_page_test.dart`
- Test (modify): `app/test/features/wallet/home_page_test.dart`
- Test (modify): `app/test/app/app_scope_test.dart`
- Test (modify): `app/test/app/router_test.dart`
- Test (create): `app/test/features/send/send_cubit_test.dart`
- Test (create): `app/test/features/send/send_page_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4 (`PaymentUri`, `SendRules`, `AddressSafety`, `SendRepository` and friends, `HistoryRepository.recentCounterparties`/`sync`, `AssetsRepository.refreshBalance`, `Explorers`, `openExplorer`, `Routes.asset`); M1-C `PasswordGate`, `PasswordGateState`, `PasswordGateForm`, `PasswordAttempts`, `BiometricStore`, `WalletRepository.verifyPassword`, `TimerFactory`, `SecureScreen`, `ClipboardGuard`.
- Produces:
  - `enum SendStep { editing, previewing, confirming, authenticating, broadcasting, done, failed }`
  - `enum AddressStatus { empty, checking, valid, invalid, unverified, wrongCoin }`
  - `class SendState extends Equatable` with `ticker, step, address, addressStatus, otherTicker, amount, isMax, note, source, sourceFailure, preview, warnings, acknowledged, needPassword, gate, txid, failure, fieldRevision` and getters `loadingSource`, `amountProblem`, `canPreview`, `canSend`; `stringify` off.
  - `class SendCubit extends Cubit<SendState> { SendCubit({required String ticker, required String walletName, required SendRepository send, required HistoryRepository history, required AssetsRepository assets, required WalletRepository wallet, required PasswordAttempts attempts, required BiometricStore biometrics, TimerFactory? timer, Duration debounce = const Duration(milliseconds: 400)}); String get ticker; Future<void> init({PaymentUri? request}); Future<void> retrySource(); void addressChanged(String text); void applyRequest(PaymentUri request); void recheckAddress(); void amountChanged(String text); void useMax(); Future<void> next(); void acknowledge({required bool checked}); Future<void> confirm({required String reason}); Future<void> confirmWithPassword(String password); void backToEdit(); void discard(); void lockoutExpired(); }`
  - `class SendPage extends StatelessWidget { const SendPage({required String ticker, PaymentUri? request}); }`; views `SendFormView`, `SendConfirmView`, `SendResultView`.
  - `extension SendFailureMessage on SendFailure { String message(AppLocalizations) }`; `extension AmountProblemMessage on AmountProblem { String? message(AppLocalizations, {required String ticker, required String sourceAmount}) }` (`lib/l10n/send_messages.dart`).
  - `Routes.send(String ticker)` → `/home/send/<ticker>`; the route keys the page by its request (`ObjectKey(request)`), so a new link replaces the form.
  - `AppServices` gains `required SendRepository send`.
  - Widget ids — form: `send.address`, `send.recheck`, `send.note`, `send.amount`, `send.max`, `send.available`, `send.retrySource`, `send.error`, `send.next`, `send.busy`; Confirm: `confirm.to`, `confirm.amount`, `confirm.fee`, `confirm.total`, `confirm.from`, `confirm.lookalike`, `confirm.self`, `confirm.ack`, `confirm.send`, `confirm.busy`, `confirm.back`, plus `PasswordGateForm`'s `confirm.password`, `confirm.submit`, `confirm.biometric`, `confirm.lockout`; Result: `result.txid`, `result.copy`, `result.explorer`, `result.done`, `result.error`, `result.back`; `asset.send`; `home.row.<TICKER>.send`.
- Test support: `TestApp.send` (a `FakeSendRepository`).

- [ ] **Step 1: Write the failing tests**

Edit `app/test/features/asset/asset_detail_page_test.dart` (2 replacements, top to bottom):

1. Replace:

```dart
        child: const AssetDetailPage(ticker: 'DGB'),
      ),
      stubs: [Routes.receive('DGB')],
    );
  }
```

   with:

```dart
        child: const AssetDetailPage(ticker: 'DGB'),
      ),
      stubs: [Routes.receive('DGB'), Routes.send('DGB')],
    );
  }
```

2. Replace:

```dart
    expect(find.text("Couldn't open the explorer."), findsOneWidget);
  });
}
```

   with:

```dart
    expect(find.text("Couldn't open the explorer."), findsOneWidget);
  });

  testWidgets('Send opens the send page', (t) async {
    await pump(t);
    await tapKey(t, 'asset.send');
    await t.pumpAndSettle();
    expect(find.text('route:${Routes.send('DGB')}'), findsOneWidget);
  });
}
```


Edit `app/test/features/wallet/home_page_test.dart` (2 replacements, top to bottom):

1. Replace:

```dart
        ),
      ),
      stubs: [Routes.asset('DGB')],
    );
  }
```

   with:

```dart
        ),
      ),
      stubs: [Routes.asset('DGB'), Routes.send('DGB')],
    );
  }
```

2. Replace:

```dart
    expect(find.text('route:${Routes.asset('DGB')}'), findsOneWidget);
  });
}
```

   with:

```dart
    expect(find.text('route:${Routes.asset('DGB')}'), findsOneWidget);
  });

  testWidgets('an active row has a Send action', (t) async {
    await pump(t);
    await tapKey(t, 'home.row.DGB.send');
    await t.pumpAndSettle();
    expect(find.text('route:${Routes.send('DGB')}'), findsOneWidget);
  });
}
```


Edit `app/test/support/test_app.dart` (3 replacements, top to bottom):

1. Replace:

```dart
import 'fake_receive_repository.dart';
import 'fake_seed_validator.dart';
import 'fake_text_sharer.dart';
import 'fake_timers.dart';
```

   with:

```dart
import 'fake_receive_repository.dart';
import 'fake_seed_validator.dart';
import 'fake_send_repository.dart';
import 'fake_text_sharer.dart';
import 'fake_timers.dart';
```

2. Replace:

```dart
  final receive = FakeReceiveRepository();
  final history = FakeHistoryRepository();
  final urls = FakeUrlOpener();
  final clipboardWrites = <String>[];
```

   with:

```dart
  final receive = FakeReceiveRepository();
  final history = FakeHistoryRepository();
  final send = FakeSendRepository();
  final urls = FakeUrlOpener();
  final clipboardWrites = <String>[];
```

3. Replace:

```dart
    receive: receive,
    history: history,
    backups: backups,
    attempts: attempts,
```

   with:

```dart
    receive: receive,
    history: history,
    send: send,
    backups: backups,
    attempts: attempts,
```


Edit `app/test/app/app_scope_test.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
```

   with:

```dart
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/send_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
```

2. Replace:

```dart
import '../support/fake_receive_repository.dart';
import '../support/fake_seed_validator.dart';
import '../support/fake_text_sharer.dart';
import '../support/fake_url_opener.dart';
```

   with:

```dart
import '../support/fake_receive_repository.dart';
import '../support/fake_seed_validator.dart';
import '../support/fake_send_repository.dart';
import '../support/fake_text_sharer.dart';
import '../support/fake_url_opener.dart';
```

3. Replace:

```dart
      receive: FakeReceiveRepository(),
      history: FakeHistoryRepository(),
      backups: BackupStatusStore(storage),
      attempts: PasswordAttempts(LockoutStore(storage)),
```

   with:

```dart
      receive: FakeReceiveRepository(),
      history: FakeHistoryRepository(),
      send: FakeSendRepository(),
      backups: BackupStatusStore(storage),
      attempts: PasswordAttempts(LockoutStore(storage)),
```

4. Replace:

```dart
    expect(probe.read<TextSharer>(), same(services.sharer));
    expect(probe.read<HistoryRepository>(), same(services.history));
    expect(probe.read<UrlOpener>(), same(services.urls));
    expect(probe.read<AuthCubit>(), same(cubits.auth));
```

   with:

```dart
    expect(probe.read<TextSharer>(), same(services.sharer));
    expect(probe.read<HistoryRepository>(), same(services.history));
    expect(probe.read<SendRepository>(), same(services.send));
    expect(probe.read<UrlOpener>(), same(services.urls));
    expect(probe.read<AuthCubit>(), same(cubits.auth));
```


Edit `app/test/app/router_test.dart` (3 replacements, top to bottom):

1. Replace:

```dart
      '/home/receive/DGB',
      '/home/asset/DGB',
      '/nonexistent',
      '',
```

   with:

```dart
      '/home/receive/DGB',
      '/home/asset/DGB',
      '/home/send/DGB',
      '/nonexistent',
      '',
```

2. Replace:

```dart
    expect(Routes.receive('DGB'), '/home/receive/DGB');
    expect(Routes.asset('DGB'), '/home/asset/DGB');
  });

```

   with:

```dart
    expect(Routes.receive('DGB'), '/home/receive/DGB');
    expect(Routes.asset('DGB'), '/home/asset/DGB');
    expect(Routes.send('DGB'), '/home/send/DGB');
  });

```

3. Replace:

```dart
    expect(go(pending, Routes.asset('DGB')), Routes.backup);
    expect(go(returning, Routes.asset('DGB')), Routes.signIn);
  });

```

   with:

```dart
    expect(go(pending, Routes.asset('DGB')), Routes.backup);
    expect(go(returning, Routes.asset('DGB')), Routes.signIn);
  });

  test('send needs an unlocked session with no pending backup', () {
    expect(go(signedIn, Routes.send('DGB')), isNull);
    expect(go(signedIn, Routes.send('DGB'), locked), Routes.locked);
    expect(go(pending, Routes.send('DGB')), Routes.backup);
    expect(go(fresh, Routes.send('DGB')), Routes.welcome);
  });

```


Create `app/test/features/send/send_cubit_test.dart`:

```dart
import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/send_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
import 'package:digibyte_dex/domain/address_safety.dart';
import 'package:digibyte_dex/domain/payment_uri.dart';
import 'package:digibyte_dex/domain/send_rules.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/send/bloc/send_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_assets_repository.dart';
import '../../support/fake_biometric_store.dart';
import '../../support/fake_history_repository.dart';
import '../../support/fake_send_repository.dart';
import '../../support/fake_timers.dart';
import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/tx_views.dart';

const _pw = 'Correct-Horse-9';
const _wrong = 'Wrong-Horse-1';
// Dummies, not real addresses.
const _payee = 'DAbc1111111111111111111111111wxyz';
const _poison = 'DAbc2222222222222222222222222wxyz';
const _other = 'DQrs3333333333333333333333333tuvw';

Decimal _d(String s) => Decimal.parse(s);

void main() {
  late FakeSendRepository send;
  late FakeHistoryRepository history;
  late FakeAssetsRepository assets;
  late FakeWalletRepository wallet;
  late FakeBiometricStore biometrics;
  late InMemoryKeyValueStore storage;
  late PasswordAttempts attempts;
  late FakeTimers timers;
  late DateTime now;

  setUp(() {
    send = FakeSendRepository();
    history = FakeHistoryRepository();
    assets = FakeAssetsRepository();
    wallet = FakeWalletRepository();
    biometrics = FakeBiometricStore();
    storage = InMemoryKeyValueStore();
    now = DateTime.utc(2026, 10, 4, 12);
    attempts = PasswordAttempts(LockoutStore(storage), now: () => now);
    timers = FakeTimers();
    assets.refreshed['DGB'] = BalanceView(total: _d('8'), spendable: _d('8'));
  });
  tearDown(() => wallet.dispose());

  Future<SendCubit> build({String ticker = 'DGB', PaymentUri? request}) async {
    final cubit = SendCubit(
      ticker: ticker,
      walletName: 'main',
      send: send,
      history: history,
      assets: assets,
      wallet: wallet,
      attempts: attempts,
      biometrics: biometrics,
      timer: timers.create,
    );
    addTearDown(cubit.close);
    await cubit.init(request: request);
    return cubit;
  }

  /// Types [address], lets the 400 ms debounce pass and the check finish.
  Future<void> typeAddress(SendCubit cubit, String address) async {
    cubit.addressChanged(address);
    timers.pending.last.fire();
    await pumpEventQueue();
  }

  /// A filled form: a valid address and 1 coin.
  Future<SendCubit> filled({String address = _other}) async {
    final cubit = await build();
    await typeAddress(cubit, address);
    cubit.amountChanged('1');
    return cubit;
  }

  Future<SendCubit> confirming({String address = _other}) async {
    final cubit = await filled(address: address);
    await cubit.next();
    expect(cubit.state.step, SendStep.confirming);
    return cubit;
  }

  group('form', () {
    test('loads the source address and its balance', () async {
      final cubit = await build();
      expect(cubit.state.step, SendStep.editing);
      expect(cubit.state.source?.source.spendable, _d('10'));
      expect(cubit.state.loadingSource, isFalse);
    });

    test('a failed source load can be retried', () async {
      send.sourceFailure = SendFailure.network;
      final cubit = await build();
      expect(cubit.state.sourceFailure, SendFailure.network);
      send.sourceFailure = null;
      await cubit.retrySource();
      expect(cubit.state.source, isNotNull);
      expect(cubit.state.sourceFailure, isNull);
    });

    test('the address is checked 400 ms after the last edit', () async {
      final cubit = await build();
      cubit
        ..addressChanged('DAbc')
        ..addressChanged(' $_other ');
      expect(cubit.state.addressStatus, AddressStatus.checking);
      expect(timers.pending, hasLength(1));
      expect(timers.pending.single.duration, const Duration(milliseconds: 400));
      timers.pending.single.fire();
      await pumpEventQueue();
      expect(send.validated, [_other]);
      expect(cubit.state.address, _other);
      expect(cubit.state.addressStatus, AddressStatus.valid);
    });

    test(
      'invalid and unverified addresses; unverified can be rechecked',
      () async {
        send
          ..invalid = {_poison}
          ..unverified = {_payee};
        final cubit = await build();
        await typeAddress(cubit, _poison);
        expect(cubit.state.addressStatus, AddressStatus.invalid);
        await typeAddress(cubit, _payee);
        expect(cubit.state.addressStatus, AddressStatus.unverified);
        send.unverified = {};
        cubit.recheckAddress();
        timers.pending.last.fire();
        await pumpEventQueue();
        expect(cubit.state.addressStatus, AddressStatus.valid);
      },
    );

    test('a stale check never overwrites a newer address', () async {
      final cubit = await build();
      cubit.addressChanged(_payee);
      final first = timers.pending.single;
      cubit.addressChanged('');
      first.fire();
      await pumpEventQueue();
      expect(cubit.state.addressStatus, AddressStatus.empty);
      expect(send.validated, isEmpty);
    });

    test('a pasted payment URI fills address, amount and note', () async {
      final cubit = await build();
      final revision = cubit.state.fieldRevision;
      cubit.addressChanged('digibyte:$_other?amount=2.5&message=Coffee');
      expect(cubit.state.address, _other);
      expect(cubit.state.amount, '2.5');
      expect(cubit.state.note, 'Coffee');
      expect(cubit.state.fieldRevision, revision + 1);
      timers.pending.last.fire();
      await pumpEventQueue();
      expect(cubit.state.canPreview, isTrue);
    });

    test('a URI for another coin is refused, never switched', () async {
      final cubit = await build();
      cubit.addressChanged('bitcoin:bc1qdummyaddress0000000000000000000000');
      expect(cubit.state.addressStatus, AddressStatus.wrongCoin);
      expect(cubit.state.otherTicker, 'BTC');
      expect(cubit.state.address, isEmpty);
      expect(timers.pending, isEmpty);
    });

    test('a request prefills the form at start (link or scan)', () async {
      final cubit = await build(
        request: PaymentUri(ticker: 'DGB', address: _other, amount: _d('3')),
      );
      expect(cubit.state.address, _other);
      expect(cubit.state.amount, '3');
      expect(send.requests, isEmpty);
    });

    test('amount rules: precision, dust, one-transaction limit', () async {
      final cubit = await build();
      cubit.amountChanged('1.123456789');
      expect(cubit.state.amountProblem, AmountProblem.tooPrecise);
      cubit.amountChanged('0.00001');
      expect(cubit.state.amountProblem, AmountProblem.belowDust);
      cubit.amountChanged('11');
      expect(cubit.state.amountProblem, AmountProblem.overSource);
      cubit.amountChanged('13');
      expect(cubit.state.amountProblem, AmountProblem.overBalance);
      cubit.amountChanged('10');
      expect(cubit.state.amountProblem, isNull);
    });

    test('Max is the source balance and is sent as max', () async {
      final cubit = await build();
      await typeAddress(cubit, _other);
      cubit.useMax();
      expect(cubit.state.amount, '10');
      expect(cubit.state.isMax, isTrue);
      await cubit.next();
      expect(send.requests.single.isMax, isTrue);
      expect(send.requests.single.amount, isNull);
      cubit
        ..backToEdit()
        ..amountChanged('2');
      expect(cubit.state.isMax, isFalse);
    });

    test('Next needs a valid address and a valid amount', () async {
      final cubit = await build();
      await typeAddress(cubit, _other);
      expect(cubit.state.canPreview, isFalse);
      cubit.amountChanged('1');
      expect(cubit.state.canPreview, isTrue);
    });
  });

  group('preview', () {
    test('Next signs a preview and shows Confirm', () async {
      final cubit = await confirming();
      final request = send.requests.single;
      expect(request.toAddress, _other);
      expect(request.amount, _d('1'));
      expect(cubit.state.preview?.fee, _d('0.0226'));
      expect(cubit.state.warnings, isEmpty);
      expect(cubit.state.canSend, isTrue);
    });

    test('a double tap on Next previews once', () async {
      final gate = Completer<void>();
      send.previewGate = gate;
      final cubit = await filled();
      final first = cubit.next();
      unawaited(cubit.next());
      gate.complete();
      await first;
      expect(send.requests, hasLength(1));
    });

    test('a preview error returns to the form with the reason', () async {
      send.previewFailure = SendFailure.insufficientFunds;
      final cubit = await filled();
      await cubit.next();
      expect(cubit.state.step, SendStep.editing);
      expect(cubit.state.failure, SendFailure.insufficientFunds);
      expect(send.busy, isFalse);
    });

    test('a look-alike of a recent address needs an acknowledgement', () async {
      history.recent = [_payee];
      final cubit = await confirming(address: _poison);
      expect(cubit.state.warnings, [const LookalikeWarning(_payee)]);
      expect(cubit.state.canSend, isFalse);
      cubit.acknowledge(checked: true);
      expect(cubit.state.canSend, isTrue);
    });

    test('an earlier send counts as a recent address', () async {
      send.sent['DGB'] = [_payee];
      final cubit = await confirming(address: _poison);
      expect(cubit.state.warnings, [const LookalikeWarning(_payee)]);
    });

    test('sending to my own address warns', () async {
      final cubit = await confirming(address: fakeOtherOwnAddress);
      expect(cubit.state.warnings, [const OwnAddressWarning()]);
    });
  });

  group('re-authentication', () {
    test('biometrics enabled: one prompt, then broadcast', () async {
      biometrics.passwords['main'] = _pw;
      final cubit = await confirming();
      expect(cubit.state.needPassword, isFalse);
      await cubit.confirm(reason: 'r');
      await pumpEventQueue();
      expect(biometrics.reads, 1);
      expect(cubit.state.step, SendStep.done);
      expect(cubit.state.txid, fakeTxid(1));
      expect(send.broadcasts, hasLength(1));
      expect(assets.refreshCalls, ['DGB']);
      expect(history.synced, ['DGB']);
      expect(wallet.calls, isEmpty);
    });

    test('a cancelled prompt falls back to the password', () async {
      biometrics
        ..passwords['main'] = _pw
        ..cancel = true;
      final cubit = await confirming();
      await cubit.confirm(reason: 'r');
      expect(cubit.state.step, SendStep.confirming);
      expect(cubit.state.needPassword, isTrue);
      expect(send.broadcasts, isEmpty);
      await cubit.confirmWithPassword(_pw);
      expect(cubit.state.step, SendStep.done);
      expect(wallet.calls, ['verify']);
    });

    test('biometrics off: Send asks for the password', () async {
      final cubit = await confirming();
      expect(cubit.state.needPassword, isTrue);
      await cubit.confirm(reason: 'r');
      expect(biometrics.reads, 0);
      expect(send.broadcasts, isEmpty);
    });

    test(
      'a wrong password sends nothing and counts in the shared lockout',
      () async {
        final cubit = await confirming();
        for (var i = 0; i < 5; i++) {
          await cubit.confirmWithPassword(_wrong);
        }
        expect(cubit.state.step, SendStep.confirming);
        expect(cubit.state.gate.failure, WalletFailure.wrongPassword);
        expect(send.broadcasts, isEmpty);
        // The same lockout the lock screen and sign-in use.
        expect(await attempts.blockedUntil('main'), isNotNull);
        await cubit.confirmWithPassword(_pw);
        expect(cubit.state.gate.failure, WalletFailure.lockedOut);
        expect(send.broadcasts, isEmpty);
      },
    );

    test('a lockout from the lock screen also blocks Confirm', () async {
      for (var i = 0; i < 5; i++) {
        await attempts.fail('main');
      }
      final cubit = await confirming();
      expect(cubit.state.gate.blockedUntil, isNotNull);
      await cubit.confirmWithPassword(_pw);
      expect(send.broadcasts, isEmpty);
      expect(wallet.calls, isEmpty);
    });

    test('Confirm never offers to turn biometrics on', () async {
      final cubit = await confirming();
      expect(cubit.state.gate.biometricsAvailable, isFalse);
    });
  });

  group('broadcast', () {
    test(
      'a failure shows the reason; Back to edit drops the preview',
      () async {
        send.broadcastFailure = SendFailure.network;
        final cubit = await confirming();
        await cubit.confirmWithPassword(_pw);
        expect(cubit.state.step, SendStep.failed);
        expect(cubit.state.failure, SendFailure.network);
        cubit.backToEdit();
        expect(cubit.state.step, SendStep.editing);
        expect(cubit.state.preview, isNull);
        expect(cubit.state.address, _other);
        send.broadcastFailure = null;
        await cubit.next();
        await cubit.confirmWithPassword(_pw);
        expect(cubit.state.step, SendStep.done);
        // A fresh preview each time; the failed one was never re-sent.
        expect(send.requests, hasLength(2));
        expect(send.broadcasts, hasLength(2));
        expect(identical(send.broadcasts[0], send.broadcasts[1]), isFalse);
      },
    );

    test('a double tap on Send broadcasts once', () async {
      final gate = Completer<void>();
      send.broadcastGate = gate;
      final cubit = await confirming();
      final first = cubit.confirmWithPassword(_pw);
      unawaited(cubit.confirmWithPassword(_pw));
      await pumpEventQueue();
      gate.complete();
      await first;
      expect(send.broadcasts, hasLength(1));
    });
  });

  group('discarding the preview', () {
    test('a lock on Confirm returns to the form and releases it', () async {
      final cubit = await confirming();
      final preview = cubit.state.preview!;
      cubit.discard();
      expect(cubit.state.step, SendStep.editing);
      expect(cubit.state.preview, isNull);
      expect(send.released, [preview]);
      expect(send.busy, isFalse);
      await cubit.confirmWithPassword(_pw);
      expect(send.broadcasts, isEmpty);
    });

    test('a lock while signing drops the preview when it arrives', () async {
      final gate = Completer<void>();
      send.previewGate = gate;
      final cubit = await filled();
      final next = cubit.next();
      cubit.discard();
      gate.complete();
      await next;
      expect(cubit.state.step, SendStep.editing);
      expect(send.released, hasLength(1));
      expect(send.busy, isFalse);
    });

    test('a lock during the biometric prompt sends nothing', () async {
      final gate = Completer<void>();
      biometrics
        ..passwords['main'] = _pw
        ..readGate = gate.future;
      final cubit = await confirming();
      final confirm = cubit.confirm(reason: 'r');
      await pumpEventQueue();
      cubit.discard();
      gate.complete();
      await confirm;
      expect(cubit.state.step, SendStep.editing);
      expect(send.broadcasts, isEmpty);
    });

    test('a lock during the broadcast does not interrupt it', () async {
      final gate = Completer<void>();
      send.broadcastGate = gate;
      final cubit = await confirming();
      final sending = cubit.confirmWithPassword(_pw);
      await pumpEventQueue();
      cubit.discard();
      expect(cubit.state.step, SendStep.broadcasting);
      gate.complete();
      await sending;
      expect(cubit.state.step, SendStep.done);
    });

    test('closing the page releases a held preview', () async {
      final cubit = await confirming();
      final preview = cubit.state.preview!;
      await cubit.close();
      expect(send.released, [preview]);
      expect(send.busy, isFalse);
    });
  });

  test('the state never prints addresses', () async {
    final cubit = await confirming();
    expect(cubit.state.toString(), isNot(contains(_other)));
  });
}
```

Create `app/test/features/send/send_page_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/send_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
import 'package:digibyte_dex/domain/payment_uri.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/send/view/send_page.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/url_opener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_assets_repository.dart';
import '../../support/fake_biometric_store.dart';
import '../../support/fake_history_repository.dart';
import '../../support/fake_send_repository.dart';
import '../../support/fake_timers.dart';
import '../../support/fake_url_opener.dart';
import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/platform_channel_mock.dart';
import '../../support/pump_app.dart';
import '../../support/tx_views.dart';

const _pw = 'Correct-Horse-9';
// Dummies, not real addresses.
const _payee = 'DAbc1111111111111111111111111wxyz';
const _poison = 'DAbc2222222222222222222222222wxyz';
const _other = 'DQrs3333333333333333333333333tuvw';

void main() {
  late FakeWalletRepository wallet;
  late FakeSendRepository send;
  late FakeHistoryRepository history;
  late FakeAssetsRepository assets;
  late FakeBiometricStore biometrics;
  late FakeUrlOpener urls;
  late InMemoryKeyValueStore storage;
  late ClipboardGuard clipboard;
  late List<bool> secureFlags;
  late AuthCubit auth;
  late LockCubit lock;

  setUp(() {
    wallet = FakeWalletRepository();
    send = FakeSendRepository();
    history = FakeHistoryRepository();
    assets = FakeAssetsRepository();
    biometrics = FakeBiometricStore();
    urls = FakeUrlOpener();
    storage = InMemoryKeyValueStore();
    clipboard = ClipboardGuard(
      write: (_) async {},
      read: () async => null,
      timer: FakeTimers().create,
    );
    assets.refreshed['DGB'] = BalanceView(
      total: Decimal.one,
      spendable: Decimal.one,
    );
  });
  tearDown(() async {
    clipboard.dispose();
    await wallet.dispose();
  });

  // Cubits are created inside the test body, so their stream callbacks run
  // in the tester's fake-async zone.
  Future<void> pump(WidgetTester t, {PaymentUri? request}) async {
    secureFlags = [];
    mockPlatformChannel((call) async {
      if (call.method == 'setSecure') {
        secureFlags.add((call.arguments as Map)['secure'] as bool);
      }
      return null;
    });
    auth = AuthCubit(
      wallet,
      backups: BackupStatusStore(InMemoryKeyValueStore()),
    );
    lock = LockCubit(authStates: auth.stream);
    addTearDown(() async {
      await lock.close();
      await auth.close();
    });
    wallet.emit(null);
    await t.pump();
    wallet.emit(const WalletUser('main'));
    await t.pump();
    await pumpPage(
      t,
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<WalletRepository>.value(value: wallet),
          RepositoryProvider<SendRepository>.value(value: send),
          RepositoryProvider<HistoryRepository>.value(value: history),
          RepositoryProvider<AssetsRepository>.value(value: assets),
          RepositoryProvider<BiometricStore>.value(value: biometrics),
          RepositoryProvider<UrlOpener>.value(value: urls),
          RepositoryProvider.value(value: clipboard),
          RepositoryProvider.value(
            value: PasswordAttempts(LockoutStore(storage)),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: auth),
            BlocProvider.value(value: lock),
          ],
          child: SendPage(ticker: 'DGB', request: request),
        ),
      ),
      stubs: [Routes.asset('DGB')],
    );
  }

  /// Types into the address field and waits out the 400 ms check.
  Future<void> address(WidgetTester t, String text) async {
    await enterKey(t, 'send.address', text);
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
  }

  String? errorOf(WidgetTester t, String key) =>
      t.widget<TextField>(find.byKey(Key(key))).decoration?.errorText;

  Future<void> toConfirm(WidgetTester t, {String to = _other}) async {
    await address(t, to);
    await enterKey(t, 'send.amount', '1');
    await tapKey(t, 'send.next');
    await t.pump();
    await t.pump();
  }

  group('form', () {
    testWidgets('shows what is available and validates the address', (
      t,
    ) async {
      send.invalid = {_poison};
      await pump(t);
      expect(find.text('Available: 10 DGB'), findsOneWidget);
      await enterKey(t, 'send.address', _poison);
      expect(find.text('Checking the address…'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(errorOf(t, 'send.address'), 'Not a DigiByte address');
      await address(t, _other);
      expect(find.text('Address OK'), findsOneWidget);
    });

    testWidgets('amount hints, including the one-transaction limit', (
      t,
    ) async {
      await pump(t);
      await enterKey(t, 'send.amount', '1.123456789');
      expect(errorOf(t, 'send.amount'), 'Use at most 8 decimal places.');
      await enterKey(t, 'send.amount', '11');
      expect(
        errorOf(t, 'send.amount'),
        'Up to 10 DGB can be sent in one transaction. The rest is on other '
        'addresses.',
      );
      await enterKey(t, 'send.amount', '20');
      expect(errorOf(t, 'send.amount'), "That's more than your balance.");
    });

    testWidgets('Next stays off until the form is complete', (t) async {
      await pump(t);
      FilledButton next() =>
          t.widget<FilledButton>(find.byKey(const Key('send.next')));
      expect(next().onPressed, isNull);
      await address(t, _other);
      expect(next().onPressed, isNull);
      await enterKey(t, 'send.amount', '1');
      expect(next().onPressed, isNotNull);
    });

    testWidgets('Max fills the source balance', (t) async {
      await pump(t);
      await tapKey(t, 'send.max');
      expect(
        t
            .widget<TextField>(find.byKey(const Key('send.amount')))
            .controller
            ?.text,
        '10',
      );
    });

    testWidgets('a payment request prefills and shows its note', (t) async {
      await pump(
        t,
        request: PaymentUri(
          ticker: 'DGB',
          address: _other,
          amount: Decimal.parse('2'),
          label: 'Shop',
        ),
      );
      expect(
        t
            .widget<TextField>(find.byKey(const Key('send.address')))
            .controller
            ?.text,
        _other,
      );
      expect(find.text('Payment request note: Shop'), findsOneWidget);
    });

    testWidgets('a pasted URI for another coin is refused', (t) async {
      await pump(t);
      await enterKey(
        t,
        'send.address',
        'litecoin:ltc1qdummyaddress000000000000000000000',
      );
      expect(
        errorOf(t, 'send.address'),
        "That's a LTC payment request. Open LTC Send to pay it.",
      );
    });

    testWidgets('a preview error is shown on the form', (t) async {
      send.previewFailure = SendFailure.insufficientFunds;
      await pump(t);
      await toConfirm(t);
      expect(
        find.text(
          'Not enough funds for this amount plus the network fee. Try Max.',
        ),
        findsOneWidget,
      );
    });
  });

  group('confirm', () {
    testWidgets('shows the preview, grouped, on a secure screen', (t) async {
      await pump(t);
      await toConfirm(t);
      expect(
        t.widget<Text>(find.byKey(const Key('confirm.to'))).data,
        'DQrs 3333 3333 3333 3333 3333 3333 3tuv w',
      );
      expect(
        t.widget<Text>(find.byKey(const Key('confirm.fee'))).data,
        '0.0226 DGB',
      );
      expect(
        t.widget<Text>(find.byKey(const Key('confirm.total'))).data,
        '1.0226 DGB',
      );
      expect(secureFlags, [true]);
    });

    testWidgets('a look-alike needs "I\'ve checked the address" first', (
      t,
    ) async {
      history.recent = [_payee];
      await pump(t);
      await toConfirm(t, to: _poison);
      expect(find.byKey(const Key('confirm.lookalike')), findsOneWidget);
      expect(find.byKey(const Key('confirm.password')), findsNothing);
      expect(
        t.widget<FilledButton>(find.byKey(const Key('confirm.send'))).onPressed,
        isNull,
      );
      await tapKey(t, 'confirm.ack');
      expect(find.byKey(const Key('confirm.password')), findsOneWidget);
    });

    testWidgets('the password sends; the result links to the explorer', (
      t,
    ) async {
      await pump(t);
      await toConfirm(t);
      await enterKey(t, 'confirm.password', _pw);
      await tapKey(t, 'confirm.submit');
      await t.pump();
      await t.pump();
      expect(
        t.widget<Text>(find.byKey(const Key('result.txid'))).data,
        fakeTxid(1),
      );
      expect(secureFlags, [true, false]);
      await tapKey(t, 'result.explorer');
      await t.pump();
      expect(urls.opened, [
        Uri.parse('https://digiexplorer.info/tx/${fakeTxid(1)}'),
      ]);
      await tapKey(t, 'result.done');
      await t.pumpAndSettle();
      expect(find.text('route:${Routes.asset('DGB')}'), findsOneWidget);
    });

    testWidgets('a broadcast failure offers Back to edit', (t) async {
      send.broadcastFailure = SendFailure.network;
      await pump(t);
      await toConfirm(t);
      await enterKey(t, 'confirm.password', _pw);
      await tapKey(t, 'confirm.submit');
      await t.pump();
      await t.pump();
      expect(
        find.text("Couldn't reach the network. Try again."),
        findsOneWidget,
      );
      await tapKey(t, 'result.back');
      expect(find.byKey(const Key('send.next')), findsOneWidget);
      expect(send.busy, isFalse);
    });

    testWidgets('Back leaves Confirm and drops the preview', (t) async {
      await pump(t);
      await toConfirm(t);
      await tapKey(t, 'confirm.back');
      expect(find.byKey(const Key('send.next')), findsOneWidget);
      expect(send.released, hasLength(1));
    });

    testWidgets('a lock while confirming drops the preview', (t) async {
      await pump(t);
      await toConfirm(t);
      lock.lockNow();
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('send.next')), findsOneWidget);
      expect(send.released, hasLength(1));
      expect(send.busy, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/features/asset/asset_detail_page_test.dart \
  test/features/wallet/home_page_test.dart \
  test/app/app_scope_test.dart \
  test/app/router_test.dart \
  test/features/send/send_cubit_test.dart \
  test/features/send/send_page_test.dart
```

Expected: FAIL. Compile errors: `send_cubit.dart` and `send_page.dart` are missing, `Member not found: 'Routes.send'`, and `No named parameter with the name 'send'` in `AppServices`.

- [ ] **Step 3: Implement**

In `app/lib/features/asset/view/asset_detail_page.dart`, replace:

```dart
              Expanded(
                child: Tagged(
                  'asset.receive',
                  child: OutlinedButton.icon(
```

with:

```dart
              Expanded(
                child: Tagged(
                  'asset.send',
                  child: FilledButton.icon(
                    key: const Key('asset.send'),
                    onPressed: () =>
                        unawaited(context.push(Routes.send(ticker))),
                    icon: const Icon(Icons.north_east),
                    label: Text(l10n.sendAction),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Tagged(
                  'asset.receive',
                  child: OutlinedButton.icon(
```

In `app/lib/app/routes.dart`, replace:

```dart
  /// Balance, Send, Receive and history of one listed asset.
  static String asset(String ticker) => '/home/asset/$ticker';
}
```

with:

```dart
  /// Balance, Send, Receive and history of one listed asset.
  static String asset(String ticker) => '/home/asset/$ticker';

  /// Send one listed asset. A prefill travels as the route's `extra`,
  /// never in the URL.
  static String send(String ticker) => '/home/send/$ticker';
}
```

Edit `app/lib/app/router.dart` (3 replacements, top to bottom):

1. Replace:

```dart

import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/features/asset/view/asset_detail_page.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
```

   with:

```dart

import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/domain/payment_uri.dart';
import 'package:digibyte_dex/features/asset/view/asset_detail_page.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
```

2. Replace:

```dart
import 'package:digibyte_dex/features/onboarding/view/welcome_page.dart';
import 'package:digibyte_dex/features/receive/view/receive_page.dart';
import 'package:digibyte_dex/features/wallet/view/home_page.dart';
import 'package:flutter/material.dart';
```

   with:

```dart
import 'package:digibyte_dex/features/onboarding/view/welcome_page.dart';
import 'package:digibyte_dex/features/receive/view/receive_page.dart';
import 'package:digibyte_dex/features/send/view/send_page.dart';
import 'package:digibyte_dex/features/wallet/view/home_page.dart';
import 'package:flutter/material.dart';
```

3. Replace:

```dart
            AssetDetailPage(ticker: state.pathParameters['ticker']!),
      ),
    ],
  ),
```

   with:

```dart
            AssetDetailPage(ticker: state.pathParameters['ticker']!),
      ),
      GoRoute(
        path: 'send/:ticker',
        builder: (_, state) {
          final extra = state.extra;
          final request = extra is PaymentUri ? extra : null;
          // A new request is a new form: the key drops the old cubit.
          return SendPage(
            key: ObjectKey(request),
            ticker: state.pathParameters['ticker']!,
            request: request,
          );
        },
      ),
    ],
  ),
```


In `app/lib/features/wallet/view/home_page.dart`, replace:

```dart
        ),
      ),
      AssetActivationView.active => _Balance(id: id, balance: row.balance),
    };
    return Tagged(
```

with:

```dart
        ),
      ),
      AssetActivationView.active => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Balance(id: id, balance: row.balance),
          Tagged(
            '$id.send',
            child: IconButton(
              key: Key('$id.send'),
              tooltip: l10n.sendAction,
              icon: const Icon(Icons.north_east),
              onPressed: () => unawaited(context.push(Routes.send(row.ticker))),
            ),
          ),
        ],
      ),
    };
    return Tagged(
```

Edit `app/lib/app/app_scope.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
```

   with:

```dart
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/send_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
```

2. Replace:

```dart
    required this.receive,
    required this.history,
    required this.backups,
    required this.attempts,
```

   with:

```dart
    required this.receive,
    required this.history,
    required this.send,
    required this.backups,
    required this.attempts,
```

3. Replace:

```dart
  final ReceiveRepository receive;
  final HistoryRepository history;
  final BackupStatusStore backups;
  final PasswordAttempts attempts;
```

   with:

```dart
  final ReceiveRepository receive;
  final HistoryRepository history;
  final SendRepository send;
  final BackupStatusStore backups;
  final PasswordAttempts attempts;
```

4. Replace:

```dart
      RepositoryProvider<ReceiveRepository>.value(value: services.receive),
      RepositoryProvider<HistoryRepository>.value(value: services.history),
      RepositoryProvider.value(value: services.backups),
      RepositoryProvider.value(value: services.attempts),
```

   with:

```dart
      RepositoryProvider<ReceiveRepository>.value(value: services.receive),
      RepositoryProvider<HistoryRepository>.value(value: services.history),
      RepositoryProvider<SendRepository>.value(value: services.send),
      RepositoryProvider.value(value: services.backups),
      RepositoryProvider.value(value: services.attempts),
```


Edit `app/lib/main.dart` (2 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
```

   with:

```dart
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/send_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
```

2. Replace:

```dart
      receive: SdkReceiveRepository(sdk),
      history: SdkHistoryRepository(sdk),
      backups: BackupStatusStore(storage),
      attempts: PasswordAttempts(LockoutStore(storage)),
```

   with:

```dart
      receive: SdkReceiveRepository(sdk),
      history: SdkHistoryRepository(sdk),
      send: SdkSendRepository(sdk),
      backups: BackupStatusStore(storage),
      attempts: PasswordAttempts(LockoutStore(storage)),
```


`app_en.arb` grows at the end in every task that adds strings. The replacement below adds a comma to the current last entry and appends this task's entries.

In `app/lib/l10n/arb/app_en.arb`, replace:

```json
  "txIdCopied": "Transaction ID copied.",
  "viewInExplorer": "View in explorer",
  "explorerFailed": "Couldn't open the explorer."
}
```

with:

```json
  "txIdCopied": "Transaction ID copied.",
  "viewInExplorer": "View in explorer",
  "explorerFailed": "Couldn't open the explorer.",
  "sendAction": "Send",
  "sendTitle": "Send {ticker}",
  "@sendTitle": {"placeholders": {"ticker": {"type": "String"}}},
  "sendAddressLabel": "Recipient address",
  "sendAmountLabel": "Amount",
  "sendMax": "Max",
  "sendAvailable": "Available: {amount} {ticker}",
  "@sendAvailable": {"placeholders": {"amount": {"type": "String"}, "ticker": {"type": "String"}}},
  "sendNext": "Next",
  "sendSourceFailed": "Couldn't load your balance.",
  "sendNote": "Payment request note: {note}",
  "@sendNote": {"placeholders": {"note": {"type": "String"}}},
  "addressChecking": "Checking the address…",
  "addressValid": "Address OK",
  "addressInvalid": "Not a {ticker, select, DGB{DigiByte} BTC{Bitcoin} LTC{Litecoin} other{{ticker}}} address",
  "@addressInvalid": {"placeholders": {"ticker": {"type": "String"}}},
  "addressUnverified": "Couldn't check the address. Check your connection.",
  "addressWrongCoin": "That's a {other} payment request. Open {other} Send to pay it.",
  "@addressWrongCoin": {"placeholders": {"other": {"type": "String"}}},
  "amountMalformed": "Enter a number, like 12.5.",
  "amountTooPrecise": "Use at most 8 decimal places.",
  "amountBelowDust": "This amount is too small to send.",
  "amountOverSource": "Up to {amount} {ticker} can be sent in one transaction. The rest is on other addresses.",
  "@amountOverSource": {"placeholders": {"amount": {"type": "String"}, "ticker": {"type": "String"}}},
  "amountOverBalance": "That's more than your balance.",
  "sendFailureInsufficient": "Not enough funds for this amount plus the network fee. Try Max.",
  "sendFailureAmountTooLow": "This amount is too small to send.",
  "sendFailureInvalidAddress": "The wallet engine rejected this address.",
  "sendFailureFee": "Couldn't estimate the network fee. Try again.",
  "sendFailureNetwork": "Couldn't reach the network. Try again.",
  "sendFailureBusy": "Another send is still in progress.",
  "sendFailureUnknown": "Something went wrong. Try again.",
  "confirmTitle": "Confirm send",
  "confirmTo": "To",
  "confirmAmount": "Amount",
  "confirmFee": "Network fee",
  "confirmTotal": "Total",
  "confirmFrom": "From",
  "confirmLookalike": "This address looks like one you used before, but it is different. Compare every character.",
  "confirmLookalikeRecent": "Address you used before:",
  "confirmSelf": "This is one of your own addresses.",
  "confirmAck": "I've checked the address",
  "confirmSend": "Send",
  "confirmPassword": "Enter your password to send.",
  "confirmBack": "Back",
  "sendBiometricReason": "Confirm this send",
  "resultSentTitle": "Sent",
  "resultSentBody": "Your transaction was broadcast. It shows as pending until it is confirmed.",
  "resultDone": "Done",
  "resultFailedTitle": "Not sent",
  "resultFailedHint": "Check the history before you try again.",
  "resultBack": "Back to edit"
}
```

Create `app/lib/features/send/bloc/send_cubit.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/send_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/domain/address_safety.dart';
import 'package:digibyte_dex/domain/payment_uri.dart';
import 'package:digibyte_dex/domain/send_rules.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/domain/password_gate.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart' show TimerFactory;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';

/// The send flow (spec §7): editing → previewing → confirming →
/// authenticating → broadcasting → done or failed.
enum SendStep {
  editing,
  previewing,
  confirming,
  authenticating,
  broadcasting,
  done,
  failed,
}

enum AddressStatus {
  empty,
  checking,
  valid,
  invalid,

  /// The check itself failed; it can be retried.
  unverified,

  /// A payment request for another coin was pasted or scanned.
  wrongCoin,
}

/// Everything the send screens show. `stringify` is off: it holds
/// addresses, amounts and the signed preview.
class SendState extends Equatable {
  const SendState({
    required this.ticker,
    this.step = SendStep.editing,
    this.address = '',
    this.addressStatus = AddressStatus.empty,
    this.otherTicker,
    this.amount = '',
    this.isMax = false,
    this.note,
    this.source,
    this.sourceFailure,
    this.preview,
    this.warnings = const [],
    this.acknowledged = false,
    this.needPassword = false,
    this.gate = const PasswordGateState(),
    this.txid,
    this.failure,
    this.fieldRevision = 0,
  });

  final String ticker;
  final SendStep step;

  /// The destination as typed, or as taken from a payment request.
  final String address;
  final AddressStatus addressStatus;

  /// The coin of a rejected payment request ([AddressStatus.wrongCoin]).
  final String? otherTicker;
  final String amount;
  final bool isMax;

  /// The untrusted "Payment request note" (spec §5.3).
  final String? note;

  /// Null while loading, or after [sourceFailure].
  final SendSource? source;
  final SendFailure? sourceFailure;
  final SendPreview? preview;
  final List<AddressWarning> warnings;
  final bool acknowledged;

  /// The password field is shown (biometrics off, cancelled or failed).
  final bool needPassword;

  /// Re-authentication state: shared lockout and biometrics.
  final PasswordGateState gate;
  final String? txid;

  /// Why the last preview (editing) or broadcast (failed) did not work.
  final SendFailure? failure;

  /// Bumped when the cubit rewrites the fields (payment request, Max), so
  /// the page can update its text controllers.
  final int fieldRevision;

  bool get loadingSource => source == null && sourceFailure == null;

  /// What is wrong with the amount, once the source is known.
  AmountProblem? get amountProblem {
    final from = source;
    if (from == null) return null;
    if (isMax) return SendRules.checkMax(ticker, from.source.spendable);
    return SendRules.checkAmount(
      amount,
      ticker: ticker,
      source: from.source.spendable,
      total: from.total,
    );
  }

  bool get canPreview =>
      step == SendStep.editing &&
      addressStatus == AddressStatus.valid &&
      source != null &&
      amountProblem == null;

  bool get canSend =>
      step == SendStep.confirming &&
      preview != null &&
      (warnings.isEmpty || acknowledged);

  static const _keep = Object();

  SendState copyWith({
    SendStep? step,
    String? address,
    AddressStatus? addressStatus,
    Object? otherTicker = _keep,
    String? amount,
    bool? isMax,
    Object? note = _keep,
    Object? source = _keep,
    Object? sourceFailure = _keep,
    Object? preview = _keep,
    List<AddressWarning>? warnings,
    bool? acknowledged,
    bool? needPassword,
    PasswordGateState? gate,
    Object? txid = _keep,
    Object? failure = _keep,
    bool rewriteFields = false,
  }) => SendState(
    ticker: ticker,
    step: step ?? this.step,
    address: address ?? this.address,
    addressStatus: addressStatus ?? this.addressStatus,
    otherTicker: identical(otherTicker, _keep)
        ? this.otherTicker
        : otherTicker as String?,
    amount: amount ?? this.amount,
    isMax: isMax ?? this.isMax,
    note: identical(note, _keep) ? this.note : note as String?,
    source: identical(source, _keep) ? this.source : source as SendSource?,
    sourceFailure: identical(sourceFailure, _keep)
        ? this.sourceFailure
        : sourceFailure as SendFailure?,
    preview: identical(preview, _keep) ? this.preview : preview as SendPreview?,
    warnings: warnings ?? this.warnings,
    acknowledged: acknowledged ?? this.acknowledged,
    needPassword: needPassword ?? this.needPassword,
    gate: gate ?? this.gate,
    txid: identical(txid, _keep) ? this.txid : txid as String?,
    failure: identical(failure, _keep) ? this.failure : failure as SendFailure?,
    fieldRevision: rewriteFields ? fieldRevision + 1 : fieldRevision,
  );

  @override
  List<Object?> get props => [
    ticker,
    step,
    address,
    addressStatus,
    otherTicker,
    amount,
    isMax,
    note,
    source,
    sourceFailure,
    preview,
    warnings,
    acknowledged,
    needPassword,
    gate,
    txid,
    failure,
    fieldRevision,
  ];

  @override
  bool? get stringify => false;
}

/// Sends one listed asset (spec §3): the form, a signed preview, explicit
/// confirmation with re-authentication on every send (D2), broadcast.
///
/// The signed preview lives only here and in the repository's in-flight
/// guard. Leaving Confirm, a lock or sign-out ([discard], [close]) drops
/// it; it is never broadcast twice.
class SendCubit extends Cubit<SendState> {
  SendCubit({
    required String ticker,
    required this.walletName,
    required SendRepository send,
    required HistoryRepository history,
    required AssetsRepository assets,
    required WalletRepository wallet,
    required PasswordAttempts attempts,
    required BiometricStore biometrics,
    TimerFactory? timer,
    Duration debounce = const Duration(milliseconds: 400),
  }) : _send = send,
       _history = history,
       _assets = assets,
       _wallet = wallet,
       _timer = timer ?? Timer.new,
       _debounce = debounce,
       super(SendState(ticker: ticker)) {
    _gate = PasswordGate(
      attempts: attempts,
      biometrics: biometrics,
      read: () => state.gate,
      write: (gate) => _emit(state.copyWith(gate: gate)),
    );
  }

  final String walletName;
  final SendRepository _send;
  final HistoryRepository _history;
  final AssetsRepository _assets;
  final WalletRepository _wallet;
  final TimerFactory _timer;
  final Duration _debounce;
  late final PasswordGate _gate;
  Timer? _validation;

  String get ticker => state.ticker;

  /// Applies [request] (a payment link or scan), then loads the source
  /// address and balance.
  Future<void> init({PaymentUri? request}) async {
    if (request != null) applyRequest(request);
    await _loadSource();
  }

  Future<void> retrySource() async {
    _emit(state.copyWith(sourceFailure: null));
    await _loadSource();
  }

  Future<void> _loadSource() async {
    try {
      final source = await _send.source(ticker);
      _emit(state.copyWith(source: source, sourceFailure: null));
    } on SendException catch (e) {
      _emit(state.copyWith(sourceFailure: e.failure));
    }
  }

  /// The address field changed. A pasted payment URI fills the form.
  void addressChanged(String text) {
    if (state.step != SendStep.editing) return;
    final trimmed = text.trim();
    final request = trimmed.contains(':') ? PaymentUri.parse(trimmed) : null;
    if (request != null) {
      applyRequest(request);
      return;
    }
    _emit(state.copyWith(address: trimmed, otherTicker: null, failure: null));
    _scheduleValidation();
  }

  /// Fills the form from a payment request. One for another coin is
  /// refused with a message; it never switches coins silently.
  void applyRequest(PaymentUri request) {
    if (state.step != SendStep.editing) return;
    final other = request.ticker;
    if (other != null && other != ticker) {
      _validation?.cancel();
      _emit(
        state.copyWith(
          address: '',
          addressStatus: AddressStatus.wrongCoin,
          otherTicker: other,
          rewriteFields: true,
        ),
      );
      return;
    }
    final amount = request.amount;
    _emit(
      state.copyWith(
        address: request.address,
        otherTicker: null,
        amount: amount?.toString(),
        isMax: amount == null ? null : false,
        note: request.note,
        failure: null,
        rewriteFields: true,
      ),
    );
    _scheduleValidation();
  }

  /// Checks the address again after [AddressStatus.unverified].
  void recheckAddress() {
    if (state.step == SendStep.editing) _scheduleValidation();
  }

  void _scheduleValidation() {
    _validation?.cancel();
    final address = state.address;
    if (address.isEmpty) {
      _emit(state.copyWith(addressStatus: AddressStatus.empty));
      return;
    }
    _emit(state.copyWith(addressStatus: AddressStatus.checking));
    _validation = _timer(_debounce, () => unawaited(_validate(address)));
  }

  Future<void> _validate(String address) async {
    final check = await _send.validate(ticker, address);
    // A newer edit wins.
    if (isClosed || state.address != address) return;
    _emit(
      state.copyWith(
        addressStatus: switch (check) {
          AddressCheck.valid => AddressStatus.valid,
          AddressCheck.invalid => AddressStatus.invalid,
          AddressCheck.unverified => AddressStatus.unverified,
        },
      ),
    );
  }

  void amountChanged(String text) {
    if (state.step != SendStep.editing) return;
    _emit(state.copyWith(amount: text.trim(), isMax: false, failure: null));
  }

  /// Max: the source address's whole balance; KDF deducts the fee.
  void useMax() {
    final source = state.source;
    if (state.step != SendStep.editing || source == null) return;
    _emit(
      state.copyWith(
        amount: source.source.spendable.toString(),
        isMax: true,
        failure: null,
        rewriteFields: true,
      ),
    );
  }

  /// Next: builds and signs the transaction, then shows Confirm. Ignored
  /// unless the form is complete (a double tap is ignored).
  Future<void> next() async {
    if (!state.canPreview) return;
    final source = state.source!;
    _emit(state.copyWith(step: SendStep.previewing, failure: null));
    final SendPreview preview;
    try {
      preview = await _send.preview(
        SendRequest(
          ticker: ticker,
          toAddress: state.address,
          amount: state.isMax ? null : SendRules.parseAmount(state.amount),
        ),
        source,
      );
    } on SendException catch (e) {
      if (state.step == SendStep.previewing) {
        _emit(state.copyWith(step: SendStep.editing, failure: e.failure));
      }
      return;
    }
    final recent = [
      ...await _history.recentCounterparties(ticker),
      ..._send.sentTo(ticker),
    ];
    // Fresh re-authentication state for this confirmation.
    var gate = const PasswordGateState();
    _emit(state.copyWith(gate: gate));
    await _gate.load(walletName, (loaded) => gate = loaded);
    if (isClosed || state.step != SendStep.previewing) {
      // Discarded while signing (lock, Back, sign-out).
      _send.release(preview);
      return;
    }
    _emit(
      state.copyWith(
        step: SendStep.confirming,
        preview: preview,
        warnings: AddressSafety.check(
          destination: preview.toAddress,
          recent: recent,
          own: source.ownAddresses,
        ),
        acknowledged: false,
        needPassword: !gate.biometricsEnabled,
        // No biometric opt-in on Confirm: biometricsAvailable stays false.
        gate: PasswordGateState(
          failure: gate.failure,
          blockedUntil: gate.blockedUntil,
          biometricsEnabled: gate.biometricsEnabled,
        ),
      ),
    );
  }

  void acknowledge({required bool checked}) {
    if (state.step == SendStep.confirming) {
      _emit(state.copyWith(acknowledged: checked));
    }
  }

  /// Send on Confirm: biometrics when enabled, else the password field.
  Future<void> confirm({required String reason}) async {
    if (!state.canSend) return;
    if (!state.gate.biometricsEnabled) {
      _emit(state.copyWith(needPassword: true));
      return;
    }
    _emit(state.copyWith(step: SendStep.authenticating));
    final ok = await _gate.tryBiometrics(
      walletName,
      reason: reason,
      use: (_) async {},
    );
    if (isClosed || state.step != SendStep.authenticating) return;
    if (!ok) {
      // Cancelled or failed: fall back to the password.
      _emit(state.copyWith(step: SendStep.confirming, needPassword: true));
      return;
    }
    await _broadcast();
  }

  /// The password, checked against KDF through the shared lockout.
  Future<void> confirmWithPassword(String password) async {
    if (!state.canSend) return;
    _emit(state.copyWith(step: SendStep.authenticating));
    final ok = await _gate.tryPassword(
      walletName,
      password,
      check: _wallet.verifyPassword,
    );
    if (isClosed || state.step != SendStep.authenticating) return;
    if (!ok) {
      _emit(state.copyWith(step: SendStep.confirming));
      return;
    }
    await _broadcast();
  }

  Future<void> _broadcast() async {
    final preview = state.preview!;
    _emit(state.copyWith(step: SendStep.broadcasting));
    try {
      final txid = await _send.broadcast(preview);
      _emit(state.copyWith(step: SendStep.done, txid: txid));
      unawaited(_refreshAfterSend());
    } on SendException catch (e) {
      _emit(state.copyWith(step: SendStep.failed, failure: e.failure));
    }
  }

  /// The balance is force-refreshed and history syncs (spec §3.5).
  Future<void> _refreshAfterSend() async {
    try {
      await _assets.refreshBalance(ticker);
    } on Object catch (error) {
      debugPrint('Balance refresh failed: ${error.runtimeType}');
    }
    try {
      await _history.sync(ticker);
    } on Object catch (error) {
      debugPrint('History sync failed: ${error.runtimeType}');
    }
  }

  /// Back from Confirm or a failed broadcast: the preview is dropped and
  /// the form is kept. A retry signs a fresh one.
  void backToEdit() {
    if (state.step != SendStep.confirming && state.step != SendStep.failed) {
      return;
    }
    _toEditing(failure: null);
  }

  /// A lock or sign-out: drops the preview unless it is already being
  /// broadcast.
  void discard() {
    switch (state.step) {
      case SendStep.previewing:
      case SendStep.confirming:
      case SendStep.authenticating:
        _toEditing(failure: state.failure);
      case SendStep.editing:
      case SendStep.broadcasting:
      case SendStep.done:
      case SendStep.failed:
        break;
    }
  }

  void _toEditing({required SendFailure? failure}) {
    final preview = state.preview;
    if (preview != null) _send.release(preview);
    _emit(
      state.copyWith(
        step: SendStep.editing,
        preview: null,
        warnings: const [],
        acknowledged: false,
        needPassword: false,
        gate: const PasswordGateState(),
        failure: failure,
      ),
    );
  }

  void lockoutExpired() => _gate.lockoutExpired();

  void _emit(SendState next) {
    if (!isClosed) emit(next);
  }

  @override
  Future<void> close() {
    _validation?.cancel();
    final preview = state.preview;
    if (preview != null && state.step != SendStep.broadcasting) {
      _send.release(preview);
    }
    return super.close();
  }
}
```

Create `app/lib/features/send/view/send_page.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/send_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/domain/payment_uri.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/send/bloc/send_cubit.dart';
import 'package:digibyte_dex/features/send/view/send_confirm_view.dart';
import 'package:digibyte_dex/features/send/view/send_form_view.dart';
import 'package:digibyte_dex/features/send/view/send_result_view.dart';
import 'package:digibyte_dex/widgets/secure_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Send one listed asset (spec §3): form, Confirm, Result. [request]
/// prefills the form from a payment link or QR code; it never sends.
class SendPage extends StatelessWidget {
  const SendPage({required this.ticker, this.request, super.key});

  final String ticker;
  final PaymentUri? request;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthCubit>().state;
    return BlocProvider(
      create: (context) {
        final cubit = SendCubit(
          ticker: ticker,
          walletName: auth is AuthSignedIn ? auth.user.name : '',
          send: context.read<SendRepository>(),
          history: context.read<HistoryRepository>(),
          assets: context.read<AssetsRepository>(),
          wallet: context.read<WalletRepository>(),
          attempts: context.read<PasswordAttempts>(),
          biometrics: context.read<BiometricStore>(),
        );
        unawaited(cubit.init(request: request));
        return cubit;
      },
      child: const _SendView(),
    );
  }
}

class _SendView extends StatelessWidget {
  const _SendView();

  @override
  Widget build(BuildContext context) => BlocListener<LockCubit, AppLockState>(
    // A lock discards the signed preview (spec §3.7).
    listener: (context, lock) {
      if (lock is Locked) context.read<SendCubit>().discard();
    },
    child: BlocBuilder<SendCubit, SendState>(
      buildWhen: (a, b) => a.step != b.step,
      builder: (context, state) {
        final cubit = context.read<SendCubit>();
        return PopScope(
          canPop: state.step == SendStep.editing,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            switch (state.step) {
              case SendStep.confirming:
              case SendStep.failed:
                cubit.backToEdit();
              case SendStep.done:
                context.go(Routes.asset(cubit.ticker));
              case SendStep.editing:
              case SendStep.previewing:
              case SendStep.authenticating:
              case SendStep.broadcasting:
                break;
            }
          },
          child: switch (state.step) {
            SendStep.editing || SendStep.previewing => const SendFormView(),
            SendStep.confirming ||
            SendStep.authenticating ||
            SendStep.broadcasting => const SecureScreen(
              child: SendConfirmView(),
            ),
            SendStep.done || SendStep.failed => const SendResultView(),
          },
        );
      },
    ),
  );
}
```

Create `app/lib/features/send/view/send_form_view.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/features/send/bloc/send_cubit.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/l10n/send_messages.dart';
import 'package:digibyte_dex/widgets/busy_indicator.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The send form (spec §3.2): address, amount with Max, Next.
class SendFormView extends StatefulWidget {
  const SendFormView({super.key});

  @override
  State<SendFormView> createState() => _SendFormViewState();
}

class _SendFormViewState extends State<SendFormView> {
  late final TextEditingController _address;
  late final TextEditingController _amount;

  @override
  void initState() {
    super.initState();
    final state = context.read<SendCubit>().state;
    _address = TextEditingController(text: state.address);
    _amount = TextEditingController(text: state.amount);
  }

  @override
  void dispose() {
    _address.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _syncFields(SendState state) {
    if (_address.text != state.address) _address.text = state.address;
    if (_amount.text != state.amount) _amount.text = state.amount;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<SendCubit>();
    return BlocConsumer<SendCubit, SendState>(
      listenWhen: (a, b) => a.fieldRevision != b.fieldRevision,
      listener: (context, state) => _syncFields(state),
      builder: (context, state) {
        final busy = state.step == SendStep.previewing;
        final source = state.source;
        return Scaffold(
          appBar: AppBar(title: Text(l10n.sendTitle(state.ticker))),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Tagged(
                  'send.address',
                  child: TextField(
                    key: const Key('send.address'),
                    controller: _address,
                    enabled: !busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    onTapOutside: unfocusOnTapOutside,
                    onChanged: cubit.addressChanged,
                    decoration: InputDecoration(
                      labelText: l10n.sendAddressLabel,
                      errorMaxLines: 3,
                      errorText: _addressError(l10n, state),
                      helperText: _addressHelper(l10n, state),
                    ),
                  ),
                ),
                if (state.addressStatus == AddressStatus.unverified)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Tagged(
                      'send.recheck',
                      child: TextButton(
                        key: const Key('send.recheck'),
                        onPressed: cubit.recheckAddress,
                        child: Text(l10n.retry),
                      ),
                    ),
                  ),
                if (state.note case final note?) ...[
                  const SizedBox(height: 12),
                  Tagged(
                    'send.note',
                    child: Text(
                      l10n.sendNote(note),
                      key: const Key('send.note'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Tagged(
                  'send.amount',
                  child: TextField(
                    key: const Key('send.amount'),
                    controller: _amount,
                    enabled: !busy && source != null,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
                    ],
                    onTapOutside: unfocusOnTapOutside,
                    onChanged: cubit.amountChanged,
                    decoration: InputDecoration(
                      labelText: l10n.sendAmountLabel,
                      suffixText: state.ticker,
                      errorMaxLines: 3,
                      errorText: source == null
                          ? null
                          : state.amountProblem?.message(
                              l10n,
                              ticker: state.ticker,
                              sourceAmount: source.source.spendable.toString(),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _Available(state: state)),
                    Tagged(
                      'send.max',
                      child: TextButton(
                        key: const Key('send.max'),
                        onPressed: busy || source == null ? null : cubit.useMax,
                        child: Text(l10n.sendMax),
                      ),
                    ),
                  ],
                ),
                if (state.failure case final failure?) ...[
                  const SizedBox(height: 12),
                  Tagged(
                    'send.error',
                    child: Text(
                      failure.message(l10n),
                      key: const Key('send.error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Tagged(
                  'send.next',
                  child: FilledButton(
                    key: const Key('send.next'),
                    onPressed: state.canPreview
                        ? () => unawaited(cubit.next())
                        : null,
                    child: busy
                        ? const BusyIndicator('send.busy')
                        : Text(l10n.sendNext),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _addressError(AppLocalizations l10n, SendState state) =>
      switch (state.addressStatus) {
        AddressStatus.invalid => l10n.addressInvalid(state.ticker),
        AddressStatus.unverified => l10n.addressUnverified,
        AddressStatus.wrongCoin => l10n.addressWrongCoin(
          state.otherTicker ?? '',
        ),
        AddressStatus.empty ||
        AddressStatus.checking ||
        AddressStatus.valid => null,
      };

  String? _addressHelper(AppLocalizations l10n, SendState state) =>
      switch (state.addressStatus) {
        AddressStatus.checking => l10n.addressChecking,
        AddressStatus.valid => l10n.addressValid,
        AddressStatus.empty ||
        AddressStatus.invalid ||
        AddressStatus.unverified ||
        AddressStatus.wrongCoin => null,
      };
}

class _Available extends StatelessWidget {
  const _Available({required this.state});

  final SendState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final source = state.source;
    if (source != null) {
      return Tagged(
        'send.available',
        child: Text(
          l10n.sendAvailable(source.source.spendable.toString(), state.ticker),
          key: const Key('send.available'),
        ),
      );
    }
    if (state.sourceFailure != null) {
      return Row(
        children: [
          Flexible(child: Text(l10n.sendSourceFailed)),
          Tagged(
            'send.retrySource',
            child: TextButton(
              key: const Key('send.retrySource'),
              onPressed: () =>
                  unawaited(context.read<SendCubit>().retrySource()),
              child: Text(l10n.retry),
            ),
          ),
        ],
      );
    }
    return Text(l10n.balanceLoading);
  }
}
```

Create `app/lib/features/send/view/send_confirm_view.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/domain/address_safety.dart';
import 'package:digibyte_dex/features/auth/widgets/password_gate_form.dart';
import 'package:digibyte_dex/features/send/bloc/send_cubit.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/widgets/busy_indicator.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Confirm (spec §3.4): every number from the signed preview, the
/// address-safety warnings with their acknowledgement, and
/// re-authentication on every send.
class SendConfirmView extends StatelessWidget {
  const SendConfirmView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<SendCubit>();
    return BlocBuilder<SendCubit, SendState>(
      builder: (context, state) {
        final preview = state.preview;
        if (preview == null) return const SizedBox.shrink();
        final ticker = state.ticker;
        final working = state.step != SendStep.confirming;
        // The password form appears once any warning is acknowledged.
        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.confirmTitle),
            automaticallyImplyLeading: false,
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _Line(
                  id: 'confirm.to',
                  label: l10n.confirmTo,
                  value: AddressSafety.groups(preview.toAddress).join(' '),
                  monospace: true,
                ),
                _Line(
                  id: 'confirm.amount',
                  label: l10n.confirmAmount,
                  value: '${preview.amount} $ticker',
                ),
                _Line(
                  id: 'confirm.fee',
                  label: l10n.confirmFee,
                  value: '${preview.fee} $ticker',
                ),
                _Line(
                  id: 'confirm.total',
                  label: l10n.confirmTotal,
                  value: '${preview.total} $ticker',
                ),
                _Line(
                  id: 'confirm.from',
                  label: l10n.confirmFrom,
                  value: AddressSafety.groups(preview.fromAddress).join(' '),
                  monospace: true,
                ),
                for (final warning in state.warnings)
                  _Warning(warning: warning, destination: preview.toAddress),
                if (state.warnings.isNotEmpty)
                  Tagged(
                    'confirm.ack',
                    child: CheckboxListTile(
                      key: const Key('confirm.ack'),
                      contentPadding: EdgeInsets.zero,
                      value: state.acknowledged,
                      onChanged: working
                          ? null
                          : (value) =>
                                cubit.acknowledge(checked: value ?? false),
                      title: Text(l10n.confirmAck),
                    ),
                  ),
                const SizedBox(height: 24),
                if (state.needPassword &&
                    (state.warnings.isEmpty || state.acknowledged)) ...[
                  Text(l10n.confirmPassword),
                  const SizedBox(height: 8),
                  PasswordGateForm(
                    idPrefix: 'confirm',
                    state: state.gate,
                    submitLabel: l10n.confirmSend,
                    onSubmit: (password, {required enableBiometrics}) =>
                        unawaited(cubit.confirmWithPassword(password)),
                    onBiometrics: () => unawaited(
                      cubit.confirm(reason: l10n.sendBiometricReason),
                    ),
                    onLockoutExpired: cubit.lockoutExpired,
                  ),
                ] else
                  Tagged(
                    'confirm.send',
                    child: FilledButton(
                      key: const Key('confirm.send'),
                      onPressed: state.canSend
                          ? () => unawaited(
                              cubit.confirm(reason: l10n.sendBiometricReason),
                            )
                          : null,
                      child: working
                          ? const BusyIndicator('confirm.busy')
                          : Text(l10n.confirmSend),
                    ),
                  ),
                const SizedBox(height: 12),
                Tagged(
                  'confirm.back',
                  child: TextButton(
                    key: const Key('confirm.back'),
                    onPressed: working ? null : cubit.backToEdit,
                    child: Text(l10n.confirmBack),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.id,
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String id;
  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.bodySmall),
          Tagged(
            id,
            child: Text(
              value,
              key: Key(id),
              style: monospace
                  ? theme.titleMedium?.copyWith(fontFamily: 'monospace')
                  : theme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.warning, required this.destination});

  final AddressWarning warning;
  final String destination;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final (id, children) = switch (warning) {
      LookalikeWarning(:final recent) => (
        'confirm.lookalike',
        <Widget>[
          Text(l10n.confirmLookalike),
          const SizedBox(height: 8),
          _Highlighted(address: destination, other: recent),
          const SizedBox(height: 8),
          Text(l10n.confirmLookalikeRecent),
          _Highlighted(address: recent, other: destination),
        ],
      ),
      OwnAddressWarning() => ('confirm.self', <Widget>[Text(l10n.confirmSelf)]),
    };
    return Tagged(
      id,
      child: Card(
        key: Key(id),
        color: scheme.errorContainer,
        margin: const EdgeInsets.only(top: 16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// [address] in groups of 4, the groups that differ from [other] in bold
/// and underlined.
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.address, required this.other});

  final String address;
  final String other;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(
      context,
    ).style.copyWith(fontFamily: 'monospace');
    final differs = AddressSafety.differingGroups(address, other);
    final groups = AddressSafety.groups(address);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (var i = 0; i < groups.length; i++)
            TextSpan(
              text: i == groups.length - 1 ? groups[i] : '${groups[i]} ',
              style: differs.contains(i)
                  ? const TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}
```

Create `app/lib/features/send/view/send_result_view.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/config/explorers.dart';
import 'package:digibyte_dex/data/repositories/send_repository.dart';
import 'package:digibyte_dex/features/asset/view/tx_detail_sheet.dart';
import 'package:digibyte_dex/features/send/bloc/send_cubit.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/l10n/send_messages.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Result (spec §3.5): the txid with copy and explorer, or the broadcast
/// failure with Back to edit.
class SendResultView extends StatelessWidget {
  const SendResultView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<SendCubit>();
    final state = cubit.state;
    final txid = state.txid;
    final done = state.step == SendStep.done && txid != null;
    final explorer = txid == null ? null : Explorers.tx(state.ticker, txid);
    return Scaffold(
      appBar: AppBar(
        title: Text(done ? l10n.resultSentTitle : l10n.resultFailedTitle),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              done ? Icons.check_circle_outline : Icons.error_outline,
              size: 64,
            ),
            const SizedBox(height: 16),
            if (done) ...[
              Text(l10n.resultSentBody, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(
                l10n.txIdLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Tagged(
                'result.txid',
                child: Text(
                  txid,
                  key: const Key('result.txid'),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Tagged(
                      'result.copy',
                      child: OutlinedButton.icon(
                        key: const Key('result.copy'),
                        onPressed: () => unawaited(_copy(context, txid)),
                        icon: const Icon(Icons.copy),
                        label: Text(l10n.copy),
                      ),
                    ),
                  ),
                  if (explorer != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Tagged(
                        'result.explorer',
                        child: OutlinedButton.icon(
                          key: const Key('result.explorer'),
                          onPressed: () =>
                              unawaited(openExplorer(context, explorer)),
                          icon: const Icon(Icons.open_in_new),
                          label: Text(l10n.viewInExplorer),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              Tagged(
                'result.done',
                child: FilledButton(
                  key: const Key('result.done'),
                  onPressed: () => context.go(Routes.asset(state.ticker)),
                  child: Text(l10n.resultDone),
                ),
              ),
            ] else ...[
              Tagged(
                'result.error',
                child: Text(
                  (state.failure ?? SendFailure.unknown).message(l10n),
                  key: const Key('result.error'),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Text(l10n.resultFailedHint, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Tagged(
                'result.back',
                child: FilledButton(
                  key: const Key('result.back'),
                  onPressed: cubit.backToEdit,
                  child: Text(l10n.resultBack),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context, String txid) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    var message = l10n.txIdCopied;
    try {
      await context.read<ClipboardGuard>().copy(txid);
    } on Object {
      message = l10n.copyFailed;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
```

Create `app/lib/l10n/send_messages.dart`:

```dart
import 'package:digibyte_dex/data/repositories/send_repository.dart';
import 'package:digibyte_dex/domain/send_rules.dart';
import 'package:digibyte_dex/l10n/l10n.dart';

extension SendFailureMessage on SendFailure {
  String message(AppLocalizations l10n) => switch (this) {
    SendFailure.insufficientFunds => l10n.sendFailureInsufficient,
    SendFailure.amountTooLow => l10n.sendFailureAmountTooLow,
    SendFailure.invalidAddress => l10n.sendFailureInvalidAddress,
    SendFailure.feeUnavailable => l10n.sendFailureFee,
    SendFailure.network => l10n.sendFailureNetwork,
    SendFailure.busy => l10n.sendFailureBusy,
    SendFailure.unknown => l10n.sendFailureUnknown,
  };
}

extension AmountProblemMessage on AmountProblem {
  /// Null for [AmountProblem.empty]: an empty field needs no error.
  String? message(
    AppLocalizations l10n, {
    required String ticker,
    required String sourceAmount,
  }) => switch (this) {
    AmountProblem.empty => null,
    AmountProblem.malformed => l10n.amountMalformed,
    AmountProblem.tooPrecise => l10n.amountTooPrecise,
    AmountProblem.belowDust => l10n.amountBelowDust,
    AmountProblem.overSource => l10n.amountOverSource(sourceAmount, ticker),
    AmountProblem.overBalance => l10n.amountOverBalance,
  };
}
```

Then regenerate the localizations:

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter gen-l10n
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/features/asset/asset_detail_page_test.dart \
  test/features/wallet/home_page_test.dart \
  test/app/app_scope_test.dart \
  test/app/router_test.dart \
  test/features/send/send_cubit_test.dart \
  test/features/send/send_page_test.dart
```

Expected: `+76: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```

Expected: the formatter changes 0 files; `No issues found!`; `+513: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/app/app_scope.dart \
  lib/app/router.dart \
  lib/app/routes.dart \
  lib/features/asset/view/asset_detail_page.dart \
  lib/features/send/bloc/send_cubit.dart \
  lib/features/send/view/send_confirm_view.dart \
  lib/features/send/view/send_form_view.dart \
  lib/features/send/view/send_page.dart \
  lib/features/send/view/send_result_view.dart \
  lib/features/wallet/view/home_page.dart \
  lib/l10n/arb/app_en.arb \
  lib/l10n/send_messages.dart \
  lib/main.dart \
  test/app/app_scope_test.dart \
  test/app/router_test.dart \
  test/features/asset/asset_detail_page_test.dart \
  test/features/send/send_cubit_test.dart \
  test/features/send/send_page_test.dart \
  test/features/wallet/home_page_test.dart \
  test/support/test_app.dart
git commit -m "feat(send): send flow with signed-preview Confirm, re-authentication and Result" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 6: QR scanner: `mobile_scanner` page and scan-result handling

Spec §5.2. The scanner is a full-screen page at `/home/scan` that pops with the first readable QR code; it runs on-device and offline (bundled ML Kit on Android, Vision on iOS) and uses the existing `CAMERA` permission. The Send form's scan button (`send.scan`) handles the result: the same coin (or a bare address) fills the form; another coin asks before opening that coin's Send; anything else says "Not a payment code". The camera page is behind `QrScanner`, so widget tests use `FakeQrScanner`.

**Files:**
- Create: `app/lib/features/send/scan_outcome.dart`
- Create: `app/lib/platform/qr_scanner.dart`
- Create: `app/test/support/fake_qr_scanner.dart`
- Create: `app/lib/features/send/view/scan_page.dart`
- Modify: `app/lib/app/routes.dart`
- Modify: `app/lib/app/router.dart`
- Modify: `app/lib/app/app_scope.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/test/support/test_app.dart`
- Modify: `app/lib/l10n/arb/app_en.arb`
- Modify: `app/lib/features/send/view/send_form_view.dart`
- Test (modify): `app/test/app/app_scope_test.dart`
- Test (modify): `app/test/app/router_test.dart`
- Test (modify): `app/test/features/send/send_page_test.dart`
- Test (create): `app/test/features/send/scan_outcome_test.dart`

**Interfaces:**
- Consumes: Task 1 `PaymentUri`; Task 5 `SendCubit.applyRequest`, `SendCubit.ticker`, `Routes.send`.
- Produces:
  - `sealed class ScanOutcome { factory ScanOutcome.of(String raw, {required String ticker}); }` with `final class SameCoin(PaymentUri request)`, `final class OtherCoin(PaymentUri request) { String get ticker; }`, `final class NotPaymentCode()`.
  - `class QrScanner { const QrScanner(); Future<String?> scan(BuildContext context); }` — pushes `Routes.scan` and returns what the page pops.
  - `class ScanPage extends StatefulWidget` (`MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: [BarcodeFormat.qrCode])`, torch, cancel).
  - `Routes.scan` = `/home/scan`; `AppServices` gains `required QrScanner scanner`.
  - Widget ids: `send.scan`, `scan.torch`, `scan.cancel`, `scan.stay`, `scan.open`.
- Test support: `FakeQrScanner` (`next`, `scans`); `TestApp.scanner`.

- [ ] **Step 1: Write the failing tests**

Edit `app/test/support/test_app.dart` (3 replacements, top to bottom):

1. Replace:

```dart
import 'fake_biometric_store.dart';
import 'fake_history_repository.dart';
import 'fake_receive_repository.dart';
import 'fake_seed_validator.dart';
```

   with:

```dart
import 'fake_biometric_store.dart';
import 'fake_history_repository.dart';
import 'fake_qr_scanner.dart';
import 'fake_receive_repository.dart';
import 'fake_seed_validator.dart';
```

2. Replace:

```dart
  final send = FakeSendRepository();
  final urls = FakeUrlOpener();
  final clipboardWrites = <String>[];

```

   with:

```dart
  final send = FakeSendRepository();
  final urls = FakeUrlOpener();
  final scanner = FakeQrScanner();
  final clipboardWrites = <String>[];

```

3. Replace:

```dart
    sharer: sharer,
    urls: urls,
    session: session,
  );
```

   with:

```dart
    sharer: sharer,
    urls: urls,
    scanner: scanner,
    session: session,
  );
```


Edit `app/test/app/app_scope_test.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:digibyte_dex/platform/url_opener.dart';
```

   with:

```dart
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/qr_scanner.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:digibyte_dex/platform/url_opener.dart';
```

2. Replace:

```dart
import '../support/fake_biometric_store.dart';
import '../support/fake_history_repository.dart';
import '../support/fake_receive_repository.dart';
import '../support/fake_seed_validator.dart';
```

   with:

```dart
import '../support/fake_biometric_store.dart';
import '../support/fake_history_repository.dart';
import '../support/fake_qr_scanner.dart';
import '../support/fake_receive_repository.dart';
import '../support/fake_seed_validator.dart';
```

3. Replace:

```dart
      sharer: FakeTextSharer(),
      urls: FakeUrlOpener(),
    );
  });
```

   with:

```dart
      sharer: FakeTextSharer(),
      urls: FakeUrlOpener(),
      scanner: FakeQrScanner(),
    );
  });
```

4. Replace:

```dart
    expect(probe.read<SendRepository>(), same(services.send));
    expect(probe.read<UrlOpener>(), same(services.urls));
    expect(probe.read<AuthCubit>(), same(cubits.auth));
    expect(probe.read<LockCubit>(), same(cubits.lock));
```

   with:

```dart
    expect(probe.read<SendRepository>(), same(services.send));
    expect(probe.read<UrlOpener>(), same(services.urls));
    expect(probe.read<QrScanner>(), same(services.scanner));
    expect(probe.read<AuthCubit>(), same(cubits.auth));
    expect(probe.read<LockCubit>(), same(cubits.lock));
```


In `app/test/app/router_test.dart`, replace:

```dart
      '/home/asset/DGB',
      '/home/send/DGB',
      '/nonexistent',
      '',
```

with:

```dart
      '/home/asset/DGB',
      '/home/send/DGB',
      '/home/scan',
      '/nonexistent',
      '',
```

Edit `app/test/features/send/send_page_test.dart` (7 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/features/send/view/send_page.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/url_opener.dart';
import 'package:flutter/material.dart';
```

   with:

```dart
import 'package:digibyte_dex/features/send/view/send_page.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/qr_scanner.dart';
import 'package:digibyte_dex/platform/url_opener.dart';
import 'package:flutter/material.dart';
```

2. Replace:

```dart
import '../../support/fake_biometric_store.dart';
import '../../support/fake_history_repository.dart';
import '../../support/fake_send_repository.dart';
import '../../support/fake_timers.dart';
```

   with:

```dart
import '../../support/fake_biometric_store.dart';
import '../../support/fake_history_repository.dart';
import '../../support/fake_qr_scanner.dart';
import '../../support/fake_send_repository.dart';
import '../../support/fake_timers.dart';
```

3. Replace:

```dart
  late FakeBiometricStore biometrics;
  late FakeUrlOpener urls;
  late InMemoryKeyValueStore storage;
  late ClipboardGuard clipboard;
```

   with:

```dart
  late FakeBiometricStore biometrics;
  late FakeUrlOpener urls;
  late FakeQrScanner scanner;
  late InMemoryKeyValueStore storage;
  late ClipboardGuard clipboard;
```

4. Replace:

```dart
    biometrics = FakeBiometricStore();
    urls = FakeUrlOpener();
    storage = InMemoryKeyValueStore();
    clipboard = ClipboardGuard(
```

   with:

```dart
    biometrics = FakeBiometricStore();
    urls = FakeUrlOpener();
    scanner = FakeQrScanner();
    storage = InMemoryKeyValueStore();
    clipboard = ClipboardGuard(
```

5. Replace:

```dart
          RepositoryProvider<BiometricStore>.value(value: biometrics),
          RepositoryProvider<UrlOpener>.value(value: urls),
          RepositoryProvider.value(value: clipboard),
          RepositoryProvider.value(
```

   with:

```dart
          RepositoryProvider<BiometricStore>.value(value: biometrics),
          RepositoryProvider<UrlOpener>.value(value: urls),
          RepositoryProvider<QrScanner>.value(value: scanner),
          RepositoryProvider.value(value: clipboard),
          RepositoryProvider.value(
```

6. Replace:

```dart
        ),
      ),
      stubs: [Routes.asset('DGB')],
    );
  }
```

   with:

```dart
        ),
      ),
      stubs: [Routes.asset('DGB'), Routes.send('BTC')],
    );
  }
```

7. Replace:

```dart
    });
  });
}
```

   with:

```dart
    });
  });

  group('QR scan', () {
    String fieldText(WidgetTester t, String key) =>
        t.widget<TextField>(find.byKey(Key(key))).controller!.text;

    testWidgets('a code for this coin fills address and amount', (t) async {
      scanner.next = 'digibyte:$_other?amount=2';
      await pump(t);
      await tapKey(t, 'send.scan');
      await t.pump();
      expect(fieldText(t, 'send.address'), _other);
      expect(fieldText(t, 'send.amount'), '2');
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(find.text('Address OK'), findsOneWidget);
    });

    testWidgets('a code for another coin asks; Cancel stays here', (t) async {
      scanner.next = 'bitcoin:bc1qdummyaddress0000000000000000000000';
      await pump(t);
      await tapKey(t, 'send.scan');
      await t.pumpAndSettle();
      expect(
        find.text('This is a Bitcoin address. Open BTC send?'),
        findsOneWidget,
      );
      await tapKey(t, 'scan.stay');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('send.next')), findsOneWidget);
      expect(fieldText(t, 'send.address'), isEmpty);
    });

    testWidgets('Open switches to that coin, prefilled', (t) async {
      scanner.next = 'bitcoin:bc1qdummyaddress0000000000000000000000';
      await pump(t);
      await tapKey(t, 'send.scan');
      await t.pumpAndSettle();
      await tapKey(t, 'scan.open');
      await t.pumpAndSettle();
      expect(find.text('route:${Routes.send('BTC')}'), findsOneWidget);
    });

    testWidgets('anything else is not a payment code', (t) async {
      scanner.next = 'hello';
      await pump(t);
      await tapKey(t, 'send.scan');
      await t.pump();
      expect(find.text('Not a payment code'), findsOneWidget);
    });

    testWidgets('a cancelled scan changes nothing', (t) async {
      await pump(t);
      await tapKey(t, 'send.scan');
      await t.pump();
      expect(scanner.scans, 1);
      expect(fieldText(t, 'send.address'), isEmpty);
    });
  });
}
```


Create `app/test/features/send/scan_outcome_test.dart`:

```dart
import 'package:digibyte_dex/features/send/scan_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

// Shape-valid dummies, not real addresses.
const _dgb = 'DDummyAddress000000000000000000001';
const _btc = 'bc1qdummyaddress0000000000000000000000';

void main() {
  test('a URI for this coin fills the form', () {
    final outcome = ScanOutcome.of('digibyte:$_dgb?amount=1', ticker: 'DGB');
    expect(outcome, isA<SameCoin>());
    expect((outcome as SameCoin).request.address, _dgb);
  });

  test('a bare address fills the form; validation decides', () {
    expect(ScanOutcome.of(_btc, ticker: 'DGB'), isA<SameCoin>());
  });

  test('a URI for another coin asks first', () {
    final outcome = ScanOutcome.of('bitcoin:$_btc', ticker: 'DGB');
    expect(outcome, isA<OtherCoin>());
    expect((outcome as OtherCoin).ticker, 'BTC');
  });

  test('anything else is not a payment code', () {
    for (final raw in [
      'hello',
      'https://example.com',
      'digibyte:$_dgb?req-x=1',
    ]) {
      expect(ScanOutcome.of(raw, ticker: 'DGB'), isA<NotPaymentCode>());
    }
  });
}
```

Create `app/test/support/fake_qr_scanner.dart`:

```dart
import 'package:digibyte_dex/platform/qr_scanner.dart';
import 'package:flutter/widgets.dart';

/// Returns [next] instead of opening the camera.
class FakeQrScanner implements QrScanner {
  String? next;
  int scans = 0;

  @override
  Future<String?> scan(BuildContext context) async {
    scans++;
    return next;
  }
}
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/app/app_scope_test.dart \
  test/app/router_test.dart \
  test/features/send/send_page_test.dart \
  test/features/send/scan_outcome_test.dart
```

Expected: FAIL. Compile errors: `scan_outcome.dart` and `qr_scanner.dart` are missing, and `No named parameter with the name 'scanner'` in `AppServices`.

- [ ] **Step 3: Implement**

First add the dependency (already resolved transitively at 7.4.2; this makes it direct):

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter pub add 'mobile_scanner:^7.4.2'
grep -n '^  mobile_scanner:' pubspec.yaml
```
Expected: `mobile_scanner: ^7.4.2` under `dependencies` (after `local_auth`); `pubspec.lock` marks it `direct main`, version 7.4.2. Its Android manifest declares only `CAMERA` (already allowed); its iOS target is 12.0, below the app's 13.0.

In `app/lib/app/routes.dart`, replace:

```dart
  static const home = '/home';

  /// The receive screen of one listed asset.
  static String receive(String ticker) => '/home/receive/$ticker';
```

with:

```dart
  static const home = '/home';

  /// The QR scanner; it pops with the scanned text.
  static const scan = '/home/scan';

  /// The receive screen of one listed asset.
  static String receive(String ticker) => '/home/receive/$ticker';
```

Edit `app/lib/app/router.dart` (2 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/features/onboarding/view/welcome_page.dart';
import 'package:digibyte_dex/features/receive/view/receive_page.dart';
import 'package:digibyte_dex/features/send/view/send_page.dart';
import 'package:digibyte_dex/features/wallet/view/home_page.dart';
```

   with:

```dart
import 'package:digibyte_dex/features/onboarding/view/welcome_page.dart';
import 'package:digibyte_dex/features/receive/view/receive_page.dart';
import 'package:digibyte_dex/features/send/view/scan_page.dart';
import 'package:digibyte_dex/features/send/view/send_page.dart';
import 'package:digibyte_dex/features/wallet/view/home_page.dart';
```

2. Replace:

```dart
        },
      ),
    ],
  ),
```

   with:

```dart
        },
      ),
      GoRoute(path: 'scan', builder: (_, _) => const ScanPage()),
    ],
  ),
```


Edit `app/lib/app/app_scope.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:digibyte_dex/platform/url_opener.dart';
```

   with:

```dart
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/qr_scanner.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:digibyte_dex/platform/url_opener.dart';
```

2. Replace:

```dart
    required this.sharer,
    required this.urls,
    PendingBackupSession? session,
  }) : session = session ?? PendingBackupSession();
```

   with:

```dart
    required this.sharer,
    required this.urls,
    required this.scanner,
    PendingBackupSession? session,
  }) : session = session ?? PendingBackupSession();
```

3. Replace:

```dart
  final TextSharer sharer;
  final UrlOpener urls;
  final PendingBackupSession session;
}
```

   with:

```dart
  final TextSharer sharer;
  final UrlOpener urls;
  final QrScanner scanner;
  final PendingBackupSession session;
}
```

4. Replace:

```dart
      RepositoryProvider<TextSharer>.value(value: services.sharer),
      RepositoryProvider<UrlOpener>.value(value: services.urls),
    ],
    child: MultiBlocProvider(
```

   with:

```dart
      RepositoryProvider<TextSharer>.value(value: services.sharer),
      RepositoryProvider<UrlOpener>.value(value: services.urls),
      RepositoryProvider<QrScanner>.value(value: services.scanner),
    ],
    child: MultiBlocProvider(
```


Edit `app/lib/main.dart` (2 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/platform/backup_exclusion.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:digibyte_dex/platform/url_opener.dart';
```

   with:

```dart
import 'package:digibyte_dex/platform/backup_exclusion.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/qr_scanner.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:digibyte_dex/platform/url_opener.dart';
```

2. Replace:

```dart
      sharer: const TextSharer(),
      urls: const UrlOpener(),
    );
    // App-lifetime cubits: never closed, the process ends with them.
```

   with:

```dart
      sharer: const TextSharer(),
      urls: const UrlOpener(),
      scanner: const QrScanner(),
    );
    // App-lifetime cubits: never closed, the process ends with them.
```


`app_en.arb` grows at the end in every task that adds strings. The replacement below adds a comma to the current last entry and appends this task's entries.

In `app/lib/l10n/arb/app_en.arb`, replace:

```json
  "resultFailedTitle": "Not sent",
  "resultFailedHint": "Check the history before you try again.",
  "resultBack": "Back to edit"
}
```

with:

```json
  "resultFailedTitle": "Not sent",
  "resultFailedHint": "Check the history before you try again.",
  "resultBack": "Back to edit",
  "cancel": "Cancel",
  "sendScan": "Scan a QR code",
  "scanTitle": "Scan a QR code",
  "scanTorch": "Flashlight",
  "scanCameraError": "The camera isn't available. Allow camera access for DigiByte DEX in Settings.",
  "scanNotPayment": "Not a payment code",
  "scanOtherCoin": "This is a {ticker, select, DGB{DigiByte} BTC{Bitcoin} LTC{Litecoin} other{{ticker}}} address. Open {ticker} send?",
  "@scanOtherCoin": {"placeholders": {"ticker": {"type": "String"}}},
  "scanOpen": "Open {ticker} send",
  "@scanOpen": {"placeholders": {"ticker": {"type": "String"}}}
}
```

Edit `app/lib/features/send/view/send_form_view.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'dart:async';

import 'package:digibyte_dex/features/send/bloc/send_cubit.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/l10n/send_messages.dart';
import 'package:digibyte_dex/widgets/busy_indicator.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
```

   with:

```dart
import 'dart:async';

import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/features/send/bloc/send_cubit.dart';
import 'package:digibyte_dex/features/send/scan_outcome.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/l10n/send_messages.dart';
import 'package:digibyte_dex/platform/qr_scanner.dart';
import 'package:digibyte_dex/widgets/busy_indicator.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
```

2. Replace:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The send form (spec §3.2): address, amount with Max, Next.
```

   with:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// The send form (spec §3.2): address, amount with Max, Next.
```

3. Replace:

```dart
    _amount.dispose();
    super.dispose();
  }

```

   with:

```dart
    _amount.dispose();
    super.dispose();
  }

  /// Scans a QR code (spec §5.2): same coin fills the form; another coin
  /// asks before opening its Send; anything else says so.
  Future<void> _scan() async {
    final cubit = context.read<SendCubit>();
    final raw = await context.read<QrScanner>().scan(context);
    if (raw == null || !mounted) return;
    switch (ScanOutcome.of(raw, ticker: cubit.ticker)) {
      case SameCoin(:final request):
        cubit.applyRequest(request);
      case OtherCoin(:final request, :final ticker):
        final open = await _confirmOtherCoin(ticker);
        if (open && mounted) {
          context.pushReplacement(Routes.send(ticker), extra: request);
        }
      case NotPaymentCode():
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.scanNotPayment)));
    }
  }

  Future<bool> _confirmOtherCoin(String ticker) async {
    final l10n = context.l10n;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.scanOtherCoin(ticker)),
        actions: [
          Tagged(
            'scan.stay',
            child: TextButton(
              key: const Key('scan.stay'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
          ),
          Tagged(
            'scan.open',
            child: FilledButton(
              key: const Key('scan.open'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.scanOpen(ticker)),
            ),
          ),
        ],
      ),
    );
    return open ?? false;
  }

```

4. Replace:

```dart
                      errorText: _addressError(l10n, state),
                      helperText: _addressHelper(l10n, state),
                    ),
                  ),
```

   with:

```dart
                      errorText: _addressError(l10n, state),
                      helperText: _addressHelper(l10n, state),
                      suffixIcon: Tagged(
                        'send.scan',
                        child: IconButton(
                          key: const Key('send.scan'),
                          tooltip: l10n.sendScan,
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: busy ? null : () => unawaited(_scan()),
                        ),
                      ),
                    ),
                  ),
```


Create `app/lib/features/send/scan_outcome.dart`:

```dart
import 'package:digibyte_dex/domain/payment_uri.dart';

/// What a scanned QR code means on the Send page of one coin (spec §5.2).
sealed class ScanOutcome {
  const ScanOutcome();

  factory ScanOutcome.of(String raw, {required String ticker}) {
    final request = PaymentUri.parse(raw);
    if (request == null) return const NotPaymentCode();
    final other = request.ticker;
    if (other != null && other != ticker) return OtherCoin(request);
    return SameCoin(request);
  }
}

/// Fill the form: a request for this coin, or a bare address.
final class SameCoin extends ScanOutcome {
  const SameCoin(this.request);

  final PaymentUri request;
}

/// A request for another listed coin: ask before switching.
final class OtherCoin extends ScanOutcome {
  const OtherCoin(this.request);

  final PaymentUri request;

  String get ticker => request.ticker!;
}

final class NotPaymentCode extends ScanOutcome {
  const NotPaymentCode();
}
```

Create `app/lib/platform/qr_scanner.dart`:

```dart
import 'package:digibyte_dex/app/routes.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Scans one QR code with the camera page and returns its text, or null
/// when cancelled. Tests replace it.
class QrScanner {
  const QrScanner();

  Future<String?> scan(BuildContext context) =>
      context.push<String>(Routes.scan);
}
```

Create `app/lib/features/send/view/scan_page.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen QR scanner (spec §5.2). On-device and offline: ML Kit
/// bundled on Android, Vision on iOS; it uses the existing CAMERA
/// permission. Pops with the first readable code.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _done = true;
      unawaited(_controller.stop());
      context.pop(raw);
      return;
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scanTitle),
        actions: [
          Tagged(
            'scan.torch',
            child: IconButton(
              key: const Key('scan.torch'),
              tooltip: l10n.scanTorch,
              icon: const Icon(Icons.flashlight_on_outlined),
              onPressed: () => unawaited(_controller.toggleTorch()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.scanCameraError,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Tagged(
                'scan.cancel',
                child: OutlinedButton(
                  key: const Key('scan.cancel'),
                  onPressed: () => context.pop(),
                  child: Text(l10n.cancel),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

Then regenerate the localizations:

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter gen-l10n
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/app/app_scope_test.dart \
  test/app/router_test.dart \
  test/features/send/send_page_test.dart \
  test/features/send/scan_outcome_test.dart
```

Expected: `+36: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```

Expected: the formatter changes 0 files; `No issues found!`; `+522: All tests passed!`.

- [ ] **Step 6: Check the Android build and the permission allowlist**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter build apk --debug
cd .. && bash tool/check_permissions.sh
```
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`, then `permissions OK: 5 entries match allowlist`.

- [ ] **Step 7: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/app/app_scope.dart \
  lib/app/router.dart \
  lib/app/routes.dart \
  lib/features/send/scan_outcome.dart \
  lib/features/send/view/scan_page.dart \
  lib/features/send/view/send_form_view.dart \
  lib/l10n/arb/app_en.arb \
  lib/main.dart \
  lib/platform/qr_scanner.dart \
  pubspec.lock \
  pubspec.yaml \
  test/app/app_scope_test.dart \
  test/app/router_test.dart \
  test/features/send/scan_outcome_test.dart \
  test/features/send/send_page_test.dart \
  test/support/fake_qr_scanner.dart \
  test/support/test_app.dart
git commit -m "feat(send): QR scanner page and scan-result handling" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 7: `digibyte:` links: Android intent filter, iOS URL type, platform-channel intake, pending request, routing

Spec §5.3. Native code keeps the latest `digibyte:` link and Dart takes it: `takePaymentLink` (Dart → native, returns the link or null, once) at start, and again whenever native calls `paymentLinkAvailable`. Android reads the launch intent in `onCreate` (unless the activity is being recreated or Android replays the intent from recents) and later ones in `onNewIntent`; `flutter_deeplinking_enabled=false` keeps raw URLs away from go_router. iOS registers the `digibyte` URL type, turns Flutter's deep linking off, and receives links through a `FlutterSceneLifeCycleDelegate` added to a plugin registrar (`FlutterPlugin.h` `addSceneDelegate:`); the Swift lives in `AppDelegate.swift` so no Xcode project change is needed. iOS is compiled by CI and verified in the Mac pass only.

`PaymentLinkDispatcher` decides with the pure `paymentLinkRoute(auth, lock)`: open now (signed in, unlocked, no pending backup), hold (locked, signed out with wallets, backup pending, starting), or drop with a message (no wallet). It re-checks a microtask after every auth or lock change, so `LockCubit` has already locked an adopted session before Send could open.

**Files:**
- Create: `app/lib/data/payment_links.dart`
- Create: `app/lib/app/payment_link_dispatcher.dart`
- Create: `app/test/support/fake_payment_link_source.dart`
- Modify: `app/lib/app/app_scope.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/test/support/test_app.dart`
- Modify: `app/lib/l10n/arb/app_en.arb`
- Modify: `app/lib/app/app.dart`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Modify: `app/android/app/src/main/kotlin/me/digiscope/wallet/MainActivity.kt`
- Modify: `app/ios/Runner/Info.plist`
- Modify: `app/ios/Runner/AppDelegate.swift`
- Test (modify): `app/test/app/app_scope_test.dart`
- Test (create): `app/test/data/payment_links_test.dart`
- Test (create): `app/test/app/payment_link_dispatcher_test.dart`
- Test (modify): `app/test/app/app_test.dart`
- Test (modify): `app/test/platform/platform_config_test.dart`

**Interfaces:**
- Consumes: Task 1 `PaymentUri`; Task 5 `Routes.send` (and its `extra`); M1-C `AuthCubit`/`AuthState`, `LockCubit`/`AppLockState`, `platformChannel`.
- Produces:
  - `class PendingPaymentRequest { PendingPaymentRequest({DateTime Function()? now, Duration ttl = const Duration(minutes: 10)}); void hold(PaymentUri request); PaymentUri? get current; bool get hasRequest; PaymentUri? take(); void clear(); }`
  - `class PaymentLinkSource { const PaymentLinkSource({MethodChannel channel = platformChannel}); Future<void> start(void Function(String link) onLink); }`
  - `enum PaymentLinkRoute { open, hold, drop }`; `PaymentLinkRoute paymentLinkRoute(AuthState auth, AppLockState lock)`; `enum PaymentLinkNotice { notPayment, noWallet }`
  - `class PaymentLinkDispatcher { PaymentLinkDispatcher({required AuthCubit auth, required LockCubit lock, required PendingPaymentRequest pending, required void Function(PaymentUri request) open, required void Function(PaymentLinkNotice notice) notify}); void receive(String link); Future<void> dispose(); }`
  - `AppServices` gains `required PaymentLinkSource links` and an optional `PendingPaymentRequest? pendingRequest` (default `PendingPaymentRequest()`), both provided by `AppScope`. `DigiByteDexApp` owns the dispatcher and a `scaffoldMessengerKey` for its notices.
  - Platform channel `me.digiscope.wallet/platform` methods: `takePaymentLink` (Dart → native), `paymentLinkAvailable` (native → Dart, no arguments).
- Test support: `FakePaymentLinkSource` (`launch`, `emit`); `TestApp.links`, `TestApp.pendingRequest` (on the test clock).

- [ ] **Step 1: Write the failing tests**

Edit `app/test/support/test_app.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/app/app_scope.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
```

   with:

```dart
import 'package:digibyte_dex/app/app_scope.dart';
import 'package:digibyte_dex/data/payment_links.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
```

2. Replace:

```dart
import 'fake_biometric_store.dart';
import 'fake_history_repository.dart';
import 'fake_qr_scanner.dart';
import 'fake_receive_repository.dart';
```

   with:

```dart
import 'fake_biometric_store.dart';
import 'fake_history_repository.dart';
import 'fake_payment_link_source.dart';
import 'fake_qr_scanner.dart';
import 'fake_receive_repository.dart';
```

3. Replace:

```dart
  final urls = FakeUrlOpener();
  final scanner = FakeQrScanner();
  final clipboardWrites = <String>[];

```

   with:

```dart
  final urls = FakeUrlOpener();
  final scanner = FakeQrScanner();
  final links = FakePaymentLinkSource();
  late final pendingRequest = PendingPaymentRequest(now: () => now);
  final clipboardWrites = <String>[];

```

4. Replace:

```dart
    urls: urls,
    scanner: scanner,
    session: session,
  );

```

   with:

```dart
    urls: urls,
    scanner: scanner,
    links: links,
    session: session,
    pendingRequest: pendingRequest,
  );

```


Edit `app/test/app/app_scope_test.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/app/app_scope.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
```

   with:

```dart
import 'package:digibyte_dex/app/app_scope.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/payment_links.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
```

2. Replace:

```dart
import '../support/fake_biometric_store.dart';
import '../support/fake_history_repository.dart';
import '../support/fake_qr_scanner.dart';
import '../support/fake_receive_repository.dart';
```

   with:

```dart
import '../support/fake_biometric_store.dart';
import '../support/fake_history_repository.dart';
import '../support/fake_payment_link_source.dart';
import '../support/fake_qr_scanner.dart';
import '../support/fake_receive_repository.dart';
```

3. Replace:

```dart
      urls: FakeUrlOpener(),
      scanner: FakeQrScanner(),
    );
  });
```

   with:

```dart
      urls: FakeUrlOpener(),
      scanner: FakeQrScanner(),
      links: FakePaymentLinkSource(),
    );
  });
```

4. Replace:

```dart
    expect(probe.read<UrlOpener>(), same(services.urls));
    expect(probe.read<QrScanner>(), same(services.scanner));
    expect(probe.read<AuthCubit>(), same(cubits.auth));
    expect(probe.read<LockCubit>(), same(cubits.lock));
```

   with:

```dart
    expect(probe.read<UrlOpener>(), same(services.urls));
    expect(probe.read<QrScanner>(), same(services.scanner));
    expect(probe.read<PaymentLinkSource>(), same(services.links));
    expect(
      probe.read<PendingPaymentRequest>(),
      same(services.pendingRequest),
    );
    expect(probe.read<AuthCubit>(), same(cubits.auth));
    expect(probe.read<LockCubit>(), same(cubits.lock));
```


Create `app/test/data/payment_links_test.dart`:

```dart
import 'package:digibyte_dex/data/payment_links.dart';
import 'package:digibyte_dex/domain/payment_uri.dart';
import 'package:digibyte_dex/platform/platform_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/capture_debug_print.dart';
import '../support/platform_channel_mock.dart';

// Dummies, not real addresses.
const _a = PaymentUri(
  ticker: 'DGB',
  address: 'DAaaa0000000000000000000000000001',
);
const _b = PaymentUri(
  ticker: 'DGB',
  address: 'DBbbb0000000000000000000000000002',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PendingPaymentRequest', () {
    late DateTime now;
    late PendingPaymentRequest pending;

    setUp(() {
      now = DateTime.utc(2026, 10, 4, 12);
      pending = PendingPaymentRequest(now: () => now);
    });

    test('holds one request until taken', () {
      expect(pending.hasRequest, isFalse);
      pending.hold(_a);
      expect(pending.hasRequest, isTrue);
      expect(pending.take(), _a);
      expect(pending.take(), isNull);
    });

    test('a newer link replaces the older one', () {
      pending
        ..hold(_a)
        ..hold(_b);
      expect(pending.take(), _b);
    });

    test('dropped after 10 minutes', () {
      pending.hold(_a);
      now = now.add(const Duration(minutes: 9, seconds: 59));
      expect(pending.hasRequest, isTrue);
      now = now.add(const Duration(seconds: 1));
      expect(pending.hasRequest, isFalse);
      expect(pending.take(), isNull);
    });

    test('a replacement restarts the 10 minutes', () {
      pending.hold(_a);
      now = now.add(const Duration(minutes: 8));
      pending.hold(_b);
      now = now.add(const Duration(minutes: 8));
      expect(pending.take(), _b);
    });
  });

  group('PaymentLinkSource', () {
    late List<String?> native;
    late List<String> calls;

    setUp(() {
      native = [];
      calls = [];
      mockPlatformChannel((call) async {
        calls.add(call.method);
        if (call.method != 'takePaymentLink') return null;
        return native.isEmpty ? null : native.removeAt(0);
      });
    });

    Future<void> nativeSaysAvailable() async {
      const codec = StandardMethodCodec();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            platformChannel.name,
            codec.encodeMethodCall(const MethodCall('paymentLinkAvailable')),
            (_) {},
          );
    }

    test('takes the launch link at start', () async {
      native = ['digibyte:launch'];
      final links = <String>[];
      await const PaymentLinkSource().start(links.add);
      expect(links, ['digibyte:launch']);
      expect(calls, ['takePaymentLink']);
    });

    test('no launch link, then one while running', () async {
      final links = <String>[];
      await const PaymentLinkSource().start(links.add);
      expect(links, isEmpty);
      native = ['digibyte:later'];
      await nativeSaysAvailable();
      await pumpEventQueue();
      expect(links, ['digibyte:later']);
    });

    test('no native side: nothing delivered, only the type logged', () async {
      final logs = captureDebugPrint();
      mockPlatformChannel(null);
      final links = <String>[];
      await const PaymentLinkSource().start(links.add);
      expect(links, isEmpty);
      expect(logs, ['Payment link intake failed: MissingPluginException']);
    });
  });
}
```

Create `app/test/app/payment_link_dispatcher_test.dart`:

```dart
import 'package:digibyte_dex/app/payment_link_dispatcher.dart';
import 'package:digibyte_dex/data/payment_links.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/domain/payment_uri.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_wallet_repository.dart';
import '../support/in_memory_key_value_store.dart';

// A dummy, not a real address.
const _address = 'DAaaa0000000000000000000000000001';
const _link = 'digibyte:$_address?amount=2';

void main() {
  group('paymentLinkRoute', () {
    const user = WalletUser('main');
    test('unlocked and backed up: open', () {
      expect(
        paymentLinkRoute(const AuthSignedIn(user), const Unlocked()),
        PaymentLinkRoute.open,
      );
    });

    test('locked, backup pending, signed out or starting: hold', () {
      expect(
        paymentLinkRoute(const AuthSignedIn(user), const Locked()),
        PaymentLinkRoute.hold,
      );
      expect(
        paymentLinkRoute(
          const AuthSignedIn(user, backupPending: true),
          const Unlocked(),
        ),
        PaymentLinkRoute.hold,
      );
      expect(
        paymentLinkRoute(
          const AuthSignedOut(walletNames: ['main']),
          const Unlocked(),
        ),
        PaymentLinkRoute.hold,
      );
      expect(
        paymentLinkRoute(const AuthUnknown(), const Unlocked()),
        PaymentLinkRoute.hold,
      );
    });

    test('no wallet at all: drop', () {
      expect(
        paymentLinkRoute(const AuthSignedOut(), const Unlocked()),
        PaymentLinkRoute.drop,
      );
    });
  });

  group('PaymentLinkDispatcher', () {
    late FakeWalletRepository wallet;
    late AuthCubit auth;
    late LockCubit lock;
    late PendingPaymentRequest pending;
    late List<PaymentUri> opened;
    late List<PaymentLinkNotice> notices;
    late PaymentLinkDispatcher dispatcher;

    setUp(() {
      wallet = FakeWalletRepository();
      auth = AuthCubit(
        wallet,
        backups: BackupStatusStore(InMemoryKeyValueStore()),
      );
      lock = LockCubit(authStates: auth.stream);
      pending = PendingPaymentRequest();
      opened = [];
      notices = [];
      dispatcher = PaymentLinkDispatcher(
        auth: auth,
        lock: lock,
        pending: pending,
        open: opened.add,
        notify: notices.add,
      );
    });
    tearDown(() async {
      await dispatcher.dispose();
      await lock.close();
      await auth.close();
      await wallet.dispose();
    });

    Future<void> signedInUnlocked() async {
      wallet.emit(null);
      await pumpEventQueue();
      wallet.emit(const WalletUser('main'));
      await pumpEventQueue();
    }

    test('unlocked: opens Send at once, prefilled', () async {
      await signedInUnlocked();
      dispatcher.receive(_link);
      expect(opened.single.address, _address);
      expect(opened.single.amount.toString(), '2');
      expect(pending.hasRequest, isFalse);
    });

    test('locked: held, then opened after unlock', () async {
      await signedInUnlocked();
      lock.lockNow();
      dispatcher.receive(_link);
      expect(opened, isEmpty);
      expect(pending.hasRequest, isTrue);
      lock.unlock();
      await pumpEventQueue();
      expect(opened.single.address, _address);
    });

    test('signed out: held, then opened after sign-in', () async {
      wallet
        ..names = ['main']
        ..emit(null);
      await pumpEventQueue();
      dispatcher.receive(_link);
      expect(opened, isEmpty);
      wallet.emit(const WalletUser('main'));
      await pumpEventQueue();
      expect(opened.single.address, _address);
    });

    test('an adopted (locked) session never opens before unlock', () async {
      dispatcher.receive(_link);
      wallet.emit(const WalletUser('main'));
      await pumpEventQueue();
      expect(lock.state, const Locked());
      expect(opened, isEmpty);
      lock.unlock();
      await pumpEventQueue();
      expect(opened, hasLength(1));
    });

    test('no wallet: dropped with a notice', () async {
      wallet.emit(null);
      await pumpEventQueue();
      dispatcher.receive(_link);
      expect(opened, isEmpty);
      expect(pending.hasRequest, isFalse);
      expect(notices, [PaymentLinkNotice.noWallet]);
    });

    test('not a DigiByte payment request: a notice, nothing held', () async {
      await signedInUnlocked();
      dispatcher
        ..receive('digibyte:not an address')
        ..receive('bitcoin:bc1qdummyaddress0000000000000000000000');
      expect(opened, isEmpty);
      expect(pending.hasRequest, isFalse);
      expect(notices, [
        PaymentLinkNotice.notPayment,
        PaymentLinkNotice.notPayment,
      ]);
    });
  });
}
```

Create `app/test/support/fake_payment_link_source.dart`:

```dart
import 'package:digibyte_dex/data/payment_links.dart';

/// Hand-written [PaymentLinkSource]: [launch] is the link the app was
/// started with; [emit] delivers one while it runs.
class FakePaymentLinkSource implements PaymentLinkSource {
  String? launch;
  void Function(String link)? _onLink;

  @override
  Future<void> start(void Function(String link) onLink) async {
    _onLink = onLink;
    final link = launch;
    if (link != null) onLink(link);
  }

  void emit(String link) => _onLink?.call(link);
}
```

Edit `app/test/app/app_test.dart` (2 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
```

   with:

```dart
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/features/send/view/send_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
```

2. Replace:

```dart
    expect(app.session.passwordFor('main'), isNull);
  });
}
```

   with:

```dart
    expect(app.session.passwordFor('main'), isNull);
  });

  group('digibyte: links', () {
    // A dummy, not a real address.
    const address = 'DAaaa0000000000000000000000000001';
    const link = 'digibyte:$address?amount=2';

    String fieldText(WidgetTester t, String key) =>
        t.widget<TextField>(find.byKey(Key(key))).controller!.text;

    Future<void> unlock(WidgetTester t, TestApp app) async {
      await t.enterText(
        find.byKey(const Key('locked.password')),
        app.wallet.correctPassword,
      );
      await t.tap(find.byKey(const Key('locked.submit')));
      await t.pumpAndSettle();
    }

    testWidgets('unlocked: opens a prefilled DGB Send at once', (t) async {
      final app = TestApp();
      addTearDown(app.dispose);
      await t.pumpWidget(app.build());
      await signIn(t, app);
      app.links.emit(link);
      await t.pumpAndSettle();
      expect(find.byType(SendPage), findsOneWidget);
      expect(fieldText(t, 'send.address'), address);
      expect(fieldText(t, 'send.amount'), '2');
      expect(app.send.broadcasts, isEmpty);
    });

    testWidgets('locked: Send opens only after unlock', (t) async {
      final app = TestApp();
      addTearDown(app.dispose);
      await t.pumpWidget(app.build());
      await signIn(t, app);
      app.lock.lockNow();
      await t.pumpAndSettle();
      app.links.emit(link);
      await t.pumpAndSettle();
      expect(find.byType(SendPage), findsNothing);
      expect(find.byKey(const Key('locked.password')), findsOneWidget);
      await unlock(t, app);
      expect(find.byType(SendPage), findsOneWidget);
      expect(fieldText(t, 'send.address'), address);
    });

    testWidgets('a launch link waits for sign-in', (t) async {
      final app = TestApp();
      addTearDown(app.dispose);
      app
        ..wallet.names = ['main']
        ..links.launch = link;
      await t.pumpWidget(app.build());
      app.wallet.emit(null);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('signin.password')), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('signin.password')),
        app.wallet.correctPassword,
      );
      await t.tap(find.byKey(const Key('signin.submit')));
      await t.pumpAndSettle();
      expect(find.byType(SendPage), findsOneWidget);
      expect(fieldText(t, 'send.address'), address);
    });

    testWidgets('a held link expires after 10 minutes', (t) async {
      final app = TestApp();
      addTearDown(app.dispose);
      await t.pumpWidget(app.build());
      await signIn(t, app);
      app.lock.lockNow();
      await t.pumpAndSettle();
      app.links.emit(link);
      await t.pump();
      app.now = app.now.add(const Duration(minutes: 10));
      await unlock(t, app);
      expect(find.byType(SendPage), findsNothing);
      expect(find.text('Portfolio'), findsOneWidget);
    });

    testWidgets('no wallet: dropped, with a message on welcome', (t) async {
      final app = TestApp();
      addTearDown(app.dispose);
      await t.pumpWidget(app.build());
      app.wallet.emit(null);
      await t.pumpAndSettle();
      app.links.emit(link);
      await t.pump();
      expect(find.text('Welcome to DigiByte DEX'), findsOneWidget);
      expect(
        find.text(
          'Create or restore a wallet first, then open the payment link '
          'again.',
        ),
        findsOneWidget,
      );
      expect(app.pendingRequest.hasRequest, isFalse);
    });
  });
}
```


In `app/test/platform/platform_config_test.dart`, replace:

```dart
    expect(kt, contains('setRecentsScreenshotEnabled(false)'));
  });
}
```

with:

```dart
    expect(kt, contains('setRecentsScreenshotEnabled(false)'));
  });

  test('digibyte: links open MainActivity; Flutter deep linking is off', () {
    final activity = manifest
        .findAllElements('activity')
        .singleWhere(
          (a) =>
              a.getAttribute('name', namespaceUri: _android) == '.MainActivity',
        );
    String? name(XmlElement e) =>
        e.getAttribute('name', namespaceUri: _android);
    final filter = activity
        .findElements('intent-filter')
        .singleWhere(
          (f) => f
              .findElements('data')
              .any(
                (d) =>
                    d.getAttribute('scheme', namespaceUri: _android) ==
                    'digibyte',
              ),
        );
    expect(filter.findElements('action').map(name), [
      'android.intent.action.VIEW',
    ]);
    expect(filter.findElements('category').map(name).toSet(), {
      'android.intent.category.DEFAULT',
      'android.intent.category.BROWSABLE',
    });
    final deepLinking = activity
        .findElements('meta-data')
        .singleWhere((m) => name(m) == 'flutter_deeplinking_enabled');
    expect(deepLinking.getAttribute('value', namespaceUri: _android), 'false');
    // No other scheme is registered (spec D5).
    final schemes = manifest
        .findAllElements('data')
        .map((d) => d.getAttribute('scheme', namespaceUri: _android))
        .whereType<String>()
        .toSet();
    expect(schemes, {'digibyte'});
  });

  test('iOS registers digibyte: and turns Flutter deep linking off', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>CFBundleURLSchemes</key>'));
    expect(
      RegExp(
        r'<key>CFBundleURLSchemes</key>\s*<array>\s*'
        r'<string>digibyte</string>\s*</array>',
      ).hasMatch(plist),
      isTrue,
    );
    expect(
      RegExp(
        r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>',
      ).hasMatch(plist),
      isTrue,
    );
  });

  test(
    'MainActivity hands payment links to Dart, never replaying old ones',
    () {
      final kt = File(
        'android/app/src/main/kotlin/me/digiscope/wallet/MainActivity.kt',
      ).readAsStringSync();
      expect(kt, contains('"takePaymentLink"'));
      expect(kt, contains('"paymentLinkAvailable"'));
      expect(kt, contains('override fun onNewIntent'));
      expect(kt, contains('FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY'));
      expect(kt, contains('if (savedInstanceState == null)'));
    },
  );
}
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/app/app_scope_test.dart \
  test/data/payment_links_test.dart \
  test/app/payment_link_dispatcher_test.dart \
  test/app/app_test.dart \
  test/platform/platform_config_test.dart
```

Expected: FAIL. `payment_links.dart` and `payment_link_dispatcher.dart` are missing, `TestApp` cannot build (`No named parameter with the name 'links'`), and the platform tests fail: no `digibyte` intent filter, no `flutter_deeplinking_enabled`, no `CFBundleURLSchemes`, no `takePaymentLink` in `MainActivity.kt`.

- [ ] **Step 3: Implement**

Edit `app/lib/app/app_scope.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/app/app.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
```

   with:

```dart
import 'package:digibyte_dex/app/app.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/payment_links.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
```

2. Replace:

```dart
    required this.urls,
    required this.scanner,
    PendingBackupSession? session,
  }) : session = session ?? PendingBackupSession();

  final WalletRepository wallet;
```

   with:

```dart
    required this.urls,
    required this.scanner,
    required this.links,
    PendingBackupSession? session,
    PendingPaymentRequest? pendingRequest,
  }) : session = session ?? PendingBackupSession(),
       pendingRequest = pendingRequest ?? PendingPaymentRequest();

  final WalletRepository wallet;
```

3. Replace:

```dart
  final UrlOpener urls;
  final QrScanner scanner;
  final PendingBackupSession session;
}

```

   with:

```dart
  final UrlOpener urls;
  final QrScanner scanner;
  final PaymentLinkSource links;
  final PendingBackupSession session;
  final PendingPaymentRequest pendingRequest;
}

```

4. Replace:

```dart
      RepositoryProvider<UrlOpener>.value(value: services.urls),
      RepositoryProvider<QrScanner>.value(value: services.scanner),
    ],
    child: MultiBlocProvider(
```

   with:

```dart
      RepositoryProvider<UrlOpener>.value(value: services.urls),
      RepositoryProvider<QrScanner>.value(value: services.scanner),
      RepositoryProvider<PaymentLinkSource>.value(value: services.links),
      RepositoryProvider.value(value: services.pendingRequest),
    ],
    child: MultiBlocProvider(
```


Edit `app/lib/main.dart` (2 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/bootstrap/sdk_bootstrap.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
```

   with:

```dart
import 'package:digibyte_dex/bootstrap/sdk_bootstrap.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/payment_links.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
```

2. Replace:

```dart
      urls: const UrlOpener(),
      scanner: const QrScanner(),
    );
    // App-lifetime cubits: never closed, the process ends with them.
```

   with:

```dart
      urls: const UrlOpener(),
      scanner: const QrScanner(),
      links: const PaymentLinkSource(),
    );
    // App-lifetime cubits: never closed, the process ends with them.
```


`app_en.arb` grows at the end in every task that adds strings. The replacement below adds a comma to the current last entry and appends this task's entries.

In `app/lib/l10n/arb/app_en.arb`, replace:

```json
  "@scanOtherCoin": {"placeholders": {"ticker": {"type": "String"}}},
  "scanOpen": "Open {ticker} send",
  "@scanOpen": {"placeholders": {"ticker": {"type": "String"}}}
}
```

with:

```json
  "@scanOtherCoin": {"placeholders": {"ticker": {"type": "String"}}},
  "scanOpen": "Open {ticker} send",
  "@scanOpen": {"placeholders": {"ticker": {"type": "String"}}},
  "linkNotPayment": "That link isn't a DigiByte payment request.",
  "linkNoWallet": "Create or restore a wallet first, then open the payment link again."
}
```

Create `app/lib/data/payment_links.dart`:

```dart
import 'package:digibyte_dex/domain/payment_uri.dart';
import 'package:digibyte_dex/platform/platform_channel.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// The one payment request waiting for an unlock or sign-in (spec §5.3).
/// In memory only, so it is gone when the app is killed. A newer request
/// replaces it, and it expires after [ttl].
class PendingPaymentRequest {
  PendingPaymentRequest({
    DateTime Function()? now,
    this.ttl = const Duration(minutes: 10),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration ttl;
  PaymentUri? _request;
  DateTime? _heldAt;

  void hold(PaymentUri request) {
    _request = request;
    _heldAt = _now();
  }

  /// The request, unless it expired (which also drops it).
  PaymentUri? get current {
    final at = _heldAt;
    if (at != null && _now().difference(at) >= ttl) clear();
    return _request;
  }

  bool get hasRequest => current != null;

  /// The request, and forgets it.
  PaymentUri? take() {
    final request = current;
    clear();
    return request;
  }

  void clear() {
    _request = null;
    _heldAt = null;
  }
}

/// `digibyte:` links from the OS (spec §5.3), over the app's platform
/// channel. Android `MainActivity` and the iOS scene delegate keep the
/// latest link; Dart takes it at start and whenever the native side says
/// a new one arrived. Links are never logged.
class PaymentLinkSource {
  const PaymentLinkSource({MethodChannel channel = platformChannel})
    : _channel = channel;

  final MethodChannel _channel;

  /// Delivers the launch link, if any, then every later one, to [onLink].
  ///
  /// This is the only Dart-side handler of the platform channel; native
  /// code only calls `paymentLinkAvailable` on it.
  Future<void> start(void Function(String link) onLink) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'paymentLinkAvailable') await _take(onLink);
      return null;
    });
    await _take(onLink);
  }

  Future<void> _take(void Function(String link) onLink) async {
    try {
      final link = await _channel.invokeMethod<String>('takePaymentLink');
      if (link != null && link.isNotEmpty) onLink(link);
    } on Object catch (error) {
      // No native handler (tests, desktop) or a platform error.
      debugPrint('Payment link intake failed: ${error.runtimeType}');
    }
  }
}
```

Create `app/lib/app/payment_link_dispatcher.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/payment_links.dart';
import 'package:digibyte_dex/domain/payment_uri.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';

enum PaymentLinkRoute {
  /// Open DGB Send with the request now.
  open,

  /// Keep it until the wallet is unlocked or signed in.
  hold,

  /// No wallet exists: drop it and say why.
  drop,
}

/// Where a payment link goes in each session state (spec §5.3). Pure, like
/// `authRedirect`.
PaymentLinkRoute paymentLinkRoute(AuthState auth, AppLockState lock) =>
    switch (auth) {
      AuthUnknown() => PaymentLinkRoute.hold,
      AuthSignedOut(:final walletNames) =>
        walletNames.isEmpty ? PaymentLinkRoute.drop : PaymentLinkRoute.hold,
      AuthSignedIn(:final backupPending) =>
        lock is Locked || backupPending
            ? PaymentLinkRoute.hold
            : PaymentLinkRoute.open,
    };

enum PaymentLinkNotice {
  /// Not a DigiByte payment request.
  notPayment,

  /// No wallet exists yet.
  noWallet,
}

/// Turns OS links into a prefilled DGB Send: at once when unlocked,
/// otherwise after the next unlock or sign-in. A link only prefills;
/// nothing is sent without Confirm and re-authentication.
class PaymentLinkDispatcher {
  PaymentLinkDispatcher({
    required AuthCubit auth,
    required LockCubit lock,
    required PendingPaymentRequest pending,
    required void Function(PaymentUri request) open,
    required void Function(PaymentLinkNotice notice) notify,
  }) : _auth = auth,
       _lock = lock,
       _pending = pending,
       _open = open,
       _notify = notify {
    // A microtask later, so every listener (LockCubit included) has seen
    // the same auth event first.
    void later(Object? _) => scheduleMicrotask(_dispatch);
    _subscriptions = [auth.stream.listen(later), lock.stream.listen(later)];
  }

  final AuthCubit _auth;
  final LockCubit _lock;
  final PendingPaymentRequest _pending;
  final void Function(PaymentUri request) _open;
  final void Function(PaymentLinkNotice notice) _notify;
  late final List<StreamSubscription<Object?>> _subscriptions;

  /// Only `digibyte:` is registered with the OS (spec D5).
  void receive(String link) {
    final request = PaymentUri.parse(link);
    if (request == null || request.ticker != 'DGB') {
      _notify(PaymentLinkNotice.notPayment);
      return;
    }
    _pending.hold(request);
    _dispatch();
  }

  void _dispatch() {
    if (!_pending.hasRequest) return;
    switch (paymentLinkRoute(_auth.state, _lock.state)) {
      case PaymentLinkRoute.open:
        final request = _pending.take();
        if (request != null) _open(request);
      case PaymentLinkRoute.drop:
        _pending.clear();
        _notify(PaymentLinkNotice.noWallet);
      case PaymentLinkRoute.hold:
        break;
    }
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
```

Edit `app/lib/app/app.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'dart:async';

import 'package:digibyte_dex/app/router.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
```

   with:

```dart
import 'dart:async';

import 'package:digibyte_dex/app/payment_link_dispatcher.dart';
import 'package:digibyte_dex/app/router.dart';
import 'package:digibyte_dex/data/payment_links.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
```

2. Replace:

```dart
  late final AppRouter _router;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _router = AppRouter(context.read<AuthCubit>(), context.read<LockCubit>());
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleChanged);
  }

```

   with:

```dart
  late final AppRouter _router;
  late final AppLifecycleListener _lifecycle;
  late final PaymentLinkDispatcher _links;
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthCubit>();
    final lock = context.read<LockCubit>();
    _router = AppRouter(auth, lock);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleChanged);
    _links = PaymentLinkDispatcher(
      auth: auth,
      lock: lock,
      pending: context.read<PendingPaymentRequest>(),
      open: (request) => _router.router.go(Routes.send('DGB'), extra: request),
      notify: _onLinkNotice,
    );
    unawaited(context.read<PaymentLinkSource>().start(_links.receive));
  }

  void _onLinkNotice(PaymentLinkNotice notice) {
    final messenger = _messenger.currentState;
    if (messenger == null) return;
    final l10n = AppLocalizations.of(messenger.context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (notice) {
          PaymentLinkNotice.notPayment => l10n.linkNotPayment,
          PaymentLinkNotice.noWallet => l10n.linkNoWallet,
        }),
      ),
    );
  }

```

3. Replace:

```dart
  @override
  void dispose() {
    _lifecycle.dispose();
    _router.dispose();
```

   with:

```dart
  @override
  void dispose() {
    unawaited(_links.dispose());
    _lifecycle.dispose();
    _router.dispose();
```

4. Replace:

```dart
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    onGenerateTitle: (c) => c.l10n.appTitle,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
```

   with:

```dart
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    scaffoldMessengerKey: _messenger,
    onGenerateTitle: (c) => c.l10n.appTitle,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
```


In `app/android/app/src/main/AndroidManifest.xml`, replace:

```xml
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <!-- Don't delete the meta-data below.
```

with:

```xml
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            <!-- digibyte: payment links (spec §5.3). MainActivity hands them
                 to Dart over the platform channel. -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="digibyte"/>
            </intent-filter>
            <!-- The router never sees raw external URLs. -->
            <meta-data
                android:name="flutter_deeplinking_enabled"
                android:value="false"/>
        </activity>
        <!-- Don't delete the meta-data below.
```

Edit `app/android/app/src/main/kotlin/me/digiscope/wallet/MainActivity.kt` (4 replacements, top to bottom):

1. Replace:

```kotlin
package me.digiscope.wallet

import android.os.Build
import android.os.Bundle
```

   with:

```kotlin
package me.digiscope.wallet

import android.content.Intent
import android.os.Build
import android.os.Bundle
```

2. Replace:

```kotlin
// BiometricPrompt.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
```

   with:

```kotlin
// BiometricPrompt.
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null

    // The latest digibyte: link Dart has not taken yet (spec §5.3). Never
    // logged.
    private var pendingLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
```

3. Replace:

```kotlin
            setRecentsScreenshotEnabled(false)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Screenshots and screen recording off on seed screens.
```

   with:

```kotlin
            setRecentsScreenshotEnabled(false)
        }
        // A recreated activity must not replay its launch link.
        if (savedInstanceState == null) pendingLink = paymentLink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = paymentLink(intent) ?: return
        pendingLink = link
        channel?.invokeMethod("paymentLinkAvailable", null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .also { it.setMethodCallHandler { call, result ->
                when (call.method) {
                    // Screenshots and screen recording off on seed screens.
```

4. Replace:

```kotlin
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

```

   with:

```kotlin
                        result.success(null)
                    }
                    // Hands the pending payment link to Dart, once.
                    "takePaymentLink" -> {
                        result.success(pendingLink)
                        pendingLink = null
                    }
                    else -> result.notImplemented()
                }
            } }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // A VIEW intent for a digibyte: URI, unless Android replays it from
    // the recents list.
    private fun paymentLink(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return null
        val uri = intent.data ?: return null
        if (!uri.scheme.equals("digibyte", ignoreCase = true)) return null
        return uri.toString()
    }

```


In `app/ios/Runner/Info.plist`, replace:

```xml
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
```

with:

```xml
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>me.digiscope.wallet.payment</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>digibyte</string>
			</array>
		</dict>
	</array>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>FlutterDeepLinkingEnabled</key>
	<false/>
	<key>LSRequiresIPhoneOS</key>
	<true/>
```

Edit `app/ios/Runner/AppDelegate.swift` (4 replacements, top to bottom):

1. Replace:

```swift
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
```

   with:

```swift
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let paymentLinks = PaymentLinks()

  override func application(
    _ application: UIApplication,
```

2. Replace:

```swift
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
```

   with:

```swift
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    paymentLinks.channel = channel
    // digibyte: links arrive through the scene life cycle (spec §5.3).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DigiBytePaymentLinks") {
      registrar.addSceneDelegate(paymentLinks)
    }
    let links = paymentLinks
    channel.setMethodCallHandler { call, result in
      switch call.method {
```

3. Replace:

```swift
          result(FlutterError(code: "exclude_failed", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
```

   with:

```swift
          result(FlutterError(code: "exclude_failed", message: error.localizedDescription, details: nil))
        }
      case "takePaymentLink":
        result(links.take())
      default:
        result(FlutterMethodNotImplemented)
```

4. Replace:

```swift
  }
}
```

   with:

```swift
  }
}

/// Keeps the latest digibyte: link until Dart takes it (spec §5.3). Wired
/// here, verified in the iOS pass. Links are never logged.
final class PaymentLinks: NSObject, FlutterSceneLifeCycleDelegate {
  var channel: FlutterMethodChannel?
  private var pending: String?

  func take() -> String? {
    defer { pending = nil }
    return pending
  }

  private func receive(_ url: URL?) -> Bool {
    guard let url = url, url.scheme?.lowercased() == "digibyte" else { return false }
    pending = url.absoluteString
    channel?.invokeMethod("paymentLinkAvailable", arguments: nil)
    return true
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    return receive(connectionOptions?.urlContexts.first?.url)
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    return receive(URLContexts.first?.url)
  }
}
```


Then regenerate the localizations:

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter gen-l10n
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/app/app_scope_test.dart \
  test/data/payment_links_test.dart \
  test/app/payment_link_dispatcher_test.dart \
  test/app/app_test.dart \
  test/platform/platform_config_test.dart
```

Expected: `+47: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```

Expected: the formatter changes 0 files; `No issues found!`; `+546: All tests passed!`.

- [ ] **Step 6: Check the Android build and the permission allowlist**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter build apk --debug
cd .. && bash tool/check_permissions.sh
```
Expected: the build succeeds (the Kotlin compiles) and `permissions OK: 5 entries match allowlist`. The Swift is compiled by CI's `build-ios` job when the PR is opened (Task 13).

- [ ] **Step 7: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  android/app/src/main/AndroidManifest.xml \
  android/app/src/main/kotlin/me/digiscope/wallet/MainActivity.kt \
  ios/Runner/AppDelegate.swift \
  ios/Runner/Info.plist \
  lib/app/app.dart \
  lib/app/app_scope.dart \
  lib/app/payment_link_dispatcher.dart \
  lib/data/payment_links.dart \
  lib/l10n/arb/app_en.arb \
  lib/main.dart \
  test/app/app_scope_test.dart \
  test/app/app_test.dart \
  test/app/payment_link_dispatcher_test.dart \
  test/data/payment_links_test.dart \
  test/platform/platform_config_test.dart \
  test/support/fake_payment_link_source.dart \
  test/support/test_app.dart
git commit -m "feat(links): digibyte: payment links from the OS, held until unlock" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 8: Restore seed field hardening: no selection, Paste button, no autofill, redacted controller

Spec §6.1. With `enableInteractiveSelection: false` the field has no selection handles, no text menu and — the point — no accessibility Copy or Cut actions, which the M1-C custom menu could not remove. Text comes in by typing or the new Paste button. `autofillHints: null` turns autofill off, and `SeedTextController.toString` no longer prints the text (`TextEditingController.toString` prints its value).

**Files:**
- Modify: `app/lib/l10n/arb/app_en.arb`
- Modify: `app/lib/features/onboarding/view/restore_wallet_page.dart`
- Modify: `app/lib/features/onboarding/widgets/seed_input.dart`
- Test (modify): `app/test/features/onboarding/restore_wallet_page_test.dart`
- Test (create): `app/test/features/onboarding/seed_input_test.dart`

**Interfaces:**
- Consumes: M1-C `SeedTextController`, `NoCopyShortcuts`, restore page.
- Produces: `Widget noSeedMenu(BuildContext context, EditableTextState state)` (replaces `seedContextMenu`, which is removed); `SeedTextController.toString()` → `SeedTextController(hidden: <bool>)`; widget id `restore.paste`.

- [ ] **Step 1: Write the failing tests**

Edit `app/test/features/onboarding/restore_wallet_page_test.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
```

   with:

```dart
import 'dart:ui' show SemanticsAction;

import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
```

2. Replace:

```dart
  });

  Future<void> showSeedMenu(WidgetTester t) async {
    await enterKey(t, 'restore.seed', 'word1 word2');
    t.state<EditableTextState>(seedEditable())
```

   with:

```dart
  });

  Future<void> selectAllSeed(WidgetTester t) async {
    await enterKey(t, 'restore.seed', 'word1 word2');
    t.state<EditableTextState>(seedEditable())
```

3. Replace:

```dart
  for (final reveal in [false, true]) {
    final mode = reveal ? 'revealed' : 'hidden';
    testWidgets('the $mode seed menu offers paste but never copy or cut', (
      t,
    ) async {
      await pump(t);
      if (reveal) await tapKey(t, 'restore.seedVisibility');
      await showSeedMenu(t);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Cut'), findsNothing);
    });
  }

  testWidgets('the copy and cut shortcuts do nothing', (t) async {
```

   with:

```dart
  for (final reveal in [false, true]) {
    final mode = reveal ? 'revealed' : 'hidden';
    testWidgets('the $mode seed has no selection menu at all', (t) async {
      await pump(t);
      if (reveal) await tapKey(t, 'restore.seedVisibility');
      await selectAllSeed(t);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Cut'), findsNothing);
      expect(find.text('Select all'), findsNothing);
    });

    testWidgets('the $mode seed offers no accessibility copy or cut', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      await pump(t);
      if (reveal) await tapKey(t, 'restore.seedVisibility');
      await selectAllSeed(t);
      final data = t
          .getSemantics(find.byKey(const Key('restore.seed')))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.copy), isFalse);
      expect(data.hasAction(SemanticsAction.cut), isFalse);
      semantics.dispose();
    });
  }

  testWidgets('Paste fills the seed from the clipboard', (t) async {
    await pump(t);
    await tapKey(t, 'restore.paste');
    await t.pump();
    expect(
      t
          .widget<TextField>(find.byKey(const Key('restore.seed')))
          .controller!
          .text,
      'pasted',
    );
  });

  testWidgets('the seed field never offers autofill', (t) async {
    await pump(t);
    expect(
      t.widget<TextField>(find.byKey(const Key('restore.seed'))).autofillHints,
      isNull,
    );
  });

  testWidgets('the copy and cut shortcuts do nothing', (t) async {
```

4. Replace:

```dart
      'restore.seed',
      'restore.seedVisibility',
      'restore.legacy',
      'restore.name',
```

   with:

```dart
      'restore.seed',
      'restore.seedVisibility',
      'restore.paste',
      'restore.legacy',
      'restore.name',
```


Create `app/test/features/onboarding/seed_input_test.dart`:

```dart
import 'package:digibyte_dex/features/onboarding/widgets/seed_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the seed controller never prints its text', () {
    final controller = SeedTextController()..text = 'word1 word2 word3';
    addTearDown(controller.dispose);
    expect(controller.toString(), isNot(contains('word')));
    controller.hidden = false;
    expect(controller.toString(), isNot(contains('word')));
    expect('$controller', isNot(contains('word')));
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/features/onboarding/restore_wallet_page_test.dart \
  test/features/onboarding/seed_input_test.dart
```

Expected: FAIL. Four assertion failures: the seed field still offers `SemanticsAction.copy` / `cut` (`Expected: false Actual: <true>`, twice), `restore.paste` is not found, and `autofillHints` is `[]` instead of null; `seed_input_test.dart` finds the words in `toString()`.

- [ ] **Step 3: Implement**

`app_en.arb` grows at the end in every task that adds strings. The replacement below adds a comma to the current last entry and appends this task's entries.

In `app/lib/l10n/arb/app_en.arb`, replace:

```json
  "@scanOpen": {"placeholders": {"ticker": {"type": "String"}}},
  "linkNotPayment": "That link isn't a DigiByte payment request.",
  "linkNoWallet": "Create or restore a wallet first, then open the payment link again."
}
```

with:

```json
  "@scanOpen": {"placeholders": {"ticker": {"type": "String"}}},
  "linkNotPayment": "That link isn't a DigiByte payment request.",
  "linkNoWallet": "Create or restore a wallet first, then open the payment link again.",
  "seedPaste": "Paste"
}
```

Edit `app/lib/features/onboarding/view/restore_wallet_page.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Restore from a seed phrase (spec §5.1). The seed field is hidden by
/// default (see [SeedTextController]), never offers Copy or Cut, and
/// screenshots are blocked while it is open.
class RestoreWalletPage extends StatelessWidget {
  const RestoreWalletPage({super.key});
```

   with:

```dart
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Restore from a seed phrase (spec §5.1). The seed field is hidden by
/// default (see [SeedTextController]). It has no selection at all, so no
/// Copy or Cut, not even through accessibility; text comes in by typing
/// or the Paste button. Screenshots are blocked while it is open.
class RestoreWalletPage extends StatelessWidget {
  const RestoreWalletPage({super.key});
```

2. Replace:

```dart
    _confirm.dispose();
    super.dispose();
  }

```

   with:

```dart
    _confirm.dispose();
    super.dispose();
  }

  /// The seed field has no selection menu, so pasting is this button.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || !mounted) return;
    _seed.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

```

3. Replace:

```dart
                      smartQuotesType: SmartQuotesType.disabled,
                      keyboardType: TextInputType.visiblePassword,
                      contextMenuBuilder: seedContextMenu,
                      onTapOutside: unfocusOnTapOutside,
                      decoration: InputDecoration(
```

   with:

```dart
                      smartQuotesType: SmartQuotesType.disabled,
                      keyboardType: TextInputType.visiblePassword,
                      // No selection: no handles, no menu, and no copy or
                      // cut semantics actions for accessibility services.
                      enableInteractiveSelection: false,
                      contextMenuBuilder: noSeedMenu,
                      autofillHints: null,
                      onTapOutside: unfocusOnTapOutside,
                      decoration: InputDecoration(
```

4. Replace:

```dart
                  ),
                ),
                const SizedBox(height: 8),
                Tagged(
                  'restore.legacy',
```

   with:

```dart
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Tagged(
                    'restore.paste',
                    child: TextButton.icon(
                      key: const Key('restore.paste'),
                      onPressed: busy ? null : () => unawaited(_paste()),
                      icon: const Icon(Icons.content_paste),
                      label: Text(l10n.seedPaste),
                    ),
                  ),
                ),
                Tagged(
                  'restore.legacy',
```


Edit `app/lib/features/onboarding/widgets/seed_input.dart` (2 replacements, top to bottom):

1. Replace:

```dart
  static final _visible = RegExp(r'[^\n]');

  @override
  TextSpan buildTextSpan({
```

   with:

```dart
  static final _visible = RegExp(r'[^\n]');

  /// Never the text: `TextEditingController.toString` prints its value,
  /// which is the seed.
  @override
  String toString() => 'SeedTextController(hidden: $_hidden)';

  @override
  TextSpan buildTextSpan({
```

2. Replace:

```dart
}

const Set<ContextMenuButtonType> _seedMenuButtons = {
  ContextMenuButtonType.paste,
  ContextMenuButtonType.selectAll,
};

/// The seed field's context menu: Paste and Select all only. Copy, Cut,
/// Share, Look up and Search would all carry the seed off the page.
Widget seedContextMenu(BuildContext context, EditableTextState state) =>
    AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: [
        for (final item in state.contextMenuButtonItems)
          if (_seedMenuButtons.contains(item.type)) item,
      ],
    );

/// Swallows the copy and cut keyboard shortcuts of the text field below.
```

   with:

```dart
}

/// The seed field's text menu: none. Copy, Cut, Share, Look up and Search
/// would all carry the seed off the page; text comes in by typing or the
/// page's Paste button.
Widget noSeedMenu(BuildContext context, EditableTextState state) =>
    const SizedBox.shrink();

/// Swallows the copy and cut keyboard shortcuts of the text field below.
```


Then regenerate the localizations:

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter gen-l10n
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/features/onboarding/restore_wallet_page_test.dart \
  test/features/onboarding/seed_input_test.dart
```

Expected: `+19: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```

Expected: the formatter changes 0 files; `No issues found!`; `+551: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/features/onboarding/view/restore_wallet_page.dart \
  lib/features/onboarding/widgets/seed_input.dart \
  lib/l10n/arb/app_en.arb \
  test/features/onboarding/restore_wallet_page_test.dart \
  test/features/onboarding/seed_input_test.dart
git commit -m "fix(restore): seed field without selection or autofill, explicit Paste, redacted controller" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 9: Biometric opt-in: strong biometrics only, and a failed enable is reported

Spec §6.2. `isAvailable` now requires an enrolled strong (Class 3) biometric on Android — the Keystore key is `strongBiometricOnly` — and Face ID or Touch ID on iOS (local_auth_android 1.0.56 reports enrolled classes as `weak` / `strong`). `enable` keeps returning its outcome (`true` stored, `false` refused, cancelled or failed); every caller now reports a `false` instead of dropping it: `PasswordGate` (Lock and Sign-in) sets `PasswordGateState.biometricsEnableFailed`, `WalletSetup.enableBiometrics` returns whether it failed (Create and Restore states carry `biometricsEnableFailed`), and the four pages show one SnackBar through the app-wide messenger, so it stays visible after the page has gone. Includes the first-time opt-in widget test from the Lock page.

**Files:**
- Create: `app/lib/features/auth/widgets/biometric_enable_notice.dart`
- Modify: `app/lib/l10n/arb/app_en.arb`
- Modify: `app/lib/features/onboarding/view/restore_wallet_page.dart`
- Modify: `app/lib/data/biometrics/biometric_store.dart`
- Modify: `app/lib/features/auth/domain/password_gate.dart`
- Modify: `app/lib/features/onboarding/bloc/wallet_setup.dart`
- Modify: `app/lib/features/onboarding/bloc/create_wallet_cubit.dart`
- Modify: `app/lib/features/onboarding/bloc/restore_wallet_cubit.dart`
- Modify: `app/lib/features/auth/view/locked_page.dart`
- Modify: `app/lib/features/auth/view/sign_in_page.dart`
- Modify: `app/lib/features/onboarding/view/create_wallet_page.dart`
- Modify: `app/test/support/fake_biometric_store.dart`
- Test (modify): `app/test/data/biometrics/device_biometric_store_test.dart`
- Test (modify): `app/test/features/onboarding/create_wallet_cubit_test.dart`
- Test (modify): `app/test/features/onboarding/restore_wallet_cubit_test.dart`
- Test (modify): `app/test/features/auth/unlock_cubit_test.dart`
- Test (modify): `app/test/features/auth/locked_page_test.dart`
- Test (modify): `app/test/features/auth/sign_in_page_test.dart`
- Test (modify): `app/test/features/onboarding/create_wallet_page_test.dart`

**Interfaces:**
- Consumes: M1-C `BiometricStore`, `PasswordGate`, `WalletSetup`, Create/Restore cubits and pages, Locked and Sign-in pages.
- Produces:
  - `PasswordGateState.biometricsEnableFailed` (`bool`, default false) and `next({..., bool biometricsEnableFailed = false})`.
  - `static Future<bool> WalletSetup.enableBiometrics(...)` — true when it was requested and could not be turned on.
  - `CreateWalletState.biometricsEnableFailed`, `RestoreWalletState.biometricsEnableFailed`.
  - `void showBiometricEnableFailed(BuildContext context)` (`lib/features/auth/widgets/biometric_enable_notice.dart`).
- Test support: `FakeBiometricStore.refuseEnable`.

- [ ] **Step 1: Write the failing tests**

Edit `app/test/data/biometrics/device_biometric_store_test.dart` (2 replacements, top to bottom):

1. Replace:

```dart

  test('available only with biometrics on a supported device', () async {
    when(() => localAuth.canCheckBiometrics).thenAnswer((_) async => true);
    when(localAuth.isDeviceSupported).thenAnswer((_) async => false);
```

   with:

```dart

  test('available only with biometrics on a supported device', () async {
    when(
      localAuth.getAvailableBiometrics,
    ).thenAnswer((_) async => [BiometricType.strong]);
    when(() => localAuth.canCheckBiometrics).thenAnswer((_) async => true);
    when(localAuth.isDeviceSupported).thenAnswer((_) async => false);
```

2. Replace:

```dart
    ).thenThrow(PlatformException(code: 'NotAvailable'));
    expect(await build().isAvailable(), isFalse);
  });

```

   with:

```dart
    ).thenThrow(PlatformException(code: 'NotAvailable'));
    expect(await build().isAvailable(), isFalse);
  });

  test('Android needs a strong (Class 3) biometric enrolled', () async {
    when(() => localAuth.canCheckBiometrics).thenAnswer((_) async => true);
    when(localAuth.isDeviceSupported).thenAnswer((_) async => true);
    when(
      localAuth.getAvailableBiometrics,
    ).thenAnswer((_) async => [BiometricType.weak]);
    expect(await build().isAvailable(), isFalse);
    when(
      localAuth.getAvailableBiometrics,
    ).thenAnswer((_) async => [BiometricType.weak, BiometricType.strong]);
    expect(await build().isAvailable(), isTrue);
  });

  test('iOS: Face ID or Touch ID enrolled', () async {
    when(() => localAuth.canCheckBiometrics).thenAnswer((_) async => true);
    when(localAuth.isDeviceSupported).thenAnswer((_) async => true);
    when(
      localAuth.getAvailableBiometrics,
    ).thenAnswer((_) async => [BiometricType.face]);
    expect(await build(isAndroid: false).isAvailable(), isTrue);
    when(localAuth.getAvailableBiometrics).thenAnswer((_) async => []);
    expect(await build(isAndroid: false).isAvailable(), isFalse);
  });

```


In `app/test/features/onboarding/create_wallet_cubit_test.dart`, replace:

```dart
    await submit(cubit, enableBiometrics: true);
    expect(cubit.state.status, CreateWalletStatus.done);
    expect(biometrics.passwords, isEmpty);
    expect(session.passwordFor('main'), _pw);
  });

```

with:

```dart
    await submit(cubit, enableBiometrics: true);
    expect(cubit.state.status, CreateWalletStatus.done);
    expect(cubit.state.biometricsEnableFailed, isTrue);
    expect(biometrics.passwords, isEmpty);
    expect(session.passwordFor('main'), _pw);
  });

  test('a refused opt-in is reported; creation still completes', () async {
    biometrics.refuseEnable = true;
    final cubit = build();
    await cubit.init();
    await submit(cubit, enableBiometrics: true);
    expect(cubit.state.status, CreateWalletStatus.done);
    expect(cubit.state.biometricsEnableFailed, isTrue);
  });

  test('no opt-in, nothing to report', () async {
    final cubit = build();
    await cubit.init();
    await submit(cubit);
    expect(cubit.state.biometricsEnableFailed, isFalse);
  });

```

In `app/test/features/onboarding/restore_wallet_cubit_test.dart`, replace:

```dart
    await submit(cubit, enableBiometrics: true);
    expect(cubit.state.status, RestoreWalletStatus.done);
    expect(biometrics.passwords, isEmpty);
  });

```

with:

```dart
    await submit(cubit, enableBiometrics: true);
    expect(cubit.state.status, RestoreWalletStatus.done);
    expect(cubit.state.biometricsEnableFailed, isTrue);
    expect(biometrics.passwords, isEmpty);
  });

  test('a refused opt-in is reported; the restore still completes', () async {
    seeds.result = const SeedAccepted('alpha', isBip39: true);
    biometrics.refuseEnable = true;
    final cubit = build();
    await cubit.init();
    await submit(cubit, enableBiometrics: true);
    expect(cubit.state.status, RestoreWalletStatus.done);
    expect(cubit.state.biometricsEnableFailed, isTrue);
  });

```

In `app/test/features/auth/unlock_cubit_test.dart`, replace:

```dart
    });
  });
}
```

with:

```dart
    });
  });

  test('a refused opt-in still unlocks, and is reported', () async {
    biometrics.refuseEnable = true;
    final cubit = await build();
    await cubit.unlockWithPassword(_pw, enableBiometrics: true);
    expect(unlocked, 1);
    expect(cubit.state.biometricsEnabled, isFalse);
    expect(cubit.state.biometricsEnableFailed, isTrue);
  });

  test('an accepted opt-in is not reported as failed', () async {
    final cubit = await build();
    await cubit.unlockWithPassword(_pw, enableBiometrics: true);
    expect(cubit.state.biometricsEnabled, isTrue);
    expect(cubit.state.biometricsEnableFailed, isFalse);
  });
}
```

Edit `app/test/features/auth/locked_page_test.dart` (2 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/view/locked_page.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
```

   with:

```dart
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/view/locked_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
```

2. Replace:

```dart
    expect(back.handlesBack.last, isTrue);
  });
}
```

   with:

```dart
    expect(back.handlesBack.last, isTrue);
  });

  group('first-time biometric opt-in', () {
    testWidgets('tick, unlock with the password: biometrics are on', (
      t,
    ) async {
      await pump(t);
      final box = find.byKey(const Key('locked.enableBiometrics'));
      expect(box, findsOneWidget);
      expect(t.widget<CheckboxListTile>(box).value, isFalse);
      await tapKey(t, 'locked.enableBiometrics');
      expect(t.widget<CheckboxListTile>(box).value, isTrue);
      await submit(t, _pw);
      expect(lock.state, const Unlocked());
      expect(biometrics.passwords['main'], _pw);
    });

    testWidgets('a refused opt-in unlocks and says so', (t) async {
      biometrics.refuseEnable = true;
      await pump(t);
      await tapKey(t, 'locked.enableBiometrics');
      await submit(t, _pw);
      expect(lock.state, const Unlocked());
      expect(
        find.text(
          "Fingerprint unlock wasn't turned on. You can try again the next "
          'time you unlock.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no strong biometric: no opt-in offered', (t) async {
      biometrics.available = false;
      await pump(t);
      expect(find.byKey(const Key('locked.enableBiometrics')), findsNothing);
    });
  });
}
```


In `app/test/features/auth/sign_in_page_test.dart`, replace:

```dart
    expect(find.text('route:${Routes.welcome}'), findsOneWidget);
  });
}
```

with:

```dart
    expect(find.text('route:${Routes.welcome}'), findsOneWidget);
  });

  testWidgets('a refused biometric opt-in signs in and says so', (t) async {
    biometrics.refuseEnable = true;
    await pump(t);
    await tapKey(t, 'signin.enableBiometrics');
    await submit(t, _pw);
    expect(repo.calls, ['signIn:main']);
    expect(
      find.text(
        "Fingerprint unlock wasn't turned on. You can try again the next "
        'time you unlock.',
      ),
      findsOneWidget,
    );
  });
}
```

In `app/test/features/onboarding/create_wallet_page_test.dart`, replace:

```dart
    );
  });
}
```

with:

```dart
    );
  });

  testWidgets('a refused biometric opt-in is reported after create', (
    t,
  ) async {
    biometrics.refuseEnable = true;
    await pump(t);
    await enterKey(t, 'create.name', 'main');
    await enterKey(t, 'create.password', _pw);
    await enterKey(t, 'create.confirm', _pw);
    await tapKey(t, 'create.biometrics');
    await tapKey(t, 'create.submit');
    await t.pump();
    expect(repo.calls, ['create:main']);
    expect(
      find.text(
        "Fingerprint unlock wasn't turned on. You can try again the next "
        'time you unlock.',
      ),
      findsOneWidget,
    );
  });
}
```

Edit `app/test/support/fake_biometric_store.dart` (2 replacements, top to bottom):

1. Replace:

```dart
  /// When set, [enable] throws it.
  Exception? enableError;

  /// When set, [isEnabled] throws it (a marker read error).
```

   with:

```dart
  /// When set, [enable] throws it.
  Exception? enableError;

  /// Simulates a refused or cancelled enable prompt: [enable] is false.
  bool refuseEnable = false;

  /// When set, [isEnabled] throws it (a marker read error).
```

2. Replace:

```dart
    final error = enableError;
    if (error != null) throw error;
    if (!available) return false;
    passwords[wallet] = password;
    return true;
```

   with:

```dart
    final error = enableError;
    if (error != null) throw error;
    if (!available || refuseEnable) return false;
    passwords[wallet] = password;
    return true;
```


- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/data/biometrics/device_biometric_store_test.dart \
  test/features/onboarding/create_wallet_cubit_test.dart \
  test/features/onboarding/restore_wallet_cubit_test.dart \
  test/features/auth/unlock_cubit_test.dart \
  test/features/auth/locked_page_test.dart \
  test/features/auth/sign_in_page_test.dart \
  test/features/onboarding/create_wallet_page_test.dart
```

Expected: FAIL. Compile errors such as `The getter 'biometricsEnableFailed' isn't defined for the type 'PasswordGateState'` (and for the Create/Restore states). Once those exist, `device_biometric_store_test.dart` would still fail: a weak-only device counts as available until `getAvailableBiometrics` is consulted.

- [ ] **Step 3: Implement**

`app_en.arb` grows at the end in every task that adds strings. The replacement below adds a comma to the current last entry and appends this task's entries.

In `app/lib/l10n/arb/app_en.arb`, replace:

```json
  "linkNotPayment": "That link isn't a DigiByte payment request.",
  "linkNoWallet": "Create or restore a wallet first, then open the payment link again.",
  "seedPaste": "Paste"
}
```

with:

```json
  "linkNotPayment": "That link isn't a DigiByte payment request.",
  "linkNoWallet": "Create or restore a wallet first, then open the payment link again.",
  "seedPaste": "Paste",
  "biometricsEnableFailed": "Fingerprint unlock wasn't turned on. You can try again the next time you unlock."
}
```

Edit `app/lib/features/onboarding/view/restore_wallet_page.dart` (2 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';
import 'package:digibyte_dex/features/onboarding/bloc/restore_wallet_cubit.dart';
import 'package:digibyte_dex/features/onboarding/widgets/seed_input.dart';
```

   with:

```dart
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';
import 'package:digibyte_dex/features/auth/widgets/biometric_enable_notice.dart';
import 'package:digibyte_dex/features/onboarding/bloc/restore_wallet_cubit.dart';
import 'package:digibyte_dex/features/onboarding/widgets/seed_input.dart';
```

2. Replace:

```dart
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<RestoreWalletCubit, RestoreWalletState>(
      builder: (context, state) {
        final busy =
```

   with:

```dart
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<RestoreWalletCubit, RestoreWalletState>(
      listenWhen: (before, after) =>
          !before.biometricsEnableFailed && after.biometricsEnableFailed,
      listener: (context, _) => showBiometricEnableFailed(context),
      builder: (context, state) {
        final busy =
```


Edit `app/lib/data/biometrics/biometric_store.dart` (2 replacements, top to bottom):

1. Replace:

```dart
  Future<bool> isEnabled(String wallet);

  /// Stores [password] for [wallet] (prompts on Android). False if refused.
  Future<bool> enable(String wallet, String password);

```

   with:

```dart
  Future<bool> isEnabled(String wallet);

  /// Stores [password] for [wallet] (prompts on Android). The outcome:
  /// true when stored, false when refused, cancelled or failed. Callers
  /// tell the user about a false (never silent).
  Future<bool> enable(String wallet, String password);

```

2. Replace:

```dart
  Future<void> _forget(String wallet) => _markers.delete(_marker(wallet));

  @override
  Future<bool> isAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics &&
          await _localAuth.isDeviceSupported();
    } on PlatformException {
      return false;
```

   with:

```dart
  Future<void> _forget(String wallet) => _markers.delete(_marker(wallet));

  /// A strong (Class 3) biometric must be enrolled on Android: the
  /// Keystore key in [androidOptions] is `strongBiometricOnly`, so a
  /// weak-only device could never store the password. local_auth_android
  /// 1.0.56 reports enrolled classes as `weak` / `strong`; iOS reports
  /// `face` / `fingerprint`.
  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _localAuth.canCheckBiometrics ||
          !await _localAuth.isDeviceSupported()) {
        return false;
      }
      final enrolled = await _localAuth.getAvailableBiometrics();
      return _isAndroid
          ? enrolled.contains(BiometricType.strong)
          : enrolled.contains(BiometricType.face) ||
                enrolled.contains(BiometricType.fingerprint);
    } on PlatformException {
      return false;
```


Edit `app/lib/features/auth/domain/password_gate.dart` (7 replacements, top to bottom):

1. Replace:

```dart
    this.biometricsEnabled = false,
    this.biometricsInvalidated = false,
  });

```

   with:

```dart
    this.biometricsEnabled = false,
    this.biometricsInvalidated = false,
    this.biometricsEnableFailed = false,
  });

```

2. Replace:

```dart
  final bool biometricsInvalidated;

  /// The next state. [failure] resets unless given. [blockedUntil] is kept
  /// unless a new one is given or [unblock] is set.
```

   with:

```dart
  final bool biometricsInvalidated;

  /// The user asked to turn biometrics on with a successful password, and
  /// it did not work (refused, cancelled or failed). The page says so.
  final bool biometricsEnableFailed;

  /// The next state. [failure] resets unless given. [blockedUntil] is kept
  /// unless a new one is given or [unblock] is set.
```

3. Replace:

```dart
    bool? biometricsEnabled,
    bool? biometricsInvalidated,
  }) => PasswordGateState(
    status: status,
```

   with:

```dart
    bool? biometricsEnabled,
    bool? biometricsInvalidated,
    bool biometricsEnableFailed = false,
  }) => PasswordGateState(
    status: status,
```

4. Replace:

```dart
    biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
    biometricsInvalidated: biometricsInvalidated ?? this.biometricsInvalidated,
  );

```

   with:

```dart
    biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
    biometricsInvalidated: biometricsInvalidated ?? this.biometricsInvalidated,
    biometricsEnableFailed: biometricsEnableFailed,
  );

```

5. Replace:

```dart
    biometricsEnabled,
    biometricsInvalidated,
  ];
}
```

   with:

```dart
    biometricsEnabled,
    biometricsInvalidated,
    biometricsEnableFailed,
  ];
}
```

6. Replace:

```dart
    final state = _read();
    var enabled = state.biometricsEnabled;
    if (enableBiometrics && state.biometricsAvailable && !enabled) {
      try {
        enabled = await _biometrics.enable(wallet, password);
      } on Object catch (error) {
        // Biometrics simply stay off; the password already worked.
        debugPrint('Biometric enable failed: ${error.runtimeType}');
      }
```

   with:

```dart
    final state = _read();
    var enabled = state.biometricsEnabled;
    final requested = enableBiometrics && state.biometricsAvailable && !enabled;
    if (requested) {
      try {
        enabled = await _biometrics.enable(wallet, password);
      } on Object catch (error) {
        // Biometrics stay off; the password already worked. The page
        // reports it (biometricsEnableFailed).
        debugPrint('Biometric enable failed: ${error.runtimeType}');
      }
```

7. Replace:

```dart
        biometricsEnabled: enabled,
        biometricsInvalidated: state.biometricsInvalidated && !enabled,
      ),
    );
```

   with:

```dart
        biometricsEnabled: enabled,
        biometricsInvalidated: state.biometricsInvalidated && !enabled,
        biometricsEnableFailed: requested && !enabled,
      ),
    );
```


Edit `app/lib/features/onboarding/bloc/wallet_setup.dart` (2 replacements, top to bottom):

1. Replace:

```dart

  /// Stores [password] behind biometrics for [wallet] when the user
  /// [requested] it and the device has biometrics [available].
  ///
  /// Never throws: the wallet already exists, so a failure here just
  /// leaves biometrics off.
  static Future<void> enableBiometrics(
    BiometricStore biometrics, {
    required String wallet,
```

   with:

```dart

  /// Stores [password] behind biometrics for [wallet] when the user
  /// [requested] it and the device has biometrics [available]. True when
  /// it was requested and could not be turned on, so the page says so.
  ///
  /// Never throws: the wallet already exists, so a failure here just
  /// leaves biometrics off.
  static Future<bool> enableBiometrics(
    BiometricStore biometrics, {
    required String wallet,
```

2. Replace:

```dart
    required bool available,
  }) async {
    if (!requested || !available) return;
    try {
      await biometrics.enable(wallet, password);
    } on Object {
      // Biometrics simply stay off.
    }
  }
```

   with:

```dart
    required bool available,
  }) async {
    if (!requested || !available) return false;
    try {
      return !await biometrics.enable(wallet, password);
    } on Object {
      return true;
    }
  }
```


Edit `app/lib/features/onboarding/bloc/create_wallet_cubit.dart` (5 replacements, top to bottom):

1. Replace:

```dart
    this.failure,
    this.biometricsAvailable = false,
  });

```

   with:

```dart
    this.failure,
    this.biometricsAvailable = false,
    this.biometricsEnableFailed = false,
  });

```

2. Replace:

```dart
  final WalletFailure? failure;
  final bool biometricsAvailable;

  CreateWalletState copyWith({bool? biometricsAvailable}) => CreateWalletState(
```

   with:

```dart
  final WalletFailure? failure;
  final bool biometricsAvailable;

  /// Done, but the requested biometric unlock could not be turned on.
  final bool biometricsEnableFailed;

  CreateWalletState copyWith({bool? biometricsAvailable}) => CreateWalletState(
```

3. Replace:

```dart
    failure,
    biometricsAvailable,
  ];
}
```

   with:

```dart
    failure,
    biometricsAvailable,
    biometricsEnableFailed,
  ];
}
```

4. Replace:

```dart
      return;
    }
    await WalletSetup.enableBiometrics(
      _biometrics,
      wallet: walletName,
```

   with:

```dart
      return;
    }
    final bioFailed = await WalletSetup.enableBiometrics(
      _biometrics,
      wallet: walletName,
```

5. Replace:

```dart
        status: CreateWalletStatus.done,
        biometricsAvailable: bio,
      ),
    );
```

   with:

```dart
        status: CreateWalletStatus.done,
        biometricsAvailable: bio,
        biometricsEnableFailed: bioFailed,
      ),
    );
```


Edit `app/lib/features/onboarding/bloc/restore_wallet_cubit.dart` (5 replacements, top to bottom):

1. Replace:

```dart
    this.failure,
    this.biometricsAvailable = false,
  });

```

   with:

```dart
    this.failure,
    this.biometricsAvailable = false,
    this.biometricsEnableFailed = false,
  });

```

2. Replace:

```dart
  final WalletFailure? failure;
  final bool biometricsAvailable;

  RestoreWalletState copyWith({bool? biometricsAvailable}) =>
```

   with:

```dart
  final WalletFailure? failure;
  final bool biometricsAvailable;

  /// Done, but the requested biometric unlock could not be turned on.
  final bool biometricsEnableFailed;

  RestoreWalletState copyWith({bool? biometricsAvailable}) =>
```

3. Replace:

```dart
    failure,
    biometricsAvailable,
  ];
}
```

   with:

```dart
    failure,
    biometricsAvailable,
    biometricsEnableFailed,
  ];
}
```

4. Replace:

```dart
    // Restored: the name is now ours, whatever the lookup said.
    await _clearBackupFlag(walletName);
    await WalletSetup.enableBiometrics(
      _biometrics,
      wallet: walletName,
```

   with:

```dart
    // Restored: the name is now ours, whatever the lookup said.
    await _clearBackupFlag(walletName);
    final bioFailed = await WalletSetup.enableBiometrics(
      _biometrics,
      wallet: walletName,
```

5. Replace:

```dart
        status: RestoreWalletStatus.done,
        biometricsAvailable: bio,
      ),
    );
```

   with:

```dart
        status: RestoreWalletStatus.done,
        biometricsAvailable: bio,
        biometricsEnableFailed: bioFailed,
      ),
    );
```


Create `app/lib/features/auth/widgets/biometric_enable_notice.dart`:

```dart
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Tells the user that the biometric unlock they asked for was not turned
/// on (never silent). The app-wide messenger keeps it on screen after the
/// page that asked has gone.
void showBiometricEnableFailed(BuildContext context) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.biometricsEnableFailed)),
    );
```

Edit `app/lib/features/auth/view/locked_page.dart` (2 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/features/auth/bloc/unlock_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/widgets/password_gate_form.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
```

   with:

```dart
import 'package:digibyte_dex/features/auth/bloc/unlock_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/widgets/biometric_enable_notice.dart';
import 'package:digibyte_dex/features/auth/widgets/password_gate_form.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
```

2. Replace:

```dart
    final l10n = context.l10n;
    final cubit = context.read<UnlockCubit>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.lockedTitle),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              l10n.lockedWallet(walletName),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            BlocBuilder<UnlockCubit, UnlockState>(
              builder: (context, state) => PasswordGateForm(
                idPrefix: 'locked',
                state: state,
                submitLabel: l10n.unlockSubmit,
                onSubmit: (password, {required enableBiometrics}) => unawaited(
                  cubit.unlockWithPassword(
                    password,
                    enableBiometrics: enableBiometrics,
                  ),
                ),
                onBiometrics: () => unawaited(
                  cubit.unlockWithBiometrics(reason: l10n.biometricReason),
                ),
                onLockoutExpired: cubit.lockoutExpired,
              ),
            ),
          ],
        ),
      ),
```

   with:

```dart
    final l10n = context.l10n;
    final cubit = context.read<UnlockCubit>();
    return BlocListener<UnlockCubit, UnlockState>(
      listenWhen: (before, after) =>
          !before.biometricsEnableFailed && after.biometricsEnableFailed,
      listener: (context, _) => showBiometricEnableFailed(context),
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.lockedTitle),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                l10n.lockedWallet(walletName),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              BlocBuilder<UnlockCubit, UnlockState>(
                builder: (context, state) => PasswordGateForm(
                  idPrefix: 'locked',
                  state: state,
                  submitLabel: l10n.unlockSubmit,
                  onSubmit: (password, {required enableBiometrics}) =>
                      unawaited(
                        cubit.unlockWithPassword(
                          password,
                          enableBiometrics: enableBiometrics,
                        ),
                      ),
                  onBiometrics: () => unawaited(
                    cubit.unlockWithBiometrics(reason: l10n.biometricReason),
                  ),
                  onLockoutExpired: cubit.lockoutExpired,
                ),
              ),
            ],
          ),
        ),
      ),
```


Edit `app/lib/features/auth/view/sign_in_page.dart` (2 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/features/auth/bloc/sign_in_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/widgets/password_gate_form.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
```

   with:

```dart
import 'package:digibyte_dex/features/auth/bloc/sign_in_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/widgets/biometric_enable_notice.dart';
import 'package:digibyte_dex/features/auth/widgets/password_gate_form.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
```

2. Replace:

```dart
    final l10n = context.l10n;
    final cubit = context.read<SignInCubit>();
    return BlocBuilder<SignInCubit, SignInState>(
      builder: (context, state) {
        final busy = state.status == SignInStatus.busy;
```

   with:

```dart
    final l10n = context.l10n;
    final cubit = context.read<SignInCubit>();
    return BlocConsumer<SignInCubit, SignInState>(
      listenWhen: (before, after) =>
          !before.gate.biometricsEnableFailed &&
          after.gate.biometricsEnableFailed,
      listener: (context, _) => showBiometricEnableFailed(context),
      builder: (context, state) {
        final busy = state.status == SignInStatus.busy;
```


Edit `app/lib/features/onboarding/view/create_wallet_page.dart` (2 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/onboarding/bloc/create_wallet_cubit.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
```

   with:

```dart
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/auth/widgets/biometric_enable_notice.dart';
import 'package:digibyte_dex/features/onboarding/bloc/create_wallet_cubit.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
```

2. Replace:

```dart
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<CreateWalletCubit, CreateWalletState>(
      builder: (context, state) {
        final busy =
```

   with:

```dart
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<CreateWalletCubit, CreateWalletState>(
      listenWhen: (before, after) =>
          !before.biometricsEnableFailed && after.biometricsEnableFailed,
      listener: (context, _) => showBiometricEnableFailed(context),
      builder: (context, state) {
        final busy =
```


Then regenerate the localizations:

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter gen-l10n
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/data/biometrics/device_biometric_store_test.dart \
  test/features/onboarding/create_wallet_cubit_test.dart \
  test/features/onboarding/restore_wallet_cubit_test.dart \
  test/features/auth/unlock_cubit_test.dart \
  test/features/auth/locked_page_test.dart \
  test/features/auth/sign_in_page_test.dart \
  test/features/onboarding/create_wallet_page_test.dart
```

Expected: `+92: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```

Expected: the formatter changes 0 files; `No issues found!`; `+563: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/data/biometrics/biometric_store.dart \
  lib/features/auth/domain/password_gate.dart \
  lib/features/auth/view/locked_page.dart \
  lib/features/auth/view/sign_in_page.dart \
  lib/features/auth/widgets/biometric_enable_notice.dart \
  lib/features/onboarding/bloc/create_wallet_cubit.dart \
  lib/features/onboarding/bloc/restore_wallet_cubit.dart \
  lib/features/onboarding/bloc/wallet_setup.dart \
  lib/features/onboarding/view/create_wallet_page.dart \
  lib/features/onboarding/view/restore_wallet_page.dart \
  lib/l10n/arb/app_en.arb \
  test/data/biometrics/device_biometric_store_test.dart \
  test/features/auth/locked_page_test.dart \
  test/features/auth/sign_in_page_test.dart \
  test/features/auth/unlock_cubit_test.dart \
  test/features/onboarding/create_wallet_cubit_test.dart \
  test/features/onboarding/create_wallet_page_test.dart \
  test/features/onboarding/restore_wallet_cubit_test.dart \
  test/support/fake_biometric_store.dart
git commit -m "fix(biometrics): require strong biometrics and report a failed opt-in" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 10: One password gate: the backup prompt goes through `PasswordGate`

Spec §6.3. After a restart the backup page asks for the password; that attempt now runs through `PasswordGate` with the shared `PasswordAttempts`, so it is refused during a lockout, a wrong password counts towards it, and a right one resets it — one counter for unlock, sign-in, Confirm (Task 5) and backup. The prompt shows the same lockout countdown and clears the field on each submit.

**Files:**
- Modify: `app/lib/features/onboarding/bloc/backup_cubit.dart`
- Modify: `app/lib/features/onboarding/view/backup_page.dart`
- Test (modify): `app/test/features/onboarding/backup_cubit_test.dart`
- Test (modify): `app/test/features/onboarding/backup_page_test.dart`

**Interfaces:**
- Consumes: M1-C `PasswordGate`, `PasswordAttempts`, `BiometricStore`, `LockoutCountdown`, `WalletFailure.lockedOut`.
- Produces: `BackupCubit` gains `required PasswordAttempts attempts` and `required BiometricStore biometrics` and `void lockoutExpired()`; `BackupNeedsPassword` gains `DateTime? blockedUntil`; widget id `backup.lockout`.

- [ ] **Step 1: Write the failing tests**

Edit `app/test/features/onboarding/backup_cubit_test.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/onboarding/bloc/backup_cubit.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';
```

   with:

```dart
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/onboarding/bloc/backup_cubit.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_biometric_store.dart';
import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';
```

2. Replace:

```dart
  late BackupStatusStore backups;
  late PendingBackupSession session;
  late int completions;

  setUp(() async {
    repo = FakeWalletRepository();
    backups = BackupStatusStore(InMemoryKeyValueStore());
    session = PendingBackupSession();
```

   with:

```dart
  late BackupStatusStore backups;
  late PendingBackupSession session;
  late PasswordAttempts attempts;
  late int completions;

  setUp(() async {
    repo = FakeWalletRepository();
    attempts = PasswordAttempts(
      LockoutStore(InMemoryKeyValueStore()),
      now: () => DateTime.utc(2026, 10, 4, 12),
    );
    backups = BackupStatusStore(InMemoryKeyValueStore());
    session = PendingBackupSession();
```

3. Replace:

```dart
      backups: backups,
      session: session,
      onCompleted: () async => completions++,
      random: Random(7),
```

   with:

```dart
      backups: backups,
      session: session,
      attempts: attempts,
      biometrics: FakeBiometricStore(),
      onCompleted: () async => completions++,
      random: Random(7),
```

4. Replace:

```dart
    expect(cubit.state, BackupShowingWords(repo.seedWords));
    expect(await backups.isPending('main'), isTrue);
  });

```

   with:

```dart
    expect(cubit.state, BackupShowingWords(repo.seedWords));
    expect(await backups.isPending('main'), isTrue);
  });

  test('wrong passwords count in the shared lockout', () async {
    final cubit = build();
    await cubit.start();
    for (var i = 0; i < 5; i++) {
      await cubit.submitPassword('Wrong-Horse-1');
    }
    final asking = cubit.state as BackupNeedsPassword;
    expect(asking.blockedUntil, isNotNull);
    // The same counter the lock screen and sign-in read.
    expect(await attempts.blockedUntil('main'), asking.blockedUntil);
    final reveals = repo.calls.length;
    await cubit.submitPassword(repo.correctPassword);
    expect(cubit.state, isA<BackupNeedsPassword>());
    expect(repo.calls, hasLength(reveals));
  });

  test('a lockout from the lock screen also blocks the backup', () async {
    for (var i = 0; i < 5; i++) {
      await attempts.fail('main');
    }
    final cubit = build();
    await cubit.start();
    expect((cubit.state as BackupNeedsPassword).blockedUntil, isNotNull);
    await cubit.submitPassword(repo.correctPassword);
    expect(repo.calls, isEmpty);
  });

  test('the right password resets the shared count', () async {
    await attempts.fail('main');
    final cubit = build();
    await cubit.start();
    await cubit.submitPassword(repo.correctPassword);
    expect(cubit.state, BackupShowingWords(repo.seedWords));
    for (var i = 0; i < 4; i++) {
      await attempts.fail('main');
    }
    expect(await attempts.blockedUntil('main'), isNull);
  });

```


Edit `app/test/features/onboarding/backup_page_test.dart` (4 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:digibyte_dex/features/onboarding/view/backup_page.dart';
```

   with:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:digibyte_dex/features/onboarding/view/backup_page.dart';
```

2. Replace:

```dart
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';
```

   with:

```dart
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_biometric_store.dart';
import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';
```

3. Replace:

```dart
          RepositoryProvider.value(value: backups),
          RepositoryProvider.value(value: session),
        ],
        child: BlocProvider.value(value: auth, child: const BackupPage()),
```

   with:

```dart
          RepositoryProvider.value(value: backups),
          RepositoryProvider.value(value: session),
          RepositoryProvider.value(
            value: PasswordAttempts(LockoutStore(InMemoryKeyValueStore())),
          ),
          RepositoryProvider<BiometricStore>.value(
            value: FakeBiometricStore(),
          ),
        ],
        child: BlocProvider.value(value: auth, child: const BackupPage()),
```

4. Replace:

```dart
  });

  testWidgets('passing the quiz clears the pending backup', (t) async {
    session.start('main', repo.correctPassword);
```

   with:

```dart
  });

  testWidgets('five wrong passwords show the shared lockout countdown', (
    t,
  ) async {
    await pump(t);
    for (var i = 0; i < 5; i++) {
      await enterKey(t, 'backup.password', 'Wrong-Horse-1');
      await tapKey(t, 'backup.reveal');
      await t.pump();
    }
    expect(find.byKey(const Key('backup.lockout')), findsOneWidget);
    expect(
      t.widget<FilledButton>(find.byKey(const Key('backup.reveal'))).onPressed,
      isNull,
    );
  });

  testWidgets('passing the quiz clears the pending backup', (t) async {
    session.start('main', repo.correctPassword);
```


- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/features/onboarding/backup_cubit_test.dart \
  test/features/onboarding/backup_page_test.dart
```

Expected: FAIL. `No named parameter with the name 'attempts'` / `'biometrics'` for `BackupCubit`, and `The getter 'blockedUntil' isn't defined for the type 'BackupNeedsPassword'`.

- [ ] **Step 3: Implement**

Edit `app/lib/features/onboarding/bloc/backup_cubit.dart` (6 replacements, top to bottom):

1. Replace:

```dart
import 'dart:math';

import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:equatable/equatable.dart';
```

   with:

```dart
import 'dart:math';

import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/domain/password_gate.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:equatable/equatable.dart';
```

2. Replace:

```dart
}

/// The create session is gone (app killed or locked): ask again.
final class BackupNeedsPassword extends BackupState {
  const BackupNeedsPassword({this.failure, this.busy = false});

  final WalletFailure? failure;
  final bool busy;

  @override
  List<Object?> get props => [failure, busy];
}

```

   with:

```dart
}

/// The create session is gone (app killed or locked): ask again. Attempts
/// go through the shared wrong-password lockout.
final class BackupNeedsPassword extends BackupState {
  const BackupNeedsPassword({
    this.failure,
    this.busy = false,
    this.blockedUntil,
  });

  final WalletFailure? failure;
  final bool busy;

  /// Attempts are refused until then (the shared lockout).
  final DateTime? blockedUntil;

  @override
  List<Object?> get props => [failure, busy, blockedUntil];
}

```

3. Replace:

```dart
    required BackupStatusStore backups,
    required PendingBackupSession session,
    required Future<void> Function() onCompleted,
    Random? random,
```

   with:

```dart
    required BackupStatusStore backups,
    required PendingBackupSession session,
    required PasswordAttempts attempts,
    required BiometricStore biometrics,
    required Future<void> Function() onCompleted,
    Random? random,
```

4. Replace:

```dart
       _onCompleted = onCompleted,
       _random = random ?? Random.secure(),
       super(const BackupStarting());

  static const questionCount = 4;
```

   with:

```dart
       _onCompleted = onCompleted,
       _random = random ?? Random.secure(),
       super(const BackupStarting()) {
    _gate = PasswordGate(
      attempts: attempts,
      biometrics: biometrics,
      read: () => _gateState,
      write: (gate) {
        _gateState = gate;
        if (state is BackupNeedsPassword) _emit(_asking(gate));
      },
    );
  }

  static const questionCount = 4;
```

5. Replace:

```dart
  final Future<void> Function() _onCompleted;
  final Random _random;
  List<String> _words = const [];

  /// Reveals at once with the create session's password, else asks for it.
  Future<void> start() async {
    final password = _session.passwordFor(walletName);
    if (password == null) {
      _emit(const BackupNeedsPassword());
      return;
    }
```

   with:

```dart
  final Future<void> Function() _onCompleted;
  final Random _random;
  late final PasswordGate _gate;
  PasswordGateState _gateState = const PasswordGateState();
  List<String> _words = const [];

  static BackupNeedsPassword _asking(PasswordGateState gate) =>
      BackupNeedsPassword(
        failure: gate.failure,
        busy: gate.status == PasswordGateStatus.busy,
        blockedUntil: gate.blockedUntil,
      );

  /// Reveals at once with the create session's password, else asks for it
  /// (showing any running lockout).
  Future<void> start() async {
    final password = _session.passwordFor(walletName);
    if (password == null) {
      await _gate.load(walletName, (gate) => _gateState = gate);
      _emit(_asking(_gateState));
      return;
    }
```

6. Replace:

```dart
  }

  Future<void> submitPassword(String password) async {
    _emit(const BackupNeedsPassword(busy: true));
    await _reveal(password);
  }

  Future<void> _reveal(String password) async {
    try {
```

   with:

```dart
  }

  /// One password attempt through [PasswordGate]: refused during a
  /// lockout, and a wrong password counts towards it, exactly like the
  /// lock screen and sign-in (one shared counter).
  Future<void> submitPassword(String password) async {
    List<String>? words;
    final ok = await _gate.tryPassword(
      walletName,
      password,
      check: (password) async {
        words = await _wallet.revealSeed(password);
      },
    );
    final revealed = words;
    if (!ok || revealed == null) return;
    _words = revealed;
    _emit(BackupShowingWords(List.unmodifiable(_words)));
  }

  /// The lockout countdown reached zero.
  void lockoutExpired() => _gate.lockoutExpired();

  /// The create session's password: no gate, it was just set.
  Future<void> _reveal(String password) async {
    try {
```


Edit `app/lib/features/onboarding/view/backup_page.dart` (6 replacements, top to bottom):

1. Replace:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/onboarding/bloc/backup_cubit.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
```

   with:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/widgets/lockout_countdown.dart';
import 'package:digibyte_dex/features/onboarding/bloc/backup_cubit.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
```

2. Replace:

```dart
          backups: context.read<BackupStatusStore>(),
          session: context.read<PendingBackupSession>(),
          onCompleted: context.read<AuthCubit>().refreshBackupStatus,
        );
```

   with:

```dart
          backups: context.read<BackupStatusStore>(),
          session: context.read<PendingBackupSession>(),
          attempts: context.read<PasswordAttempts>(),
          biometrics: context.read<BiometricStore>(),
          onCompleted: context.read<AuthCubit>().refreshBackupStatus,
        );
```

3. Replace:

```dart
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = widget.state.busy;
    return ListView(
      padding: const EdgeInsets.all(24),
```

   with:

```dart
  }

  /// The field is cleared on each submit, so it is empty after a failure.
  void _submit() {
    final password = _password.text;
    _password.clear();
    unawaited(context.read<BackupCubit>().submitPassword(password));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = widget.state.busy;
    final blockedUntil = widget.state.blockedUntil;
    final failure = widget.state.failure;
    return ListView(
      padding: const EdgeInsets.all(24),
```

4. Replace:

```dart
            key: const Key('backup.password'),
            controller: _password,
            enabled: !busy,
            obscureText: true,
            autocorrect: false,
```

   with:

```dart
            key: const Key('backup.password'),
            controller: _password,
            enabled: !busy && blockedUntil == null,
            obscureText: true,
            autocorrect: false,
```

5. Replace:

```dart
            decoration: InputDecoration(
              labelText: l10n.passwordLabel,
              errorText: widget.state.failure?.message(l10n),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Tagged(
```

   with:

```dart
            decoration: InputDecoration(
              labelText: l10n.passwordLabel,
              errorText: failure == null || failure == WalletFailure.lockedOut
                  ? null
                  : failure.message(l10n),
            ),
          ),
        ),
        if (blockedUntil != null) ...[
          const SizedBox(height: 12),
          LockoutCountdown(
            id: 'backup.lockout',
            until: blockedUntil,
            now: context.read<PasswordAttempts>().now,
            onExpired: context.read<BackupCubit>().lockoutExpired,
          ),
        ],
        const SizedBox(height: 24),
        Tagged(
```

6. Replace:

```dart
          child: FilledButton(
            key: const Key('backup.reveal'),
            onPressed: busy
                ? null
                : () => unawaited(
                    context.read<BackupCubit>().submitPassword(_password.text),
                  ),
            child: busy
                ? const BusyIndicator('backup.busy')
```

   with:

```dart
          child: FilledButton(
            key: const Key('backup.reveal'),
            onPressed: busy || blockedUntil != null ? null : _submit,
            child: busy
                ? const BusyIndicator('backup.busy')
```


- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/features/onboarding/backup_cubit_test.dart \
  test/features/onboarding/backup_page_test.dart
```

Expected: `+19: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```

Expected: the formatter changes 0 files; `No issues found!`; `+567: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/features/onboarding/bloc/backup_cubit.dart \
  lib/features/onboarding/view/backup_page.dart \
  test/features/onboarding/backup_cubit_test.dart \
  test/features/onboarding/backup_page_test.dart
git commit -m "fix(backup): the backup password prompt uses the shared lockout gate" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 11: Startup leftovers: orphaned KDF in any state, SDK disposed on a failed start, secure-storage log line

Spec §6.4 and §6.5.
- `stopOrphanedKdf` stops a leftover KDF in any status but `notRunning` (`MainStatus` in `komodo_defi_framework/lib/src/operations/kdf_operations_interface.dart:8-31`), so one caught mid-startup (`noContext`, `noRpc`) is stopped too (departure 4). Its doc comment states the one-engine-per-process assumption.
- `main.dart` builds the services through `disposeOnFailure`, so an error after `startSdk` (for example in `SdkSeedValidator.init`) disposes the SDK — and its KDF — before the error screen's Retry starts a new one.
- **The secure-storage warning** ("EncryptedSharedPreferences initialization failed. Falling back to custom ciphers.", every cold start) is flutter_secure_storage 10.3.4's own migration probe, once per namespace that holds data (`dgbdex_state`, `dgbdex_bio`, and the SDK's default namespace). Until a namespace has been migrated from the deprecated Jetpack EncryptedSharedPreferences, `FlutterSecureStorage.java` opens the namespace's file as EncryptedSharedPreferences (`:184-266`, `:1460-1476`); its `getAll` cannot decrypt the custom-cipher entries ("could not decrypt key"), the plugin logs that and continues with the custom ciphers. The "migrated" flag is only written after a real migration (`:1070-1078`), so the probe repeats; the data is untouched. Fixing it would mean turning on the plugin's `migrateWithBackup` path for existing users' data, which is riskier than the noise. It is documented on `SecureKeyValueStore`, and a test pins that persisted state (backup flag, lockout, biometric marker) survives a restart. Task 13 counts the lines on the device.

**Files:**
- Modify: `app/lib/main.dart`
- Modify: `app/lib/bootstrap/sdk_bootstrap.dart`
- Modify: `app/lib/data/storage/key_value_store.dart`
- Test (modify): `app/test/bootstrap/sdk_bootstrap_test.dart`
- Test (modify): `app/test/data/storage/secure_key_value_store_test.dart`

**Interfaces:**
- Consumes: M1-C `stopOrphanedKdf`, `startSdk`, `SecureKeyValueStore`, `LockoutStore`, `BackupStatusStore`.
- Produces: `Future<T> disposeOnFailure<T>({required Future<T> Function() build, required Future<void> Function() dispose})` in `lib/bootstrap/sdk_bootstrap.dart`; `main.dart` gets `Future<AppServices> _services(KomodoDefiSdk sdk)`.

- [ ] **Step 1: Write the failing tests**

The `noContext` / `noRpc` cases wait out `kdfStop`'s real 0.5 s settle delay; that is expected.

Edit `app/test/bootstrap/sdk_bootstrap_test.dart` (4 replacements, top to bottom):

1. Replace:

```dart
/// check must stay on native status and stop calls.
class _NativeKdf implements IKdfOperations {
  _NativeKdf({required this.running});

  bool running;
  int stops = 0;
  final httpCalls = <String>[];
```

   with:

```dart
/// check must stay on native status and stop calls.
class _NativeKdf implements IKdfOperations {
  _NativeKdf({required this.running, this.startingStatus});

  bool running;

  /// A KDF caught mid-startup (`noContext` / `noRpc`).
  MainStatus? startingStatus;
  int stops = 0;
  final httpCalls = <String>[];
```

2. Replace:

```dart
  @override
  Future<MainStatus> kdfMainStatus() async =>
      running ? MainStatus.rpcIsUp : MainStatus.notRunning;

  @override
```

   with:

```dart
  @override
  Future<MainStatus> kdfMainStatus() async =>
      startingStatus ?? (running ? MainStatus.rpcIsUp : MainStatus.notRunning);

  @override
```

3. Replace:

```dart
    stops++;
    running = false;
    return StopStatus.ok;
  }
```

   with:

```dart
    stops++;
    running = false;
    startingStatus = null;
    return StopStatus.ok;
  }
```

4. Replace:

```dart
    });

    for (final running in [true, false]) {
      final name = running
          ? 'a KDF left running in this process is stopped, over FFI only'
          : 'with no KDF running nothing is stopped or dialled';
      test(name, () async {
        final native = _NativeKdf(running: running);
        final kdf = KomodoDefiFramework.createWithOperations(
          hostConfig: buildHostConfig(port: 41234, rpcPassword: 'Rpc-Pass-1!'),
          kdfOperations: native,
        );

        await stopOrphanedKdf(kdf);

        expect(native.stops, running ? 1 : 0);
        expect(native.running, isFalse);
        expect(native.httpCalls, isEmpty);
        expect(native.disposed, isTrue);
      });
    }
  });
}
```

   with:

```dart
    });

    KomodoDefiFramework framework(_NativeKdf native) =>
        KomodoDefiFramework.createWithOperations(
          hostConfig: buildHostConfig(port: 41234, rpcPassword: 'Rpc-Pass-1!'),
          kdfOperations: native,
        );

    test(
      'a KDF left running in this process is stopped, over FFI only',
      () async {
        final native = _NativeKdf(running: true);
        await stopOrphanedKdf(framework(native));
        expect(native.stops, 1);
        expect(native.running, isFalse);
        expect(native.httpCalls, isEmpty);
        expect(native.disposed, isTrue);
      },
    );

    for (final status in [MainStatus.noContext, MainStatus.noRpc]) {
      test(
        'a KDF caught mid-startup (${status.name}) is stopped too',
        () async {
          final native = _NativeKdf(running: false, startingStatus: status);
          await stopOrphanedKdf(framework(native));
          expect(native.stops, 1);
          expect(native.httpCalls, isEmpty);
          expect(native.disposed, isTrue);
        },
      );
    }

    test('with no KDF running nothing is stopped; only the framework '
        "probes this launch's own port", () async {
      final native = _NativeKdf(running: false);
      await stopOrphanedKdf(framework(native));
      expect(native.stops, 0);
      expect(native.httpCalls, ['version']);
      expect(native.disposed, isTrue);
    });
  });

  group('disposeOnFailure', () {
    test('a successful build keeps the SDK', () async {
      var disposed = 0;
      final value = await disposeOnFailure(
        build: () async => 7,
        dispose: () async => disposed++,
      );
      expect(value, 7);
      expect(disposed, 0);
    });

    test('a failing build disposes the SDK and rethrows', () async {
      var disposed = 0;
      await expectLater(
        disposeOnFailure<int>(
          build: () async => throw StateError('seed validator'),
          dispose: () async => disposed++,
        ),
        throwsStateError,
      );
      expect(disposed, 1);
    });

    test('a failing dispose never masks the original error', () async {
      await expectLater(
        disposeOnFailure<int>(
          build: () async => throw StateError('seed validator'),
          dispose: () async => throw Exception('kdf'),
        ),
        throwsStateError,
      );
    });
  });
}
```


Edit `app/test/data/storage/secure_key_value_store_test.dart` (2 replacements, top to bottom):

1. Replace:

```dart
import 'package:digibyte_dex/data/storage/key_value_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
```

   with:

```dart
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/key_value_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
```

2. Replace:

```dart
    );
  });
}
```

   with:

```dart
    );
  });

  test('persisted state survives a restart (fresh store instances)', () async {
    final at = DateTime.utc(2026, 10, 4, 12);
    // First run: a backup owed, one wrong password, a biometric marker.
    final first = SecureKeyValueStore();
    await BackupStatusStore(first).markPending('main');
    await LockoutStore(first).recordFailure('main', at);
    await first.write('bio_on_main', '1');

    // "Restart": nothing is shared but the platform storage.
    final second = SecureKeyValueStore();
    expect(await BackupStatusStore(second).isPending('main'), isTrue);
    expect((await LockoutStore(second).read('main')).failures, 1);
    expect(await second.read('bio_on_main'), '1');
  });
}
```


- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/bootstrap/sdk_bootstrap_test.dart \
  test/data/storage/secure_key_value_store_test.dart
```

Expected: FAIL. `Method not found: 'disposeOnFailure'`. (The new persistence test in `secure_key_value_store_test.dart` already passes: it pins existing behaviour.)

- [ ] **Step 3: Implement**

Edit `app/lib/main.dart` (3 replacements, top to bottom):

1. Replace:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
```

   with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart' show KomodoDefiSdk;

Future<void> main() async {
```

2. Replace:

```dart
  try {
    final sdk = await startSdk();
    final storage = SecureKeyValueStore();
    final seeds = SdkSeedValidator(sdk.mnemonicValidator);
    await seeds.init();
    final services = AppServices(
      wallet: SdkWalletRepository(sdk),
      seeds: seeds,
      assets: SdkAssetsRepository(sdk),
      receive: SdkReceiveRepository(sdk),
      history: SdkHistoryRepository(sdk),
      send: SdkSendRepository(sdk),
      backups: BackupStatusStore(storage),
      attempts: PasswordAttempts(LockoutStore(storage)),
      biometrics: DeviceBiometricStore(markers: storage),
      clipboard: ClipboardGuard(),
      sharer: const TextSharer(),
      urls: const UrlOpener(),
      scanner: const QrScanner(),
      links: const PaymentLinkSource(),
    );
    // App-lifetime cubits: never closed, the process ends with them.
```

   with:

```dart
  try {
    final sdk = await startSdk();
    final services = await disposeOnFailure(
      build: () => _services(sdk),
      dispose: sdk.dispose,
    );
    // App-lifetime cubits: never closed, the process ends with them.
```

3. Replace:

```dart
    runApp(StartupErrorApp(error: error, onRetry: _start));
  }
}

```

   with:

```dart
    runApp(StartupErrorApp(error: error, onRetry: _start));
  }
}

Future<AppServices> _services(KomodoDefiSdk sdk) async {
  final storage = SecureKeyValueStore();
  final seeds = SdkSeedValidator(sdk.mnemonicValidator);
  await seeds.init();
  return AppServices(
    wallet: SdkWalletRepository(sdk),
    seeds: seeds,
    assets: SdkAssetsRepository(sdk),
    receive: SdkReceiveRepository(sdk),
    history: SdkHistoryRepository(sdk),
    send: SdkSendRepository(sdk),
    backups: BackupStatusStore(storage),
    attempts: PasswordAttempts(LockoutStore(storage)),
    biometrics: DeviceBiometricStore(markers: storage),
    clipboard: ClipboardGuard(),
    sharer: const TextSharer(),
    urls: const UrlOpener(),
    scanner: const QrScanner(),
    links: const PaymentLinkSource(),
  );
}

```


Edit `app/lib/bootstrap/sdk_bootstrap.dart` (2 replacements, top to bottom):

1. Replace:

```dart
    show MarketDataConfig;
import 'package:komodo_defi_framework/komodo_defi_framework.dart'
    show KomodoDefiFramework;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
```

   with:

```dart
    show MarketDataConfig;
import 'package:komodo_defi_framework/komodo_defi_framework.dart'
    show KomodoDefiFramework, MainStatus;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
```

2. Replace:

```dart
/// native KDF inside it, live on. That KDF's port and RPC password were
/// that engine's, so it cannot be reattached; stopping it makes the next
/// start a cold one. Native status and stop calls only, nothing over HTTP.
Future<void> stopOrphanedKdf(KomodoDefiFramework kdf) async {
  try {
    if (await kdf.isRunning(allowVersionFallback: false)) {
      await kdf.kdfStop();
    }
  } finally {
    await kdf.dispose();
  }
}
```

   with:

```dart
/// native KDF inside it, live on. That KDF's port and RPC password were
/// that engine's, so it cannot be reattached; stopping it makes the next
/// start a cold one.
///
/// Any status but `notRunning` is stopped: a KDF caught mid-startup
/// (`noContext`, `noRpc`) is as orphaned as one that serves RPC. The
/// native status comes first; only when it says `notRunning` does the
/// framework also probe `version` on this launch's fresh port
/// (komodo_defi_framework.dart:154-170), where nothing listens.
///
/// This assumes one Flutter engine per process: `MainActivity` is the only
/// engine, so a KDF found here is always an earlier engine's leftover,
/// never a sibling engine's live one. A second engine (an add-to-app
/// screen, a background isolate engine) would break that.
Future<void> stopOrphanedKdf(KomodoDefiFramework kdf) async {
  try {
    if (await kdf.kdfMainStatus() != MainStatus.notRunning) {
      await kdf.kdfStop();
    }
  } finally {
    await kdf.dispose();
  }
}

/// Runs [build] on a started SDK. If it throws, [dispose] (the SDK's) runs
/// before the error is rethrown, so the KDF it started is stopped and a
/// retry starts clean. Errors from disposal never mask the original.
Future<T> disposeOnFailure<T>({
  required Future<T> Function() build,
  required Future<void> Function() dispose,
}) async {
  try {
    return await build();
  } on Object {
    try {
      await dispose();
    } on Object {
      // ignored
    }
    rethrow;
  }
}
```


In `app/lib/data/storage/key_value_store.dart`, replace:

```dart
/// [KeyValueStore] in its own secure-storage namespace. Never the SDK's
/// default namespace, whose first-opened options would otherwise win.
class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore({FlutterSecureStorage? storage})
```

with:

```dart
/// [KeyValueStore] in its own secure-storage namespace. Never the SDK's
/// default namespace, whose first-opened options would otherwise win.
///
/// Known log line, harmless: on every cold start Android logs
/// "EncryptedSharedPreferences initialization failed. Falling back to
/// custom ciphers." once per namespace that holds data (this one,
/// `dgbdex_bio`, and the SDK's default). It is flutter_secure_storage
/// 10.3.4's one-way migration probe (`FlutterSecureStorage.java`
/// :184-266): until a namespace has been migrated from the deprecated
/// Jetpack EncryptedSharedPreferences it opens the namespace's file as
/// EncryptedSharedPreferences, whose `getAll` cannot decrypt the
/// custom-cipher entries and throws. The plugin logs that, then uses the
/// custom ciphers as normal. The "migrated" flag is only written after a
/// real migration (:1070-1078), so the probe repeats. The data is
/// untouched; `secure_key_value_store_test.dart` pins that state survives
/// a restart.
class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore({FlutterSecureStorage? storage})
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/bootstrap/sdk_bootstrap_test.dart \
  test/data/storage/secure_key_value_store_test.dart
```

Expected: `+19: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```

Expected: the formatter changes 0 files; `No issues found!`; `+573: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/bootstrap/sdk_bootstrap.dart \
  lib/data/storage/key_value_store.dart \
  lib/main.dart \
  test/bootstrap/sdk_bootstrap_test.dart \
  test/data/storage/secure_key_value_store_test.dart
git commit -m "fix(startup): stop an orphaned KDF in any state, dispose the SDK on a failed start" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 12: `tool/play_upload.py`: 20-minute timeout, chunked resumable upload with retries, 403 guidance

Spec §6.6. The 210 MB AAB failed under httplib2's 60 s default. The upload now uses an `AuthorizedHttp` with a 20-minute timeout, 8 MB resumable chunks with `next_chunk(num_retries=5)`, progress on stderr, and an explicit hint for HTTP 403 (the service account needs "Release apps to testing tracks"). `docs/release.md` documents both. The tests mock the Google client; they need the release venv (`tool/.venv`, `docs/release.md` "One-time setup").

**Files:**
- Modify: `tool/play_upload.py`
- Modify: `docs/release.md`
- Test (create): `tool/test_play_upload.py`

**Interfaces:**
- Produces: in `tool/play_upload.py` the constants `CHUNK_BYTES = 8 MiB`, `RETRIES = 5`, `HTTP_TIMEOUT_S = 1200`, `PERMISSION_MSG`; `service(creds_path)` builds with `http=AuthorizedHttp(...)`; `http_error_text(e)` appends `PERMISSION_MSG` on 403; `upload(...)` loops `next_chunk` until the bundle response. The command line is unchanged.

- [ ] **Step 1: Write the failing tests**

Create `tool/test_play_upload.py`:

```python
"""Unit tests for tool/play_upload.py. No network and no credentials.

  tool/.venv/bin/python -m unittest discover -s tool -p 'test_play_upload.py' -v
"""
import io
import json
import os
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import play_upload  # noqa: E402


class FakeResp(dict):
    def __init__(self, status):
        super().__init__()
        self.status = status
        self.reason = "reason"


def http_error(status, message="nope", reason="forbidden"):
    body = json.dumps({"error": {"message": message, "errors": [{"reason": reason}]}})
    return play_upload.HttpError(FakeResp(status), body.encode("utf-8"))


class ServiceTest(unittest.TestCase):
    def test_uses_a_long_http_timeout(self):
        with mock.patch.object(play_upload.service_account.Credentials,
                               "from_service_account_file") as creds, \
                mock.patch.object(play_upload, "build") as build:
            creds.return_value = mock.sentinel.creds
            play_upload.service("creds.json")
        http = build.call_args.kwargs["http"]
        self.assertEqual(http.http.timeout, play_upload.HTTP_TIMEOUT_S)
        self.assertGreaterEqual(play_upload.HTTP_TIMEOUT_S, 20 * 60)
        self.assertNotIn("credentials", build.call_args.kwargs)


class UploadTest(unittest.TestCase):
    def setUp(self):
        self.api = mock.MagicMock()
        self.api.edits().insert().execute.return_value = {"id": "e1"}
        self.request = mock.MagicMock()
        self.api.edits().bundles().upload.return_value = self.request

    def test_uploads_in_chunks_with_retries(self):
        progress = mock.MagicMock()
        progress.progress.return_value = 0.5
        self.request.next_chunk.side_effect = [
            (progress, None),
            (None, {"versionCode": 7}),
        ]
        with mock.patch.object(play_upload, "MediaFileUpload") as media, \
                mock.patch.object(play_upload.os.path, "isfile", return_value=True), \
                redirect_stderr(io.StringIO()), redirect_stdout(io.StringIO()):
            play_upload.upload(self.api, "app.aab", "internal", "draft", None)
        kwargs = media.call_args.kwargs
        self.assertTrue(kwargs["resumable"])
        self.assertEqual(kwargs["chunksize"], play_upload.CHUNK_BYTES)
        for call in self.request.next_chunk.call_args_list:
            self.assertEqual(call.kwargs["num_retries"], play_upload.RETRIES)
        update = self.api.edits().tracks().update.call_args.kwargs
        release = update["body"]["releases"][0]
        self.assertEqual(release["versionCodes"], ["7"])
        self.assertEqual(release["status"], "draft")
        self.api.edits().commit.assert_called()

    def test_a_failed_upload_deletes_the_edit(self):
        self.request.next_chunk.side_effect = http_error(500)
        with mock.patch.object(play_upload, "MediaFileUpload"), \
                mock.patch.object(play_upload.os.path, "isfile", return_value=True), \
                self.assertRaises(play_upload.HttpError):
            play_upload.upload(self.api, "app.aab", "internal", "draft", None)
        self.api.edits().delete.assert_called()


class ErrorTextTest(unittest.TestCase):
    def test_403_names_the_missing_permission(self):
        text = play_upload.http_error_text(http_error(403))
        self.assertIn("HTTP 403", text)
        self.assertIn("Release apps to testing tracks", text)

    def test_other_errors_have_no_permission_hint(self):
        text = play_upload.http_error_text(http_error(500))
        self.assertNotIn("Release apps to testing tracks", text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet
tool/.venv/bin/python -m unittest discover -s tool -p 'test_play_upload.py' -v
```

Expected: FAIL. `Ran 5 tests`, `FAILED (failures=2, errors=2)`: no `HTTP_TIMEOUT_S` / `CHUNK_BYTES`, the bundle is uploaded with one `execute()`, and the 403 text has no permission hint.

- [ ] **Step 3: Implement**

Edit `tool/play_upload.py` (6 replacements, top to bottom):

1. Replace:

```python
  tool/play_upload.py --check
  tool/play_upload.py --aab PATH [--track internal] [--status draft] [--notes TEXT]
"""
import argparse
```

   with:

```python
  tool/play_upload.py --check
  tool/play_upload.py --aab PATH [--track internal] [--status draft] [--notes TEXT]

The bundle (about 210 MB) goes up as a resumable upload in 8 MB chunks; each
chunk is retried on transient errors, and the HTTP timeout is 20 minutes
(the library default of 60 s failed mid-upload).

HTTP 403 "The caller does not have permission": the service account needs,
in Play Console > Users and permissions > the service account > App
permissions > me.digiscope.wallet, the permission "Release apps to testing
tracks" (and "View app information"). Until then, upload by hand in Play
Console > Testing > Internal testing.
"""
import argparse
```

2. Replace:

```python
import sys

from google.oauth2 import service_account
from googleapiclient.discovery import build
```

   with:

```python
import sys

import google_auth_httplib2
import httplib2
from google.oauth2 import service_account
from googleapiclient.discovery import build
```

3. Replace:

```python
    "Play Console -> Testing -> Internal testing."
)


def service(creds_path):
    creds = service_account.Credentials.from_service_account_file(creds_path, scopes=SCOPES)
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


```

   with:

```python
    "Play Console -> Testing -> Internal testing."
)
PERMISSION_MSG = (
    "The service account may not release this app. In Play Console -> Users and "
    "permissions -> the service account -> App permissions -> %s, grant "
    "'Release apps to testing tracks' (and 'View app information'), or upload "
    "by hand in Testing -> Internal testing." % PACKAGE
)
# One request per chunk; a 210 MB bundle is about 27 chunks.
CHUNK_BYTES = 8 * 1024 * 1024
# Per chunk, with exponential backoff (googleapiclient's num_retries).
RETRIES = 5
HTTP_TIMEOUT_S = 20 * 60


def service(creds_path):
    creds = service_account.Credentials.from_service_account_file(creds_path, scopes=SCOPES)
    http = google_auth_httplib2.AuthorizedHttp(creds, http=httplib2.Http(timeout=HTTP_TIMEOUT_S))
    return build("androidpublisher", "v3", http=http, cache_discovery=False)


```

4. Replace:

```python
    try:
        err = json.loads(e.content.decode("utf-8")).get("error", {})
        return "HTTP %s: %s (%s)" % (
            e.resp.status,
            err.get("message", ""),
```

   with:

```python
    try:
        err = json.loads(e.content.decode("utf-8")).get("error", {})
        text = "HTTP %s: %s (%s)" % (
            e.resp.status,
            err.get("message", ""),
```

5. Replace:

```python
        )
    except Exception:
        return "HTTP %s: %s" % (e.resp.status, e.reason)


```

   with:

```python
        )
    except Exception:
        text = "HTTP %s: %s" % (e.resp.status, e.reason)
    if e.resp.status == 403:
        text += "\n" + PERMISSION_MSG
    return text


```

6. Replace:

```python
    eid = edit["id"]
    try:
        media = MediaFileUpload(aab, mimetype="application/octet-stream", resumable=True)
        bundle = api.edits().bundles().upload(packageName=PACKAGE, editId=eid, media_body=media).execute()
        code = bundle["versionCode"]
        release = {"versionCodes": [str(code)], "status": status}
```

   with:

```python
    eid = edit["id"]
    try:
        media = MediaFileUpload(
            aab, mimetype="application/octet-stream", chunksize=CHUNK_BYTES, resumable=True
        )
        request = api.edits().bundles().upload(packageName=PACKAGE, editId=eid, media_body=media)
        bundle = None
        while bundle is None:
            # Not "status": that is the release status argument.
            chunk, bundle = request.next_chunk(num_retries=RETRIES)
            if chunk is not None:
                print("uploaded %d%%" % int(chunk.progress() * 100), file=sys.stderr)
        code = bundle["versionCode"]
        release = {"versionCodes": [str(code)], "status": status}
```


In `docs/release.md`, replace:

```markdown
Default status is `draft` (an app never published only accepts drafts); finish the rollout in Console. A 404 / "Package not found" prints guidance and exits 2.

## Promotion

```

with:

```markdown
Default status is `draft` (an app never published only accepts drafts); finish the rollout in Console. A 404 / "Package not found" prints guidance and exits 2.

The bundle (about 210 MB) goes up as a resumable upload in 8 MB chunks, each retried up to 5 times, with a 20-minute HTTP timeout. The library's 60 s default failed mid-upload.

**HTTP 403 "The caller does not have permission".** The service account is missing an app permission. In Play Console > Users and permissions, open the service account, then App permissions > `me.digiscope.wallet`, and grant "Release apps to testing tracks" (and "View app information"). Until then, upload the AAB by hand in Testing > Internal testing. `play_upload.py` prints this hint with every 403.

## Promotion

```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet
tool/.venv/bin/python -m unittest discover -s tool -p 'test_play_upload.py' -v
python3 -m py_compile tool/play_upload.py
```

Expected: `Ran 5 tests` and `OK`; py_compile prints nothing.

- [ ] **Step 5: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  ../docs/release.md \
  ../tool/play_upload.py \
  ../tool/test_play_upload.py
git commit -m "fix(release): resumable chunked Play upload with a long timeout and 403 guidance" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 13: Release 0.3.0 through Play internal testing, on-device acceptance on the Moto, and the PR

Spec §8 (on-device acceptance) and §9 (release). Everything runs on the release workstation against the Moto `ZY22HVMNKZ`.

**Files:**
- Modify: `app/pubspec.yaml` (`version: 0.3.0+4`)
- Modify: `docs/release.md` (new section "M1-D1 acceptance (0.3.0)")
- Scratch only, never committed: `$SCRATCH/m1d1-accept/` with `env.sh`, `ui.py`, `scan_log.py`, `fund.py`, `addrgen.py`, `txfee.py`, `web/`, screenshots, logcat dumps and the PR body.
- Secrets, mode 600, never printed: the new throwaway `~/.config/dgb-dex/m1d1-send1-password`; the existing `~/.config/dgb-dex/m0-phone-seed` (read only by `fund.py`, on the workstation); `$S/m1d1-send1-seed` (written by `ui.py backup` for the log scan, shredded in Step 19).

**Interfaces:**
- Consumes every widget id of Tasks 4–10 and M1-C (`welcome.*`, `create.*`, `backup.*`, `home.*`, `locked.*`, `signin.*`, `receive.*`); Android reports each `Tagged` id as a node `resource-id`.
- Produces: 0.3.0 installed from Play internal testing on `ZY22HVMNKZ`; the AAB in `~/digibyte-dex/release-artifacts/`; the acceptance record in `docs/release.md`; an open PR `feat/m1d1-move-money` → `main` with green CI.

**Rules for this task:**
- Every adb command targets `-s ZY22HVMNKZ`. Never touch the Note 8. Never restart adb (`adb reverse` is fine).
- **No real seed is ever typed through adb.** The only secret typed is `send1`'s throwaway password, through `type_throwaway`, which clears logcat right after. The M0 mule seed never leaves the workstation: `fund.py` gives it to a local KDF.
- No screenshot while a password or seed is on screen. `secureshot` on Confirm proves `FLAG_SECURE` (on the Moto a secure window captures as 0 bytes).
- `ui.py text`, `poll`, `changed` and `waittext` print node text; use them only on addresses, amounts, fees, txids and statuses.
- **[OWNER]** steps need the owner at the phone (fingerprint, Chrome, camera, Play). **[CONTROLLER]** steps are run by the controller session, not an implementer subagent; the controller tells the owner the amount and address before any broadcast from the mule.
- Funds moved: mule → `send1` 5 DGB; `send1` → mule 1 DGB; `send1` → a keyless look-alike address 0.001 DGB (burned, about 0.024 DGB with the fee); `send1` Max → mule. No LTC or BTC.

- [ ] **Step 1: Bump the version and commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
sed -i 's/^version: 0\.2\.1+3$/version: 0.3.0+4/' pubspec.yaml
grep -n '^version:' pubspec.yaml   # version: 0.3.0+4
fvm flutter analyze && fvm flutter test
git add pubspec.yaml
git commit -m "chore(app): version 0.3.0 (M1-D1 move money)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```
Expected: `No issues found!` and `+573: All tests passed!`.

- [ ] **Step 2: [CONTROLLER] Whole-branch review before the release build**

Spec §8: one whole-branch review (`main...feat/m1d1-move-money`) before the release build. Fixes land on the branch with their own tests; re-run Step 1's checks after them. Continue only when the review is clean.

- [ ] **Step 3: Build the signed AAB and keep a copy**

```bash
export SCRATCH=<this session's scratchpad>
cd ~/digibyte-dex/digibyte-wallet
mkdir -p "$SCRATCH/m1d1-accept"
set -o pipefail
tool/release_android.sh | tee "$SCRATCH/m1d1-accept/release.log"
VC=$(sed -n 's/^versionCode: *//p' "$SCRATCH/m1d1-accept/release.log")
cp app/build/app/outputs/bundle/release/app-release.aab \
  ~/digibyte-dex/release-artifacts/digibyte-dex-0.3.0-$VC.aab
ls -l ~/digibyte-dex/release-artifacts/ | tail -2
java -jar /tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/eab8c964-9b1e-44ec-b157-ec18db695089/scratchpad/tools/bundletool-all-1.18.1.jar \
  dump manifest --bundle ~/digibyte-dex/release-artifacts/digibyte-dex-0.3.0-$VC.aab \
  --xpath /manifest/uses-sdk/@android:targetSdkVersion
```
Expected: the signer matches the upload certificate; every 16 KB row is PASS; `versionName: 0.3.0` and a `versionCode`; the copy exists; the target SDK is `36`.

- [ ] **Step 4: Upload to Play internal testing (manual upload if the API says 403)**

```bash
cd ~/digibyte-dex/digibyte-wallet
VC=<versionCode from Step 3>
tool/.venv/bin/python tool/play_upload.py \
  --aab ~/digibyte-dex/release-artifacts/digibyte-dex-0.3.0-$VC.aab \
  --track internal --status draft \
  --notes "0.3.0: send, history, payment links and QR scanning"
```
Expected: `uploaded N%` lines, then `Uploaded versionCode <VC> to internal (draft).`
- On `HTTP 403`, the script prints the missing permission. **[OWNER]** either grants it (Play Console > Users and permissions > the service account > App permissions > `me.digiscope.wallet` > "Release apps to testing tracks") and the step is re-run, or uploads `digibyte-dex-0.3.0-<VC>.aab` by hand in Testing > Internal testing > Create new release.
- **[OWNER]** In Testing > Internal testing, review the release and roll it out to the internal testers (a draft is not installable).

- [ ] **Step 5: [OWNER] Install 0.3.0 on the Moto from Play**

```bash
adb -s ZY22HVMNKZ shell pm list packages -i me.digiscope.wallet
adb -s ZY22HVMNKZ shell dumpsys package me.digiscope.wallet | grep -m1 versionName
```
- If the line for exactly `package:me.digiscope.wallet` shows an installer other than `com.android.vending`, it is the sideloaded M1-C build, signed with the upload key; Play cannot update it. Remove it (only the throwaway wallets `accept1`, `m0r` and `legacy1` live in it; `m0r`'s seed stays in `~/.config/dgb-dex/`). Never touch `me.digiscope.wallet.m0`.

  ```bash
  adb -s ZY22HVMNKZ uninstall me.digiscope.wallet
  ```
- **[OWNER]** On the Moto, open https://play.google.com/apps/internaltest/4700509738211946340 in Chrome, accept the invitation if asked, follow "download it on Google Play", and install or update DigiByte DEX. Then:

```bash
adb -s ZY22HVMNKZ shell pm list packages -i me.digiscope.wallet | grep 'package:me.digiscope.wallet '
adb -s ZY22HVMNKZ shell dumpsys package me.digiscope.wallet | grep -m1 versionName
```
Expected: `installer=com.android.vending` and `versionName=0.3.0`.

- [ ] **Step 6: Create the acceptance helpers and the throwaway password**

Create `$SCRATCH/m1d1-accept/env.sh`:

```bash
# Source me at the start of every acceptance command:
#   source "$SCRATCH/m1d1-accept/env.sh"
set +x
ACC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D=ZY22HVMNKZ
S=~/.config/dgb-dex
# The M0 test mule's first DGB address (SECRETS-INDEX.md; public).
MULE=DLFhh33PLHZ2y1kN37BiQ2uD4f394jdixs

# Types the THROWAWAY password of send1 into the focused field, 8
# characters per `input text` call, then clears logcat at once: adbd logs
# `input text`. It refuses any other file, so a real seed is never typed.
type_throwaway() {
  case "$1" in
    */m1d1-send1-password) ;;
    *) echo "refusing: only the send1 throwaway password is typed" >&2; return 1 ;;
  esac
  local secret chunk i
  secret="$(tr -d '\n' < "$1")"
  for ((i = 0; i < ${#secret}; i += 8)); do
    chunk="${secret:i:8}"
    adb -s "$D" shell input text "'${chunk}'" > /dev/null 2>&1
  done
  secret=''
  chunk=''
  adb -s "$D" logcat -c
}

# A normal screenshot. Never on a screen showing a password or seed.
shot() { adb -s "$D" exec-out screencap -p > "$ACC/$1.png"; echo "saved $1.png"; }

ui() { python3 "$ACC/ui.py" "$@"; }

pause() { python3 "$ACC/ui.py" pause "$1"; }

launch() { adb -s "$D" shell am start -n me.digiscope.wallet/.MainActivity > /dev/null; }

kill_app() { adb -s "$D" shell am force-stop me.digiscope.wallet; }

# Scans the device log for every acceptance secret; prints counts and log
# tags only. The dump is kept as evidence when clean, deleted on a leak.
scan_log() {
  adb -s "$D" logcat -d > "$ACC/logcat-$1.txt"
  python3 "$ACC/scan_log.py" "$ACC/logcat-$1.txt" \
    "$S/m1d1-send1-password" "$S/m0-phone-seed" "$S/m1d1-send1-seed"
}
```

Create `$SCRATCH/m1d1-accept/ui.py` (the M1-C driver, plus `checked`, `enabled`, `waittext`, `backup SAVEFILE`, and an empty capture accepted by `secureshot`):

```python
#!/usr/bin/env python3
"""Drives DigiByte DEX on the Moto by Semantics identifier.

Flutter reports Semantics(identifier:) as the node's resource-id in
`uiautomator dump`. Only `text`, `poll` and `changed` print node text,
and they are used for addresses, amounts, fees and txids only.
"""
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
import zlib

ADB = ['adb', '-s', 'ZY22HVMNKZ']


def adb(*args):
    return subprocess.run(ADB + list(args), check=True,
                          capture_output=True).stdout


def dump():
    raw = adb('exec-out', 'uiautomator', 'dump', '/dev/tty').decode(
        'utf-8', 'replace')
    start, end = raw.find('<?xml'), raw.rfind('</hierarchy>')
    if start < 0 or end < 0:
        return None
    return ET.fromstring(raw[start:end + len('</hierarchy>')])


def nodes(root, pattern):
    rx = re.compile(pattern)
    return [n for n in root.iter('node')
            if rx.fullmatch(n.get('resource-id', ''))]


def find(pattern, timeout):
    deadline = time.time() + timeout
    while True:
        root = dump()
        hits = nodes(root, pattern) if root is not None else []
        if hits or time.time() >= deadline:
            return root, hits
        time.sleep(1)


def screen():
    out = adb('shell', 'wm', 'size').decode()
    w, h = re.findall(r'(\d+)x(\d+)', out)[-1]
    return int(w), int(h)


def center(node):
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
    return (x1 + x2) // 2, (y1 + y2) // 2


def tap_node(node):
    x, y = center(node)
    adb('shell', 'input', 'tap', str(x), str(y))
    time.sleep(0.6)


def text_of(node):
    parts = [n.get('text') or n.get('content-desc') or ''
             for n in node.iter('node')]
    return ' '.join(p for p in parts if p).strip()


def unfocus():
    # A tap on the app bar title hides the keyboard: every text field
    # unfocuses on a tap outside it (onTapOutside).
    w, h = screen()
    adb('shell', 'input', 'tap', str(w // 2), str(int(h * 0.075)))
    time.sleep(0.7)


def scroll_down():
    w, h = screen()
    adb('shell', 'input', 'swipe', str(w // 2), str(int(h * 0.75)),
        str(w // 2), str(int(h * 0.35)), '300')
    time.sleep(0.7)


def locate(pattern, timeout=20.0):
    """The first match whose centre is on screen, scrolling down if needed."""
    _, h = screen()
    for attempt in range(4):
        root, hits = find(pattern, timeout if attempt == 0 else 3.0)
        for node in hits:
            if 0 < center(node)[1] < h * 0.9:
                return root, node
        scroll_down()
    return None, None


def tap(ident):
    unfocus()
    _, node = locate(re.escape(ident))
    if node is None:
        sys.exit(f'not found: {ident}')
    tap_node(node)


def gone(ident, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        root = dump()
        if root is not None and not nodes(root, re.escape(ident)):
            return True
        time.sleep(1)
    return False


def poll(ident, timeout):
    """A balance once it leaves the loading mark and holds for 10 s."""
    deadline = time.time() + timeout
    last, since = None, time.time()
    while time.time() < deadline:
        _, hits = find(re.escape(ident), 5)
        value = text_of(hits[0]) if hits else None
        if value != last:
            last, since = value, time.time()
        elif value not in (None, '…') and time.time() - since >= 10:
            return value
        time.sleep(1)
    return last


def is_blank(png):
    pos, idat = 8, b''
    while pos < len(png):
        length = int.from_bytes(png[pos:pos + 4], 'big')
        if png[pos + 4:pos + 8] == b'IDAT':
            idat += png[pos + 8:pos + 8 + length]
        pos += 12 + length
    # A uniformly black RGBA capture filters to bytes from {0..4, 255}.
    return len(set(zlib.decompress(idat))) <= 8


def backup(save=None):
    """Passes the quiz of the throwaway wallet on screen. With [save], the
    words also go to that 0600 file (for the final logcat scan only)."""
    unfocus()
    root, hits = find(r'backup\.word\.\d+', 120)
    words = {int(n.get('resource-id').rsplit('.', 1)[1]): text_of(n)
             for n in hits}
    print(f'words shown: {len(words)}')
    if len(words) != 24:
        sys.exit('expected 24 words')
    if save:
        fd = os.open(save, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as f:
            f.write(' '.join(words[i] for i in sorted(words)))
    tap('backup.continue')
    for k in range(4):
        root, question = locate(rf'backup\.quiz\.{k}\.word\d+')
        if question is None:
            sys.exit(f'quiz question {k} not found')
        want = words[int(question.get('resource-id').rsplit('word', 1)[1])]
        options = [o for o in nodes(root, rf'backup\.quiz\.{k}\.option\.\d+')
                   if want in text_of(o).split()]
        if not options:
            sys.exit(f'quiz question {k}: no matching option')
        tap_node(options[0])
    words.clear()
    tap('backup.check')
    print('quiz answered')


def wait_text(ident, needle, timeout):
    """Waits until the node's text contains [needle]; prints the text."""
    deadline = time.time() + timeout
    last = ''
    while time.time() < deadline:
        _, hits = find(re.escape(ident), 5)
        last = text_of(hits[0]) if hits else ''
        if needle in last:
            return last
        time.sleep(2)
    sys.exit(f'{ident}: "{needle}" not seen; last text: {last!r}')


def enabled(ident):
    """'true' or 'false': whether the control accepts taps."""
    _, hits = find(re.escape(ident), 20)
    if not hits:
        sys.exit(f'not found: {ident}')
    states = [n.get('enabled') for n in hits[0].iter('node')
              if n.get('clickable') == 'true' or n.get('checkable') == 'true']
    return (states or [hits[0].get('enabled')])[0]


def checked(ident):
    """'true' or 'false': a checkbox or switch, read before tapping it."""
    _, hits = find(re.escape(ident), 20)
    if not hits:
        sys.exit(f'not found: {ident}')
    for node in hits[0].iter('node'):
        if node.get('checkable') == 'true':
            return node.get('checked')
    return hits[0].get('checked')


def main():
    cmd, *args = sys.argv[1:]
    if cmd == 'tap':
        tap(args[0])
    elif cmd == 'wait':
        _, hits = find(re.escape(args[0]), float(args[1]))
        print('present' if hits else 'absent')
        sys.exit(0 if hits else 1)
    elif cmd == 'gone':
        ok = gone(args[0], float(args[1]))
        print('gone' if ok else 'still there')
        sys.exit(0 if ok else 1)
    elif cmd == 'busy':
        find(re.escape(args[0]), 5)
        sys.exit(0 if gone(args[0], float(args[1])) else 1)
    elif cmd == 'count':
        root = dump()
        print(len(nodes(root, args[0])) if root is not None else 0)
    elif cmd == 'text':
        _, hits = find(re.escape(args[0]), 20)
        print(text_of(hits[0]) if hits else '')
    elif cmd == 'poll':
        print(poll(args[0], float(args[1])))
    elif cmd == 'changed':
        deadline = time.time() + float(args[2])
        while time.time() < deadline:
            _, hits = find(re.escape(args[0]), 5)
            if hits and text_of(hits[0]) != args[1]:
                print(text_of(hits[0]))
                return
            time.sleep(1)
        sys.exit('unchanged')
    elif cmd == 'secureshot':
        png = adb('exec-out', 'screencap', '-p')
        # On the Moto, a FLAG_SECURE window captures as 0 bytes.
        if png and not is_blank(png):
            sys.exit('capture is NOT blank: FLAG_SECURE failed; not saved')
        with open(args[0], 'wb') as f:
            f.write(png)
        print('blank or empty capture saved (FLAG_SECURE works)')
    elif cmd == 'backup':
        backup(args[0] if args else None)
    elif cmd == 'checked':
        print(checked(args[0]))
    elif cmd == 'enabled':
        print(enabled(args[0]))
    elif cmd == 'waittext':
        print(wait_text(args[0], args[1], float(args[2])))
    elif cmd == 'pause':
        time.sleep(min(float(args[0]), 10.0))
    else:
        sys.exit(f'unknown command {cmd}')


if __name__ == '__main__':
    main()
```

Create `$SCRATCH/m1d1-accept/scan_log.py`:

```python
#!/usr/bin/env python3
"""Scans a logcat dump for the acceptance secrets. Prints only counts and
log tags, never a secret. On a leak the dump is deleted.

  python3 scan_log.py LOGCAT_FILE SECRET_FILE...
"""
import os
import sys

log = open(sys.argv[1], errors='replace').read().splitlines()
hits = {}
for path in sys.argv[2:]:
    if not os.path.exists(path):
        continue
    secret = open(path).read().strip()
    words = secret.split()
    if len(words) >= 3:
        probes = [' '.join(words[i:i + 3]) for i in range(len(words) - 2)]
    else:
        # A password: whole, and the 8-character chunks adbd would log.
        probes = [secret] + [secret[i:i + 8] for i in range(0, len(secret), 8)
                             if len(secret[i:i + 8]) == 8]
    for line in log:
        if any(p in line for p in probes):
            head = line.split(': ', 1)[0].split()
            hits.setdefault(os.path.basename(path), set()).add(
                head[-1] if head else '?')
if hits:
    os.remove(sys.argv[1])
    print('logcat secret scan: LEAK', {k: sorted(v) for k, v in hits.items()})
    sys.exit(1)
print('logcat secret scan: clean (%d lines)' % len(log))
```

Create `$SCRATCH/m1d1-accept/fund.py` (dry-run verified during planning against the workstation KDF with a public test vector):

```python
#!/usr/bin/env python3
"""Funds the M1-D1 acceptance wallet from the M0 test mule with a local KDF.

  python3 fund.py --seed-file ~/.config/dgb-dex/m0-phone-seed --to ADDRESS \
      --amount 5 [--dry-run]

Starts ~/.local/bin/kdf in a scratch directory (no P2P, its own port,
HD on, the mule seed as passphrase), activates DGB over the app's three SSL
electrums, builds and signs a withdraw from the mule's richest address,
broadcasts it (unless --dry-run), and stops KDF. The seed and the RPC
password go only into the 0600 config file and the KDF process; nothing
secret is printed. The scratch directory is deleted at the end.
"""
import argparse
import json
import os
import secrets
import shutil
import string
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

KDF = os.path.expanduser("~/.local/bin/kdf")
COINS = os.path.expanduser("~/.local/share/dgb-bot/coins")
PORT = 7795
SERVERS = [
    {"url": "electrum.digiscope.me:50002", "protocol": "SSL"},
    {"url": "dgb.electrum1.cipig.net:20059", "protocol": "SSL"},
    {"url": "dgb.electrum2.cipig.net:20059", "protocol": "SSL"},
]


def rpc_password():
    """32 characters that satisfy KDF's password policy."""
    alphabet = string.ascii_letters + string.digits + "-_"
    while True:
        p = "".join(secrets.choice(alphabet) for _ in range(32))
        if (any(c.isdigit() for c in p) and any(c.islower() for c in p)
                and any(c.isupper() for c in p) and any(c in "-_" for c in p)
                and not any(p[i] == p[i + 1] == p[i + 2] for i in range(30))
                and "password" not in p.lower()):
            return p


def call(pw, method, params=None, v2=True):
    body = {"userpass": pw, "method": method}
    if v2:
        body["mmrpc"] = "2.0"
        body["params"] = params or {}
    else:
        body.update(params or {})
    req = urllib.request.Request(
        "http://127.0.0.1:%d" % PORT, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return json.loads(e.read())
    except (urllib.error.URLError, OSError):
        return {}  # not listening yet, or already gone


def wait_task(pw, method, task_id, timeout=600):
    deadline = time.time() + timeout
    while time.time() < deadline:
        r = call(pw, method, {"task_id": task_id, "forget_if_finished": False})
        status = r.get("result", {}).get("status")
        if status in ("Ok", "Error"):
            return r["result"]
        time.sleep(2)
    sys.exit("timed out waiting for %s" % method)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed-file", required=True)
    ap.add_argument("--to", required=True)
    ap.add_argument("--amount", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    work = tempfile.mkdtemp(prefix="m1d1-fund-", dir=os.environ.get("SCRATCH"))
    os.chmod(work, 0o700)
    pw = rpc_password()
    with open(a.seed_file) as f:
        seed = " ".join(f.read().split())
    conf = {
        "gui": "m1d1-fund", "netid": 2014, "rpcip": "127.0.0.1", "rpcport": PORT,
        "rpc_password": pw, "passphrase": seed, "enable_hd": True,
        "disable_p2p": True, "dbdir": os.path.join(work, "db"),
    }
    seed = None
    os.makedirs(conf["dbdir"])
    conf_path = os.path.join(work, "MM2.json")
    fd = os.open(conf_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(conf, f)
    conf = None
    env = dict(os.environ, MM_CONF_PATH=conf_path, MM_COINS_PATH=COINS,
               MM_LOG=os.path.join(work, "kdf.log"))
    proc = subprocess.Popen([KDF], cwd=work, env=env,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(60):
            if "result" in call(pw, "version", v2=False):
                break
            time.sleep(1)
        else:
            sys.exit("KDF did not start")
        os.remove(conf_path)  # KDF has read it; the seed leaves the disk
        init = call(pw, "task::enable_utxo::init", {
            "ticker": "DGB",
            "activation_params": {
                "mode": {"rpc": "Electrum", "rpc_data": {"servers": SERVERS}},
                "scan_policy": "scan", "gap_limit": 20,
            },
        })
        if "result" not in init:
            sys.exit("activation failed: %s" % init.get("error_type", init))
        done = wait_task(pw, "task::enable_utxo::status", init["result"]["task_id"])
        if done["status"] != "Ok":
            sys.exit("activation failed: %s" % done["details"].get("error_type"))
        addresses = done["details"]["wallet_balance"]["accounts"][0]["addresses"]
        richest = max(addresses, key=lambda x: float(x["balance"]["DGB"]["spendable"]))
        print("mule source %s holds %s DGB" % (
            richest["address"], richest["balance"]["DGB"]["spendable"]))
        w = call(pw, "task::withdraw::init", {
            "coin": "DGB", "to": a.to, "amount": a.amount,
            "from": {"derivation_path": richest["derivation_path"]},
        })
        if "result" not in w:
            sys.exit("withdraw failed: %s" % w.get("error_type", w))
        signed = wait_task(pw, "task::withdraw::status", w["result"]["task_id"])
        if signed["status"] != "Ok":
            sys.exit("withdraw failed: %s" % signed["details"].get("error_type"))
        tx = signed["details"]
        print("signed: %s DGB to %s, fee %s DGB" % (
            a.amount, a.to, tx["fee_details"]["amount"]))
        if a.dry_run:
            print("dry run: not broadcast")
            return
        sent = call(pw, "send_raw_transaction",
                    {"coin": "DGB", "tx_hex": tx["tx_hex"]}, v2=False)
        if "tx_hash" not in sent:
            sys.exit("broadcast failed: %s" % sent.get("error", sent))
        print("txid %s" % sent["tx_hash"])
    finally:
        call(pw, "stop", v2=False)
        try:
            proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
```

Create `$SCRATCH/m1d1-accept/addrgen.py`:

```python
#!/usr/bin/env python3
"""Test addresses for the M1-D1 acceptance. Nobody holds their keys: coins
sent to them are gone.

  python3 addrgen.py lookalike   # two DGB P2PKH addresses, same first and last 4
  python3 addrgen.py bech32      # one valid dgb1 (P2WPKH) address
"""
import hashlib
import os
import sys

B58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'


def b58check(payload):
    data = payload + hashlib.sha256(hashlib.sha256(payload).digest()).digest()[:4]
    n = int.from_bytes(data, 'big')
    out = ''
    while n:
        n, r = divmod(n, 58)
        out = B58[r] + out
    return '1' * (len(data) - len(data.lstrip(b'\0'))) + out


def p2pkh(h160):
    return b58check(b'\x1e' + h160)  # DigiByte P2PKH version 30 ('D')


def lookalike():
    seen = {}
    while True:
        a = p2pkh(os.urandom(20))
        key = (a[:4], a[-4:])
        b = seen.get(key)
        if b and b != a:
            return b, a
        seen[key] = a


CHARSET = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l'


def polymod(values):
    gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
    chk = 1
    for v in values:
        top = chk >> 25
        chk = (chk & 0x1ffffff) << 5 ^ v
        for i in range(5):
            chk ^= gen[i] if (top >> i) & 1 else 0
    return chk


def bech32(hrp, witver, prog):
    acc, bits, data = 0, 0, [witver]
    for b in prog:
        acc = (acc << 8) | b
        bits += 8
        while bits >= 5:
            bits -= 5
            data.append((acc >> bits) & 31)
    if bits:
        data.append((acc << (5 - bits)) & 31)
    hrpx = [ord(c) >> 5 for c in hrp] + [0] + [ord(c) & 31 for c in hrp]
    pm = polymod(hrpx + data + [0] * 6) ^ 1
    checksum = [(pm >> 5 * (5 - i)) & 31 for i in range(6)]
    return hrp + '1' + ''.join(CHARSET[d] for d in data + checksum)


if __name__ == '__main__':
    if sys.argv[1:] == ['lookalike']:
        a, b = lookalike()
        print(a)
        print(b)
    elif sys.argv[1:] == ['bech32']:
        print(bech32('dgb', 0, os.urandom(20)))
    else:
        sys.exit(__doc__)
```

Create `$SCRATCH/m1d1-accept/txfee.py` (reads the local `digibyted`, which has `txindex=1`):

```python
#!/usr/bin/env python3
"""The on-chain fee of a DGB transaction, from the local digibyted.

  python3 txfee.py TXID
"""
import json
import subprocess
import sys
from decimal import Decimal


def cli(*args):
    out = subprocess.run(['digibyte-cli', *args], check=True,
                         capture_output=True, text=True).stdout
    return json.loads(out, parse_float=Decimal)


tx = cli('getrawtransaction', sys.argv[1], '1')
spent = sum(cli('getrawtransaction', i['txid'], '1')['vout'][i['vout']]['value']
            for i in tx['vin'])
paid = sum(o['value'] for o in tx['vout'])
print('fee %s DGB, %d confirmations' % (spent - paid, tx.get('confirmations', 0)))
```

Generate the throwaway password (written straight to a mode-600 file, never printed) and index it:

```bash
umask 077
python3 - ~/.config/dgb-dex/m1d1-send1-password <<'EOF'
import re, secrets, string, sys
alphabet = string.ascii_letters + string.digits
while True:
    p = 'Dgb_' + ''.join(secrets.choice(alphabet) for _ in range(12))
    if (re.search('[0-9]', p) and re.search('[a-z]', p)
            and re.search('[A-Z]', p) and not re.search(r'(.)\1\1', p)
            and 'password' not in p.lower()):
        break
open(sys.argv[1], 'w').write(p)
print('written')
EOF
chmod 600 ~/.config/dgb-dex/m1d1-send1-password
cat >> ~/.config/dgb-dex/SECRETS-INDEX.md <<'EOF'
## M1-D1 acceptance (Moto ZY22HVMNKZ, 0.3.0)
- m1d1-send1-password: password of acceptance wallet send1 (throwaway; typed via adb, logcat cleared after)
- send1's 24 words are shown only on the device; m1d1-send1-seed is a temporary copy for the log scan, shredded after
EOF
chmod +x "$SCRATCH"/m1d1-accept/*.py
```

- [ ] **Step 7: Create `send1` on the device, with fingerprint unlock**

```bash
source "$SCRATCH/m1d1-accept/env.sh"
launch
ui wait welcome.create 60 || { ui tap signin.other && ui wait welcome.create 30; }
ui tap welcome.create
ui tap create.name && adb -s "$D" shell input text send1
ui tap create.password && type_throwaway "$S/m1d1-send1-password"
ui tap create.confirm && type_throwaway "$S/m1d1-send1-password"
ui checked create.biometrics        # false: tap it once
ui tap create.biometrics && ui checked create.biometrics   # true
ui tap create.submit
echo "OWNER: if a fingerprint prompt appears, touch the sensor (power button)"
ui wait backup.continue 180
ui backup "$S/m1d1-send1-seed"      # words shown: 24 / quiz answered
ui wait home.row.DGB 180 && shot 01-home-send1
scan_log 01-create
```
Expected: `true` after the tap (if `create.biometrics` is absent, this Moto has no strong biometric enrolled: record it, and use the password wherever a fingerprint step follows); 24 words; the quiz passes; Home shows DGB, BTC, LTC; `logcat secret scan: clean`.

- [ ] **Step 8: Open DGB asset detail and read `send1`'s receive address**

```bash
source "$SCRATCH/m1d1-accept/env.sh"
ui tap home.row.DGB && ui wait asset.receive 60
ui wait asset.empty 120 && shot 02-asset-empty      # "No transactions yet"
ui tap asset.receive && ui wait receive.address 60
ui text receive.address | grep -o 'D[1-9A-HJ-NP-Za-km-z]\{25,34\}' | head -1 > "$ACC/send1-address"
echo "send1 DGB address: $(cat "$ACC/send1-address")"
adb -s "$D" shell input keyevent KEYCODE_BACK
```

- [ ] **Step 9: [CONTROLLER] Fund `send1` with 5 DGB from the M0 test mule (spec D7)**

Tell the owner: "5 DGB from the M0 mule to <send1 address>". Dry run first, then the real send:

```bash
source "$SCRATCH/m1d1-accept/env.sh"
python3 "$ACC/fund.py" --seed-file "$S/m0-phone-seed" --to "$(cat "$ACC/send1-address")" --amount 5 --dry-run
python3 "$ACC/fund.py" --seed-file "$S/m0-phone-seed" --to "$(cat "$ACC/send1-address")" --amount 5 | tee "$ACC/fund.log"
ss -ltn | grep -c ':7795 '              # 0: the funding KDF is gone
systemctl --user is-active kdf-bot     # active: the bot KDF on 7790 is untouched
```
Expected: `mule source D… holds N DGB`, `signed: 5 DGB to D…, fee 0.0… DGB`, then `dry run: not broadcast`; the second run ends with `txid <64 hex>`. The seed only reaches the 0600 KDF config (deleted as soon as KDF has read it) and the KDF process; it is never printed and never touches the phone or adb.

- [ ] **Step 10: Watch the deposit: pending, then confirmed (and the unconfirmed-balance check)**

```bash
source "$SCRATCH/m1d1-accept/env.sh"
ui wait asset.tx.0 600 && ui text asset.tx.0 && shot 03-received-pending
ui wait asset.spendable 5; echo "spendable shown while pending: exit=$?"
ui poll asset.balance 600
ui waittext asset.tx.0 Confirmed 900 && shot 04-received-confirmed
```
Expected: `Received … Pending` and `+5 DGB`, then `Confirming n/7`, then `Confirmed`; the balance is `5 DGB`. Record whether `asset.spendable` appeared while the deposit was pending (spec §10: does `spendable` include unconfirmed coins?). Pull to refresh (swipe down on the list) if a row lags.

- [ ] **Step 11: Send 1 DGB to the mule with the fingerprint; compare the fee; open the explorer**

```bash
source "$SCRATCH/m1d1-accept/env.sh"
ui tap asset.send && ui wait send.address 60
ui tap send.address && adb -s "$D" shell input text "$MULE"
ui waittext send.address 'Address OK' 30
ui text send.available                                  # Available: 5 DGB
ui tap send.amount && adb -s "$D" shell input text 1
ui tap send.next && ui wait confirm.fee 120
ui secureshot "$ACC/05-confirm-blank.png"
ui text confirm.to; ui text confirm.amount; ui text confirm.fee; ui text confirm.total
ui tap confirm.send
echo "OWNER: touch the fingerprint sensor"
ui wait result.txid 180
ui text result.txid | grep -o '[0-9a-f]\{64\}' > "$ACC/tx1"; cat "$ACC/tx1"
shot 06-result
python3 "$ACC/txfee.py" "$(cat "$ACC/tx1")"
scan_log 02-send
```
Expected: Confirm shows the mule address in groups of 4, `1 DGB`, a fee such as `0.0226 DGB` and the total; the capture is blank or empty; the result shows a txid; **`txfee.py` prints the same fee as Confirm**; the log is clean.

**[OWNER]** Tap **View in explorer** (`result.explorer`): digiexplorer.info opens `…/tx/<txid>` for this txid and shows the same fee. Come back to the app. Then:

```bash
source "$SCRATCH/m1d1-accept/env.sh"
ui tap result.done && ui wait asset.tx.0 60
ui waittext asset.tx.0 Sent 120 && shot 07-sent-pending
ui waittext asset.tx.0 Confirmed 900
```
Expected: the newest row is `Sent … Pending` (`-1.0226 DGB` or similar), then `Confirmed`.

- [ ] **Step 12: A bech32 `dgb1…` recipient validates and previews (spec D8); nothing is sent**

```bash
source "$SCRATCH/m1d1-accept/env.sh"
B32=$(python3 "$ACC/addrgen.py" bech32); echo "$B32"
ui tap asset.send && ui wait send.address 60
ui tap send.address && adb -s "$D" shell input text "$B32"
ui waittext send.address 'Address OK' 30 && shot 08-bech32-valid
ui tap send.amount && adb -s "$D" shell input text 0.001
ui tap send.next && ui wait confirm.to 120 && ui text confirm.to
ui tap confirm.back && ui wait send.next 30
adb -s "$D" shell input keyevent KEYCODE_BACK
```
Expected: `Address OK`, and Confirm shows the `dgb1…` address. If KDF refuses it (`Not a DigiByte address`), record **D8: FAIL** and continue; that is an owner decision, not a blocker for the other steps.

- [ ] **Step 13: The look-alike warning (spec §8.6); the look-alike itself is never sent to**

`addrgen.py lookalike` prints two valid, keyless DGB addresses `A` and `A2` that share their first and last 4 characters (about 15 s). `A` becomes a recent address through a 0.001 DGB send (burned); then a send to `A2` must stop on the warning.

```bash
source "$SCRATCH/m1d1-accept/env.sh"
python3 "$ACC/addrgen.py" lookalike > "$ACC/lookalike.txt"
A=$(sed -n 1p "$ACC/lookalike.txt"); A2=$(sed -n 2p "$ACC/lookalike.txt"); echo "A=$A A2=$A2"
ui tap asset.send && ui wait send.address 60
ui tap send.address && adb -s "$D" shell input text "$A"
ui waittext send.address 'Address OK' 30
ui tap send.amount && adb -s "$D" shell input text 0.001
ui tap send.next && ui wait confirm.send 120
ui tap confirm.send
echo "OWNER: touch the fingerprint sensor"
ui wait result.done 180 && ui tap result.done && ui wait asset.send 60
ui tap asset.send && ui wait send.address 60
ui tap send.address && adb -s "$D" shell input text "$A2"
ui waittext send.address 'Address OK' 30
ui tap send.amount && adb -s "$D" shell input text 0.001
ui tap send.next && ui wait confirm.lookalike 120
ui checked confirm.ack          # false
ui enabled confirm.send         # false
ui secureshot "$ACC/09-lookalike-blank.png"
ui tap confirm.back && ui wait send.next 30
adb -s "$D" shell input keyevent KEYCODE_BACK
```
Expected: the first send completes; the second stops on `confirm.lookalike` with the acknowledgement unchecked and Send disabled; Back returns to the form. Nothing is sent to `A2`.

- [ ] **Step 14: A Max send back to the mule with the password (biometric fallback)**

```bash
source "$SCRATCH/m1d1-accept/env.sh"
ui tap asset.send && ui wait send.address 60
ui tap send.address && adb -s "$D" shell input text "$MULE"
ui waittext send.address 'Address OK' 30
ui text send.available
ui tap send.max && ui tap send.next && ui wait confirm.amount 120
ui text confirm.amount; ui text confirm.fee; ui text confirm.total
ui tap confirm.send
echo "OWNER: on the fingerprint prompt tap 'Use password' or Cancel; do not touch the sensor"
ui wait confirm.password 60
ui tap confirm.password && type_throwaway "$S/m1d1-send1-password"
ui tap confirm.submit && ui wait result.txid 180
ui text result.txid | grep -o '[0-9a-f]\{64\}' > "$ACC/tx2"; cat "$ACC/tx2"
python3 "$ACC/txfee.py" "$(cat "$ACC/tx2")"
ui tap result.done && ui wait asset.balance 30
ui poll asset.balance 900 && shot 10-after-max
scan_log 03-max
```
Expected: Confirm's total equals `Available`; after the fallback the password sends; the fees match; the balance ends at `0 DGB` (or at what other `send1` addresses hold; record it); the log is clean.

- [ ] **Step 15: `digibyte:` links from Chrome, unlocked and locked (spec §8.4)**

```bash
source "$SCRATCH/m1d1-accept/env.sh"
mkdir -p "$ACC/web"
~/.local/bin/qr "digibyte:$MULE?amount=0.25&message=QR%20test" > "$ACC/web/qr.png"
cat > "$ACC/web/pay.html" <<EOF
<!doctype html><meta name="viewport" content="width=device-width">
<p><a id="pay" href="digibyte:$MULE?amount=0.5&label=M1-D1%20acceptance">Pay 0.5 DGB</a></p>
<p><img src="qr.png" width="300" alt="payment QR"></p>
EOF
adb -s "$D" reverse tcp:8099 tcp:8099
```
Run `python3 -m http.server 8099 --bind 127.0.0.1 --directory "$SCRATCH/m1d1-accept/web"` with `run_in_background`.

a. **Unlocked.** The app is open and unlocked. **[OWNER]** Press Home, open Chrome on the Moto, go to `http://127.0.0.1:8099/pay.html`, tap **Pay 0.5 DGB** (choose DigiByte DEX if Android asks).

```bash
source "$SCRATCH/m1d1-accept/env.sh"
ui wait send.address 60 && ui text send.address && ui text send.amount && ui text send.note
shot 11-link-unlocked
adb -s "$D" shell input keyevent KEYCODE_BACK       # one Back: Send -> Home
ui wait home.lock 30 && ui tap home.lock && ui wait locked.password 30
```
Expected: the mule address, `0.5`, and `Payment request note: M1-D1 acceptance`; nothing was sent.

b. **Locked.** **[OWNER]** Press Home, switch to Chrome, tap the link again.

```bash
source "$SCRATCH/m1d1-accept/env.sh"
ui wait locked.password 60
ui wait send.address 3; echo "Send before unlock: exit=$?"     # exit=1
ui tap locked.biometric
echo "OWNER: touch the fingerprint sensor"
ui wait send.address 90 && ui text send.address && ui text send.amount
shot 12-link-after-unlock
```
Expected: the lock screen first, no Send; after the unlock Send opens prefilled.

c. **Cold start.** Kill the app, then **[OWNER]** tap the link in Chrome again.

```bash
source "$SCRATCH/m1d1-accept/env.sh"
kill_app
echo "OWNER: tap the link in Chrome"
ui wait signin.biometric 120 && ui tap signin.biometric
echo "OWNER: touch the fingerprint sensor"
ui wait send.address 180 && ui text send.address
```
Expected: sign-in first, then Send prefilled.

- [ ] **Step 16: [OWNER] Scan a QR code (spec §8.5)**

Open `http://127.0.0.1:8099/pay.html` (or `$SCRATCH/m1d1-accept/web/qr.png`) on the workstation's screen.

```bash
source "$SCRATCH/m1d1-accept/env.sh"
adb -s "$D" shell input keyevent KEYCODE_BACK
ui wait home.row.DGB 30 && ui tap home.row.DGB && ui wait asset.send 60
ui tap asset.send && ui wait send.scan 60 && ui tap send.scan
echo "OWNER: allow camera access if asked, then point the Moto at the QR on the screen"
ui wait send.address 120 && ui text send.address && ui text send.amount && ui text send.note
shot 13-qr-prefilled
adb -s "$D" shell input keyevent KEYCODE_BACK
adb -s "$D" reverse --remove tcp:8099
```
Stop the background `http.server` (kill its process). Expected: the mule address, `0.25`, `Payment request note: QR test`. The camera permission prompt is Android's own (`CAMERA` was already declared).

- [ ] **Step 17: State survives a cold start; count the secure-storage log line (spec §6.4)**

```bash
source "$SCRATCH/m1d1-accept/env.sh"
scan_log 04-before-cold-start
kill_app && adb -s "$D" logcat -c && launch
ui wait signin.biometric 120 && echo "biometric unlock kept across a cold start"
adb -s "$D" logcat -d | grep -c 'EncryptedSharedPreferences initialization failed'
ui tap signin.biometric
echo "OWNER: touch the fingerprint sensor"
ui wait home.row.DGB 180
```
Expected: the biometric button is offered (its marker and the stored password survived); the warning appears at most 3 times (one per namespace with data, Task 11) and nothing else changes.

- [ ] **Step 18: Final log scan**

```bash
source "$SCRATCH/m1d1-accept/env.sh"
scan_log 05-final
```
Expected: `logcat secret scan: clean`. On `LEAK`, the dump is already deleted; stop and report which secret file and which log tags (never the content).

- [ ] **Step 19: Shred the temporary seed copy**

```bash
shred -u ~/.config/dgb-dex/m1d1-send1-seed && ls ~/.config/dgb-dex/ | grep -c m1d1-send1-seed
```
Expected: `0`.

- [ ] **Step 20: Record the results in `docs/release.md`**

Append this section to `~/digibyte-dex/digibyte-wallet/docs/release.md`; fill each Result with PASS or FAIL and a short note from Steps 7–19.

```markdown
## M1-D1 acceptance (0.3.0)

Moto G 5G (2023) `ZY22HVMNKZ`, Android 14. Release AAB versionCode <VC>, installed from Play internal testing.

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Create `send1` with fingerprint unlock; 24-word quiz | | `01-home-send1.png` |
| 2 | Asset detail: empty history; receive address | | `02-asset-empty.png` |
| 3 | Mule → send1 5 DGB (local KDF, seed never on the phone): Pending → Confirmed; spendable while pending: <yes/no> | | `03`, `04`, fund txid |
| 4 | Send 1 DGB to the mule with the fingerprint; Confirm fee = on-chain fee (`txfee.py`) = digiexplorer.info | | `05`–`07`, tx1 |
| 5 | Explorer link opens the right transaction | | owner |
| 6 | bech32 `dgb1…` recipient validates and previews (D8) | | `08-bech32-valid.png` |
| 7 | Look-alike of a recent address: warning, acknowledgement required, nothing sent | | `09-lookalike-blank.png` |
| 8 | Max send with the password after cancelling the fingerprint; final balance | | `10-after-max.png`, tx2 |
| 9 | `digibyte:` link from Chrome: unlocked, locked (after unlock), cold start | | `11`, `12` |
| 10 | QR scan prefills Send | | `13-qr-prefilled.png` |
| 11 | Cold start keeps state; secure-storage warning count: <n> | | step 17 |
| 12 | Logcat contains no seed or password | | scan outputs |

Known gaps: iOS link handling and scanning are compiled by CI and verified in the iOS pass.
```

```bash
cd ~/digibyte-dex/digibyte-wallet
git add docs/release.md
git commit -m "docs(release): M1-D1 on-device acceptance (0.3.0)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

- [ ] **Step 21: Push, open the PR, and wait for CI**

```bash
export SCRATCH=<this session's scratchpad>
cd ~/digibyte-dex/digibyte-wallet
bash tool/secret_scan.sh                                   # secret scan: clean
git ls-files | grep -Ei '\.jks$|\.p8$|key\.properties$|service-account' || echo "no secret files tracked"
git push -u origin feat/m1d1-move-money
cat > "$SCRATCH/m1d1-accept/pr-body.md" <<'EOF'
M1-D1 "Move money" for DigiByte DEX 0.3.0.

- Send DGB/BTC/LTC: the HD source is the richest address (one transaction, D3); Max; a Confirm built from the signed preview (real fee); look-alike and own-address warnings with an acknowledgement; re-authentication on every send through the shared lockout (biometrics or password); one send in flight; the preview is dropped on Back, lock or sign-out.
- Asset detail: balance, Send and Receive, history (pending / confirming n/N / confirmed, 25 per page, pull to refresh), transaction detail with copy and explorer links (digiexplorer.info, mempool.space, litecoinspace.org).
- `digibyte:` payment links from the OS (Android intent filter, iOS URL type, Flutter deep linking off), held until unlock or sign-in for 10 minutes; in-app QR scanner (mobile_scanner, on-device ML Kit) for digibyte:, bitcoin: and litecoin:.
- M1-C follow-ups: restore seed field without selection or autofill (explicit Paste); strong-biometric opt-in that reports failures; the backup password prompt uses the shared lockout; orphaned KDF stopped in any state and the SDK disposed on a failed start; the secure-storage log line documented with a persistence test; Play upload with a 20-minute timeout, resumable chunks and retries.

On-device acceptance: see `docs/release.md` → "M1-D1 acceptance (0.3.0)".

Plan: `Digi-Dex-Komodo/docs/superpowers/plans/2026-10-04-m1d1-move-money.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
gh pr create -R JohnnyLawDGB/digibyte-wallet --base main --head feat/m1d1-move-money \
  --title "M1-D1: move money (send, history, payment links, QR) — 0.3.0" \
  --body-file "$SCRATCH/m1d1-accept/pr-body.md"
gh pr checks --watch -R JohnnyLawDGB/digibyte-wallet "$(gh pr view feat/m1d1-move-money -R JohnnyLawDGB/digibyte-wallet --json number -q .number)"
```
Expected: `secret-scan`, `analyze-test`, `build-android` and `build-ios` are green. `build-ios` is the first compile of the Swift in Task 7; fix any failure on the branch (with the iOS change kept minimal) and push again.

**Stop here.** Report the PR URL and the acceptance table. The controller merges after its final review with `gh pr merge feat/m1d1-move-money --merge -R JohnnyLawDGB/digibyte-wallet`.

## Open questions for the owner

1. **Departure 1** (look-alike check): a destination that is itself in history still warns when it resembles a *different* recent address. Keep, or follow the spec's literal exemption?
2. **ML Kit** (Task 6): the bundled barcode model brings Google Play services components into the APK and may send Google anonymous usage statistics. Acceptable for M1, or should a later milestone switch to an on-device ZXing scanner?
3. **D8** (bech32 recipients): if Step 12 shows that KDF rejects `dgb1…` for the legacy `DGB` ticker, should D1 accept that (legacy addresses only) or should a fix follow?
4. **Unconfirmed balances** (spec §10): Step 10 records whether `spendable` includes the pending deposit. Is spending unconfirmed coins acceptable, or should Available exclude them?
