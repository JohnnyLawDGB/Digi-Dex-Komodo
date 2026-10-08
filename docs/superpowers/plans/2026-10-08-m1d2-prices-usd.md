# M1-D2: Prices and USD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the Moto, DigiByte DEX 0.4.0 from Play internal testing shows USD values from CoinGecko: a portfolio total and each coin's value and 24 h change on Home; the value, unit price and 24h/7d/30d sparklines on asset detail; "≈ $" on Send and Confirm. Without network it shows "Price unavailable" or a stale note while the wallet keeps working, and it fixes the M1-D1 follow-ups R3-1, R3-2 and S3-2.

**Architecture:**
- The app's layering is unchanged (parent spec §4.2, M1-D1): pages → cubits → app-owned repositories and services behind interfaces, with hand-written fakes in `test/support/`.
- Pure rules live in `lib/domain/`: `usd_format.dart` (spec §4.4) and `portfolio_value.dart` (spec §4.1).
- `lib/data/repositories/price_repository.dart`:
  - `PriceRepository`, implemented by `CoinGeckoPriceRepository`.
  - Its HTTP port is `package:http`'s `Client`; tests pass `MockClient`.
  - JSON numbers become strings before `jsonDecode` (`quoteJsonNumbers`), so prices are parsed as `Decimal` from their text.
  - Every outcome is a `PriceResult` (`PriceOk` or `PriceError(PriceFailure)`); nothing throws.
  - The CoinGecko ids come from the SDK coin config (`coingecko_id`) at startup.
- `lib/data/price_service.dart`:
  - `PriceService` implements `PriceFeed`. It handles the 3-minute poll, the backoff, the 15-minute stale flag, the disk copy in the existing `KeyValueStore`, and the 10-minute chart cache.
  - Its timers and clock are injectable.
- `lib/app/price_polling.dart`: `PricePolling` turns the feed on only while signed in, unlocked and in the foreground.
  - It reads the existing `AuthCubit` and `LockCubit` states.
  - `app.dart` forwards the lifecycle to it, beside `LockCubit`.
  - It is provided as `AppServices.prices` and `AppCubits.pricePolling`.
- Screens read prices through `PriceBuilder` (`lib/widgets/price_widgets.dart`, together with `ChangeText`, `StaleNote` and `UsdApprox`).
- Asset detail adds `PriceChartCubit` and `PriceChart`, drawn by `SparklinePainter` (a `CustomPainter`; no chart package).
- The SDK's market data is fully off (`marketDataOff`).
- The follow-ups:
  - R3-1: `knownTime` in `history_repository.dart`.
  - R3-2: a resume-without-answer watch in `DeviceBiometricStore._prompting`, fed by `appLifecycleChanges()`.
  - S3-2: `LastWalletStore`, written on every sign-in by `AppCubits` and read by `SignInCubit`.

**Tech Stack:**
- Flutter 3.41.4 (fvm), Dart ≥3.9, flutter_bloc 9.1.1, go_router 17.5.0, equatable, decimal 3.2.6, intl, very_good_analysis 10.2.0, gen_l10n.
- New direct dependency: `http: ^1.6.0`. It already resolves transitively at 1.6.0 (through `komodo_defi_sdk` and `komodo_cex_market_data`), so no package is added. The lock entry only changes from `transitive` to `direct main`, and no Android permission is added.
- Tests: flutter_test, bloc_test 10, mocktail 1.0, and `package:http/testing.dart` `MockClient`.

**Spec:** `docs/superpowers/specs/2026-10-08-m1d2-prices-usd-design.md` (binding, owner-approved).
- Parent spec: `docs/superpowers/specs/2026-09-27-digibyte-wallet-design.md` §5.1 and §7.1.
- Research: `.superpowers/research/m1d2-prices.md`.
- All paths are relative to `~/Digi-Dex-Komodo`.

**Code base:**
- The repo is `~/digibyte-dex/digibyte-wallet` (`JohnnyLawDGB/digibyte-wallet`), branch `main` at `f9fb142` (M1-D1 merged, plus 0.3.1). The workstation clone's local `main` is behind, at `d750118`; Task 1 fast-forwards it.
- The Flutter app is `app/`.
- The SDK fork is the submodule `third_party/komodo-defi-sdk-flutter` at `c0cb40b9`. This plan needs **no SDK patch**.

**Execution:** subagent-driven (spec §7). Each task gets one fresh implementer and one fresh reviewer. One whole-branch review follows before the release build (Task 10).

### Where this plan departs from the spec, and why

1. **Unit prices (§4.2 vs §4.4).** §4.4 prints anything from $0.01 up with 2 decimals, which would show DGB as "1 DGB = $0.01". §4.2 asks for "1 DGB = $0.012345", and §4.4's own sub-cent example is `$0.012345`.
   - `UsdFormat.value` follows the §4.4 table for amounts.
   - `UsdFormat.price`, used for unit prices only, shows 6 significant digits below $1 (`$0.012345`, `$0.50`), and uses `value` from $1 up.
2. **`http` becomes a direct dependency (§5).** It is already transitive. However, very_good_analysis's `depend_on_referenced_packages` refuses an import of a package that is not listed in `pubspec.yaml`. So it is listed at the version already resolved: no new package and no new permission.
3. **`inactive` alone keeps polling (§3.2).** Polling stops on hidden, paused and detached, as the auto-lock does. Spec §3.2 asks for `resumed` only; with that rule, every system prompt (fingerprint, notification shade) would stop polling and refetch on its dismissal.
4. **Becoming active during a backoff waits it out (§3.2).** "Refresh immediately on sign-in, unlock and resume" applies only when no backoff is running. Otherwise, after a 429, every unlock or app switch would hit CoinGecko again.
5. **The total and unknown balances (§4.1).**
   - A balance that is not known yet (still loading, or a failed activation) is excluded like an unpriced one: "≈ $X" with "excludes LTC".
   - While every balance is still loading, the total shows "…".
   - A row without a price shows no USD line. "Price unavailable" is shown once, as the total, and on asset detail.
6. **Confirm's "≈ $" sits under each value (§4.3 "next to them").** It is its own line under the amount, the fee and the total (`confirm.usd.*`). This keeps the `confirm.amount`, `confirm.fee` and `confirm.total` texts that M1-D1's acceptance reads unchanged.
7. **R3-1 threshold (§6.1).** Any timestamp before 2009-01-03 (the first Bitcoin block) counts as unknown, not only one at or before 0. This also covers Unix time 0 read back from Hive storage in another time zone, for example `1970-01-01T06:00Z`.

**Pre-verification (2026-10-08).**
- The code of Tasks 1–9 was applied by a script to a fresh scratch copy of `main` at `f9fb142` (submodule `c0cb40b9` included). The script applied it exactly as written in this plan: every "Create" and every numbered "Replace … with …", in task order.
- After each task, the script checked:
  - that the task's tests failed before its implementation and passed after it;
  - that `fvm dart format lib test` changed nothing and `fvm flutter analyze` reported `No issues found!`;
  - that the full suite passed;
  - that the task's commit command left `git status` clean.
- The full suite went from 724 tests at `f9fb142` to 742 after Task 1, 771 after Task 2, 810 after Task 3, 818 after Task 4, 836 after Task 5, 842 after Task 6, 847 after Task 7, 858 after Task 8, and finally **868** after Task 9.
- The resulting tree was identical to the hand-verified tree.
- `fvm flutter build apk --debug` then built, and `tool/check_permissions.sh` printed `permissions OK: 5 entries match allowlist`.
- Not verifiable here:
  - any live CoinGecko answer (the dev machine cannot reach CoinGecko);
  - the R3-2 lifecycle signal of the real BiometricPrompt;
  - everything else on the device (all in Task 10).
- Executors still follow every TDD step. A deviation from an expected output is a real finding.

### Known gaps (accepted for M1-D2)

- **iOS** (spec §1, out of scope): nothing in this plan is iOS-specific. The R3-2 watch is Android-only, because the iOS Keychain reports its cancels.
- **The orphaned prompt after 30 s** (release.md R3-2, as observed in 0.3.1).
  - R3-2 fixes "Use password": the app answers within about 1 s.
  - A prompt that is ignored for 30 s still times out while the system prompt stays on screen. The plugin has no way to dismiss it.
  - See the open question at the end of Task 10.

## Global Constraints

- **Identity:**
  - App name **DigiByte DEX**.
  - Android `applicationId` and iOS bundle ID **`me.digiscope.wallet`**; this can never change.
  - Dart package name `digibyte_dex`; every app import is `package:digibyte_dex/...`.
- **Network:** netid `2014` and seed nodes `['seed1.digiscope.me']`, set only in `lib/config/brand.dart`.
- **Assets:**
  - The listed wallet assets are exactly `DGB`, `BTC` and `LTC` (`Brand.listedAssets`), with DGB pinned first.
  - Every SDK asset lookup goes through `findListedAsset` (`lib/data/sdk/asset_lookup.dart`).
- **No Gleec or Komodo services at runtime, and no SDK market data at all:** `marketDataOff` (every provider off, no custom repository), and coin-config auto-update stays off.
  - The only new host is `Brand.priceApiBase` (`https://api.coingecko.com`, no key). It is the only place that names it.
- **Prices:**
  - USD only (spec P2).
  - Spot prices are `Decimal`, parsed from the JSON number's text and never through a `double`. Sparkline points are `double`, because they are display-only.
  - USD is display-only. It never feeds an amount, a fee, a check or the signed preview.
  - Requests carry only `Accept: application/json`. No address, balance or wallet name ever leaves the phone.
- **CoinGecko is unreachable from this dev machine.** Never call it from the workstation. Tests use fakes and fixtures only. `test/support/coingecko_fixtures.dart` holds bodies in the documented `simple/price` and `market_chart` shapes, with the docs cited. The live check happens on the Moto (Task 10).
- **Toolchain:**
  - Flutter `3.41.4` via `.fvmrc`; always `fvm flutter` / `fvm dart`.
  - `very_good_analysis` 10.2.0 with `public_member_api_docs` off. `fvm flutter analyze` must report **`No issues found!`**: infos are fatal.
  - Run `fvm dart format lib test` before every analyze. The formatter does not wrap comments or strings; keep those under 80 columns by hand.
  - After changing `app_en.arb`, run `fvm flutter gen-l10n`. `lib/l10n/gen/` is gitignored.
  - After changing `pubspec.yaml`, run `fvm flutter pub get` and commit `pubspec.lock` with it.
- **Android:**
  - targetSdk 36 and compileSdk 36, minSdk 28, 16 KB page alignment.
  - Permissions stay `INTERNET`, `CAMERA` and `USE_BIOMETRIC`. The merged manifest's allowlist is `tool/check_permissions.sh`, which also lists `ACCESS_NETWORK_STATE` and `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
  - `MainActivity` stays `launchMode="singleTask"`.
  - Predictive back stays enabled. `allowBackup="false"` and `usesCleartextTraffic="false"` (CoinGecko is HTTPS).
- **iOS:** no Swift changes in this plan.
- **Branch:** app tasks commit on **`feat/m1d2-prices-usd`** in `~/digibyte-dex/digibyte-wallet`, created from `main` in Task 1.
- **SDK:** no fork patch.
- **Code style:** match the existing app.
  - Repositories and services are an `abstract interface class` plus an implementation over a small port, with hand-written fakes in `test/support/`.
  - Every interactive or acceptance-read widget is wrapped in `Tagged(id)`, with the same string as its `Key`. New ids use the prefixes `price.*`, `home.total`, `asset.price.*`, `asset.chart.*`, `send.usd` and `confirm.usd.*`. Home rows add `home.row.<T>.usd` and `.change`.
  - Timers and clocks are injectable (`TimerFactory`, `test/support/fake_timers.dart`).
  - Tests capture expected logs with `captureDebugPrint` (unit tests) or `debugPrintsDuring` (widget tests).
  - Catch with `on Object catch` only. Use `unawaited(...)` for fire-and-forget futures.
  - Logs carry only `runtimeType` (`Price request failed: SocketException`), never a URL, price, address, amount, wallet name, seed or password.
  - Equatable values that hold balances or addresses turn `stringify` off (`PortfolioTotal`, `TxView`). Prices are public and keep it on.
  - Lifecycle gating comes from the existing auth and lock state (`PricePolling` reads `AuthCubit.state` and `LockCubit.state`). Never add a second lock or session flag.
- **Strings:** every user-facing word is in `lib/l10n/arb/app_en.arb`, read through `context.l10n`. Exceptions:
  - the dollar formats from `UsdFormat`, which are fixed because USD is the only currency;
  - the biometric prompt texts (M1-C departure 8).
- **Secrets:**
  - Signing material, Play credentials, test seeds and passwords live only in `~/.config/dgb-dex/` (mode 600). They are never committed, echoed or put in test names.
  - Test fixtures use dummies (`DThem0000…`, `Correct-Horse-9`).
- **Devices:** the Moto `ZY22HVMNKZ` only, always as `adb -s ZY22HVMNKZ`. Never touch the Note 8 `ce061716640b191c017e`. Never restart adb.
  - **Never type a real seed via `adb shell input text`**, because adbd logs it. Type throwaway values only, then run `logcat -c` straight after.
  - **Never print UI node text on a seed screen** (backup reveal, quiz, restore). Use the ids-only dump helper (`ids`).
  - Read a checkbox's `checked` state before tapping it.
  - **STOP and relay to the controller before every fingerprint prompt.** The controller tells the owner to touch the sensor or to tap "Use password". The sensor is on the power button. The phone's keyguard is a PIN.
  - The screen timeout may be raised to 30 min during acceptance. It must be restored to `60000` afterwards.
  - Use the official bundletool at `/tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/eab8c964-9b1e-44ec-b157-ec18db695089/scratchpad/tools/bundletool-all-1.18.1.jar`.
- **Release:**
  - Version **0.4.0** (`version: 0.4.0+6`), with a new versionCode from the release lane (`tool/release_android.sh`).
  - Upload with `tool/play_upload.py --track internal --status completed`. This is hands-off, because the service account can release to testing tracks.
  - The owner installs it on the Moto from Play internal testing.
- **Spending:** only the M0 test mule moves funds. It sends about 0.1 DGB to the acceptance wallet `legacy3`, at most twice. `send1` is never used. No LTC or BTC moves.
- **Commit trailer:** every commit message ends with a blank line and then exactly these two lines (the commands below add them with a second `-m`):
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD
  ```
- **PR:** one PR, `feat/m1d2-prices-usd` → `main`, opened in Task 10. Its body ends with the line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. The **controller** merges it after the final whole-branch review and green CI; implementers never merge.
- **Scratch files:** `$SCRATCH` is the executing session's scratchpad directory. Put `export SCRATCH=<that path>` at the start of any command block that uses it.
- **Waiting:** foreground `sleep` is blocked in Claude Code. Waits longer than a few seconds run as a background command, and `ui.py pause N` (at most 10 s) covers short UI settles.

## Review Focus

1. **No network, or CoinGecko blocked, from the very first launch** (no disk copy). Every price field must degrade without breaking anything:
   - The total says "Price unavailable", rows show balances only, and Send shows no "≈".
   - Nothing throws, and polling keeps its 3-minute pace.
   - Prices appear by themselves at the next poll once the network is back.
   - Pinned by:
     - Task 2 `coingecko_price_repository_test.dart`: "a socket error is network, logged by type only", "no answer within the timeout is network".
     - Task 3 `price_service_test.dart`: "network and malformed failures keep the 3-minute poll".
     - Task 4 `home_page_test.dart`: "no prices: \"Price unavailable\"; balances still show".
     - Task 6 `send_page_test.dart`: "no \"≈ $\" without a price".
2. **A price that arrives or moves while the user is on Send or Confirm** must never change the amount typed, the amount previewed, the fee or the total. Only the "≈" lines change.
   - Pinned by Task 6 `send_page_test.dart`: "USD never changes what is sent, even when the price moves".
3. **Rate limits combined with unlock/resume churn** (a 429 followed by app switches) must not hammer CoinGecko:
   - The backoff holds across lock, unlock and resume.
   - Only one request runs at a time.
   - A system prompt (inactive alone) neither stops nor restarts polling.
   - Pinned by:
     - Task 3 `price_service_test.dart`: "a resume during a backoff waits it out", "one fetch at a time".
     - Task 3 `price_polling_test.dart`: "inactive alone (a system prompt on top) changes nothing".
4. **A session adopted from a running KDF (locked from the first frame), a locked app, a backgrounded app, or a signed-out app must fetch nothing.**
   - Pinned by:
     - Task 3 `price_polling_test.dart`: "an adopted session (locked from the start) never polls before the unlock".
     - Task 3 `app_test.dart`: "prices poll only in the foreground, signed in and unlocked".
5. **Odd values from the API must still display correctly:**
   - more digits than a double holds;
   - exponent notation (`8.123e-05`);
   - a null 24 h change;
   - a coin missing from the answer;
   - half-cent rounding (`2.675`, `0.005`);
   - `999.999`.
   - Each must show a sane string, never a float artefact or scientific notation.
   - Pinned by:
     - Task 1 `usd_format_test.dart`: "rounds half up on the exact decimal…", "below a cent…".
     - Task 2 `coingecko_price_repository_test.dart`: "the price is parsed from the JSON text, never a double", "exponent notation is read exactly", "a coin missing from the answer has no quote, no error".

Also pinned, though less likely to be missed:
- A fingerprint that succeeds but answers later than the 1 s grace: the password is asked for anyway, and the late enable write is removed. Task 8: "a late write after the resume-cancel is removed".
- A remembered wallet that was deleted: Task 9, "a deleted wallet falls back to the first".
- An unreadable disk copy: Task 3, "an unreadable cache is ignored, logged by type".

## File map

| Unit | Responsibility | Task |
|---|---|---|
| `lib/domain/usd_format.dart` | USD amounts, unit prices, change arrows (pure) | 1 |
| `lib/domain/portfolio_value.dart` | total, partial total, excluded tickers (pure) | 1 |
| `lib/data/repositories/price_repository.dart` | `PriceQuote`, `PricePoint`, `ChartRange`, `PriceFailure`, `PriceResult`, `CoinGeckoPriceRepository`, `quoteJsonNumbers`, `coinGeckoIdsOf` | 2 |
| `lib/config/brand.dart` | `Brand.priceApiBase` | 2 |
| `lib/data/price_service.dart` | `PriceSnapshot`, `PriceFeed`, `PriceService` (poll, backoff, stale, disk copy, chart cache) | 3 |
| `lib/app/price_polling.dart` | feed on only while signed in, unlocked, in the foreground | 3 |
| `lib/bootstrap/sdk_bootstrap.dart` | `marketDataOff` | 3 |
| `lib/widgets/price_widgets.dart` | `PriceBuilder`, `ChangeText`, `StaleNote`, `UsdApprox` | 4, 6 |
| `lib/features/wallet/view/home_page.dart` | total, row USD and 24 h change | 4 |
| `lib/features/asset/…` | `PriceChartCubit`, `PriceChart`, header USD and unit price | 5 |
| `lib/widgets/sparkline.dart` | `sparklineOffsets`, `SparklinePainter` | 5 |
| `lib/features/send/view/…` | "≈ $" on the form and on Confirm | 6 |
| `lib/data/repositories/history_repository.dart`, `lib/l10n/history_messages.dart` | R3-1: unknown time | 7 |
| `lib/data/biometrics/biometric_store.dart`, `lib/platform/app_lifecycle.dart` | R3-2: resume without an answer | 8 |
| `lib/data/storage/last_wallet_store.dart`, sign-in | S3-2: preselect the last wallet | 9 |

---

### Task 1: Branch, and the pure rules: `UsdFormat` and `PortfolioValue`

Pure Dart with exhaustive unit tests: the USD formats (spec §4.4 and departure 1) and the portfolio total (spec §4.1 and departure 5). Nothing here touches the SDK, the network or widgets.

**Files:**
- Create: `app/lib/domain/usd_format.dart`
- Create: `app/lib/domain/portfolio_value.dart`
- Test (create): `app/test/domain/usd_format_test.dart`
- Test (create): `app/test/domain/portfolio_value_test.dart`

**Interfaces:**
- Consumes: `package:decimal`, `package:equatable` only.
- Produces (`lib/domain/usd_format.dart`):
  - `enum ChangeDirection { up, down, flat }`
  - `abstract final class UsdFormat`, with these static members:
    - `const significantDigits = 6`;
    - `String value(Decimal usd)`;
    - `String price(Decimal usd)`;
    - `String change(Decimal percent)`;
    - `ChangeDirection direction(Decimal percent)`.
- Produces (`lib/domain/portfolio_value.dart`):
  - `class PortfolioTotal extends Equatable`:
    - `const PortfolioTotal({required Decimal? usd, List<String> excluded = const []})`;
    - `bool get partial`;
    - `stringify` off.
  - `abstract final class PortfolioValue { static PortfolioTotal total({required Map<String, Decimal?> balances, required Map<String, Decimal> prices}); }`. `balances` is in display order, with null for an unknown balance.

- [ ] **Step 1: Create the branch**

```bash
cd ~/digibyte-dex/digibyte-wallet
git status --short            # clean
git fetch origin
git checkout main && git pull --ff-only
git log --oneline -1          # f9fb142 Merge pull request #5 ... (or newer)
git checkout -b feat/m1d2-prices-usd
git submodule update --init
git submodule status          # c0cb40b9... third_party/komodo-defi-sdk-flutter
cd app && fvm flutter pub get && fvm flutter gen-l10n && fvm flutter test
```
Expected: `+724: All tests passed!` (the M1-D1 / 0.3.1 baseline).

- [ ] **Step 2: Write the failing tests**

Create `app/test/domain/usd_format_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/domain/usd_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Decimal d(String s) => Decimal.parse(s);

  group('value', () {
    test('cents: two decimals with thousands separators', () {
      expect(UsdFormat.value(d('1234.56')), r'$1,234.56');
      expect(UsdFormat.value(d('1234567.8')), r'$1,234,567.80');
      expect(UsdFormat.value(d('999.999')), r'$1,000.00');
      expect(UsdFormat.value(d('0.01')), r'$0.01');
      expect(UsdFormat.value(d('12')), r'$12.00');
    });

    test('rounds half up on the exact decimal, never through a double', () {
      // 2.675 is 2.67499999… as a double.
      expect(UsdFormat.value(d('2.675')), r'$2.68');
      expect(UsdFormat.value(d('0.125')), r'$0.13');
      expect(UsdFormat.value(d('0.0149')), r'$0.01');
    });

    test('below a cent: up to 6 significant digits, never scientific', () {
      expect(UsdFormat.value(d('0.000123')), r'$0.000123');
      expect(UsdFormat.value(d('0.00012345678')), r'$0.000123457');
      expect(UsdFormat.value(d('0.0001')), r'$0.0001');
      expect(UsdFormat.value(d('0.005')), r'$0.005');
      expect(UsdFormat.value(d('1e-9')), r'$0.000000001');
      expect(UsdFormat.value(d('0.00999999999')), r'$0.01');
    });

    test(r'zero is $0.00', () {
      expect(UsdFormat.value(Decimal.zero), r'$0.00');
      expect(UsdFormat.value(d('0.000')), r'$0.00');
    });

    test('a negative value keeps its sign in front', () {
      expect(UsdFormat.value(d('-1234.5')), r'-$1,234.50');
    });
  });

  group('price', () {
    test(r'from $1: like a value', () {
      expect(UsdFormat.price(d('67187.33589365664')), r'$67,187.34');
      expect(UsdFormat.price(d('1')), r'$1.00');
    });

    test(r'below $1: 6 significant digits, at least 2 decimals', () {
      expect(UsdFormat.price(d('0.012345')), r'$0.012345');
      expect(UsdFormat.price(d('0.0123456789')), r'$0.0123457');
      expect(UsdFormat.price(d('0.5')), r'$0.50');
      expect(UsdFormat.price(d('0.000123')), r'$0.000123');
      expect(UsdFormat.price(d('1.2e-5')), r'$0.000012');
    });

    test(r'zero is $0.00', () {
      expect(UsdFormat.price(Decimal.zero), r'$0.00');
    });
  });

  group('change', () {
    test('an arrow, two decimals and a percent sign', () {
      expect(UsdFormat.change(d('3.2149')), '▲ 3.21%');
      expect(UsdFormat.change(d('-1.055')), '▼ 1.06%');
      expect(UsdFormat.change(d('12')), '▲ 12.00%');
    });

    test('no arrow when it rounds to zero', () {
      expect(UsdFormat.change(Decimal.zero), '0.00%');
      expect(UsdFormat.change(d('-0.004')), '0.00%');
      expect(UsdFormat.change(d('0.004')), '0.00%');
    });

    test('the direction follows the rounded value', () {
      expect(UsdFormat.direction(d('0.005')), ChangeDirection.up);
      expect(UsdFormat.direction(d('-0.005')), ChangeDirection.down);
      expect(UsdFormat.direction(d('0.004')), ChangeDirection.flat);
    });
  });
}
```

Create `app/test/domain/portfolio_value_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/domain/portfolio_value.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Decimal d(String s) => Decimal.parse(s);

  final prices = {'DGB': d('0.0125'), 'BTC': d('60000'), 'LTC': d('80')};

  test('every asset priced: the exact sum, nothing excluded', () {
    final total = PortfolioValue.total(
      balances: {'DGB': d('1000'), 'BTC': d('0.001'), 'LTC': d('0.5')},
      prices: prices,
    );
    expect(total.usd, d('112.5'));
    expect(total.excluded, isEmpty);
    expect(total.partial, isFalse);
  });

  test('Decimal all the way: no float drift', () {
    final total = PortfolioValue.total(
      balances: {'DGB': d('0.1'), 'BTC': d('0.2')},
      prices: {'DGB': d('0.1'), 'BTC': d('0.2')},
    );
    expect(total.usd, d('0.05'));
  });

  test('a non-zero balance without a price is excluded, by name', () {
    final total = PortfolioValue.total(
      balances: {'DGB': d('1000'), 'BTC': d('0.001'), 'LTC': d('0.5')},
      prices: {'DGB': d('0.0125'), 'LTC': d('80')},
    );
    expect(total.usd, d('52.5'));
    expect(total.excluded, ['BTC']);
    expect(total.partial, isTrue);
  });

  test('a zero balance needs no price', () {
    final total = PortfolioValue.total(
      balances: {'DGB': d('1000'), 'BTC': Decimal.zero},
      prices: {'DGB': d('0.0125')},
    );
    expect(total.usd, d('12.5'));
    expect(total.excluded, isEmpty);
  });

  test('a balance not known yet is excluded, in display order', () {
    final total = PortfolioValue.total(
      balances: {'DGB': d('1000'), 'BTC': null, 'LTC': null},
      prices: prices,
    );
    expect(total.usd, d('12.5'));
    expect(total.excluded, ['BTC', 'LTC']);
  });

  test('nothing priced: no total', () {
    final total = PortfolioValue.total(
      balances: {'DGB': d('1000'), 'BTC': Decimal.zero},
      prices: const {},
    );
    expect(total.usd, isNull);
    expect(total.partial, isFalse);
  });

  test('every balance zero and priced: zero dollars', () {
    final total = PortfolioValue.total(
      balances: {'DGB': Decimal.zero, 'BTC': Decimal.zero},
      prices: prices,
    );
    expect(total.usd, Decimal.zero);
    expect(total.excluded, isEmpty);
  });
}
```

- [ ] **Step 3: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test test/domain/usd_format_test.dart test/domain/portfolio_value_test.dart
```
Expected: FAIL to compile: `Error: Undefined name 'UsdFormat'` and `Undefined name 'PortfolioValue'`.

- [ ] **Step 4: Implement**

Create `app/lib/domain/usd_format.dart`:

```dart
import 'package:decimal/decimal.dart';

/// Which way a price moved, for its arrow and colour.
enum ChangeDirection { up, down, flat }

/// USD display rules (spec §4.4). USD is the only fiat currency (spec P2),
/// so these formats are fixed, not localized; the words around them are
/// in the ARB file. Every value is display-only.
abstract final class UsdFormat {
  /// Significant digits below one cent, and in unit prices below $1.
  static const significantDigits = 6;

  static final Decimal _cent = Decimal.parse('0.01');

  /// 10^(significantDigits - 1): a value scaled up to at least this has
  /// [significantDigits] digits before the point.
  static final Decimal _sixDigits = Decimal.fromInt(100000);

  /// A USD amount: `$1,234.56` from one cent up (rounded half-up), up to
  /// 6 significant digits below one cent (`$0.000123`, never scientific),
  /// `$0.00` for zero.
  static String value(Decimal usd) {
    if (usd < Decimal.zero) return '-${value(-usd)}';
    if (usd == Decimal.zero) return r'$0.00';
    if (usd >= _cent) return '\$${_grouped(usd.toStringAsFixed(2))}';
    return '\$${_significant(usd)}';
  }

  /// A unit price ("1 DGB = $0.012345"): like [value] from $1 up; below
  /// $1, 6 significant digits with at least 2 decimals (`$0.50`).
  static String price(Decimal usd) {
    if (usd < Decimal.zero) return '-${price(-usd)}';
    if (usd >= Decimal.one || usd == Decimal.zero) return value(usd);
    return '\$${_significant(usd)}';
  }

  /// A change in percent with its arrow: `▲ 3.21%`, `▼ 1.06%`, and no
  /// arrow when it rounds to `0.00%`.
  static String change(Decimal percent) {
    final digits = percent.abs().toStringAsFixed(2);
    return switch (direction(percent)) {
      ChangeDirection.up => '▲ $digits%',
      ChangeDirection.down => '▼ $digits%',
      ChangeDirection.flat => '$digits%',
    };
  }

  /// The direction of [percent] as shown: after rounding to 2 decimals.
  static ChangeDirection direction(Decimal percent) {
    final shown = percent.round(scale: 2);
    if (shown > Decimal.zero) return ChangeDirection.up;
    if (shown < Decimal.zero) return ChangeDirection.down;
    return ChangeDirection.flat;
  }

  /// [positive] (below 1) to [significantDigits] significant digits, with
  /// trailing zeros trimmed down to 2 decimals.
  static String _significant(Decimal positive) {
    var scale = 0;
    var scaled = positive;
    while (scaled < _sixDigits) {
      scaled *= Decimal.ten;
      scale++;
    }
    final text = positive.toStringAsFixed(scale);
    var end = text.length;
    // Keep at least 2 decimals: `0.50`, never `0.5`.
    while (end - text.indexOf('.') - 1 > 2 && text[end - 1] == '0') {
      end--;
    }
    return text.substring(0, end);
  }

  /// `1234567.89` → `1,234,567.89`.
  static String _grouped(String fixed) {
    final dot = fixed.indexOf('.');
    final whole = fixed.substring(0, dot);
    final out = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) out.write(',');
      out.write(whole[i]);
    }
    return '$out${fixed.substring(dot)}';
  }
}
```

Create `app/lib/domain/portfolio_value.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

/// The portfolio's USD total (spec §4.1). `stringify` is off: it is the
/// value of the wallet's balances.
class PortfolioTotal extends Equatable {
  const PortfolioTotal({required this.usd, this.excluded = const []});

  /// Null when no listed asset has a price ("Price unavailable").
  final Decimal? usd;

  /// Tickers left out of [usd], in display order: a non-zero balance
  /// without a price, or a balance that is not known yet.
  final List<String> excluded;

  /// [usd] is shown as "≈", with a note naming [excluded].
  bool get partial => usd != null && excluded.isNotEmpty;

  @override
  List<Object?> get props => [usd, excluded];

  @override
  bool? get stringify => false;
}

/// Pure total and partial-total rules (spec §4.1).
abstract final class PortfolioValue {
  /// [balances] maps every listed ticker, in display order, to its balance
  /// (null while unknown); [prices] maps tickers to their USD unit price.
  /// A zero balance needs no price.
  static PortfolioTotal total({
    required Map<String, Decimal?> balances,
    required Map<String, Decimal> prices,
  }) {
    if (!balances.keys.any(prices.containsKey)) {
      return const PortfolioTotal(usd: null);
    }
    var sum = Decimal.zero;
    final excluded = <String>[];
    for (final MapEntry(key: ticker, value: balance) in balances.entries) {
      final price = prices[ticker];
      if (balance == null || (balance != Decimal.zero && price == null)) {
        excluded.add(ticker);
      } else if (price != null) {
        sum += balance * price;
      }
    }
    return PortfolioTotal(usd: sum, excluded: excluded);
  }
}
```

- [ ] **Step 5: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test test/domain/usd_format_test.dart test/domain/portfolio_value_test.dart
```
Expected: `+18: All tests passed!`

- [ ] **Step 6: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```
Expected: the formatter changes 0 files; `No issues found!`; `+742: All tests passed!`.

- [ ] **Step 7: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/domain/portfolio_value.dart \
  lib/domain/usd_format.dart \
  test/domain/portfolio_value_test.dart \
  test/domain/usd_format_test.dart
git commit -m "feat(domain): USD formats and the portfolio total" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 2: `PriceRepository` and `CoinGeckoPriceRepository`: spot prices, charts, `PriceFailure`, `Brand.priceApiBase`

Spec §3.1 and P4.
- **Spot prices:** one `GET {base}/api/v3/simple/price?ids=digibyte,bitcoin,litecoin&vs_currencies=usd&include_24hr_change=true` covers every listed coin.
- **Charts:** `GET {base}/api/v3/coins/{id}/market_chart?vs_currency=usd&days=1|7|30`.
- **Errors:**
  - A timeout (10 s) or a network error is `network`.
  - 429 is `rateLimited`.
  - 5xx, and any other non-200 such as a regional 403, is `server`.
  - A body that is not the documented JSON is `malformed`.
- **Logs:** only the error type.
- **Requests:** only `Accept: application/json`.
- **Ids:** they come from the SDK coin config's `coingecko_id` through `coinGeckoIdsOf`. A test pins the bundled config's values (`digibyte`, `bitcoin`, `litecoin`).

**Files:**
- Modify: `app/pubspec.yaml` (`http: ^1.6.0`), and with it `app/pubspec.lock` (`transitive` → `direct main`, same 1.6.0)
- Modify: `app/lib/config/brand.dart`
- Create: `app/lib/data/repositories/price_repository.dart`
- Test (create): `app/test/support/coingecko_fixtures.dart`
- Test (create): `app/test/data/repositories/coingecko_price_repository_test.dart`
- Test (modify): `app/test/config/brand_test.dart`

**Interfaces:**
- Consumes: `package:http` (`Client`, `Response`); `package:decimal`.
- Produces (`lib/config/brand.dart`): `static const priceApiBase = 'https://api.coingecko.com'`.
- Produces (`lib/data/repositories/price_repository.dart`):
  - `class PriceQuote extends Equatable { const PriceQuote({required Decimal usd, required DateTime fetchedAt, Decimal? change24hPct}); }`
  - `class PricePoint extends Equatable { const PricePoint(DateTime time, double usd); }`
  - `enum ChartRange { day(1), week(7), month(30); final int days; }`
  - `enum PriceFailure { network, rateLimited, server, malformed }`
  - The result types:
    - `sealed class PriceResult<T>`;
    - `final class PriceOk<T> extends PriceResult<T> { const PriceOk(T value); }`;
    - `final class PriceError<T> extends PriceResult<T> { const PriceError(PriceFailure failure); }`.
  - `abstract interface class PriceRepository`:
    - `Future<PriceResult<Map<String, PriceQuote>>> spot(List<String> tickers)`;
    - `Future<PriceResult<List<PricePoint>>> chart(String ticker, ChartRange range)`.
  - `class CoinGeckoPriceRepository implements PriceRepository`:
    - constructor `CoinGeckoPriceRepository({required http.Client client, required Map<String, String> ids, required String base, Duration timeout = defaultTimeout, DateTime Function()? now})`;
    - `static const defaultTimeout = Duration(seconds: 10)`.
  - `String quoteJsonNumbers(String json)`
  - `Map<String, String> coinGeckoIdsOf(List<String> tickers, String? Function(String ticker) lookup)`

- [ ] **Step 1: Write the failing tests**

The fixtures follow CoinGecko's documented response shapes. The dev machine cannot reach CoinGecko, so nothing here is recorded live; the header cites the docs pages.

Create `app/test/support/coingecko_fixtures.dart`:

```dart
// Response bodies in the shapes CoinGecko documents. The dev machine cannot
// reach CoinGecko, so these are built from the documented examples, not
// recorded:
// - GET /api/v3/simple/price?ids=…&vs_currencies=usd
//   &include_24hr_change=true — an object keyed by coin id, each with
//   `usd` and `usd_24h_change` (docs.coingecko.com/v3.0.1/reference/
//   simple-price, example `{"bitcoin": {"usd": 67187.33589365664,
//   "usd_24h_change": 3.637278946773539, …}}`).
// - GET /api/v3/coins/{id}/market_chart?vs_currency=usd&days=N —
//   `prices`, `market_caps` and `total_volumes`, each a list of
//   `[unix ms, value]` pairs, oldest first (docs.coingecko.com/v3.0.1/
//   reference/coins-id-market-chart, example `"prices":
//   [[1711843200000, 69702.3087473573], …]`).

/// All three listed coins. DGB's price has more digits than a double
/// holds; LTC's 24 h change is null, as CoinGecko sends for a coin
/// without one.
const simplePriceBody = '''
{
  "bitcoin": {"usd": 67187.33589365664, "usd_24h_change": 3.637278946773539},
  "digibyte": {"usd": 0.01234567890123456789, "usd_24h_change": -1.0549},
  "litecoin": {"usd": 84.12, "usd_24h_change": null}
}
''';

/// Only DGB and BTC: CoinGecko leaves out an id it does not know.
const simplePriceWithoutLitecoin = '''
{
  "bitcoin": {"usd": 67187.33, "usd_24h_change": 3.6},
  "digibyte": {"usd": 0.0123, "usd_24h_change": -1.05}
}
''';

/// A tiny price in exponent form, as CoinGecko sends below 1e-4.
const simplePriceExponent = '''
{"digibyte": {"usd": 8.123e-05, "usd_24h_change": 1.5E+1}}
''';

/// Four points of DGB in USD, oldest first.
const marketChartBody = '''
{
  "prices": [
    [1711843200000, 0.0121],
    [1711846800000, 0.01234],
    [1711850400000, 0.0119],
    [1711854000000, 0.0125]
  ],
  "market_caps": [[1711843200000, 205000000.5]],
  "total_volumes": [[1711843200000, 4100000.25]]
}
''';

/// The body of CoinGecko's 429 (public rate limit).
const rateLimitedBody = '''
{"status": {"error_code": 429, "error_message": "You've exceeded the Rate Limit."}}
''';
```

Create `app/test/data/repositories/coingecko_price_repository_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/repositories/price_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/capture_debug_print.dart';
import '../../support/coingecko_fixtures.dart';

const _ids = {'DGB': 'digibyte', 'BTC': 'bitcoin', 'LTC': 'litecoin'};
const _tickers = ['DGB', 'BTC', 'LTC'];

void main() {
  final now = DateTime.utc(2026, 10, 8, 12);
  late List<http.Request> requests;

  Decimal d(String s) => Decimal.parse(s);

  CoinGeckoPriceRepository build(
    Future<http.Response> Function(http.Request) answer, {
    Duration timeout = const Duration(seconds: 10),
    String base = 'https://api.coingecko.com',
  }) {
    requests = [];
    return CoinGeckoPriceRepository(
      client: MockClient((request) {
        requests.add(request);
        return answer(request);
      }),
      ids: _ids,
      base: base,
      timeout: timeout,
      now: () => now,
    );
  }

  CoinGeckoPriceRepository answering(String body, {int status = 200}) =>
      build((_) async => http.Response(body, status));

  Map<String, PriceQuote> quotesOf(PriceResult<Map<String, PriceQuote>> r) =>
      (r as PriceOk<Map<String, PriceQuote>>).value;

  PriceFailure failureOf(PriceResult<Object?> r) =>
      (r as PriceError<Object?>).failure;

  group('spot prices', () {
    test('one simple/price call for every listed coin', () async {
      final repo = answering(simplePriceBody);
      await repo.spot(_tickers);
      final uri = requests.single.url;
      expect(uri.origin, 'https://api.coingecko.com');
      expect(uri.path, '/api/v3/simple/price');
      expect(uri.queryParameters, {
        'ids': 'digibyte,bitcoin,litecoin',
        'vs_currencies': 'usd',
        'include_24hr_change': 'true',
      });
    });

    test('only Accept: no key, no address, no balance', () async {
      final repo = answering(simplePriceBody);
      await repo.spot(_tickers);
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.headers, {'Accept': 'application/json'});
      expect(request.body, isEmpty);
    });

    test('quotes by ticker, with the 24 h change and the time', () async {
      final quotes = quotesOf(await answering(simplePriceBody).spot(_tickers));
      expect(quotes.keys, unorderedEquals(_tickers));
      expect(quotes['BTC']!.usd, d('67187.33589365664'));
      expect(quotes['BTC']!.change24hPct, d('3.637278946773539'));
      expect(quotes['BTC']!.fetchedAt, now);
      expect(quotes['LTC']!.change24hPct, isNull);
    });

    test('the price is parsed from the JSON text, never a double', () async {
      final quotes = quotesOf(await answering(simplePriceBody).spot(_tickers));
      // A double keeps about 17 significant digits; all 19 survive.
      expect(quotes['DGB']!.usd, d('0.01234567890123456789'));
      expect(quotes['DGB']!.change24hPct, d('-1.0549'));
    });

    test('exponent notation is read exactly', () async {
      final quotes = quotesOf(
        await answering(simplePriceExponent).spot(_tickers),
      );
      expect(quotes['DGB']!.usd, d('0.00008123'));
      expect(quotes['DGB']!.change24hPct, d('15'));
    });

    test('a coin missing from the answer has no quote, no error', () async {
      final quotes = quotesOf(
        await answering(simplePriceWithoutLitecoin).spot(_tickers),
      );
      expect(quotes.keys, unorderedEquals(['DGB', 'BTC']));
    });

    test('a coin entry without a usable price is skipped', () async {
      final quotes = quotesOf(
        await answering(
          '{"digibyte": {"usd": "n/a"}, "bitcoin": {"usd": 1}}',
        ).spot(_tickers),
      );
      expect(quotes.keys, ['BTC']);
    });

    test('a ticker without a CoinGecko id is never asked for', () async {
      final repo = answering(simplePriceBody);
      final quotes = quotesOf(await repo.spot(['DGB', 'DOGE']));
      expect(requests.single.url.queryParameters['ids'], 'digibyte');
      expect(quotes.keys, ['DGB']);
    });

    test('no ids at all: no request', () async {
      final repo = answering(simplePriceBody);
      expect(quotesOf(await repo.spot(['DOGE'])), isEmpty);
      expect(requests, isEmpty);
    });

    test('the base URL is configurable (a later proxy)', () async {
      final repo = build(
        (_) async => http.Response(simplePriceBody, 200),
        base: 'https://prices.example.org/cg/',
      );
      await repo.spot(_tickers);
      expect(
        requests.single.url.toString(),
        startsWith('https://prices.example.org/cg/api/v3/simple/price?'),
      );
    });
  });

  group('failures map to PriceFailure, never throw', () {
    test('429 is rateLimited', () async {
      final r = await answering(rateLimitedBody, status: 429).spot(_tickers);
      expect(failureOf(r), PriceFailure.rateLimited);
    });

    test('5xx is server', () async {
      for (final status in [500, 502, 503]) {
        final r = await answering('oops', status: status).spot(_tickers);
        expect(failureOf(r), PriceFailure.server, reason: '$status');
      }
    });

    test('another refusal (403 from a regional block) is server', () async {
      final r = await answering('blocked', status: 403).spot(_tickers);
      expect(failureOf(r), PriceFailure.server);
    });

    test('a body that is not JSON is malformed', () async {
      final r = await answering('<html>').spot(_tickers);
      expect(failureOf(r), PriceFailure.malformed);
    });

    test('JSON of the wrong shape is malformed', () async {
      final r = await answering('[1, 2]').spot(_tickers);
      expect(failureOf(r), PriceFailure.malformed);
    });

    test('a socket error is network, logged by type only', () async {
      final logs = captureDebugPrint();
      final repo = build(
        (_) async => throw const SocketException('no route to 10.0.0.1'),
      );
      expect(failureOf(await repo.spot(_tickers)), PriceFailure.network);
      expect(logs, ['Price request failed: SocketException']);
    });

    test('no answer within the timeout is network', () async {
      captureDebugPrint();
      final repo = build(
        (_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 1),
      );
      expect(failureOf(await repo.spot(_tickers)), PriceFailure.network);
    });

    test('the default timeout is 10 s', () {
      expect(
        CoinGeckoPriceRepository.defaultTimeout,
        const Duration(seconds: 10),
      );
    });
  });

  group('charts', () {
    test('market_chart in USD for the range', () async {
      final repo = answering(marketChartBody);
      for (final range in ChartRange.values) {
        await repo.chart('DGB', range);
        final uri = requests.last.url;
        expect(uri.path, '/api/v3/coins/digibyte/market_chart');
        expect(uri.queryParameters, {
          'vs_currency': 'usd',
          'days': '${range.days}',
        });
      }
      expect([for (final r in ChartRange.values) r.days], [1, 7, 30]);
    });

    test('points oldest first, as time and price', () async {
      final r = await answering(marketChartBody).chart('DGB', ChartRange.week);
      final points = (r as PriceOk<List<PricePoint>>).value;
      expect(points, hasLength(4));
      expect(
        points.first.time,
        DateTime.fromMillisecondsSinceEpoch(1711843200000, isUtc: true),
      );
      expect(points.first.usd, 0.0121);
      expect(points.last.usd, 0.0125);
    });

    test('a chart without prices is malformed', () async {
      final r = await answering(
        jsonEncode({'market_caps': <Object>[]}),
      ).chart('DGB', ChartRange.week);
      expect(failureOf(r), PriceFailure.malformed);
    });

    test('a broken point is skipped', () async {
      final r = await answering(
        '{"prices": [[1711843200000, 0.0121], [null, 1], [1711850400000]]}',
      ).chart('DGB', ChartRange.week);
      expect((r as PriceOk<List<PricePoint>>).value, hasLength(1));
    });

    test('429 and 5xx map like spot prices', () async {
      expect(
        failureOf(
          await answering('', status: 429).chart('DGB', ChartRange.day),
        ),
        PriceFailure.rateLimited,
      );
      expect(
        failureOf(
          await answering('', status: 500).chart('DGB', ChartRange.day),
        ),
        PriceFailure.server,
      );
    });

    test('a ticker without an id has no chart and no request', () async {
      final repo = answering(marketChartBody);
      final r = await repo.chart('DOGE', ChartRange.week);
      expect((r as PriceOk<List<PricePoint>>).value, isEmpty);
      expect(requests, isEmpty);
    });
  });

  group('quoteJsonNumbers', () {
    test('turns numbers into strings, keeping their exact text', () {
      expect(
        quoteJsonNumbers('{"a": -1.5e-7, "b": [0, 12.30], "c": null}'),
        '{"a": "-1.5e-7", "b": ["0", "12.30"], "c": null}',
      );
    });

    test('leaves strings alone, escapes included', () {
      const json = r'{"k 1": "x\"2, 3", "n": 4}';
      expect(quoteJsonNumbers(json), r'{"k 1": "x\"2, 3", "n": "4"}');
    });
  });

  group('coinGeckoIdsOf', () {
    test('the coin-config id of each ticker', () {
      expect(
        coinGeckoIdsOf(_tickers, (t) => _ids[t]),
        _ids,
      );
    });

    test('a ticker without an id, or whose lookup fails, is left out', () {
      final logs = captureDebugPrint();
      final ids = coinGeckoIdsOf(_tickers, (t) {
        if (t == 'BTC') throw StateError('no BTC asset');
        return t == 'LTC' ? '' : _ids[t];
      });
      expect(ids, {'DGB': 'digibyte'});
      expect(logs, ['No CoinGecko id: StateError']);
    });

    test('the bundled coin config maps DGB, BTC and LTC', () {
      final config =
          jsonDecode(
                File(
                  '../third_party/komodo-defi-sdk-flutter/packages/'
                  'komodo_defi_framework/assets/config/coins_config.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      String? idOf(String ticker) =>
          (config[ticker] as Map<String, dynamic>)['coingecko_id'] as String?;
      expect(coinGeckoIdsOf(_tickers, idOf), _ids);
    });
  });
}
```

Edit `app/test/config/brand_test.dart` (1 replacement, top to bottom):

**1.** Replace:

```dart
    expect(Brand.supportUrl, startsWith('https://'));
  });
```

with:

```dart
    expect(Brand.supportUrl, startsWith('https://'));
    expect(Brand.priceApiBase, 'https://api.coingecko.com');
  });
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test test/data/repositories/coingecko_price_repository_test.dart test/config/brand_test.dart
```
Expected: FAIL to compile: `price_repository.dart` not found, and `Member not found: 'priceApiBase'`.

- [ ] **Step 3: Implement**

Edit `app/pubspec.yaml` (1 replacement, top to bottom):

**1.** Replace:

```yaml
  go_router: ^17.5.0
  intl: any
```

with:

```yaml
  go_router: ^17.5.0
  http: ^1.6.0
  intl: any
```

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter pub get
git diff --stat pubspec.lock      # 1 line: http becomes "direct main", still 1.6.0
```

Edit `app/lib/config/brand.dart` (1 replacement, top to bottom):

**1.** Replace:

```dart
  static const supportUrl = 'https://digiscope.me';
}
```

with:

```dart
  static const supportUrl = 'https://digiscope.me';

  /// Where USD prices come from (spec P4): CoinGecko's public API, no
  /// key. A digiscope.me proxy can replace it later.
  static const priceApiBase = 'https://api.coingecko.com';
}
```

Create `app/lib/data/repositories/price_repository.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// One coin's spot price in USD (spec §3.1).
class PriceQuote extends Equatable {
  const PriceQuote({
    required this.usd,
    required this.fetchedAt,
    this.change24hPct,
  });

  /// Parsed from the JSON number's text, never through a double.
  final Decimal usd;

  /// The 24 h change in percent (CoinGecko `usd_24h_change`), if known.
  final Decimal? change24hPct;
  final DateTime fetchedAt;

  @override
  List<Object?> get props => [usd, change24hPct, fetchedAt];
}

/// One sparkline point. A double is fine: the chart is display-only.
class PricePoint extends Equatable {
  const PricePoint(this.time, this.usd);

  final DateTime time;
  final double usd;

  @override
  List<Object?> get props => [time, usd];
}

/// The sparkline periods of asset detail (spec §4.2).
enum ChartRange {
  day(1),
  week(7),
  month(30);

  const ChartRange(this.days);

  /// CoinGecko's `days` parameter.
  final int days;
}

/// Why prices could not be fetched (spec §3.1).
enum PriceFailure {
  /// No answer: offline, DNS, TLS, or the 10 s timeout.
  network,

  /// HTTP 429.
  rateLimited,

  /// HTTP 5xx, or any other refusal.
  server,

  /// An answer that is not the documented JSON.
  malformed,
}

/// A price call's outcome. Price calls never throw.
sealed class PriceResult<T> {
  const PriceResult();
}

final class PriceOk<T> extends PriceResult<T> {
  const PriceOk(this.value);

  final T value;
}

final class PriceError<T> extends PriceResult<T> {
  const PriceError(this.failure);

  final PriceFailure failure;
}

/// USD prices of the listed assets. Nothing about the wallet (addresses,
/// balances) is ever sent.
abstract interface class PriceRepository {
  /// The spot price of each of [tickers] that has one, by ticker. A coin
  /// missing from the answer has no quote; that is not an error.
  Future<PriceResult<Map<String, PriceQuote>>> spot(List<String> tickers);

  /// [ticker]'s USD price over [range], oldest first.
  Future<PriceResult<List<PricePoint>>> chart(String ticker, ChartRange range);
}

/// [PriceRepository] over CoinGecko's public API (spec P1, P4): one
/// `simple/price` call for all listed coins, and `market_chart` per chart.
/// The `client` is the HTTP port; tests pass `MockClient`.
class CoinGeckoPriceRepository implements PriceRepository {
  CoinGeckoPriceRepository({
    required http.Client client,
    required Map<String, String> ids,
    required String base,
    Duration timeout = defaultTimeout,
    DateTime Function()? now,
  }) : _client = client,
       _ids = ids,
       _base = base.endsWith('/') ? base.substring(0, base.length - 1) : base,
       _timeout = timeout,
       _now = now ?? DateTime.now;

  static const defaultTimeout = Duration(seconds: 10);

  final http.Client _client;

  /// Ticker → CoinGecko id, from the coin config ([coinGeckoIdsOf]).
  final Map<String, String> _ids;
  final String _base;
  final Duration _timeout;
  final DateTime Function() _now;

  @override
  Future<PriceResult<Map<String, PriceQuote>>> spot(
    List<String> tickers,
  ) async {
    final wanted = {
      for (final ticker in tickers) ticker: ?_ids[ticker],
    };
    if (wanted.isEmpty) return const PriceOk({});
    final answer = await _get('/api/v3/simple/price', {
      'ids': wanted.values.join(','),
      'vs_currencies': 'usd',
      'include_24hr_change': 'true',
    });
    switch (answer) {
      case PriceError(:final failure):
        return PriceError(failure);
      case PriceOk(value: final Map<String, dynamic> coins):
        final at = _now();
        return PriceOk({
          for (final MapEntry(key: ticker, value: id) in wanted.entries)
            ticker: ?_quoteOf(coins[id], at),
        });
      case PriceOk():
        return const PriceError(PriceFailure.malformed);
    }
  }

  /// One coin's entry; numbers arrive as their JSON text
  /// ([quoteJsonNumbers]). Null when it has no usable price.
  static PriceQuote? _quoteOf(Object? entry, DateTime at) {
    if (entry is! Map<String, dynamic>) return null;
    final usd = _decimal(entry['usd']);
    if (usd == null) return null;
    return PriceQuote(
      usd: usd,
      change24hPct: _decimal(entry['usd_24h_change']),
      fetchedAt: at,
    );
  }

  static Decimal? _decimal(Object? text) =>
      text is String ? Decimal.tryParse(text) : null;

  @override
  Future<PriceResult<List<PricePoint>>> chart(
    String ticker,
    ChartRange range,
  ) async {
    final id = _ids[ticker];
    if (id == null) return const PriceOk([]);
    final answer = await _get('/api/v3/coins/$id/market_chart', {
      'vs_currency': 'usd',
      'days': '${range.days}',
    });
    switch (answer) {
      case PriceError(:final failure):
        return PriceError(failure);
      case PriceOk(value: {'prices': final List<dynamic> prices}):
        return PriceOk([
          for (final pair in prices) ?_pointOf(pair),
        ]);
      case PriceOk():
        return const PriceError(PriceFailure.malformed);
    }
  }

  /// `[unix ms, price]`; null when broken.
  static PricePoint? _pointOf(Object? pair) {
    if (pair is! List<dynamic> || pair.length < 2) return null;
    final ms = pair[0] is String ? num.tryParse(pair[0] as String) : null;
    final usd = pair[1] is String ? double.tryParse(pair[1] as String) : null;
    if (ms == null || usd == null || !usd.isFinite) return null;
    return PricePoint(
      DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true),
      usd,
    );
  }

  /// GETs [path] and decodes the JSON body with every number as its text.
  Future<PriceResult<Object?>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeout);
    } on Object catch (error) {
      debugPrint('Price request failed: ${error.runtimeType}');
      return const PriceError(PriceFailure.network);
    }
    final status = response.statusCode;
    if (status == 429) return const PriceError(PriceFailure.rateLimited);
    if (status != 200) return const PriceError(PriceFailure.server);
    try {
      return PriceOk(
        jsonDecode(quoteJsonNumbers(utf8.decode(response.bodyBytes))),
      );
    } on FormatException {
      return const PriceError(PriceFailure.malformed);
    }
  }
}

/// [json] with every number turned into a JSON string of its exact text,
/// so `jsonDecode` never makes it a double (spec §3.1: prices are parsed
/// as Decimal from the JSON number's text). Strings, escapes included,
/// are copied unchanged.
String quoteJsonNumbers(String json) {
  final out = StringBuffer();
  var inString = false;
  var escaped = false;
  var i = 0;
  while (i < json.length) {
    final c = json[i];
    if (inString) {
      out.write(c);
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      i++;
    } else if (c == '"') {
      inString = true;
      out.write(c);
      i++;
    } else if (c == '-' || _digits.contains(c)) {
      final start = i++;
      while (i < json.length && _numberChars.contains(json[i])) {
        i++;
      }
      out.write('"${json.substring(start, i)}"');
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

const _digits = '0123456789';
const _numberChars = '0123456789.eE+-';

/// The CoinGecko id of each of [tickers], from the coin config's
/// `coingecko_id` through [lookup]. A ticker without one is left out, and
/// its price is never asked for.
Map<String, String> coinGeckoIdsOf(
  List<String> tickers,
  String? Function(String ticker) lookup,
) {
  final ids = <String, String>{};
  for (final ticker in tickers) {
    try {
      final id = lookup(ticker);
      if (id != null && id.isNotEmpty) ids[ticker] = id;
    } on Object catch (error) {
      debugPrint('No CoinGecko id: ${error.runtimeType}');
    }
  }
  return ids;
}
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test test/data/repositories/coingecko_price_repository_test.dart test/config/brand_test.dart
```
Expected: `+30: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```
Expected: the formatter changes 0 files; `No issues found!`; `+771: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  pubspec.yaml \
  pubspec.lock \
  lib/config/brand.dart \
  lib/data/repositories/price_repository.dart \
  test/config/brand_test.dart \
  test/data/repositories/coingecko_price_repository_test.dart \
  test/support/coingecko_fixtures.dart
git commit -m "feat(prices): CoinGecko client with exact decimals and typed failures" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 3: `PriceService`, polling gated by auth, lock and lifecycle, the disk copy, and SDK market data off

Spec §3.2, §3.3 and departures 3–4.
- **`PriceService`:**
  - It polls every 3 minutes while active, and fetches at once when it becomes active. One fetch runs at a time.
  - After `rateLimited` or `server` it backs off 3 → 6 → 12 → 24 → 30 minutes. It does not fetch early when it becomes active during a backoff, and a success resets the backoff.
  - It keeps the last good quotes, which go stale more than 15 minutes after the last success.
  - It saves quotes and time to `KeyValueStore` key `price_cache_v1`. `loadCache()` shows them, stale, on a cold start, unless a fetch has already finished.
  - It caches each chart for 10 minutes per (ticker, range), and shares one request when two ask at once.
- **`PricePolling`:** it calls `setActive(signedIn && unlocked && foreground)`.
  - It is created after `LockCubit`, so an adopted session (which `LockCubit` locks on its first auth event) never polls.
  - `app.dart` forwards the lifecycle to it, as it does to `LockCubit`.
- **`main.dart`:** it builds the service, with the ids from the SDK coin config, and awaits `loadCache()` before `runApp`.
- **`sdk_bootstrap.dart`:** it disables every SDK market-data provider. With them on, the SDK downloads coin lists from Binance, CoinPaprika and CoinGecko at every start (`market_data_manager.dart` `_warmCoinLists`).

**Files:**
- Create: `app/lib/data/price_service.dart`
- Create: `app/lib/app/price_polling.dart`
- Modify: `app/lib/app/app_scope.dart`, `app/lib/app/app.dart`, `app/lib/main.dart`, `app/lib/bootstrap/sdk_bootstrap.dart`
- Test (create): `app/test/support/fake_price_repository.dart`, `app/test/support/fake_price_feed.dart`, `app/test/data/price_service_test.dart`, `app/test/app/price_polling_test.dart`
- Test (modify): `app/test/support/test_app.dart`, `app/test/app/app_scope_test.dart`, `app/test/app/app_test.dart`, `app/test/bootstrap/sdk_bootstrap_test.dart`

**Interfaces:**
- Consumes:
  - from Task 2: `PriceRepository`, `PriceQuote`, `PricePoint`, `ChartRange`, `PriceFailure`, `PriceResult` / `PriceOk` / `PriceError`, `CoinGeckoPriceRepository`, `coinGeckoIdsOf`, `Brand.priceApiBase`;
  - existing: `KeyValueStore`, `TimerFactory` (`lib/platform/clipboard_guard.dart`), `AuthCubit` / `AuthSignedIn`, `LockCubit` / `Unlocked`, `findListedAsset`.
- Produces (`lib/data/price_service.dart`):
  - `class PriceSnapshot extends Equatable`:
    - `const PriceSnapshot({Map<String, PriceQuote> quotes = const {}, DateTime? updatedAt, bool stale = false, PriceFailure? failure})`;
    - `Map<String, Decimal> get usd`.
  - `abstract interface class PriceFeed`:
    - `PriceSnapshot get current`;
    - `Stream<PriceSnapshot> get snapshots`;
    - `void setActive({required bool active})`;
    - `Future<PriceResult<List<PricePoint>>> chart(String ticker, ChartRange range)`.
  - `class PriceService implements PriceFeed`:
    - constructor `PriceService({required PriceRepository repository, required KeyValueStore store, required List<String> tickers, TimerFactory? timer, DateTime Function()? now})`;
    - constants `interval`, `maxBackoff`, `staleAfter`, `chartTtl`, and `cacheKey = 'price_cache_v1'`;
    - `static Duration backoff(int failures)`;
    - `Future<void> loadCache()` and `void dispose()`.
- Produces (`lib/app/price_polling.dart`):
  - `class PricePolling`:
    - `PricePolling({required PriceFeed prices, required AuthCubit auth, required LockCubit lock})`;
    - `void onLifecycleChanged(AppLifecycleState state)`;
    - `Future<void> close()`.
- Produces (`lib/app/app_scope.dart`):
  - `AppServices` gains `required PriceFeed prices`.
  - `AppCubits` gains `late final PricePolling pricePolling`.
  - `AppScope` provides `PriceFeed` and `PricePolling`.
- Produces (`lib/bootstrap/sdk_bootstrap.dart`): `const marketDataOff = MarketDataConfig(...)`, with every provider off.
- Produces (tests):
  - `FakePriceRepository`: `spotResult`, `spotGate`, `spotCalls`, `chartResult`, `chartGate`, `chartCalls`, `prices(map, at:)`, `fail(failure)`.
  - `FakePriceFeed`: `emit`, `activeCalls`, `active`, `chartResult`, `chartGate`, `chartCalls`.
  - `PriceSnapshot priced(Map<String, String> usd, {Map<String, String> change, bool stale, DateTime? at})`.
  - `TestApp.prices`.

- [ ] **Step 1: Write the failing tests**

Create `app/test/support/fake_price_repository.dart`:

```dart
import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/repositories/price_repository.dart';

/// Hand-written [PriceRepository]: answers what the test sets, records
/// every call.
class FakePriceRepository implements PriceRepository {
  /// What [spot] answers next.
  PriceResult<Map<String, PriceQuote>> spotResult = const PriceOk({});

  /// When set, [spot] waits for it (a request in flight).
  Completer<void>? spotGate;

  /// Every [spot] call's tickers, in order.
  final spotCalls = <List<String>>[];

  /// What [chart] answers next.
  PriceResult<List<PricePoint>> chartResult = const PriceOk([]);

  /// When set, [chart] waits for it.
  Completer<void>? chartGate;

  /// Every [chart] call, in order.
  final chartCalls = <(String, ChartRange)>[];

  /// Makes [spot] answer [usd] (ticker → price text) at [at].
  void prices(Map<String, String> usd, {required DateTime at}) {
    spotResult = PriceOk({
      for (final MapEntry(key: ticker, value: price) in usd.entries)
        ticker: PriceQuote(usd: Decimal.parse(price), fetchedAt: at),
    });
  }

  void fail(PriceFailure failure) => spotResult = PriceError(failure);

  @override
  Future<PriceResult<Map<String, PriceQuote>>> spot(
    List<String> tickers,
  ) async {
    spotCalls.add(tickers);
    await spotGate?.future;
    return spotResult;
  }

  @override
  Future<PriceResult<List<PricePoint>>> chart(
    String ticker,
    ChartRange range,
  ) async {
    chartCalls.add((ticker, range));
    await chartGate?.future;
    return chartResult;
  }
}
```

Create `app/test/support/fake_price_feed.dart`:

```dart
import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/price_service.dart';
import 'package:digibyte_dex/data/repositories/price_repository.dart';

/// Hand-written [PriceFeed]: the test pushes snapshots and sets chart
/// answers; [setActive] calls are recorded.
class FakePriceFeed implements PriceFeed {
  final _changes = StreamController<PriceSnapshot>.broadcast();
  PriceSnapshot _current = const PriceSnapshot();

  /// Every [setActive] value, in order.
  final activeCalls = <bool>[];

  /// What [chart] answers.
  PriceResult<List<PricePoint>> chartResult = const PriceOk([]);

  /// When set, [chart] waits for it.
  Completer<void>? chartGate;

  /// Every [chart] call, in order.
  final chartCalls = <(String, ChartRange)>[];

  /// Whether the last [setActive] turned polling on.
  bool get active => activeCalls.isNotEmpty && activeCalls.last;

  void emit(PriceSnapshot snapshot) {
    _current = snapshot;
    _changes.add(snapshot);
  }

  @override
  PriceSnapshot get current => _current;

  @override
  Stream<PriceSnapshot> get snapshots => _changes.stream;

  @override
  void setActive({required bool active}) => activeCalls.add(active);

  @override
  Future<PriceResult<List<PricePoint>>> chart(
    String ticker,
    ChartRange range,
  ) async {
    chartCalls.add((ticker, range));
    await chartGate?.future;
    return chartResult;
  }
}

/// A snapshot with [usd] (ticker → price text) and [change] (ticker →
/// 24 h change in percent), fetched at [at].
PriceSnapshot priced(
  Map<String, String> usd, {
  Map<String, String> change = const {},
  bool stale = false,
  DateTime? at,
}) {
  final time = at ?? DateTime.utc(2026, 10, 8, 12);
  return PriceSnapshot(
    quotes: {
      for (final MapEntry(key: ticker, value: price) in usd.entries)
        ticker: PriceQuote(
          usd: Decimal.parse(price),
          change24hPct: switch (change[ticker]) {
            final pct? => Decimal.parse(pct),
            null => null,
          },
          fetchedAt: time,
        ),
    },
    updatedAt: time,
    stale: stale,
  );
}
```

Create `app/test/data/price_service_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/price_service.dart';
import 'package:digibyte_dex/data/repositories/price_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/capture_debug_print.dart';
import '../support/fake_price_repository.dart';
import '../support/fake_timers.dart';
import '../support/in_memory_key_value_store.dart';

const _tickers = ['DGB', 'BTC', 'LTC'];

void main() {
  late FakePriceRepository repo;
  late InMemoryKeyValueStore store;
  late FakeTimers timers;
  late DateTime now;

  setUp(() {
    repo = FakePriceRepository();
    store = InMemoryKeyValueStore();
    timers = FakeTimers();
    now = DateTime.utc(2026, 10, 8, 12);
    repo.prices({'DGB': '0.0125', 'BTC': '60000'}, at: now);
  });

  PriceService build() {
    final service = PriceService(
      repository: repo,
      store: store,
      tickers: _tickers,
      timer: timers.create,
      now: () => now,
    );
    addTearDown(service.dispose);
    return service;
  }

  /// The single pending poll timer.
  FakeTimer poll() => timers.pending.single;

  Future<void> fire() async {
    poll().fire();
    await pumpEventQueue();
  }

  Future<void> activate(PriceService service) async {
    service.setActive(active: true);
    await pumpEventQueue();
  }

  group('polling', () {
    test('nothing is fetched until the service is active', () async {
      build();
      await pumpEventQueue();
      expect(repo.spotCalls, isEmpty);
      expect(timers.created, isEmpty);
    });

    test('active: fetches at once for every listed ticker, then every '
        '3 minutes', () async {
      final service = build();
      await activate(service);
      expect(repo.spotCalls, [_tickers]);
      expect(service.current.quotes['DGB']!.usd, Decimal.parse('0.0125'));
      expect(poll().duration, const Duration(minutes: 3));
      await fire();
      expect(repo.spotCalls, hasLength(2));
      expect(poll().duration, const Duration(minutes: 3));
    });

    test('inactive (locked, background, signed out): polling stops', () async {
      final service = build();
      await activate(service);
      service.setActive(active: false);
      expect(timers.pending, isEmpty);
      await pumpEventQueue();
      expect(repo.spotCalls, hasLength(1));
    });

    test('active again (unlock, resume, sign-in): refreshes at once', () async {
      final service = build();
      await activate(service);
      service.setActive(active: false);
      await activate(service);
      expect(repo.spotCalls, hasLength(2));
      expect(poll().duration, const Duration(minutes: 3));
    });

    test('a repeated active is not another fetch', () async {
      final service = build();
      await activate(service);
      await activate(service);
      expect(repo.spotCalls, hasLength(1));
    });

    test('one fetch at a time', () async {
      final service = build();
      repo.spotGate = Completer<void>();
      service
        ..setActive(active: true)
        ..setActive(active: false)
        ..setActive(active: true);
      await pumpEventQueue();
      expect(repo.spotCalls, hasLength(1));
      repo.spotGate!.complete();
      await pumpEventQueue();
      expect(service.current.quotes, isNotEmpty);
      expect(poll().duration, const Duration(minutes: 3));
    });

    test(
      'deactivated while a fetch runs: its result is kept, no next poll',
      () async {
        final service = build();
        repo.spotGate = Completer<void>();
        service.setActive(active: true);
        await pumpEventQueue();
        service.setActive(active: false);
        repo.spotGate!.complete();
        await pumpEventQueue();
        expect(service.current.quotes, isNotEmpty);
        expect(timers.pending, isEmpty);
      },
    );
  });

  group('backoff', () {
    test('rate limits back off 3, 6, 12, 24, then 30 minutes; a success '
        'resets it', () async {
      final service = build();
      repo.fail(PriceFailure.rateLimited);
      await activate(service);
      final waits = <int>[poll().duration.inMinutes];
      for (var i = 0; i < 5; i++) {
        await fire();
        waits.add(poll().duration.inMinutes);
      }
      expect(waits, [3, 6, 12, 24, 30, 30]);
      repo.prices({'DGB': '0.0125'}, at: now);
      await fire();
      expect(poll().duration, const Duration(minutes: 3));
      repo.fail(PriceFailure.rateLimited);
      await fire();
      expect(poll().duration, const Duration(minutes: 3));
      await fire();
      expect(poll().duration, const Duration(minutes: 6));
    });

    test('server errors back off too', () async {
      final service = build();
      repo.fail(PriceFailure.server);
      await activate(service);
      await fire();
      expect(poll().duration, const Duration(minutes: 6));
    });

    test('network and malformed failures keep the 3-minute poll', () async {
      final service = build();
      repo.fail(PriceFailure.network);
      await activate(service);
      await fire();
      expect(poll().duration, const Duration(minutes: 3));
      repo.fail(PriceFailure.malformed);
      await fire();
      expect(poll().duration, const Duration(minutes: 3));
    });

    test('a resume during a backoff waits it out', () async {
      final service = build();
      repo.fail(PriceFailure.rateLimited);
      await activate(service);
      await fire(); // second failure: 6 minutes
      service.setActive(active: false);
      now = now.add(const Duration(minutes: 1));
      await activate(service);
      expect(repo.spotCalls, hasLength(2));
      expect(poll().duration, const Duration(minutes: 5));
      await fire();
      expect(repo.spotCalls, hasLength(3));
    });

    test('the backoff schedule', () {
      expect(
        [for (var n = 1; n <= 7; n++) PriceService.backoff(n).inMinutes],
        [3, 6, 12, 24, 30, 30, 30],
      );
    });
  });

  group('snapshots', () {
    test('the last good quotes stay through a failure', () async {
      final service = build();
      await activate(service);
      repo.fail(PriceFailure.network);
      await fire();
      expect(service.current.quotes['BTC']!.usd, Decimal.parse('60000'));
      expect(service.current.failure, PriceFailure.network);
      expect(service.current.updatedAt, now);
    });

    test('stale once the last success is more than 15 minutes old', () async {
      final service = build();
      await activate(service);
      expect(service.current.stale, isFalse);
      repo.fail(PriceFailure.network);
      now = now.add(const Duration(minutes: 15));
      await fire();
      expect(service.current.stale, isFalse);
      now = now.add(const Duration(minutes: 1));
      await fire();
      expect(service.current.stale, isTrue);
      repo.prices({'DGB': '0.013'}, at: now);
      await fire();
      expect(service.current.stale, isFalse);
      expect(service.current.failure, isNull);
    });

    test('a resume after a long background is stale before it '
        'refreshes', () async {
      final service = build();
      await activate(service);
      service.setActive(active: false);
      now = now.add(const Duration(hours: 2));
      repo.spotGate = Completer<void>();
      service.setActive(active: true);
      expect(service.current.stale, isTrue);
      repo.spotGate!.complete();
    });

    test('a coin missing from the answer loses its quote', () async {
      final service = build();
      await activate(service);
      repo.prices({'DGB': '0.0125'}, at: now);
      await fire();
      expect(service.current.quotes.keys, ['DGB']);
    });

    test('every change is streamed', () async {
      final service = build();
      final seen = <PriceSnapshot>[];
      final sub = service.snapshots.listen(seen.add);
      addTearDown(sub.cancel);
      await activate(service);
      expect(seen.last, service.current);
      expect(seen.last.quotes, hasLength(2));
    });

    test('usd maps tickers to their price', () async {
      final service = build();
      await activate(service);
      expect(service.current.usd, {
        'DGB': Decimal.parse('0.0125'),
        'BTC': Decimal.parse('60000'),
      });
    });
  });

  group('disk cache', () {
    test('a success is saved: quotes and time only', () async {
      repo.spotResult = PriceOk({
        'DGB': PriceQuote(
          usd: Decimal.parse('0.0125'),
          change24hPct: Decimal.parse('-1.5'),
          fetchedAt: now,
        ),
      });
      await activate(build());
      final saved =
          jsonDecode(store.values[PriceService.cacheKey]!)
              as Map<String, dynamic>;
      expect(saved, {
        'at': now.toIso8601String(),
        'quotes': {
          'DGB': {'usd': '0.0125', 'change': '-1.5'},
        },
      });
    });

    test('a cold start shows the saved prices, stale, before any '
        'fetch', () async {
      await activate(build());
      final restarted = build();
      await restarted.loadCache();
      expect(restarted.current.quotes['DGB']!.usd, Decimal.parse('0.0125'));
      expect(restarted.current.updatedAt, now);
      expect(restarted.current.stale, isTrue);
      repo.prices({'DGB': '0.013'}, at: now);
      await activate(restarted);
      expect(restarted.current.stale, isFalse);
      expect(restarted.current.quotes['DGB']!.usd, Decimal.parse('0.013'));
    });

    test('a fresh fetch is never replaced by a slower cache read', () async {
      await activate(build());
      final restarted = build();
      final gate = Completer<void>();
      store.readGate = gate.future;
      final loading = restarted.loadCache();
      repo.prices({'DGB': '0.02'}, at: now);
      await activate(restarted);
      gate.complete();
      await loading;
      expect(restarted.current.quotes['DGB']!.usd, Decimal.parse('0.02'));
      expect(restarted.current.stale, isFalse);
    });

    test('an unreadable cache is ignored, logged by type', () async {
      final logs = captureDebugPrint();
      store.values[PriceService.cacheKey] = '{"at": 5';
      final service = build();
      await service.loadCache();
      expect(service.current.quotes, isEmpty);
      store.readError = Exception('keystore');
      await service.loadCache();
      expect(logs, [
        'Price cache read failed: FormatException',
        'Price cache read failed: _Exception',
      ]);
    });

    test('a failed save is logged and changes nothing', () async {
      final logs = captureDebugPrint();
      store.writeError = Exception('keystore');
      final service = build();
      await activate(service);
      expect(service.current.quotes, isNotEmpty);
      expect(logs, ['Price cache write failed: _Exception']);
    });
  });

  group('charts', () {
    final points = [
      PricePoint(DateTime.utc(2026, 10), 0.012),
      PricePoint(DateTime.utc(2026, 10, 2), 0.013),
    ];

    test('fetched on demand, cached 10 minutes per ticker and range', () async {
      final service = build();
      repo.chartResult = PriceOk(points);
      final first = await service.chart('DGB', ChartRange.week);
      expect((first as PriceOk<List<PricePoint>>).value, points);
      await service.chart('DGB', ChartRange.week);
      expect(repo.chartCalls, [('DGB', ChartRange.week)]);
      await service.chart('DGB', ChartRange.day);
      await service.chart('BTC', ChartRange.week);
      expect(repo.chartCalls, hasLength(3));
      now = now.add(const Duration(minutes: 10));
      await service.chart('DGB', ChartRange.week);
      expect(repo.chartCalls, hasLength(4));
    });

    test('a failed chart is not cached', () async {
      final service = build();
      repo.chartResult = const PriceError(PriceFailure.network);
      final failed = await service.chart('DGB', ChartRange.week);
      expect(
        (failed as PriceError<List<PricePoint>>).failure,
        PriceFailure.network,
      );
      repo.chartResult = PriceOk(points);
      await service.chart('DGB', ChartRange.week);
      expect(repo.chartCalls, hasLength(2));
    });

    test('two requests at once share one call', () async {
      final service = build();
      repo
        ..chartResult = PriceOk(points)
        ..chartGate = Completer<void>();
      final a = service.chart('DGB', ChartRange.month);
      final b = service.chart('DGB', ChartRange.month);
      repo.chartGate!.complete();
      await Future.wait([a, b]);
      expect(repo.chartCalls, hasLength(1));
    });
  });

  test('dispose stops polling and the stream', () async {
    final service = PriceService(
      repository: repo,
      store: store,
      tickers: _tickers,
      timer: timers.create,
      now: () => now,
    );
    await activate(service);
    var done = false;
    service.snapshots.listen(null, onDone: () => done = true);
    service.dispose();
    await pumpEventQueue();
    expect(timers.pending, isEmpty);
    expect(done, isTrue);
  });
}
```

Create `app/test/app/price_polling_test.dart`:

```dart
import 'package:digibyte_dex/app/price_polling.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_price_feed.dart';
import '../support/fake_wallet_repository.dart';
import '../support/in_memory_key_value_store.dart';

void main() {
  late FakeWalletRepository wallet;
  late FakePriceFeed prices;
  late AuthCubit auth;
  late LockCubit lock;
  late PricePolling polling;

  setUp(() {
    wallet = FakeWalletRepository();
    prices = FakePriceFeed();
    auth = AuthCubit(
      wallet,
      backups: BackupStatusStore(InMemoryKeyValueStore()),
    );
    // Created in this order, like AppCubits: the lock cubit hears each
    // auth event first.
    lock = LockCubit(authStates: auth.stream);
    polling = PricePolling(prices: prices, auth: auth, lock: lock);
  });
  tearDown(() async {
    await polling.close();
    await lock.close();
    await auth.close();
    await wallet.dispose();
  });

  /// A sign-in the app watched happen (signed out first): unlocked.
  Future<void> signIn() async {
    wallet.emit(null);
    await pumpEventQueue();
    wallet.emit(const WalletUser('main'));
    await pumpEventQueue();
  }

  test('nothing polls before a sign-in', () async {
    wallet.emit(null);
    await pumpEventQueue();
    expect(prices.active, isFalse);
  });

  test('a sign-in starts polling; a sign-out stops it', () async {
    await signIn();
    expect(prices.active, isTrue);
    wallet.emit(null);
    await pumpEventQueue();
    expect(prices.active, isFalse);
  });

  test('a lock stops polling; an unlock starts it again', () async {
    await signIn();
    lock.lockNow();
    await pumpEventQueue();
    expect(prices.active, isFalse);
    lock.unlock();
    await pumpEventQueue();
    expect(prices.active, isTrue);
  });

  test('the background stops polling; a resume starts it again', () async {
    await signIn();
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      polling.onLifecycleChanged(state);
      expect(prices.active, isFalse, reason: '$state');
      polling.onLifecycleChanged(AppLifecycleState.resumed);
      expect(prices.active, isTrue);
    }
  });

  test('inactive alone (a system prompt on top) changes nothing', () async {
    await signIn();
    final calls = prices.activeCalls.length;
    polling
      ..onLifecycleChanged(AppLifecycleState.inactive)
      ..onLifecycleChanged(AppLifecycleState.resumed);
    expect(prices.active, isTrue);
    expect(prices.activeCalls.skip(calls), everyElement(isTrue));
  });

  test('a sign-in while in the background waits for the resume', () async {
    polling.onLifecycleChanged(AppLifecycleState.paused);
    await signIn();
    expect(prices.active, isFalse);
    polling.onLifecycleChanged(AppLifecycleState.resumed);
    expect(prices.active, isTrue);
  });

  test('an adopted session (locked from the start) never polls before '
      'the unlock', () async {
    wallet.emit(const WalletUser('main'));
    await pumpEventQueue();
    expect(lock.state, const Locked());
    expect(prices.activeCalls, everyElement(isFalse));
    lock.unlock();
    await pumpEventQueue();
    expect(prices.active, isTrue);
  });

  test('close stops polling for good', () async {
    await signIn();
    await polling.close();
    expect(prices.active, isFalse);
    polling.onLifecycleChanged(AppLifecycleState.resumed);
    expect(prices.active, isFalse);
  });
}
```

Edit `app/test/support/test_app.dart` (3 replacements, top to bottom):

**1.** Replace:

```dart
import 'fake_payment_link_source.dart';
import 'fake_qr_scanner.dart';
```

with:

```dart
import 'fake_payment_link_source.dart';
import 'fake_price_feed.dart';
import 'fake_qr_scanner.dart';
```

**2.** Replace:

```dart
  final links = FakePaymentLinkSource();
  late final PendingPaymentRequest pendingRequest = _pendingRequest();
```

with:

```dart
  final links = FakePaymentLinkSource();
  final prices = FakePriceFeed();
  late final PendingPaymentRequest pendingRequest = _pendingRequest();
```

**3.** Replace:

```dart
    links: links,
    session: session,
```

with:

```dart
    links: links,
    prices: prices,
    session: session,
```

Edit `app/test/app/app_scope_test.dart` (5 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/app/app_scope.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/payment_links.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
```

with:

```dart
import 'package:digibyte_dex/app/app_scope.dart';
import 'package:digibyte_dex/app/price_polling.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/payment_links.dart';
import 'package:digibyte_dex/data/price_service.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
```

**2.** Replace:

```dart
import '../support/fake_payment_link_source.dart';
import '../support/fake_qr_scanner.dart';
```

with:

```dart
import '../support/fake_payment_link_source.dart';
import '../support/fake_price_feed.dart';
import '../support/fake_qr_scanner.dart';
```

**3.** Replace:

```dart
  late FakeWalletRepository wallet;
  late AppServices services;

  setUp(() {
    wallet = FakeWalletRepository();
    final storage = InMemoryKeyValueStore();
```

with:

```dart
  late FakeWalletRepository wallet;
  late FakePriceFeed prices;
  late AppServices services;

  setUp(() {
    wallet = FakeWalletRepository();
    prices = FakePriceFeed();
    final storage = InMemoryKeyValueStore();
```

**4.** Replace:

```dart
      links: FakePaymentLinkSource(),
    );
```

with:

```dart
      links: FakePaymentLinkSource(),
      prices: prices,
    );
```

**5.** Replace:

```dart
    expect(probe.read<ActiveSend>(), same(cubits.activeSend));
  });
```

with:

```dart
    expect(probe.read<ActiveSend>(), same(cubits.activeSend));
    expect(probe.read<PriceFeed>(), same(prices));
    expect(probe.read<PricePolling>(), same(cubits.pricePolling));
  });

  test('prices poll only while signed in and unlocked', () async {
    final cubits = build();
    wallet.emit(null);
    await settle();
    expect(prices.active, isFalse);
    wallet.emit(const WalletUser('main'));
    await settle();
    expect(prices.active, isTrue);
    cubits.lock.lockNow();
    await settle();
    expect(prices.active, isFalse);
  });

  test('closing the cubits stops the prices', () async {
    final cubits = AppCubits(services);
    wallet.emit(null);
    await settle();
    wallet.emit(const WalletUser('main'));
    await settle();
    await cubits.close();
    expect(prices.active, isFalse);
  });
```

Edit `app/test/app/app_test.dart` (1 replacement, top to bottom):

**1.** Replace:

```dart
    app.wallet.emit(null);
    await t.pumpAndSettle();
    expect(find.text('Welcome to DigiByte DEX'), findsOneWidget);
  });

  testWidgets('locking now clears the pending backup session', (t) async {
```

with:

```dart
    app.wallet.emit(null);
    await t.pumpAndSettle();
    expect(find.text('Welcome to DigiByte DEX'), findsOneWidget);
  });

  testWidgets('prices poll only in the foreground, signed in and '
      'unlocked', (t) async {
    final app = TestApp();
    addTearDown(app.dispose);
    await t.pumpWidget(app.build());
    await signIn(t, app);
    expect(app.prices.active, isTrue);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await t.pump();
    expect(app.prices.active, isFalse);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(app.prices.active, isTrue);
    app.lock.lockNow();
    await t.pumpAndSettle();
    expect(app.prices.active, isFalse);
  });

  testWidgets('locking now clears the pending backup session', (t) async {
```

Edit `app/test/bootstrap/sdk_bootstrap_test.dart` (1 replacement, top to bottom):

**1.** Replace:

```dart
    expect(c.enableAssetAutoUpdate, isFalse);
  });
```

with:

```dart
    expect(c.enableAssetAutoUpdate, isFalse);
  });

  test('no SDK market data at all: no Binance, CoinPaprika, CoinGecko '
      'or Komodo price provider, and no custom one', () {
    final m = c.marketDataConfig;
    expect(m.enableKomodoPrice, isFalse);
    expect(m.enableBinance, isFalse);
    expect(m.enableCoinPaprika, isFalse);
    expect(m.enableCoinGecko, isFalse);
    expect(m.customRepositories, isEmpty);
  });
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/data/price_service_test.dart \
  test/app/price_polling_test.dart \
  test/bootstrap/sdk_bootstrap_test.dart \
  test/app/app_scope_test.dart \
  test/app/app_test.dart
```
Expected: FAIL.
- `price_service.dart` and `price_polling.dart` are not found.
- `No named parameter with the name 'prices'`.
- In `sdk_bootstrap_test.dart`, "no SDK market data at all…" fails on `enableBinance` (`Expected: false, Actual: <true>`).

- [ ] **Step 3: Implement**

Create `app/lib/data/price_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/repositories/price_repository.dart';
import 'package:digibyte_dex/data/storage/key_value_store.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart' show TimerFactory;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// What the price fields show (spec §3.2). Prices are public data.
class PriceSnapshot extends Equatable {
  const PriceSnapshot({
    this.quotes = const {},
    this.updatedAt,
    this.stale = false,
    this.failure,
  });

  /// The last good quotes, by ticker. A ticker without one has no price.
  final Map<String, PriceQuote> quotes;

  /// When [quotes] were fetched; null before the first success.
  final DateTime? updatedAt;

  /// [quotes] are old: the last success is more than 15 minutes ago, or
  /// they come from the disk copy of an earlier run.
  final bool stale;

  /// Why the latest fetch failed; null after a success.
  final PriceFailure? failure;

  /// Ticker → USD unit price.
  Map<String, Decimal> get usd => {
    for (final MapEntry(key: ticker, value: quote) in quotes.entries)
      ticker: quote.usd,
  };

  @override
  List<Object?> get props => [quotes, updatedAt, stale, failure];
}

/// The app-wide price source the screens read (spec §3.2).
abstract interface class PriceFeed {
  /// The latest snapshot.
  PriceSnapshot get current;

  /// Every snapshot after [current].
  Stream<PriceSnapshot> get snapshots;

  /// Polls while [active]: signed in, unlocked and in the foreground
  /// (`PricePolling` decides). Becoming active refreshes at once.
  void setActive({required bool active});

  /// [ticker]'s sparkline over [range], fetched on demand.
  Future<PriceResult<List<PricePoint>>> chart(String ticker, ChartRange range);
}

/// [PriceFeed] over a [PriceRepository], one per running app (spec §3.2):
/// - polls every [interval] while active, and at once on becoming active;
/// - backs off after a rate limit or server error ([backoff]), but never
///   fetches early on becoming active during a backoff;
/// - keeps the last good quotes, marked [PriceSnapshot.stale] after
///   [staleAfter];
/// - keeps a disk copy (quotes and time, nothing secret) in [KeyValueStore]
///   for the first paint after a cold start ([loadCache]);
/// - caches each sparkline for [chartTtl].
///
/// Timers are injectable; tests pass fake ones.
class PriceService implements PriceFeed {
  PriceService({
    required PriceRepository repository,
    required KeyValueStore store,
    required List<String> tickers,
    TimerFactory? timer,
    DateTime Function()? now,
  }) : _repository = repository,
       _store = store,
       _tickers = tickers,
       _timer = timer ?? Timer.new,
       _now = now ?? DateTime.now;

  static const interval = Duration(minutes: 3);
  static const maxBackoff = Duration(minutes: 30);
  static const staleAfter = Duration(minutes: 15);
  static const chartTtl = Duration(minutes: 10);
  static const cacheKey = 'price_cache_v1';

  final PriceRepository _repository;
  final KeyValueStore _store;
  final List<String> _tickers;
  final TimerFactory _timer;
  final DateTime Function() _now;
  final _changes = StreamController<PriceSnapshot>.broadcast();

  PriceSnapshot _current = const PriceSnapshot();
  Map<String, PriceQuote> _quotes = const {};
  DateTime? _updatedAt;
  PriceFailure? _failure;

  /// [_quotes] were read from disk and nothing newer has arrived.
  bool _fromDisk = false;
  bool _active = false;
  bool _fetching = false;
  bool _disposed = false;

  /// Rate-limit or server failures in a row.
  int _failures = 0;

  /// No fetch before this, during a backoff.
  DateTime? _notBefore;
  Timer? _next;

  final _charts = <(String, ChartRange), (DateTime, List<PricePoint>)>{};
  final _chartLoads =
      <(String, ChartRange), Future<PriceResult<List<PricePoint>>>>{};

  /// The wait after [failures] rate-limit or server failures in a row:
  /// 3, 6, 12, 24, then 30 minutes.
  static Duration backoff(int failures) {
    final wait = interval * (1 << (failures - 1).clamp(0, 10));
    return wait > maxBackoff ? maxBackoff : wait;
  }

  @override
  PriceSnapshot get current => _current;

  @override
  Stream<PriceSnapshot> get snapshots => _changes.stream;

  @override
  void setActive({required bool active}) {
    if (_disposed || active == _active) return;
    _active = active;
    if (!active) {
      _next?.cancel();
      _next = null;
      return;
    }
    // Time passed while inactive: the quotes may have gone stale.
    _publish();
    if (_fetching) return;
    final wait = _notBefore?.difference(_now());
    if (wait != null && wait > Duration.zero) {
      _schedule(wait);
    } else {
      unawaited(_fetch());
    }
  }

  void _schedule(Duration delay) {
    _next?.cancel();
    _next = _timer(delay, () => unawaited(_fetch()));
  }

  Future<void> _fetch() async {
    if (!_active || _fetching) return;
    _fetching = true;
    _next?.cancel();
    final result = await _repository.spot(_tickers);
    _fetching = false;
    if (_disposed) return;
    final Duration wait;
    switch (result) {
      case PriceOk(value: final quotes):
        _quotes = quotes;
        _updatedAt = _now();
        _fromDisk = false;
        _failure = null;
        _failures = 0;
        _notBefore = null;
        wait = interval;
        unawaited(_save());
      case PriceError(:final failure):
        _failure = failure;
        if (failure == PriceFailure.rateLimited ||
            failure == PriceFailure.server) {
          wait = backoff(++_failures);
          _notBefore = _now().add(wait);
        } else {
          wait = interval;
        }
    }
    _publish();
    if (_active) _schedule(wait);
  }

  void _publish() {
    final at = _updatedAt;
    _current = PriceSnapshot(
      quotes: _quotes,
      updatedAt: at,
      stale: at != null && (_fromDisk || _now().difference(at) > staleAfter),
      failure: _failure,
    );
    if (!_changes.isClosed) _changes.add(_current);
  }

  /// Shows the disk copy of an earlier run, stale, unless prices arrived
  /// first. Never throws.
  Future<void> loadCache() async {
    try {
      final raw = await _store.read(cacheKey);
      if (raw == null || _updatedAt != null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.parse(json['at'] as String);
      final quotes = {
        for (final MapEntry(key: ticker, value: entry)
            in (json['quotes'] as Map<String, dynamic>).entries)
          ticker: _quoteFromJson(entry as Map<String, dynamic>, at),
      };
      if (_updatedAt != null || _disposed) return;
      _quotes = quotes;
      _updatedAt = at;
      _fromDisk = true;
      _publish();
    } on Object catch (error) {
      debugPrint('Price cache read failed: ${error.runtimeType}');
    }
  }

  static PriceQuote _quoteFromJson(Map<String, dynamic> json, DateTime at) {
    final change = json['change'] as String?;
    return PriceQuote(
      usd: Decimal.parse(json['usd'] as String),
      change24hPct: change == null ? null : Decimal.parse(change),
      fetchedAt: at,
    );
  }

  Future<void> _save() async {
    final at = _updatedAt;
    if (at == null) return;
    try {
      await _store.write(
        cacheKey,
        jsonEncode({
          'at': at.toIso8601String(),
          'quotes': {
            for (final MapEntry(key: ticker, value: quote) in _quotes.entries)
              ticker: {
                'usd': quote.usd.toString(),
                if (quote.change24hPct case final change?)
                  'change': change.toString(),
              },
          },
        }),
      );
    } on Object catch (error) {
      debugPrint('Price cache write failed: ${error.runtimeType}');
    }
  }

  @override
  Future<PriceResult<List<PricePoint>>> chart(
    String ticker,
    ChartRange range,
  ) {
    final key = (ticker, range);
    final cached = _charts[key];
    if (cached != null && _now().difference(cached.$1) < chartTtl) {
      return Future.value(PriceOk(cached.$2));
    }
    return _chartLoads[key] ??= _loadChart(key);
  }

  Future<PriceResult<List<PricePoint>>> _loadChart(
    (String, ChartRange) key,
  ) async {
    try {
      final result = await _repository.chart(key.$1, key.$2);
      if (result case PriceOk(value: final points)) {
        _charts[key] = (_now(), points);
      }
      return result;
    } finally {
      unawaited(_chartLoads.remove(key));
    }
  }

  /// Stops polling and ends [snapshots].
  void dispose() {
    _disposed = true;
    _active = false;
    _next?.cancel();
    unawaited(_changes.close());
  }
}
```

Create `app/lib/app/price_polling.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/price_service.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

/// Runs the price feed only while a wallet is signed in, unlocked and in
/// the foreground (spec §3.2), from the app's own auth and lock state.
///
/// Inactive alone (a system prompt or the notification shade on top)
/// changes nothing, as for the auto-lock: hidden, paused and detached are
/// the background. Create it after the lock cubit, so that cubit has
/// handled an auth event (an adopted session locks at once) before this
/// reads its state.
class PricePolling {
  PricePolling({
    required PriceFeed prices,
    required AuthCubit auth,
    required LockCubit lock,
  }) : _prices = prices,
       _auth = auth,
       _lock = lock {
    _authChanges = auth.stream.listen((_) => _apply());
    _lockChanges = lock.stream.listen((_) => _apply());
    _apply();
  }

  final PriceFeed _prices;
  final AuthCubit _auth;
  final LockCubit _lock;
  late final StreamSubscription<AuthState> _authChanges;
  late final StreamSubscription<AppLockState> _lockChanges;
  bool _foreground = true;
  bool _closed = false;

  void onLifecycleChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _foreground = false;
      case AppLifecycleState.inactive:
        break;
    }
    _apply();
  }

  void _apply() => _prices.setActive(
    active:
        !_closed &&
        _foreground &&
        _auth.state is AuthSignedIn &&
        _lock.state is Unlocked,
  );

  Future<void> close() async {
    _closed = true;
    _apply();
    await _authChanges.cancel();
    await _lockChanges.cancel();
  }
}
```

Edit `app/lib/app/app_scope.dart` (6 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/app/app.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/payment_links.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
```

with:

```dart
import 'package:digibyte_dex/app/app.dart';
import 'package:digibyte_dex/app/price_polling.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/payment_links.dart';
import 'package:digibyte_dex/data/price_service.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
```

**2.** Replace:

```dart
    required this.links,
    PendingBackupSession? session,
```

with:

```dart
    required this.links,
    required this.prices,
    PendingBackupSession? session,
```

**3.** Replace:

```dart
  final PaymentLinkSource links;
  final PendingBackupSession session;
```

with:

```dart
  final PaymentLinkSource links;

  /// USD prices for every screen (M1-D2 spec §3.2).
  final PriceFeed prices;
  final PendingBackupSession session;
```

**4.** Replace:

```dart
/// send whose broadcast has started past its page; signing out clears it.
class AppCubits {
```

with:

```dart
/// send whose broadcast has started past its page; signing out clears it.
/// [pricePolling] runs the price feed while signed in and unlocked.
class AppCubits {
```

**5.** Replace:

```dart
    );
  }

  late final AuthCubit auth;
  late final LockCubit lock;
  final activeSend = ActiveSend();
  late final StreamSubscription<AuthState> _signedOut;

  Future<void> close() async {
    await _signedOut.cancel();
```

with:

```dart
    );
    // After the lock cubit: see PricePolling.
    pricePolling = PricePolling(
      prices: services.prices,
      auth: auth,
      lock: lock,
    );
  }

  late final AuthCubit auth;
  late final LockCubit lock;
  late final PricePolling pricePolling;
  final activeSend = ActiveSend();
  late final StreamSubscription<AuthState> _signedOut;

  Future<void> close() async {
    await pricePolling.close();
    await _signedOut.cancel();
```

**6.** Replace:

```dart
      RepositoryProvider.value(value: services.pendingRequest),
    ],
```

with:

```dart
      RepositoryProvider.value(value: services.pendingRequest),
      RepositoryProvider<PriceFeed>.value(value: services.prices),
      RepositoryProvider.value(value: cubits.pricePolling),
    ],
```

Edit `app/lib/app/app.dart` (2 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/app/payment_link_dispatcher.dart';
import 'package:digibyte_dex/app/router.dart';
```

with:

```dart
import 'package:digibyte_dex/app/payment_link_dispatcher.dart';
import 'package:digibyte_dex/app/price_polling.dart';
import 'package:digibyte_dex/app/router.dart';
```

**2.** Replace:

```dart
    context.read<LockCubit>().onLifecycleChanged(state);
    unawaited(context.read<ClipboardGuard>().handleLifecycleChanged(state));
```

with:

```dart
    context.read<LockCubit>().onLifecycleChanged(state);
    context.read<PricePolling>().onLifecycleChanged(state);
    unawaited(context.read<ClipboardGuard>().handleLifecycleChanged(state));
```

Edit `app/lib/main.dart` (4 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/bootstrap/sdk_bootstrap.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/payment_links.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/send_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
```

with:

```dart
import 'package:digibyte_dex/bootstrap/sdk_bootstrap.dart';
import 'package:digibyte_dex/config/brand.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/payment_links.dart';
import 'package:digibyte_dex/data/price_service.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/price_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/send_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/sdk/asset_lookup.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
```

**2.** Replace:

```dart
import 'package:flutter/services.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart' show KomodoDefiSdk;
```

with:

```dart
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart' show KomodoDefiSdk;
```

**3.** Replace:

```dart
  await seeds.init();
  return AppServices(
```

with:

```dart
  await seeds.init();
  final prices = PriceService(
    repository: CoinGeckoPriceRepository(
      client: http.Client(),
      ids: coinGeckoIdsOf(
        Brand.listedAssets,
        (ticker) => findListedAsset(sdk, ticker).id.symbol.coinGeckoId,
      ),
      base: Brand.priceApiBase,
    ),
    store: storage,
    tickers: Brand.listedAssets,
  );
  // The last prices, stale, for the first paint (never throws).
  await prices.loadCache();
  return AppServices(
```

**4.** Replace:

```dart
    links: const PaymentLinkSource(),
  );
```

with:

```dart
    links: const PaymentLinkSource(),
    prices: prices,
  );
```

Edit `app/lib/bootstrap/sdk_bootstrap.dart` (2 replacements, top to bottom):

**1.** Replace:

```dart

/// The only place the SDK is configured. Every non-default here is a
```

with:

```dart

/// No SDK market-data provider at all (M1-D2 spec §3.3, P4): the app's
/// own CoinGecko client fetches prices. With any provider on, the SDK
/// downloads coin lists from it at startup.
const marketDataOff = MarketDataConfig(
  enableKomodoPrice: false,
  enableBinance: false,
  enableCoinPaprika: false,
  enableCoinGecko: false,
);

/// The only place the SDK is configured. Every non-default here is a
```

**2.** Replace:

```dart
  preActivateCustomTokenAssets: false,
  marketDataConfig: const MarketDataConfig(enableKomodoPrice: false),
  enableAssetAutoUpdate: false,
```

with:

```dart
  preActivateCustomTokenAssets: false,
  marketDataConfig: marketDataOff,
  enableAssetAutoUpdate: false,
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/data/price_service_test.dart \
  test/app/price_polling_test.dart \
  test/bootstrap/sdk_bootstrap_test.dart \
  test/app/app_scope_test.dart \
  test/app/app_test.dart
```
Expected: `+82: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```
Expected: the formatter changes 0 files; `No issues found!`; `+810: All tests passed!`.

- [ ] **Step 6: Check the Android build and the permission allowlist**

`main.dart` now opens HTTPS connections through `package:http` (dart:io). INTERNET is already granted.

```bash
cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter build apk --debug
cd .. && tool/check_permissions.sh
```
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`; `permissions OK: 5 entries match allowlist`.

- [ ] **Step 7: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/app/app.dart \
  lib/app/app_scope.dart \
  lib/app/price_polling.dart \
  lib/bootstrap/sdk_bootstrap.dart \
  lib/data/price_service.dart \
  lib/main.dart \
  test/app/app_scope_test.dart \
  test/app/app_test.dart \
  test/app/price_polling_test.dart \
  test/bootstrap/sdk_bootstrap_test.dart \
  test/data/price_service_test.dart \
  test/support/fake_price_feed.dart \
  test/support/fake_price_repository.dart \
  test/support/test_app.dart
git commit -m "feat(prices): price service polled while signed in, unlocked and in front; SDK market data off" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 4: Home: the USD total, each row's USD value and 24 h change, stale and unavailable states

Spec §4.1 and departure 5.
- **Header:**
  - The label "Total value".
  - The total (`home.total`): `$112.50` when complete. When partial, `≈ $52.50` with `excludes BTC` (`home.total.excludes`). With no price, `Price unavailable`. While every balance is loading, `…`.
  - `Prices as of 14:05` (`price.stale`) while stale.
- **Each active row:** under the balance, one line with the USD value (`home.row.<T>.usd`) and the 24 h change (`home.row.<T>.change`, ▲ in green, ▼ in red). A row without a price has no USD line.
- **Shared price widgets:** `PriceBuilder`, `ChangeText` and `StaleNote`, in `lib/widgets/price_widgets.dart`.

**Files:**
- Create: `app/lib/widgets/price_widgets.dart`
- Modify: `app/lib/features/wallet/view/home_page.dart`
- Modify: `app/lib/l10n/arb/app_en.arb`
- Test (modify): `app/test/features/wallet/home_page_test.dart`

**Interfaces:**
- Consumes:
  - Task 1: `UsdFormat`, `ChangeDirection`, `PortfolioValue.total`.
  - Task 3: `PriceFeed`, `PriceSnapshot` (`quotes`, `usd`, `stale`, `updatedAt`).
  - Test helpers: `FakePriceFeed` and `priced(...)`.
- Produces (`lib/widgets/price_widgets.dart`):
  - `class PriceBuilder extends StatelessWidget { const PriceBuilder({required Widget Function(BuildContext, PriceSnapshot) builder}); }`
  - `Color? changeColor(BuildContext context, ChangeDirection direction)`
  - `class ChangeText extends StatelessWidget { const ChangeText({required String id, required Decimal percent}); }`
  - `class StaleNote extends StatelessWidget { const StaleNote({required PriceSnapshot prices}); }`
- Produces (ARB):
  - `homeTotalLabel`, `priceUnavailable`;
  - `priceExcludes(String tickers)`, `pricesAsOf(String time)`, `usdApprox(String usd)`.
- HomePage now reads `PriceFeed` from the tree. `AppScope` provides it (Task 3), and widget tests that pump `HomePage` provide a `FakePriceFeed`.

- [ ] **Step 1: Write the failing tests**

Edit `app/test/features/wallet/home_page_test.dart` (6 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
```

with:

```dart
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/price_service.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
```

**2.** Replace:

```dart
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_assets_repository.dart';
import '../../support/fake_wallet_repository.dart';
```

with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../support/fake_assets_repository.dart';
import '../../support/fake_price_feed.dart';
import '../../support/fake_wallet_repository.dart';
```

**3.** Replace:

```dart
  late FakeAssetsRepository assets;
  late AuthCubit auth;
```

with:

```dart
  late FakeAssetsRepository assets;
  late FakePriceFeed prices;
  late AuthCubit auth;
```

**4.** Replace:

```dart
    assets = FakeAssetsRepository();
  });
```

with:

```dart
    assets = FakeAssetsRepository();
    prices = FakePriceFeed();
  });
```

**5.** Replace:

```dart
      t,
      RepositoryProvider<AssetsRepository>.value(
        value: assets,
        child: MultiBlocProvider(
```

with:

```dart
      t,
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AssetsRepository>.value(value: assets),
          RepositoryProvider<PriceFeed>.value(value: prices),
        ],
        child: MultiBlocProvider(
```

**6.** Replace:

```dart
      '0',
    );
  });

```

with:

```dart
      '0',
    );
  });

  Future<void> balances(WidgetTester t, Map<String, String> totals) async {
    for (final MapEntry(key: ticker, value: total) in totals.entries) {
      final amount = Decimal.parse(total);
      assets.emitBalance(
        ticker,
        BalanceView(total: amount, spendable: amount),
      );
    }
    await t.pump();
    await t.pump();
  }

  String? textOf(WidgetTester t, String key) =>
      t.widget<Text>(find.byKey(Key(key))).data;

  group('USD', () {
    const all = {'DGB': '1000', 'BTC': '0.001', 'LTC': '0.5'};

    testWidgets('the total, and each row with its 24 h change', (t) async {
      prices.emit(
        priced(
          {'DGB': '0.0125', 'BTC': '60000', 'LTC': '80'},
          change: {'DGB': '3.2149', 'BTC': '-1.055'},
        ),
      );
      await pump(t);
      await balances(t, all);
      expect(textOf(t, 'home.total'), r'$112.50');
      expect(find.byKey(const Key('home.total.excludes')), findsNothing);
      expect(textOf(t, 'home.row.DGB.usd'), r'$12.50');
      expect(textOf(t, 'home.row.BTC.usd'), r'$60.00');
      expect(textOf(t, 'home.row.LTC.usd'), r'$40.00');
      expect(textOf(t, 'home.row.DGB.change'), '▲ 3.21%');
      expect(textOf(t, 'home.row.BTC.change'), '▼ 1.06%');
      expect(find.byKey(const Key('home.row.LTC.change')), findsNothing);
      expect(find.byKey(const Key('price.stale')), findsNothing);
      for (final id in [
        'home.total',
        'home.row.DGB.usd',
        'home.row.DGB.change',
      ]) {
        expect(tagged(id), findsOneWidget, reason: id);
      }
    });

    testWidgets('up is green, down is red', (t) async {
      prices.emit(
        priced(
          {'DGB': '0.0125', 'BTC': '60000'},
          change: {'DGB': '1', 'BTC': '-1'},
        ),
      );
      await pump(t);
      await balances(t, all);
      Color? colorOf(String key) =>
          t.widget<Text>(find.byKey(Key(key))).style?.color;
      expect(colorOf('home.row.DGB.change'), const Color(0xFF2E7D32));
      expect(colorOf('home.row.BTC.change'), const Color(0xFFC62828));
    });

    testWidgets('a coin without a price: ≈ total naming it; its row has no '
        r'$', (t) async {
      prices.emit(priced({'DGB': '0.0125', 'LTC': '80'}));
      await pump(t);
      await balances(t, all);
      expect(textOf(t, 'home.total'), r'≈ $52.50');
      expect(textOf(t, 'home.total.excludes'), 'excludes BTC');
      expect(tagged('home.total.excludes'), findsOneWidget);
      expect(find.byKey(const Key('home.row.BTC.usd')), findsNothing);
      expect(textOf(t, 'home.row.BTC.balance'), '0.001');
    });

    testWidgets('a coin with a zero balance needs no price', (t) async {
      prices.emit(priced({'DGB': '0.0125'}));
      await pump(t);
      await balances(t, {'DGB': '1000', 'BTC': '0', 'LTC': '0'});
      expect(textOf(t, 'home.total'), r'$12.50');
    });

    testWidgets('no prices: "Price unavailable"; balances still show', (
      t,
    ) async {
      await pump(t);
      await balances(t, all);
      expect(textOf(t, 'home.total'), 'Price unavailable');
      expect(find.byKey(const Key('home.row.DGB.usd')), findsNothing);
      expect(textOf(t, 'home.row.DGB.balance'), '1000');
    });

    testWidgets('balances still loading: no total yet', (t) async {
      prices.emit(priced({'DGB': '0.0125'}));
      await pump(t);
      expect(textOf(t, 'home.total'), '…');
      expect(find.byKey(const Key('home.total.excludes')), findsNothing);
    });

    testWidgets('stale prices say when they are from', (t) async {
      final at = DateTime.utc(2026, 10, 8, 9, 30);
      prices.emit(priced({'DGB': '0.0125'}, stale: true, at: at));
      await pump(t);
      await balances(t, {'DGB': '1000'});
      expect(
        textOf(t, 'price.stale'),
        'Prices as of ${DateFormat.Hm('en').format(at.toLocal())}',
      );
      expect(tagged('price.stale'), findsOneWidget);
      expect(textOf(t, 'home.row.DGB.usd'), r'$12.50');
    });

    testWidgets('new prices show without a reload', (t) async {
      prices.emit(priced({'DGB': '0.0125'}));
      await pump(t);
      await balances(t, {'DGB': '1000', 'BTC': '0', 'LTC': '0'});
      expect(textOf(t, 'home.total'), r'$12.50');
      prices.emit(priced({'DGB': '0.02'}));
      await t.pump();
      await t.pump();
      expect(textOf(t, 'home.total'), r'$20.00');
      expect(textOf(t, 'home.row.DGB.usd'), r'$20.00');
    });
  });

```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test test/features/wallet/home_page_test.dart
```
Expected: FAIL. The new `USD` group cannot find `home.total` (`Bad state: No element`).

- [ ] **Step 3: Implement**

`app_en.arb` grows at its end in every task that adds strings. The replacement below adds a comma to the current last entry and appends this task's entries.

Edit `app/lib/l10n/arb/app_en.arb` (1 replacement, top to bottom):

**1.** Replace:

```json
  "seedPaste": "Paste",
  "biometricsEnableFailed": "Fingerprint unlock wasn't turned on. You can try again the next time you unlock."
}
```

with:

```json
  "seedPaste": "Paste",
  "biometricsEnableFailed": "Fingerprint unlock wasn't turned on. You can try again the next time you unlock.",
  "homeTotalLabel": "Total value",
  "priceUnavailable": "Price unavailable",
  "priceExcludes": "excludes {tickers}",
  "@priceExcludes": {"placeholders": {"tickers": {"type": "String"}}},
  "pricesAsOf": "Prices as of {time}",
  "@pricesAsOf": {"placeholders": {"time": {"type": "String"}}},
  "usdApprox": "≈ {usd}",
  "@usdApprox": {"placeholders": {"usd": {"type": "String"}}}
}
```

```bash
cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter gen-l10n
```

Create `app/lib/widgets/price_widgets.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/price_service.dart';
import 'package:digibyte_dex/domain/usd_format.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

/// Rebuilds [builder] with the latest prices (M1-D2 spec §3.2).
class PriceBuilder extends StatelessWidget {
  const PriceBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, PriceSnapshot prices) builder;

  @override
  Widget build(BuildContext context) {
    final feed = context.read<PriceFeed>();
    return StreamBuilder<PriceSnapshot>(
      stream: feed.snapshots,
      initialData: feed.current,
      builder: (context, snapshot) =>
          builder(context, snapshot.data ?? feed.current),
    );
  }
}

/// Green up, red down (spec §4.1), readable in both themes.
Color? changeColor(BuildContext context, ChangeDirection direction) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (direction) {
    ChangeDirection.up =>
      dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
    ChangeDirection.down =>
      dark ? const Color(0xFFE57373) : const Color(0xFFC62828),
    ChangeDirection.flat => null,
  };
}

/// A change in percent with its arrow and colour: `▲ 3.21%`.
class ChangeText extends StatelessWidget {
  const ChangeText({required this.id, required this.percent, super.key});

  final String id;
  final Decimal percent;

  @override
  Widget build(BuildContext context) => Tagged(
    id,
    child: Text(
      UsdFormat.change(percent),
      key: Key(id),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: changeColor(context, UsdFormat.direction(percent)),
      ),
    ),
  );
}

/// "Prices as of 14:05" while [prices] are stale; nothing otherwise.
class StaleNote extends StatelessWidget {
  const StaleNote({required this.prices, super.key});

  final PriceSnapshot prices;

  @override
  Widget build(BuildContext context) {
    final at = prices.updatedAt;
    if (!prices.stale || at == null) return const SizedBox.shrink();
    final locale = Localizations.localeOf(context).toString();
    return Tagged(
      'price.stale',
      child: Text(
        context.l10n.pricesAsOf(DateFormat.Hm(locale).format(at.toLocal())),
        key: const Key('price.stale'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
```

Edit `app/lib/features/wallet/view/home_page.dart` (7 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:digibyte_dex/features/wallet/bloc/portfolio_bloc.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
```

with:

```dart
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/price_service.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/price_repository.dart';
import 'package:digibyte_dex/domain/portfolio_value.dart';
import 'package:digibyte_dex/domain/usd_format.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:digibyte_dex/features/wallet/bloc/portfolio_bloc.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/widgets/price_widgets.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
```

**2.** Replace:

```dart

/// The portfolio: DGB, BTC and LTC with activation state and balance.
class HomePage extends StatelessWidget {
```

with:

```dart

/// The portfolio: DGB, BTC and LTC with activation state, balance and
/// USD value, under the portfolio's USD total (M1-D2 spec §4.1).
class HomePage extends StatelessWidget {
```

**3.** Replace:

```dart
          }
          return ListView(
            children: [for (final row in state.rows) _AssetTile(row: row)],
          );
```

with:

```dart
          }
          return PriceBuilder(
            builder: (context, prices) => ListView(
              children: [
                _Total(rows: state.rows, prices: prices),
                for (final row in state.rows)
                  _AssetTile(row: row, quote: prices.quotes[row.ticker]),
              ],
            ),
          );
```

**4.** Replace:

```dart

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.row});

  final PortfolioRow row;

```

with:

```dart

/// The USD total of every listed asset (spec §4.1): exact, "≈" naming
/// what it leaves out, or "Price unavailable"; "Prices as of" when stale.
class _Total extends StatelessWidget {
  const _Total({required this.rows, required this.prices});

  final List<PortfolioRow> rows;
  final PriceSnapshot prices;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context).textTheme;
    final total = PortfolioValue.total(
      balances: {for (final row in rows) row.ticker: row.balance?.total},
      prices: prices.usd,
    );
    final usd = total.usd;
    final loading = rows.every((row) => row.balance == null);
    final String text;
    if (usd == null) {
      text = l10n.priceUnavailable;
    } else if (loading) {
      text = l10n.balanceLoading;
    } else if (total.partial) {
      text = l10n.usdApprox(UsdFormat.value(usd));
    } else {
      text = UsdFormat.value(usd);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.homeTotalLabel, style: theme.bodySmall),
          Tagged(
            'home.total',
            child: Text(
              text,
              key: const Key('home.total'),
              style: theme.headlineSmall,
            ),
          ),
          if (total.partial && !loading)
            Tagged(
              'home.total.excludes',
              child: Text(
                l10n.priceExcludes(total.excluded.join(', ')),
                key: const Key('home.total.excludes'),
                style: theme.bodySmall,
              ),
            ),
          StaleNote(prices: prices),
        ],
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.row, required this.quote});

  final PortfolioRow row;

  /// This asset's price; null without one.
  final PriceQuote? quote;

```

**5.** Replace:

```dart
        children: [
          _Balance(id: id, balance: row.balance),
          Tagged(
```

with:

```dart
        children: [
          _Balance(id: id, balance: row.balance, quote: quote),
          Tagged(
```

**6.** Replace:

```dart
class _Balance extends StatelessWidget {
  const _Balance({required this.id, required this.balance});

  final String id;
  final BalanceView? balance;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final value = balance;
    return Column(
```

with:

```dart
class _Balance extends StatelessWidget {
  const _Balance({
    required this.id,
    required this.balance,
    required this.quote,
  });

  final String id;
  final BalanceView? balance;
  final PriceQuote? quote;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final value = balance;
    final price = quote;
    final change = price?.change24hPct;
    return Column(
```

**7.** Replace:

```dart
        ),
        if (value != null && value.hasLockedFunds)
```

with:

```dart
        ),
        // The USD value and 24 h change on one line, under the balance.
        if (value != null && price != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tagged(
                '$id.usd',
                child: Text(
                  UsdFormat.value(value.total * price.usd),
                  key: Key('$id.usd'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (change != null) ...[
                const SizedBox(width: 6),
                ChangeText(id: '$id.change', percent: change),
              ],
            ],
          ),
        if (value != null && value.hasLockedFunds)
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test test/features/wallet/home_page_test.dart
```
Expected: `+16: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```
Expected: the formatter changes 0 files; `No issues found!`; `+818: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/features/wallet/view/home_page.dart \
  lib/l10n/arb/app_en.arb \
  lib/widgets/price_widgets.dart \
  test/features/wallet/home_page_test.dart
git commit -m "feat(home): USD total and per-coin value with the 24 h change" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 5: Asset detail: the balance in USD, the unit price, and the 24h/7d/30d sparkline

Spec §4.2 and departure 1.
- **Header, under the balance:**
  - `asset.price.value`: the balance in USD, or `Price unavailable`.
  - `asset.price.unit`: `1 DGB = $0.012345` (`UsdFormat.price`).
  - `price.stale` while stale.
- **Chart, under Send and Receive:**
  - Chips `asset.chart.24h`, `asset.chart.7d` (the default) and `asset.chart.30d`.
  - The change over the period (`asset.chart.change`).
  - A grey skeleton while loading (`asset.chart.loading`), then the line (`asset.chart.line`, a `CustomPainter`).
  - On failure, or with fewer than 2 points: `Chart unavailable` (`asset.chart.error`) and Retry (`asset.chart.retry`).
- `PriceChartCubit` lets only the latest tab's answer through, and the service's 10-minute cache makes tab switches cheap.
- History rows are unchanged.

**Files:**
- Create: `app/lib/widgets/sparkline.dart`
- Create: `app/lib/features/asset/bloc/price_chart_cubit.dart`
- Create: `app/lib/features/asset/view/price_chart.dart`
- Modify: `app/lib/features/asset/view/asset_detail_page.dart`
- Modify: `app/lib/l10n/arb/app_en.arb`
- Test (create): `app/test/widgets/sparkline_test.dart`, `app/test/features/asset/price_chart_cubit_test.dart`
- Test (modify): `app/test/features/asset/asset_detail_page_test.dart`

**Interfaces:**
- Consumes:
  - Task 1: `UsdFormat`, `ChangeDirection`.
  - Task 2: `ChartRange`, `PricePoint`, `PriceResult`.
  - Task 3: `PriceFeed.chart`, `PriceSnapshot`.
  - Task 4: `PriceBuilder`, `ChangeText`, `StaleNote`, `changeColor`.
- Produces (`lib/widgets/sparkline.dart`):
  - `List<Offset> sparklineOffsets(List<double> values, Size size)`
  - `class SparklinePainter extends CustomPainter { SparklinePainter({required List<double> values, required Color color}); }`
- Produces (`lib/features/asset/bloc/price_chart_cubit.dart`):
  - `enum ChartStatus { loading, ready, failed }`
  - `class PriceChartState extends Equatable`:
    - `const PriceChartState({ChartRange range = ChartRange.week, ChartStatus status = ChartStatus.loading, List<PricePoint> points = const []})`;
    - `Decimal? get changePct`.
  - `class PriceChartCubit extends Cubit<PriceChartState>`:
    - `PriceChartCubit({required String ticker, required PriceFeed prices})`;
    - `Future<void> start()`, `Future<void> select(ChartRange range)`, `Future<void> retry()`.
- Produces (`lib/features/asset/view/price_chart.dart`): `class PriceChart extends StatelessWidget`, which reads `PriceChartCubit`.
- Produces (ARB): `assetUnitPrice(String ticker, String price)`, `chartRangeDay`, `chartRangeWeek`, `chartRangeMonth`, `chartUnavailable`.

- [ ] **Step 1: Write the failing tests**

Create `app/test/widgets/sparkline_test.dart`:

```dart
import 'package:digibyte_dex/widgets/sparkline.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const size = Size(300, 100);

  test('evenly spaced; lowest at the bottom, highest at the top', () {
    expect(sparklineOffsets([2, 4, 3], size), const [
      Offset(0, 100),
      Offset(150, 0),
      Offset(300, 50),
    ]);
  });

  test('a flat series sits on the middle line', () {
    expect(sparklineOffsets([5, 5], size), const [
      Offset(0, 50),
      Offset(300, 50),
    ]);
  });

  test('fewer than two values, or no room: nothing', () {
    expect(sparklineOffsets([1], size), isEmpty);
    expect(sparklineOffsets([], size), isEmpty);
    expect(sparklineOffsets([1, 2], Size.zero), isEmpty);
  });

  test('repaints only when the line or its colour changes', () {
    const blue = Color(0xFF0066CC);
    final painter = SparklinePainter(values: [1, 2], color: blue);
    expect(
      painter.shouldRepaint(SparklinePainter(values: [1, 2], color: blue)),
      isFalse,
    );
    expect(
      painter.shouldRepaint(SparklinePainter(values: [1, 3], color: blue)),
      isTrue,
    );
    expect(
      painter.shouldRepaint(
        SparklinePainter(values: [1, 2], color: const Color(0xFF000000)),
      ),
      isTrue,
    );
  });

  testWidgets('paints without errors', (t) async {
    await t.pumpWidget(
      Center(
        child: CustomPaint(
          size: size,
          painter: SparklinePainter(
            values: const [1, 3, 2, 5],
            color: const Color(0xFF0066CC),
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
  });
}
```

Create `app/test/features/asset/price_chart_cubit_test.dart`:

```dart
import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/repositories/price_repository.dart';
import 'package:digibyte_dex/features/asset/bloc/price_chart_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_price_feed.dart';

void main() {
  late FakePriceFeed prices;

  final points = [
    PricePoint(DateTime.utc(2026, 10), 0.0125),
    PricePoint(DateTime.utc(2026, 10, 4), 0.012),
    PricePoint(DateTime.utc(2026, 10, 8), 0.01275),
  ];

  setUp(() => prices = FakePriceFeed()..chartResult = PriceOk(points));

  PriceChartCubit build() {
    final cubit = PriceChartCubit(ticker: 'DGB', prices: prices);
    addTearDown(cubit.close);
    return cubit;
  }

  test('starts on 7 days, loading', () async {
    final cubit = build();
    expect(cubit.state.range, ChartRange.week);
    expect(cubit.state.status, ChartStatus.loading);
    await cubit.start();
    expect(prices.chartCalls, [('DGB', ChartRange.week)]);
    expect(cubit.state.status, ChartStatus.ready);
    expect(cubit.state.points, points);
  });

  test('the change over the period, first point to last', () async {
    final cubit = build();
    await cubit.start();
    expect(cubit.state.changePct, Decimal.parse('2'));
  });

  test('a tab loads its range', () async {
    final cubit = build();
    await cubit.start();
    await cubit.select(ChartRange.day);
    expect(cubit.state.range, ChartRange.day);
    await cubit.select(ChartRange.month);
    expect(prices.chartCalls.map((c) => c.$2), [
      ChartRange.week,
      ChartRange.day,
      ChartRange.month,
    ]);
  });

  test(
    'a failure shows "unavailable"; Retry loads the same range again',
    () async {
      prices.chartResult = const PriceError(PriceFailure.network);
      final cubit = build();
      await cubit.select(ChartRange.month);
      expect(cubit.state.status, ChartStatus.failed);
      expect(cubit.state.changePct, isNull);
      prices.chartResult = PriceOk(points);
      await cubit.retry();
      expect(cubit.state.status, ChartStatus.ready);
      expect(prices.chartCalls.last, ('DGB', ChartRange.month));
    },
  );

  test('fewer than two points is no chart', () async {
    prices.chartResult = PriceOk([points.first]);
    final cubit = build();
    await cubit.start();
    expect(cubit.state.status, ChartStatus.failed);
  });

  test('a slower earlier tab never replaces the newer one', () async {
    final cubit = build();
    final slow = prices.chartGate = Completer<void>();
    final week = cubit.start();
    prices
      ..chartGate = null
      ..chartResult = PriceOk(points.sublist(1));
    await cubit.select(ChartRange.day);
    prices.chartResult = PriceOk(points);
    slow.complete();
    await week;
    expect(cubit.state.range, ChartRange.day);
    expect(cubit.state.points, points.sublist(1));
  });

  test('a late answer after close is ignored', () async {
    final cubit = PriceChartCubit(ticker: 'DGB', prices: prices);
    final gate = prices.chartGate = Completer<void>();
    final loading = cubit.start();
    await cubit.close();
    gate.complete();
    await loading;
    expect(cubit.state.status, ChartStatus.loading);
  });
}
```

Edit `app/test/features/asset/asset_detail_page_test.dart` (6 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/features/asset/view/asset_detail_page.dart';
```

with:

```dart
import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/price_service.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/data/repositories/price_repository.dart';
import 'package:digibyte_dex/features/asset/view/asset_detail_page.dart';
```

**2.** Replace:

```dart
import 'package:flutter_test/flutter_test.dart';

import '../../support/capture_debug_print.dart';
import '../../support/fake_assets_repository.dart';
import '../../support/fake_history_repository.dart';
import '../../support/fake_timers.dart';
```

with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../support/capture_debug_print.dart';
import '../../support/fake_assets_repository.dart';
import '../../support/fake_history_repository.dart';
import '../../support/fake_price_feed.dart';
import '../../support/fake_timers.dart';
```

**3.** Replace:

```dart
  late FakeUrlOpener urls;
  late List<String> copied;
```

with:

```dart
  late FakeUrlOpener urls;
  late FakePriceFeed prices;
  late List<String> copied;
```

**4.** Replace:

```dart
    urls = FakeUrlOpener();
    copied = [];
```

with:

```dart
    urls = FakeUrlOpener();
    prices = FakePriceFeed();
    copied = [];
```

**5.** Replace:

```dart
          RepositoryProvider<UrlOpener>.value(value: urls),
          RepositoryProvider.value(value: clipboard),
```

with:

```dart
          RepositoryProvider<UrlOpener>.value(value: urls),
          RepositoryProvider<PriceFeed>.value(value: prices),
          RepositoryProvider.value(value: clipboard),
```

**6.** Replace:

```dart
    expect(find.byKey(const Key('asset.spendable')), findsOneWidget);
  });
```

with:

```dart
    expect(find.byKey(const Key('asset.spendable')), findsOneWidget);
  });

  String? textOf(WidgetTester t, String key) =>
      t.widget<Text>(find.byKey(Key(key))).data;

  Finder tagged(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> balance(WidgetTester t, String total) async {
    assets.emitBalance(
      'DGB',
      BalanceView(total: Decimal.parse(total), spendable: Decimal.parse(total)),
    );
    await t.pump();
    await t.pump();
  }

  group('USD', () {
    testWidgets('the balance in USD and the unit price', (t) async {
      prices.emit(priced({'DGB': '0.012345'}));
      await pump(t);
      await balance(t, '1000');
      expect(textOf(t, 'asset.price.value'), r'$12.35');
      expect(textOf(t, 'asset.price.unit'), r'1 DGB = $0.012345');
      expect(tagged('asset.price.value'), findsOneWidget);
      expect(tagged('asset.price.unit'), findsOneWidget);
      expect(find.byKey(const Key('price.stale')), findsNothing);
    });

    testWidgets('no price: "Price unavailable", no unit price', (t) async {
      await pump(t);
      await balance(t, '1000');
      expect(textOf(t, 'asset.price.value'), 'Price unavailable');
      expect(find.byKey(const Key('asset.price.unit')), findsNothing);
      expect(textOf(t, 'asset.balance'), '1000 DGB');
    });

    testWidgets('stale prices say when they are from', (t) async {
      final at = DateTime.utc(2026, 10, 8, 9, 30);
      prices.emit(priced({'DGB': '0.0125'}, stale: true, at: at));
      await pump(t);
      expect(
        textOf(t, 'price.stale'),
        'Prices as of ${DateFormat.Hm('en').format(at.toLocal())}',
      );
    });
  });

  group('chart', () {
    final points = [
      PricePoint(DateTime.utc(2026, 10), 0.0125),
      PricePoint(DateTime.utc(2026, 10, 8), 0.01275),
    ];

    testWidgets('7 days first: a skeleton, then the line and its change', (
      t,
    ) async {
      prices
        ..chartResult = PriceOk(points)
        ..chartGate = Completer<void>();
      await pump(t);
      expect(find.byKey(const Key('asset.chart.loading')), findsOneWidget);
      expect(prices.chartCalls, [('DGB', ChartRange.week)]);
      final chip = t.widget<ChoiceChip>(
        find.byKey(const Key('asset.chart.7d')),
      );
      expect(chip.selected, isTrue);
      prices.chartGate!.complete();
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('asset.chart.line')), findsOneWidget);
      expect(textOf(t, 'asset.chart.change'), '▲ 2.00%');
      for (final id in [
        'asset.chart.24h',
        'asset.chart.7d',
        'asset.chart.30d',
        'asset.chart.line',
        'asset.chart.change',
      ]) {
        expect(tagged(id), findsOneWidget, reason: id);
      }
    });

    testWidgets('the tabs load 24 hours and 30 days', (t) async {
      prices.chartResult = PriceOk(points);
      await pump(t);
      await tapKey(t, 'asset.chart.24h');
      await t.pump();
      await tapKey(t, 'asset.chart.30d');
      await t.pump();
      expect(prices.chartCalls.map((c) => c.$2), [
        ChartRange.week,
        ChartRange.day,
        ChartRange.month,
      ]);
      expect(
        t.widget<ChoiceChip>(find.byKey(const Key('asset.chart.30d'))).selected,
        isTrue,
      );
    });

    testWidgets('a failure says "Chart unavailable"; Retry tries again', (
      t,
    ) async {
      prices.chartResult = const PriceError(PriceFailure.network);
      await pump(t);
      expect(textOf(t, 'asset.chart.error'), 'Chart unavailable');
      expect(tagged('asset.chart.retry'), findsOneWidget);
      prices.chartResult = PriceOk(points);
      await tapKey(t, 'asset.chart.retry');
      await t.pump();
      expect(find.byKey(const Key('asset.chart.line')), findsOneWidget);
      expect(prices.chartCalls, hasLength(2));
    });
  });
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/widgets/sparkline_test.dart \
  test/features/asset/price_chart_cubit_test.dart \
  test/features/asset/asset_detail_page_test.dart
```
Expected: FAIL to compile: `sparkline.dart` and `price_chart_cubit.dart` are not found. The page test's `USD` and `chart` groups fail.

- [ ] **Step 3: Implement**

Edit `app/lib/l10n/arb/app_en.arb` (1 replacement, top to bottom):

**1.** Replace:

```json
  "usdApprox": "≈ {usd}",
  "@usdApprox": {"placeholders": {"usd": {"type": "String"}}}
}
```

with:

```json
  "usdApprox": "≈ {usd}",
  "@usdApprox": {"placeholders": {"usd": {"type": "String"}}},
  "assetUnitPrice": "1 {ticker} = {price}",
  "@assetUnitPrice": {"placeholders": {"ticker": {"type": "String"}, "price": {"type": "String"}}},
  "chartRangeDay": "24h",
  "chartRangeWeek": "7d",
  "chartRangeMonth": "30d",
  "chartUnavailable": "Chart unavailable"
}
```

```bash
cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter gen-l10n
```

Create `app/lib/widgets/sparkline.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

/// Where each of [values] is drawn in [size]: evenly spaced from left to
/// right, the lowest at the bottom and the highest at the top; a flat
/// series sits on the middle line. Fewer than 2 values draw nothing.
List<Offset> sparklineOffsets(List<double> values, Size size) {
  if (values.length < 2 || size.isEmpty) return const [];
  final low = values.reduce(math.min);
  final high = values.reduce(math.max);
  final span = high - low;
  return [
    for (var i = 0; i < values.length; i++)
      Offset(
        size.width * i / (values.length - 1),
        span == 0
            ? size.height / 2
            : size.height - (values[i] - low) / span * size.height,
      ),
  ];
}

/// A price line without axes (M1-D2 spec §4.2). Display-only, so doubles.
class SparklinePainter extends CustomPainter {
  SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final points = sparklineOffsets(values, size);
    if (points.isEmpty) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(SparklinePainter oldDelegate) =>
      oldDelegate.color != color || !listEquals(oldDelegate.values, values);
}
```

Create `app/lib/features/asset/bloc/price_chart_cubit.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/price_service.dart';
import 'package:digibyte_dex/data/repositories/price_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum ChartStatus { loading, ready, failed }

/// The asset-detail sparkline (M1-D2 spec §4.2).
class PriceChartState extends Equatable {
  const PriceChartState({
    this.range = ChartRange.week,
    this.status = ChartStatus.loading,
    this.points = const [],
  });

  final ChartRange range;
  final ChartStatus status;

  /// Oldest first; at least 2 when [status] is ready.
  final List<PricePoint> points;

  /// The change over [range] in percent, first point to last.
  Decimal? get changePct {
    if (points.length < 2 || points.first.usd <= 0) return null;
    final first = points.first.usd;
    final pct = (points.last.usd - first) / first * 100;
    return Decimal.parse(pct.toStringAsFixed(4));
  }

  @override
  List<Object?> get props => [range, status, points];
}

/// Loads [ticker]'s sparkline for the chosen range; 7 days first.
class PriceChartCubit extends Cubit<PriceChartState> {
  PriceChartCubit({required this.ticker, required PriceFeed prices})
    : _prices = prices,
      super(const PriceChartState());

  final String ticker;
  final PriceFeed _prices;

  /// Only the latest load may set the state.
  int _loads = 0;

  Future<void> start() => select(state.range);

  /// Shows [range]: a skeleton, then its line or "Chart unavailable".
  Future<void> select(ChartRange range) async {
    final load = ++_loads;
    emit(PriceChartState(range: range));
    final result = await _prices.chart(ticker, range);
    if (isClosed || load != _loads) return;
    emit(switch (result) {
      PriceOk(value: final points) when points.length >= 2 => PriceChartState(
        range: range,
        status: ChartStatus.ready,
        points: points,
      ),
      _ => PriceChartState(range: range, status: ChartStatus.failed),
    });
  }

  /// "Chart unavailable" → Retry.
  Future<void> retry() => select(state.range);
}
```

Create `app/lib/features/asset/view/price_chart.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/repositories/price_repository.dart';
import 'package:digibyte_dex/domain/usd_format.dart';
import 'package:digibyte_dex/features/asset/bloc/price_chart_cubit.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/widgets/price_widgets.dart';
import 'package:digibyte_dex/widgets/sparkline.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

extension on ChartRange {
  /// The tab's widget id suffix.
  String get id => switch (this) {
    ChartRange.day => '24h',
    ChartRange.week => '7d',
    ChartRange.month => '30d',
  };

  String label(AppLocalizations l10n) => switch (this) {
    ChartRange.day => l10n.chartRangeDay,
    ChartRange.week => l10n.chartRangeWeek,
    ChartRange.month => l10n.chartRangeMonth,
  };
}

/// The sparkline with its 24h / 7d / 30d tabs and the change over the
/// period (M1-D2 spec §4.2). Reads [PriceChartCubit].
class PriceChart extends StatelessWidget {
  const PriceChart({super.key});

  static const height = 120.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<PriceChartCubit>();
    return BlocBuilder<PriceChartCubit, PriceChartState>(
      builder: (context, state) {
        final change = state.changePct;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final range in ChartRange.values)
                        Tagged(
                          'asset.chart.${range.id}',
                          child: ChoiceChip(
                            key: Key('asset.chart.${range.id}'),
                            label: Text(range.label(l10n)),
                            selected: state.range == range,
                            onSelected: (_) => unawaited(cubit.select(range)),
                          ),
                        ),
                    ],
                  ),
                ),
                if (state.status == ChartStatus.ready && change != null)
                  ChangeText(id: 'asset.chart.change', percent: change),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: height,
              child: switch (state.status) {
                ChartStatus.loading => Tagged(
                  'asset.chart.loading',
                  child: DecoratedBox(
                    key: const Key('asset.chart.loading'),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                ChartStatus.ready => Tagged(
                  'asset.chart.line',
                  child: CustomPaint(
                    key: const Key('asset.chart.line'),
                    size: Size.infinite,
                    painter: SparklinePainter(
                      values: [for (final point in state.points) point.usd],
                      color:
                          changeColor(
                            context,
                            change == null
                                ? ChangeDirection.flat
                                : UsdFormat.direction(change),
                          ) ??
                          Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                ChartStatus.failed => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Tagged(
                      'asset.chart.error',
                      child: Text(
                        l10n.chartUnavailable,
                        key: const Key('asset.chart.error'),
                      ),
                    ),
                    Tagged(
                      'asset.chart.retry',
                      child: TextButton(
                        key: const Key('asset.chart.retry'),
                        onPressed: () => unawaited(cubit.retry()),
                        child: Text(l10n.retry),
                      ),
                    ),
                  ],
                ),
              },
            ),
          ],
        );
      },
    );
  }
}
```

Edit `app/lib/features/asset/view/asset_detail_page.dart` (4 replacements, top to bottom):

**1.** Replace:

```dart
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
```

with:

```dart
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/price_service.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/history_repository.dart';
import 'package:digibyte_dex/domain/usd_format.dart';
import 'package:digibyte_dex/features/asset/bloc/asset_history_cubit.dart';
import 'package:digibyte_dex/features/asset/bloc/price_chart_cubit.dart';
import 'package:digibyte_dex/features/asset/view/price_chart.dart';
import 'package:digibyte_dex/features/asset/view/tx_detail_sheet.dart';
import 'package:digibyte_dex/l10n/history_messages.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/widgets/price_widgets.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// One listed asset: balance and its USD value, the price and its
/// sparkline, Send and Receive, and history (spec §4; M1-D2 spec §4.2).
class AssetDetailPage extends StatelessWidget {
```

**2.** Replace:

```dart
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
```

with:

```dart
  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (context) {
          final cubit = AssetHistoryCubit(
            ticker: ticker,
            assets: context.read<AssetsRepository>(),
            history: context.read<HistoryRepository>(),
          );
          unawaited(cubit.start());
          return cubit;
        },
      ),
      BlocProvider(
        create: (context) {
          final cubit = PriceChartCubit(
            ticker: ticker,
            prices: context.read<PriceFeed>(),
          );
          unawaited(cubit.start());
          return cubit;
        },
      ),
    ],
    child: _AssetDetailView(ticker: ticker),
```

**3.** Replace:

```dart
            ),
          const SizedBox(height: 16),
```

with:

```dart
            ),
          PriceBuilder(
            builder: (context, prices) =>
                _Prices(ticker: ticker, balance: balance, prices: prices),
          ),
          const SizedBox(height: 16),
```

**4.** Replace:

```dart
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
```

with:

```dart
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const PriceChart(),
        ],
      ),
    );
  }
}

/// The balance in USD and the unit price (M1-D2 spec §4.2).
class _Prices extends StatelessWidget {
  const _Prices({
    required this.ticker,
    required this.balance,
    required this.prices,
  });

  final String ticker;
  final BalanceView? balance;
  final PriceSnapshot prices;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final quote = prices.quotes[ticker];
    final total = balance?.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tagged(
          'asset.price.value',
          child: Text(
            quote == null
                ? l10n.priceUnavailable
                : total == null
                ? l10n.balanceLoading
                : UsdFormat.value(total * quote.usd),
            key: const Key('asset.price.value'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (quote != null)
          Tagged(
            'asset.price.unit',
            child: Text(
              l10n.assetUnitPrice(ticker, UsdFormat.price(quote.usd)),
              key: const Key('asset.price.unit'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        StaleNote(prices: prices),
      ],
    );
  }
}

class _TxRow extends StatelessWidget {
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/widgets/sparkline_test.dart \
  test/features/asset/price_chart_cubit_test.dart \
  test/features/asset/asset_detail_page_test.dart
```
Expected: `+31: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```
Expected: the formatter changes 0 files; `No issues found!`; `+836: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/features/asset/bloc/price_chart_cubit.dart \
  lib/features/asset/view/asset_detail_page.dart \
  lib/features/asset/view/price_chart.dart \
  lib/l10n/arb/app_en.arb \
  lib/widgets/sparkline.dart \
  test/features/asset/asset_detail_page_test.dart \
  test/features/asset/price_chart_cubit_test.dart \
  test/widgets/sparkline_test.dart
git commit -m "feat(asset): USD value, unit price and a 24h/7d/30d sparkline" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 6: Send: "≈ $" under the amount, and by the amount, fee and total on Confirm

Spec §4.3 and departure 6.
- **Form:** `send.usd` shows `≈ $1.25` under the amount field, as the user types. It appears only when `SendRules.parseAmount` accepts the text, the amount is above zero, and the coin has a price.
- **Confirm:** it adds `confirm.usd.amount`, `confirm.usd.fee` and `confirm.usd.total` under the three values, which come from the signed preview.
- **Display-only:** `UsdApprox` reads only a coin amount and the price. Nothing it shows reaches `SendCubit`, the preview or a check.

**Files:**
- Modify: `app/lib/widgets/price_widgets.dart` (`UsdApprox`)
- Modify: `app/lib/features/send/view/send_form_view.dart`
- Modify: `app/lib/features/send/view/send_confirm_view.dart`
- Test (modify): `app/test/features/send/send_page_test.dart`

**Interfaces:**
- Consumes:
  - Task 1: `UsdFormat.value`.
  - Task 4: `PriceBuilder` and `usdApprox` (ARB).
  - Existing: `SendRules.parseAmount`, `SendPreview.amount` / `fee` / `total`.
- Produces (`lib/widgets/price_widgets.dart`): `class UsdApprox extends StatelessWidget { const UsdApprox({required String id, required String ticker, required Decimal? amount}); }`.
- `SendPage` now reads `PriceFeed` from the tree (provided by `AppScope`; `send_page_test.dart` provides a `FakePriceFeed`).

- [ ] **Step 1: Write the failing tests**

Edit `app/test/features/send/send_page_test.dart` (6 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
```

with:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/price_service.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
```

**2.** Replace:

```dart
import '../../support/fake_history_repository.dart';
import '../../support/fake_qr_scanner.dart';
```

with:

```dart
import '../../support/fake_history_repository.dart';
import '../../support/fake_price_feed.dart';
import '../../support/fake_qr_scanner.dart';
```

**3.** Replace:

```dart
  late FakeQrScanner scanner;
  late InMemoryKeyValueStore storage;
```

with:

```dart
  late FakeQrScanner scanner;
  late FakePriceFeed prices;
  late InMemoryKeyValueStore storage;
```

**4.** Replace:

```dart
    scanner = FakeQrScanner();
    storage = InMemoryKeyValueStore();
```

with:

```dart
    scanner = FakeQrScanner();
    prices = FakePriceFeed();
    storage = InMemoryKeyValueStore();
```

**5.** Replace:

```dart
          RepositoryProvider<QrScanner>.value(value: scanner),
          RepositoryProvider.value(value: clipboard),
```

with:

```dart
          RepositoryProvider<QrScanner>.value(value: scanner),
          RepositoryProvider<PriceFeed>.value(value: prices),
          RepositoryProvider.value(value: clipboard),
```

**6.** Replace:

```dart
    await t.pump();
  }

  group('form', () {
```

with:

```dart
    await t.pump();
  }

  group('USD', () {
    String? usdOf(WidgetTester t, String key) {
      final found = find.byKey(Key(key));
      return found.evaluate().isEmpty ? null : t.widget<Text>(found).data;
    }

    testWidgets(r'the form shows "≈ $" as the amount is typed', (t) async {
      prices.emit(priced({'DGB': '0.0125'}));
      await pump(t);
      expect(usdOf(t, 'send.usd'), isNull);
      await enterKey(t, 'send.amount', '100');
      expect(usdOf(t, 'send.usd'), r'≈ $1.25');
      await enterKey(t, 'send.amount', '1000.5');
      expect(usdOf(t, 'send.usd'), r'≈ $12.51');
      final tag = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.identifier == 'send.usd',
      );
      expect(tag, findsOneWidget);
    });

    testWidgets(r'no "≈ $" for an amount that does not parse, or zero', (
      t,
    ) async {
      prices.emit(priced({'DGB': '0.0125'}));
      await pump(t);
      for (final text in ['1,5', '1.123456789', 'abc', '0', '']) {
        await enterKey(t, 'send.amount', text);
        expect(usdOf(t, 'send.usd'), isNull, reason: text);
      }
    });

    testWidgets(r'no "≈ $" without a price', (t) async {
      prices.emit(priced({'BTC': '60000'}));
      await pump(t);
      await enterKey(t, 'send.amount', '100');
      expect(usdOf(t, 'send.usd'), isNull);
    });

    testWidgets(r'Confirm shows "≈ $" by the amount, the fee and the total', (
      t,
    ) async {
      prices.emit(priced({'DGB': '2'}));
      await pump(t);
      await toConfirm(t);
      expect(usdOf(t, 'confirm.usd.amount'), r'≈ $2.00');
      expect(usdOf(t, 'confirm.usd.fee'), r'≈ $0.05');
      expect(usdOf(t, 'confirm.usd.total'), r'≈ $2.05');
      expect(usdOf(t, 'confirm.amount'), '1 DGB');
    });

    testWidgets(r'Confirm without a price has no "≈ $"', (t) async {
      await pump(t);
      await toConfirm(t);
      expect(usdOf(t, 'confirm.usd.amount'), isNull);
      expect(usdOf(t, 'confirm.usd.fee'), isNull);
      expect(usdOf(t, 'confirm.usd.total'), isNull);
    });

    testWidgets('USD never changes what is sent, even when the price moves', (
      t,
    ) async {
      prices.emit(priced({'DGB': '0.5'}));
      await pump(t);
      await address(t, _other);
      await enterKey(t, 'send.amount', '5');
      prices.emit(priced({'DGB': '0.8'}));
      await t.pump();
      await t.pump();
      expect(usdOf(t, 'send.usd'), r'≈ $4.00');
      await tapKey(t, 'send.next');
      await t.pump();
      await t.pump();
      expect(send.requests.single.amount, Decimal.parse('5'));
      expect(usdOf(t, 'confirm.amount'), '5 DGB');
      prices.emit(priced({'DGB': '1.2'}));
      await t.pump();
      await t.pump();
      expect(usdOf(t, 'confirm.amount'), '5 DGB');
      expect(usdOf(t, 'confirm.usd.amount'), r'≈ $6.00');
    });
  });

  group('form', () {
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test test/features/send/send_page_test.dart
```
Expected: FAIL. The `USD` group finds no `send.usd` or `confirm.usd.*` (`Expected: '≈ $1.25' Actual: <null>`).

- [ ] **Step 3: Implement**

Edit `app/lib/widgets/price_widgets.dart` (1 replacement, top to bottom):

**1.** Replace:

```dart

/// "Prices as of 14:05" while [prices] are stale; nothing otherwise.
```

with:

```dart

/// "≈ $12.50" for [amount] of [ticker] (M1-D2 spec §4.3). Display-only:
/// it never feeds an amount, a fee or a check. Nothing without a price,
/// or for an amount that is missing or not above zero.
class UsdApprox extends StatelessWidget {
  const UsdApprox({
    required this.id,
    required this.ticker,
    required this.amount,
    super.key,
  });

  final String id;
  final String ticker;
  final Decimal? amount;

  @override
  Widget build(BuildContext context) => PriceBuilder(
    builder: (context, prices) {
      final value = amount;
      final quote = prices.quotes[ticker];
      if (value == null || value <= Decimal.zero || quote == null) {
        return const SizedBox.shrink();
      }
      return Tagged(
        id,
        child: Text(
          context.l10n.usdApprox(UsdFormat.value(value * quote.usd)),
          key: Key(id),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    },
  );
}

/// "Prices as of 14:05" while [prices] are stale; nothing otherwise.
```

Edit `app/lib/features/send/view/send_form_view.dart` (3 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/features/send/bloc/send_cubit.dart';
```

with:

```dart
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/domain/send_rules.dart';
import 'package:digibyte_dex/features/send/bloc/send_cubit.dart';
```

**2.** Replace:

```dart
import 'package:digibyte_dex/widgets/busy_indicator.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// The send form (spec §3.2): address, amount with Max, Next.
class SendFormView extends StatefulWidget {
```

with:

```dart
import 'package:digibyte_dex/widgets/busy_indicator.dart';
import 'package:digibyte_dex/widgets/price_widgets.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// The send form (spec §3.2): address, amount with Max and its "≈ $"
/// (M1-D2 spec §4.3), Next.
class SendFormView extends StatefulWidget {
```

**3.** Replace:

```dart
                ),
                if (state.amountDropped) ...[
```

with:

```dart
                ),
                // Display-only: the amount sent is the coin amount above.
                UsdApprox(
                  id: 'send.usd',
                  ticker: state.ticker,
                  amount: SendRules.parseAmount(state.amount),
                ),
                if (state.amountDropped) ...[
```

Edit `app/lib/features/send/view/send_confirm_view.dart` (2 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/widgets/labeled_value.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Confirm (spec §3.4): every number from the signed preview, the
/// address-safety warnings with their acknowledgement, and
/// re-authentication on every send.
class SendConfirmView extends StatelessWidget {
```

with:

```dart
import 'package:digibyte_dex/widgets/labeled_value.dart';
import 'package:digibyte_dex/widgets/price_widgets.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Confirm (spec §3.4): every number from the signed preview, each with
/// its display-only "≈ $" (M1-D2 spec §4.3), the address-safety warnings
/// with their acknowledgement, and re-authentication on every send.
class SendConfirmView extends StatelessWidget {
```

**2.** Replace:

```dart
                ),
                LabeledValue(
                  id: 'confirm.fee',
                  label: l10n.confirmFee,
                  value: '${preview.fee} $ticker',
                ),
                LabeledValue(
                  id: 'confirm.total',
                  label: l10n.confirmTotal,
                  value: '${preview.total} $ticker',
                ),
```

with:

```dart
                ),
                UsdApprox(
                  id: 'confirm.usd.amount',
                  ticker: ticker,
                  amount: preview.amount,
                ),
                LabeledValue(
                  id: 'confirm.fee',
                  label: l10n.confirmFee,
                  value: '${preview.fee} $ticker',
                ),
                UsdApprox(
                  id: 'confirm.usd.fee',
                  ticker: ticker,
                  amount: preview.fee,
                ),
                LabeledValue(
                  id: 'confirm.total',
                  label: l10n.confirmTotal,
                  value: '${preview.total} $ticker',
                ),
                UsdApprox(
                  id: 'confirm.usd.total',
                  ticker: ticker,
                  amount: preview.total,
                ),
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test test/features/send/send_page_test.dart
```
Expected: `+34: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```
Expected: the formatter changes 0 files; `No issues found!`; `+842: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/features/send/view/send_confirm_view.dart \
  lib/features/send/view/send_form_view.dart \
  lib/widgets/price_widgets.dart \
  test/features/send/send_page_test.dart
git commit -m "feat(send): display-only ≈ USD on the form and on Confirm" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 7: R3-1: a mempool receive shows "Pending", never "Dec 31, 1969"

Spec §6.1 and departure 7. KDF reports a received transaction that is still in the mempool at Unix time 0. West of UTC, the row and the sheet showed "Dec 31, 1969 18:00".
- `TxView.timestamp` becomes `DateTime?`, and `txViewOf` maps through `knownTime`, which treats anything before 2009-01-03 as null.
- `localTime` returns null for an unknown time.
- The row shows only its status ("Pending").
- The sheet's date shows "Pending".
- Sorting puts an unknown time first among pending rows.
- Once mined, the SDK reports the block time and the row shows it.

**Files:**
- Modify: `app/lib/data/repositories/history_repository.dart`
- Modify: `app/lib/l10n/history_messages.dart`
- Modify: `app/lib/features/asset/view/asset_detail_page.dart`
- Modify: `app/lib/features/asset/view/tx_detail_sheet.dart`
- Test (modify): `app/test/support/tx_views.dart`, `app/test/data/repositories/sdk_history_repository_test.dart`, `app/test/features/asset/asset_detail_page_test.dart`

**Interfaces:**
- Consumes: existing `TxView`, `txViewOf`, `TxViewText`, and `l10n.txPending`.
- Produces:
  - `TxView.timestamp` is now `DateTime?`.
  - `DateTime? knownTime(DateTime time)` (`history_repository.dart`).
  - `String? TxViewText.localTime(String locale)`.
  - `txView(..., bool unknownTime = false)` (test helper).

- [ ] **Step 1: Write the failing tests**

Edit `app/test/support/tx_views.dart` (3 replacements, top to bottom):

**1.** Replace:

```dart

/// A history row for tests. Addresses are dummies.
TxView txView(
```

with:

```dart

/// A history row for tests. Addresses are dummies. [unknownTime] is a
/// receive still in the mempool, whose time KDF does not know.
TxView txView(
```

**2.** Replace:

```dart
  int confirmations = 10,
  List<String> counterparties = const ['DThem0000000000000000000000000000'],
```

with:

```dart
  int confirmations = 10,
  bool unknownTime = false,
  List<String> counterparties = const ['DThem0000000000000000000000000000'],
```

**3.** Replace:

```dart
  fee: fee == null ? null : Decimal.parse(fee),
  timestamp: DateTime.utc(2026, 10, 2).subtract(Duration(minutes: n)),
  confirmations: confirmations,
```

with:

```dart
  fee: fee == null ? null : Decimal.parse(fee),
  timestamp: unknownTime
      ? null
      : DateTime.utc(2026, 10, 2).subtract(Duration(minutes: n)),
  confirmations: confirmations,
```

Edit `app/test/data/repositories/sdk_history_repository_test.dart` (2 replacements, top to bottom):

**1.** Replace:

```dart

    test('a view never prints its addresses', () {
```

with:

```dart

    test('a mempool receive at Unix time 0 has no time (R3-1)', () {
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      final view = txViewOf(
        _tx(id: '11', net: '1', confirmations: 0, at: epoch),
        own,
      );
      expect(view.timestamp, isNull);
      expect(view.localTime('en'), isNull);
      // Read back from storage in another time zone.
      expect(knownTime(DateTime.utc(1970, 1, 1, 6)), isNull);
      expect(knownTime(DateTime.utc(1969, 12, 31, 18)), isNull);
    });

    test('a real time is kept, and shows once mined', () {
      final mined = DateTime.utc(2026, 10, 7, 14, 5);
      final view = txViewOf(_tx(id: '12', net: '1', at: mined), own);
      expect(view.timestamp, mined);
      expect(knownTime(DateTime.utc(2009, 1, 3)), DateTime.utc(2009, 1, 3));
    });

    test('a view never prints its addresses', () {
```

**2.** Replace:

```dart
      'internal-old',
    ]);
```

with:

```dart
      'internal-old',
    ]);
  });

  test('a pending receive without a time sorts first', () async {
    final lists = <List<TxView>>[];
    final sub = build().watch('DGB').listen(lists.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    feed.add([
      _tx(id: 'mined', net: '1', at: DateTime.utc(2026, 9)),
      _tx(
        id: 'sent',
        net: '-1',
        confirmations: 0,
        at: DateTime.utc(2026, 10),
      ),
      _tx(
        id: 'mempool',
        net: '1',
        confirmations: 0,
        at: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ]);
    await pumpEventQueue();
    expect(lists.single.map((v) => v.id), [
      'internal-mempool',
      'internal-sent',
      'internal-mined',
    ]);
```

Edit `app/test/features/asset/asset_detail_page_test.dart` (1 replacement, top to bottom):

**1.** Replace:

```dart

  testWidgets('scrolling to the end loads the next page', (t) async {
```

with:

```dart

  testWidgets('a mempool receive shows "Pending" and no 1969 date (R3-1)', (
    t,
  ) async {
    await pump(t);
    await show(t, [txView(1, confirmations: 0, unknownTime: true)]);
    final row = find.byKey(const Key('asset.tx.0'));
    expect(
      find.descendant(of: row, matching: find.text('Pending')),
      findsOneWidget,
    );
    expect(find.textContaining('1969'), findsNothing);
    expect(find.textContaining('1970'), findsNothing);
    await tapKey(t, 'asset.tx.0');
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('tx.date'))).data, 'Pending');
    expect(find.textContaining('1969'), findsNothing);
  });

  testWidgets('once mined, the row shows its time', (t) async {
    await pump(t);
    await show(t, [txView(1)]);
    final row = find.byKey(const Key('asset.tx.0'));
    expect(
      find.descendant(of: row, matching: find.textContaining('2026')),
      findsOneWidget,
    );
  });

  testWidgets('scrolling to the end loads the next page', (t) async {
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/data/repositories/sdk_history_repository_test.dart \
  test/features/asset/asset_detail_page_test.dart
```
Expected: FAIL to compile. `tx_views.dart` passes `null` to the non-nullable `timestamp`, and `knownTime` is not defined.

- [ ] **Step 3: Implement**

Edit `app/lib/data/repositories/history_repository.dart` (4 replacements, top to bottom):

**1.** Replace:

```dart
  final Decimal? fee;
  final DateTime timestamp;
  final int confirmations;
```

with:

```dart
  final Decimal? fee;

  /// When it happened; null while unknown (an unmined receive, see
  /// [knownTime]).
  final DateTime? timestamp;
  final int confirmations;
```

**2.** Replace:

```dart
  bool? get stringify => false;
}

/// Maps an SDK [Transaction] to a [TxView] (spec §4): received when the
```

with:

```dart
  bool? get stringify => false;
}

/// The first Bitcoin block (2009-01-03): no DGB, BTC or LTC transaction
/// is older.
final _firstBlock = DateTime.utc(2009, 1, 3);

/// [time], or null when it is no real time. KDF reports a received
/// transaction still in the mempool at Unix time 0, which showed as
/// "Dec 31, 1969" (M1-D2 spec §6, R3-1). Anything before the first
/// Bitcoin block counts as unknown, so 0 read back from storage in
/// another time zone is caught too.
DateTime? knownTime(DateTime time) => time.isBefore(_firstBlock) ? null : time;

/// Maps an SDK [Transaction] to a [TxView] (spec §4): received when the
```

**3.** Replace:

```dart
    fee: fee,
    timestamp: tx.timestamp,
    // Without a block there are no confirmations. KDF reports the chain
```

with:

```dart
    fee: fee,
    timestamp: knownTime(tx.timestamp),
    // Without a block there are no confirmations. KDF reports the chain
```

**4.** Replace:

```dart

/// Pending first, then newest first.
int _newestFirst(TxView a, TxView b) {
  if (a.pending != b.pending) return a.pending ? -1 : 1;
  return b.timestamp.compareTo(a.timestamp);
}
```

with:

```dart

/// Pending first, then newest first; an unknown time counts as newest.
int _newestFirst(TxView a, TxView b) {
  if (a.pending != b.pending) return a.pending ? -1 : 1;
  final (at, bt) = (a.timestamp, b.timestamp);
  if (at == null || bt == null) {
    return at == bt ? 0 : (at == null ? -1 : 1);
  }
  return bt.compareTo(at);
}
```

Edit `app/lib/l10n/history_messages.dart` (1 replacement, top to bottom):

**1.** Replace:

```dart

  /// Local date and time, e.g. `Oct 4, 2026 14:05`.
  String localTime(String locale) =>
      DateFormat.yMMMd(locale).add_Hm().format(timestamp.toLocal());
}
```

with:

```dart

  /// Local date and time, e.g. `Oct 4, 2026 14:05`; null while the time
  /// is unknown (an unmined receive).
  String? localTime(String locale) {
    final at = timestamp;
    return at == null
        ? null
        : DateFormat.yMMMd(locale).add_Hm().format(at.toLocal());
  }
}
```

Edit `app/lib/features/asset/view/asset_detail_page.dart` (1 replacement, top to bottom):

**1.** Replace:

```dart
        title: Text(tx.directionLabel(l10n)),
        subtitle: Text(
          '${tx.localTime(locale)} · ${tx.status(l10n, required)}',
        ),
```

with:

```dart
        title: Text(tx.directionLabel(l10n)),
        // No date while the time is unknown: just "Pending".
        subtitle: Text(
          [
            tx.localTime(locale),
            tx.status(l10n, required),
          ].nonNulls.join(' · '),
        ),
```

Edit `app/lib/features/asset/view/tx_detail_sheet.dart` (1 replacement, top to bottom):

**1.** Replace:

```dart
            label: l10n.txDateLabel,
            value: tx.localTime(locale),
          ),
```

with:

```dart
            label: l10n.txDateLabel,
            value: tx.localTime(locale) ?? l10n.txPending,
          ),
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/data/repositories/sdk_history_repository_test.dart \
  test/features/asset/asset_detail_page_test.dart
```
Expected: `+45: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```
Expected: the formatter changes 0 files; `No issues found!`; `+847: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/data/repositories/history_repository.dart \
  lib/features/asset/view/asset_detail_page.dart \
  lib/features/asset/view/tx_detail_sheet.dart \
  lib/l10n/history_messages.dart \
  test/data/repositories/sdk_history_repository_test.dart \
  test/features/asset/asset_detail_page_test.dart \
  test/support/tx_views.dart
git commit -m "fix(history): an unmined receive shows Pending, not Dec 31, 1969" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 8: R3-2: "Use password" on the fingerprint prompt answers within about 1 s

Spec §6.2.

**What it builds on:** M1-D1 Task 13b (commits `42bf8df`, `cf5d645`, `87461dc` and `646b62a`) found two behaviours, recorded in `biometric_store.dart`:
- flutter_secure_storage 10.3.4 never answers a call whose Keystore prompt is closed with the negative "Use password" button. Its negative-button listener only cancels the prompt, and Android reports `onDialogDismissed` (reason negative) instead of `onAuthenticationError`.
- `_prompting` therefore gives up after `promptTimeout` (30 s), and `_removeLateWrite` deletes a password that a late touch stored after the user was told biometrics are off.

**What this task adds:** the Android system prompt covers the app, which goes inactive, and closing it brings the app back to resumed. `_prompting` therefore also listens to the app lifecycle.
- If the app leaves resumed and comes back while the call is pending, a 1 s grace timer starts (`resumeGrace`).
- When the grace runs out with no answer, the call fails with `TimeoutException`, exactly like the 30 s timeout, so every existing caller path applies unchanged:
  - `enable` returns false and schedules `_removeLateWrite`, so `BiometricOptIn` shows the "wasn't turned on" notice at once;
  - `read` returns null, so the password field is offered at once.
- An answer within the grace wins.
- Being covered again during the grace (the prompt shown again) restarts the watch.
- A resume without a prior leave (for example, local_auth's own prompt closing before this call began) is ignored.
- The 30 s timeout and the late-write cleanup stay as backstops.
- iOS is untouched.
- The lifecycle reaches the store through `appLifecycleChanges()` (`lib/platform/app_lifecycle.dart`), which `main.dart` creates once.

**Files:**
- Create: `app/lib/platform/app_lifecycle.dart`
- Modify: `app/lib/data/biometrics/biometric_store.dart`
- Modify: `app/lib/main.dart`
- Test (create): `app/test/platform/app_lifecycle_test.dart`
- Test (modify): `app/test/data/biometrics/device_biometric_store_test.dart`

**Interfaces:**
- Consumes: the existing `DeviceBiometricStore` internals (`_prompting`, `_removeLateWrite`, `promptTimeout`, `TimerFactory`), plus `BiometricOptIn` and `PasswordGate`, which are unchanged.
- Produces:
  - The `DeviceBiometricStore(...)` constructor gains `Stream<AppLifecycleState>? lifecycle`, defaulting to `const Stream.empty()`.
  - `static const resumeGrace = Duration(seconds: 1)`.
  - `Stream<AppLifecycleState> appLifecycleChanges()`.
  - The new log line `Biometric prompt closed without an answer`.

- [ ] **Step 1: Write the failing tests**

Create `app/test/platform/app_lifecycle_test.dart`:

```dart
import 'package:digibyte_dex/platform/app_lifecycle.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('streams the app lifecycle, inactive included', (t) async {
    final seen = <AppLifecycleState>[];
    final sub = appLifecycleChanges().listen(seen.add);
    addTearDown(sub.cancel);
    t.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(seen, [AppLifecycleState.inactive, AppLifecycleState.resumed]);
  });
}
```

Edit `app/test/data/biometrics/device_biometric_store_test.dart` (5 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
```

with:

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
```

**2.** Replace:

```dart
  late FakeTimers timers;

```

with:

```dart
  late FakeTimers timers;
  late StreamController<AppLifecycleState> lifecycle;

```

**3.** Replace:

```dart
    timers = FakeTimers();
    when(
```

with:

```dart
    timers = FakeTimers();
    lifecycle = StreamController<AppLifecycleState>.broadcast(sync: true);
    addTearDown(lifecycle.close);
    when(
```

**4.** Replace:

```dart
    timer: timers.create,
  );
```

with:

```dart
    timer: timers.create,
    lifecycle: lifecycle.stream,
  );
```

**5.** Replace:

```dart
      verifyNever(() => storage.delete(key: any(named: 'key')));
      expect(await store.isEnabled('w'), isFalse);
      expect(logs, ['Biometric prompt timed out']);
    });

    test('iOS: the Keychain reports its cancels, so no timeout', () async {
```

with:

```dart
      verifyNever(() => storage.delete(key: any(named: 'key')));
      expect(await store.isEnabled('w'), isFalse);
      expect(logs, ['Biometric prompt timed out']);
    });

    group('"Use password": back in front with no answer (R3-2)', () {
      /// The system prompt covers the app, then goes away.
      void promptShownAndClosed() => lifecycle
        ..add(AppLifecycleState.inactive)
        ..add(AppLifecycleState.resumed);

      FakeTimer graceTimer() => timers.pending.singleWhere(
        (t) => t.duration == DeviceBiometricStore.resumeGrace,
      );

      test('the grace is 1 s', () {
        expect(DeviceBiometricStore.resumeGrace, const Duration(seconds: 1));
      });

      test('enable: refused 1 s after the resume, the 30 s timer '
          'cancelled', () async {
        final logs = captureDebugPrint();
        final store = build();
        final result = store.enable('w', 'pw-1');
        await pumpEventQueue();
        promptShownAndClosed();
        graceTimer().fire();
        expect(await result, isFalse);
        expect(await store.isEnabled('w'), isFalse);
        expect(timers.pending, isEmpty);
        expect(lifecycle.hasListener, isFalse);
        expect(logs, ['Biometric prompt closed without an answer']);
      });

      test(
        'first read: a cancel 1 s after the resume; the entry is kept',
        () async {
          captureDebugPrint();
          await enabled('w');
          final store = build();
          final result = store.read('w', reason: 'why');
          await pumpEventQueue();
          promptShownAndClosed();
          graceTimer().fire();
          expect(await result, isNull);
          expect(await store.isEnabled('w'), isTrue);
          verifyNever(() => storage.delete(key: any(named: 'key')));
        },
      );

      test('an answer within the grace wins', () async {
        final logs = captureDebugPrint();
        final store = build();
        final result = store.enable('w', 'pw-1');
        await pumpEventQueue();
        promptShownAndClosed();
        final grace = graceTimer();
        write.complete();
        expect(await result, isTrue);
        expect(grace.isActive, isFalse);
        expect(timers.pending, isEmpty);
        expect(await store.isEnabled('w'), isTrue);
        expect(logs, isEmpty);
      });

      test('a late write after the resume-cancel is removed', () async {
        final logs = captureDebugPrint();
        final store = build();
        final result = store.enable('w', 'pw-1');
        await pumpEventQueue();
        promptShownAndClosed();
        graceTimer().fire();
        expect(await result, isFalse);
        write.complete();
        await pumpEventQueue();
        verify(() => storage.delete(key: 'bio_pw_w')).called(1);
        expect(await store.isEnabled('w'), isFalse);
        expect(logs, [
          'Biometric prompt closed without an answer',
          'Biometric late write removed',
        ]);
      });

      test('a late read answer after the resume-cancel is dropped', () async {
        captureDebugPrint();
        await enabled('w');
        final store = build();
        final result = store.read('w', reason: 'why');
        await pumpEventQueue();
        promptShownAndClosed();
        graceTimer().fire();
        expect(await result, isNull);
        read.complete('pw-1');
        await pumpEventQueue();
        expect(await store.isEnabled('w'), isTrue);
      });

      test('a resume without leaving first is not a dismissal', () async {
        final store = build();
        final result = store.enable('w', 'pw-1');
        await pumpEventQueue();
        lifecycle.add(AppLifecycleState.resumed);
        expect(timers.pending.single.duration, const Duration(seconds: 30));
        write.complete();
        expect(await result, isTrue);
      });

      test('covered again during the grace: the watch starts over', () async {
        captureDebugPrint();
        final store = build();
        final result = store.enable('w', 'pw-1');
        await pumpEventQueue();
        promptShownAndClosed();
        final first = graceTimer();
        lifecycle.add(AppLifecycleState.inactive);
        expect(first.isActive, isFalse);
        lifecycle.add(AppLifecycleState.resumed);
        graceTimer().fire();
        expect(await result, isFalse);
      });

      test('the background and back counts too', () async {
        captureDebugPrint();
        final store = build();
        final result = store.enable('w', 'pw-1');
        await pumpEventQueue();
        lifecycle
          ..add(AppLifecycleState.inactive)
          ..add(AppLifecycleState.hidden)
          ..add(AppLifecycleState.paused)
          ..add(AppLifecycleState.hidden)
          ..add(AppLifecycleState.inactive)
          ..add(AppLifecycleState.resumed);
        graceTimer().fire();
        expect(await result, isFalse);
      });

      test('iOS ignores the lifecycle', () async {
        final store = build(isAndroid: false);
        final result = store.enable('w', 'pw-1');
        await pumpEventQueue();
        promptShownAndClosed();
        expect(timers.created, isEmpty);
        write.complete();
        expect(await result, isTrue);
      });
    });

    test('iOS: the Keychain reports its cancels, so no timeout', () async {
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/data/biometrics/device_biometric_store_test.dart \
  test/platform/app_lifecycle_test.dart
```
Expected: FAIL to compile: `No named parameter with the name 'lifecycle'`, `Member not found: 'resumeGrace'`, and `app_lifecycle.dart` not found.

- [ ] **Step 3: Implement**

Create `app/lib/platform/app_lifecycle.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';

/// Every app lifecycle change from now on, for services outside the
/// widget tree (the biometric prompt watch, M1-D2 spec §6 R3-2). Its
/// listener lives as long as the process: call this once, from `main`.
Stream<AppLifecycleState> appLifecycleChanges() {
  final changes = StreamController<AppLifecycleState>.broadcast();
  AppLifecycleListener(onStateChange: changes.add);
  return changes.stream;
}
```

Edit `app/lib/data/biometrics/biometric_store.dart` (8 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
```

with:

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
```

**2.** Replace:

```dart
    TimerFactory? timer,
  }) : _markers = markers,
```

with:

```dart
    TimerFactory? timer,
    Stream<AppLifecycleState>? lifecycle,
  }) : _markers = markers,
```

**3.** Replace:

```dart
       _isAndroid = isAndroid ?? Platform.isAndroid,
       _timer = timer ?? Timer.new;

```

with:

```dart
       _isAndroid = isAndroid ?? Platform.isAndroid,
       _timer = timer ?? Timer.new,
       _lifecycle = lifecycle ?? const Stream.empty();

```

**4.** Replace:

```dart
  final TimerFactory _timer;
  // Static: the native namespace stays open for the whole process, so a
```

with:

```dart
  final TimerFactory _timer;

  /// The app's lifecycle changes (`appLifecycleChanges`); see [_prompting].
  final Stream<AppLifecycleState> _lifecycle;
  // Static: the native namespace stays open for the whole process, so a
```

**5.** Replace:

```dart
  static const promptTimeout = Duration(seconds: 30);

```

with:

```dart
  static const promptTimeout = Duration(seconds: 30);

  /// How long a call may stay unanswered once the app is back in front
  /// after its prompt; see [_prompting].
  static const resumeGrace = Duration(seconds: 1);

```

**6.** Replace:

```dart

  /// Runs [call], a plugin call that may show the Keystore prompt, and
  /// on Android throws a [TimeoutException] after [promptTimeout]. The iOS
  /// Keychain reports its cancels, so there it only waits.
```

with:

```dart

  /// Runs [call], a plugin call that may show the Keystore prompt. On
  /// Android it throws a [TimeoutException] when the prompt went away
  /// without an answer, or after [promptTimeout] at the latest. The iOS
  /// Keychain reports its cancels, so there it only waits.
```

**7.** Replace:

```dart
  ///
  /// A call that succeeds, even too late, has opened the namespace, so
  /// later reads in this process must ask local_auth first.
  Future<T> _prompting<T>(Future<T> call) {
    if (!_isAndroid) return call;
    final result = Completer<T>();
    final timer = _timer(promptTimeout, () {
      if (result.isCompleted) return;
      debugPrint('Biometric prompt timed out');
      result.completeError(TimeoutException(null, promptTimeout));
    });
    unawaited(
      call.then(
        (value) {
          _primedThisProcess = true;
          timer.cancel();
          if (!result.isCompleted) result.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          timer.cancel();
          if (!result.isCompleted) result.completeError(error, stack);
```

with:

```dart
  ///
  /// The prompt covers the app, which goes inactive, and its dismissal
  /// brings the app back to resumed. So after the app leaves resumed and
  /// comes back with no answer, [resumeGrace] later the call counts as
  /// cancelled (M1-D2 spec §6, R3-2); an answer within the grace wins, and
  /// leaving again (the prompt shown again) restarts the watch. The
  /// [promptTimeout] stays as the backstop where the lifecycle says
  /// nothing, and a late write is still removed (`enable`).
  ///
  /// A call that succeeds, even too late, has opened the namespace, so
  /// later reads in this process must ask local_auth first.
  Future<T> _prompting<T>(Future<T> call) {
    if (!_isAndroid) return call;
    final result = Completer<T>();
    Timer? grace;
    var away = false;
    late final Timer timeout;
    late final StreamSubscription<AppLifecycleState> lifecycle;
    void settle() {
      timeout.cancel();
      grace?.cancel();
      unawaited(lifecycle.cancel());
    }

    void giveUp(String why, Duration after) {
      if (result.isCompleted) return;
      debugPrint(why);
      settle();
      result.completeError(TimeoutException(null, after));
    }

    timeout = _timer(
      promptTimeout,
      () => giveUp('Biometric prompt timed out', promptTimeout),
    );
    lifecycle = _lifecycle.listen((state) {
      if (state != AppLifecycleState.resumed) {
        away = true;
        grace?.cancel();
        return;
      }
      if (!away) return;
      away = false;
      grace?.cancel();
      grace = _timer(
        resumeGrace,
        () => giveUp('Biometric prompt closed without an answer', resumeGrace),
      );
    });
    unawaited(
      call.then(
        (value) {
          _primedThisProcess = true;
          settle();
          if (!result.isCompleted) result.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          settle();
          if (!result.isCompleted) result.completeError(error, stack);
```

**8.** Replace:

```dart

  /// The prompt outlives a timed-out [enable]: a touch minutes later still
  /// stores the password. The user was told biometrics are off, so that
  /// entry is removed. The namespace is open by then, so the delete does
```

with:

```dart

  /// A given-up [enable] can still store the password later: a touch on
  /// a prompt left on screen after [promptTimeout], or an answer slower
  /// than [resumeGrace]. The user was told biometrics are off, so that
  /// entry is removed. The namespace is open by then, so the delete does
```

Edit `app/lib/main.dart` (2 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/platform/backup_exclusion.dart';
```

with:

```dart
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/platform/app_lifecycle.dart';
import 'package:digibyte_dex/platform/backup_exclusion.dart';
```

**2.** Replace:

```dart
    attempts: PasswordAttempts(LockoutStore(storage)),
    biometrics: DeviceBiometricStore(markers: storage),
    clipboard: ClipboardGuard(),
```

with:

```dart
    attempts: PasswordAttempts(LockoutStore(storage)),
    biometrics: DeviceBiometricStore(
      markers: storage,
      lifecycle: appLifecycleChanges(),
    ),
    clipboard: ClipboardGuard(),
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/data/biometrics/device_biometric_store_test.dart \
  test/platform/app_lifecycle_test.dart
```
Expected: `+43: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```
Expected: the formatter changes 0 files; `No issues found!`; `+858: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/data/biometrics/biometric_store.dart \
  lib/main.dart \
  lib/platform/app_lifecycle.dart \
  test/data/biometrics/device_biometric_store_test.dart \
  test/platform/app_lifecycle_test.dart
git commit -m "fix(biometrics): a prompt closed without an answer counts as cancelled after 1 s" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 9: S3-2: sign-in preselects the wallet signed in last

Spec §6.3.
- `LastWalletStore` keeps one wallet name under `last_wallet` in the existing state `KeyValueStore`.
- `AppCubits` writes it on every `AuthSignedIn`, so every sign-in path counts: the sign-in page, create, restore, and an adopted session. A write error only logs its type.
- `SignInCubit.init`:
  - reads the stored name and preselects it if it is still in the wallet list, otherwise the first wallet;
  - falls back to the first wallet, logging the type, when the store is unreadable;
  - puts the choice in the same first state that lists the wallets. The wallet picker (`DropdownButtonFormField.initialValue`) reads its value only once, so a choice that arrives later would never be shown.

**Files:**
- Create: `app/lib/data/storage/last_wallet_store.dart`
- Modify: `app/lib/app/app_scope.dart`, `app/lib/main.dart`
- Modify: `app/lib/features/auth/bloc/sign_in_cubit.dart`, `app/lib/features/auth/view/sign_in_page.dart`
- Test (create): `app/test/data/storage/last_wallet_store_test.dart`
- Test (modify): `app/test/support/test_app.dart`, `app/test/app/app_scope_test.dart`, `app/test/app/app_test.dart`, `app/test/features/auth/sign_in_cubit_test.dart`, `app/test/features/auth/sign_in_page_test.dart`

**Interfaces:**
- Consumes: `KeyValueStore`, `AuthSignedIn`, and the existing `SignInCubit` and `SignInPage`.
- Produces:
  - `class LastWalletStore`:
    - `LastWalletStore(KeyValueStore store)`;
    - `static const key = 'last_wallet'`;
    - `Future<String?> read()` and `Future<void> remember(String wallet)`.
  - `AppServices` gains `required LastWalletStore lastWallet`, and `AppScope` provides it.
  - The `SignInCubit(...)` constructor gains `required LastWalletStore lastWallet`.
  - `TestApp.lastWallet`.

- [ ] **Step 1: Write the failing tests**

Create `app/test/data/storage/last_wallet_store_test.dart`:

```dart
import 'package:digibyte_dex/data/storage/last_wallet_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';

void main() {
  test('remembers one wallet name; the latest wins', () async {
    final storage = InMemoryKeyValueStore();
    final store = LastWalletStore(storage);
    expect(await store.read(), isNull);
    await store.remember('main');
    await store.remember('cold');
    expect(await store.read(), 'cold');
    expect(storage.values, {'last_wallet': 'cold'});
  });
}
```

Edit `app/test/support/test_app.dart` (3 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
```

with:

```dart
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/last_wallet_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
```

**2.** Replace:

```dart
  late final backups = BackupStatusStore(storage);
  late final attempts = PasswordAttempts(LockoutStore(storage), now: () => now);
```

with:

```dart
  late final backups = BackupStatusStore(storage);
  late final lastWallet = LastWalletStore(storage);
  late final attempts = PasswordAttempts(LockoutStore(storage), now: () => now);
```

**3.** Replace:

```dart
    prices: prices,
    session: session,
```

with:

```dart
    prices: prices,
    lastWallet: lastWallet,
    session: session,
```

Edit `app/test/app/app_scope_test.dart` (5 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
```

with:

```dart
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/last_wallet_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
```

**2.** Replace:

```dart

import '../support/fake_assets_repository.dart';
```

with:

```dart

import '../support/capture_debug_print.dart';
import '../support/fake_assets_repository.dart';
```

**3.** Replace:

```dart
  late FakePriceFeed prices;
  late AppServices services;

  setUp(() {
    wallet = FakeWalletRepository();
    prices = FakePriceFeed();
    final storage = InMemoryKeyValueStore();
    services = AppServices(
```

with:

```dart
  late FakePriceFeed prices;
  late InMemoryKeyValueStore storage;
  late AppServices services;

  setUp(() {
    wallet = FakeWalletRepository();
    prices = FakePriceFeed();
    storage = InMemoryKeyValueStore();
    services = AppServices(
```

**4.** Replace:

```dart
      prices: prices,
    );
```

with:

```dart
      prices: prices,
      lastWallet: LastWalletStore(storage),
    );
```

**5.** Replace:

```dart
    expect(probe.read<PricePolling>(), same(cubits.pricePolling));
  });
```

with:

```dart
    expect(probe.read<PricePolling>(), same(cubits.pricePolling));
    expect(probe.read<LastWalletStore>(), same(services.lastWallet));
  });

  test('every sign-in is remembered for the next sign-in page', () async {
    build();
    wallet.emit(null);
    await settle();
    expect(await services.lastWallet.read(), isNull);
    wallet.emit(const WalletUser('cold'));
    await settle();
    expect(await services.lastWallet.read(), 'cold');
    wallet
      ..emit(null)
      ..emit(const WalletUser('main'));
    await settle();
    expect(await services.lastWallet.read(), 'main');
  });

  test('a failed write only logs its type', () async {
    final logs = captureDebugPrint();
    storage.writeError = Exception('keystore');
    build();
    wallet.emit(const WalletUser('cold'));
    await settle();
    expect(logs, ['Last wallet write failed: _Exception']);
  });
```

Edit `app/test/app/app_test.dart` (1 replacement, top to bottom):

**1.** Replace:

```dart
    expect(find.text('Portfolio'), findsOneWidget);
  });
```

with:

```dart
    expect(find.text('Portfolio'), findsOneWidget);
  });

  testWidgets('after a sign-out, sign-in starts on that wallet (S3-2)', (
    t,
  ) async {
    final app = TestApp();
    addTearDown(app.dispose);
    app.wallet.names = ['main', 'cold'];
    await t.pumpWidget(app.build());
    app.wallet.emit(null);
    await t.pumpAndSettle();
    app.wallet.emit(const WalletUser('cold'));
    await t.pumpAndSettle();
    expect(find.text('Portfolio'), findsOneWidget);
    app.wallet.emit(null);
    await t.pumpAndSettle();
    final picker = find.byKey(const Key('signin.wallet'));
    expect(
      find.descendant(of: picker, matching: find.text('cold')),
      findsOneWidget,
    );
    await t.enterText(
      find.byKey(const Key('signin.password')),
      app.wallet.correctPassword,
    );
    await t.tap(find.byKey(const Key('signin.submit')));
    await t.pumpAndSettle();
    expect(app.wallet.calls.last, 'signIn:cold');
  });
```

Edit `app/test/features/auth/sign_in_cubit_test.dart` (3 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
```

with:

```dart
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/storage/last_wallet_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
```

**2.** Replace:

```dart
      optIn: BiometricOptIn(biometrics),
    );
```

with:

```dart
      optIn: BiometricOptIn(biometrics),
      lastWallet: LastWalletStore(storage),
    );
```

**3.** Replace:

```dart
    expect(cubit.state.wallets, ['main', 'cold']);
  });
```

with:

```dart
    expect(cubit.state.wallets, ['main', 'cold']);
  });

  group('the wallet signed in last (S3-2)', () {
    test('is preselected', () async {
      await LastWalletStore(storage).remember('cold');
      final cubit = await build(wallets: ['main', 'cold', 'spare']);
      expect(cubit.state.selected, 'cold');
    });

    test('is chosen in the first state that lists the wallets', () async {
      await LastWalletStore(storage).remember('cold');
      final cubit = SignInCubit(
        wallet: repo,
        attempts: PasswordAttempts(LockoutStore(storage), now: () => now),
        biometrics: biometrics,
        optIn: BiometricOptIn(biometrics),
        lastWallet: LastWalletStore(storage),
      );
      addTearDown(cubit.close);
      final states = <SignInState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);
      await cubit.init(['main', 'cold']);
      expect(states.first.wallets, ['main', 'cold']);
      expect(states.first.selected, 'cold');
    });

    test('a deleted wallet falls back to the first', () async {
      await LastWalletStore(storage).remember('gone');
      final cubit = await build(wallets: ['main', 'cold']);
      expect(cubit.state.selected, 'main');
    });

    test(
      'an unreadable store falls back to the first, logged by type',
      () async {
        final logs = captureDebugPrint();
        await LastWalletStore(storage).remember('cold');
        storage.readError = Exception('keystore');
        final cubit = SignInCubit(
          wallet: repo,
          attempts: PasswordAttempts(LockoutStore(storage), now: () => now),
          biometrics: biometrics,
          optIn: BiometricOptIn(biometrics),
          lastWallet: LastWalletStore(storage),
        );
        addTearDown(cubit.close);
        await cubit.init(['main', 'cold']);
        expect(cubit.state.selected, 'main');
        expect(logs, contains('Last wallet read failed: _Exception'));
      },
    );

    test('no wallets: nothing selected', () async {
      final cubit = await build(wallets: []);
      expect(cubit.state.selected, isNull);
    });
  });
```

Edit `app/test/features/auth/sign_in_page_test.dart` (3 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
```

with:

```dart
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/last_wallet_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
```

**2.** Replace:

```dart
          RepositoryProvider.value(value: optIn),
        ],
```

with:

```dart
          RepositoryProvider.value(value: optIn),
          RepositoryProvider.value(value: LastWalletStore(storage)),
        ],
```

**3.** Replace:

```dart
    expect(repo.calls, ['signIn:main']);
  });
```

with:

```dart
    expect(repo.calls, ['signIn:main']);
  });

  testWidgets('the picker starts on the wallet signed in last (S3-2)', (
    t,
  ) async {
    repo.names = ['main', 'cold', 'spare'];
    await LastWalletStore(storage).remember('cold');
    await pump(t);
    await t.pump();
    final picker = find.byKey(const Key('signin.wallet'));
    expect(
      find.descendant(of: picker, matching: find.text('cold')),
      findsOneWidget,
    );
    await submit(t, _pw);
    expect(repo.calls, ['signIn:cold']);
  });
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/data/storage/last_wallet_store_test.dart \
  test/features/auth/sign_in_cubit_test.dart \
  test/features/auth/sign_in_page_test.dart \
  test/app/app_scope_test.dart \
  test/app/app_test.dart
```
Expected: FAIL to compile: `last_wallet_store.dart` not found, and `No named parameter with the name 'lastWallet'`.

- [ ] **Step 3: Implement**

Create `app/lib/data/storage/last_wallet_store.dart`:

```dart
import 'package:digibyte_dex/data/storage/key_value_store.dart';

/// The wallet signed in last, so sign-in preselects it (M1-D2 spec §6,
/// S3-2). A wallet name only; nothing secret.
class LastWalletStore {
  LastWalletStore(this._store);

  final KeyValueStore _store;

  static const key = 'last_wallet';

  Future<String?> read() => _store.read(key);

  Future<void> remember(String wallet) => _store.write(key, wallet);
}
```

Edit `app/lib/app/app_scope.dart` (7 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';
```

with:

```dart
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/last_wallet_store.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';
```

**2.** Replace:

```dart
    required this.prices,
    PendingBackupSession? session,
```

with:

```dart
    required this.prices,
    required this.lastWallet,
    PendingBackupSession? session,
```

**3.** Replace:

```dart
  final PriceFeed prices;
  final PendingBackupSession session;
```

with:

```dart
  final PriceFeed prices;

  /// The wallet sign-in preselects (M1-D2 spec §6, S3-2).
  final LastWalletStore lastWallet;
  final PendingBackupSession session;
```

**4.** Replace:

```dart
/// send whose broadcast has started past its page; signing out clears it.
/// [pricePolling] runs the price feed while signed in and unlocked.
class AppCubits {
```

with:

```dart
/// send whose broadcast has started past its page; signing out clears it.
/// [pricePolling] runs the price feed while signed in and unlocked. Every
/// sign-in (sign-in page, create, restore) is remembered for the next
/// sign-in page.
class AppCubits {
```

**5.** Replace:

```dart
      activeSend.clear();
    });
```

with:

```dart
      activeSend.clear();
    });
    _signedIn = auth.stream.listen((state) {
      if (state is AuthSignedIn) {
        unawaited(_remember(services.lastWallet, state.user.name));
      }
    });
```

**6.** Replace:

```dart
  late final StreamSubscription<AuthState> _signedOut;

  Future<void> close() async {
    await pricePolling.close();
    await _signedOut.cancel();
```

with:

```dart
  late final StreamSubscription<AuthState> _signedOut;
  late final StreamSubscription<AuthState> _signedIn;

  /// Never throws: a keystore error only costs the preselection.
  static Future<void> _remember(LastWalletStore store, String wallet) async {
    try {
      await store.remember(wallet);
    } on Object catch (error) {
      debugPrint('Last wallet write failed: ${error.runtimeType}');
    }
  }

  Future<void> close() async {
    await pricePolling.close();
    await _signedIn.cancel();
    await _signedOut.cancel();
```

**7.** Replace:

```dart
      RepositoryProvider.value(value: services.backups),
      RepositoryProvider.value(value: services.attempts),
```

with:

```dart
      RepositoryProvider.value(value: services.backups),
      RepositoryProvider.value(value: services.lastWallet),
      RepositoryProvider.value(value: services.attempts),
```

Edit `app/lib/main.dart` (2 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/data/storage/key_value_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
```

with:

```dart
import 'package:digibyte_dex/data/storage/key_value_store.dart';
import 'package:digibyte_dex/data/storage/last_wallet_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
```

**2.** Replace:

```dart
    prices: prices,
  );
```

with:

```dart
    prices: prices,
    lastWallet: LastWalletStore(storage),
  );
```

Edit `app/lib/features/auth/bloc/sign_in_cubit.dart` (5 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/features/auth/domain/biometric_opt_in.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/domain/password_gate.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
```

with:

```dart
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/last_wallet_store.dart';
import 'package:digibyte_dex/features/auth/domain/biometric_opt_in.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/domain/password_gate.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
```

**2.** Replace:

```dart
/// Cold-start sign-in: pick a wallet, then password or biometrics. Every
/// sign-in starts KDF with the wallet's stored options (Task 5).
class SignInCubit extends Cubit<SignInState> {
```

with:

```dart
/// Cold-start sign-in: pick a wallet, then password or biometrics. Every
/// sign-in starts KDF with the wallet's stored options (Task 5). The
/// wallet signed in last is preselected (M1-D2 spec §6, S3-2).
class SignInCubit extends Cubit<SignInState> {
```

**3.** Replace:

```dart
    required BiometricOptIn optIn,
  }) : _wallet = wallet,
       super(const SignInState()) {
```

with:

```dart
    required BiometricOptIn optIn,
    required LastWalletStore lastWallet,
  }) : _wallet = wallet,
       _lastWallet = lastWallet,
       super(const SignInState()) {
```

**4.** Replace:

```dart
  final WalletRepository _wallet;
  late final PasswordGate _gate;
```

with:

```dart
  final WalletRepository _wallet;
  final LastWalletStore _lastWallet;
  late final PasswordGate _gate;
```

**5.** Replace:

```dart

  Future<void> init(List<String> wallets) async {
    _emit(SignInState(wallets: wallets));
    if (wallets.isNotEmpty) await select(wallets.first);
  }
```

with:

```dart

  /// Preselects the wallet signed in last if it still exists, otherwise
  /// the first. The choice is in the first state with [wallets], so the
  /// wallet picker starts on it.
  Future<void> init(List<String> wallets) async {
    if (wallets.isEmpty) {
      _emit(SignInState(wallets: wallets));
      return;
    }
    final last = await _readLastWallet();
    final first = wallets.contains(last) ? last! : wallets.first;
    _emit(SignInState(wallets: wallets, selected: first));
    await select(first);
  }

  Future<String?> _readLastWallet() async {
    try {
      return await _lastWallet.read();
    } on Object catch (error) {
      debugPrint('Last wallet read failed: ${error.runtimeType}');
      return null;
    }
  }
```

Edit `app/lib/features/auth/view/sign_in_page.dart` (2 replacements, top to bottom):

**1.** Replace:

```dart
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
```

with:

```dart
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/last_wallet_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
```

**2.** Replace:

```dart
          optIn: context.read<BiometricOptIn>(),
        );
```

with:

```dart
          optIn: context.read<BiometricOptIn>(),
          lastWallet: context.read<LastWalletStore>(),
        );
```

- [ ] **Step 4: Run the task tests**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter test \
  test/data/storage/last_wallet_store_test.dart \
  test/features/auth/sign_in_cubit_test.dart \
  test/features/auth/sign_in_page_test.dart \
  test/app/app_scope_test.dart \
  test/app/app_test.dart
```
Expected: `+63: All tests passed!`

- [ ] **Step 5: Format, analyze and run the whole suite**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter analyze
fvm flutter test
```
Expected: the formatter changes 0 files; `No issues found!`; `+868: All tests passed!`.

- [ ] **Step 6: Check the Android build and the permission allowlist**

```bash
cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter build apk --debug
cd .. && tool/check_permissions.sh
```
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`; `permissions OK: 5 entries match allowlist`.

- [ ] **Step 7: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add \
  lib/app/app_scope.dart \
  lib/data/storage/last_wallet_store.dart \
  lib/features/auth/bloc/sign_in_cubit.dart \
  lib/features/auth/view/sign_in_page.dart \
  lib/main.dart \
  test/app/app_scope_test.dart \
  test/app/app_test.dart \
  test/data/storage/last_wallet_store_test.dart \
  test/features/auth/sign_in_cubit_test.dart \
  test/features/auth/sign_in_page_test.dart \
  test/support/test_app.dart
git commit -m "fix(sign-in): preselect the wallet signed in last" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

### Task 10: Release 0.4.0 through Play internal testing, on-device acceptance on the Moto, and the PR

Spec §8 (on-device acceptance) and §9 (release). Everything runs on the release workstation against the Moto `ZY22HVMNKZ`.

**Files:**
- Modify: `app/pubspec.yaml` (`version: 0.4.0+6`)
- Modify: `docs/release.md` (a new section, "M1-D2 acceptance (0.4.0)")
- Scratch only, never committed:
  - `$SCRATCH/m1d2-accept/`, with `env.sh`, the M1-D1 helpers (`ui.py`, `rids.py`, `scan_log.py`, `fund.py`) and the new helpers (`text.py`, `watchrow.py`, `cg.py`, `pct.py`, `r32.py`, `conns.py`);
  - screenshots, logcat dumps and the PR body.
- Secrets (mode 600, never printed):
  - `~/.config/dgb-dex/m1d1-send1-password`, the throwaway password of `legacy3`;
  - `~/.config/dgb-dex/m0-phone-seed`, read only by `fund.py` on the workstation;
  - `~/.config/dgb-dex/m1c-iguana-seed`, `legacy3`'s seed. It is used only by the log scan and is never typed.

**Interfaces:**
- Consumes:
  - every widget id of Tasks 4–9: `home.total`, `home.total.excludes`, `home.row.<T>.usd` / `.change`, `price.stale`, `asset.price.value` / `.unit`, `asset.chart.*`, `send.usd`, `confirm.usd.*`, `tx.date`, `signin.wallet`;
  - the existing ids from M1-C and M1-D1.
  - Android reports each `Tagged` id as a node `resource-id`.
- Produces:
  - 0.4.0 installed from Play internal testing on `ZY22HVMNKZ`;
  - the AAB in `~/digibyte-dex/release-artifacts/`;
  - the acceptance record in `docs/release.md`;
  - an open PR `feat/m1d2-prices-usd` → `main` with green CI.

**Rules for this task:**
- **adb:** every command targets `-s ZY22HVMNKZ`. Never touch the Note 8. Never restart adb.
- **Secrets on the phone:**
  - No real seed is ever typed through adb. The only secret typed is `legacy3`'s throwaway password, through `type_throwaway`, which clears logcat right after.
  - The M0 mule seed never leaves the workstation: `fund.py` gives it to a local KDF.
  - No screenshot while a password or seed is on screen.
- **Printing node text:** `ui text`, `ui waittext`, `watchrow.py` and `text.py` print node text. Use them only on prices, amounts, statuses, wallet names and addresses, never on a backup, quiz or restore screen. There, use `ids` (ids, bounds and checked state only).
- **Checkboxes:** read a checkbox's state (`ui checked …`) before tapping it.
- **Fingerprint prompts — STOP and relay:** before every command that can raise a fingerprint prompt, stop and have the controller tell the owner exactly what to do: touch the sensor (the power button), or tap "Use password". Continue only after the owner's go.
- **Who runs what:**
  - **[OWNER]** steps need the owner at the phone (fingerprint, Play, Chrome).
  - **[CONTROLLER]** steps are run by the controller session, not by an implementer subagent. Before any broadcast from the mule, the controller tells the owner the amount and the address.
- **Funds moved:** mule → `legacy3` 0.1 DGB, and once more only if the first deposit was never seen pending. Nothing else is sent: the Send check stops at Confirm.

- [ ] **Step 1: Bump the version and commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
sed -i 's/^version: 0\.3\.1+5$/version: 0.4.0+6/' pubspec.yaml
grep -n '^version:' pubspec.yaml   # version: 0.4.0+6
fvm flutter analyze && fvm flutter test
git add pubspec.yaml
git commit -m "chore(app): version 0.4.0 (M1-D2 prices and USD)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```
Expected: `No issues found!` and `+868: All tests passed!`.

- [ ] **Step 2: [CONTROLLER] Whole-branch review before the release build**

Spec §7: one whole-branch review (`main...feat/m1d2-prices-usd`) before the release build. Its checklist:
- the Review Focus list;
- the departures;
- no URL, price or wallet name in any log line;
- `marketDataOff`;
- the `Tagged` ids Task 10 uses.

Fixes land on the branch with their own tests; re-run Step 1's checks after them. Continue only when the review is clean.

- [ ] **Step 3: Build the signed AAB and keep a copy**

```bash
export SCRATCH=<this session's scratchpad>
cd ~/digibyte-dex/digibyte-wallet
mkdir -p "$SCRATCH/m1d2-accept"
set -o pipefail
tool/release_android.sh | tee "$SCRATCH/m1d2-accept/release.log"
VC=$(sed -n 's/^versionCode: *//p' "$SCRATCH/m1d2-accept/release.log")
cp app/build/app/outputs/bundle/release/app-release.aab \
  ~/digibyte-dex/release-artifacts/digibyte-dex-0.4.0-$VC.aab
ls -l ~/digibyte-dex/release-artifacts/ | tail -2
java -jar /tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/eab8c964-9b1e-44ec-b157-ec18db695089/scratchpad/tools/bundletool-all-1.18.1.jar \
  dump manifest --bundle ~/digibyte-dex/release-artifacts/digibyte-dex-0.4.0-$VC.aab \
  --xpath /manifest/uses-sdk/@android:targetSdkVersion
echo "$VC" > "$SCRATCH/m1d2-accept/versionCode"
```
Expected:
- The signer matches the upload certificate, and every 16 KB row is PASS.
- `versionName: 0.4.0` and a `versionCode` above 402506 (0.3.1).
- The copy exists, and the target SDK is `36`.

- [ ] **Step 4: Upload to Play internal testing and release it (hands-off)**

```bash
export SCRATCH=<this session's scratchpad>
cd ~/digibyte-dex/digibyte-wallet
VC=$(cat "$SCRATCH/m1d2-accept/versionCode")
tool/.venv/bin/python tool/play_upload.py \
  --aab ~/digibyte-dex/release-artifacts/digibyte-dex-0.4.0-$VC.aab \
  --track internal --status completed \
  --notes "0.4.0: USD prices, portfolio total and sparklines (CoinGecko)"
```
Expected: `uploaded N%` lines, then `Uploaded versionCode <VC> to internal (completed).` The service account can release to testing tracks, so no Console step is needed.
- On `HTTP 403`, the permission was revoked. Stop and tell the owner; the script prints the missing permission.

- [ ] **Step 5: [OWNER] Update the Moto to 0.4.0 from Play**

```bash
adb -s ZY22HVMNKZ shell am start -a android.intent.action.VIEW -d 'market://details?id=me.digiscope.wallet'
```
**[OWNER]** On the Play page that opens, tap **Update**. If it still says "Open", wait a few minutes for the internal-testing rollout and pull down to refresh. Then:

```bash
adb -s ZY22HVMNKZ shell pm list packages -i me.digiscope.wallet | grep 'package:me.digiscope.wallet '
adb -s ZY22HVMNKZ shell dumpsys package me.digiscope.wallet | grep -m1 versionName
```
Expected: `installer=com.android.vending` and `versionName=0.4.0`.

- [ ] **Step 6: Create the acceptance helpers; raise the screen timeout**

Copy the M1-D1 helpers. They are unchanged, and the ids-only dump is `rids.py`. If that directory is gone, they are in the M1-D1 plan, Task 13 Step 6 (`docs/superpowers/plans/2026-10-04-m1d1-move-money.md`).

```bash
export SCRATCH=<this session's scratchpad>
M1D1=/tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/eab8c964-9b1e-44ec-b157-ec18db695089/scratchpad/m1d1-accept
mkdir -p "$SCRATCH/m1d2-accept"
cp "$M1D1"/{ui.py,rids.py,scan_log.py,fund.py} "$SCRATCH/m1d2-accept/"
```

Create `$SCRATCH/m1d2-accept/env.sh`:

```bash
# Source me at the start of every acceptance command:
#   source "$SCRATCH/m1d2-accept/env.sh"
set +x
ACC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D=ZY22HVMNKZ
S=~/.config/dgb-dex
# The M0 test mule's first DGB address (SECRETS-INDEX.md; public).
MULE=DLFhh33PLHZ2y1kN37BiQ2uD4f394jdixs
# legacy3's throwaway password (SECRETS-INDEX.md: m1d1-send1-password).
PW="$S/m1d1-send1-password"

# Types the THROWAWAY password into the focused field, 8 characters per
# `input text` call, then clears logcat at once: adbd logs `input text`.
# It refuses any other file, so a real seed is never typed.
type_throwaway() {
  case "$1" in
    */m1d1-send1-password) ;;
    *) echo "refusing: only the throwaway password is typed" >&2; return 1 ;;
  esac
  local secret chunk i left
  secret="$(tr -d '\n' < "$1")"
  for ((i = 0; i < ${#secret}; i += 8)); do
    chunk="${secret:i:8}"
    adb -s "$D" shell input text "'${chunk}'" > /dev/null 2>&1
  done
  secret=''
  chunk=''
  adb -s "$D" logcat -c
  left="$(adb -s "$D" logcat -d | grep -c 'input text')"
  if [ "$left" != 0 ]; then
    echo "WARNING: $left 'input text' log line(s) remain after logcat -c" >&2
    return 1
  fi
}

# A normal screenshot. Never on a screen showing a password or seed.
shot() { adb -s "$D" exec-out screencap -p > "$ACC/$1.png"; echo "saved $1.png"; }

ui() { python3 "$ACC/ui.py" "$@"; }

# Resource-ids, bounds, enabled and checked only: never node text.
ids() { python3 "$ACC/rids.py"; }

# On-screen text by content. Never on a backup, quiz or restore screen.
txt() { python3 "$ACC/text.py" "$@"; }

pause() { python3 "$ACC/ui.py" pause "$1"; }

launch() { adb -s "$D" shell am start -n me.digiscope.wallet/.MainActivity > /dev/null; }

kill_app() { adb -s "$D" shell am force-stop me.digiscope.wallet; }

# Scans the device log for every acceptance secret; prints counts and log
# tags only. The dump is kept as evidence when clean, deleted on a leak.
scan_log() {
  adb -s "$D" logcat -d > "$ACC/logcat-$1.txt"
  python3 "$ACC/scan_log.py" "$ACC/logcat-$1.txt" \
    "$S/m1d1-send1-password" "$S/m0-phone-seed" "$S/m1c-iguana-seed"
}
```

Create `$SCRATCH/m1d2-accept/text.py`:

```python
#!/usr/bin/env python3
"""On-screen text, for screens without secrets (sign-in, Home, notices).
Never use it on a backup, quiz or restore screen.

  text.py wait NEEDLE [TIMEOUT]  waits for a node whose text contains
                                 NEEDLE; prints how long it took
  text.py tap EXACT [TIMEOUT]    taps the first node whose text is EXACT
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ui  # noqa: E402


def main():
    cmd, needle = sys.argv[1], sys.argv[2]
    timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 20.0
    start = time.time()
    while time.time() - start < timeout:
        root = ui.dump()
        for node in root.iter('node') if root is not None else []:
            text = (node.get('text') or node.get('content-desc') or '').strip()
            if (needle in text) if cmd == 'wait' else (text == needle):
                if cmd == 'tap':
                    ui.tap_node(node)
                    print('tapped')
                else:
                    print('seen after %.1f s' % (time.time() - start))
                return
        time.sleep(0.3)
    sys.exit('not seen: %s' % needle)


if __name__ == '__main__':
    main()
```

Create `$SCRATCH/m1d2-accept/watchrow.py`:

```python
#!/usr/bin/env python3
"""Prints the newest history row (asset.tx.0) each time it changes, until
it is a received row still Pending (exit 0) or SECONDS pass (exit 1).
History rows hold no secret.

  watchrow.py SECONDS
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ui  # noqa: E402

start = time.time()
last = None
while time.time() - start < float(sys.argv[1]):
    _, hits = ui.find(r'asset\.tx\.0', 2)
    text = ui.text_of(hits[0]) if hits else ''
    if text != last:
        print('%5.1f s  %s' % (time.time() - start, text), flush=True)
        last = text
    if 'Received' in text and 'Pending' in text:
        sys.exit(0)
    time.sleep(0.5)
sys.exit(1)
```

Create `$SCRATCH/m1d2-accept/cg.py`:

```python
#!/usr/bin/env python3
"""CoinGecko's own USD prices, read on the Moto: the workstation cannot
reach CoinGecko. Opens the public simple/price URL in Chrome and reads
the JSON from the screen. Prints `digibyte <usd>` and so on.

  cg.py
"""
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ui  # noqa: E402

URL = ('https://api.coingecko.com/api/v3/simple/price'
       '?ids=digibyte,bitcoin,litecoin&vs_currencies=usd')
ui.adb('shell', 'am', 'start', '-a', 'android.intent.action.VIEW',
       '-d', URL, '-p', 'com.android.chrome')
start = time.time()
while time.time() - start < 30:
    root = ui.dump()
    if root is not None:
        for node in root.iter('node'):
            text = node.get('text') or ''
            match = re.search(r'\{.*"digibyte".*\}', text)
            if not match:
                continue
            try:
                data = json.loads(match.group(0))
            except ValueError:
                continue
            for coin in ('digibyte', 'bitcoin', 'litecoin'):
                print(coin, data[coin]['usd'])
            sys.exit(0)
    time.sleep(1)
sys.exit('no JSON on the Chrome page: read the prices on coingecko.com')
```

Create `$SCRATCH/m1d2-accept/pct.py`:

```python
#!/usr/bin/env python3
"""The app's unit price against CoinGecko's, within 1 % (spec §8.1).

  pct.py '1 DGB = $0.012345' 0.01236
"""
import re
import sys
from decimal import Decimal

app = Decimal(re.search(r'\$([\d,]+(?:\.\d+)?)', sys.argv[1])
              .group(1).replace(',', ''))
cg = Decimal(sys.argv[2])
diff = abs(app - cg) / cg * 100
print('app %s  coingecko %s  diff %.2f %%  %s'
      % (app, cg, diff, 'PASS' if diff <= 1 else 'FAIL'))
```

Create `$SCRATCH/m1d2-accept/r32.py`:

```python
#!/usr/bin/env python3
"""R3-2 timing from a `logcat -v epoch` dump: from the system closing the
fingerprint prompt to the app giving it up (spec §6.2, about 1 s).

  r32.py LOGCAT_FILE
"""
import re
import sys

closed = gave_up = timed_out = None
for line in open(sys.argv[1], errors='replace'):
    m = re.match(r'\s*(\d+\.\d+)', line)
    if not m:
        continue
    t = float(m.group(1))
    if closed is None and 'onDialogDismissed' in line:
        closed = t
    elif (closed is not None and gave_up is None
          and 'Biometric prompt closed without an answer' in line):
        gave_up = t
    elif 'Biometric prompt timed out' in line:
        timed_out = t
if closed is None:
    sys.exit('no onDialogDismissed line; grep the dump for BiometricPrompt')
if gave_up is None:
    sys.exit('the app never gave up' +
             (': it TIMED OUT after 30 s instead' if timed_out else ''))
delta = gave_up - closed
print('prompt closed -> app answered: %.1f s  %s'
      % (delta, 'PASS' if delta <= 2.0 else 'FAIL'))
```

Create `$SCRATCH/m1d2-accept/conns.py`:

```python
#!/usr/bin/env python3
"""Remote endpoints of the app's TCP connections, sampled every second for
SECONDS from /proc/net/tcp and tcp6. It prints IPs and ports only: host
names are resolved on the workstation.

  conns.py SECONDS
"""
import ipaddress
import re
import subprocess
import sys
import time

ADB = ['adb', '-s', 'ZY22HVMNKZ']


def sh(*args):
    return subprocess.run(ADB + ['shell'] + list(args),
                          capture_output=True, text=True)


uid = re.search(r'userId=(\d+)',
                sh('dumpsys', 'package', 'me.digiscope.wallet').stdout).group(1)


def endpoint(hexaddr):
    ip, port = hexaddr.split(':')
    raw = bytes.fromhex(ip)
    if len(raw) == 4:
        return str(ipaddress.IPv4Address(raw[::-1])), int(port, 16)
    words = b''.join(raw[i:i + 4][::-1] for i in range(0, 16, 4))
    v6 = ipaddress.IPv6Address(words)
    return str(v6.ipv4_mapped or v6), int(port, 16)


seen = {}
end = time.time() + float(sys.argv[1])
while time.time() < end:
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        p = sh('cat', table)
        if p.returncode != 0:
            sys.exit('cannot read %s: %s' % (table, p.stderr.strip()))
        for line in p.stdout.splitlines()[1:]:
            cols = line.split()
            # 01 established, 02 SYN sent
            if len(cols) > 7 and cols[7] == uid and cols[3] in ('01', '02'):
                ip, port = endpoint(cols[2])
                if not ip.startswith('127.') and ip != '::1':
                    seen[(ip, port)] = seen.get((ip, port), 0) + 1
    time.sleep(1)
for (ip, port), n in sorted(seen.items()):
    print(ip, port, n)
```

```bash
export SCRATCH=<this session's scratchpad>
chmod +x "$SCRATCH"/m1d2-accept/*.py
adb -s ZY22HVMNKZ shell settings get system screen_off_timeout      # 60000
adb -s ZY22HVMNKZ shell settings put system screen_off_timeout 1800000
```
Expected: `60000` before the change. If it is something else, record it and restore that value in Step 16 instead of `60000`.

- [ ] **Step 7: Sign in to `legacy3` (and see which wallet 0.4.0 preselects on its first run)**

`legacy3` is a throwaway restored from `m1c-iguana-seed` (legacy on). Its password is `m1d1-send1-password`, it has fingerprint unlock off, and it holds no funds (SECRETS-INDEX.md). Never use `send1`.

```bash
source "$SCRATCH/m1d2-accept/env.sh"
kill_app && adb -s "$D" logcat -c && launch
ui wait signin.password 120
ui text signin.wallet                       # 0.4.0's first run: the first wallet
ui tap signin.wallet && txt tap legacy3 && pause 2
ui text signin.wallet                       # legacy3
ui wait signin.biometric 3; echo "fingerprint button: exit=$?"   # exit=1: off
ui checked signin.enableBiometrics          # false: leave it unticked
ui tap signin.password && type_throwaway "$PW"
ui tap signin.submit
ui wait home.row.DGB 180 && ui wait home.total 120 && shot 01-home-first
scan_log 01-signin
```
Expected:
- The picker moves to `legacy3`, there is no fingerprint button, and Home appears with `home.total`.
- `logcat secret scan: clean`.
- If `signin.biometric` is present, `legacy3` already has fingerprint unlock on (release.md R2 says it is off). Then Step 13a cannot refuse an opt-in on it. Stop and tell the controller, who either runs Step 13a on another throwaway wallet whose fingerprint is off (recording which one), or records 13a as not run and keeps Step 14.

- [ ] **Step 8: R3-1: a received deposit shows "Pending" and no 1969 date (spec §8.5)**

```bash
source "$SCRATCH/m1d2-accept/env.sh"
ui tap home.row.DGB && ui wait asset.receive 60
ui tap asset.receive && ui wait receive.address 60
ui text receive.address | grep -o 'D[1-9A-HJ-NP-Za-km-z]\{25,34\}' | head -1 > "$ACC/legacy3-address"
echo "legacy3 DGB address: $(cat "$ACC/legacy3-address")"
adb -s "$D" shell input keyevent KEYCODE_BACK
ui wait asset.list 30
```

**[CONTROLLER]** Tell the owner: "0.1 DGB from the M0 mule to <legacy3 address>". Dry run first:

```bash
source "$SCRATCH/m1d2-accept/env.sh"
python3 "$ACC/fund.py" --seed-file "$S/m0-phone-seed" --to "$(cat "$ACC/legacy3-address")" --amount 0.1 --dry-run
```
Expected: `mule source D… holds N DGB`, `signed: 0.1 DGB to D…, fee 0.0… DGB`, `dry run: not broadcast`.

Then broadcast, and watch the row at once. DGB blocks come every 15 s, so the pending row lasts only seconds:

```bash
source "$SCRATCH/m1d2-accept/env.sh"
python3 "$ACC/fund.py" --seed-file "$S/m0-phone-seed" --to "$(cat "$ACC/legacy3-address")" --amount 0.1 | tee "$ACC/fund1.log"
read -r W H < <(adb -s "$D" shell wm size | grep -o '[0-9]*x[0-9]*' | tail -1 | tr x ' ')
adb -s "$D" shell input swipe $((W / 2)) $((H * 3 / 10)) $((W / 2)) $((H * 7 / 10)) 300   # pull to refresh
python3 "$ACC/watchrow.py" 180 | tee "$ACC/r31-rows.txt"; echo "pending seen: exit=$?"
ui tap asset.tx.0 && ui text tx.date && shot 02-r31-sheet-pending
adb -s "$D" shell input keyevent KEYCODE_BACK
ss -ltn | grep -c ':7795 '      # 0: the funding KDF is gone
```
Expected:
- `fund1.log` ends with `txid <64 hex>`.
- `watchrow.py` prints a `Received … Pending … +0.1 DGB` row with **no date** (no `1969` or `1970`) and exits 0.
- `tx.date` prints `Pending`.
- If `watchrow.py` exits 1 (the deposit was already mined when it first showed), repeat this block once with a second 0.1 DGB. If it is still never seen pending, record "R3-1: not observable on the device (15 s blocks); covered by unit tests".

Then confirm that the mined row shows its real time:

```bash
source "$SCRATCH/m1d2-accept/env.sh"
ui waittext asset.tx.0 Confirm 900 && shot 03-r31-mined
ui text asset.balance
```
Expected: the row shows `Oct 8, 2026 HH:MM · Confirming n/7`, or `Confirmed`, with today's date; the balance is `0.1 DGB`.

- [ ] **Step 9: Asset detail: the USD value, the unit price and the three sparklines (spec §8.2)**

```bash
source "$SCRATCH/m1d2-accept/env.sh"
ui text asset.balance; ui text asset.price.value; ui text asset.price.unit
ui wait asset.chart.line 60 && ui text asset.chart.change && shot 04-chart-7d
ui tap asset.chart.24h && pause 2 && ui wait asset.chart.line 60 && ui text asset.chart.change && shot 04-chart-24h
ui tap asset.chart.30d && pause 2 && ui wait asset.chart.line 60 && ui text asset.chart.change && shot 04-chart-30d
```
Expected:
- `asset.price.value` ≈ 0.1 × the unit price, for example `$0.00123`.
- `asset.price.unit` reads `1 DGB = $0.0…`, with 6 significant digits.
- Each tab draws a line with a `▲`/`▼` change.
- If a tab shows `Chart unavailable`, tap `asset.chart.retry` once and record both results.

- [ ] **Step 10: Home: the total and per-coin USD with the 24 h change, against coingecko.com (spec §8.1)**

```bash
source "$SCRATCH/m1d2-accept/env.sh"
adb -s "$D" shell input keyevent KEYCODE_BACK && ui wait home.total 30
ui text home.total
for T in DGB BTC LTC; do ui text home.row.$T.balance; ui text home.row.$T.usd; ui text home.row.$T.change; done
shot 05-home-usd
for T in DGB BTC LTC; do
  ui tap home.row.$T && ui wait asset.price.unit 60
  ui text asset.price.unit | tee "$ACC/unit-$T"
  adb -s "$D" shell input keyevent KEYCODE_BACK && ui wait home.total 30
done
python3 "$ACC/cg.py" | tee "$ACC/cg.txt"
launch && ui wait home.total 30
python3 "$ACC/pct.py" "$(cat "$ACC/unit-DGB")" "$(awk '$1=="digibyte"{print $2}' "$ACC/cg.txt")"
python3 "$ACC/pct.py" "$(cat "$ACC/unit-BTC")" "$(awk '$1=="bitcoin"{print $2}' "$ACC/cg.txt")"
python3 "$ACC/pct.py" "$(cat "$ACC/unit-LTC")" "$(awk '$1=="litecoin"{print $2}' "$ACC/cg.txt")"
```
Expected:
- `home.total` is a dollar amount (no `≈`, because BTC and LTC are zero balances).
- Every row shows its USD value and a `▲`/`▼` change.
- All three comparisons print `PASS` (within 1 %).
- If `cg.py` finds no JSON on the Chrome page, **[OWNER]** reads the three prices on coingecko.com on the phone, and the controller runs `pct.py` with them.

- [ ] **Step 11: Send: "≈ $" on the form and on Confirm; cancel without sending (spec §8.3)**

```bash
source "$SCRATCH/m1d2-accept/env.sh"
ui tap home.row.DGB && ui wait asset.send 60
ui tap asset.send && ui wait send.address 60
ui tap send.address && adb -s "$D" shell input text "$MULE"
ui waittext send.address 'Address OK' 30
ui tap send.amount && adb -s "$D" shell input text 0.05
ui text send.usd
ui tap send.next && ui wait confirm.usd.amount 120
for f in amount fee total; do ui text confirm.$f; ui text confirm.usd.$f; done
ui secureshot "$ACC/06-confirm-blank.png"
ui tap confirm.back && ui wait send.next 30
adb -s "$D" shell input keyevent KEYCODE_BACK
ui wait asset.send 30 && adb -s "$D" shell input keyevent KEYCODE_BACK
ui wait home.total 30
```
Expected:
- `send.usd` is `≈ $0.000…` (0.05 × the price).
- Confirm shows `0.05 DGB`, a fee and a total, each with its `≈ $` line, and the capture is blank (FLAG_SECURE).
- Back returns to the form, and nothing is sent: no new history row.

- [ ] **Step 12: No network: the price fields degrade, the wallet still works, prices come back (spec §8.4)**

```bash
source "$SCRATCH/m1d2-accept/env.sh"
adb -s "$D" shell cmd connectivity airplane-mode enable
pause 5
ui text home.total; ui text home.row.DGB.balance
ui tap home.row.DGB && ui wait asset.tx.0 60 && ui text asset.tx.0
ui tap asset.receive && ui wait receive.address 60 && echo "receive works offline"
adb -s "$D" shell input keyevent KEYCODE_BACK && ui wait asset.list 30
adb -s "$D" shell input keyevent KEYCODE_BACK && ui wait home.total 30
```
Expected:
- The total and the balances are still shown (the last good prices).
- History shows the deposit, and Receive shows the address.

Prices go stale more than 15 minutes after the last success. The app stays in front on Home; the screen timeout is 30 min (Step 6). Run this with `run_in_background` and wait for it:

```bash
source "$SCRATCH/m1d2-accept/env.sh"
ui wait price.stale 1260
```
Then:

```bash
source "$SCRATCH/m1d2-accept/env.sh"
ui text price.stale; ui text home.total; shot 07-offline-stale
adb -s "$D" shell cmd connectivity airplane-mode disable
ui gone price.stale 300 && ui text home.total && shot 08-prices-back
```
Expected:
- `present` within about 15–18 minutes.
- `Prices as of HH:MM`, with HH:MM the time of the last success before airplane mode.
- After airplane mode is off, `gone` within about 3 minutes (the next poll), and the total updates.
- If the total showed `Price unavailable` instead (no price had been fetched yet), record that: it is the other accepted outcome.

- [ ] **Step 13: R3-2: "Use password" on an opt-in prompt; then turn fingerprint unlock on (spec §8.6)**

a. **The refusal.**

```bash
source "$SCRATCH/m1d2-accept/env.sh"
ui tap home.lock && ui wait locked.password 30
ui checked locked.enableBiometrics          # false: tap it once
ui tap locked.enableBiometrics && ui checked locked.enableBiometrics   # true
ui tap locked.password && type_throwaway "$PW"
```
**STOP. [CONTROLLER]** Tell the owner: "A fingerprint prompt will appear. Do **not** touch the sensor. Tap **Use password** on it." Continue after the owner's go:

```bash
source "$SCRATCH/m1d2-accept/env.sh"
adb -s "$D" logcat -c
ui tap locked.submit
txt wait 'turned on' 60 | tee "$ACC/r32a-notice.txt"
adb -s "$D" logcat -d -v epoch > "$ACC/logcat-r32a.txt"
python3 "$ACC/r32.py" "$ACC/logcat-r32a.txt"
ui wait home.total 30 && shot 09-r32-notice
```
Expected:
- Home appears.
- The notice "Fingerprint unlock wasn't turned on…" is seen (`seen after N s`).
- `r32.py` prints `PASS`: about 1 s from the prompt closing to the app answering. In 0.3.1 the notice came 24.6 s after the cancel.
- If `r32.py` says `TIMED OUT`, the lifecycle signal did not arrive on this device. Record **R3-2: FAIL, fallback timeout**; the spec accepts that fallback.

b. **Turn fingerprint unlock on for the read check.**

```bash
source "$SCRATCH/m1d2-accept/env.sh"
ui tap home.lock && ui wait locked.password 30
ui wait locked.biometric 3; echo "fingerprint button: exit=$?"     # exit=1: still off
ui checked locked.enableBiometrics          # false: tap it once
ui tap locked.enableBiometrics && ui checked locked.enableBiometrics   # true
ui tap locked.password && type_throwaway "$PW"
```
**STOP. [CONTROLLER]** Tell the owner: "A fingerprint prompt will appear. **Touch the sensor** (the power button)." Continue after the owner's go:

```bash
source "$SCRATCH/m1d2-accept/env.sh"
ui tap locked.submit
ui wait home.total 60
txt wait 'turned on' 40; echo "refusal notice: exit=$?"            # exit=1: none
```
Expected: Home, and no refusal notice. `legacy3` now has fingerprint unlock on. Record it in SECRETS-INDEX.md: "legacy3: fingerprint on since M1-D2 acceptance".

- [ ] **Step 14: R3-2 on the first read after a cold start; S3-2 across a cold start**

```bash
source "$SCRATCH/m1d2-accept/env.sh"
kill_app && adb -s "$D" logcat -c && launch
ui wait signin.biometric 120
ui text signin.wallet                       # legacy3 (S3-2)
```
**STOP. [CONTROLLER]** Tell the owner: "A fingerprint prompt will appear. Do **not** touch the sensor. Tap **Use password**." Continue after the owner's go:

```bash
source "$SCRATCH/m1d2-accept/env.sh"
adb -s "$D" logcat -c
ui tap signin.biometric
txt wait 'Use password' 30 > /dev/null; echo "prompt shown: exit=$?"
```
After the owner reports that they tapped "Use password":

```bash
source "$SCRATCH/m1d2-accept/env.sh"
pause 3
adb -s "$D" logcat -d -v epoch > "$ACC/logcat-r32c.txt"
python3 "$ACC/r32.py" "$ACC/logcat-r32c.txt"
ui enabled signin.password                  # true
ui tap signin.password && type_throwaway "$PW"
ui tap signin.submit && ui wait home.total 180
scan_log 02-r32
```
Expected:
- `signin.wallet` is `legacy3` after the cold start.
- `r32.py` prints `PASS`: about 1 s. In 0.3.1 the same path waited out the full 30 s.
- The password field is enabled, the sign-in works, and the log is clean.

- [ ] **Step 15: S3-2: after a sign-out, sign-in preselects `legacy3` (spec §8.7)**

```bash
source "$SCRATCH/m1d2-accept/env.sh"
ui tap home.menu && pause 1 && ui tap home.signOut
ui wait signin.password 60
ui text signin.wallet && shot 10-signin-preselect
```
Expected: `legacy3`, not the first wallet in the list. (Step 7 showed which wallet the list puts first.)

- [ ] **Step 16: Network endpoints from a cold start; the final log scan; restore the screen timeout (spec §8.8)**

Start the sampler with `run_in_background`:

```bash
source "$SCRATCH/m1d2-accept/env.sh"
kill_app && python3 "$ACC/conns.py" 150 > "$ACC/conns.txt"
```
While it runs (within 10 s of starting it):

```bash
source "$SCRATCH/m1d2-accept/env.sh"
launch && ui wait signin.password 120
ui tap signin.password && type_throwaway "$PW"
ui tap signin.submit && ui wait home.total 180
```
When the sampler has finished:

```bash
source "$SCRATCH/m1d2-accept/env.sh"
cat "$ACC/conns.txt"
for h in api.binance.com api.binance.us api.coinpaprika.com defistats.gleec.com; do
  getent ahosts "$h" | awk -v h="$h" '{print $1, h}' | sort -u
done > "$ACC/forbidden.txt"
awk 'NR==FNR{bad[$1]=$2; next} ($1 in bad){print "FORBIDDEN", $0, bad[$1]}' \
  "$ACC/forbidden.txt" "$ACC/conns.txt"; echo "forbidden check done"
adb -s "$D" logcat -d | grep -ciE 'binance|coinpaprika|gleec' ; true
scan_log 03-final
adb -s "$D" shell settings put system screen_off_timeout 60000
adb -s "$D" shell settings get system screen_off_timeout      # 60000
```
Expected:
- Every line of `conns.txt` is one of:
  - an electrum server (`50002`, `20059`, and the BTC/LTC electrums' ports);
  - KDF's seed node, `seed1.digiscope.me`;
  - a port 443 endpoint for CoinGecko (Cloudflare).
- No `FORBIDDEN` line. The log grep counts `0`.
- `logcat secret scan: clean`, and the screen timeout is back at `60000`.
- If `/proc/net` is unreadable (`cannot read`), record that. The proof then rests on `sdk_bootstrap_test.dart` ("no SDK market data at all") and the log grep.
- A 443 address shared with CoinPaprika's Cloudflare range is not proof of CoinPaprika traffic. Record it with the host from `forbidden.txt`.

- [ ] **Step 17: Record the results in `docs/release.md`**

Append this section to `~/digibyte-dex/digibyte-wallet/docs/release.md`. Fill each Result with PASS or FAIL and a short note from Steps 7–16.

```markdown
## M1-D2 acceptance (0.4.0)

Moto G 5G (2023) `ZY22HVMNKZ`, Android 14. Release AAB versionCode <VC>, installed from Play internal testing (`installer=com.android.vending`). Acceptance wallet `legacy3` (throwaway, restored from `m1c-iguana-seed`).

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Home: USD total; per-coin USD and 24 h change; unit prices within 1 % of CoinGecko (DGB / BTC / LTC diffs) | | `05-home-usd.png`, `pct.py` |
| 2 | Asset detail (DGB): USD value, unit price, 24h / 7d / 30d sparklines | | `04-chart-*.png` |
| 3 | Send: "≈ $" on the form and on Confirm; cancelled, nothing sent | | `06-confirm-blank.png` |
| 4 | No network: balances, history, Receive work; "Prices as of HH:MM" after N min; prices back N min after airplane off | | `07`, `08` |
| 5 | R3-1: received deposit (0.1 DGB, fund txid …) shown Pending with no 1969 date; mined row shows its time | | `r31-rows.txt`, `02`, `03` |
| 6 | R3-2: "Use password" on the opt-in prompt: notice after N s (`r32.py` N s); on the first read after a cold start: password field after N s | | `09`, `r32.py` |
| 7 | S3-2: preselects `legacy3` after a cold start and after a sign-out | | `10-signin-preselect.png` |
| 8 | Network: no Binance, CoinPaprika or Gleec endpoint; logcat secret scan clean | | `conns.txt`, scan outputs |

Notes: <the first-run preselection from Step 7; any retry; anything recorded instead of a PASS>.
```

```bash
cd ~/digibyte-dex/digibyte-wallet
git add docs/release.md
git commit -m "docs(release): M1-D2 on-device acceptance (0.4.0)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013dAwo7HnLRmU8RYxtjHFGD"
```

- [ ] **Step 18: Push, open the PR, and wait for CI**

```bash
export SCRATCH=<this session's scratchpad>
cd ~/digibyte-dex/digibyte-wallet
bash tool/secret_scan.sh                                   # secret scan: clean
git ls-files | grep -Ei '\.jks$|\.p8$|key\.properties$|service-account' || echo "no secret files tracked"
git push -u origin feat/m1d2-prices-usd
cat > "$SCRATCH/m1d2-accept/pr-body.md" <<'EOF'
M1-D2 "Prices and USD" for DigiByte DEX 0.4.0.

- USD prices from CoinGecko through the app's own small client (exact decimals from the JSON text, typed failures, 10 s timeout, no key, nothing about the wallet sent). The base URL is `Brand.priceApiBase`, so a proxy can replace it later.
- A price service polled every 3 minutes only while signed in, unlocked and in front; backoff 3 → 30 min on 429/5xx; stale after 15 min; a disk copy for the first paint; a 10-minute chart cache.
- Home: portfolio USD total (exact, "≈ … excludes BTC", or "Price unavailable"), each coin's USD value and 24 h change, "Prices as of HH:MM" when stale.
- Asset detail: USD value, unit price, and a 24h / 7d / 30d sparkline (custom painter).
- Send and Confirm: display-only "≈ $"; the signed preview stays the only source of truth.
- The SDK's market data is fully off (no Binance, CoinPaprika, CoinGecko or Komodo provider; no startup coin-list downloads).
- M1-D1 follow-ups: R3-1 a mempool receive shows Pending instead of "Dec 31, 1969"; R3-2 "Use password" on the fingerprint prompt answers within about 1 s; S3-2 sign-in preselects the wallet signed in last.

On-device acceptance: see `docs/release.md` → "M1-D2 acceptance (0.4.0)".

Plan: `Digi-Dex-Komodo/docs/superpowers/plans/2026-10-08-m1d2-prices-usd.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
gh pr create -R JohnnyLawDGB/digibyte-wallet --base main --head feat/m1d2-prices-usd \
  --title "M1-D2: prices and USD (CoinGecko), R3-1, R3-2, S3-2 — 0.4.0" \
  --body-file "$SCRATCH/m1d2-accept/pr-body.md"
gh pr checks --watch -R JohnnyLawDGB/digibyte-wallet "$(gh pr view feat/m1d2-prices-usd -R JohnnyLawDGB/digibyte-wallet --json number -q .number)"
```
Expected: `secret-scan`, `analyze-test`, `build-android` and `build-ios` are green.

**Stop here.** Report the PR URL and the acceptance table. The controller merges after its final review with `gh pr merge feat/m1d2-prices-usd --merge -R JohnnyLawDGB/digibyte-wallet`.

## Open questions for the owner

1. **R3-2 and the 30 s backstop.** "Use password" now answers within about 1 s, but a prompt that is simply ignored still times out after 30 s and stays on screen; that was the 0.3.1 R3 case. Should the backstop grow, for example to 2 minutes, so that a slow touch is not cut off, now that "Use password" no longer depends on it?
2. **Unit-price format (departure 1).** Is "1 DGB = $0.012345" (6 significant digits below $1) right, rather than the §4.4 table's "$0.01"?
3. **Prices during system prompts (departure 3).** Polling keeps running while only `inactive` (a fingerprint prompt or the notification shade). Is that acceptable?
