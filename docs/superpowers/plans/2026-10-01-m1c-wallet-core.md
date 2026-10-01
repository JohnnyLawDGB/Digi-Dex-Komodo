# M1-C: Wallet Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the Moto, a user of **DigiByte DEX** can:
- create a 24-word wallet and pass the backup quiz, or restore one (HD, or legacy iguana from the old app);
- unlock with a password or biometrics, with auto-lock and the wrong-password lockout enforced;
- see DGB/BTC/LTC balances;
- receive with a QR code, copy, share and a new address.

**Architecture:**
- Two small SDK-fork patches, pushed to `digibyte/main` and pinned by the app submodule:
  - `KomodoDefiSdkConfig.mnemonicWordCount` → KDF `word_count`, so KDF generates the 24-word seed;
  - `HdGapLimit.software` = 20 (BIP-44).
- App layering per spec §4.2: pages → cubits/blocs → app-owned repositories (`abstract interface class` + `Sdk*` implementation + hand-written fakes) → SDK managers.
- Pure policy code lives in `lib/domain/` (password, lockout, wallet name, seed phrase/validator).
- "Signed out" means no KDF wallet session; "locked" is a UI state above a running session (`LockCubit`). `authRedirect(auth, lock, location)` stays a pure function.
- Small persisted app state (lockout, backup-pending, biometric markers) goes through one `KeyValueStore` in its own secure-storage namespace. The biometric password lives in a second, biometric-bound namespace.

**Tech Stack:**
- Flutter 3.41.4 (fvm), Dart ≥3.9, flutter_bloc 9.1.1, go_router 17.5.0, equatable, decimal, very_good_analysis 10.2.0, gen_l10n.
- New direct dependencies: `flutter_secure_storage: ^10.3.4`, `local_auth: ^2.3.0`, `qr_flutter: ^4.1.0`, `share_plus: ^11.1.0`, plus the existing path package `komodo_defi_local_auth`.
- Tests: flutter_test, bloc_test 10, mocktail 1.0.

**Spec:** `docs/superpowers/specs/2026-09-27-digibyte-wallet-design.md`:
- §4.2 app layering; §5.1 onboarding, unlock, portfolio and receive;
- §8.1 secrets and biometric unlock; §8.2 screen protection, auto-lock, lockout and clipboard; §9 testing.

**Binding design decisions:** `.superpowers/research/m1c-design-notes.md` (every decision there is final). SDK facts with citations: `.superpowers/research/m1c-sdk-api.md`. Both paths are relative to `~/Digi-Dex-Komodo`.

**Execution:** the owner chose **subagent-driven** execution (superpowers:subagent-driven-development). One fresh implementer per task, one fresh reviewer per task, a whole-branch review before the PR is merged.

### Where this plan departs from the task list or the design notes, and why

These follow from reading the real code. Nothing else is re-decided.

1. **`validateMnemonic(isHd:false, allowCustomSeed:false)` does not return field-level reasons.** `MnemonicValidator.validateMnemonic` (`komodo_defi_types/lib/src/utils/mnemonic_validator.dart:79-87`) turns both `invalidWord` and `invalidChecksum` into `customNotAllowed`. Only `empty` and `invalidLength` pass through. So `SdkSeedValidator` still calls exactly that method (design note 4), and when it gets `customNotAllowed` it loads the SDK's own bundled BIP39 list (`packages/komodo_defi_types/assets/bip-0039/english-wordlist.txt`) to tell "word N is not a seed word" from "bad checksum".
2. **Legacy custom seeds are not lower-cased.** An iguana key is a hash of the exact passphrase text, so lower-casing a non-BIP39 legacy seed would derive a different, empty wallet. Normalisation (lower-case, trim, collapse whitespace) is applied for validation and whenever the phrase is valid BIP39. A legacy seed that is *not* BIP39 is sent to KDF verbatim, with only its outer whitespace trimmed (`SeedPhrase.verbatim`). It still needs at least 12 words. The old app passed the field text through unchanged (`Digi-Dex-Komodo/lib/screens/settings/restore_seed_page.dart:226`).
3. **`AssetManager` and `PubkeyManager` are not exported by `komodo_defi_sdk`,** so they cannot be mocked from app tests without `implementation_imports`. `SdkAssetsRepository` and `SdkReceiveRepository` therefore take a small "ports" object built from the SDK (`AssetsSdkPorts.of(sdk)`, `ReceiveSdkPorts.of(sdk)`), and their tests fake the ports. `SdkWalletRepository` still mocks `KomodoDefiSdk` and `KomodoDefiLocalAuth`, which are exported.
4. **`InMemoryKeyValueStore` lives in `test/support/`, not `lib/`.** `komodo_defi_sdk` already exports a class with that name (`activation_config_service.dart:156`), so a `lib/` class would make every file importing both ambiguous. It is test-only anyway.
5. **`PendingBackupSession` is created in Task 8**, as listed. `LockCubit` (Task 6) takes a generic `onLocked` callback, which `main.dart` wires to `session.clear` in Task 8.
6. **The restore page is a `SecureScreen` and its seed field is hidden by default.** This extends spec §8.2 ("screenshots blocked on seed screens") to seed entry. It is also what keeps the seed out of acceptance screenshots and `uiautomator` dumps (Task 14).
7. **Every interactive widget is wrapped in `Tagged(id)`** (`Semantics(identifier: id, container: true)`), with the same string as its `Key`. Android reports the identifier as the node's `resource-id`, so the acceptance script can address widgets with `uiautomator dump`.
8. **Biometric prompt texts are fixed English in `DeviceBiometricStore.androidOptions`** (design note 9). Android binds them when the storage namespace is first opened, before any `BuildContext` exists. They are the one exception to "all strings in ARB". The `local_auth` reason string *is* localised (passed in from the page).
9. **very_good_analysis `avoid_redundant_argument_values`:** arguments equal to the default are omitted. That covers `allowCustomSeed: false` (validator), `resetOnError: true` (biometric options) and `synchronizable: false` (iOS options). Tests assert the effective values instead.
10. **Wallet names** must match `^[A-Za-z0-9 _-]{1,32}$`. KDF's own rule (`kdf/mm2src/mm2_main/src/lp_wallet/mnemonics_storage.rs:22-35`) is "alphanumeric, space, dash, underscore". This is a new pure `WalletNamePolicy`, added to Task 3 with the other policies.
11. **The lock state is `AppLockState`** (`Unlocked`, `Locked`). Flutter's `widgets.dart` already exports a `LockState`, and the clash is an `ambiguous_import` error in `router.dart`.
12. **`AssetsRepository.listed()` returns app-level `ListedAsset(ticker, name)`**, not SDK `Asset`s, so pages and fakes never construct SDK types. The design note's `AssetActivationView` and `BalanceView` names are kept.
13. **A biometric success is allowed during a wrong-password lockout and resets it.** It proves the owner, and the lockout exists to slow password guessing. The design notes are silent on this; it is listed as an open question for the owner.

**Pre-verification:** the code in Tasks 1–13 was applied to a scratch copy of both repos on 2026-10-01. `fvm flutter analyze` reported no issues after `fvm dart format`, and all 225 app tests passed. The full suites of the five touched SDK packages passed. A debug APK built (Kotlin included), and `tool/check_permissions.sh` passed. Executors still follow every TDD step; a deviation from the expected output is a real finding.

### Known gaps (accepted for M1-C)

- **iOS screenshot blocking on seed screens** is deferred to the iOS pass on the owner's Mac (design note 11). `setSecure` is a no-op on iOS: the channel returns `notImplemented`, and Dart ignores the `MissingPluginException`. The Flutter privacy overlay covers the iOS app switcher.
- **Gboard keeps its own clipboard history.** The app clears the system clipboard (spec §8.2). It cannot reach a keyboard's private history.

## Global Constraints

- **Identity:**
  - App name **DigiByte DEX**. Android `applicationId` and iOS bundle ID **`me.digiscope.wallet`**; this can never change.
  - Dart package name `digibyte_dex`; every app import is `package:digibyte_dex/...`.
  - The M0 probe (`me.digiscope.wallet.m0`) stays untouched.
- **Network:** netid `2014`, seed nodes `['seed1.digiscope.me']`, set only in `lib/config/brand.dart` and passed through `KomodoDefiSdkConfig.network`.
- **Assets:**
  - Listed wallet assets are exactly the legacy P2PKH tickers `DGB`, `BTC`, `LTC` (`Brand.listedAssets`); DGB is pinned first.
  - Every other coin config is marked `excluded` by `assetConfigTransform`. Segwit variants stay hidden.
  - `defaultAssets` does not activate anything; the app activates the listed assets itself after sign-in.
- **No Gleec or Komodo services at runtime:**
  - `MarketDataConfig(enableKomodoPrice: false)`;
  - coin-config auto-update off;
  - no fallback to GLEECBTC coin configs.
- **Toolchain:**
  - Flutter `3.41.4` via `.fvmrc`; always `fvm flutter` / `fvm dart`.
  - `very_good_analysis` 10.2.0 with `public_member_api_docs` off. `fvm flutter analyze` must report **no issues**: infos are fatal, and that includes `lines_longer_than_80_chars`, `discarded_futures`, `avoid_redundant_argument_values`, `one_member_abstracts`, `only_throw_errors` and `avoid_catching_errors`.
  - Run `fvm dart format lib test` before every analyze. The formatter does not wrap comments or string literals, so keep those under 80 columns by hand. Any remaining lint is fixed without changing behaviour.
  - After changing `app_en.arb`, run `fvm flutter gen-l10n`. The generated `lib/l10n/gen/` is gitignored.
- **Platforms:**
  - Android: minSdk 28, targetSdk 35, 16 KB page alignment. Permissions are only `INTERNET`, `CAMERA` and `USE_BIOMETRIC` (`USE_FINGERPRINT` stays removed). `allowBackup="false"`, `usesCleartextTraffic="false"`.
  - iOS: 13+, `PrivacyInfo.xcprivacy`, app data excluded from iCloud backup, ATS defaults kept.
- **Secrets:**
  - Signing material, Play credentials and test-wallet seeds and passwords live only in `~/.config/dgb-dex/` (mode 600) and are never committed or echoed.
  - **Never log or print seed words or passwords**: not in app code (`debugPrint`, `toString`, exceptions), not in commands, not in test names, expectations or failure messages.
    - App states, value objects and exceptions that hold seed words override Equatable's `stringify` (it defaults to *true* in debug and test runs) or `toString`, so a failing `expect` cannot print them.
    - Test fixtures use public BIP39 vectors or obvious dummies (`word1`…`word24`, `Correct-Horse-9`).
  - Seed words only ever appear on the backup screens (reveal and quiz). They are never copyable and never held outside `BackupCubit` and the KDF call that returns them.
  - The wallet password is held in memory only by `PendingBackupSession` (create → backup) and by the call stack of the cubit method using it. It is persisted only in the biometric-bound store.
- **Strings:** every user-facing string is in `lib/l10n/arb/app_en.arb` and is read through `context.l10n`. The only exceptions are the biometric prompt texts (departure 8) and numeric formatting such as `'$n.'`.
- **Code style:** match the existing app:
  - `abstract interface class` repositories, with `Sdk*` implementations and fakes under `test/support/`;
  - sealed `Equatable` states;
  - `unawaited(...)` for fire-and-forget futures;
  - `on Object catch` (never a bare `catch`, never `on SomeError`).
- **Devices:** the Moto `ZY22HVMNKZ` only, always addressed as `adb -s ZY22HVMNKZ`. Never touch the Note 8 `ce061716640b191c017e`. Never run `adb kill-server` or otherwise restart adb.
- **Commit trailer rule:** every commit message ends with a blank line and then exactly these two lines:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb
  ```
  The commit commands below produce this with a second `-m`.
- **Work branches:**
  - App tasks (2–14) commit on branch **`feat/m1c-wallet-core`** in `~/digibyte-dex/digibyte-wallet` (default branch `main`).
  - The SDK task (1) commits in `~/digibyte-dex/sdk` on **`digibyte/main`**. That branch is protected against force-push and deletion, so push normally.
- **PR:** one PR for `feat/m1c-wallet-core` → `main`, opened in Task 14. After the final whole-branch review, the **controller** merges it with `gh pr merge --merge`. Implementers never merge.
- **Swaps and spending:** M1-C has no send and no swap. On-device acceptance never spends funds.
- **Scratch files:** `$SCRATCH` means the executing session's scratchpad directory (Claude Code lists it as "Scratchpad directory"). Put `export SCRATCH=<that path>` at the start of any command block that uses it. Never use other `/tmp` paths.
- **Waiting:** foreground `sleep` is blocked in Claude Code. Waits over a few seconds run as a background `sleep N` whose completion you wait for. Task 14's helper provides `pause N` (at most 10 s) for short UI settles.

## Review Focus

1. **A seed pasted with extra spaces, tabs, newlines, non-breaking spaces or capitals** must be accepted and registered in canonical BIP39 form, not rejected or registered as typed.
   - Task 3 `seed_validator_test.dart`: "a messy paste of a valid seed is accepted normalized".
   - Task 10 `restore_wallet_cubit_test.dart`: "a messy paste reaches the repository normalized".
2. **An old-app (iguana) seed restored, then signed in again later**, must stay iguana. The SDK's `signIn` default would silently rewrite it to HD and show an empty wallet.
   - Task 5 `sdk_wallet_repository_test.dart`: "a restored iguana wallet signs in as iguana", plus the `getUsers` fallback.
3. **The app is killed mid-backup**, losing the in-memory password. The next sign-in must land on the backup flow, ask for the password, and still require the quiz.
   - Task 4 `backup_status_store_test.dart`: "pending survives a restart until cleared".
   - Task 6 `auth_cubit_test.dart`: "a pending backup survives an app restart".
   - Task 9 `backup_cubit_test.dart`: "after a restart the password is asked first".
   - Task 9 `app_test.dart`: "a pending backup after restart forces the backup page".
4. **Biometrics re-enrolled**, so the Keystore key is invalidated and the read throws. The entry must be cleared, the user must fall back to the password, and re-enabling must be offered and must work.
   - Task 4 `device_biometric_store_test.dart`: "re-enrolled biometrics clear the entry".
   - Task 11 `unlock_cubit_test.dart`: "re-enrolled biometrics fall back to the password and can be re-enabled".
5. **The wrong-password lockout must survive an app kill.** It must not reset when the process restarts.
   - Task 4 `lockout_store_test.dart`: "a lockout survives an app restart (new store instance)".
   - Task 11 `password_attempts_test.dart`: "the lockout survives a restart and ends on time"; `sign_in_cubit_test.dart`: "the lockout survives a restart".

Also pinned, though less likely to be missed:
- a wrong password at unlock never stops KDF or signs out (Tasks 5 and 11);
- the clipboard is cleared only if it still holds the address (Task 13);
- one asset failing to activate leaves the others usable (Task 12).

---

### Task 1: SDK fork — `mnemonicWordCount` → KDF `word_count`, and `HdGapLimit.software` = 20

**Repo:** `~/digibyte-dex/sdk`, branch `digibyte/main`. Mirror how fork commit `dae9dda0` threaded `network` (`git show dae9dda0 cf40ccdf`).

**Files:**
- Modify: `packages/komodo_defi_framework/lib/src/config/kdf_startup_config.dart` (`_` ctor, fields, `generateWithDefaults`, `noAuthStartup`, `encodeStartParams`)
- Modify: `packages/komodo_defi_local_auth/lib/src/auth/auth_service.dart:175-188` (ctor + field)
- Modify: `packages/komodo_defi_local_auth/lib/src/auth/auth_service_kdf_extension.dart:481-516` (`_generateStartupConfig`)
- Modify: `packages/komodo_defi_local_auth/lib/src/komodo_defi_local_auth.dart:363-372` (ctor)
- Modify: `packages/komodo_defi_sdk/lib/src/bootstrap.dart:~165` (auth registration)
- Modify: `packages/komodo_defi_sdk/lib/src/sdk/komodo_defi_sdk_config.dart` (field, ctor, `copyWith`)
- Modify: `packages/komodo_defi_types/lib/src/public_key/hd_gap_limit.dart:35-41`
- Test: `packages/komodo_defi_sdk/test/sdk_config_mnemonic_word_count_test.dart` (create)
- Test: `packages/komodo_defi_local_auth/test/src/kdf_network_startup_test.dart` (add two tests)
- Test: `packages/komodo_defi_types/test/hd_gap_limit_test.dart` (update two tests)
- Test: `packages/komodo_defi_rpc_methods/test/src/common_structures/activation/gap_limit_on_the_wire_test.dart` (update two tests)

**Interfaces:**
- Consumes: nothing from this plan.
- Produces, for Task 2:
  - `KomodoDefiSdkConfig({..., int? mnemonicWordCount})`, `final int? mnemonicWordCount`, and `copyWith(mnemonicWordCount:)`. Null keeps KDF's default of 12.
  - `KomodoDefiLocalAuth({..., int? mnemonicWordCount})` and `KdfAuthService(kdf, hostConfig, {..., int? mnemonicWordCount})`.
  - `KdfStartupConfig.generateWithDefaults({..., int? wordCount})` and `final int? wordCount`. `encodeStartParams()` emits `'word_count': wordCount` only when it is non-null.
  - `HdGapLimit.software == 20`. `hardware` (20) and `newlyGeneratedFirstSignIn` (1) are unchanged.
  - Env line `SDK_SHA_M1C=<sha>` in `~/.config/dgb-dex/kdf-release.env`.

- [ ] **Step 1: Sync, and record a test baseline for the five packages you will touch**

```bash
cd ~/digibyte-dex/sdk
git status --short   # must be empty
git checkout digibyte/main && git pull --ff-only origin digibyte/main
git log --oneline -1   # expect bcd07f4e or a descendant
B="$SCRATCH/m1c-sdk" && mkdir -p "$B"
for p in komodo_defi_types komodo_defi_rpc_methods komodo_defi_framework komodo_defi_local_auth komodo_defi_sdk; do
  (cd packages/$p && fvm flutter test > "$B/baseline-$p.txt" 2>&1; echo "$p exit=$?")
done
git checkout -- packages/komodo_defi_framework/app_build/build_config.json 2>/dev/null; true
```
Expected: an `exit=` line per package. Keep the files. Step 5 compares against them, so pre-existing failures are not blamed on this task.

- [ ] **Step 2: Write the failing tests**

Create `packages/komodo_defi_sdk/test/sdk_config_mnemonic_word_count_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';

void main() {
  test('mnemonic word count defaults to KDF and survives copyWith', () {
    const c = KomodoDefiSdkConfig();
    expect(c.mnemonicWordCount, isNull);
    final c24 = c.copyWith(mnemonicWordCount: 24);
    expect(c24.mnemonicWordCount, 24);
    expect(c24.copyWith().mnemonicWordCount, 24);
  });
}
```

In `packages/komodo_defi_local_auth/test/src/kdf_network_startup_test.dart`, add these two tests at the end of `main()`, after `'default network is unchanged (6133)'`. They reuse the file's `_StartupKdfOperations` fake and its `setUp`, which stores `test-wallet`.

```dart
  test('wallet creation asks KDF for the configured word count', () async {
    final hostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');
    final operations = _StartupKdfOperations(
      noAuthResult: KdfStartupResult.ok,
      walletResult: KdfStartupResult.initError,
    );
    final service = KdfAuthService(
      KomodoDefiFramework.createWithOperations(
        hostConfig: hostConfig,
        kdfOperations: operations,
      ),
      hostConfig,
      mnemonicWordCount: 24,
    );
    addTearDown(service.dispose);

    await expectLater(
      service.register(
        walletName: 'new-wallet',
        password: 'Qz7!sentinel-Wv4#',
        options: const AuthOptions(
          derivationMethod: DerivationMethod.hdWallet,
          allowWeakPassword: true,
        ),
      ),
      throwsA(isA<AuthException>()),
    );

    final walletStarts = operations.startParams
        .where((p) => p.containsKey('wallet_password'))
        .toList();
    expect(walletStarts, isNotEmpty);
    for (final params in walletStarts) {
      expect(params['word_count'], 24);
      expect(params.containsKey('passphrase'), isFalse);
    }
  });

  test('word_count is omitted unless configured', () async {
    final hostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');
    final operations = _StartupKdfOperations(
      noAuthResult: KdfStartupResult.ok,
      walletResult: KdfStartupResult.initError,
    );
    final service = KdfAuthService(
      KomodoDefiFramework.createWithOperations(
        hostConfig: hostConfig,
        kdfOperations: operations,
      ),
      hostConfig,
    );
    addTearDown(service.dispose);

    await expectLater(
      service.signIn(
        walletName: 'test-wallet',
        password: 'Qz7!sentinel-Wv4#',
        options: const AuthOptions(
          derivationMethod: DerivationMethod.hdWallet,
          allowWeakPassword: true,
        ),
      ),
      throwsA(isA<AuthException>()),
    );

    expect(operations.startParams, isNotEmpty);
    for (final params in operations.startParams) {
      expect(params.containsKey('word_count'), isFalse);
    }
  });
```

In `packages/komodo_defi_types/test/hd_gap_limit_test.dart`, replace the test `'a software wallet uses the reduced gap'` with:

```dart
    test('a software wallet uses the full BIP-44 gap', () {
      expect(
        HdGapLimit.resolve(
          privKeyPolicy: software,
          isNewlyGeneratedFirstSignIn: false,
        ),
        20,
      );
    });
```

and replace `'the three tiers are ordered and distinct'` with:

```dart
    test('only a wallet generated this session narrows the gap', () {
      expect(
        HdGapLimit.newlyGeneratedFirstSignIn,
        lessThan(HdGapLimit.software),
      );
      expect(HdGapLimit.software, HdGapLimit.hardware);
    });
```

In `packages/komodo_defi_rpc_methods/test/src/common_structures/activation/gap_limit_on_the_wire_test.dart`:
- in `'the software gap reaches the payload'`, change `expect(params.toRpcParams()['gap_limit'], 3);` to `expect(params.toRpcParams()['gap_limit'], 20);`;
- rename `'a software wallet gets the reduced gap'` to `'a software wallet gets the BIP-44 gap'`, and change *its* `expect(params.gapLimit, 3);` to `expect(params.gapLimit, 20);`.
- Leave `'gap_limit survives a fromJson round trip'` alone. Its `3` is an explicit JSON value, not the software constant.

- [ ] **Step 3: Run the tests and confirm they fail**

```bash
cd ~/digibyte-dex/sdk
(cd packages/komodo_defi_sdk && fvm flutter test test/sdk_config_mnemonic_word_count_test.dart)
(cd packages/komodo_defi_local_auth && fvm flutter test test/src/kdf_network_startup_test.dart)
(cd packages/komodo_defi_types && fvm flutter test test/hd_gap_limit_test.dart)
(cd packages/komodo_defi_rpc_methods && fvm flutter test test/src/common_structures/activation/gap_limit_on_the_wire_test.dart)
```
Expected:
- the first two fail to compile (`mnemonicWordCount` isn't defined);
- the gap tests fail with `Expected: <20> Actual: <3>`.

- [ ] **Step 4: Implement**

`kdf_startup_config.dart`:
- In the private `KdfStartupConfig._({...})` parameter list, add `required this.wordCount,` after `required this.eventStreamingConfiguration,`.
- After the field `final EventStreamingConfiguration? eventStreamingConfiguration;`, add:

```dart
  /// BIP39 word count KDF uses when it generates a new wallet seed
  /// (`word_count`). Null leaves KDF's default (12). KDF only reads it when
  /// it creates a seed, so passing it on sign-in is harmless.
  final int? wordCount;
```

- In `generateWithDefaults({...})`, add the parameter `int? wordCount,` after `EventStreamingConfiguration? eventStreamingConfiguration,`. Add this assert right after the existing `assert(hdAccountId == null, ...)`:

```dart
    assert(
      wordCount == null || const [12, 15, 18, 21, 24].contains(wordCount),
      'word_count must be a BIP39 length (12, 15, 18, 21 or 24)',
    );
```

  Then, in its `return KdfStartupConfig._(`, add `wordCount: wordCount,` after `enableHd: enableHd,`.
- In `noAuthStartup`'s `return KdfStartupConfig._(`, add `wordCount: null,` after `enableHd: false,`.
- In `encodeStartParams()`, add `if (wordCount != null) 'word_count': wordCount,` right after the `if (hdAccountId != null) 'hd_account_id': hdAccountId,` line.

`auth_service.dart`: replace the constructor head and add the field.

```dart
  KdfAuthService(
    this._kdfFramework,
    this._hostConfig, {
    SecureLocalStorage? secureStorage,
    KdfNetworkConfig network = const KdfNetworkConfig(),
    int? mnemonicWordCount,
  }) : _network = network,
       _mnemonicWordCount = mnemonicWordCount,
       _secureStorage = secureStorage ?? SecureLocalStorage() {
```

and, after `final KdfNetworkConfig _network;`:

```dart
  /// `word_count` for seeds KDF generates at registration (null = KDF's 12).
  final int? _mnemonicWordCount;
```

`auth_service_kdf_extension.dart`: in `_generateStartupConfig`, inside `return KdfStartupConfig.generateWithDefaults(`, add `wordCount: _mnemonicWordCount,` after `netid: netId,`.

`komodo_defi_local_auth.dart`: replace the constructor.

```dart
  KomodoDefiLocalAuth({
    required KomodoDefiFramework kdf,
    required IKdfHostConfig hostConfig,
    bool allowRegistrations = true,
    KdfNetworkConfig network = const KdfNetworkConfig(),
    int? mnemonicWordCount,
  }) : _allowRegistrations = allowRegistrations,
       _authService = KdfAuthService(
         kdf,
         hostConfig,
         network: network,
         mnemonicWordCount: mnemonicWordCount,
       ) {
    _trezorAuthService = TrezorAuthService(_authService, TrezorRepository(kdf));
  }
```

`bootstrap.dart`: in the `KomodoDefiLocalAuth(` construction, add `mnemonicWordCount: config.mnemonicWordCount,` after `network: config.network,`.

`komodo_defi_sdk_config.dart`:
- Constructor: add `this.mnemonicWordCount,` after `this.enableAssetAutoUpdate = true,`.
- Field: after `final bool enableAssetAutoUpdate;` add:

```dart
  /// BIP39 word count for seeds KDF generates at wallet creation
  /// (KDF `word_count`). Null keeps KDF's default of 12. Valid values are
  /// 12, 15, 18, 21 and 24.
  final int? mnemonicWordCount;
```

- `copyWith`: add the parameter `int? mnemonicWordCount,` after `bool? enableAssetAutoUpdate,`, and the body entry `mnemonicWordCount: mnemonicWordCount ?? this.mnemonicWordCount,` after the `enableAssetAutoUpdate:` entry.

`hd_gap_limit.dart`: replace the `software` member and its doc comment (lines 35-41) with:

```dart
  /// Software wallets after their first sign-in: the BIP-44 standard gap.
  ///
  /// DigiByte fork: upstream used 3 here to cut node requests on EVM token
  /// fan-out. A DigiByte wallet restores seeds made by other BIP-44 wallets,
  /// whose history can contain longer runs of unused addresses, and a short
  /// gap silently hides those funds. The DigiByte app lists only UTXO coins
  /// (DGB, BTC, LTC), where a probe is one or two electrum requests, so the
  /// full gap is cheap.
  static const int software = 20;
```

- [ ] **Step 5: Run the tests, then the suites, analysis and format**

```bash
cd ~/digibyte-dex/sdk
(cd packages/komodo_defi_sdk && fvm flutter test test/sdk_config_mnemonic_word_count_test.dart)
(cd packages/komodo_defi_local_auth && fvm flutter test test/src/kdf_network_startup_test.dart)
(cd packages/komodo_defi_types && fvm flutter test test/hd_gap_limit_test.dart)
(cd packages/komodo_defi_rpc_methods && fvm flutter test test/src/common_structures/activation/gap_limit_on_the_wire_test.dart)
B="$SCRATCH/m1c-sdk"
for p in komodo_defi_types komodo_defi_rpc_methods komodo_defi_framework komodo_defi_local_auth komodo_defi_sdk; do
  (cd packages/$p && fvm flutter test > "$B/after-$p.txt" 2>&1; echo "$p exit=$?")
  diff <(grep -E '\[E\]|FAILED' "$B/baseline-$p.txt" | sort -u) <(grep -E '\[E\]|FAILED' "$B/after-$p.txt" | sort -u) || echo "CHANGED FAILURES in $p"
done
for p in komodo_defi_types komodo_defi_rpc_methods komodo_defi_framework komodo_defi_local_auth komodo_defi_sdk; do (cd packages/$p && fvm dart analyze .) || echo "ANALYZE $p"; done
fvm dart format packages/komodo_defi_framework/lib/src/config/kdf_startup_config.dart packages/komodo_defi_local_auth/lib packages/komodo_defi_local_auth/test/src/kdf_network_startup_test.dart packages/komodo_defi_sdk/lib/src/bootstrap.dart packages/komodo_defi_sdk/lib/src/sdk/komodo_defi_sdk_config.dart packages/komodo_defi_sdk/test/sdk_config_mnemonic_word_count_test.dart packages/komodo_defi_types/lib/src/public_key/hd_gap_limit.dart packages/komodo_defi_types/test/hd_gap_limit_test.dart packages/komodo_defi_rpc_methods/test/src/common_structures/activation/gap_limit_on_the_wire_test.dart
git checkout -- packages/komodo_defi_framework/app_build/build_config.json 2>/dev/null; true
git status --short
```
Expected:
- the four targeted runs PASS;
- no `CHANGED FAILURES` lines;
- no `ANALYZE` lines, or only issues already present on the baseline;
- `git status` lists only the files in **Files**.

A test outside **Files** that now fails because it asserted the old software gap of 3 is part of this change. Update it to 20 with the BIP-44 reason, and list it in the commit.

- [ ] **Step 6: Commit twice, push, and record the SHA**

```bash
cd ~/digibyte-dex/sdk
git add packages/komodo_defi_framework/lib/src/config/kdf_startup_config.dart \
  packages/komodo_defi_local_auth/lib/src/auth/auth_service.dart \
  packages/komodo_defi_local_auth/lib/src/auth/auth_service_kdf_extension.dart \
  packages/komodo_defi_local_auth/lib/src/komodo_defi_local_auth.dart \
  packages/komodo_defi_local_auth/test/src/kdf_network_startup_test.dart \
  packages/komodo_defi_sdk/lib/src/bootstrap.dart \
  packages/komodo_defi_sdk/lib/src/sdk/komodo_defi_sdk_config.dart \
  packages/komodo_defi_sdk/test/sdk_config_mnemonic_word_count_test.dart
git commit -m "feat(sdk): KomodoDefiSdkConfig.mnemonicWordCount threads KDF word_count" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
git add packages/komodo_defi_types/lib/src/public_key/hd_gap_limit.dart \
  packages/komodo_defi_types/test/hd_gap_limit_test.dart \
  packages/komodo_defi_rpc_methods/test/src/common_structures/activation/gap_limit_on_the_wire_test.dart
git commit -m "feat(types): HdGapLimit.software = 20 (BIP-44) for restored DigiByte wallets" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
git push origin refs/heads/digibyte/main:refs/heads/digibyte/main
echo "SDK_SHA_M1C=$(git rev-parse HEAD)" >> ~/.config/dgb-dex/kdf-release.env
grep -c '^SDK_SHA_M1C=' ~/.config/dgb-dex/kdf-release.env   # expect 1
```
If the push is rejected as non-fast-forward, run `git pull --rebase origin digibyte/main`, rerun Step 5, and push again. Never force-push.

---

### Task 2: App — bump the SDK submodule; 24-word seeds and the asset allowlist in the bootstrap

**Repo:** `~/digibyte-dex/digibyte-wallet`. Create the work branch here.

**Files:**
- Modify: `third_party/komodo-defi-sdk-flutter` (submodule pointer → `SDK_SHA_M1C`)
- Modify: `app/lib/bootstrap/sdk_bootstrap.dart`
- Test: `app/test/bootstrap/sdk_bootstrap_test.dart` (rewrite; renames the misleading test)

**Interfaces:**
- Consumes: `KomodoDefiSdkConfig.mnemonicWordCount` (Task 1); `AssetConfigTransform` (`Map<String, dynamic> Function(Map<String, dynamic>)`, exported by `komodo_defi_sdk`).
- Produces:
  - `const int seedWordCount = 24;`
  - `Map<String, dynamic> listedAssetsOnly(Map<String, dynamic> config)`
  - `KomodoDefiSdkConfig buildSdkConfig()`, now with `mnemonicWordCount: 24` and `assetConfigTransform: listedAssetsOnly`.

- [ ] **Step 1: Branch and bump the submodule**

```bash
cd ~/digibyte-dex/digibyte-wallet
git status --short   # must be empty
git checkout main && git pull --ff-only
git checkout -b feat/m1c-wallet-core
source ~/.config/dgb-dex/kdf-release.env
git -C third_party/komodo-defi-sdk-flutter fetch origin digibyte/main
git -C third_party/komodo-defi-sdk-flutter checkout "$SDK_SHA_M1C"
git -C third_party/komodo-defi-sdk-flutter log --oneline -2   # the two Task 1 commits
cd app && fvm flutter pub get
```
Expected: `pub get` resolves.

- [ ] **Step 2: Write the failing test.** Replace `app/test/bootstrap/sdk_bootstrap_test.dart` with:

```dart
import 'package:digibyte_dex/bootstrap/sdk_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final c = buildSdkConfig();

  test('network is DigiByte 2014 with explicit seeds', () {
    expect(c.network.netId, 2014);
    expect(c.network.seedNodes, ['seed1.digiscope.me']);
    expect(c.network.hasExplicitSeedNodes, isTrue);
  });

  test('default assets are exactly DGB, BTC, LTC', () {
    expect(c.defaultAssets, {'DGB', 'BTC', 'LTC'});
  });

  test('no Gleec price API and no background coin-config updates', () {
    expect(c.marketDataConfig.enableKomodoPrice, isFalse);
    expect(c.enableAssetAutoUpdate, isFalse);
  });

  test('custom tokens and historical auto-activation are off', () {
    expect(c.preActivateCustomTokenAssets, isFalse);
    expect(c.preActivateHistoricalAssets, isFalse);
  });

  test('KDF generates 24-word seeds', () {
    expect(seedWordCount, 24);
    expect(c.mnemonicWordCount, seedWordCount);
  });

  group('asset allowlist', () {
    test('DGB, BTC and LTC pass through unchanged', () {
      final transform = c.assetConfigTransform!;
      for (final coin in ['DGB', 'BTC', 'LTC']) {
        final config = <String, dynamic>{'coin': coin, 'txfee': 1000};
        final out = transform(Map.unmodifiable(config));
        expect(out, config, reason: coin);
        expect(out.containsKey('excluded'), isFalse, reason: coin);
      }
    });

    test('every other coin is excluded and keeps its fields', () {
      final transform = c.assetConfigTransform!;
      const others = [
        'DGB-segwit',
        'BTC-segwit',
        'LTC-segwit',
        'KMD',
        'ETH',
        'BTC-BEP20',
        'DOC',
      ];
      for (final coin in others) {
        final config = <String, dynamic>{'coin': coin, 'decimals': 8};
        final out = transform(Map.unmodifiable(config));
        expect(out['excluded'], isTrue, reason: coin);
        expect(out['decimals'], 8, reason: coin);
      }
    });
  });
}
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter test test/bootstrap/sdk_bootstrap_test.dart`
Expected: a compile error (`seedWordCount` isn't defined).

- [ ] **Step 4: Implement.** Replace `app/lib/bootstrap/sdk_bootstrap.dart` with:

```dart
import 'package:digibyte_dex/config/brand.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart'
    show MarketDataConfig;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// BIP39 word count of wallets KDF creates (spec §5.1).
const seedWordCount = 24;

/// Hides every coin config except the curated list (spec §5.1: no custom
/// tokens; design note 3). The SDK requires a new map, so listed configs
/// are copied too.
Map<String, dynamic> listedAssetsOnly(Map<String, dynamic> config) =>
    Brand.listedAssets.contains(config['coin'])
    ? {...config}
    : {...config, 'excluded': true};

/// The only place the SDK is configured. Every non-default here is a
/// product decision (spec §7.1, §7.2).
KomodoDefiSdkConfig buildSdkConfig() => KomodoDefiSdkConfig(
  defaultAssets: Brand.listedAssets.toSet(),
  preActivateHistoricalAssets: false,
  preActivateCustomTokenAssets: false,
  marketDataConfig: const MarketDataConfig(enableKomodoPrice: false),
  enableAssetAutoUpdate: false,
  network: const KdfNetworkConfig(
    netId: Brand.netId,
    seedNodes: Brand.seedNodes,
  ),
  mnemonicWordCount: seedWordCount,
  assetConfigTransform: listedAssetsOnly,
);

Future<KomodoDefiSdk> startSdk() async {
  final sdk = KomodoDefiSdk(config: buildSdkConfig());
  try {
    await sdk.initialize();
  } on Object {
    // Release whatever initialize() acquired (may terminate KDF). Errors
    // from disposal must not mask the original failure.
    try {
      await sdk.dispose();
    } on Object {
      // ignored
    }
    rethrow;
  }
  return sdk;
}
```

- [ ] **Step 5: Run the test, the whole suite and the analyzer**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter test test/bootstrap/sdk_bootstrap_test.dart
fvm flutter analyze
fvm flutter test
git -C ../third_party/komodo-defi-sdk-flutter status --short   # must be empty
```
Expected: PASS; `No issues found!`; the whole suite passes.
- If a test fails because coin assets are missing, prime them once: `fvm flutter pub get && (fvm flutter build bundle || fvm flutter build bundle)`. The first build may fail on purpose; see `tool/prime_assets.sh`.
- If the submodule status is not empty, revert with `git -C ../third_party/komodo-defi-sdk-flutter checkout -- .`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet
git add third_party/komodo-defi-sdk-flutter app/lib/bootstrap/sdk_bootstrap.dart app/test/bootstrap/sdk_bootstrap_test.dart
git commit -m "feat(app): 24-word KDF seeds and DGB/BTC/LTC asset allowlist; SDK @ $(git -C third_party/komodo-defi-sdk-flutter rev-parse --short HEAD)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 3: Pure policies — password, lockout, wallet name, seed phrase and seed validator

**Files:**
- Create: `app/lib/config/security_defaults.dart`
- Create: `app/lib/domain/security/password_policy.dart`
- Create: `app/lib/domain/security/lockout_policy.dart`
- Create: `app/lib/domain/wallet_name_policy.dart`
- Create: `app/lib/domain/seed/seed_phrase.dart`
- Create: `app/lib/domain/seed/seed_validator.dart`
- Test: `app/test/domain/password_policy_test.dart`
- Test: `app/test/domain/lockout_policy_test.dart`
- Test: `app/test/domain/wallet_name_policy_test.dart`
- Test: `app/test/domain/seed_phrase_test.dart`
- Test: `app/test/domain/seed_validator_test.dart`

**Interfaces:**
- Consumes: `MnemonicValidator`, `MnemonicFailedReason` (`package:komodo_defi_types/komodo_defi_type_utils.dart`).
- Produces:
  - `abstract final class SecurityDefaults { static const Duration autoLockTimeout; static const Duration clipboardClearAfter; }` (2 min, 60 s)
  - `enum PasswordRule { containsPassword, tooShort, missingDigit, missingLowercase, missingUppercase, missingSpecial, tripleRepeat }`
  - `abstract final class PasswordPolicy { static const int minLength; static List<PasswordRule> violations(String); static bool isAcceptable(String); static int strength(String); }`, where `strength` returns 0–4
  - `abstract final class LockoutPolicy { static const int freeAttempts; static const Duration maxDelay; static Duration delayAfter(int failures); }`
  - `class LockoutRecord extends Equatable { const LockoutRecord({int failures, DateTime? lockedUntil}); factory LockoutRecord.fromJson(Map<String, Object?>); static const LockoutRecord none; Duration remaining(DateTime now); LockoutRecord failedAt(DateTime now); Map<String, Object?> toJson(); }`
  - `enum WalletNameProblem { empty, invalidCharacters, tooLong, taken }`; `abstract final class WalletNamePolicy { static const int maxLength; static WalletNameProblem? check(String trimmedName, Iterable<String> existing); }`
  - `final class SeedPhrase { SeedPhrase(String input); final String normalized; final String verbatim; List<String> get words; int get wordCount; static String normalize(String); }`
  - `sealed class SeedCheck`, with `SeedAccepted(String phrase, {required bool isBip39})`, `SeedEmpty()`, `SeedWrongLength(int wordCount)`, `SeedLegacyTooShort(int wordCount)`, `SeedUnknownWord(int position)` (1-based) and `SeedBadChecksum()`
  - `abstract interface class SeedValidator { Future<void> init(); SeedCheck check(SeedPhrase seed, {required bool legacy}); }`
  - `class SdkSeedValidator implements SeedValidator { SdkSeedValidator(MnemonicValidator validator, {Future<String> Function()? loadWordlist}); static const String wordlistAsset; static const int legacyMinWords; }`

- [ ] **Step 1: Write the failing tests**

`app/test/domain/password_policy_test.dart`:

```dart
import 'package:digibyte_dex/domain/security/password_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mirrors KDF common/password_policy.rs fixtures', () {
    // The first KDF error for each fixture must be our first violation.
    final fixtures = <String, PasswordRule>{
      '1234567': PasswordRule.tooShort,
      'pass123worD': PasswordRule.missingSpecial,
      r'SecretPassSoStrong$*': PasswordRule.missingDigit,
      'SECRETPASS-SOSTRONG123*': PasswordRule.missingLowercase,
      'secretpass-sostrong123*': PasswordRule.missingUppercase,
      'SecretPassSoStrong123*aaa': PasswordRule.tripleRepeat,
      r'Password123*$': PasswordRule.containsPassword,
      r'Foopassword123*$': PasswordRule.containsPassword,
    };
    var index = 0;
    for (final MapEntry(key: input, value: rule) in fixtures.entries) {
      test('fixture ${index++} fails first on ${rule.name}', () {
        expect(PasswordPolicy.violations(input).first, rule);
      });
    }

    test('KDF valid passwords are acceptable', () {
      const valid = [
        'SecretPassSoStrong*!1234567891012',
        'StrongPass123*',
        r'StrongPass123[]\± ',
        'StrongPass123£StrongPass123£Pass',
      ];
      for (final p in valid) {
        expect(PasswordPolicy.isAcceptable(p), isTrue);
      }
    });
  });

  test('letter classes are ASCII only, like KDF', () {
    // Ä is not an uppercase letter for KDF, but it is a special character.
    expect(
      PasswordPolicy.violations('Äbcdefg1!'),
      contains(PasswordRule.missingUppercase),
    );
    expect(PasswordPolicy.isAcceptable('Ab1Äxyzq'), isTrue);
  });

  test('length counts characters, not UTF-16 units', () {
    expect(
      PasswordPolicy.violations('Ab1!ÄÖÜ'),
      contains(PasswordRule.tooShort),
    );
    expect(PasswordPolicy.isAcceptable('Ab1!ÄÖÜß'), isTrue);
  });

  test('every broken rule is listed, in KDF order', () {
    expect(PasswordPolicy.violations(''), [
      PasswordRule.tooShort,
      PasswordRule.missingDigit,
      PasswordRule.missingLowercase,
      PasswordRule.missingUppercase,
      PasswordRule.missingSpecial,
    ]);
  });

  test('strength: 0 empty, 1 rule broken, then 2-4 by length', () {
    expect(PasswordPolicy.strength(''), 0);
    expect(PasswordPolicy.strength('abc'), 1);
    expect(PasswordPolicy.strength('Ab1!efgh'), 2);
    expect(PasswordPolicy.strength('StrongPass123*'), 3);
    expect(PasswordPolicy.strength('SecretPassSoStrong*!1234567891012'), 4);
    expect(PasswordPolicy.strength('SecretPassSoStrong123*aaa'), 1);
  });
}
```

`app/test/domain/lockout_policy_test.dart`:

```dart
import 'package:digibyte_dex/domain/security/lockout_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failures 1-4 are free; then 30s, 60s, 5m, 15m, then 1h', () {
    for (var n = 0; n <= 4; n++) {
      expect(LockoutPolicy.delayAfter(n), Duration.zero, reason: '$n');
    }
    expect(LockoutPolicy.delayAfter(5), const Duration(seconds: 30));
    expect(LockoutPolicy.delayAfter(6), const Duration(seconds: 60));
    expect(LockoutPolicy.delayAfter(7), const Duration(minutes: 5));
    expect(LockoutPolicy.delayAfter(8), const Duration(minutes: 15));
    expect(LockoutPolicy.delayAfter(9), const Duration(hours: 1));
    expect(LockoutPolicy.delayAfter(50), const Duration(hours: 1));
  });

  group('LockoutRecord', () {
    final t0 = DateTime.utc(2026, 10, 1, 12);

    test('the fifth failure locks for 30 s', () {
      var r = LockoutRecord.none;
      for (var i = 0; i < 4; i++) {
        r = r.failedAt(t0);
        expect(r.lockedUntil, isNull);
      }
      r = r.failedAt(t0);
      expect(r.failures, 5);
      expect(r.lockedUntil, t0.add(const Duration(seconds: 30)));
    });

    test('remaining counts down to zero and never goes negative', () {
      final r = LockoutRecord(
        failures: 5,
        lockedUntil: t0.add(const Duration(seconds: 30)),
      );
      expect(r.remaining(t0), const Duration(seconds: 30));
      expect(
        r.remaining(t0.add(const Duration(seconds: 29))),
        const Duration(seconds: 1),
      );
      expect(r.remaining(t0.add(const Duration(minutes: 1))), Duration.zero);
      expect(LockoutRecord.none.remaining(t0), Duration.zero);
    });

    test('round-trips through JSON as UTC', () {
      final r = LockoutRecord(
        failures: 6,
        lockedUntil: t0.add(const Duration(seconds: 60)),
      );
      expect(LockoutRecord.fromJson(r.toJson()), r);
      expect(LockoutRecord.fromJson(const {}), LockoutRecord.none);
      expect(
        LockoutRecord.fromJson(const {'failures': 'x', 'lockedUntil': 3}),
        LockoutRecord.none,
      );
    });
  });
}
```

`app/test/domain/wallet_name_policy_test.dart`:

```dart
import 'package:digibyte_dex/domain/wallet_name_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts KDF-safe names', () {
    for (final name in ['main', 'My Wallet 2', 'cold_store-1']) {
      expect(WalletNamePolicy.check(name, const []), isNull, reason: name);
    }
  });

  test('rejects empty, odd characters and over-long names', () {
    expect(WalletNamePolicy.check('', const []), WalletNameProblem.empty);
    expect(
      WalletNamePolicy.check('a/b', const []),
      WalletNameProblem.invalidCharacters,
    );
    expect(
      WalletNamePolicy.check('wallet.dat', const []),
      WalletNameProblem.invalidCharacters,
    );
    expect(
      WalletNamePolicy.check('x' * 33, const []),
      WalletNameProblem.tooLong,
    );
    expect(WalletNamePolicy.check('x' * 32, const []), isNull);
  });

  test('a taken name is rejected regardless of case', () {
    expect(
      WalletNamePolicy.check('Main', const ['main']),
      WalletNameProblem.taken,
    );
  });
}
```

`app/test/domain/seed_phrase_test.dart`:

```dart
import 'package:digibyte_dex/domain/seed/seed_phrase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalize collapses spaces, tabs, newlines and NBSP', () {
    expect(
      SeedPhrase.normalize('  Abandon\tABOUT\n\nzoo  Word \r\n'),
      'abandon about zoo word',
    );
  });

  test('blank input normalizes to empty with no words', () {
    final seed = SeedPhrase(' \n\t ');
    expect(seed.normalized, '');
    expect(seed.words, isEmpty);
    expect(seed.wordCount, 0);
  });

  test('words follow the normalized form', () {
    final seed = SeedPhrase('Alpha  BETA\ngamma');
    expect(seed.words, ['alpha', 'beta', 'gamma']);
    expect(seed.wordCount, 3);
  });

  test('verbatim keeps inner case and spacing, trims the ends', () {
    expect(SeedPhrase('  My  Old Seed \n').verbatim, 'My  Old Seed');
  });

  test('toString never shows the words', () {
    expect(SeedPhrase('alpha beta').toString(), isNot(contains('alpha')));
  });
}
```

`app/test/domain/seed_validator_test.dart`. This uses the real SDK validator and the real bundled word list, which `flutter test` serves from `build/unit_test_assets/packages/komodo_defi_types/...`. The phrases are the public BIP39 test vectors, not secrets.

```dart
import 'package:digibyte_dex/domain/seed/seed_phrase.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SdkSeedValidator validator;

  // Public BIP39 test vectors (trezor/python-mnemonic vectors.json).
  final valid12 = '${List.filled(11, 'abandon').join(' ')} about';
  final valid24 = '${List.filled(23, 'abandon').join(' ')} art';

  setUpAll(() async {
    validator = SdkSeedValidator(MnemonicValidator());
    await validator.init();
  });

  SeedCheck hd(String input) =>
      validator.check(SeedPhrase(input), legacy: false);
  SeedCheck legacy(String input) =>
      validator.check(SeedPhrase(input), legacy: true);

  test('a messy paste of a valid seed is accepted normalized', () {
    final messy = '  ${valid24.toUpperCase().replaceAll(' ', ' \n\t ')}  ';
    expect(hd(messy), SeedAccepted(valid24, isBip39: true));
  });

  test('12 and 24 word vectors are accepted', () {
    expect(hd(valid12), SeedAccepted(valid12, isBip39: true));
    expect(hd(valid24), SeedAccepted(valid24, isBip39: true));
  });

  test('an unknown word is reported by its 1-based position', () {
    final words = valid12.split(' ')..[6] = 'abandonx';
    expect(hd(words.join(' ')), const SeedUnknownWord(7));
  });

  test('valid words with a bad checksum', () {
    expect(
      hd(List.filled(12, 'abandon').join(' ')),
      const SeedBadChecksum(),
    );
  });

  test('HD needs 12, 15, 18, 21 or 24 words', () {
    expect(hd('$valid12 abandon'), const SeedWrongLength(13));
  });

  test('blank input is empty', () {
    expect(hd('  \n '), const SeedEmpty());
    expect(legacy(''), const SeedEmpty());
  });

  test('legacy accepts a 12+ word custom seed verbatim', () {
    // 12 words, not BIP39: the exact text is the iguana key material.
    const custom =
        '  My Old Custom seed one two three four five six seven eight ';
    expect(
      legacy(custom),
      const SeedAccepted(
        'My Old Custom seed one two three four five six seven eight',
        isBip39: false,
      ),
    );
  });

  test('legacy BIP39 seeds are normalized', () {
    expect(legacy(valid12.toUpperCase()), SeedAccepted(valid12, isBip39: true));
  });

  test('legacy custom seeds need at least 12 words', () {
    expect(legacy('one two three four five'), const SeedLegacyTooShort(5));
  });

  test('an accepted seed never prints its words', () {
    expect(hd(valid12).toString(), isNot(contains('abandon')));
  });
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter test test/domain`
Expected: compile errors (the `domain/...` libraries don't exist).

- [ ] **Step 3: Implement**

`app/lib/config/security_defaults.dart`:

```dart
/// Security timings (spec §8.2). M1-D makes the auto-lock timeout a setting.
abstract final class SecurityDefaults {
  /// Background time after which the app locks on return (design note 7).
  static const autoLockTimeout = Duration(minutes: 2);

  /// How long a copied address may stay on the clipboard.
  static const clipboardClearAfter = Duration(seconds: 60);
}
```

`app/lib/domain/security/password_policy.dart`:

```dart
/// One rule of the wallet engine's password policy
/// (KDF `common/password_policy.rs`).
enum PasswordRule {
  containsPassword,
  tooShort,
  missingDigit,
  missingLowercase,
  missingUppercase,
  missingSpecial,
  tripleRepeat,
}

/// KDF's password policy, mirrored exactly so problems are shown per field
/// before KDF ever sees the password (design note 6).
///
/// Letter and digit classes are ASCII-only, like KDF's regexes: `Ä` is not
/// an uppercase letter here, but it does count as a special character.
abstract final class PasswordPolicy {
  static const minLength = 8;

  static final _digit = RegExp('[0-9]');
  static final _lower = RegExp('[a-z]');
  static final _upper = RegExp('[A-Z]');
  static final _special = RegExp('[^A-Za-z0-9]');

  /// Every rule [password] breaks, in KDF's order. Empty means acceptable.
  static List<PasswordRule> violations(String password) => [
    if (password.toLowerCase().contains('password'))
      PasswordRule.containsPassword,
    if (password.runes.length < minLength) PasswordRule.tooShort,
    if (!_digit.hasMatch(password)) PasswordRule.missingDigit,
    if (!_lower.hasMatch(password)) PasswordRule.missingLowercase,
    if (!_upper.hasMatch(password)) PasswordRule.missingUppercase,
    if (!_special.hasMatch(password)) PasswordRule.missingSpecial,
    if (_hasTripleRepeat(password)) PasswordRule.tripleRepeat,
  ];

  static bool isAcceptable(String password) => violations(password).isEmpty;

  /// 0 for empty, 1 while any rule is broken, then 2, 3 or 4 for
  /// 8-11, 12-15 and 16+ characters.
  static int strength(String password) {
    if (password.isEmpty) return 0;
    if (!isAcceptable(password)) return 1;
    final length = password.runes.length;
    return length >= 16
        ? 4
        : length >= 12
        ? 3
        : 2;
  }

  static bool _hasTripleRepeat(String password) {
    final runes = password.runes.toList();
    for (var i = 2; i < runes.length; i++) {
      if (runes[i] == runes[i - 1] && runes[i] == runes[i - 2]) return true;
    }
    return false;
  }
}
```

`app/lib/domain/security/lockout_policy.dart`:

```dart
import 'package:equatable/equatable.dart';

/// Wrong-password delays (spec §8.2, design note 8). No auto-wipe.
abstract final class LockoutPolicy {
  /// Failures allowed before the first delay.
  static const freeAttempts = 4;

  static const _steps = <Duration>[
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  /// The delay after every failure past the stepped ones.
  static const maxDelay = Duration(hours: 1);

  /// How long attempts are refused after the [failures]-th failure in a row.
  static Duration delayAfter(int failures) {
    if (failures <= freeAttempts) return Duration.zero;
    final step = failures - freeAttempts - 1;
    return step < _steps.length ? _steps[step] : maxDelay;
  }
}

/// Persisted wrong-password state of one wallet.
class LockoutRecord extends Equatable {
  const LockoutRecord({this.failures = 0, this.lockedUntil});

  /// Reads a stored record; anything malformed reads as [none].
  factory LockoutRecord.fromJson(Map<String, Object?> json) {
    final failures = json['failures'];
    final until = json['lockedUntil'];
    if (failures is! int) return none;
    return LockoutRecord(
      failures: failures,
      lockedUntil: until is String ? DateTime.tryParse(until)?.toUtc() : null,
    );
  }

  /// No failures recorded.
  static const none = LockoutRecord();

  final int failures;

  /// UTC instant before which attempts are refused, or null.
  final DateTime? lockedUntil;

  /// Time left at [now], or [Duration.zero] when attempts are allowed.
  Duration remaining(DateTime now) {
    final until = lockedUntil;
    if (until == null || !until.isAfter(now)) return Duration.zero;
    return until.difference(now);
  }

  /// The record after one more failure at [now].
  LockoutRecord failedAt(DateTime now) {
    final next = failures + 1;
    final delay = LockoutPolicy.delayAfter(next);
    return LockoutRecord(
      failures: next,
      lockedUntil: delay == Duration.zero ? null : now.toUtc().add(delay),
    );
  }

  Map<String, Object?> toJson() => {
    'failures': failures,
    'lockedUntil': lockedUntil?.toUtc().toIso8601String(),
  };

  @override
  List<Object?> get props => [failures, lockedUntil];
}
```

`app/lib/domain/wallet_name_policy.dart`:

```dart
/// Why a wallet name can't be used.
enum WalletNameProblem { empty, invalidCharacters, tooLong, taken }

/// Wallet names KDF can store as a file name, and that are unique.
///
/// KDF allows alphanumerics, space, `-` and `_`
/// (`mm2_main/src/lp_wallet/mnemonics_storage.rs`); the app keeps to ASCII.
abstract final class WalletNamePolicy {
  static const maxLength = 32;

  static final _allowed = RegExp(r'^[A-Za-z0-9 _-]+$');

  /// The first problem with [name], which must already be trimmed, or null.
  static WalletNameProblem? check(String name, Iterable<String> existing) {
    if (name.isEmpty) return WalletNameProblem.empty;
    if (!_allowed.hasMatch(name)) return WalletNameProblem.invalidCharacters;
    if (name.length > maxLength) return WalletNameProblem.tooLong;
    final lower = name.toLowerCase();
    if (existing.any((e) => e.toLowerCase() == lower)) {
      return WalletNameProblem.taken;
    }
    return null;
  }
}
```

`app/lib/domain/seed/seed_phrase.dart`:

```dart
/// A seed phrase as the user typed or pasted it.
///
/// [toString] never reveals the words.
final class SeedPhrase {
  SeedPhrase(String input)
    : normalized = normalize(input),
      verbatim = input.trim();

  /// Lower-case words separated by single spaces: the BIP39 form.
  final String normalized;

  /// The input with only outer whitespace removed. Used for legacy custom
  /// seeds, whose exact text is the key material.
  final String verbatim;

  List<String> get words =>
      normalized.isEmpty ? const [] : normalized.split(' ');

  int get wordCount => words.length;

  /// Lower-cases, trims, and collapses every whitespace run (spaces, tabs,
  /// newlines, non-breaking spaces) to one space.
  static String normalize(String input) => input
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .join(' ');

  @override
  String toString() => 'SeedPhrase(<redacted>)';
}
```

`app/lib/domain/seed/seed_validator.dart`:

```dart
import 'package:digibyte_dex/domain/seed/seed_phrase.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// The result of checking a seed before any wallet is registered.
///
/// `stringify` is off so a failing test can never print seed words.
sealed class SeedCheck extends Equatable {
  const SeedCheck();

  @override
  List<Object?> get props => [];

  @override
  bool? get stringify => false;
}

/// The seed can be registered; [phrase] is exactly what KDF must receive.
final class SeedAccepted extends SeedCheck {
  const SeedAccepted(this.phrase, {required this.isBip39});

  final String phrase;
  final bool isBip39;

  @override
  List<Object?> get props => [phrase, isBip39];
}

final class SeedEmpty extends SeedCheck {
  const SeedEmpty();
}

/// Not 12, 15, 18, 21 or 24 words (HD restore).
final class SeedWrongLength extends SeedCheck {
  const SeedWrongLength(this.wordCount);

  final int wordCount;

  @override
  List<Object?> get props => [wordCount];
}

/// A legacy custom seed shorter than 12 words.
final class SeedLegacyTooShort extends SeedCheck {
  const SeedLegacyTooShort(this.wordCount);

  final int wordCount;

  @override
  List<Object?> get props => [wordCount];
}

/// The word at [position] (1-based) is not in the BIP39 English list.
final class SeedUnknownWord extends SeedCheck {
  const SeedUnknownWord(this.position);

  final int position;

  @override
  List<Object?> get props => [position];
}

/// Valid words, but the BIP39 checksum does not match.
final class SeedBadChecksum extends SeedCheck {
  const SeedBadChecksum();
}

/// Checks seeds before registration (design note 4: validate BEFORE
/// register, or a bad HD seed leaves a registered wallet behind).
abstract interface class SeedValidator {
  /// Loads the word list. Call once before [check].
  Future<void> init();

  /// Checks [seed] for an HD restore, or a legacy iguana one if [legacy].
  SeedCheck check(SeedPhrase seed, {required bool legacy});
}

/// [SeedValidator] over the SDK's BIP39 validator.
class SdkSeedValidator implements SeedValidator {
  SdkSeedValidator(
    this._validator, {
    Future<String> Function()? loadWordlist,
  }) : _loadWordlist = loadWordlist ?? _bundledWordlist;

  /// The SDK's bundled English BIP39 list (also used by its validator).
  static const wordlistAsset =
      'packages/komodo_defi_types/assets/bip-0039/english-wordlist.txt';

  /// Old-app seeds were at least 12 words (design note 4).
  static const legacyMinWords = 12;

  final MnemonicValidator _validator;
  final Future<String> Function() _loadWordlist;
  Set<String> _wordlist = const {};

  static Future<String> _bundledWordlist() =>
      rootBundle.loadString(wordlistAsset);

  @override
  Future<void> init() async {
    await _validator.init();
    _wordlist = (await _loadWordlist())
        .split('\n')
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toSet();
  }

  @override
  SeedCheck check(SeedPhrase seed, {required bool legacy}) {
    final phrase = seed.normalized;
    if (phrase.isEmpty) return const SeedEmpty();
    // isHd:false with custom seeds disallowed (the default) keeps length
    // and word errors apart from "custom seed" (design note 4).
    final reason = _validator.validateMnemonic(phrase, isHd: false);
    if (reason == null) return SeedAccepted(phrase, isBip39: true);
    if (legacy) {
      return seed.wordCount >= legacyMinWords
          ? SeedAccepted(seed.verbatim, isBip39: false)
          : SeedLegacyTooShort(seed.wordCount);
    }
    return switch (reason) {
      MnemonicFailedReason.empty => const SeedEmpty(),
      MnemonicFailedReason.invalidLength => SeedWrongLength(seed.wordCount),
      MnemonicFailedReason.invalidWord ||
      MnemonicFailedReason.invalidChecksum ||
      MnemonicFailedReason.customNotAllowed ||
      MnemonicFailedReason.customNotSupportedForHd => _wordOrChecksum(seed),
    };
  }

  // The SDK folds a bad word and a bad checksum into customNotAllowed;
  // the word list tells them apart.
  SeedCheck _wordOrChecksum(SeedPhrase seed) {
    final unknown = seed.words.indexWhere((w) => !_wordlist.contains(w));
    return unknown >= 0
        ? SeedUnknownWord(unknown + 1)
        : const SeedBadChecksum();
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter test test/domain
fvm flutter analyze
```
Expected: all PASS; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add lib/config/security_defaults.dart lib/domain test/domain
git commit -m "feat(app): password, lockout, wallet-name and seed policies (KDF mirror, BIP39 via SDK)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 4: Storage and biometrics — `KeyValueStore`, lockout and backup stores, `BiometricStore`, `FlutterFragmentActivity`

**Files:**
- Modify: `app/pubspec.yaml` (add `flutter_secure_storage`, `local_auth`)
- Create: `app/lib/data/storage/key_value_store.dart`
- Create: `app/lib/data/storage/lockout_store.dart`
- Create: `app/lib/data/storage/backup_status_store.dart`
- Create: `app/lib/data/biometrics/biometric_store.dart`
- Modify: `app/android/app/src/main/kotlin/me/digiscope/wallet/MainActivity.kt`
- Create: `app/test/support/in_memory_key_value_store.dart`
- Create: `app/test/support/fake_biometric_store.dart`
- Test: `app/test/data/storage/secure_key_value_store_test.dart`
- Test: `app/test/data/storage/lockout_store_test.dart`
- Test: `app/test/data/storage/backup_status_store_test.dart`
- Test: `app/test/data/biometrics/device_biometric_store_test.dart`
- Modify: `app/test/platform/platform_config_test.dart` (add the `MainActivity` test)

**Interfaces:**
- Consumes: `LockoutRecord` (Task 3).
- Produces:
  - `abstract interface class KeyValueStore { Future<String?> read(String key); Future<void> write(String key, String value); Future<void> delete(String key); }`
  - `class SecureKeyValueStore implements KeyValueStore { SecureKeyValueStore({FlutterSecureStorage? storage}); static const AndroidOptions androidOptions; static const IOSOptions iosOptions; }`, using namespace `dgbdex_state`
  - `class LockoutStore { LockoutStore(KeyValueStore); Future<LockoutRecord> read(String wallet); Future<LockoutRecord> recordFailure(String wallet, DateTime now); Future<void> reset(String wallet); }`, key `lockout_<wallet>`
  - `class BackupStatusStore { BackupStatusStore(KeyValueStore); Future<void> markPending(String wallet); Future<bool> isPending(String wallet); Future<void> clear(String wallet); }`, key `backup_pending_<wallet>`
  - `abstract interface class BiometricStore { Future<bool> isAvailable(); Future<bool> isEnabled(String wallet); Future<bool> enable(String wallet, String password); Future<String?> read(String wallet, {required String reason}); Future<void> disable(String wallet); }`
  - `class DeviceBiometricStore implements BiometricStore { DeviceBiometricStore({required KeyValueStore markers, FlutterSecureStorage? storage, LocalAuthentication? localAuth, bool? isAndroid}); static const AndroidOptions androidOptions; static const IOSOptions iosOptions; }`. The password key is `bio_pw_<wallet>` (namespace `dgbdex_bio`); the marker key is `bio_on_<wallet>` (state store).
  - Test support: `InMemoryKeyValueStore implements KeyValueStore` (with a public `values` map) and `FakeBiometricStore implements BiometricStore` (fields `available`, `passwords`, `invalidated`, `cancel`, `reads`).

- [ ] **Step 1: Add the dependencies**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter pub add 'flutter_secure_storage:^10.3.4' 'local_auth:^2.3.0'
grep -nE '^  (flutter_secure_storage|local_auth):' pubspec.yaml
```
Expected:
- the lock keeps `flutter_secure_storage 10.3.4` and `local_auth 2.3.0`, which move from transitive to direct;
- `pubspec.yaml` gains `flutter_secure_storage: ^10.3.4` (between `flutter_localizations` and `go_router`) and `local_auth: ^2.3.0` (after `komodo_defi_types`).

Keep the dependencies sorted, because `sort_pub_dependencies` is on.

- [ ] **Step 2: Write the test support and the failing tests**

`app/test/support/in_memory_key_value_store.dart`:

```dart
import 'package:digibyte_dex/data/storage/key_value_store.dart';

/// [KeyValueStore] in memory. Lives in test/support because
/// komodo_defi_sdk exports an unrelated class with the same name.
class InMemoryKeyValueStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
```

`app/test/support/fake_biometric_store.dart`:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';

class FakeBiometricStore implements BiometricStore {
  bool available = true;

  /// Stored passwords by wallet. Dummy test values only.
  final passwords = <String, String>{};

  /// Simulates re-enrolled biometrics: the next read fails and clears.
  bool invalidated = false;

  /// Simulates the user cancelling the prompt (entry kept).
  bool cancel = false;

  int reads = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> isEnabled(String wallet) async =>
      passwords.containsKey(wallet);

  @override
  Future<bool> enable(String wallet, String password) async {
    if (!available) return false;
    passwords[wallet] = password;
    return true;
  }

  @override
  Future<String?> read(String wallet, {required String reason}) async {
    reads++;
    if (invalidated) {
      invalidated = false;
      passwords.remove(wallet);
      return null;
    }
    if (cancel) return null;
    return passwords[wallet];
  }

  @override
  Future<void> disable(String wallet) async {
    passwords.remove(wallet);
  }
}
```

`app/test/data/storage/secure_key_value_store_test.dart`:

```dart
import 'package:digibyte_dex/data/storage/key_value_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('writes, reads and deletes', () async {
    final store = SecureKeyValueStore();
    expect(await store.read('k'), isNull);
    await store.write('k', 'v');
    expect(await store.read('k'), 'v');
    await store.delete('k');
    expect(await store.read('k'), isNull);
  });

  test('own namespace, never reset on error, first-unlock on iOS', () {
    final android = SecureKeyValueStore.androidOptions.toMap();
    expect(android['storageNamespace'], 'dgbdex_state');
    expect(android['resetOnError'], 'false');
    expect(
      SecureKeyValueStore.iosOptions.accessibility,
      KeychainAccessibility.first_unlock_this_device,
    );
  });
}
```

`app/test/data/storage/lockout_store_test.dart`:

```dart
import 'package:digibyte_dex/data/storage/lockout_store.dart';
import 'package:digibyte_dex/domain/security/lockout_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';

void main() {
  late InMemoryKeyValueStore storage;
  final t0 = DateTime.utc(2026, 10, 1, 12);

  setUp(() => storage = InMemoryKeyValueStore());

  test('an unknown wallet has no failures', () async {
    expect(await LockoutStore(storage).read('w'), LockoutRecord.none);
  });

  test('the fifth failure locks for 30 s', () async {
    final store = LockoutStore(storage);
    for (var i = 0; i < 4; i++) {
      expect((await store.recordFailure('w', t0)).lockedUntil, isNull);
    }
    final fifth = await store.recordFailure('w', t0);
    expect(fifth.failures, 5);
    expect(fifth.lockedUntil, t0.add(const Duration(seconds: 30)));
  });

  test('a lockout survives an app restart (new store instance)', () async {
    final beforeRestart = LockoutStore(storage);
    for (var i = 0; i < 5; i++) {
      await beforeRestart.recordFailure('w', t0);
    }
    final afterRestart = LockoutStore(storage);
    final record = await afterRestart.read('w');
    expect(record.failures, 5);
    expect(
      record.remaining(t0.add(const Duration(seconds: 10))),
      const Duration(seconds: 20),
    );
  });

  test('lockouts are per wallet and reset clears one', () async {
    final store = LockoutStore(storage);
    await store.recordFailure('a', t0);
    await store.recordFailure('b', t0);
    await store.reset('a');
    expect(await store.read('a'), LockoutRecord.none);
    expect((await store.read('b')).failures, 1);
  });

  test('a corrupt record reads as none', () async {
    await storage.write('lockout_w', '{not json');
    expect(await LockoutStore(storage).read('w'), LockoutRecord.none);
  });
}
```

`app/test/data/storage/backup_status_store_test.dart`:

```dart
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';

void main() {
  test('pending survives a restart until cleared', () async {
    final storage = InMemoryKeyValueStore();
    await BackupStatusStore(storage).markPending('w');

    final afterRestart = BackupStatusStore(storage);
    expect(await afterRestart.isPending('w'), isTrue);
    expect(await afterRestart.isPending('other'), isFalse);

    await afterRestart.clear('w');
    expect(await BackupStatusStore(storage).isPending('w'), isFalse);
  });
}
```

`app/test/data/biometrics/device_biometric_store_test.dart`:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/in_memory_key_value_store.dart';

class _MockStorage extends Mock implements FlutterSecureStorage {}

class _MockLocalAuth extends Mock implements LocalAuthentication {}

void main() {
  late _MockStorage storage;
  late _MockLocalAuth localAuth;
  late InMemoryKeyValueStore markers;

  setUpAll(() => registerFallbackValue(const AuthenticationOptions()));

  setUp(() {
    storage = _MockStorage();
    localAuth = _MockLocalAuth();
    markers = InMemoryKeyValueStore();
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => storage.delete(key: any(named: 'key')),
    ).thenAnswer((_) async {});
    when(
      () => storage.read(key: any(named: 'key')),
    ).thenAnswer((_) async => 'pw-1');
    when(
      () => localAuth.authenticate(
        localizedReason: any(named: 'localizedReason'),
        options: any(named: 'options'),
      ),
    ).thenAnswer((_) async => true);
  });

  DeviceBiometricStore build({bool isAndroid = true}) => DeviceBiometricStore(
    markers: markers,
    storage: storage,
    localAuth: localAuth,
    isAndroid: isAndroid,
  );

  Future<void> enabled(String wallet) => markers.write('bio_on_$wallet', '1');

  void verifyNoLocalAuth() => verifyNever(
    () => localAuth.authenticate(
      localizedReason: any(named: 'localizedReason'),
      options: any(named: 'options'),
    ),
  );

  test('enable stores the password under bio_pw_<wallet>', () async {
    final store = build();
    expect(await store.enable('w', 'pw-1'), isTrue);
    verify(() => storage.write(key: 'bio_pw_w', value: 'pw-1')).called(1);
    expect(await store.isEnabled('w'), isTrue);
    expect(await store.isEnabled('other'), isFalse);
  });

  test('a refused write stores nothing', () async {
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenThrow(PlatformException(code: 'Exception encountered'));
    final store = build();
    expect(await store.enable('w', 'pw-1'), isFalse);
    expect(await store.isEnabled('w'), isFalse);
  });

  test('Android: first read uses the Keystore prompt, later reads '
      'ask local_auth first', () async {
    await enabled('w');
    final store = build();
    expect(await store.read('w', reason: 'why'), 'pw-1');
    verifyNoLocalAuth();
    expect(await store.read('w', reason: 'why'), 'pw-1');
    verify(
      () => localAuth.authenticate(
        localizedReason: 'why',
        options: any(named: 'options'),
      ),
    ).called(1);
  });

  test('Android: a read right after enable asks local_auth', () async {
    final store = build();
    await store.enable('w', 'pw-1');
    expect(await store.read('w', reason: 'why'), 'pw-1');
    verify(
      () => localAuth.authenticate(
        localizedReason: 'why',
        options: any(named: 'options'),
      ),
    ).called(1);
  });

  test('a cancelled local_auth prompt keeps the entry', () async {
    final store = build();
    await store.enable('w', 'pw-1');
    when(
      () => localAuth.authenticate(
        localizedReason: any(named: 'localizedReason'),
        options: any(named: 'options'),
      ),
    ).thenAnswer((_) async => false);
    expect(await store.read('w', reason: 'why'), isNull);
    expect(await store.isEnabled('w'), isTrue);
  });

  test('re-enrolled biometrics clear the entry', () async {
    await enabled('w');
    when(() => storage.read(key: any(named: 'key'))).thenThrow(
      PlatformException(
        code: 'Exception encountered',
        message: 'Migration failed after algorithm change (Invalid key)',
      ),
    );
    final store = build();
    expect(await store.read('w', reason: 'why'), isNull);
    expect(await store.isEnabled('w'), isFalse);
    verify(() => storage.delete(key: 'bio_pw_w')).called(1);
  });

  test('cancelling the first Keystore prompt keeps the entry', () async {
    await enabled('w');
    when(() => storage.read(key: any(named: 'key'))).thenThrow(
      PlatformException(
        code: 'Exception encountered',
        message: 'Biometric authentication error [10]: Cancelled',
      ),
    );
    final store = build();
    expect(await store.read('w', reason: 'why'), isNull);
    expect(await store.isEnabled('w'), isTrue);
    verifyNever(() => storage.delete(key: any(named: 'key')));
  });

  test('iOS: cancelling the Keychain prompt keeps the entry', () async {
    await enabled('w');
    when(() => storage.read(key: any(named: 'key'))).thenThrow(
      PlatformException(
        code: 'Unexpected security result code',
        details: -128,
      ),
    );
    final store = build(isAndroid: false);
    expect(await store.read('w', reason: 'why'), isNull);
    expect(await store.isEnabled('w'), isTrue);
  });

  test('a temporary lockout [7] keeps biometrics on', () async {
    await enabled('w');
    when(() => storage.read(key: any(named: 'key'))).thenThrow(
      PlatformException(
        code: 'Exception encountered',
        message: 'Biometric authentication error [7]: Too many attempts',
      ),
    );
    final store = build();
    expect(await store.read('w', reason: 'why'), isNull);
    expect(await store.isEnabled('w'), isTrue);
  });

  test('a permanent lockout [9] turns biometrics off', () async {
    await enabled('w');
    when(() => storage.read(key: any(named: 'key'))).thenThrow(
      PlatformException(
        code: 'Exception encountered',
        message: 'Biometric authentication error [9]: Locked out',
      ),
    );
    final store = build();
    expect(await store.read('w', reason: 'why'), isNull);
    expect(await store.isEnabled('w'), isFalse);
  });

  test('a null read (namespace reset by the plugin) clears too', () async {
    await enabled('w');
    when(
      () => storage.read(key: any(named: 'key')),
    ).thenAnswer((_) async => null);
    final store = build();
    expect(await store.read('w', reason: 'why'), isNull);
    expect(await store.isEnabled('w'), isFalse);
  });

  test('iOS: every read goes to the Keychain, never local_auth', () async {
    await enabled('w');
    final store = build(isAndroid: false);
    await store.read('w', reason: 'why');
    await store.read('w', reason: 'why');
    verifyNoLocalAuth();
    verify(() => storage.read(key: 'bio_pw_w')).called(2);
  });

  test('a wallet without biometrics is never read', () async {
    expect(await build().read('w', reason: 'why'), isNull);
    verifyNever(() => storage.read(key: any(named: 'key')));
  });

  test('available only with biometrics on a supported device', () async {
    when(() => localAuth.canCheckBiometrics).thenAnswer((_) async => true);
    when(localAuth.isDeviceSupported).thenAnswer((_) async => false);
    expect(await build().isAvailable(), isFalse);
    when(localAuth.isDeviceSupported).thenAnswer((_) async => true);
    expect(await build().isAvailable(), isTrue);
    when(
      () => localAuth.canCheckBiometrics,
    ).thenThrow(PlatformException(code: 'NotAvailable'));
    expect(await build().isAvailable(), isFalse);
  });

  test('strong biometrics only, own namespace, current set on iOS', () {
    final android = DeviceBiometricStore.androidOptions.toMap();
    expect(android['storageNamespace'], 'dgbdex_bio');
    expect(android['enforceBiometrics'], 'true');
    expect(android['biometricType'], 'strongBiometricOnly');
    expect(android['resetOnError'], 'true');
    const ios = DeviceBiometricStore.iosOptions;
    expect(ios.accessControlFlags, [AccessControlFlag.biometryCurrentSet]);
    expect(ios.accessibility, KeychainAccessibility.passcode);
    expect(ios.synchronizable, isFalse);
  });
}
```

Append this test inside `main()` of `app/test/platform/platform_config_test.dart`:

```dart
  test('MainActivity is a FlutterFragmentActivity (local_auth)', () {
    final kt = File(
      'android/app/src/main/kotlin/me/digiscope/wallet/MainActivity.kt',
    ).readAsStringSync();
    expect(kt, contains('class MainActivity : FlutterFragmentActivity()'));
  });
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter test test/data test/platform/platform_config_test.dart`
Expected:
- compile errors (`key_value_store.dart` etc. don't exist);
- the `MainActivity` test fails (`FlutterActivity`).

- [ ] **Step 4: Implement**

`app/lib/data/storage/key_value_store.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small string store for app state (design note 13).
abstract interface class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// [KeyValueStore] in its own secure-storage namespace. Never the SDK's
/// default namespace, whose first-opened options would otherwise win.
class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: androidOptions,
            iOptions: iosOptions,
          );

  static const androidOptions = AndroidOptions(
    storageNamespace: 'dgbdex_state',
    resetOnError: false,
  );

  static const iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
```

`app/lib/data/storage/lockout_store.dart`:

```dart
import 'dart:convert';

import 'package:digibyte_dex/data/storage/key_value_store.dart';
import 'package:digibyte_dex/domain/security/lockout_policy.dart';

/// Wrong-password state per wallet, persisted so killing the app does not
/// reset it (design note 8).
class LockoutStore {
  LockoutStore(this._store);

  final KeyValueStore _store;

  static String _key(String wallet) => 'lockout_$wallet';

  Future<LockoutRecord> read(String wallet) async {
    final raw = await _store.read(_key(wallet));
    if (raw == null) return LockoutRecord.none;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?>
          ? LockoutRecord.fromJson(decoded)
          : LockoutRecord.none;
    } on FormatException {
      return LockoutRecord.none;
    }
  }

  /// Records one wrong password at [now] and returns the new record.
  Future<LockoutRecord> recordFailure(String wallet, DateTime now) async {
    final next = (await read(wallet)).failedAt(now);
    await _store.write(_key(wallet), jsonEncode(next.toJson()));
    return next;
  }

  Future<void> reset(String wallet) => _store.delete(_key(wallet));
}
```

`app/lib/data/storage/backup_status_store.dart`:

```dart
import 'package:digibyte_dex/data/storage/key_value_store.dart';

/// Whether a created wallet still owes its seed backup (design note 10).
/// Persisted, so killing the app mid-backup keeps the wallet pending.
class BackupStatusStore {
  BackupStatusStore(this._store);

  final KeyValueStore _store;

  static String _key(String wallet) => 'backup_pending_$wallet';

  Future<void> markPending(String wallet) => _store.write(_key(wallet), '1');

  Future<bool> isPending(String wallet) async =>
      await _store.read(_key(wallet)) == '1';

  Future<void> clear(String wallet) => _store.delete(_key(wallet));
}
```

`app/lib/data/biometrics/biometric_store.dart`:

```dart
import 'dart:io' show Platform;

import 'package:digibyte_dex/data/storage/key_value_store.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// The wallet password behind biometrics (spec §8.1, design note 9).
abstract interface class BiometricStore {
  /// Whether this device can do biometrics now.
  Future<bool> isAvailable();

  /// Whether a password is stored for [wallet]. Never prompts.
  Future<bool> isEnabled(String wallet);

  /// Stores [password] for [wallet] (prompts on Android). False if refused.
  Future<bool> enable(String wallet, String password);

  /// Prompts and returns the password, or null after a cancel or failure.
  /// Any platform error or empty read removes the entry.
  Future<String?> read(String wallet, {required String reason});

  Future<void> disable(String wallet);
}

/// [BiometricStore] over flutter_secure_storage 10 and local_auth 2.3.
///
/// Android shows the Keystore prompt only on the first use of the storage
/// namespace per process. Every later read is therefore gated by local_auth.
class DeviceBiometricStore implements BiometricStore {
  DeviceBiometricStore({
    required KeyValueStore markers,
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
    bool? isAndroid,
  }) : _markers = markers,
       _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: androidOptions,
             iOptions: iosOptions,
           ),
       _localAuth = localAuth ?? LocalAuthentication(),
       _isAndroid = isAndroid ?? Platform.isAndroid;

  /// Keystore key bound to strong biometrics, invalidated on new
  /// enrolment. resetOnError keeps its default (true): a broken key wipes
  /// only this namespace. The prompt texts are bound when the namespace is
  /// opened, before any BuildContext exists, so they are fixed here.
  static const androidOptions = AndroidOptions.biometric(
    enforceBiometrics: true,
    biometricType: AndroidBiometricType.strongBiometricOnly,
    storageNamespace: 'dgbdex_bio',
    biometricPromptTitle: 'Unlock DigiByte DEX',
    biometricPromptNegativeButton: 'Use password',
  );

  /// Keychain item bound to the current biometric set; synchronizable keeps
  /// its default (false), so it never leaves the device.
  static const iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.passcode,
    accessControlFlags: [AccessControlFlag.biometryCurrentSet],
  );

  final KeyValueStore _markers;
  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;
  final bool _isAndroid;
  bool _primedThisProcess = false;

  static String _key(String wallet) => 'bio_pw_$wallet';

  static String _marker(String wallet) => 'bio_on_$wallet';

  @override
  Future<bool> isAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics &&
          await _localAuth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> isEnabled(String wallet) async =>
      await _markers.read(_marker(wallet)) == '1';

  @override
  Future<bool> enable(String wallet, String password) async {
    try {
      await _storage.write(key: _key(wallet), value: password);
    } on PlatformException {
      await disable(wallet);
      return false;
    }
    _primedThisProcess = true;
    await _markers.write(_marker(wallet), '1');
    return true;
  }

  @override
  Future<String?> read(String wallet, {required String reason}) async {
    if (!await isEnabled(wallet)) return null;
    try {
      if (_isAndroid && _primedThisProcess) {
        final ok = await _localAuth.authenticate(
          localizedReason: reason,
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
          ),
        );
        if (!ok) return null;
      }
      final password = await _storage.read(key: _key(wallet));
      if (password == null) {
        await disable(wallet);
        return null;
      }
      _primedThisProcess = true;
      return password;
    } on PlatformException catch (error) {
      // A cancel or a temporary lockout only skips biometrics this time;
      // anything else (invalidated key, permanent lockout, unavailable)
      // turns them off.
      if (!isTransient(error)) await disable(wallet);
      return null;
    }
  }

  /// True when [error] should not turn biometrics off: the user dismissed
  /// the prompt, or the sensor is temporarily locked out.
  ///
  /// Android (flutter_secure_storage 10.3.4, `FlutterSecureStorage.java`
  /// :1366-1370) reports `Biometric authentication error [<code>]` with
  /// BiometricPrompt codes 5 (canceled), 7 (temporary lockout), 10 (user
  /// canceled) and 13 (negative button). Code 9 (permanent lockout) is
  /// not transient. iOS reports errSecUserCanceled (-128) as details.
  @visibleForTesting
  static bool isTransient(PlatformException error) {
    final message = error.message ?? '';
    const cancelCodes = ['[5]', '[7]', '[10]', '[13]'];
    if (message.contains('Biometric authentication error') &&
        cancelCodes.any(message.contains)) {
      return true;
    }
    return error.details == -128;
  }

  @override
  Future<void> disable(String wallet) async {
    await _markers.delete(_marker(wallet));
    try {
      await _storage.delete(key: _key(wallet));
    } on PlatformException {
      // An invalidated key may already have taken the entry with it.
    }
  }
}
```

Replace `app/android/app/src/main/kotlin/me/digiscope/wallet/MainActivity.kt` with:

```kotlin
package me.digiscope.wallet

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth needs a FragmentActivity to show BiometricPrompt.
class MainActivity : FlutterFragmentActivity()
```

- [ ] **Step 5: Run the tests and the analyzer, and build the APK once (Kotlin change)**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter test test/data test/platform/platform_config_test.dart
fvm flutter analyze
fvm flutter test
fvm flutter build apk --debug && bash ../tool/check_permissions.sh
```
Expected:
- all PASS; `No issues found!`;
- the APK builds;
- `permissions OK: 5 entries match allowlist`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add pubspec.yaml pubspec.lock lib/data/storage lib/data/biometrics android/app/src/main/kotlin/me/digiscope/wallet/MainActivity.kt test/support/in_memory_key_value_store.dart test/support/fake_biometric_store.dart test/data test/platform/platform_config_test.dart
git commit -m "feat(app): secure key-value state, lockout/backup stores, biometric password store" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 5: `WalletRepository` — create, restore, sign in with stored options, verify, reveal; `WalletFailure`

**Files:**
- Modify: `app/pubspec.yaml` (add the `komodo_defi_local_auth` path dependency)
- Create: `app/lib/data/repositories/wallet_failure.dart`
- Modify: `app/lib/data/repositories/wallet_repository.dart` (rewrite)
- Create: `app/lib/l10n/wallet_failure_messages.dart`
- Modify: `app/lib/l10n/arb/app_en.arb` (failure strings)
- Modify: `app/test/support/fake_wallet_repository.dart` (rewrite)
- Test: `app/test/data/repositories/wallet_failure_test.dart`
- Test: `app/test/data/repositories/sdk_wallet_repository_test.dart`
- Test: `app/test/l10n/wallet_failure_messages_test.dart`

**Interfaces:**
- Consumes: `SeedAccepted` (Task 3).
- Produces:
  - `enum WalletFailure { wrongPassword, walletExists, invalidSeed, weakPassword, lockedOut, engine, unknown }`
  - `final class WalletException implements Exception { const WalletException(this.failure); final WalletFailure failure; }`
  - `WalletFailure walletFailureOf(Object error, {bool registering = false})`, the only `AuthException` mapping. While `registering`, `incorrectPassword` becomes `weakPassword`.
  - `abstract interface class WalletRepository`, with:
    - `Stream<WalletUser?> watchUser();`
    - `Future<List<String>> walletNames();`
    - `Future<void> create({required String name, required String password});`
    - `Future<void> restore({required String name, required String password, required SeedAccepted seed, required bool legacy});`
    - `Future<void> signIn({required String name, required String password});`
    - `Future<void> verifyPassword(String password);`
    - `Future<List<String>> revealSeed(String password);`
    - `Future<void> signOut();`

    Every method except `watchUser`, `walletNames` and `signOut` throws only `WalletException`.
  - `typedef StoredAuthOptions = Future<AuthOptions?> Function(String walletName);`
  - `class SdkWalletRepository implements WalletRepository { SdkWalletRepository(KomodoDefiSdk sdk, {StoredAuthOptions? storedOptions}); }`
  - `extension WalletFailureMessage on WalletFailure { String message(AppLocalizations l10n); }`
  - Test support: `FakeWalletRepository`, with:
    - `names`;
    - `correctPassword` (`'Correct-Horse-9'`);
    - `seedWords` (`word1`…`word24`);
    - `createFailure`, `restoreFailure` and `signInFailure` (`WalletFailure?`);
    - `namesGate` (`Completer<List<String>>?`) and `namesError` (`Exception?`);
    - `onCreate` (`void Function(String)?`), called first in `create`;
    - `calls` (`List<String>`), `lastSeed`, `lastLegacy`;
    - `emit(WalletUser?)` and `dispose()`.

- [ ] **Step 1: Add the path dependency**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter pub add 'komodo_defi_local_auth:{"path":"../third_party/komodo-defi-sdk-flutter/packages/komodo_defi_local_auth"}'
grep -n -A1 '^  komodo_defi_local_auth:' pubspec.yaml
```
Expected: `komodo_defi_local_auth:` with `path: ../third_party/komodo-defi-sdk-flutter/packages/komodo_defi_local_auth` under `dependencies`, between `komodo_cex_market_data` and `komodo_defi_sdk`. It is needed for the static `KomodoDefiLocalAuth.storedAuthOptions`; the dependency override already exists.

- [ ] **Step 2: Write the failing tests and the new fake**

Replace `app/test/support/fake_wallet_repository.dart` with:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';

/// Hand-written [WalletRepository]. Passwords and words are dummies.
class FakeWalletRepository implements WalletRepository {
  final _users = StreamController<WalletUser?>.broadcast();

  List<String> names = [];
  String correctPassword = 'Correct-Horse-9';
  List<String> seedWords = [for (var i = 1; i <= 24; i++) 'word$i'];
  WalletFailure? createFailure;
  WalletFailure? restoreFailure;
  WalletFailure? signInFailure;

  /// When set, [walletNames] waits for it (to test racing lookups).
  Completer<List<String>>? namesGate;

  /// When set, [walletNames] throws it (KDF not reachable).
  Exception? namesError;

  /// Called first in [create], to observe what happened before register.
  void Function(String name)? onCreate;

  /// Every call, e.g. `create:main`, `signIn:main`, `verify`, `signOut`.
  final calls = <String>[];
  SeedAccepted? lastSeed;
  bool? lastLegacy;

  void emit(WalletUser? user) => _users.add(user);

  @override
  Stream<WalletUser?> watchUser() => _users.stream;

  @override
  Future<List<String>> walletNames() async {
    final error = namesError;
    if (error != null) throw error;
    final gate = namesGate;
    if (gate != null) return gate.future;
    return List.of(names);
  }

  @override
  Future<void> create({required String name, required String password}) async {
    calls.add('create:$name');
    onCreate?.call(name);
    final failure = createFailure;
    if (failure != null) throw WalletException(failure);
    names.add(name);
    emit(WalletUser(name));
  }

  @override
  Future<void> restore({
    required String name,
    required String password,
    required SeedAccepted seed,
    required bool legacy,
  }) async {
    calls.add('restore:$name');
    lastSeed = seed;
    lastLegacy = legacy;
    final failure = restoreFailure;
    if (failure != null) throw WalletException(failure);
    names.add(name);
    emit(WalletUser(name));
  }

  @override
  Future<void> signIn({required String name, required String password}) async {
    calls.add('signIn:$name');
    if (password != correctPassword) {
      throw const WalletException(WalletFailure.wrongPassword);
    }
    final failure = signInFailure;
    if (failure != null) throw WalletException(failure);
    emit(WalletUser(name));
  }

  @override
  Future<void> verifyPassword(String password) async {
    calls.add('verify');
    if (password != correctPassword) {
      throw const WalletException(WalletFailure.wrongPassword);
    }
  }

  @override
  Future<List<String>> revealSeed(String password) async {
    calls.add('reveal');
    if (password != correctPassword) {
      throw const WalletException(WalletFailure.wrongPassword);
    }
    return List.of(seedWords);
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    emit(null);
  }

  Future<void> dispose() => _users.close();
}
```

`app/test/data/repositories/wallet_failure_test.dart`:

```dart
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

AuthException _auth(AuthExceptionType type) => AuthException('x', type: type);

void main() {
  test('every AuthExceptionType maps to a failure', () {
    for (final type in AuthExceptionType.values) {
      expect(walletFailureOf(_auth(type)), isA<WalletFailure>());
    }
  });

  test('wrong password, existing wallet, bad seed, engine', () {
    expect(
      walletFailureOf(_auth(AuthExceptionType.incorrectPassword)),
      WalletFailure.wrongPassword,
    );
    expect(
      walletFailureOf(_auth(AuthExceptionType.walletAlreadyExists)),
      WalletFailure.walletExists,
    );
    expect(
      walletFailureOf(_auth(AuthExceptionType.invalidBip39Mnemonic)),
      WalletFailure.invalidSeed,
    );
    expect(
      walletFailureOf(_auth(AuthExceptionType.apiConnectionError)),
      WalletFailure.engine,
    );
  });

  test('a policy rejection while registering is weakPassword', () {
    expect(
      walletFailureOf(
        _auth(AuthExceptionType.incorrectPassword),
        registering: true,
      ),
      WalletFailure.weakPassword,
    );
  });

  test('a WalletException passes through; anything else is unknown', () {
    expect(
      walletFailureOf(const WalletException(WalletFailure.lockedOut)),
      WalletFailure.lockedOut,
    );
    expect(walletFailureOf(StateError('boom')), WalletFailure.unknown);
  });

  test('toString carries only the category', () {
    expect(
      const WalletException(WalletFailure.wrongPassword).toString(),
      'WalletException(wrongPassword)',
    );
  });
}
```

`app/test/data/repositories/sdk_wallet_repository_test.dart`:

```dart
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';

class _MockSdk extends Mock implements KomodoDefiSdk {}

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

const _hd = AuthOptions(derivationMethod: DerivationMethod.hdWallet);
const _iguana = AuthOptions(derivationMethod: DerivationMethod.iguana);

KdfUser _user(String name, AuthOptions options) =>
    KdfUser(walletId: WalletId.fromName(name, options), isBip39Seed: true);

Matcher _throwsFailure(WalletFailure failure) => throwsA(
  isA<WalletException>().having((e) => e.failure, 'failure', failure),
);

void main() {
  late _MockSdk sdk;
  late _MockAuth auth;

  setUpAll(() {
    registerFallbackValue(_hd);
    registerFallbackValue(Mnemonic.plaintext(''));
  });

  setUp(() {
    sdk = _MockSdk();
    auth = _MockAuth();
    when(() => sdk.auth).thenReturn(auth);
    when(() => auth.getUsers()).thenAnswer((_) async => []);
    when(
      () => auth.signIn(
        walletName: any(named: 'walletName'),
        password: any(named: 'password'),
        options: any(named: 'options'),
      ),
    ).thenAnswer((_) async => _user('w', _hd));
  });

  SdkWalletRepository repo({AuthOptions? stored}) =>
      SdkWalletRepository(sdk, storedOptions: (_) async => stored);

  group('signIn passes the stored derivation method', () {
    test('a restored iguana wallet signs in as iguana', () async {
      await repo(stored: _iguana).signIn(name: 'legacy', password: 'pw');
      verify(
        () => auth.signIn(
          walletName: 'legacy',
          password: 'pw',
          options: _iguana,
        ),
      ).called(1);
    });

    test('falls back to the options getUsers reports', () async {
      when(
        () => auth.getUsers(),
      ).thenAnswer((_) async => [_user('legacy', _iguana)]);
      await repo().signIn(name: 'legacy', password: 'pw');
      verify(
        () => auth.signIn(
          walletName: 'legacy',
          password: 'pw',
          options: _iguana,
        ),
      ).called(1);
    });

    test('defaults to HD when nothing is stored', () async {
      await repo().signIn(name: 'w', password: 'pw');
      final options = verify(
        () => auth.signIn(
          walletName: 'w',
          password: 'pw',
          options: captureAny(named: 'options'),
        ),
      ).captured.single;
      expect(options, _hd);
    });

    test('a wrong password is wrongPassword', () async {
      when(
        () => auth.signIn(
          walletName: any(named: 'walletName'),
          password: any(named: 'password'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        AuthException('x', type: AuthExceptionType.incorrectPassword),
      );
      await expectLater(
        repo().signIn(name: 'w', password: 'bad'),
        _throwsFailure(WalletFailure.wrongPassword),
      );
    });
  });

  group('create', () {
    setUp(() {
      when(
        () => auth.register(
          walletName: any(named: 'walletName'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => _user('w', _hd));
    });

    test('registers HD with no mnemonic, so KDF generates it', () async {
      await repo().create(name: 'w', password: 'pw');
      verify(() => auth.register(walletName: 'w', password: 'pw')).called(1);
    });

    test('an existing name is walletExists', () async {
      when(
        () => auth.register(
          walletName: any(named: 'walletName'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        AuthException('x', type: AuthExceptionType.walletAlreadyExists),
      );
      await expectLater(
        repo().create(name: 'w', password: 'pw'),
        _throwsFailure(WalletFailure.walletExists),
      );
    });

    test('a KDF policy rejection is weakPassword', () async {
      when(
        () => auth.register(
          walletName: any(named: 'walletName'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        AuthException('x', type: AuthExceptionType.incorrectPassword),
      );
      await expectLater(
        repo().create(name: 'w', password: 'pw'),
        _throwsFailure(WalletFailure.weakPassword),
      );
    });
  });

  group('restore', () {
    setUp(() {
      when(
        () => auth.register(
          walletName: any(named: 'walletName'),
          password: any(named: 'password'),
          options: any(named: 'options'),
          mnemonic: any(named: 'mnemonic'),
        ),
      ).thenAnswer((_) async => _user('w', _hd));
    });

    test('HD restore sends the validated phrase with HD options', () async {
      await repo().restore(
        name: 'w',
        password: 'pw',
        seed: const SeedAccepted('alpha beta', isBip39: true),
        legacy: false,
      );
      final captured = verify(
        () => auth.register(
          walletName: 'w',
          password: 'pw',
          options: captureAny(named: 'options'),
          mnemonic: captureAny(named: 'mnemonic'),
        ),
      ).captured;
      expect(captured.first, _hd);
      expect((captured.last as Mnemonic).plaintextMnemonic, 'alpha beta');
    });

    test('legacy restore uses iguana', () async {
      await repo().restore(
        name: 'w',
        password: 'pw',
        seed: const SeedAccepted('My Custom', isBip39: false),
        legacy: true,
      );
      verify(
        () => auth.register(
          walletName: 'w',
          password: 'pw',
          options: _iguana,
          mnemonic: any(named: 'mnemonic'),
        ),
      ).called(1);
    });
  });

  group('verifyPassword', () {
    test('a wrong password is wrongPassword and never touches the '
        'session', () async {
      when(() => auth.getMnemonicPlainText(any())).thenThrow(
        AuthException('x', type: AuthExceptionType.incorrectPassword),
      );
      await expectLater(
        repo().verifyPassword('bad'),
        _throwsFailure(WalletFailure.wrongPassword),
      );
      verifyNever(() => auth.signOut());
      verifyNever(
        () => auth.signIn(
          walletName: any(named: 'walletName'),
          password: any(named: 'password'),
          options: any(named: 'options'),
        ),
      );
    });

    test('the right password completes and returns nothing', () async {
      when(
        () => auth.getMnemonicPlainText(any()),
      ).thenAnswer((_) async => Mnemonic.plaintext('alpha beta'));
      await expectLater(repo().verifyPassword('pw'), completes);
    });
  });

  group('revealSeed', () {
    test('returns the words in order', () async {
      when(
        () => auth.getMnemonicPlainText(any()),
      ).thenAnswer((_) async => Mnemonic.plaintext('alpha beta gamma'));
      expect(await repo().revealSeed('pw'), ['alpha', 'beta', 'gamma']);
    });

    test('an empty mnemonic is unknown', () async {
      when(
        () => auth.getMnemonicPlainText(any()),
      ).thenAnswer((_) async => Mnemonic.plaintext(null));
      await expectLater(
        repo().revealSeed('pw'),
        _throwsFailure(WalletFailure.unknown),
      );
    });
  });
}
```

`app/test/l10n/wallet_failure_messages_test.dart`:

```dart
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/l10n/wallet_failure_messages.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every failure has its own English message', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final messages = WalletFailure.values.map((f) => f.message(l10n)).toSet();
    expect(messages, hasLength(WalletFailure.values.length));
    expect(messages.every((m) => m.isNotEmpty), isTrue);
    expect(
      WalletFailure.weakPassword.message(l10n),
      'Password rejected by wallet engine.',
    );
  });
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter test test/data/repositories test/l10n`
Expected: compile errors (`wallet_failure.dart` and `wallet_failure_messages.dart` don't exist).

- [ ] **Step 4: Implement**

`app/lib/data/repositories/wallet_failure.dart`:

```dart
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Every wallet error the UI tells apart (design note 16).
enum WalletFailure {
  wrongPassword,
  walletExists,
  invalidSeed,
  weakPassword,
  lockedOut,
  engine,
  unknown,
}

/// Thrown by wallet repositories. It carries only the category, never a
/// message that could contain a secret.
final class WalletException implements Exception {
  const WalletException(this.failure);

  final WalletFailure failure;

  @override
  String toString() => 'WalletException(${failure.name})';
}

/// The only mapping from SDK errors to [WalletFailure].
///
/// While [registering], KDF reports a policy-rejected password as
/// `incorrectPassword`; it is surfaced as [WalletFailure.weakPassword].
WalletFailure walletFailureOf(Object error, {bool registering = false}) {
  if (error is WalletException) return error.failure;
  if (error is! AuthException) return WalletFailure.unknown;
  return switch (error.type) {
    AuthExceptionType.incorrectPassword =>
      registering ? WalletFailure.weakPassword : WalletFailure.wrongPassword,
    AuthExceptionType.walletAlreadyExists => WalletFailure.walletExists,
    AuthExceptionType.invalidBip39Mnemonic => WalletFailure.invalidSeed,
    AuthExceptionType.walletAlreadyRunning ||
    AuthExceptionType.walletStartFailed ||
    AuthExceptionType.internalError ||
    AuthExceptionType.apiConnectionError => WalletFailure.engine,
    AuthExceptionType.generalAuthError ||
    AuthExceptionType.unauthorized ||
    AuthExceptionType.alreadySignedIn ||
    AuthExceptionType.walletNotFound ||
    AuthExceptionType.registrationNotAllowed ||
    AuthExceptionType.legacyWalletAlreadyMigrated => WalletFailure.unknown,
  };
}
```

Replace `app/lib/data/repositories/wallet_repository.dart` with:

```dart
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart'
    show KomodoDefiLocalAuth;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class WalletUser extends Equatable {
  const WalletUser(this.name);
  final String name;
  @override
  List<Object?> get props => [name];
}

/// Wallet lifecycle over KDF. Every method except [watchUser],
/// [walletNames] and [signOut] throws only [WalletException].
abstract interface class WalletRepository {
  Stream<WalletUser?> watchUser();

  Future<List<String>> walletNames();

  /// Registers an HD wallet whose seed KDF generates (24 words).
  Future<void> create({required String name, required String password});

  /// Registers a wallet from an already validated seed: iguana when
  /// [legacy], else HD.
  Future<void> restore({
    required String name,
    required String password,
    required SeedAccepted seed,
    required bool legacy,
  });

  /// Starts KDF for [name] with the wallet's stored derivation method.
  Future<void> signIn({required String name, required String password});

  /// Checks [password] against the running wallet without stopping KDF.
  Future<void> verifyPassword(String password);

  /// The running wallet's seed words. Only the backup screens call this.
  Future<List<String>> revealSeed(String password);

  Future<void> signOut();
}

/// Reads a wallet's stored [AuthOptions]; a seam for tests.
typedef StoredAuthOptions = Future<AuthOptions?> Function(String walletName);

class SdkWalletRepository implements WalletRepository {
  SdkWalletRepository(this._sdk, {StoredAuthOptions? storedOptions})
    : _storedOptions = storedOptions ?? KomodoDefiLocalAuth.storedAuthOptions;

  final KomodoDefiSdk _sdk;
  final StoredAuthOptions _storedOptions;

  static const _hd = AuthOptions(derivationMethod: DerivationMethod.hdWallet);
  static const _iguana = AuthOptions(
    derivationMethod: DerivationMethod.iguana,
  );

  @override
  Stream<WalletUser?> watchUser() => _sdk.auth.watchCurrentUser().map(
    (u) => u == null ? null : WalletUser(u.walletId.name),
  );

  @override
  Future<List<String>> walletNames() async =>
      (await _sdk.auth.getUsers()).map((u) => u.walletId.name).toList();

  // register() defaults to HD and, with no mnemonic, KDF generates the
  // seed with the configured word_count (24).
  @override
  Future<void> create({required String name, required String password}) =>
      _guard(
        () => _sdk.auth.register(walletName: name, password: password),
        registering: true,
      );

  @override
  Future<void> restore({
    required String name,
    required String password,
    required SeedAccepted seed,
    required bool legacy,
  }) => _guard(
    () => _sdk.auth.register(
      walletName: name,
      password: password,
      options: legacy ? _iguana : _hd,
      mnemonic: Mnemonic.plaintext(seed.phrase),
    ),
    registering: true,
  );

  // signIn() overwrites the stored options with whatever it is given, and
  // its default is HD, which would turn an iguana wallet into an empty HD
  // one (design note 5). Always pass what was stored.
  @override
  Future<void> signIn({required String name, required String password}) =>
      _guard(() async {
        final options = await _optionsFor(name);
        await _sdk.auth.signIn(
          walletName: name,
          password: password,
          options: options,
        );
      });

  Future<AuthOptions> _optionsFor(String name) async {
    final stored = await _storedOptions(name);
    if (stored != null) return stored;
    for (final user in await _sdk.auth.getUsers()) {
      if (user.walletId.name == name) return user.walletId.authOptions;
    }
    return _hd;
  }

  // KDF decrypts the stored seed: a wrong password throws
  // incorrectPassword and leaves KDF running (design note 7). The decrypted
  // seed is dropped immediately and never logged.
  @override
  Future<void> verifyPassword(String password) => _guard(() async {
    await _sdk.auth.getMnemonicPlainText(password);
  });

  @override
  Future<List<String>> revealSeed(String password) => _guard(() async {
    final phrase = (await _sdk.auth.getMnemonicPlainText(
      password,
    )).plaintextMnemonic;
    if (phrase == null || phrase.isEmpty) {
      throw const WalletException(WalletFailure.unknown);
    }
    return phrase.split(' ');
  });

  @override
  Future<void> signOut() => _sdk.auth.signOut();

  Future<T> _guard<T>(
    Future<T> Function() action, {
    bool registering = false,
  }) async {
    try {
      return await action();
    } on Object catch (error) {
      throw WalletException(
        walletFailureOf(error, registering: registering),
      );
    }
  }
}
```

`app/lib/l10n/wallet_failure_messages.dart`:

```dart
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/l10n/l10n.dart';

extension WalletFailureMessage on WalletFailure {
  String message(AppLocalizations l10n) => switch (this) {
    WalletFailure.wrongPassword => l10n.failureWrongPassword,
    WalletFailure.walletExists => l10n.failureWalletExists,
    WalletFailure.invalidSeed => l10n.failureInvalidSeed,
    WalletFailure.weakPassword => l10n.failureWeakPassword,
    WalletFailure.lockedOut => l10n.failureLockedOut,
    WalletFailure.engine => l10n.failureEngine,
    WalletFailure.unknown => l10n.failureUnknown,
  };
}
```

In `app/lib/l10n/arb/app_en.arb`, add these keys before the closing `}`. Put a comma after the current last entry (`"retry": "Retry"`).

```json
  "failureWrongPassword": "Wrong password.",
  "failureWalletExists": "A wallet with this name already exists.",
  "failureInvalidSeed": "This seed phrase can't be used.",
  "failureWeakPassword": "Password rejected by wallet engine.",
  "failureLockedOut": "Too many wrong passwords. Wait, then try again.",
  "failureEngine": "The wallet engine isn't responding. Try again.",
  "failureUnknown": "Something went wrong. Try again."
```

- [ ] **Step 5: Run the tests and the analyzer**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter gen-l10n
fvm dart format lib test
fvm flutter test test/data/repositories test/l10n
fvm flutter analyze
fvm flutter test
```
Expected: all PASS, including the existing `auth_cubit_test` and `app_test`, which use the rewritten fake; `No issues found!`.

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add pubspec.yaml pubspec.lock lib/data/repositories lib/l10n/wallet_failure_messages.dart lib/l10n/arb/app_en.arb test/support/fake_wallet_repository.dart test/data/repositories test/l10n/wallet_failure_messages_test.dart
git commit -m "feat(app): wallet repository create/restore/signIn(stored options)/verify/reveal; WalletFailure" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 6: Auth and lock state — `AuthState`/`AuthCubit` revision, `LockCubit`, `authRedirect(auth, lock, location)`

**Files:**
- Modify: `app/lib/features/auth/bloc/auth_cubit.dart` (rewrite)
- Create: `app/lib/features/auth/bloc/lock_cubit.dart`
- Create: `app/lib/app/routes.dart`
- Modify: `app/lib/app/router.dart` (rewrite)
- Modify: `app/lib/app/app.dart` (rewrite)
- Modify: `app/lib/main.dart` (rewrite)
- Create: `app/test/support/test_app.dart`
- Test: `app/test/features/auth/auth_cubit_test.dart` (rewrite)
- Test: `app/test/features/auth/lock_cubit_test.dart`
- Test: `app/test/app/router_test.dart` (rewrite)
- Test: `app/test/app/app_test.dart` (rewrite)

**Interfaces:**
- Consumes:
  - `WalletRepository`, `WalletUser` (Task 5);
  - `BackupStatusStore` (Task 4), `BiometricStore` / `DeviceBiometricStore`, `SecureKeyValueStore` (Task 4);
  - `SecurityDefaults.autoLockTimeout` (Task 3).
- Produces:
  - `sealed class AuthState`, with `AuthUnknown()`, `AuthSignedOut({List<String> walletNames = const []})` and `AuthSignedIn(WalletUser user, {bool backupPending = false})`
  - `class AuthCubit extends Cubit<AuthState> { AuthCubit(WalletRepository repo, {required BackupStatusStore backups}); Future<void> refreshBackupStatus(); Future<void> signOut(); }`
  - `sealed class AppLockState`, with `Unlocked()` and `Locked()`
  - `class LockCubit extends Cubit<AppLockState> { LockCubit({required Stream<AuthState> authStates, DateTime Function()? now, Duration timeout, void Function()? onLocked}); void lockNow(); void unlock(); void onLifecycleChanged(AppLifecycleState); }`
  - `abstract final class Routes`, with `splash` `/`, `welcome` `/welcome`, `create` `/welcome/create`, `restore` `/welcome/restore`, `backup` `/welcome/backup`, `signIn` `/signin`, `locked` `/locked`, `home` `/home`, and `static String receive(String ticker)` → `/home/receive/<ticker>`. `router.dart` re-exports it.
  - `String? authRedirect(AuthState auth, AppLockState lock, String location)`
  - `class AppRouter { AppRouter(AuthCubit auth, LockCubit lock, {@visibleForTesting Stream<Object?>? refreshStream}); GoRouter router; void dispose(); }`
  - `List<RouteBase> appRoutes()`: the route table, which later page tasks extend.
  - `class TestApp` (test support): fields `wallet`, `storage`, `backups`, `biometrics`, `auth`, `lock` and `now`; methods `Widget build()` and `Future<void> dispose()`.

- [ ] **Step 1: Write the failing tests**

Replace `app/test/features/auth/auth_cubit_test.dart` with:

```dart
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';

void main() {
  late FakeWalletRepository repo;
  late BackupStatusStore backups;

  setUp(() {
    repo = FakeWalletRepository();
    backups = BackupStatusStore(InMemoryKeyValueStore());
  });
  tearDown(() => repo.dispose());

  AuthCubit build() => AuthCubit(repo, backups: backups);

  test('starts unknown', () {
    final cubit = build();
    addTearDown(cubit.close);
    expect(cubit.state, const AuthUnknown());
  });

  blocTest<AuthCubit, AuthState>(
    'maps repository user stream to signed-in / signed-out',
    build: build,
    act: (_) async {
      repo.emit(const WalletUser('main'));
      await Future<void>.delayed(Duration.zero);
      repo.emit(null);
    },
    expect: () => const [AuthSignedIn(WalletUser('main')), AuthSignedOut()],
  );

  blocTest<AuthCubit, AuthState>(
    'signed out carries the wallet names',
    build: () {
      repo.names = ['a', 'b'];
      return build();
    },
    act: (_) => repo.emit(null),
    expect: () => const [
      AuthSignedOut(walletNames: ['a', 'b']),
    ],
  );

  blocTest<AuthCubit, AuthState>(
    'a failing wallet-name lookup still signs out',
    build: () {
      repo.namesError = Exception('kdf unreachable');
      return build();
    },
    act: (_) => repo.emit(null),
    expect: () => const [AuthSignedOut()],
  );

  blocTest<AuthCubit, AuthState>(
    'a pending backup survives an app restart',
    setUp: () => backups.markPending('main'),
    build: build,
    act: (_) => repo.emit(const WalletUser('main')),
    expect: () => const [
      AuthSignedIn(WalletUser('main'), backupPending: true),
    ],
  );

  blocTest<AuthCubit, AuthState>(
    'refreshBackupStatus drops the flag once the backup is done',
    setUp: () => backups.markPending('main'),
    build: build,
    act: (cubit) async {
      repo.emit(const WalletUser('main'));
      await Future<void>.delayed(Duration.zero);
      await backups.clear('main');
      await cubit.refreshBackupStatus();
    },
    expect: () => const [
      AuthSignedIn(WalletUser('main'), backupPending: true),
      AuthSignedIn(WalletUser('main')),
    ],
  );

  blocTest<AuthCubit, AuthState>(
    'a slow wallet-name lookup never overrides a newer sign-in',
    build: () {
      repo.namesGate = Completer<List<String>>();
      return build();
    },
    act: (_) async {
      repo.emit(null);
      await Future<void>.delayed(Duration.zero);
      repo.emit(const WalletUser('main'));
      await Future<void>.delayed(Duration.zero);
      repo.namesGate!.complete(['main']);
      await Future<void>.delayed(Duration.zero);
    },
    expect: () => const [AuthSignedIn(WalletUser('main'))],
  );

  test('signOut goes through the repository', () async {
    final cubit = build();
    addTearDown(cubit.close);
    await cubit.signOut();
    expect(repo.calls, ['signOut']);
  });
}
```

Create `app/test/features/auth/lock_cubit_test.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<AuthState> auth;
  late DateTime now;
  const signedIn = AuthSignedIn(WalletUser('main'));

  setUp(() {
    auth = StreamController<AuthState>.broadcast();
    now = DateTime.utc(2026, 10, 1, 12);
  });
  tearDown(() => auth.close());

  LockCubit build({void Function()? onLocked}) {
    final cubit = LockCubit(
      authStates: auth.stream,
      now: () => now,
      onLocked: onLocked,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Future<void> emitAuth(AuthState state) async {
    auth.add(state);
    await Future<void>.delayed(Duration.zero);
  }

  void background(LockCubit cubit) => cubit
    ..onLifecycleChanged(AppLifecycleState.inactive)
    ..onLifecycleChanged(AppLifecycleState.hidden)
    ..onLifecycleChanged(AppLifecycleState.paused);

  void foreground(LockCubit cubit) => cubit
    ..onLifecycleChanged(AppLifecycleState.hidden)
    ..onLifecycleChanged(AppLifecycleState.inactive)
    ..onLifecycleChanged(AppLifecycleState.resumed);

  test('starts unlocked', () {
    expect(build().state, const Unlocked());
  });

  test('lock now is ignored while signed out', () {
    final cubit = build()..lockNow();
    expect(cubit.state, const Unlocked());
  });

  test('lock now locks a signed-in wallet and fires onLocked', () async {
    var fired = 0;
    final cubit = build(onLocked: () => fired++);
    await emitAuth(signedIn);
    cubit.lockNow();
    expect(cubit.state, const Locked());
    expect(fired, 1);
    cubit.unlock();
    expect(cubit.state, const Unlocked());
  });

  test('locks on resume after 2 minutes in the background', () async {
    final cubit = build();
    await emitAuth(signedIn);
    background(cubit);
    now = now.add(const Duration(minutes: 2));
    foreground(cubit);
    expect(cubit.state, const Locked());
  });

  test('a shorter absence does not lock', () async {
    final cubit = build();
    await emitAuth(signedIn);
    background(cubit);
    now = now.add(const Duration(minutes: 1, seconds: 59));
    foreground(cubit);
    expect(cubit.state, const Unlocked());
  });

  test('inactive alone (a system dialog) never counts', () async {
    final cubit = build();
    await emitAuth(signedIn);
    cubit.onLifecycleChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(minutes: 10));
    cubit.onLifecycleChanged(AppLifecycleState.resumed);
    expect(cubit.state, const Unlocked());
  });

  test('sign-out clears a lock; the next sign-in starts unlocked', () async {
    final cubit = build();
    await emitAuth(signedIn);
    cubit.lockNow();
    await emitAuth(const AuthSignedOut());
    expect(cubit.state, const Unlocked());
    await emitAuth(signedIn);
    expect(cubit.state, const Unlocked());
  });
}
```

Replace `app/test/app/router_test.dart` with:

```dart
import 'dart:async';

import 'package:digibyte_dex/app/router.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_wallet_repository.dart';
import '../support/in_memory_key_value_store.dart';

void main() {
  const unlocked = Unlocked();
  const locked = Locked();
  const fresh = AuthSignedOut();
  const returning = AuthSignedOut(walletNames: ['main']);
  const signedIn = AuthSignedIn(WalletUser('main'));
  const pending = AuthSignedIn(WalletUser('main'), backupPending: true);
  const onboarding = [Routes.welcome, Routes.create, Routes.restore];

  String? go(AuthState auth, String location, [AppLockState lock = unlocked]) =>
      authRedirect(auth, lock, location);

  test('unknown holds on splash', () {
    expect(go(const AuthUnknown(), Routes.splash), isNull);
    for (final p in [Routes.home, Routes.welcome, Routes.signIn, '']) {
      expect(go(const AuthUnknown(), p), Routes.splash, reason: p);
    }
  });

  test('signed out with no wallets: onboarding only', () {
    for (final p in onboarding) {
      expect(go(fresh, p), isNull, reason: p);
    }
    const others = [
      Routes.backup,
      Routes.signIn,
      Routes.locked,
      Routes.home,
      '/home/receive/DGB',
      Routes.splash,
      '',
    ];
    for (final p in others) {
      expect(go(fresh, p), Routes.welcome, reason: p);
    }
  });

  test('signed out with wallets: sign-in and onboarding', () {
    for (final p in [Routes.signIn, ...onboarding]) {
      expect(go(returning, p), isNull, reason: p);
    }
    const others = [Routes.backup, Routes.locked, Routes.home, Routes.splash];
    for (final p in others) {
      expect(go(returning, p), Routes.signIn, reason: p);
    }
  });

  test('locked always shows the lock screen, even mid-backup', () {
    expect(go(signedIn, Routes.locked, locked), isNull);
    expect(go(pending, Routes.locked, locked), isNull);
    for (final p in [Routes.home, Routes.backup, Routes.welcome, '']) {
      expect(go(signedIn, p, locked), Routes.locked, reason: p);
      expect(go(pending, p, locked), Routes.locked, reason: p);
    }
  });

  test('a pending backup is forced', () {
    expect(go(pending, Routes.backup), isNull);
    const others = [
      Routes.home,
      '/home/receive/DGB',
      Routes.welcome,
      Routes.create,
      Routes.signIn,
      Routes.locked,
      Routes.splash,
    ];
    for (final p in others) {
      expect(go(pending, p), Routes.backup, reason: p);
    }
  });

  test('signed in and unlocked: gates go home, the rest passes', () {
    const gates = [
      Routes.welcome,
      Routes.create,
      Routes.restore,
      Routes.backup,
      Routes.signIn,
      Routes.locked,
      Routes.splash,
    ];
    for (final p in gates) {
      expect(go(signedIn, p), Routes.home, reason: p);
    }
    for (final p in [Routes.home, '/home/receive/DGB', '/nonexistent', '']) {
      expect(go(signedIn, p), isNull, reason: p);
    }
  });

  test('receive paths are built from the ticker', () {
    expect(Routes.receive('DGB'), '/home/receive/DGB');
  });

  test('AppRouter.dispose cancels the refresh subscription', () async {
    final repo = FakeWalletRepository();
    final backups = BackupStatusStore(InMemoryKeyValueStore());
    final auth = AuthCubit(repo, backups: backups);
    final lock = LockCubit(authStates: auth.stream);
    final controller = StreamController<Object?>.broadcast();
    final appRouter = AppRouter(auth, lock, refreshStream: controller.stream);
    expect(controller.hasListener, isTrue);
    appRouter.dispose();
    expect(controller.hasListener, isFalse);
    await controller.close();
    await lock.close();
    await auth.close();
    await repo.dispose();
  });
}
```

Create `app/test/support/test_app.dart`:

```dart
import 'package:digibyte_dex/app/app.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'fake_biometric_store.dart';
import 'fake_wallet_repository.dart';
import 'in_memory_key_value_store.dart';

/// The whole app over fakes, wired like `main.dart`. [now] drives the
/// lock clock.
class TestApp {
  TestApp() {
    auth = AuthCubit(wallet, backups: backups);
    lock = LockCubit(authStates: auth.stream, now: () => now);
  }

  final wallet = FakeWalletRepository();
  final storage = InMemoryKeyValueStore();
  late final backups = BackupStatusStore(storage);
  final biometrics = FakeBiometricStore();
  DateTime now = DateTime.utc(2026, 10, 1, 12);
  late final AuthCubit auth;
  late final LockCubit lock;

  Widget build() => MultiRepositoryProvider(
    providers: [
      RepositoryProvider<WalletRepository>.value(value: wallet),
      RepositoryProvider.value(value: backups),
      RepositoryProvider<BiometricStore>.value(value: biometrics),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider.value(value: auth),
        BlocProvider.value(value: lock),
      ],
      child: const DigiByteDexApp(),
    ),
  );

  Future<void> dispose() async {
    await lock.close();
    await auth.close();
    await wallet.dispose();
  }
}
```

Replace `app/test/app/app_test.dart` with:

```dart
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('signed-out user with no wallets lands on welcome', (t) async {
    final app = TestApp();
    addTearDown(app.dispose);
    await t.pumpWidget(app.build());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    app.wallet.emit(null);
    await t.pumpAndSettle();
    expect(find.text('Welcome to DigiByte DEX'), findsOneWidget);
  });

  testWidgets('signed-in shows home; sign-out returns to welcome', (t) async {
    final app = TestApp();
    addTearDown(app.dispose);
    await t.pumpWidget(app.build());
    app.wallet.emit(const WalletUser('main'));
    await t.pumpAndSettle();
    expect(find.text('Portfolio'), findsOneWidget);
    app.wallet.emit(null);
    await t.pumpAndSettle();
    expect(find.text('Welcome to DigiByte DEX'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter test test/features/auth test/app`
Expected: compile errors (`lock_cubit.dart` and `routes.dart` don't exist; `AuthCubit` has no `backups:`).

- [ ] **Step 3: Implement**

Replace `app/lib/features/auth/bloc/auth_cubit.dart` with:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

final class AuthUnknown extends AuthState {
  const AuthUnknown();
}

/// No KDF wallet session. [walletNames] decides sign-in vs onboarding.
final class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.walletNames = const []});

  final List<String> walletNames;

  @override
  List<Object?> get props => [walletNames];
}

/// A KDF wallet session is running; [backupPending] forces the backup flow.
final class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user, {this.backupPending = false});

  final WalletUser user;
  final bool backupPending;

  @override
  List<Object?> get props => [user, backupPending];
}

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(WalletRepository repo, {required BackupStatusStore backups})
    : _repo = repo,
      _backups = backups,
      super(const AuthUnknown()) {
    _subscription = repo.watchUser().listen(_onUser);
  }

  final WalletRepository _repo;
  final BackupStatusStore _backups;
  late final StreamSubscription<WalletUser?> _subscription;
  int _generation = 0;

  void _onUser(WalletUser? user) => unawaited(_resolve(user, ++_generation));

  /// Re-reads the backup flag, after the backup quiz is passed.
  Future<void> refreshBackupStatus() async {
    final current = state;
    if (current is AuthSignedIn) await _resolve(current.user, ++_generation);
  }

  /// Ends the KDF wallet session (Home → Sign out).
  Future<void> signOut() => _repo.signOut();

  Future<void> _resolve(WalletUser? user, int generation) async {
    final next = user == null
        ? AuthSignedOut(walletNames: await _walletNamesOrEmpty())
        : AuthSignedIn(user, backupPending: await _isPending(user.name));
    // A slower lookup must never overwrite a newer session event.
    if (generation == _generation && !isClosed) emit(next);
  }

  Future<List<String>> _walletNamesOrEmpty() async {
    try {
      return await _repo.walletNames();
    } on Object {
      return const [];
    }
  }

  Future<bool> _isPending(String wallet) async {
    try {
      return await _backups.isPending(wallet);
    } on Object {
      return false;
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
```

Create `app/lib/features/auth/bloc/lock_cubit.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/config/security_defaults.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class AppLockState extends Equatable {
  const AppLockState();
  @override
  List<Object?> get props => [];
}

final class Unlocked extends AppLockState {
  const Unlocked();
}

final class Locked extends AppLockState {
  const Locked();
}

/// The UI lock above a running KDF session (design note 7). Locking never
/// stops KDF, and unlocking reuses the session.
class LockCubit extends Cubit<AppLockState> {
  LockCubit({
    required Stream<AuthState> authStates,
    DateTime Function()? now,
    Duration timeout = SecurityDefaults.autoLockTimeout,
    void Function()? onLocked,
  }) : _now = now ?? DateTime.now,
       _timeout = timeout,
       _onLocked = onLocked,
       super(const Unlocked()) {
    _subscription = authStates.listen(_onAuth);
  }

  final DateTime Function() _now;
  final Duration _timeout;
  final void Function()? _onLocked;
  late final StreamSubscription<AuthState> _subscription;
  bool _signedIn = false;
  DateTime? _backgroundedAt;

  // A new session starts unlocked; signing out clears any lock.
  void _onAuth(AuthState auth) {
    final signedIn = auth is AuthSignedIn;
    if (signedIn == _signedIn) return;
    _signedIn = signedIn;
    _backgroundedAt = null;
    emit(const Unlocked());
  }

  /// "Lock now". Ignored when no wallet is signed in.
  void lockNow() {
    if (!_signedIn || state is Locked) return;
    _onLocked?.call();
    emit(const Locked());
  }

  void unlock() => emit(const Unlocked());

  /// Locks on resume after [SecurityDefaults.autoLockTimeout] or more in
  /// the background (paused or hidden). Inactive alone never counts.
  void onLifecycleChanged(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.paused) {
      _backgroundedAt ??= _now();
    } else if (lifecycle == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null && _now().difference(since) >= _timeout) lockNow();
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
```

Create `app/lib/app/routes.dart`:

```dart
/// Every route path (design note 12).
abstract final class Routes {
  static const splash = '/';
  static const welcome = '/welcome';
  static const create = '/welcome/create';
  static const restore = '/welcome/restore';
  static const backup = '/welcome/backup';
  static const signIn = '/signin';
  static const locked = '/locked';
  static const home = '/home';

  /// The receive screen of one listed asset.
  static String receive(String ticker) => '/home/receive/$ticker';
}
```

Replace `app/lib/app/router.dart` with:

```dart
import 'dart:async';

import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:digibyte_dex/features/onboarding/view/welcome_page.dart';
import 'package:digibyte_dex/features/wallet/view/home_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

export 'package:digibyte_dex/app/routes.dart';

/// Pure redirect rule (design note 12):
/// - unknown: splash;
/// - signed out: onboarding, plus sign-in when wallets exist;
/// - signed in: the lock screen while locked, the backup while pending,
///   otherwise anything but the gates (which go home).
String? authRedirect(AuthState auth, AppLockState lock, String location) {
  bool at(String route) => location == route;
  final onboarding =
      at(Routes.welcome) || at(Routes.create) || at(Routes.restore);
  switch (auth) {
    case AuthUnknown():
      return at(Routes.splash) ? null : Routes.splash;
    case AuthSignedOut(:final walletNames):
      if (walletNames.isEmpty) return onboarding ? null : Routes.welcome;
      return onboarding || at(Routes.signIn) ? null : Routes.signIn;
    case AuthSignedIn(:final backupPending):
      if (lock is Locked) return at(Routes.locked) ? null : Routes.locked;
      if (backupPending) return at(Routes.backup) ? null : Routes.backup;
      final gate =
          location.startsWith(Routes.welcome) ||
          at(Routes.signIn) ||
          at(Routes.locked) ||
          at(Routes.splash);
      return gate ? Routes.home : null;
  }
}

class _RefreshListenable extends ChangeNotifier {
  _RefreshListenable(List<Stream<Object?>> streams) {
    for (final stream in streams) {
      _subscriptions.add(stream.listen((_) => notifyListeners()));
    }
  }

  final _subscriptions = <StreamSubscription<Object?>>[];

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

/// Owns the [GoRouter] and its refresh listenable, which merges the auth
/// and lock streams. go_router does not dispose its `refreshListenable`.
class AppRouter {
  AppRouter(
    AuthCubit auth,
    LockCubit lock, {
    @visibleForTesting Stream<Object?>? refreshStream,
  }) : _refresh = _RefreshListenable(
         refreshStream == null ? [auth.stream, lock.stream] : [refreshStream],
       ) {
    router = GoRouter(
      initialLocation: Routes.splash,
      refreshListenable: _refresh,
      redirect: (context, state) =>
          authRedirect(auth.state, lock.state, state.matchedLocation),
      routes: appRoutes(),
    );
  }

  final _RefreshListenable _refresh;
  late final GoRouter router;

  void dispose() {
    router.dispose();
    _refresh.dispose();
  }
}

/// The route table. Each page task adds its routes here.
List<RouteBase> appRoutes() => [
  GoRoute(
    path: Routes.splash,
    builder: (_, _) =>
        const Scaffold(body: Center(child: CircularProgressIndicator())),
  ),
  GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomePage()),
  GoRoute(path: Routes.home, builder: (_, _) => const HomePage()),
];
```

Replace `app/lib/app/app.dart` with:

```dart
import 'package:digibyte_dex/app/router.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DigiByteDexApp extends StatefulWidget {
  const DigiByteDexApp({super.key});
  @override
  State<DigiByteDexApp> createState() => _DigiByteDexAppState();
}

class _DigiByteDexAppState extends State<DigiByteDexApp> {
  late final AppRouter _router;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _router = AppRouter(context.read<AuthCubit>(), context.read<LockCubit>());
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleChanged);
  }

  void _onLifecycleChanged(AppLifecycleState state) =>
      context.read<LockCubit>().onLifecycleChanged(state);

  @override
  void dispose() {
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    onGenerateTitle: (c) => c.l10n.appTitle,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    routerConfig: _router.router,
  );
}
```

Replace `app/lib/main.dart` with:

```dart
import 'dart:io' show Platform;

import 'package:digibyte_dex/app/app.dart';
import 'package:digibyte_dex/app/startup_error_app.dart';
import 'package:digibyte_dex/bootstrap/sdk_bootstrap.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/key_value_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:digibyte_dex/platform/backup_exclusion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  await _start();
}

Future<void> _start() async {
  await _excludeFromBackupOnIos();
  try {
    final sdk = await startSdk();
    final storage = SecureKeyValueStore();
    final wallet = SdkWalletRepository(sdk);
    final backups = BackupStatusStore(storage);
    runApp(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: sdk),
          RepositoryProvider<WalletRepository>.value(value: wallet),
          RepositoryProvider.value(value: backups),
          RepositoryProvider<BiometricStore>.value(
            value: DeviceBiometricStore(markers: storage),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider(
              lazy: false,
              create: (_) => AuthCubit(wallet, backups: backups),
            ),
            BlocProvider(
              lazy: false,
              create: (context) =>
                  LockCubit(authStates: context.read<AuthCubit>().stream),
            ),
          ],
          child: const DigiByteDexApp(),
        ),
      ),
    );
  } on Object catch (error, stack) {
    debugPrint('Startup failed: $error\n$stack');
    runApp(StartupErrorApp(error: error, onRetry: _start));
  }
}

Future<void> _excludeFromBackupOnIos() async {
  if (!Platform.isIOS) return;
  try {
    await excludeAppDataFromBackup();
  } on MissingPluginException catch (error) {
    debugPrint('Backup exclusion unavailable: $error');
  } on PlatformException catch (error) {
    debugPrint('Backup exclusion failed: $error');
  }
}
```

- [ ] **Step 4: Run the tests and the analyzer**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter test test/features/auth test/app
fvm flutter analyze
fvm flutter test
```
Expected: all PASS; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add lib/features/auth/bloc lib/app lib/main.dart test/support/test_app.dart test/features/auth test/app
git commit -m "feat(app): auth state with wallet names and backup flag, UI lock with auto-lock, redirect rules" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 7: Secure screens — Android `setSecure`, recents screenshot off, `SecureScreen`, `PrivacyOverlay`

**Files:**
- Modify: `app/android/app/src/main/kotlin/me/digiscope/wallet/MainActivity.kt` (rewrite)
- Create: `app/lib/platform/platform_channel.dart`
- Modify: `app/lib/platform/backup_exclusion.dart` (use the shared channel)
- Create: `app/lib/platform/secure_window.dart`
- Create: `app/lib/widgets/secure_screen.dart`
- Create: `app/lib/widgets/privacy_overlay.dart`
- Modify: `app/lib/app/app.dart` (add the `builder:` line)
- Test: `app/test/platform/secure_window_test.dart`
- Test: `app/test/widgets/secure_screen_test.dart`
- Test: `app/test/widgets/privacy_overlay_test.dart`
- Modify: `app/test/platform/platform_config_test.dart` (add the Android `setSecure` test)

**Interfaces:**
- Consumes: the existing `MethodChannel('me.digiscope.wallet/platform')` and its iOS handler (`AppDelegate.swift`, unchanged; it answers `notImplemented` for `setSecure`).
- Produces:
  - `const MethodChannel platformChannel`
  - `Future<void> setSecureWindow({required bool secure})`: a no-op where there is no native handler (iOS, tests)
  - `class SecureScreen extends StatefulWidget { const SecureScreen({required Widget child, Key? key}); }`: reference-counted, so nested or overlapping secure screens keep `FLAG_SECURE` on until the last one goes
  - `class PrivacyOverlay extends StatefulWidget { const PrivacyOverlay({required Widget child, Key? key}); }`, which shows `Key('privacy.overlay')` while the lifecycle is not `resumed`

- [ ] **Step 1: Write the failing tests**

`app/test/platform/secure_window_test.dart`:

```dart
import 'package:digibyte_dex/platform/platform_channel.dart';
import 'package:digibyte_dex/platform/secure_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(platformChannel, null));

  test('sends setSecure with the flag', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(platformChannel, (call) async {
      calls.add(call);
      return null;
    });
    await setSecureWindow(secure: true);
    await setSecureWindow(secure: false);
    expect(calls.map((c) => c.method), ['setSecure', 'setSecure']);
    expect(calls.map((c) => c.arguments), [
      {'secure': true},
      {'secure': false},
    ]);
  });

  test('a platform without the method (iOS) is ignored', () async {
    messenger.setMockMethodCallHandler(platformChannel, null);
    await expectLater(setSecureWindow(secure: true), completes);
  });
}
```

`app/test/widgets/secure_screen_test.dart`:

```dart
import 'package:digibyte_dex/platform/platform_channel.dart';
import 'package:digibyte_dex/widgets/secure_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<bool> flags;

  setUp(() {
    flags = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, (call) async {
          final args = call.arguments as Map<Object?, Object?>;
          flags.add(args['secure']! as bool);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, null),
  );

  testWidgets('on while shown, off when gone', (t) async {
    await t.pumpWidget(const SecureScreen(child: SizedBox()));
    expect(flags, [true]);
    await t.pumpWidget(const SizedBox());
    expect(flags, [true, false]);
  });

  testWidgets('overlapping secure screens keep the flag on', (t) async {
    await t.pumpWidget(
      const Column(
        children: [
          SecureScreen(key: Key('a'), child: SizedBox()),
          SecureScreen(key: Key('b'), child: SizedBox()),
        ],
      ),
    );
    expect(flags, [true]);
    await t.pumpWidget(
      const Column(
        children: [SecureScreen(key: Key('b'), child: SizedBox())],
      ),
    );
    expect(flags, [true]);
    await t.pumpWidget(const SizedBox());
    expect(flags, [true, false]);
  });
}
```

`app/test/widgets/privacy_overlay_test.dart`:

```dart
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/widgets/privacy_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('covers the app whenever it is not resumed', (t) async {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrivacyOverlay(child: Text('balance-screen')),
      ),
    );
    const overlay = Key('privacy.overlay');
    expect(find.byKey(overlay), findsNothing);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump();
    expect(find.byKey(overlay), findsOneWidget);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await t.pump();
    expect(find.byKey(overlay), findsOneWidget);

    t.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(find.byKey(overlay), findsNothing);
  });
}
```

Append inside `main()` of `app/test/platform/platform_config_test.dart`:

```dart
  test('Android blocks screenshots on demand and blanks recents', () {
    final kt = File(
      'android/app/src/main/kotlin/me/digiscope/wallet/MainActivity.kt',
    ).readAsStringSync();
    expect(kt, contains('class MainActivity : FlutterFragmentActivity()'));
    expect(kt, contains('"me.digiscope.wallet/platform"'));
    expect(kt, contains('"setSecure"'));
    expect(kt, contains('WindowManager.LayoutParams.FLAG_SECURE'));
    expect(kt, contains('setRecentsScreenshotEnabled(false)'));
  });
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter test test/platform test/widgets`
Expected: compile errors (`platform_channel.dart`, `secure_window.dart`, `secure_screen.dart` and `privacy_overlay.dart` don't exist), and the Android test fails.

- [ ] **Step 3: Implement**

Replace `app/android/app/src/main/kotlin/me/digiscope/wallet/MainActivity.kt` with:

```kotlin
package me.digiscope.wallet

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: local_auth needs a FragmentActivity for
// BiometricPrompt.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Blank app-switcher thumbnail on Android 13+ (spec §8.2).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Screenshots and screen recording off on seed screens.
                    "setSecure" -> {
                        if (call.argument<Boolean>("secure") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private companion object {
        const val CHANNEL = "me.digiscope.wallet/platform"
    }
}
```

`app/lib/platform/platform_channel.dart`:

```dart
import 'package:flutter/services.dart';

/// The app's one native channel: Android `MainActivity`, iOS `AppDelegate`.
const MethodChannel platformChannel = MethodChannel(
  'me.digiscope.wallet/platform',
);
```

Replace `app/lib/platform/backup_exclusion.dart` with:

```dart
import 'package:digibyte_dex/platform/platform_channel.dart';

/// Marks the app's persistent data directories as excluded from iCloud/iTunes
/// backups. iOS only; Android disables backup in the manifest.
Future<void> excludeAppDataFromBackup() async {
  await platformChannel.invokeMethod<void>('excludeFromBackup');
}
```

`app/lib/platform/secure_window.dart`:

```dart
import 'package:digibyte_dex/platform/platform_channel.dart';
import 'package:flutter/services.dart';

/// Turns Android `FLAG_SECURE` on or off for the whole window.
///
/// iOS has no handler yet (a known gap, design note 11). The missing method
/// is ignored there and in tests.
Future<void> setSecureWindow({required bool secure}) async {
  try {
    await platformChannel.invokeMethod<void>('setSecure', {'secure': secure});
  } on MissingPluginException {
    // No native handler on this platform.
  }
}
```

`app/lib/widgets/secure_screen.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/platform/secure_window.dart';
import 'package:flutter/widgets.dart';

/// Blocks screenshots and screen recording while it is in the tree (spec
/// §8.2). Used on every screen that shows or takes seed words.
class SecureScreen extends StatefulWidget {
  const SecureScreen({required this.child, super.key});

  final Widget child;

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  // The flag is one per window, so overlapping secure screens (a route
  // transition, nesting) share it: on with the first, off after the last.
  static int _active = 0;

  @override
  void initState() {
    super.initState();
    if (_active++ == 0) unawaited(setSecureWindow(secure: true));
  }

  @override
  void dispose() {
    if (--_active == 0) unawaited(setSecureWindow(secure: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

`app/lib/widgets/privacy_overlay.dart`:

```dart
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Covers the whole app with an opaque branded panel whenever it is not in
/// the foreground, so the app switcher never shows balances or addresses
/// (spec §8.2; both platforms).
class PrivacyOverlay extends StatefulWidget {
  const PrivacyOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<PrivacyOverlay> createState() => _PrivacyOverlayState();
}

class _PrivacyOverlayState extends State<PrivacyOverlay> {
  late final AppLifecycleListener _listener;
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    _covered = _shouldCover(WidgetsBinding.instance.lifecycleState);
    _listener = AppLifecycleListener(onStateChange: _onStateChange);
  }

  static bool _shouldCover(AppLifecycleState? state) =>
      state != null && state != AppLifecycleState.resumed;

  void _onStateChange(AppLifecycleState state) {
    final covered = _shouldCover(state);
    if (covered != _covered) setState(() => _covered = covered);
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        widget.child,
        if (_covered)
          Positioned.fill(
            child: ColoredBox(
              key: const Key('privacy.overlay'),
              color: theme.colorScheme.surface,
              child: Center(
                child: Text(
                  context.l10n.appTitle,
                  style: theme.textTheme.headlineMedium,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```

In `app/lib/app/app.dart`:
- add `import 'package:digibyte_dex/widgets/privacy_overlay.dart';` in sorted position;
- in `MaterialApp.router(`, add this line after `darkTheme: buildTheme(Brightness.dark),`:

```dart
    builder: (context, child) =>
        PrivacyOverlay(child: child ?? const SizedBox.shrink()),
```

- [ ] **Step 4: Run the tests and the analyzer, and build the APK (Kotlin)**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm dart format lib test
fvm flutter test test/platform test/widgets test/app
fvm flutter analyze
fvm flutter test
fvm flutter build apk --debug && bash ../tool/check_permissions.sh
```
Expected: all PASS; `No issues found!`; the APK builds; `permissions OK`.

- [ ] **Step 5: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add android/app/src/main/kotlin/me/digiscope/wallet/MainActivity.kt lib/platform lib/widgets lib/app/app.dart test/platform test/widgets
git commit -m "feat(app): FLAG_SECURE channel, blank recents, SecureScreen and privacy overlay" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 8: Welcome and Create-wallet pages — `CreateWalletCubit`, `PendingBackupSession`, password fields and strength meter

**Files:**
- Create: `app/lib/widgets/tagged.dart`
- Create: `app/lib/widgets/busy_indicator.dart`
- Create: `app/lib/features/onboarding/bloc/pending_backup_session.dart`
- Create: `app/lib/features/onboarding/bloc/create_wallet_cubit.dart`
- Create: `app/lib/features/onboarding/widgets/password_fields.dart`
- Create: `app/lib/features/onboarding/view/create_wallet_page.dart`
- Modify: `app/lib/features/onboarding/view/welcome_page.dart` (rewrite)
- Create: `app/lib/l10n/policy_messages.dart`
- Modify: `app/lib/l10n/arb/app_en.arb`
- Modify: `app/lib/app/router.dart` (`appRoutes()`)
- Modify: `app/lib/main.dart` (session provider; `onLocked`)
- Modify: `app/test/support/test_app.dart` (session)
- Create: `app/test/support/pump_app.dart`
- Test: `app/test/features/onboarding/pending_backup_session_test.dart`
- Test: `app/test/features/onboarding/create_wallet_cubit_test.dart`
- Test: `app/test/features/onboarding/create_wallet_page_test.dart`
- Test: `app/test/features/onboarding/welcome_page_test.dart`

**Interfaces:**
- Consumes:
  - `WalletRepository`, `WalletException`, `WalletFailure` (Task 5);
  - `BackupStatusStore`, `BiometricStore` (Task 4);
  - `PasswordPolicy`, `PasswordRule`, `WalletNamePolicy`, `WalletNameProblem` (Task 3);
  - `AuthCubit`, `AuthSignedOut`, `Routes`, `LockCubit({onLocked})` (Task 6);
  - `WalletFailureMessage` (Task 5).
- Produces:
  - `class Tagged extends StatelessWidget { const Tagged(String id, {required Widget child, Key? key}); }`
  - `void unfocusOnTapOutside(PointerDownEvent event)`
  - `class BusyIndicator extends StatelessWidget { const BusyIndicator(String id, {Key? key}); }`
  - `class PendingBackupSession { void start(String wallet, String password); String? passwordFor(String wallet); void clear(); }`
  - `enum CreateWalletStatus { editing, submitting, failure, done }`
  - `class CreateWalletState`, with fields `status`, `nameProblem`, `passwordProblems`, `confirmMismatch`, `failure` and `biometricsAvailable`
  - `class CreateWalletCubit { CreateWalletCubit({required WalletRepository wallet, required BackupStatusStore backups, required PendingBackupSession session, required BiometricStore biometrics}); Future<void> init(); Future<void> submit({required String name, required String password, required String confirm, required bool enableBiometrics}); }`
  - `class PasswordFields extends StatelessWidget { const PasswordFields({required String idPrefix, required TextEditingController password, required TextEditingController confirm, required List<PasswordRule> problems, required bool confirmMismatch, bool enabled = true}); }`, with keys `<prefix>.password` and `<prefix>.confirm`
  - `class PasswordStrengthMeter`, with key `password.strength`
  - `extension PasswordRuleMessage on PasswordRule { String message(AppLocalizations); }`
  - `extension WalletNameProblemMessage on WalletNameProblem { String message(AppLocalizations); }`
  - Widget keys and identifiers:
    - welcome: `welcome.create`, `welcome.restore`, `welcome.signIn`;
    - create: `create.name`, `create.password`, `create.confirm`, `create.biometrics`, `create.error`, `create.submit`, `create.busy`.
  - Test support:
    - `Future<GoRouter> pumpPage(WidgetTester, Widget page, {List<String> stubs})`;
    - `Future<void> tapKey(WidgetTester, String key)`;
    - `Future<void> enterKey(WidgetTester, String key, String text)`;
    - `TestApp.session`.

- [ ] **Step 1: Write the test support and the failing tests**

`app/test/support/pump_app.dart`:

```dart
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Pumps [page] at `/` in a localized router app on a phone-sized screen.
/// Each path in [stubs] renders `Text('route:<path>')`, so navigation can
/// be asserted.
Future<GoRouter> pumpPage(
  WidgetTester tester,
  Widget page, {
  List<String> stubs = const [],
}) async {
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => page),
      for (final path in stubs)
        GoRoute(path: path, builder: (_, _) => Text('route:$path')),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
  await tester.pump();
  await tester.pump();
  return router;
}

/// Scrolls the widget with [key] into view, taps it and pumps a frame.
Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// Scrolls the field with [key] into view and types [text] into it.
Future<void> enterKey(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pump();
}
```

`app/test/features/onboarding/pending_backup_session_test.dart`:

```dart
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('holds the password for one wallet until cleared', () {
    final session = PendingBackupSession()..start('main', 'Correct-Horse-9');
    expect(session.passwordFor('main'), 'Correct-Horse-9');
    expect(session.passwordFor('other'), isNull);
    session.clear();
    expect(session.passwordFor('main'), isNull);
  });
}
```

`app/test/features/onboarding/create_wallet_cubit_test.dart`:

```dart
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/domain/security/password_policy.dart';
import 'package:digibyte_dex/domain/wallet_name_policy.dart';
import 'package:digibyte_dex/features/onboarding/bloc/create_wallet_cubit.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_biometric_store.dart';
import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';

const _pw = 'Correct-Horse-9';

void main() {
  late FakeWalletRepository repo;
  late InMemoryKeyValueStore storage;
  late PendingBackupSession session;
  late FakeBiometricStore biometrics;

  setUp(() {
    repo = FakeWalletRepository();
    storage = InMemoryKeyValueStore();
    session = PendingBackupSession();
    biometrics = FakeBiometricStore();
  });
  tearDown(() => repo.dispose());

  CreateWalletCubit build() {
    final cubit = CreateWalletCubit(
      wallet: repo,
      backups: BackupStatusStore(storage),
      session: session,
      biometrics: biometrics,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Future<void> submit(
    CreateWalletCubit cubit, {
    String name = 'main',
    String password = _pw,
    String? confirm,
    bool enableBiometrics = false,
  }) => cubit.submit(
    name: name,
    password: password,
    confirm: confirm ?? password,
    enableBiometrics: enableBiometrics,
  );

  test('marks the backup pending before register, keeps the password '
      'for the backup page', () async {
    bool? pendingAtCreate;
    repo.onCreate = (name) =>
        pendingAtCreate = storage.values.containsKey('backup_pending_$name');
    final cubit = build();
    await submit(cubit, name: '  main ');
    expect(pendingAtCreate, isTrue);
    expect(repo.calls, ['create:main']);
    expect(session.passwordFor('main'), _pw);
    expect(cubit.state.status, CreateWalletStatus.done);
  });

  test('invalid input is reported per field and never reaches KDF', () async {
    final cubit = build();
    await submit(cubit, name: '', password: 'short', confirm: 'other');
    expect(cubit.state.status, CreateWalletStatus.editing);
    expect(cubit.state.nameProblem, WalletNameProblem.empty);
    expect(cubit.state.passwordProblems.first, PasswordRule.tooShort);
    expect(cubit.state.confirmMismatch, isTrue);
    expect(repo.calls, isEmpty);
    expect(storage.values, isEmpty);
  });

  test('a taken name is rejected before register', () async {
    repo.names = ['Main'];
    final cubit = build();
    await submit(cubit);
    expect(cubit.state.nameProblem, WalletNameProblem.taken);
    expect(repo.calls, isEmpty);
  });

  test('an engine rejection clears the pending flag and the session', () async {
    repo.createFailure = WalletFailure.weakPassword;
    final cubit = build();
    await submit(cubit);
    expect(cubit.state.status, CreateWalletStatus.failure);
    expect(cubit.state.failure, WalletFailure.weakPassword);
    expect(storage.values, isEmpty);
    expect(session.passwordFor('main'), isNull);
  });

  test('biometric opt-in stores the password after register', () async {
    final cubit = build();
    await cubit.init();
    expect(cubit.state.biometricsAvailable, isTrue);
    await submit(cubit, enableBiometrics: true);
    expect(biometrics.passwords['main'], _pw);
  });

  test('opt-in is ignored when biometrics are unavailable', () async {
    biometrics.available = false;
    final cubit = build();
    await cubit.init();
    await submit(cubit, enableBiometrics: true);
    expect(biometrics.passwords, isEmpty);
  });
}
```

`app/test/features/onboarding/create_wallet_page_test.dart`:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:digibyte_dex/features/onboarding/view/create_wallet_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_biometric_store.dart';
import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/pump_app.dart';

const _pw = 'Correct-Horse-9';

void main() {
  late FakeWalletRepository repo;
  late PendingBackupSession session;
  late FakeBiometricStore biometrics;

  setUp(() {
    repo = FakeWalletRepository();
    session = PendingBackupSession();
    biometrics = FakeBiometricStore();
  });
  tearDown(() => repo.dispose());

  Future<void> pump(WidgetTester t) => pumpPage(
    t,
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<WalletRepository>.value(value: repo),
        RepositoryProvider.value(
          value: BackupStatusStore(InMemoryKeyValueStore()),
        ),
        RepositoryProvider.value(value: session),
        RepositoryProvider<BiometricStore>.value(value: biometrics),
      ],
      child: const CreateWalletPage(),
    ),
  );

  testWidgets('the strength meter follows the password', (t) async {
    await pump(t);
    await enterKey(t, 'create.password', 'abc');
    expect(find.text('Weak'), findsOneWidget);
    await enterKey(t, 'create.password', 'StrongPass123*');
    expect(find.text('Good'), findsOneWidget);
  });

  testWidgets('problems are shown per field; nothing is created', (t) async {
    await pump(t);
    await tapKey(t, 'create.submit');
    await t.pump();
    expect(find.text('Enter a wallet name.'), findsOneWidget);
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('a valid form creates the wallet', (t) async {
    await pump(t);
    await enterKey(t, 'create.name', 'main');
    await enterKey(t, 'create.password', _pw);
    await enterKey(t, 'create.confirm', _pw);
    await tapKey(t, 'create.submit');
    await t.pump();
    expect(repo.calls, ['create:main']);
    expect(session.passwordFor('main'), _pw);
  });

  testWidgets('the biometric opt-in shows only when available', (t) async {
    biometrics.available = false;
    await pump(t);
    expect(find.byKey(const Key('create.biometrics')), findsNothing);
  });

  testWidgets('opting in stores the password behind biometrics', (t) async {
    await pump(t);
    await tapKey(t, 'create.biometrics');
    await enterKey(t, 'create.name', 'main');
    await enterKey(t, 'create.password', _pw);
    await enterKey(t, 'create.confirm', _pw);
    await tapKey(t, 'create.submit');
    await t.pump();
    expect(biometrics.passwords['main'], _pw);
  });
}
```

`app/test/features/onboarding/welcome_page_test.dart`:

```dart
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/onboarding/view/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeWalletRepository repo;
  late AuthCubit auth;

  setUp(() => repo = FakeWalletRepository());
  tearDown(() => repo.dispose());

  // The cubit is created inside the test body, so its stream callbacks run
  // in the tester's fake-async zone.
  Future<void> pump(WidgetTester t, {List<String> wallets = const []}) async {
    auth = AuthCubit(repo, backups: BackupStatusStore(InMemoryKeyValueStore()));
    addTearDown(auth.close);
    repo
      ..names = [...wallets]
      ..emit(null);
    await pumpPage(
      t,
      BlocProvider.value(value: auth, child: const WelcomePage()),
      stubs: [Routes.create, Routes.restore, Routes.signIn],
    );
  }

  testWidgets('create and restore; sign-in only with wallets', (t) async {
    await pump(t);
    expect(find.byKey(const Key('welcome.create')), findsOneWidget);
    expect(find.byKey(const Key('welcome.restore')), findsOneWidget);
    expect(find.byKey(const Key('welcome.signIn')), findsNothing);
  });

  testWidgets('existing wallets add a sign-in button', (t) async {
    await pump(t, wallets: ['main']);
    expect(find.byKey(const Key('welcome.signIn')), findsOneWidget);
  });

  testWidgets('create opens the create page', (t) async {
    await pump(t);
    await tapKey(t, 'welcome.create');
    await t.pumpAndSettle();
    expect(find.text('route:${Routes.create}'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter test test/features/onboarding`
Expected: compile errors (`pending_backup_session.dart`, `create_wallet_cubit.dart` and `create_wallet_page.dart` don't exist).

- [ ] **Step 3: Implement**

`app/lib/widgets/tagged.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Gives [child] a stable accessibility id. Android reports it as the
/// node's resource-id, so the on-device acceptance script can find it with
/// `uiautomator dump`. Use the same string as the child's widget key.
class Tagged extends StatelessWidget {
  const Tagged(this.id, {required this.child, super.key});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(identifier: id, container: true, child: child);
}

/// Hides the keyboard when the user taps outside a text field.
void unfocusOnTapOutside(PointerDownEvent event) =>
    FocusManager.instance.primaryFocus?.unfocus();
```

`app/lib/widgets/busy_indicator.dart`:

```dart
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';

/// A small spinner shown inside a button while its action runs.
class BusyIndicator extends StatelessWidget {
  const BusyIndicator(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) => Tagged(
    id,
    child: SizedBox.square(
      key: Key(id),
      dimension: 20,
      child: const CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}
```

`app/lib/features/onboarding/bloc/pending_backup_session.dart`:

```dart
/// Keeps a new wallet's password in memory between create and backup, so
/// the backup page can reveal the seed without asking again. Cleared on
/// completion and on lock; never persisted (design note 10).
class PendingBackupSession {
  String? _wallet;
  String? _password;

  void start(String wallet, String password) {
    _wallet = wallet;
    _password = password;
  }

  /// The password for [wallet], or null after a restart, lock or backup.
  String? passwordFor(String wallet) => wallet == _wallet ? _password : null;

  void clear() {
    _wallet = null;
    _password = null;
  }
}
```

`app/lib/features/onboarding/bloc/create_wallet_cubit.dart`:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/domain/security/password_policy.dart';
import 'package:digibyte_dex/domain/wallet_name_policy.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum CreateWalletStatus { editing, submitting, failure, done }

class CreateWalletState extends Equatable {
  const CreateWalletState({
    this.status = CreateWalletStatus.editing,
    this.nameProblem,
    this.passwordProblems = const [],
    this.confirmMismatch = false,
    this.failure,
    this.biometricsAvailable = false,
  });

  final CreateWalletStatus status;
  final WalletNameProblem? nameProblem;
  final List<PasswordRule> passwordProblems;
  final bool confirmMismatch;
  final WalletFailure? failure;
  final bool biometricsAvailable;

  @override
  List<Object?> get props => [
    status,
    nameProblem,
    passwordProblems,
    confirmMismatch,
    failure,
    biometricsAvailable,
  ];
}

/// The create flow (design note 10):
/// 1. validate;
/// 2. mark the backup pending;
/// 3. keep the password for the backup page;
/// 4. let KDF generate the 24 words;
/// 5. optionally store the password behind biometrics.
class CreateWalletCubit extends Cubit<CreateWalletState> {
  CreateWalletCubit({
    required WalletRepository wallet,
    required BackupStatusStore backups,
    required PendingBackupSession session,
    required BiometricStore biometrics,
  }) : _wallet = wallet,
       _backups = backups,
       _session = session,
       _biometrics = biometrics,
       super(const CreateWalletState());

  final WalletRepository _wallet;
  final BackupStatusStore _backups;
  final PendingBackupSession _session;
  final BiometricStore _biometrics;

  Future<void> init() async {
    final available = await _biometrics.isAvailable();
    _emit(CreateWalletState(biometricsAvailable: available));
  }

  Future<void> submit({
    required String name,
    required String password,
    required String confirm,
    required bool enableBiometrics,
  }) async {
    if (state.status == CreateWalletStatus.submitting) return;
    final bio = state.biometricsAvailable;
    _emit(
      CreateWalletState(
        status: CreateWalletStatus.submitting,
        biometricsAvailable: bio,
      ),
    );
    final walletName = name.trim();
    final nameProblem = WalletNamePolicy.check(
      walletName,
      await _existingNames(),
    );
    final passwordProblems = PasswordPolicy.violations(password);
    final mismatch = password != confirm;
    if (nameProblem != null || passwordProblems.isNotEmpty || mismatch) {
      _emit(
        CreateWalletState(
          nameProblem: nameProblem,
          passwordProblems: passwordProblems,
          confirmMismatch: mismatch,
          biometricsAvailable: bio,
        ),
      );
      return;
    }
    // Pending BEFORE register: a kill at any later point still forces the
    // backup on the next sign-in.
    await _backups.markPending(walletName);
    _session.start(walletName, password);
    try {
      await _wallet.create(name: walletName, password: password);
    } on WalletException catch (e) {
      _session.clear();
      // walletExists means another wallet owns the name (and its flag).
      if (e.failure != WalletFailure.walletExists) {
        await _backups.clear(walletName);
      }
      _emit(
        CreateWalletState(
          status: CreateWalletStatus.failure,
          failure: e.failure,
          biometricsAvailable: bio,
        ),
      );
      return;
    }
    if (enableBiometrics && bio) {
      await _biometrics.enable(walletName, password);
    }
    _emit(
      CreateWalletState(
        status: CreateWalletStatus.done,
        biometricsAvailable: bio,
      ),
    );
  }

  Future<List<String>> _existingNames() async {
    try {
      return await _wallet.walletNames();
    } on Object {
      return const [];
    }
  }

  void _emit(CreateWalletState next) {
    if (!isClosed) emit(next);
  }
}
```

`app/lib/features/onboarding/widgets/password_fields.dart`:

```dart
import 'package:digibyte_dex/domain/security/password_policy.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/l10n/policy_messages.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';

/// Password + confirm fields with the KDF rules and a strength meter
/// (spec §8.1). Shared by the create and restore pages.
class PasswordFields extends StatelessWidget {
  const PasswordFields({
    required this.idPrefix,
    required this.password,
    required this.confirm,
    required this.problems,
    required this.confirmMismatch,
    this.enabled = true,
    super.key,
  });

  final String idPrefix;
  final TextEditingController password;
  final TextEditingController confirm;
  final List<PasswordRule> problems;
  final bool confirmMismatch;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tagged(
          '$idPrefix.password',
          child: TextField(
            key: Key('$idPrefix.password'),
            controller: password,
            enabled: enabled,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onTapOutside: unfocusOnTapOutside,
            decoration: InputDecoration(
              labelText: l10n.passwordLabel,
              helperText: l10n.passwordRulesHint,
              helperMaxLines: 3,
              errorText: problems.isEmpty ? null : problems.first.message(l10n),
              errorMaxLines: 3,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: password,
          builder: (context, value, _) =>
              PasswordStrengthMeter(score: PasswordPolicy.strength(value.text)),
        ),
        const SizedBox(height: 16),
        Tagged(
          '$idPrefix.confirm',
          child: TextField(
            key: Key('$idPrefix.confirm'),
            controller: confirm,
            enabled: enabled,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onTapOutside: unfocusOnTapOutside,
            decoration: InputDecoration(
              labelText: l10n.confirmPasswordLabel,
              errorText: confirmMismatch ? l10n.passwordMismatch : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// Strength from [PasswordPolicy.strength]: 0 empty to 4 strong.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({required this.score, super.key});

  final int score;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final labels = [
      l10n.strengthEmpty,
      l10n.strengthWeak,
      l10n.strengthFair,
      l10n.strengthGood,
      l10n.strengthStrong,
    ];
    final color = switch (score) {
      0 => scheme.outline,
      1 => scheme.error,
      2 => scheme.tertiary,
      _ => scheme.primary,
    };
    return Row(
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: score / 4,
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(width: 12),
        Text(labels[score], key: const Key('password.strength')),
      ],
    );
  }
}
```

`app/lib/l10n/policy_messages.dart`:

```dart
import 'package:digibyte_dex/domain/security/password_policy.dart';
import 'package:digibyte_dex/domain/wallet_name_policy.dart';
import 'package:digibyte_dex/l10n/l10n.dart';

extension PasswordRuleMessage on PasswordRule {
  String message(AppLocalizations l10n) => switch (this) {
    PasswordRule.containsPassword => l10n.ruleContainsPassword,
    PasswordRule.tooShort => l10n.ruleTooShort,
    PasswordRule.missingDigit => l10n.ruleMissingDigit,
    PasswordRule.missingLowercase => l10n.ruleMissingLowercase,
    PasswordRule.missingUppercase => l10n.ruleMissingUppercase,
    PasswordRule.missingSpecial => l10n.ruleMissingSpecial,
    PasswordRule.tripleRepeat => l10n.ruleTripleRepeat,
  };
}

extension WalletNameProblemMessage on WalletNameProblem {
  String message(AppLocalizations l10n) => switch (this) {
    WalletNameProblem.empty => l10n.nameEmpty,
    WalletNameProblem.invalidCharacters => l10n.nameInvalidCharacters,
    WalletNameProblem.tooLong => l10n.nameTooLong,
    WalletNameProblem.taken => l10n.nameTaken,
  };
}
```

`app/lib/features/onboarding/view/create_wallet_page.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/onboarding/bloc/create_wallet_cubit.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:digibyte_dex/features/onboarding/widgets/password_fields.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/l10n/policy_messages.dart';
import 'package:digibyte_dex/l10n/wallet_failure_messages.dart';
import 'package:digibyte_dex/widgets/busy_indicator.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Create a new HD wallet (spec §5.1). On success the router moves on to
/// the backup page, because the new wallet is backup-pending.
class CreateWalletPage extends StatelessWidget {
  const CreateWalletPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) {
      final cubit = CreateWalletCubit(
        wallet: context.read<WalletRepository>(),
        backups: context.read<BackupStatusStore>(),
        session: context.read<PendingBackupSession>(),
        biometrics: context.read<BiometricStore>(),
      );
      unawaited(cubit.init());
      return cubit;
    },
    child: const _CreateWalletView(),
  );
}

class _CreateWalletView extends StatefulWidget {
  const _CreateWalletView();

  @override
  State<_CreateWalletView> createState() => _CreateWalletViewState();
}

class _CreateWalletViewState extends State<_CreateWalletView> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _enableBiometrics = false;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() => unawaited(
    context.read<CreateWalletCubit>().submit(
      name: _name.text,
      password: _password.text,
      confirm: _confirm.text,
      enableBiometrics: _enableBiometrics,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<CreateWalletCubit, CreateWalletState>(
      builder: (context, state) {
        final busy =
            state.status == CreateWalletStatus.submitting ||
            state.status == CreateWalletStatus.done;
        return Scaffold(
          appBar: AppBar(title: Text(l10n.createTitle)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Tagged(
                  'create.name',
                  child: TextField(
                    key: const Key('create.name'),
                    controller: _name,
                    enabled: !busy,
                    autocorrect: false,
                    onTapOutside: unfocusOnTapOutside,
                    decoration: InputDecoration(
                      labelText: l10n.walletNameLabel,
                      errorText: state.nameProblem?.message(l10n),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                PasswordFields(
                  idPrefix: 'create',
                  password: _password,
                  confirm: _confirm,
                  problems: state.passwordProblems,
                  confirmMismatch: state.confirmMismatch,
                  enabled: !busy,
                ),
                if (state.biometricsAvailable)
                  Tagged(
                    'create.biometrics',
                    child: CheckboxListTile(
                      key: const Key('create.biometrics'),
                      contentPadding: EdgeInsets.zero,
                      value: _enableBiometrics,
                      onChanged: busy
                          ? null
                          : (value) => setState(
                              () => _enableBiometrics = value ?? false,
                            ),
                      title: Text(l10n.enableBiometrics),
                    ),
                  ),
                if (state.failure case final failure?) ...[
                  const SizedBox(height: 8),
                  Text(
                    failure.message(l10n),
                    key: const Key('create.error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Tagged(
                  'create.submit',
                  child: FilledButton(
                    key: const Key('create.submit'),
                    onPressed: busy ? null : _submit,
                    child: busy
                        ? const BusyIndicator('create.busy')
                        : Text(l10n.createSubmit),
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
```

Replace `app/lib/features/onboarding/view/welcome_page.dart` with:

```dart
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Entry point without a session: create, restore, or sign in.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = context.watch<AuthCubit>().state;
    final hasWallets = auth is AuthSignedOut && auth.walletNames.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.welcomeTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l10n.welcomeIntro, textAlign: TextAlign.center),
            const SizedBox(height: 32),
            Tagged(
              'welcome.create',
              child: FilledButton(
                key: const Key('welcome.create'),
                onPressed: () => context.go(Routes.create),
                child: Text(l10n.welcomeCreate),
              ),
            ),
            const SizedBox(height: 12),
            Tagged(
              'welcome.restore',
              child: OutlinedButton(
                key: const Key('welcome.restore'),
                onPressed: () => context.go(Routes.restore),
                child: Text(l10n.welcomeRestore),
              ),
            ),
            if (hasWallets) ...[
              const SizedBox(height: 12),
              Tagged(
                'welcome.signIn',
                child: TextButton(
                  key: const Key('welcome.signIn'),
                  onPressed: () => context.go(Routes.signIn),
                  child: Text(l10n.welcomeSignIn),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

In `app/lib/l10n/arb/app_en.arb`, add before the closing `}`, with a comma after the previous last entry:

```json
  "welcomeIntro": "Your DigiByte wallet. Your keys never leave this phone.",
  "welcomeCreate": "Create a new wallet",
  "welcomeRestore": "Restore from a seed phrase",
  "welcomeSignIn": "Sign in to an existing wallet",
  "createTitle": "Create wallet",
  "walletNameLabel": "Wallet name",
  "passwordLabel": "Password",
  "passwordRulesHint": "At least 8 characters with an uppercase letter, a lowercase letter, a digit and a symbol. No character three times in a row.",
  "confirmPasswordLabel": "Confirm password",
  "passwordMismatch": "Passwords don't match.",
  "enableBiometrics": "Unlock with fingerprint or face",
  "createSubmit": "Create wallet",
  "strengthEmpty": "Enter a password",
  "strengthWeak": "Weak",
  "strengthFair": "Fair",
  "strengthGood": "Good",
  "strengthStrong": "Strong",
  "ruleContainsPassword": "Don't use the word \"password\".",
  "ruleTooShort": "Use at least 8 characters.",
  "ruleMissingDigit": "Add a digit (0-9).",
  "ruleMissingLowercase": "Add a lowercase letter (a-z).",
  "ruleMissingUppercase": "Add an uppercase letter (A-Z).",
  "ruleMissingSpecial": "Add a symbol, such as ! or _.",
  "ruleTripleRepeat": "Don't repeat a character three times in a row.",
  "nameEmpty": "Enter a wallet name.",
  "nameInvalidCharacters": "Use only letters, digits, spaces, - and _.",
  "nameTooLong": "Use at most 32 characters.",
  "nameTaken": "A wallet with this name already exists."
```

In `app/lib/app/router.dart`:
- add `import 'package:digibyte_dex/features/onboarding/view/create_wallet_page.dart';` in sorted position;
- replace `appRoutes()` with:

```dart
/// The route table. Each page task adds its routes here.
List<RouteBase> appRoutes() => [
  GoRoute(
    path: Routes.splash,
    builder: (_, _) =>
        const Scaffold(body: Center(child: CircularProgressIndicator())),
  ),
  GoRoute(
    path: Routes.welcome,
    builder: (_, _) => const WelcomePage(),
    routes: [
      GoRoute(path: 'create', builder: (_, _) => const CreateWalletPage()),
    ],
  ),
  GoRoute(path: Routes.home, builder: (_, _) => const HomePage()),
];
```

In `app/lib/main.dart`:
- add `import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';` in sorted position;
- after `final backups = BackupStatusStore(storage);`, add `final session = PendingBackupSession();`;
- in `providers:`, after `RepositoryProvider.value(value: backups),`, add `RepositoryProvider.value(value: session),`;
- change the `LockCubit` `create:` to:

```dart
              create: (context) => LockCubit(
                authStates: context.read<AuthCubit>().stream,
                onLocked: session.clear,
              ),
```

In `app/test/support/test_app.dart`:
- add `import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';`;
- add the field `final session = PendingBackupSession();` after `final biometrics = FakeBiometricStore();`;
- in `providers:` add `RepositoryProvider.value(value: session),`;
- change the constructor's lock line to `lock = LockCubit(authStates: auth.stream, now: () => now, onLocked: session.clear);`.

- [ ] **Step 4: Run the tests and the analyzer**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter gen-l10n
fvm dart format lib test
fvm flutter test test/features/onboarding test/app
fvm flutter analyze
fvm flutter test
```
Expected: all PASS; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add lib/widgets lib/features/onboarding lib/l10n lib/app/router.dart lib/main.dart test/support test/features/onboarding
git commit -m "feat(app): welcome and create-wallet pages (KDF password rules, strength meter, biometric opt-in)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 9: Backup — reveal and quiz pages with `BackupCubit`

**Files:**
- Create: `app/lib/features/onboarding/bloc/backup_cubit.dart`
- Create: `app/lib/features/onboarding/view/backup_page.dart`
- Modify: `app/lib/l10n/arb/app_en.arb`
- Modify: `app/lib/app/router.dart` (`appRoutes()`)
- Test: `app/test/features/onboarding/backup_cubit_test.dart`
- Test: `app/test/features/onboarding/backup_page_test.dart`
- Modify: `app/test/app/app_test.dart` (add the restart-mid-backup test)

**Interfaces:**
- Consumes:
  - `WalletRepository.revealSeed`, `WalletException` (Task 5);
  - `BackupStatusStore` (Task 4);
  - `PendingBackupSession` (Task 8);
  - `AuthCubit.refreshBackupStatus`, `AuthSignedIn` (Task 6);
  - `SecureScreen` (Task 7);
  - `Tagged`, `BusyIndicator`, `unfocusOnTapOutside` (Task 8);
  - `WalletFailureMessage` (Task 5).
- Produces:
  - `sealed class BackupState` (with `stringify` off), whose states are:
    - `BackupStarting()`, `BackupNeedsPassword({WalletFailure? failure, bool busy = false})`;
    - `BackupShowingWords(List<String> words)`;
    - `BackupQuizzing(List<QuizQuestion> questions, {Map<int, String> selections})`, with `bool get isComplete` and `BackupQuizzing withSelection(int question, String word)`;
    - `BackupQuizFailed()`, `BackupDone()`.
  - `class QuizQuestion { const QuizQuestion({required int position, required List<String> options}); }`, where `position` is 1-based
  - `class BackupCubit { BackupCubit({required String walletName, required WalletRepository wallet, required BackupStatusStore backups, required PendingBackupSession session, required Future<void> Function() onCompleted, Random? random}); static const int questionCount = 4; static const int optionCount = 4; Future<void> start(); Future<void> submitPassword(String); void startQuiz(); void select(int question, String word); Future<void> checkAnswers(); void startOver(); }`
  - Widget keys and identifiers:
    - `backup.password`, `backup.reveal`, `backup.busy`;
    - `backup.word.<n>` (n = 1..24; the node text is the word only), `backup.continue`;
    - `backup.quiz.<k>.word<position>` (question k = 0..3), `backup.quiz.<k>.option.<j>` (j = 0..3);
    - `backup.check`, `backup.startOver`.

- [ ] **Step 1: Write the failing tests**

`app/test/features/onboarding/backup_cubit_test.dart`:

```dart
import 'dart:math';

import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/onboarding/bloc/backup_cubit.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';

void main() {
  late FakeWalletRepository repo;
  late BackupStatusStore backups;
  late PendingBackupSession session;
  late int completions;

  setUp(() async {
    repo = FakeWalletRepository();
    backups = BackupStatusStore(InMemoryKeyValueStore());
    session = PendingBackupSession();
    completions = 0;
    await backups.markPending('main');
  });
  tearDown(() => repo.dispose());

  BackupCubit build() {
    final cubit = BackupCubit(
      walletName: 'main',
      wallet: repo,
      backups: backups,
      session: session,
      onCompleted: () async => completions++,
      random: Random(7),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  void answerAll(BackupCubit cubit, {bool correct = true}) {
    final quiz = cubit.state as BackupQuizzing;
    for (var k = 0; k < quiz.questions.length; k++) {
      final q = quiz.questions[k];
      final right = repo.seedWords[q.position - 1];
      cubit.select(
        k,
        correct ? right : q.options.firstWhere((o) => o != right),
      );
    }
  }

  test('with the create session the words show at once', () async {
    session.start('main', repo.correctPassword);
    final cubit = build();
    await cubit.start();
    expect(cubit.state, BackupShowingWords(repo.seedWords));
  });

  test('after a restart the password is asked first', () async {
    final cubit = build();
    await cubit.start();
    expect(cubit.state, const BackupNeedsPassword());
    await cubit.submitPassword('Wrong-Horse-1');
    expect(
      cubit.state,
      const BackupNeedsPassword(failure: WalletFailure.wrongPassword),
    );
    await cubit.submitPassword(repo.correctPassword);
    expect(cubit.state, BackupShowingWords(repo.seedWords));
    expect(await backups.isPending('main'), isTrue);
  });

  test('the quiz asks 4 distinct words, each among 4 options', () async {
    session.start('main', repo.correctPassword);
    final cubit = build();
    await cubit.start();
    cubit.startQuiz();
    final quiz = cubit.state as BackupQuizzing;
    expect(quiz.questions, hasLength(BackupCubit.questionCount));
    final positions = quiz.questions.map((q) => q.position).toSet();
    expect(positions, hasLength(BackupCubit.questionCount));
    for (final q in quiz.questions) {
      expect(q.options.toSet(), hasLength(BackupCubit.optionCount));
      expect(q.options, contains(repo.seedWords[q.position - 1]));
    }
  });

  test('all right: backup cleared, session cleared, router told', () async {
    session.start('main', repo.correctPassword);
    final cubit = build();
    await cubit.start();
    cubit.startQuiz();
    answerAll(cubit);
    expect((cubit.state as BackupQuizzing).isComplete, isTrue);
    await cubit.checkAnswers();
    expect(cubit.state, const BackupDone());
    expect(await backups.isPending('main'), isFalse);
    expect(session.passwordFor('main'), isNull);
    expect(completions, 1);
  });

  test('one wrong answer fails; start over shows the words again', () async {
    session.start('main', repo.correctPassword);
    final cubit = build();
    await cubit.start();
    cubit.startQuiz();
    answerAll(cubit, correct: false);
    await cubit.checkAnswers();
    expect(cubit.state, const BackupQuizFailed());
    expect(await backups.isPending('main'), isTrue);
    cubit.startOver();
    expect(cubit.state, BackupShowingWords(repo.seedWords));
  });

  test('states never print seed words', () async {
    session.start('main', repo.correctPassword);
    final cubit = build();
    await cubit.start();
    expect(cubit.state.toString(), isNot(contains('word1')));
    cubit.startQuiz();
    expect(cubit.state.toString(), isNot(contains('word')));
  });
}
```

`app/test/features/onboarding/backup_page_test.dart`:

```dart
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:digibyte_dex/features/onboarding/view/backup_page.dart';
import 'package:digibyte_dex/platform/platform_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeWalletRepository repo;
  late BackupStatusStore backups;
  late PendingBackupSession session;
  late AuthCubit auth;
  late List<bool> secureFlags;

  setUp(() async {
    repo = FakeWalletRepository();
    backups = BackupStatusStore(InMemoryKeyValueStore());
    session = PendingBackupSession();
    await backups.markPending('main');
    secureFlags = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, (call) async {
          final args = call.arguments as Map<Object?, Object?>;
          secureFlags.add(args['secure']! as bool);
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, null);
    await repo.dispose();
  });

  // The cubit is created inside the test body, so its stream callbacks run
  // in the tester's fake-async zone.
  Future<void> pump(WidgetTester t) async {
    auth = AuthCubit(repo, backups: backups);
    addTearDown(auth.close);
    repo.emit(const WalletUser('main'));
    // Let AuthCubit resolve the session first: the page reads its name.
    await t.pump();
    await pumpPage(
      t,
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<WalletRepository>.value(value: repo),
          RepositoryProvider.value(value: backups),
          RepositoryProvider.value(value: session),
        ],
        child: BlocProvider.value(value: auth, child: const BackupPage()),
      ),
    );
  }

  Finder byKeyPrefix(String prefix) => find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> && key.value.startsWith(prefix);
  });

  Future<void> answerQuiz(WidgetTester t) async {
    for (var k = 0; k < 4; k++) {
      final question = t.widget(byKeyPrefix('backup.quiz.$k.word'));
      final position = int.parse(
        (question.key! as ValueKey<String>).value.split('word').last,
      );
      final word = repo.seedWords[position - 1];
      for (var j = 0; j < 4; j++) {
        final option = find.byKey(Key('backup.quiz.$k.option.$j'));
        final label = find.descendant(of: option, matching: find.text(word));
        if (label.evaluate().isNotEmpty) {
          await tapKey(t, 'backup.quiz.$k.option.$j');
          break;
        }
      }
    }
  }

  testWidgets('screenshots are blocked while the backup is shown', (t) async {
    session.start('main', repo.correctPassword);
    await pump(t);
    expect(secureFlags, [true]);
    await t.pumpWidget(const SizedBox());
    expect(secureFlags, [true, false]);
  });

  testWidgets('24 numbered words that cannot be selected', (t) async {
    session.start('main', repo.correctPassword);
    await pump(t);
    expect(byKeyPrefix('backup.word.'), findsNWidgets(24));
    expect(find.text('word24'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('after a restart the password is asked first', (t) async {
    await pump(t);
    expect(find.byKey(const Key('backup.password')), findsOneWidget);
    await enterKey(t, 'backup.password', 'Wrong-Horse-1');
    await tapKey(t, 'backup.reveal');
    await t.pump();
    expect(find.text('Wrong password.'), findsOneWidget);
    await enterKey(t, 'backup.password', repo.correctPassword);
    await tapKey(t, 'backup.reveal');
    await t.pump();
    expect(byKeyPrefix('backup.word.'), findsNWidgets(24));
  });

  testWidgets('passing the quiz clears the pending backup', (t) async {
    session.start('main', repo.correctPassword);
    await pump(t);
    await tapKey(t, 'backup.continue');
    await answerQuiz(t);
    await tapKey(t, 'backup.check');
    await t.pump();
    expect(await backups.isPending('main'), isFalse);
    expect(auth.state, const AuthSignedIn(WalletUser('main')));
  });
}
```

Add this test inside `main()` of `app/test/app/app_test.dart`. The file's existing imports already cover it.

```dart
  testWidgets('a pending backup after restart forces the backup page '
      'and asks for the password', (t) async {
    final app = TestApp();
    addTearDown(app.dispose);
    await app.backups.markPending('main');
    await t.pumpWidget(app.build());
    app.wallet.emit(const WalletUser('main'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('backup.password')), findsOneWidget);
  });
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter test test/features/onboarding/backup_cubit_test.dart test/features/onboarding/backup_page_test.dart test/app/app_test.dart`
Expected: compile errors (`backup_cubit.dart` and `backup_page.dart` don't exist).

- [ ] **Step 3: Implement**

`app/lib/features/onboarding/bloc/backup_cubit.dart`:

```dart
import 'dart:math';

import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Backup states. `stringify` is off: some hold seed words, and Equatable
/// would otherwise print them in debug and test runs.
sealed class BackupState extends Equatable {
  const BackupState();

  @override
  List<Object?> get props => [];

  @override
  bool? get stringify => false;
}

final class BackupStarting extends BackupState {
  const BackupStarting();
}

/// The create session is gone (app killed or locked): ask again.
final class BackupNeedsPassword extends BackupState {
  const BackupNeedsPassword({this.failure, this.busy = false});

  final WalletFailure? failure;
  final bool busy;

  @override
  List<Object?> get props => [failure, busy];
}

final class BackupShowingWords extends BackupState {
  const BackupShowingWords(this.words);

  final List<String> words;

  @override
  List<Object?> get props => [words];
}

/// One quiz question: which word is number [position] (1-based)?
class QuizQuestion extends Equatable {
  const QuizQuestion({required this.position, required this.options});

  final int position;
  final List<String> options;

  @override
  List<Object?> get props => [position, options];

  @override
  bool? get stringify => false;
}

final class BackupQuizzing extends BackupState {
  const BackupQuizzing(this.questions, {this.selections = const {}});

  final List<QuizQuestion> questions;

  /// The chosen word per question index.
  final Map<int, String> selections;

  bool get isComplete => selections.length == questions.length;

  BackupQuizzing withSelection(int question, String word) =>
      BackupQuizzing(questions, selections: {...selections, question: word});

  @override
  List<Object?> get props => [questions, selections];
}

final class BackupQuizFailed extends BackupState {
  const BackupQuizFailed();
}

final class BackupDone extends BackupState {
  const BackupDone();
}

/// Reveal the 24 words, then check 4 of them (design note 10). The words
/// live only in this cubit, and only while the backup page is open.
class BackupCubit extends Cubit<BackupState> {
  BackupCubit({
    required this.walletName,
    required WalletRepository wallet,
    required BackupStatusStore backups,
    required PendingBackupSession session,
    required Future<void> Function() onCompleted,
    Random? random,
  }) : _wallet = wallet,
       _backups = backups,
       _session = session,
       _onCompleted = onCompleted,
       _random = random ?? Random.secure(),
       super(const BackupStarting());

  static const questionCount = 4;
  static const optionCount = 4;

  final String walletName;
  final WalletRepository _wallet;
  final BackupStatusStore _backups;
  final PendingBackupSession _session;
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
    await _reveal(password);
  }

  Future<void> submitPassword(String password) async {
    _emit(const BackupNeedsPassword(busy: true));
    await _reveal(password);
  }

  Future<void> _reveal(String password) async {
    try {
      _words = await _wallet.revealSeed(password);
      _emit(BackupShowingWords(List.unmodifiable(_words)));
    } on WalletException catch (e) {
      _emit(BackupNeedsPassword(failure: e.failure));
    }
  }

  void startQuiz() {
    final positions =
        (List.generate(_words.length, (i) => i)..shuffle(_random))
            .take(questionCount)
            .toList()
          ..sort();
    _emit(
      BackupQuizzing([
        for (final index in positions)
          QuizQuestion(position: index + 1, options: _optionsFor(index)),
      ]),
    );
  }

  // The right word plus three other, distinct words from the same seed.
  List<String> _optionsFor(int index) {
    final correct = _words[index];
    final decoys = (_words.toSet()..remove(correct)).toList()
      ..shuffle(_random);
    return [correct, ...decoys.take(optionCount - 1)]..shuffle(_random);
  }

  void select(int question, String word) {
    final current = state;
    if (current is BackupQuizzing) {
      _emit(current.withSelection(question, word));
    }
  }

  Future<void> checkAnswers() async {
    final current = state;
    if (current is! BackupQuizzing || !current.isComplete) return;
    final allRight = [
      for (var k = 0; k < current.questions.length; k++)
        current.selections[k] == _words[current.questions[k].position - 1],
    ].every((ok) => ok);
    if (!allRight) {
      _emit(const BackupQuizFailed());
      return;
    }
    await _backups.clear(walletName);
    _session.clear();
    _words = const [];
    _emit(const BackupDone());
    await _onCompleted();
  }

  void startOver() => _emit(BackupShowingWords(List.unmodifiable(_words)));

  void _emit(BackupState next) {
    if (!isClosed) emit(next);
  }
}
```

`app/lib/features/onboarding/view/backup_page.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/onboarding/bloc/backup_cubit.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/l10n/wallet_failure_messages.dart';
import 'package:digibyte_dex/widgets/busy_indicator.dart';
import 'package:digibyte_dex/widgets/secure_screen.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The forced seed backup after create (design note 10): reveal, then quiz.
/// Screenshots are blocked; the words are never selectable or copyable.
class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthCubit>().state;
    final walletName = auth is AuthSignedIn ? auth.user.name : '';
    return BlocProvider(
      create: (context) {
        final cubit = BackupCubit(
          walletName: walletName,
          wallet: context.read<WalletRepository>(),
          backups: context.read<BackupStatusStore>(),
          session: context.read<PendingBackupSession>(),
          onCompleted: context.read<AuthCubit>().refreshBackupStatus,
        );
        unawaited(cubit.start());
        return cubit;
      },
      child: const SecureScreen(
        child: PopScope(canPop: false, child: _BackupView()),
      ),
    );
  }
}

class _BackupView extends StatelessWidget {
  const _BackupView();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.l10n.backupTitle),
      automaticallyImplyLeading: false,
    ),
    body: SafeArea(
      child: BlocBuilder<BackupCubit, BackupState>(
        builder: (context, state) => switch (state) {
          BackupStarting() || BackupDone() => const Center(
            child: CircularProgressIndicator(),
          ),
          BackupNeedsPassword() => _PasswordPrompt(state: state),
          BackupShowingWords(:final words) => _WordList(words: words),
          BackupQuizzing() => _Quiz(state: state),
          BackupQuizFailed() => const _QuizFailed(),
        },
      ),
    ),
  );
}

class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt({required this.state});

  final BackupNeedsPassword state;

  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = widget.state.busy;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(l10n.backupPasswordPrompt),
        const SizedBox(height: 16),
        Tagged(
          'backup.password',
          child: TextField(
            key: const Key('backup.password'),
            controller: _password,
            enabled: !busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onTapOutside: unfocusOnTapOutside,
            decoration: InputDecoration(
              labelText: l10n.passwordLabel,
              errorText: widget.state.failure?.message(l10n),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Tagged(
          'backup.reveal',
          child: FilledButton(
            key: const Key('backup.reveal'),
            onPressed: busy
                ? null
                : () => unawaited(
                    context.read<BackupCubit>().submitPassword(_password.text),
                  ),
            child: busy
                ? const BusyIndicator('backup.busy')
                : Text(l10n.backupReveal),
          ),
        ),
      ],
    );
  }
}

class _WordList extends StatelessWidget {
  const _WordList({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.backupWordsIntro(words.length),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(l10n.backupWordsWarning),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.6,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (var i = 0; i < words.length; i++)
              _WordTile(number: i + 1, word: words[i]),
          ],
        ),
        const SizedBox(height: 24),
        Tagged(
          'backup.continue',
          child: FilledButton(
            key: const Key('backup.continue'),
            onPressed: context.read<BackupCubit>().startQuiz,
            child: Text(l10n.backupContinue),
          ),
        ),
      ],
    );
  }
}

class _WordTile extends StatelessWidget {
  const _WordTile({required this.number, required this.word});

  final int number;
  final String word;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Text('$number.', style: TextStyle(color: scheme.outline)),
            const SizedBox(width: 6),
            Expanded(
              child: Tagged(
                'backup.word.$number',
                child: Text(
                  word,
                  key: Key('backup.word.$number'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Quiz extends StatelessWidget {
  const _Quiz({required this.state});

  final BackupQuizzing state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<BackupCubit>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.quizIntro),
        for (var k = 0; k < state.questions.length; k++) ...[
          const SizedBox(height: 16),
          Tagged(
            'backup.quiz.$k.word${state.questions[k].position}',
            child: Text(
              l10n.quizQuestion(state.questions[k].position),
              key: Key('backup.quiz.$k.word${state.questions[k].position}'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var j = 0; j < state.questions[k].options.length; j++)
                Tagged(
                  'backup.quiz.$k.option.$j',
                  child: ChoiceChip(
                    key: Key('backup.quiz.$k.option.$j'),
                    label: Text(state.questions[k].options[j]),
                    selected:
                        state.selections[k] == state.questions[k].options[j],
                    onSelected: (_) =>
                        cubit.select(k, state.questions[k].options[j]),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Tagged(
          'backup.check',
          child: FilledButton(
            key: const Key('backup.check'),
            onPressed: state.isComplete
                ? () => unawaited(cubit.checkAnswers())
                : null,
            child: Text(l10n.quizCheck),
          ),
        ),
      ],
    );
  }
}

class _QuizFailed extends StatelessWidget {
  const _QuizFailed();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.quizFailed, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Tagged(
            'backup.startOver',
            child: FilledButton(
              key: const Key('backup.startOver'),
              onPressed: context.read<BackupCubit>().startOver,
              child: Text(l10n.quizStartOver),
            ),
          ),
        ],
      ),
    );
  }
}
```

In `app/lib/l10n/arb/app_en.arb`, add before the closing `}`, with a comma after the previous last entry:

```json
  "backupTitle": "Back up your wallet",
  "backupPasswordPrompt": "Enter your wallet password to show your seed phrase.",
  "backupReveal": "Show seed phrase",
  "backupWordsIntro": "Write down these {count} words, in order.",
  "@backupWordsIntro": {"placeholders": {"count": {"type": "int"}}},
  "backupWordsWarning": "Anyone with these words can take your funds. Never share them or type them into a website. Keep them offline. You can't copy them, and screenshots are blocked.",
  "backupContinue": "I've written them down",
  "quizIntro": "Pick the right word for each number.",
  "quizQuestion": "Word #{position}",
  "@quizQuestion": {"placeholders": {"position": {"type": "int"}}},
  "quizCheck": "Check",
  "quizFailed": "That's not right. Look at your words again, then start over.",
  "quizStartOver": "Start over"
```

In `app/lib/app/router.dart`:
- add `import 'package:digibyte_dex/features/onboarding/view/backup_page.dart';` in sorted position;
- in `appRoutes()`, extend the welcome sub-routes:

```dart
    routes: [
      GoRoute(path: 'create', builder: (_, _) => const CreateWalletPage()),
      GoRoute(path: 'backup', builder: (_, _) => const BackupPage()),
    ],
```

- [ ] **Step 4: Run the tests and the analyzer**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter gen-l10n
fvm dart format lib test
fvm flutter test test/features/onboarding test/app
fvm flutter analyze
fvm flutter test
```
Expected: all PASS; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add lib/features/onboarding lib/l10n/arb/app_en.arb lib/app/router.dart test/features/onboarding test/app/app_test.dart
git commit -m "feat(app): forced seed backup (secure reveal, 4-word quiz, restart-safe)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 10: Restore page — seed entry, legacy switch, name and password, with `RestoreWalletCubit`

**Files:**
- Create: `app/lib/features/onboarding/bloc/restore_wallet_cubit.dart`
- Create: `app/lib/features/onboarding/view/restore_wallet_page.dart`
- Create: `app/lib/l10n/seed_messages.dart`
- Modify: `app/lib/l10n/arb/app_en.arb`
- Modify: `app/lib/app/router.dart` (`appRoutes()`)
- Modify: `app/lib/main.dart` (seed validator)
- Create: `app/test/support/fake_seed_validator.dart`
- Modify: `app/test/support/test_app.dart` (seed validator)
- Test: `app/test/features/onboarding/restore_wallet_cubit_test.dart`
- Test: `app/test/features/onboarding/restore_wallet_page_test.dart`

**Interfaces:**
- Consumes:
  - `SeedPhrase`, `SeedValidator`, `SdkSeedValidator`, `SeedCheck` and its subclasses, `WalletNamePolicy`, `PasswordPolicy` (Task 3);
  - `WalletRepository.restore` (Task 5);
  - `BackupStatusStore`, `BiometricStore` (Task 4);
  - `SecureScreen` (Task 7);
  - `PasswordFields`, `Tagged`, `BusyIndicator`, `unfocusOnTapOutside`, `PasswordRuleMessage`, `WalletNameProblemMessage` (Task 8);
  - `WalletFailureMessage` (Task 5).
- Produces:
  - `enum RestoreWalletStatus { editing, submitting, failure, done }`
  - `class RestoreWalletState`, with fields `status`, `seedProblem` (`SeedCheck?`, never a `SeedAccepted`), `nameProblem`, `passwordProblems`, `confirmMismatch`, `failure` and `biometricsAvailable`
  - `class RestoreWalletCubit { RestoreWalletCubit({required WalletRepository wallet, required SeedValidator seeds, required BackupStatusStore backups, required BiometricStore biometrics}); Future<void> init(); Future<void> submit({required String seed, required bool legacy, required String name, required String password, required String confirm, required bool enableBiometrics}); }`
  - `extension SeedCheckMessage on SeedCheck { String? message(AppLocalizations l10n); }`
  - Widget keys and identifiers: `restore.seed`, `restore.seedVisibility`, `restore.legacy`, `restore.name`, `restore.password`, `restore.confirm`, `restore.biometrics`, `restore.error`, `restore.submit`, `restore.busy`.
  - Test support: `FakeSeedValidator` (fields `result`, `lastLegacy`, `checks`) and `TestApp.seeds`.

- [ ] **Step 1: Write the fake and the failing tests**

`app/test/support/fake_seed_validator.dart`:

```dart
import 'package:digibyte_dex/domain/seed/seed_phrase.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';

class FakeSeedValidator implements SeedValidator {
  SeedCheck result = const SeedBadChecksum();
  bool? lastLegacy;
  int checks = 0;

  @override
  Future<void> init() async {}

  @override
  SeedCheck check(SeedPhrase seed, {required bool legacy}) {
    checks++;
    lastLegacy = legacy;
    return result;
  }
}
```

`app/test/features/onboarding/restore_wallet_cubit_test.dart`:

```dart
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';
import 'package:digibyte_dex/features/onboarding/bloc/restore_wallet_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

import '../../support/fake_biometric_store.dart';
import '../../support/fake_seed_validator.dart';
import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';

const _pw = 'Correct-Horse-9';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeWalletRepository repo;
  late FakeSeedValidator seeds;
  late InMemoryKeyValueStore storage;
  late FakeBiometricStore biometrics;

  setUp(() {
    repo = FakeWalletRepository();
    seeds = FakeSeedValidator();
    storage = InMemoryKeyValueStore();
    biometrics = FakeBiometricStore();
  });
  tearDown(() => repo.dispose());

  RestoreWalletCubit build({SeedValidator? validator}) {
    final cubit = RestoreWalletCubit(
      wallet: repo,
      seeds: validator ?? seeds,
      backups: BackupStatusStore(storage),
      biometrics: biometrics,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Future<void> submit(
    RestoreWalletCubit cubit, {
    String seed = 'any seed text',
    bool legacy = false,
    String name = 'main',
    bool enableBiometrics = false,
  }) => cubit.submit(
    seed: seed,
    legacy: legacy,
    name: name,
    password: _pw,
    confirm: _pw,
    enableBiometrics: enableBiometrics,
  );

  test('a messy paste reaches the repository normalized', () async {
    // Public BIP39 test vector, pasted upper-case with tabs and newlines.
    final valid24 = '${List.filled(23, 'abandon').join(' ')} art';
    final validator = SdkSeedValidator(MnemonicValidator());
    await validator.init();
    final cubit = build(validator: validator);
    await submit(
      cubit,
      seed: '\n  ${valid24.toUpperCase().replaceAll(' ', ' \t\n ')}  \n',
    );
    expect(cubit.state.status, RestoreWalletStatus.done);
    expect(repo.lastSeed, SeedAccepted(valid24, isBip39: true));
    expect(repo.lastLegacy, isFalse);
  });

  test('an invalid seed never registers anything', () async {
    seeds.result = const SeedUnknownWord(3);
    final cubit = build();
    await submit(cubit);
    expect(cubit.state.seedProblem, const SeedUnknownWord(3));
    expect(repo.calls, isEmpty);
  });

  test('the legacy switch restores as iguana, seed text verbatim', () async {
    seeds.result = const SeedAccepted('My Old Seed', isBip39: false);
    final cubit = build();
    await submit(cubit, legacy: true);
    expect(seeds.lastLegacy, isTrue);
    expect(repo.lastLegacy, isTrue);
    expect(
      repo.lastSeed,
      const SeedAccepted('My Old Seed', isBip39: false),
    );
  });

  test('a stale backup flag for the name is cleared', () async {
    seeds.result = const SeedAccepted('alpha', isBip39: true);
    await BackupStatusStore(storage).markPending('main');
    final cubit = build();
    await submit(cubit);
    expect(repo.calls, ['restore:main']);
    expect(await BackupStatusStore(storage).isPending('main'), isFalse);
  });

  test('an engine failure is shown', () async {
    seeds.result = const SeedAccepted('alpha', isBip39: true);
    repo.restoreFailure = WalletFailure.walletExists;
    final cubit = build();
    await submit(cubit);
    expect(cubit.state.status, RestoreWalletStatus.failure);
    expect(cubit.state.failure, WalletFailure.walletExists);
  });

  test('biometric opt-in stores the password after restore', () async {
    seeds.result = const SeedAccepted('alpha', isBip39: true);
    final cubit = build();
    await cubit.init();
    await submit(cubit, enableBiometrics: true);
    expect(biometrics.passwords['main'], _pw);
  });
}
```

`app/test/features/onboarding/restore_wallet_page_test.dart`:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';
import 'package:digibyte_dex/features/onboarding/view/restore_wallet_page.dart';
import 'package:digibyte_dex/platform/platform_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_biometric_store.dart';
import '../../support/fake_seed_validator.dart';
import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/pump_app.dart';

const _pw = 'Correct-Horse-9';

void main() {
  late FakeWalletRepository repo;
  late FakeSeedValidator seeds;
  late List<bool> secureFlags;

  setUp(() {
    repo = FakeWalletRepository();
    seeds = FakeSeedValidator();
    secureFlags = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, (call) async {
          final args = call.arguments as Map<Object?, Object?>;
          secureFlags.add(args['secure']! as bool);
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, null);
    await repo.dispose();
  });

  Future<void> pump(WidgetTester t) => pumpPage(
    t,
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<WalletRepository>.value(value: repo),
        RepositoryProvider<SeedValidator>.value(value: seeds),
        RepositoryProvider.value(
          value: BackupStatusStore(InMemoryKeyValueStore()),
        ),
        RepositoryProvider<BiometricStore>.value(value: FakeBiometricStore()),
      ],
      child: const RestoreWalletPage(),
    ),
  );

  bool seedHidden(WidgetTester t) =>
      t.widget<TextField>(find.byKey(const Key('restore.seed'))).obscureText;

  Future<void> fillAndSubmit(WidgetTester t) async {
    await enterKey(t, 'restore.seed', 'some seed words');
    await enterKey(t, 'restore.name', 'main');
    await enterKey(t, 'restore.password', _pw);
    await enterKey(t, 'restore.confirm', _pw);
    await tapKey(t, 'restore.submit');
    await t.pump();
  }

  testWidgets('seed entry blocks screenshots', (t) async {
    await pump(t);
    expect(secureFlags, [true]);
  });

  testWidgets('the seed is hidden until the user reveals it', (t) async {
    await pump(t);
    expect(seedHidden(t), isTrue);
    await tapKey(t, 'restore.seedVisibility');
    expect(seedHidden(t), isFalse);
  });

  testWidgets('a seed problem is shown on the seed field', (t) async {
    seeds.result = const SeedUnknownWord(3);
    await pump(t);
    await fillAndSubmit(t);
    expect(
      find.text("Word 3 isn't a valid seed word. Check the spelling."),
      findsOneWidget,
    );
    expect(repo.calls, isEmpty);
  });

  testWidgets('the legacy switch restores as iguana', (t) async {
    seeds.result = const SeedAccepted('some seed words', isBip39: false);
    await pump(t);
    await tapKey(t, 'restore.legacy');
    await fillAndSubmit(t);
    expect(seeds.lastLegacy, isTrue);
    expect(repo.lastLegacy, isTrue);
    expect(repo.calls, ['restore:main']);
  });
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter test test/features/onboarding/restore_wallet_cubit_test.dart test/features/onboarding/restore_wallet_page_test.dart`
Expected: compile errors (`restore_wallet_cubit.dart` and `restore_wallet_page.dart` don't exist).

- [ ] **Step 3: Implement**

`app/lib/features/onboarding/bloc/restore_wallet_cubit.dart`:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/domain/security/password_policy.dart';
import 'package:digibyte_dex/domain/seed/seed_phrase.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';
import 'package:digibyte_dex/domain/wallet_name_policy.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum RestoreWalletStatus { editing, submitting, failure, done }

class RestoreWalletState extends Equatable {
  const RestoreWalletState({
    this.status = RestoreWalletStatus.editing,
    this.seedProblem,
    this.nameProblem,
    this.passwordProblems = const [],
    this.confirmMismatch = false,
    this.failure,
    this.biometricsAvailable = false,
  });

  final RestoreWalletStatus status;

  /// Why the seed was refused. Never a [SeedAccepted].
  final SeedCheck? seedProblem;
  final WalletNameProblem? nameProblem;
  final List<PasswordRule> passwordProblems;
  final bool confirmMismatch;
  final WalletFailure? failure;
  final bool biometricsAvailable;

  @override
  List<Object?> get props => [
    status,
    seedProblem,
    nameProblem,
    passwordProblems,
    confirmMismatch,
    failure,
    biometricsAvailable,
  ];
}

/// The restore flow (design note 4):
/// 1. normalise and validate the seed BEFORE register;
/// 2. HD by default, iguana with the legacy switch;
/// 3. no backup is owed.
class RestoreWalletCubit extends Cubit<RestoreWalletState> {
  RestoreWalletCubit({
    required WalletRepository wallet,
    required SeedValidator seeds,
    required BackupStatusStore backups,
    required BiometricStore biometrics,
  }) : _wallet = wallet,
       _seeds = seeds,
       _backups = backups,
       _biometrics = biometrics,
       super(const RestoreWalletState());

  final WalletRepository _wallet;
  final SeedValidator _seeds;
  final BackupStatusStore _backups;
  final BiometricStore _biometrics;

  Future<void> init() async {
    final available = await _biometrics.isAvailable();
    _emit(RestoreWalletState(biometricsAvailable: available));
  }

  Future<void> submit({
    required String seed,
    required bool legacy,
    required String name,
    required String password,
    required String confirm,
    required bool enableBiometrics,
  }) async {
    if (state.status == RestoreWalletStatus.submitting) return;
    final bio = state.biometricsAvailable;
    _emit(
      RestoreWalletState(
        status: RestoreWalletStatus.submitting,
        biometricsAvailable: bio,
      ),
    );
    final check = _seeds.check(SeedPhrase(seed), legacy: legacy);
    final walletName = name.trim();
    final nameProblem = WalletNamePolicy.check(
      walletName,
      await _existingNames(),
    );
    final passwordProblems = PasswordPolicy.violations(password);
    final mismatch = password != confirm;
    if (check is! SeedAccepted ||
        nameProblem != null ||
        passwordProblems.isNotEmpty ||
        mismatch) {
      _emit(
        RestoreWalletState(
          seedProblem: check is SeedAccepted ? null : check,
          nameProblem: nameProblem,
          passwordProblems: passwordProblems,
          confirmMismatch: mismatch,
          biometricsAvailable: bio,
        ),
      );
      return;
    }
    // A restored seed is already backed up. A flag left by an abandoned
    // create with the same name must not force a backup.
    await _backups.clear(walletName);
    try {
      await _wallet.restore(
        name: walletName,
        password: password,
        seed: check,
        legacy: legacy,
      );
    } on WalletException catch (e) {
      _emit(
        RestoreWalletState(
          status: RestoreWalletStatus.failure,
          failure: e.failure,
          biometricsAvailable: bio,
        ),
      );
      return;
    }
    if (enableBiometrics && bio) {
      await _biometrics.enable(walletName, password);
    }
    _emit(
      RestoreWalletState(
        status: RestoreWalletStatus.done,
        biometricsAvailable: bio,
      ),
    );
  }

  Future<List<String>> _existingNames() async {
    try {
      return await _wallet.walletNames();
    } on Object {
      return const [];
    }
  }

  void _emit(RestoreWalletState next) {
    if (!isClosed) emit(next);
  }
}
```

`app/lib/l10n/seed_messages.dart`:

```dart
import 'package:digibyte_dex/domain/seed/seed_validator.dart';
import 'package:digibyte_dex/l10n/l10n.dart';

extension SeedCheckMessage on SeedCheck {
  /// The problem to show, or null for an accepted seed.
  String? message(AppLocalizations l10n) => switch (this) {
    SeedAccepted() => null,
    SeedEmpty() => l10n.seedEmpty,
    SeedWrongLength(:final wordCount) => l10n.seedWrongLength(wordCount),
    SeedLegacyTooShort(:final wordCount) => l10n.seedLegacyTooShort(
      wordCount,
    ),
    SeedUnknownWord(:final position) => l10n.seedUnknownWord(position),
    SeedBadChecksum() => l10n.seedBadChecksum,
  };
}
```

`app/lib/features/onboarding/view/restore_wallet_page.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';
import 'package:digibyte_dex/features/onboarding/bloc/restore_wallet_cubit.dart';
import 'package:digibyte_dex/features/onboarding/widgets/password_fields.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/l10n/policy_messages.dart';
import 'package:digibyte_dex/l10n/seed_messages.dart';
import 'package:digibyte_dex/l10n/wallet_failure_messages.dart';
import 'package:digibyte_dex/widgets/busy_indicator.dart';
import 'package:digibyte_dex/widgets/secure_screen.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Restore from a seed phrase (spec §5.1). The seed field is hidden by
/// default and screenshots are blocked while it is open.
class RestoreWalletPage extends StatelessWidget {
  const RestoreWalletPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) {
      final cubit = RestoreWalletCubit(
        wallet: context.read<WalletRepository>(),
        seeds: context.read<SeedValidator>(),
        backups: context.read<BackupStatusStore>(),
        biometrics: context.read<BiometricStore>(),
      );
      unawaited(cubit.init());
      return cubit;
    },
    child: const SecureScreen(child: _RestoreWalletView()),
  );
}

class _RestoreWalletView extends StatefulWidget {
  const _RestoreWalletView();

  @override
  State<_RestoreWalletView> createState() => _RestoreWalletViewState();
}

class _RestoreWalletViewState extends State<_RestoreWalletView> {
  final _seed = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _seedHidden = true;
  bool _legacy = false;
  bool _enableBiometrics = false;

  @override
  void dispose() {
    _seed.dispose();
    _name.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() => unawaited(
    context.read<RestoreWalletCubit>().submit(
      seed: _seed.text,
      legacy: _legacy,
      name: _name.text,
      password: _password.text,
      confirm: _confirm.text,
      enableBiometrics: _enableBiometrics,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<RestoreWalletCubit, RestoreWalletState>(
      builder: (context, state) {
        final busy =
            state.status == RestoreWalletStatus.submitting ||
            state.status == RestoreWalletStatus.done;
        return Scaffold(
          appBar: AppBar(title: Text(l10n.restoreTitle)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Tagged(
                  'restore.seed',
                  child: TextField(
                    key: const Key('restore.seed'),
                    controller: _seed,
                    enabled: !busy,
                    obscureText: _seedHidden,
                    maxLines: _seedHidden ? 1 : 4,
                    minLines: 1,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    onTapOutside: unfocusOnTapOutside,
                    decoration: InputDecoration(
                      labelText: l10n.seedLabel,
                      errorText: state.seedProblem?.message(l10n),
                      errorMaxLines: 3,
                      suffixIcon: Tagged(
                        'restore.seedVisibility',
                        child: IconButton(
                          key: const Key('restore.seedVisibility'),
                          tooltip: _seedHidden ? l10n.seedShow : l10n.seedHide,
                          icon: Icon(
                            _seedHidden
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () =>
                              setState(() => _seedHidden = !_seedHidden),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Tagged(
                  'restore.legacy',
                  child: SwitchListTile(
                    key: const Key('restore.legacy'),
                    contentPadding: EdgeInsets.zero,
                    value: _legacy,
                    onChanged: busy
                        ? null
                        : (value) => setState(() => _legacy = value),
                    title: Text(l10n.legacySwitch),
                    subtitle: Text(l10n.legacySwitchHint),
                  ),
                ),
                const SizedBox(height: 8),
                Tagged(
                  'restore.name',
                  child: TextField(
                    key: const Key('restore.name'),
                    controller: _name,
                    enabled: !busy,
                    autocorrect: false,
                    onTapOutside: unfocusOnTapOutside,
                    decoration: InputDecoration(
                      labelText: l10n.walletNameLabel,
                      errorText: state.nameProblem?.message(l10n),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                PasswordFields(
                  idPrefix: 'restore',
                  password: _password,
                  confirm: _confirm,
                  problems: state.passwordProblems,
                  confirmMismatch: state.confirmMismatch,
                  enabled: !busy,
                ),
                if (state.biometricsAvailable)
                  Tagged(
                    'restore.biometrics',
                    child: CheckboxListTile(
                      key: const Key('restore.biometrics'),
                      contentPadding: EdgeInsets.zero,
                      value: _enableBiometrics,
                      onChanged: busy
                          ? null
                          : (value) => setState(
                              () => _enableBiometrics = value ?? false,
                            ),
                      title: Text(l10n.enableBiometrics),
                    ),
                  ),
                if (state.failure case final failure?) ...[
                  const SizedBox(height: 8),
                  Text(
                    failure.message(l10n),
                    key: const Key('restore.error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Tagged(
                  'restore.submit',
                  child: FilledButton(
                    key: const Key('restore.submit'),
                    onPressed: busy ? null : _submit,
                    child: busy
                        ? const BusyIndicator('restore.busy')
                        : Text(l10n.restoreSubmit),
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
```

In `app/lib/l10n/arb/app_en.arb`, add before the closing `}`, with a comma after the previous last entry:

```json
  "restoreTitle": "Restore wallet",
  "seedLabel": "Seed phrase",
  "seedShow": "Show seed phrase",
  "seedHide": "Hide seed phrase",
  "legacySwitch": "This seed is from the old DigiByte DEX app",
  "legacySwitchHint": "Turn on only for seeds created in the old app. Seeds from other wallets use the standard format.",
  "restoreSubmit": "Restore wallet",
  "seedEmpty": "Enter your seed phrase.",
  "seedWrongLength": "A seed phrase has 12, 15, 18, 21 or 24 words. This one has {count}.",
  "@seedWrongLength": {"placeholders": {"count": {"type": "int"}}},
  "seedLegacyTooShort": "Seeds from the old app have at least 12 words. This one has {count}.",
  "@seedLegacyTooShort": {"placeholders": {"count": {"type": "int"}}},
  "seedUnknownWord": "Word {position} isn't a valid seed word. Check the spelling.",
  "@seedUnknownWord": {"placeholders": {"position": {"type": "int"}}},
  "seedBadChecksum": "These words don't form a valid seed phrase. Check their order and spelling."
```

In `app/lib/app/router.dart`:
- add `import 'package:digibyte_dex/features/onboarding/view/restore_wallet_page.dart';` in sorted position;
- make the welcome sub-routes:

```dart
    routes: [
      GoRoute(path: 'create', builder: (_, _) => const CreateWalletPage()),
      GoRoute(path: 'restore', builder: (_, _) => const RestoreWalletPage()),
      GoRoute(path: 'backup', builder: (_, _) => const BackupPage()),
    ],
```

In `app/lib/main.dart`:
- add `import 'package:digibyte_dex/domain/seed/seed_validator.dart';` in sorted position;
- after `final session = PendingBackupSession();`, add:

```dart
    final seeds = SdkSeedValidator(sdk.mnemonicValidator);
    await seeds.init();
```

- in `providers:`, after the `WalletRepository` provider, add `RepositoryProvider<SeedValidator>.value(value: seeds),`.

In `app/test/support/test_app.dart`:
- add `import 'package:digibyte_dex/domain/seed/seed_validator.dart';` and `import 'fake_seed_validator.dart';`;
- add the field `final seeds = FakeSeedValidator();`;
- in `providers:`, add `RepositoryProvider<SeedValidator>.value(value: seeds),`.

- [ ] **Step 4: Run the tests and the analyzer**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter gen-l10n
fvm dart format lib test
fvm flutter test test/features/onboarding test/app
fvm flutter analyze
fvm flutter test
```
Expected: all PASS; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add lib/features/onboarding lib/l10n lib/app/router.dart lib/main.dart test/support test/features/onboarding
git commit -m "feat(app): restore from seed (normalised, validated before register, legacy iguana switch)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 11: Sign-in and Lock pages — `SignInCubit`, `UnlockCubit`, shared lockout via `PasswordAttempts`

**Files:**
- Create: `app/lib/features/auth/domain/password_attempts.dart`
- Create: `app/lib/features/auth/bloc/sign_in_cubit.dart`
- Create: `app/lib/features/auth/bloc/unlock_cubit.dart`
- Create: `app/lib/features/auth/widgets/lockout_countdown.dart`
- Create: `app/lib/features/auth/view/sign_in_page.dart`
- Create: `app/lib/features/auth/view/locked_page.dart`
- Modify: `app/lib/l10n/arb/app_en.arb`
- Modify: `app/lib/app/router.dart` (`appRoutes()`)
- Modify: `app/lib/main.dart` (`PasswordAttempts`)
- Modify: `app/test/support/test_app.dart` (`attempts`)
- Test: `app/test/features/auth/password_attempts_test.dart`
- Test: `app/test/features/auth/sign_in_cubit_test.dart`
- Test: `app/test/features/auth/unlock_cubit_test.dart`
- Test: `app/test/features/auth/lockout_countdown_test.dart`
- Test: `app/test/features/auth/sign_in_page_test.dart`
- Test: `app/test/features/auth/locked_page_test.dart`
- Modify: `app/test/app/app_test.dart` (sign-in, auto-lock and unlock end to end)

**Interfaces:**
- Consumes:
  - `LockoutStore`, `BiometricStore` (Task 4);
  - `WalletRepository.signIn` / `verifyPassword`, `WalletException`, `WalletFailure`, `WalletFailureMessage` (Task 5);
  - `AuthCubit`, `AuthSignedOut`, `AuthSignedIn`, `LockCubit.unlock`, `Routes` (Task 6);
  - `Tagged`, `BusyIndicator`, `unfocusOnTapOutside` (Task 8).
- Produces:
  - `class PasswordAttempts { PasswordAttempts(LockoutStore store, {DateTime Function()? now}); DateTime now(); Future<DateTime?> blockedUntil(String wallet); Future<DateTime?> fail(String wallet); Future<void> succeed(String wallet); }`
  - `enum SignInStatus { idle, busy }`
  - `class SignInState`, with fields `wallets`, `selected`, `status`, `failure`, `blockedUntil`, `biometricsAvailable`, `biometricsEnabled` and `biometricsInvalidated`
  - `class SignInCubit { SignInCubit({required WalletRepository wallet, required PasswordAttempts attempts, required BiometricStore biometrics}); Future<void> init(List<String> wallets); Future<void> select(String wallet); Future<void> signInWithPassword(String password, {bool enableBiometrics = false}); Future<void> signInWithBiometrics({required String reason}); void lockoutExpired(); }`
  - `enum UnlockStatus { idle, busy }`
  - `class UnlockState`, with the same lockout and biometric fields
  - `class UnlockCubit { UnlockCubit({required String walletName, required WalletRepository wallet, required PasswordAttempts attempts, required BiometricStore biometrics, required void Function() onUnlocked}); Future<void> init(); Future<void> unlockWithPassword(String password, {bool enableBiometrics = false}); Future<void> unlockWithBiometrics({required String reason}); void lockoutExpired(); }`
  - `class LockoutCountdown extends StatefulWidget { const LockoutCountdown({required String id, required DateTime until, required DateTime Function() now, required VoidCallback onExpired}); }`
  - Widget keys and identifiers:
    - sign-in: `signin.wallet` (dropdown, 2+ wallets), `signin.walletName`, `signin.password`, `signin.enableBiometrics`, `signin.bioInvalidated`, `signin.lockout`, `signin.submit`, `signin.busy`, `signin.biometric`, `signin.other`;
    - lock: `locked.password`, `locked.enableBiometrics`, `locked.bioInvalidated`, `locked.lockout`, `locked.submit`, `locked.busy`, `locked.biometric`.
  - Test support: `TestApp.attempts`.

- [ ] **Step 1: Write the failing tests**

`app/test/features/auth/password_attempts_test.dart`:

```dart
import 'package:digibyte_dex/data/storage/lockout_store.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';

void main() {
  test('the lockout survives a restart and ends on time', () async {
    final storage = InMemoryKeyValueStore();
    var now = DateTime.utc(2026, 10, 1, 12);
    final first = PasswordAttempts(LockoutStore(storage), now: () => now);
    for (var i = 0; i < 4; i++) {
      expect(await first.fail('w'), isNull);
    }
    expect(await first.fail('w'), now.add(const Duration(seconds: 30)));

    final restarted = PasswordAttempts(LockoutStore(storage), now: () => now);
    expect(
      await restarted.blockedUntil('w'),
      now.add(const Duration(seconds: 30)),
    );
    now = now.add(const Duration(seconds: 31));
    expect(await restarted.blockedUntil('w'), isNull);
  });

  test('success forgets the failures', () async {
    final storage = InMemoryKeyValueStore();
    final now = DateTime.utc(2026, 10, 1, 12);
    final attempts = PasswordAttempts(LockoutStore(storage), now: () => now);
    for (var i = 0; i < 4; i++) {
      await attempts.fail('w');
    }
    await attempts.succeed('w');
    expect(await attempts.fail('w'), isNull);
  });
}
```

`app/test/features/auth/sign_in_cubit_test.dart`:

```dart
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
import 'package:digibyte_dex/features/auth/bloc/sign_in_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_biometric_store.dart';
import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';

const _pw = 'Correct-Horse-9';
const _wrong = 'Wrong-Horse-1';

void main() {
  late FakeWalletRepository repo;
  late InMemoryKeyValueStore storage;
  late FakeBiometricStore biometrics;
  late DateTime now;

  setUp(() {
    repo = FakeWalletRepository();
    storage = InMemoryKeyValueStore();
    biometrics = FakeBiometricStore();
    now = DateTime.utc(2026, 10, 1, 12);
  });
  tearDown(() => repo.dispose());

  Future<SignInCubit> build({List<String> wallets = const ['main']}) async {
    final cubit = SignInCubit(
      wallet: repo,
      attempts: PasswordAttempts(LockoutStore(storage), now: () => now),
      biometrics: biometrics,
    );
    addTearDown(cubit.close);
    await cubit.init(wallets);
    return cubit;
  }

  Future<void> failFive(SignInCubit cubit) async {
    for (var i = 0; i < 5; i++) {
      await cubit.signInWithPassword(_wrong);
    }
  }

  test('selects the first wallet', () async {
    final cubit = await build(wallets: ['main', 'cold']);
    expect(cubit.state.selected, 'main');
    expect(cubit.state.wallets, ['main', 'cold']);
  });

  test('wrong passwords count; the fifth locks for 30 s', () async {
    final cubit = await build();
    for (var i = 0; i < 4; i++) {
      await cubit.signInWithPassword(_wrong);
      expect(cubit.state.failure, WalletFailure.wrongPassword);
      expect(cubit.state.blockedUntil, isNull);
    }
    await cubit.signInWithPassword(_wrong);
    expect(cubit.state.blockedUntil, now.add(const Duration(seconds: 30)));
  });

  test('while locked out, attempts never reach KDF', () async {
    final cubit = await build();
    await failFive(cubit);
    repo.calls.clear();
    await cubit.signInWithPassword(_pw);
    expect(cubit.state.failure, WalletFailure.lockedOut);
    expect(repo.calls, isEmpty);
    now = now.add(const Duration(seconds: 31));
    cubit.lockoutExpired();
    expect(cubit.state.blockedUntil, isNull);
    await cubit.signInWithPassword(_pw);
    expect(repo.calls, ['signIn:main']);
  });

  test('the lockout survives a restart', () async {
    await failFive(await build());
    final restarted = await build();
    expect(restarted.state.blockedUntil, now.add(const Duration(seconds: 30)));
    expect(restarted.state.failure, WalletFailure.lockedOut);
  });

  test('a success resets the count', () async {
    final cubit = await build();
    for (var i = 0; i < 3; i++) {
      await cubit.signInWithPassword(_wrong);
    }
    await cubit.signInWithPassword(_pw);
    expect(storage.values.containsKey('lockout_main'), isFalse);
  });

  test('biometric sign-in uses the stored password', () async {
    biometrics.passwords['main'] = _pw;
    final cubit = await build();
    expect(cubit.state.biometricsEnabled, isTrue);
    await cubit.signInWithBiometrics(reason: 'why');
    expect(repo.calls, ['signIn:main']);
  });

  test('invalidated biometrics fall back to the password', () async {
    biometrics
      ..passwords['main'] = _pw
      ..invalidated = true;
    final cubit = await build();
    await cubit.signInWithBiometrics(reason: 'why');
    expect(cubit.state.biometricsInvalidated, isTrue);
    expect(cubit.state.biometricsEnabled, isFalse);
    expect(repo.calls, isEmpty);
  });

  test('opting in on a password sign-in enables biometrics', () async {
    final cubit = await build();
    await cubit.signInWithPassword(_pw, enableBiometrics: true);
    expect(biometrics.passwords['main'], _pw);
  });

  test('selecting another wallet loads its own lockout', () async {
    final cubit = await build(wallets: ['main', 'cold']);
    await failFive(cubit);
    await cubit.select('cold');
    expect(cubit.state.blockedUntil, isNull);
    await cubit.select('main');
    expect(cubit.state.blockedUntil, isNotNull);
  });
}
```

`app/test/features/auth/unlock_cubit_test.dart`:

```dart
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
import 'package:digibyte_dex/features/auth/bloc/unlock_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_biometric_store.dart';
import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';

const _pw = 'Correct-Horse-9';
const _wrong = 'Wrong-Horse-1';

void main() {
  late FakeWalletRepository repo;
  late InMemoryKeyValueStore storage;
  late FakeBiometricStore biometrics;
  late DateTime now;
  late int unlocked;

  setUp(() {
    repo = FakeWalletRepository();
    storage = InMemoryKeyValueStore();
    biometrics = FakeBiometricStore();
    now = DateTime.utc(2026, 10, 1, 12);
    unlocked = 0;
  });
  tearDown(() => repo.dispose());

  Future<UnlockCubit> build() async {
    final cubit = UnlockCubit(
      walletName: 'main',
      wallet: repo,
      attempts: PasswordAttempts(LockoutStore(storage), now: () => now),
      biometrics: biometrics,
      onUnlocked: () => unlocked++,
    );
    addTearDown(cubit.close);
    await cubit.init();
    return cubit;
  }

  test('a wrong password never stops KDF or signs out', () async {
    final cubit = await build();
    await cubit.unlockWithPassword(_wrong);
    expect(cubit.state.failure, WalletFailure.wrongPassword);
    expect(unlocked, 0);
    expect(repo.calls, ['verify']);
  });

  test('the right password unlocks and resets the count', () async {
    final cubit = await build();
    await cubit.unlockWithPassword(_wrong);
    await cubit.unlockWithPassword(_pw);
    expect(unlocked, 1);
    expect(storage.values.containsKey('lockout_main'), isFalse);
  });

  test('five wrong passwords lock unlocking out too', () async {
    final cubit = await build();
    for (var i = 0; i < 5; i++) {
      await cubit.unlockWithPassword(_wrong);
    }
    expect(cubit.state.blockedUntil, now.add(const Duration(seconds: 30)));
    repo.calls.clear();
    await cubit.unlockWithPassword(_pw);
    expect(cubit.state.failure, WalletFailure.lockedOut);
    expect(repo.calls, isEmpty);
    expect(unlocked, 0);
  });

  test('a biometric read unlocks without a KDF call', () async {
    biometrics.passwords['main'] = _pw;
    final cubit = await build();
    await cubit.unlockWithBiometrics(reason: 'why');
    expect(unlocked, 1);
    expect(repo.calls, isEmpty);
  });

  test('a cancelled prompt keeps biometrics on', () async {
    biometrics
      ..passwords['main'] = _pw
      ..cancel = true;
    final cubit = await build();
    await cubit.unlockWithBiometrics(reason: 'why');
    expect(unlocked, 0);
    expect(cubit.state.biometricsEnabled, isTrue);
    expect(cubit.state.biometricsInvalidated, isFalse);
  });

  test('re-enrolled biometrics fall back to the password and can be '
      're-enabled', () async {
    biometrics
      ..passwords['main'] = _pw
      ..invalidated = true;
    final cubit = await build();
    expect(cubit.state.biometricsEnabled, isTrue);
    await cubit.unlockWithBiometrics(reason: 'why');
    expect(unlocked, 0);
    expect(cubit.state.biometricsInvalidated, isTrue);
    expect(cubit.state.biometricsEnabled, isFalse);
    await cubit.unlockWithPassword(_pw, enableBiometrics: true);
    expect(unlocked, 1);
    expect(biometrics.passwords['main'], _pw);
  });
}
```

`app/test/features/auth/lockout_countdown_test.dart`:

```dart
import 'package:digibyte_dex/features/auth/widgets/lockout_countdown.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('counts down each second and reports the end', (t) async {
    var now = DateTime.utc(2026, 10, 1, 12);
    var expired = 0;
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LockoutCountdown(
            id: 'test.lockout',
            until: now.add(const Duration(seconds: 30)),
            now: () => now,
            onExpired: () => expired++,
          ),
        ),
      ),
    );
    expect(
      find.text('Too many wrong passwords. Try again in 30 s.'),
      findsOneWidget,
    );
    now = now.add(const Duration(seconds: 10));
    await t.pump(const Duration(seconds: 1));
    expect(
      find.text('Too many wrong passwords. Try again in 20 s.'),
      findsOneWidget,
    );
    now = now.add(const Duration(seconds: 20));
    await t.pump(const Duration(seconds: 1));
    expect(expired, 1);
  });
}
```

`app/test/features/auth/sign_in_page_test.dart`:

```dart
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/view/sign_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_biometric_store.dart';
import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/pump_app.dart';

const _pw = 'Correct-Horse-9';
const _wrong = 'Wrong-Horse-1';

void main() {
  late FakeWalletRepository repo;
  late InMemoryKeyValueStore storage;
  late FakeBiometricStore biometrics;
  late AuthCubit auth;
  late DateTime now;

  setUp(() {
    repo = FakeWalletRepository()..names = ['main'];
    storage = InMemoryKeyValueStore();
    biometrics = FakeBiometricStore();
    now = DateTime.utc(2026, 10, 1, 12);
  });
  tearDown(() => repo.dispose());

  // The cubit is created inside the test body, so its stream callbacks run
  // in the tester's fake-async zone.
  Future<void> pump(WidgetTester t) async {
    auth = AuthCubit(repo, backups: BackupStatusStore(storage));
    addTearDown(auth.close);
    repo.emit(null);
    await t.pump();
    await pumpPage(
      t,
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<WalletRepository>.value(value: repo),
          RepositoryProvider.value(
            value: PasswordAttempts(LockoutStore(storage), now: () => now),
          ),
          RepositoryProvider<BiometricStore>.value(value: biometrics),
        ],
        child: BlocProvider.value(value: auth, child: const SignInPage()),
      ),
      stubs: [Routes.welcome],
    );
  }

  Future<void> submit(WidgetTester t, String password) async {
    await enterKey(t, 'signin.password', password);
    await tapKey(t, 'signin.submit');
    await t.pump();
  }

  testWidgets('shows the wallet and signs in with the password', (t) async {
    await pump(t);
    expect(find.text('main'), findsOneWidget);
    await submit(t, _pw);
    expect(repo.calls, ['signIn:main']);
  });

  testWidgets('a wrong password is shown and the field cleared', (t) async {
    await pump(t);
    await submit(t, _wrong);
    expect(find.text('Wrong password.'), findsOneWidget);
    final field = t.widget<TextField>(find.byKey(const Key('signin.password')));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('five wrong passwords show the countdown and block', (t) async {
    await pump(t);
    for (var i = 0; i < 5; i++) {
      await submit(t, _wrong);
    }
    expect(find.byKey(const Key('signin.lockout')), findsOneWidget);
    final button = t.widget<FilledButton>(
      find.byKey(const Key('signin.submit')),
    );
    expect(button.onPressed, isNull);
    now = now.add(const Duration(seconds: 31));
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(find.byKey(const Key('signin.lockout')), findsNothing);
  });

  testWidgets('the fingerprint button shows only when enabled', (t) async {
    await pump(t);
    expect(find.byKey(const Key('signin.biometric')), findsNothing);
    expect(find.byKey(const Key('signin.enableBiometrics')), findsOneWidget);
  });

  testWidgets('another wallet can be created or restored', (t) async {
    await pump(t);
    await tapKey(t, 'signin.other');
    await t.pumpAndSettle();
    expect(find.text('route:${Routes.welcome}'), findsOneWidget);
  });
}
```

`app/test/features/auth/locked_page_test.dart`:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/view/locked_page.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_biometric_store.dart';
import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/pump_app.dart';

const _pw = 'Correct-Horse-9';
const _wrong = 'Wrong-Horse-1';

void main() {
  late FakeWalletRepository repo;
  late InMemoryKeyValueStore storage;
  late FakeBiometricStore biometrics;
  late AuthCubit auth;
  late LockCubit lock;

  setUp(() {
    repo = FakeWalletRepository();
    storage = InMemoryKeyValueStore();
    biometrics = FakeBiometricStore();
  });
  tearDown(() => repo.dispose());

  // Cubits are created inside the test body, so their stream callbacks run
  // in the tester's fake-async zone.
  Future<void> pump(WidgetTester t) async {
    auth = AuthCubit(repo, backups: BackupStatusStore(storage));
    lock = LockCubit(authStates: auth.stream);
    addTearDown(() async {
      await lock.close();
      await auth.close();
    });
    repo.emit(const WalletUser('main'));
    await t.pump();
    lock.lockNow();
    await pumpPage(
      t,
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<WalletRepository>.value(value: repo),
          RepositoryProvider.value(value: PasswordAttempts(LockoutStore(storage))),
          RepositoryProvider<BiometricStore>.value(value: biometrics),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: auth),
            BlocProvider.value(value: lock),
          ],
          child: const LockedPage(),
        ),
      ),
    );
  }

  Future<void> submit(WidgetTester t, String password) async {
    await enterKey(t, 'locked.password', password);
    await tapKey(t, 'locked.submit');
    await t.pump();
  }

  testWidgets('a wrong password keeps the session and the lock', (t) async {
    await pump(t);
    expect(lock.state, const Locked());
    await submit(t, _wrong);
    expect(find.text('Wrong password.'), findsOneWidget);
    expect(lock.state, const Locked());
    expect(auth.state, const AuthSignedIn(WalletUser('main')));
    expect(repo.calls, ['verify']);
  });

  testWidgets('the right password unlocks', (t) async {
    await pump(t);
    await submit(t, _pw);
    expect(lock.state, const Unlocked());
  });

  testWidgets('the fingerprint button unlocks', (t) async {
    biometrics.passwords['main'] = _pw;
    await pump(t);
    await tapKey(t, 'locked.biometric');
    await t.pump();
    expect(lock.state, const Unlocked());
    expect(repo.calls, isEmpty);
  });
}
```

Add these tests inside `main()` of `app/test/app/app_test.dart`:

```dart
  testWidgets('a returning user signs in from the sign-in page', (t) async {
    final app = TestApp();
    addTearDown(app.dispose);
    app.wallet.names = ['main'];
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
    expect(find.text('Portfolio'), findsOneWidget);
  });

  testWidgets('2 minutes in the background locks; unlock keeps the '
      'session', (t) async {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final app = TestApp();
    addTearDown(app.dispose);
    await t.pumpWidget(app.build());
    app.wallet.emit(const WalletUser('main'));
    await t.pumpAndSettle();
    t.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
    app.now = app.now.add(const Duration(minutes: 2));
    t.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('locked.password')), findsOneWidget);
    await t.enterText(
      find.byKey(const Key('locked.password')),
      app.wallet.correctPassword,
    );
    await t.tap(find.byKey(const Key('locked.submit')));
    await t.pumpAndSettle();
    expect(find.text('Portfolio'), findsOneWidget);
    expect(app.wallet.calls, ['verify']);
  });
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter test test/features/auth test/app`
Expected: compile errors (`password_attempts.dart`, `sign_in_cubit.dart`, `unlock_cubit.dart`, `lockout_countdown.dart` and the two pages don't exist).

- [ ] **Step 3: Implement**

`app/lib/features/auth/domain/password_attempts.dart`:

```dart
import 'package:digibyte_dex/data/storage/lockout_store.dart';

/// The wrong-password lockout shared by sign-in and unlock (design note 8).
class PasswordAttempts {
  PasswordAttempts(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final LockoutStore _store;
  final DateTime Function() _now;

  /// The current time in UTC. It also drives the countdown.
  DateTime now() => _now().toUtc();

  /// When attempts for [wallet] are allowed again, or null if they are now.
  Future<DateTime?> blockedUntil(String wallet) async {
    final record = await _store.read(wallet);
    return record.remaining(now()) > Duration.zero ? record.lockedUntil : null;
  }

  /// Records a wrong password and returns the new block end, if any.
  Future<DateTime?> fail(String wallet) async =>
      (await _store.recordFailure(wallet, now())).lockedUntil;

  /// A success forgets every failure.
  Future<void> succeed(String wallet) => _store.reset(wallet);
}
```

`app/lib/features/auth/bloc/sign_in_cubit.dart`:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum SignInStatus { idle, busy }

class SignInState extends Equatable {
  const SignInState({
    this.wallets = const [],
    this.selected,
    this.status = SignInStatus.idle,
    this.failure,
    this.blockedUntil,
    this.biometricsAvailable = false,
    this.biometricsEnabled = false,
    this.biometricsInvalidated = false,
  });

  final List<String> wallets;
  final String? selected;
  final SignInStatus status;

  /// The last attempt's failure; the next event clears it.
  final WalletFailure? failure;

  /// Attempts are refused until then (wrong-password lockout).
  final DateTime? blockedUntil;
  final bool biometricsAvailable;
  final bool biometricsEnabled;

  /// Biometric unlock was removed after a failed read (key invalidated).
  final bool biometricsInvalidated;

  /// The next state. [failure] resets unless given. [blockedUntil] is kept
  /// unless a new one is given or [unblock] is set.
  SignInState next({
    SignInStatus status = SignInStatus.idle,
    WalletFailure? failure,
    DateTime? blockedUntil,
    bool unblock = false,
    bool? biometricsEnabled,
    bool? biometricsInvalidated,
  }) => SignInState(
    wallets: wallets,
    selected: selected,
    status: status,
    failure: failure,
    blockedUntil: unblock ? null : blockedUntil ?? this.blockedUntil,
    biometricsAvailable: biometricsAvailable,
    biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
    biometricsInvalidated: biometricsInvalidated ?? this.biometricsInvalidated,
  );

  @override
  List<Object?> get props => [
    wallets,
    selected,
    status,
    failure,
    blockedUntil,
    biometricsAvailable,
    biometricsEnabled,
    biometricsInvalidated,
  ];
}

/// Cold-start sign-in: pick a wallet, then password or biometrics. Every
/// sign-in starts KDF with the wallet's stored options (Task 5).
class SignInCubit extends Cubit<SignInState> {
  SignInCubit({
    required WalletRepository wallet,
    required PasswordAttempts attempts,
    required BiometricStore biometrics,
  }) : _wallet = wallet,
       _attempts = attempts,
       _biometrics = biometrics,
       super(const SignInState());

  final WalletRepository _wallet;
  final PasswordAttempts _attempts;
  final BiometricStore _biometrics;

  Future<void> init(List<String> wallets) async {
    _emit(SignInState(wallets: wallets));
    if (wallets.isNotEmpty) await select(wallets.first);
  }

  Future<void> select(String wallet) async {
    final available = await _biometrics.isAvailable();
    final enabled = await _biometrics.isEnabled(wallet);
    final blocked = await _attempts.blockedUntil(wallet);
    _emit(
      SignInState(
        wallets: state.wallets,
        selected: wallet,
        failure: blocked == null ? null : WalletFailure.lockedOut,
        blockedUntil: blocked,
        biometricsAvailable: available,
        biometricsEnabled: enabled,
      ),
    );
  }

  Future<void> signInWithPassword(
    String password, {
    bool enableBiometrics = false,
  }) async {
    final wallet = state.selected;
    if (wallet == null || state.status == SignInStatus.busy) return;
    final blocked = await _attempts.blockedUntil(wallet);
    if (blocked != null) {
      _emit(
        state.next(failure: WalletFailure.lockedOut, blockedUntil: blocked),
      );
      return;
    }
    _emit(state.next(status: SignInStatus.busy));
    try {
      await _wallet.signIn(name: wallet, password: password);
    } on WalletException catch (e) {
      final until = e.failure == WalletFailure.wrongPassword
          ? await _attempts.fail(wallet)
          : null;
      _emit(state.next(failure: e.failure, blockedUntil: until));
      return;
    }
    await _attempts.succeed(wallet);
    if (enableBiometrics &&
        state.biometricsAvailable &&
        !state.biometricsEnabled) {
      await _biometrics.enable(wallet, password);
    }
  }

  /// Signs in with the biometric-stored password. A biometric success is
  /// the owner, so it is allowed during a lockout and resets it.
  Future<void> signInWithBiometrics({required String reason}) async {
    final wallet = state.selected;
    if (wallet == null ||
        state.status == SignInStatus.busy ||
        !state.biometricsEnabled) {
      return;
    }
    _emit(state.next(status: SignInStatus.busy));
    final password = await _biometrics.read(wallet, reason: reason);
    if (password == null) {
      final stillEnabled = await _biometrics.isEnabled(wallet);
      _emit(
        state.next(
          biometricsEnabled: stillEnabled,
          biometricsInvalidated: !stillEnabled,
        ),
      );
      return;
    }
    try {
      await _wallet.signIn(name: wallet, password: password);
    } on WalletException catch (e) {
      final stale = e.failure == WalletFailure.wrongPassword;
      if (stale) await _biometrics.disable(wallet);
      _emit(
        state.next(
          failure: e.failure,
          biometricsEnabled: !stale,
          biometricsInvalidated: stale,
        ),
      );
      return;
    }
    await _attempts.succeed(wallet);
  }

  void lockoutExpired() => _emit(state.next(unblock: true));

  void _emit(SignInState next) {
    if (!isClosed) emit(next);
  }
}
```

`app/lib/features/auth/bloc/unlock_cubit.dart`:

```dart
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum UnlockStatus { idle, busy }

class UnlockState extends Equatable {
  const UnlockState({
    this.status = UnlockStatus.idle,
    this.failure,
    this.blockedUntil,
    this.biometricsAvailable = false,
    this.biometricsEnabled = false,
    this.biometricsInvalidated = false,
  });

  final UnlockStatus status;
  final WalletFailure? failure;
  final DateTime? blockedUntil;
  final bool biometricsAvailable;
  final bool biometricsEnabled;
  final bool biometricsInvalidated;

  /// The next state. [failure] resets unless given. [blockedUntil] is kept
  /// unless a new one is given or [unblock] is set.
  UnlockState next({
    UnlockStatus status = UnlockStatus.idle,
    WalletFailure? failure,
    DateTime? blockedUntil,
    bool unblock = false,
    bool? biometricsAvailable,
    bool? biometricsEnabled,
    bool? biometricsInvalidated,
  }) => UnlockState(
    status: status,
    failure: failure,
    blockedUntil: unblock ? null : blockedUntil ?? this.blockedUntil,
    biometricsAvailable: biometricsAvailable ?? this.biometricsAvailable,
    biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
    biometricsInvalidated: biometricsInvalidated ?? this.biometricsInvalidated,
  );

  @override
  List<Object?> get props => [
    status,
    failure,
    blockedUntil,
    biometricsAvailable,
    biometricsEnabled,
    biometricsInvalidated,
  ];
}

/// Unlocks the UI lock above the running KDF session (design note 7). The
/// password is checked against KDF without stopping it; biometrics are
/// trusted without a KDF call.
class UnlockCubit extends Cubit<UnlockState> {
  UnlockCubit({
    required this.walletName,
    required WalletRepository wallet,
    required PasswordAttempts attempts,
    required BiometricStore biometrics,
    required void Function() onUnlocked,
  }) : _wallet = wallet,
       _attempts = attempts,
       _biometrics = biometrics,
       _onUnlocked = onUnlocked,
       super(const UnlockState());

  final String walletName;
  final WalletRepository _wallet;
  final PasswordAttempts _attempts;
  final BiometricStore _biometrics;
  final void Function() _onUnlocked;

  Future<void> init() async {
    final available = await _biometrics.isAvailable();
    final enabled = await _biometrics.isEnabled(walletName);
    final blocked = await _attempts.blockedUntil(walletName);
    _emit(
      state.next(
        failure: blocked == null ? null : WalletFailure.lockedOut,
        blockedUntil: blocked,
        biometricsAvailable: available,
        biometricsEnabled: enabled,
      ),
    );
  }

  Future<void> unlockWithPassword(
    String password, {
    bool enableBiometrics = false,
  }) async {
    if (state.status == UnlockStatus.busy) return;
    final blocked = await _attempts.blockedUntil(walletName);
    if (blocked != null) {
      _emit(
        state.next(failure: WalletFailure.lockedOut, blockedUntil: blocked),
      );
      return;
    }
    _emit(state.next(status: UnlockStatus.busy));
    try {
      await _wallet.verifyPassword(password);
    } on WalletException catch (e) {
      final until = e.failure == WalletFailure.wrongPassword
          ? await _attempts.fail(walletName)
          : null;
      _emit(state.next(failure: e.failure, blockedUntil: until));
      return;
    }
    await _attempts.succeed(walletName);
    if (enableBiometrics &&
        state.biometricsAvailable &&
        !state.biometricsEnabled) {
      final enabled = await _biometrics.enable(walletName, password);
      _emit(
        state.next(
          biometricsEnabled: enabled,
          biometricsInvalidated: !enabled,
        ),
      );
    }
    _onUnlocked();
  }

  /// A biometric success is the owner: allowed during a lockout, and it
  /// resets the count.
  Future<void> unlockWithBiometrics({required String reason}) async {
    if (state.status == UnlockStatus.busy || !state.biometricsEnabled) return;
    _emit(state.next(status: UnlockStatus.busy));
    final password = await _biometrics.read(walletName, reason: reason);
    if (password == null) {
      final stillEnabled = await _biometrics.isEnabled(walletName);
      _emit(
        state.next(
          biometricsEnabled: stillEnabled,
          biometricsInvalidated: !stillEnabled,
        ),
      );
      return;
    }
    await _attempts.succeed(walletName);
    _onUnlocked();
  }

  void lockoutExpired() => _emit(state.next(unblock: true));

  void _emit(UnlockState next) {
    if (!isClosed) emit(next);
  }
}
```

`app/lib/features/auth/widgets/lockout_countdown.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';

/// "Try again in N s", ticking each second; calls [onExpired] at zero.
class LockoutCountdown extends StatefulWidget {
  const LockoutCountdown({
    required this.id,
    required this.until,
    required this.now,
    required this.onExpired,
    super.key,
  });

  final String id;
  final DateTime until;
  final DateTime Function() now;
  final VoidCallback onExpired;

  @override
  State<LockoutCountdown> createState() => _LockoutCountdownState();
}

class _LockoutCountdownState extends State<LockoutCountdown> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!widget.until.isAfter(widget.now())) {
      _timer.cancel();
      widget.onExpired();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.until.difference(widget.now());
    final seconds = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
    return Tagged(
      widget.id,
      child: Text(
        context.l10n.lockoutWait(seconds),
        key: Key(widget.id),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
```

`app/lib/features/auth/view/sign_in_page.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/sign_in_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/widgets/lockout_countdown.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/l10n/wallet_failure_messages.dart';
import 'package:digibyte_dex/widgets/busy_indicator.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Cold-start sign-in to an existing wallet (spec §5.1 unlock).
class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthCubit>().state;
    final wallets = auth is AuthSignedOut ? auth.walletNames : <String>[];
    return BlocProvider(
      create: (context) {
        final cubit = SignInCubit(
          wallet: context.read<WalletRepository>(),
          attempts: context.read<PasswordAttempts>(),
          biometrics: context.read<BiometricStore>(),
        );
        unawaited(cubit.init(wallets));
        return cubit;
      },
      child: const _SignInView(),
    );
  }
}

class _SignInView extends StatefulWidget {
  const _SignInView();

  @override
  State<_SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends State<_SignInView> {
  final _password = TextEditingController();
  bool _enableBiometrics = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<SignInCubit>();
    return BlocConsumer<SignInCubit, SignInState>(
      listenWhen: (previous, current) =>
          current.failure != null && current.failure != previous.failure,
      listener: (context, state) => _password.clear(),
      builder: (context, state) {
        final busy = state.status == SignInStatus.busy;
        final blockedUntil = state.blockedUntil;
        final blocked = blockedUntil != null;
        final failure = state.failure;
        return Scaffold(
          appBar: AppBar(title: Text(l10n.signInTitle)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (state.wallets.length > 1)
                  Tagged(
                    'signin.wallet',
                    child: DropdownButtonFormField<String>(
                      key: const Key('signin.wallet'),
                      initialValue: state.selected,
                      decoration: InputDecoration(
                        labelText: l10n.signInWalletLabel,
                      ),
                      items: [
                        for (final name in state.wallets)
                          DropdownMenuItem(value: name, child: Text(name)),
                      ],
                      onChanged: busy
                          ? null
                          : (name) {
                              if (name != null) unawaited(cubit.select(name));
                            },
                    ),
                  )
                else
                  Text(
                    state.selected ?? '',
                    key: const Key('signin.walletName'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                const SizedBox(height: 16),
                Tagged(
                  'signin.password',
                  child: TextField(
                    key: const Key('signin.password'),
                    controller: _password,
                    enabled: !busy && !blocked,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    onTapOutside: unfocusOnTapOutside,
                    decoration: InputDecoration(
                      labelText: l10n.passwordLabel,
                      errorText:
                          failure == null || failure == WalletFailure.lockedOut
                          ? null
                          : failure.message(l10n),
                    ),
                  ),
                ),
                if (blockedUntil != null) ...[
                  const SizedBox(height: 12),
                  LockoutCountdown(
                    id: 'signin.lockout',
                    until: blockedUntil,
                    now: context.read<PasswordAttempts>().now,
                    onExpired: cubit.lockoutExpired,
                  ),
                ],
                if (state.biometricsInvalidated) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.biometricsInvalidated,
                    key: const Key('signin.bioInvalidated'),
                  ),
                ],
                if (state.biometricsAvailable && !state.biometricsEnabled)
                  Tagged(
                    'signin.enableBiometrics',
                    child: CheckboxListTile(
                      key: const Key('signin.enableBiometrics'),
                      contentPadding: EdgeInsets.zero,
                      value: _enableBiometrics,
                      onChanged: busy
                          ? null
                          : (value) => setState(
                              () => _enableBiometrics = value ?? false,
                            ),
                      title: Text(l10n.enableBiometrics),
                    ),
                  ),
                const SizedBox(height: 24),
                Tagged(
                  'signin.submit',
                  child: FilledButton(
                    key: const Key('signin.submit'),
                    onPressed: busy || blocked
                        ? null
                        : () => unawaited(
                            cubit.signInWithPassword(
                              _password.text,
                              enableBiometrics: _enableBiometrics,
                            ),
                          ),
                    child: busy
                        ? const BusyIndicator('signin.busy')
                        : Text(l10n.signInSubmit),
                  ),
                ),
                if (state.biometricsEnabled) ...[
                  const SizedBox(height: 12),
                  Tagged(
                    'signin.biometric',
                    child: OutlinedButton.icon(
                      key: const Key('signin.biometric'),
                      onPressed: busy
                          ? null
                          : () => unawaited(
                              cubit.signInWithBiometrics(
                                reason: l10n.biometricReason,
                              ),
                            ),
                      icon: const Icon(Icons.fingerprint),
                      label: Text(l10n.useBiometrics),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Tagged(
                  'signin.other',
                  child: TextButton(
                    key: const Key('signin.other'),
                    onPressed: busy ? null : () => context.go(Routes.welcome),
                    child: Text(l10n.signInOther),
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
```

`app/lib/features/auth/view/locked_page.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/wallet_failure.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/unlock_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/auth/widgets/lockout_countdown.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/l10n/wallet_failure_messages.dart';
import 'package:digibyte_dex/widgets/busy_indicator.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The lock screen above a running wallet session (spec §8.2). KDF keeps
/// running; unlocking reuses the session.
class LockedPage extends StatelessWidget {
  const LockedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthCubit>().state;
    final walletName = auth is AuthSignedIn ? auth.user.name : '';
    return BlocProvider(
      create: (context) {
        final cubit = UnlockCubit(
          walletName: walletName,
          wallet: context.read<WalletRepository>(),
          attempts: context.read<PasswordAttempts>(),
          biometrics: context.read<BiometricStore>(),
          onUnlocked: context.read<LockCubit>().unlock,
        );
        unawaited(cubit.init());
        return cubit;
      },
      child: PopScope(
        canPop: false,
        child: _LockedView(walletName: walletName),
      ),
    );
  }
}

class _LockedView extends StatefulWidget {
  const _LockedView({required this.walletName});

  final String walletName;

  @override
  State<_LockedView> createState() => _LockedViewState();
}

class _LockedViewState extends State<_LockedView> {
  final _password = TextEditingController();
  bool _enableBiometrics = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<UnlockCubit>();
    return BlocConsumer<UnlockCubit, UnlockState>(
      listenWhen: (previous, current) =>
          current.failure != null && current.failure != previous.failure,
      listener: (context, state) => _password.clear(),
      builder: (context, state) {
        final busy = state.status == UnlockStatus.busy;
        final blockedUntil = state.blockedUntil;
        final blocked = blockedUntil != null;
        final failure = state.failure;
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
                  l10n.lockedWallet(widget.walletName),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Tagged(
                  'locked.password',
                  child: TextField(
                    key: const Key('locked.password'),
                    controller: _password,
                    enabled: !busy && !blocked,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    onTapOutside: unfocusOnTapOutside,
                    decoration: InputDecoration(
                      labelText: l10n.passwordLabel,
                      errorText:
                          failure == null || failure == WalletFailure.lockedOut
                          ? null
                          : failure.message(l10n),
                    ),
                  ),
                ),
                if (blockedUntil != null) ...[
                  const SizedBox(height: 12),
                  LockoutCountdown(
                    id: 'locked.lockout',
                    until: blockedUntil,
                    now: context.read<PasswordAttempts>().now,
                    onExpired: cubit.lockoutExpired,
                  ),
                ],
                if (state.biometricsInvalidated) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.biometricsInvalidated,
                    key: const Key('locked.bioInvalidated'),
                  ),
                ],
                if (state.biometricsAvailable && !state.biometricsEnabled)
                  Tagged(
                    'locked.enableBiometrics',
                    child: CheckboxListTile(
                      key: const Key('locked.enableBiometrics'),
                      contentPadding: EdgeInsets.zero,
                      value: _enableBiometrics,
                      onChanged: busy
                          ? null
                          : (value) => setState(
                              () => _enableBiometrics = value ?? false,
                            ),
                      title: Text(l10n.enableBiometrics),
                    ),
                  ),
                const SizedBox(height: 24),
                Tagged(
                  'locked.submit',
                  child: FilledButton(
                    key: const Key('locked.submit'),
                    onPressed: busy || blocked
                        ? null
                        : () => unawaited(
                            cubit.unlockWithPassword(
                              _password.text,
                              enableBiometrics: _enableBiometrics,
                            ),
                          ),
                    child: busy
                        ? const BusyIndicator('locked.busy')
                        : Text(l10n.unlockSubmit),
                  ),
                ),
                if (state.biometricsEnabled) ...[
                  const SizedBox(height: 12),
                  Tagged(
                    'locked.biometric',
                    child: OutlinedButton.icon(
                      key: const Key('locked.biometric'),
                      onPressed: busy
                          ? null
                          : () => unawaited(
                              cubit.unlockWithBiometrics(
                                reason: l10n.biometricReason,
                              ),
                            ),
                      icon: const Icon(Icons.fingerprint),
                      label: Text(l10n.useBiometrics),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
```

In `app/lib/l10n/arb/app_en.arb`, add before the closing `}`, with a comma after the previous last entry:

```json
  "signInTitle": "Sign in",
  "signInWalletLabel": "Wallet",
  "signInSubmit": "Sign in",
  "signInOther": "Create or restore another wallet",
  "useBiometrics": "Use fingerprint",
  "biometricReason": "Unlock your DigiByte wallet",
  "biometricsInvalidated": "Fingerprint unlock was turned off because this device's biometrics changed. Use your password; you can turn it on again here.",
  "lockedTitle": "Locked",
  "lockedWallet": "Unlock {name}",
  "@lockedWallet": {"placeholders": {"name": {"type": "String"}}},
  "unlockSubmit": "Unlock",
  "lockoutWait": "Too many wrong passwords. Try again in {seconds} s.",
  "@lockoutWait": {"placeholders": {"seconds": {"type": "int"}}}
```

In `app/lib/app/router.dart`:
- add `import 'package:digibyte_dex/features/auth/view/locked_page.dart';` and `import 'package:digibyte_dex/features/auth/view/sign_in_page.dart';` in sorted position;
- in `appRoutes()`, insert these two routes between the welcome route and the home route:

```dart
  GoRoute(path: Routes.signIn, builder: (_, _) => const SignInPage()),
  GoRoute(path: Routes.locked, builder: (_, _) => const LockedPage()),
```

In `app/lib/main.dart`:
- add `import 'package:digibyte_dex/data/storage/lockout_store.dart';` and `import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';` in sorted position;
- in `providers:`, after `RepositoryProvider.value(value: backups),`, add:

```dart
          RepositoryProvider.value(
            value: PasswordAttempts(LockoutStore(storage)),
          ),
```

In `app/test/support/test_app.dart`:
- add `import 'package:digibyte_dex/data/storage/lockout_store.dart';` and `import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';`;
- add the field `late final attempts = PasswordAttempts(LockoutStore(storage), now: () => now);`;
- in `providers:`, add `RepositoryProvider.value(value: attempts),`.

- [ ] **Step 4: Run the tests and the analyzer**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter gen-l10n
fvm dart format lib test
fvm flutter test test/features/auth test/app
fvm flutter analyze
fvm flutter test
```
Expected: all PASS; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add lib/features/auth lib/l10n/arb/app_en.arb lib/app/router.dart lib/main.dart test/support/test_app.dart test/features/auth test/app/app_test.dart
git commit -m "feat(app): sign-in and lock screens with persisted wrong-password lockout and biometric unlock" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 12: `AssetsRepository`, `PortfolioBloc` and the Home page

**Files:**
- Create: `app/lib/data/repositories/assets_repository.dart`
- Create: `app/lib/features/wallet/bloc/portfolio_bloc.dart`
- Modify: `app/lib/features/wallet/view/home_page.dart` (rewrite)
- Modify: `app/lib/l10n/arb/app_en.arb`
- Modify: `app/lib/main.dart` (assets repository)
- Create: `app/test/support/fake_assets_repository.dart`
- Modify: `app/test/support/test_app.dart` (assets)
- Test: `app/test/data/repositories/sdk_assets_repository_test.dart`
- Test: `app/test/features/wallet/portfolio_bloc_test.dart`
- Test: `app/test/features/wallet/home_page_test.dart`

**Interfaces:**
- Consumes:
  - `Brand.listedAssets` (DGB first);
  - `AuthCubit.signOut`, `LockCubit.lockNow`, `Routes.receive` (Task 6);
  - `Tagged` (Task 8);
  - SDK: `sdk.assets.findAssetsByConfigId(t).single`, `sdk.activateAsset(asset)` → `ActivationResult.isSuccess`, `sdk.balances.watchBalance(id, activateIfNeeded: false)` → `BalanceInfo.total` / `.spendable` (`Decimal`).
- Produces:
  - `class ListedAsset extends Equatable { const ListedAsset({required String ticker, required String name}); }`
  - `enum AssetActivationView { activating, active, failed }`
  - `class BalanceView extends Equatable { const BalanceView({required Decimal total, required Decimal spendable}); bool get hasLockedFunds; }`
  - `abstract interface class AssetsRepository { Future<List<ListedAsset>> listed(); Stream<Map<String, AssetActivationView>> watchActivation(); Future<void> activateListed(); Future<void> activate(String ticker); Stream<BalanceView> watchBalance(String ticker); }`
  - `class AssetsSdkPorts { const AssetsSdkPorts({required String Function(String) assetName, required Future<bool> Function(String) activate, required Stream<BalanceView> Function(String) watchBalance}); factory AssetsSdkPorts.of(KomodoDefiSdk sdk); }`
  - `class SdkAssetsRepository implements AssetsRepository { SdkAssetsRepository(KomodoDefiSdk sdk); SdkAssetsRepository.withPorts(AssetsSdkPorts ports); }`
  - `class PortfolioRow`, with fields `ticker`, `name`, `activation` and `BalanceView? balance`; `class PortfolioState { List<PortfolioRow> rows; bool loading; bool loadFailed; }`
  - `sealed class PortfolioEvent`: `PortfolioStarted()` and `PortfolioRetryRequested(String ticker)`
  - `class PortfolioBloc extends Bloc<PortfolioEvent, PortfolioState> { PortfolioBloc(AssetsRepository assets); }`
  - Home keys and identifiers: `home.lock`, `home.menu`, `home.signOut`, `home.row.<T>`, `home.row.<T>.activating`, `home.row.<T>.retry`, `home.row.<T>.balance`, `home.row.<T>.spendable`.
  - Test support: `FakeAssetsRepository`, with:
    - fields `assets`, `failing`, `activated` and `current`;
    - `setStatus(String, AssetActivationView)` and `emitBalance(String, BalanceView)`;
    - `TestApp.assets`.

- [ ] **Step 1: Write the fake and the failing tests**

`app/test/support/fake_assets_repository.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/repositories/assets_repository.dart';

class FakeAssetsRepository implements AssetsRepository {
  List<ListedAsset> assets = const [
    ListedAsset(ticker: 'DGB', name: 'DigiByte'),
    ListedAsset(ticker: 'BTC', name: 'Bitcoin'),
    ListedAsset(ticker: 'LTC', name: 'Litecoin'),
  ];

  /// Tickers whose activation fails.
  Set<String> failing = {};

  /// Every activation call, in order.
  final activated = <String>[];
  Map<String, AssetActivationView> current = {};
  final _activation =
      StreamController<Map<String, AssetActivationView>>.broadcast();
  final _balances = <String, StreamController<BalanceView>>{};

  void setStatus(String ticker, AssetActivationView view) {
    current = {...current, ticker: view};
    _activation.add(current);
  }

  void emitBalance(String ticker, BalanceView balance) => _balances
      .putIfAbsent(ticker, StreamController<BalanceView>.broadcast)
      .add(balance);

  @override
  Future<List<ListedAsset>> listed() async => assets;

  @override
  Stream<Map<String, AssetActivationView>> watchActivation() =>
      Stream.multi((controller) {
        controller.add(current);
        final sub = _activation.stream.listen(controller.add);
        controller.onCancel = sub.cancel;
      });

  @override
  Future<void> activateListed() async {
    for (final asset in assets) {
      await activate(asset.ticker);
    }
  }

  @override
  Future<void> activate(String ticker) async {
    activated.add(ticker);
    setStatus(
      ticker,
      failing.contains(ticker)
          ? AssetActivationView.failed
          : AssetActivationView.active,
    );
  }

  @override
  Stream<BalanceView> watchBalance(String ticker) => _balances
      .putIfAbsent(ticker, StreamController<BalanceView>.broadcast)
      .stream;
}
```

`app/test/data/repositories/sdk_assets_repository_test.dart`:

```dart
import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> activations;
  late Set<String> failing;
  late StreamController<BalanceView> dgbBalance;

  setUp(() {
    activations = [];
    failing = {};
    dgbBalance = StreamController<BalanceView>.broadcast();
  });
  tearDown(() => dgbBalance.close());

  SdkAssetsRepository build() => SdkAssetsRepository.withPorts(
    AssetsSdkPorts(
      assetName: (ticker) => 'name-$ticker',
      activate: (ticker) async {
        activations.add(ticker);
        if (ticker == 'LTC') throw StateError('electrum down');
        return !failing.contains(ticker);
      },
      watchBalance: (ticker) => dgbBalance.stream,
    ),
  );

  test('lists DGB, BTC, LTC in brand order', () async {
    final listed = await build().listed();
    expect(listed.map((a) => a.ticker), ['DGB', 'BTC', 'LTC']);
    expect(listed.first.name, 'name-DGB');
  });

  test('one failing asset does not stop the others', () async {
    failing.add('BTC');
    final repo = build();
    final updates = <Map<String, AssetActivationView>>[];
    final sub = repo.watchActivation().listen(updates.add);
    addTearDown(sub.cancel);
    await repo.activateListed();
    await Future<void>.delayed(Duration.zero);
    expect(activations, ['DGB', 'BTC', 'LTC']);
    expect(updates.last, {
      'DGB': AssetActivationView.active,
      'BTC': AssetActivationView.failed,
      'LTC': AssetActivationView.failed,
    });
  });

  test('a new subscriber gets the current states first', () async {
    final repo = build();
    await repo.activate('DGB');
    expect(
      await repo.watchActivation().first,
      {'DGB': AssetActivationView.active},
    );
  });

  test('a retry activates one asset again', () async {
    final repo = build();
    await repo.activate('BTC');
    await repo.activate('BTC');
    expect(activations, ['BTC', 'BTC']);
  });

  test('balance errors keep the last value on screen', () async {
    final seen = <BalanceView>[];
    final errors = <Object>[];
    final sub = build()
        .watchBalance('DGB')
        .listen(seen.add, onError: errors.add);
    addTearDown(sub.cancel);
    final one = BalanceView(
      total: Decimal.parse('750.5'),
      spendable: Decimal.parse('750.5'),
    );
    dgbBalance
      ..add(one)
      ..addError(StateError('timeout'));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [one]);
    expect(errors, isEmpty);
  });

  test('locked funds show when spendable differs from total', () {
    expect(
      BalanceView(
        total: Decimal.parse('2'),
        spendable: Decimal.parse('1.5'),
      ).hasLockedFunds,
      isTrue,
    );
    expect(
      BalanceView(total: Decimal.one, spendable: Decimal.one).hasLockedFunds,
      isFalse,
    );
  });
}
```

`app/test/features/wallet/portfolio_bloc_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/features/wallet/bloc/portfolio_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_assets_repository.dart';

void main() {
  late FakeAssetsRepository assets;

  setUp(() => assets = FakeAssetsRepository());

  List<String> tickers(PortfolioState s) =>
      s.rows.map((r) => r.ticker).toList();

  blocTest<PortfolioBloc, PortfolioState>(
    'DGB is pinned first even if listed last',
    setUp: () => assets.assets = const [
      ListedAsset(ticker: 'BTC', name: 'Bitcoin'),
      ListedAsset(ticker: 'LTC', name: 'Litecoin'),
      ListedAsset(ticker: 'DGB', name: 'DigiByte'),
    ],
    build: () => PortfolioBloc(assets),
    act: (bloc) => bloc.add(const PortfolioStarted()),
    wait: Duration.zero,
    verify: (bloc) =>
        expect(tickers(bloc.state), ['DGB', 'BTC', 'LTC']),
  );

  blocTest<PortfolioBloc, PortfolioState>(
    'one failed activation offers retry while the others work',
    setUp: () => assets.failing = {'BTC'},
    build: () => PortfolioBloc(assets),
    act: (bloc) => bloc.add(const PortfolioStarted()),
    wait: Duration.zero,
    verify: (bloc) {
      final byTicker = {for (final r in bloc.state.rows) r.ticker: r};
      expect(byTicker['DGB']!.activation, AssetActivationView.active);
      expect(byTicker['BTC']!.activation, AssetActivationView.failed);
      expect(byTicker['LTC']!.activation, AssetActivationView.active);
    },
  );

  blocTest<PortfolioBloc, PortfolioState>(
    'a retry activates that asset again',
    setUp: () => assets.failing = {'BTC'},
    build: () => PortfolioBloc(assets),
    act: (bloc) async {
      bloc.add(const PortfolioStarted());
      await Future<void>.delayed(Duration.zero);
      assets.failing = {};
      bloc.add(const PortfolioRetryRequested('BTC'));
    },
    wait: Duration.zero,
    verify: (bloc) {
      expect(assets.activated.where((t) => t == 'BTC'), hasLength(2));
      final btc = bloc.state.rows.firstWhere((r) => r.ticker == 'BTC');
      expect(btc.activation, AssetActivationView.active);
    },
  );

  blocTest<PortfolioBloc, PortfolioState>(
    'balances arrive for active assets',
    build: () => PortfolioBloc(assets),
    act: (bloc) async {
      bloc.add(const PortfolioStarted());
      await Future<void>.delayed(Duration.zero);
      assets.emitBalance(
        'DGB',
        BalanceView(
          total: Decimal.parse('750'),
          spendable: Decimal.parse('750'),
        ),
      );
    },
    wait: Duration.zero,
    verify: (bloc) {
      final dgb = bloc.state.rows.firstWhere((r) => r.ticker == 'DGB');
      expect(dgb.balance!.total, Decimal.parse('750'));
    },
  );
}
```

`app/test/features/wallet/home_page_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:digibyte_dex/features/wallet/view/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_assets_repository.dart';
import '../../support/fake_wallet_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeWalletRepository wallet;
  late FakeAssetsRepository assets;
  late AuthCubit auth;
  late LockCubit lock;

  setUp(() {
    wallet = FakeWalletRepository();
    assets = FakeAssetsRepository();
  });
  tearDown(() => wallet.dispose());

  // Cubits are created inside the test body, so their stream callbacks run
  // in the tester's fake-async zone.
  Future<void> pump(WidgetTester t) async {
    auth = AuthCubit(
      wallet,
      backups: BackupStatusStore(InMemoryKeyValueStore()),
    );
    lock = LockCubit(authStates: auth.stream);
    addTearDown(() async {
      await lock.close();
      await auth.close();
    });
    wallet.emit(const WalletUser('main'));
    await t.pump();
    await pumpPage(
      t,
      RepositoryProvider<AssetsRepository>.value(
        value: assets,
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: auth),
            BlocProvider.value(value: lock),
          ],
          child: const HomePage(),
        ),
      ),
      stubs: [Routes.receive('DGB')],
    );
  }

  testWidgets('DGB first, then BTC and LTC, with balances', (t) async {
    await pump(t);
    final dgb = t.getTopLeft(find.byKey(const Key('home.row.DGB')));
    final btc = t.getTopLeft(find.byKey(const Key('home.row.BTC')));
    expect(dgb.dy, lessThan(btc.dy));
    assets.emitBalance(
      'DGB',
      BalanceView(total: Decimal.zero, spendable: Decimal.zero),
    );
    // One pump delivers the stream event to the bloc, the next draws it.
    await t.pump();
    await t.pump();
    expect(
      t.widget<Text>(find.byKey(const Key('home.row.DGB.balance'))).data,
      '0',
    );
  });

  testWidgets('a failed asset shows retry; the others still work', (t) async {
    assets.failing = {'LTC'};
    await pump(t);
    expect(find.byKey(const Key('home.row.LTC.retry')), findsOneWidget);
    expect(find.byKey(const Key('home.row.DGB.balance')), findsOneWidget);
    assets.failing = {};
    await tapKey(t, 'home.row.LTC.retry');
    await t.pump();
    expect(find.byKey(const Key('home.row.LTC.retry')), findsNothing);
  });

  testWidgets('spendable shows when part of the balance is locked', (t) async {
    await pump(t);
    assets.emitBalance(
      'DGB',
      BalanceView(total: Decimal.parse('10'), spendable: Decimal.parse('7')),
    );
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('home.row.DGB.spendable')), findsOneWidget);
  });

  testWidgets('lock now locks the wallet', (t) async {
    await pump(t);
    await tapKey(t, 'home.lock');
    expect(lock.state, const Locked());
  });

  testWidgets('sign out ends the session', (t) async {
    await pump(t);
    await tapKey(t, 'home.menu');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home.signOut')));
    await t.pumpAndSettle();
    expect(wallet.calls, ['signOut']);
  });

  testWidgets('an active row opens its receive page', (t) async {
    await pump(t);
    await tapKey(t, 'home.row.DGB');
    await t.pumpAndSettle();
    expect(find.text('route:${Routes.receive('DGB')}'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter test test/data/repositories/sdk_assets_repository_test.dart test/features/wallet`
Expected: compile errors (`assets_repository.dart` and `portfolio_bloc.dart` don't exist).

- [ ] **Step 3: Implement**

`app/lib/data/repositories/assets_repository.dart`:

```dart
import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:digibyte_dex/config/brand.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class ListedAsset extends Equatable {
  const ListedAsset({required this.ticker, required this.name});

  final String ticker;
  final String name;

  @override
  List<Object?> get props => [ticker, name];
}

enum AssetActivationView { activating, active, failed }

class BalanceView extends Equatable {
  const BalanceView({required this.total, required this.spendable});

  final Decimal total;
  final Decimal spendable;

  /// Part of the balance is not spendable yet (e.g. unconfirmed).
  bool get hasLockedFunds => spendable != total;

  @override
  List<Object?> get props => [total, spendable];
}

/// The curated assets (design note 14). `defaultAssets` does not activate
/// anything, so the app activates them itself after sign-in.
abstract interface class AssetsRepository {
  /// [Brand.listedAssets], in that order.
  Future<List<ListedAsset>> listed();

  /// The current activation states, then every change.
  Stream<Map<String, AssetActivationView>> watchActivation();

  /// Activates every listed asset, one after another. A failure is
  /// recorded for its asset and never stops the others.
  Future<void> activateListed();

  /// Activates one asset (first time or retry).
  Future<void> activate(String ticker);

  /// Balance updates. Transient errors are dropped, so the last value
  /// stays on screen.
  Stream<BalanceView> watchBalance(String ticker);
}

/// The SDK calls [SdkAssetsRepository] needs. A seam for tests, because the
/// SDK's `AssetManager` is not exported.
class AssetsSdkPorts {
  const AssetsSdkPorts({
    required this.assetName,
    required this.activate,
    required this.watchBalance,
  });

  factory AssetsSdkPorts.of(KomodoDefiSdk sdk) {
    Asset asset(String ticker) =>
        sdk.assets.findAssetsByConfigId(ticker).single;
    return AssetsSdkPorts(
      assetName: (ticker) => asset(ticker).id.name,
      activate: (ticker) async =>
          (await sdk.activateAsset(asset(ticker))).isSuccess,
      watchBalance: (ticker) => sdk.balances
          .watchBalance(asset(ticker).id, activateIfNeeded: false)
          .map((b) => BalanceView(total: b.total, spendable: b.spendable)),
    );
  }

  final String Function(String ticker) assetName;
  final Future<bool> Function(String ticker) activate;
  final Stream<BalanceView> Function(String ticker) watchBalance;
}

class SdkAssetsRepository implements AssetsRepository {
  SdkAssetsRepository(KomodoDefiSdk sdk)
    : this.withPorts(AssetsSdkPorts.of(sdk));

  @visibleForTesting
  SdkAssetsRepository.withPorts(this._ports);

  final AssetsSdkPorts _ports;
  final _states = <String, AssetActivationView>{};
  final _changes =
      StreamController<Map<String, AssetActivationView>>.broadcast();

  @override
  Future<List<ListedAsset>> listed() async => [
    for (final ticker in Brand.listedAssets)
      ListedAsset(ticker: ticker, name: _ports.assetName(ticker)),
  ];

  @override
  Stream<Map<String, AssetActivationView>> watchActivation() =>
      Stream.multi((controller) {
        controller.add(Map.unmodifiable(_states));
        final sub = _changes.stream.listen(controller.add);
        controller.onCancel = sub.cancel;
      });

  @override
  Future<void> activateListed() async {
    // Mark every row as activating first, so a previous session's states
    // never show while the first asset is still activating.
    for (final ticker in Brand.listedAssets) {
      _states[ticker] = AssetActivationView.activating;
    }
    _changes.add(Map.unmodifiable(_states));
    for (final ticker in Brand.listedAssets) {
      await activate(ticker);
    }
  }

  @override
  Future<void> activate(String ticker) async {
    _set(ticker, AssetActivationView.activating);
    try {
      final ok = await _ports.activate(ticker);
      _set(
        ticker,
        ok ? AssetActivationView.active : AssetActivationView.failed,
      );
    } on Object {
      _set(ticker, AssetActivationView.failed);
    }
  }

  void _set(String ticker, AssetActivationView view) {
    _states[ticker] = view;
    _changes.add(Map.unmodifiable(_states));
  }

  @override
  Stream<BalanceView> watchBalance(String ticker) =>
      _ports.watchBalance(ticker).transform(
        StreamTransformer<BalanceView, BalanceView>.fromHandlers(
          handleError: (_, _, _) {
            // Keep the last balance; the SDK stream keeps running.
          },
        ),
      );
}
```

`app/lib/features/wallet/bloc/portfolio_bloc.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class PortfolioEvent extends Equatable {
  const PortfolioEvent();
  @override
  List<Object?> get props => [];
}

/// Home opened: list the assets, activate them, follow balances.
final class PortfolioStarted extends PortfolioEvent {
  const PortfolioStarted();
}

final class PortfolioRetryRequested extends PortfolioEvent {
  const PortfolioRetryRequested(this.ticker);

  final String ticker;

  @override
  List<Object?> get props => [ticker];
}

final class _ActivationChanged extends PortfolioEvent {
  const _ActivationChanged(this.states);

  final Map<String, AssetActivationView> states;

  @override
  List<Object?> get props => [states];
}

final class _BalanceChanged extends PortfolioEvent {
  const _BalanceChanged(this.ticker, this.balance);

  final String ticker;
  final BalanceView balance;

  @override
  List<Object?> get props => [ticker, balance];
}

class PortfolioRow extends Equatable {
  const PortfolioRow({
    required this.ticker,
    required this.name,
    required this.activation,
    this.balance,
  });

  final String ticker;
  final String name;
  final AssetActivationView activation;
  final BalanceView? balance;

  PortfolioRow copyWith({
    AssetActivationView? activation,
    BalanceView? balance,
  }) => PortfolioRow(
    ticker: ticker,
    name: name,
    activation: activation ?? this.activation,
    balance: balance ?? this.balance,
  );

  @override
  List<Object?> get props => [ticker, name, activation, balance];
}

class PortfolioState extends Equatable {
  const PortfolioState({
    this.rows = const [],
    this.loading = true,
    this.loadFailed = false,
  });

  final List<PortfolioRow> rows;
  final bool loading;
  final bool loadFailed;

  @override
  List<Object?> get props => [rows, loading, loadFailed];
}

/// One row per listed asset, DGB pinned first (design note 14).
class PortfolioBloc extends Bloc<PortfolioEvent, PortfolioState> {
  PortfolioBloc(this._assets) : super(const PortfolioState()) {
    on<PortfolioStarted>(_onStarted);
    on<PortfolioRetryRequested>(_onRetry);
    on<_ActivationChanged>(_onActivation);
    on<_BalanceChanged>(_onBalance);
  }

  final AssetsRepository _assets;
  StreamSubscription<Map<String, AssetActivationView>>? _activation;
  final _balances = <String, StreamSubscription<BalanceView>>{};

  Future<void> _onStarted(
    PortfolioStarted event,
    Emitter<PortfolioState> emit,
  ) async {
    final List<ListedAsset> listed;
    try {
      listed = await _assets.listed();
    } on Object {
      emit(const PortfolioState(loading: false, loadFailed: true));
      return;
    }
    // DGB pinned first; the rest keep the repository's order.
    final ordered = [
      ...listed.where((a) => a.ticker == 'DGB'),
      ...listed.where((a) => a.ticker != 'DGB'),
    ];
    emit(
      PortfolioState(
        loading: false,
        rows: [
          for (final asset in ordered)
            PortfolioRow(
              ticker: asset.ticker,
              name: asset.name,
              activation: AssetActivationView.activating,
            ),
        ],
      ),
    );
    await _activation?.cancel();
    _activation = _assets.watchActivation().listen(
      (states) => add(_ActivationChanged(states)),
    );
    unawaited(_assets.activateListed());
  }

  void _onRetry(PortfolioRetryRequested event, Emitter<PortfolioState> emit) {
    unawaited(_assets.activate(event.ticker));
  }

  void _onActivation(
    _ActivationChanged event,
    Emitter<PortfolioState> emit,
  ) {
    final rows = [
      for (final row in state.rows)
        row.copyWith(activation: event.states[row.ticker]),
    ];
    for (final row in rows) {
      if (row.activation == AssetActivationView.active &&
          !_balances.containsKey(row.ticker)) {
        _balances[row.ticker] = _assets
            .watchBalance(row.ticker)
            .listen((b) => add(_BalanceChanged(row.ticker, b)));
      }
    }
    emit(PortfolioState(loading: false, rows: rows));
  }

  void _onBalance(_BalanceChanged event, Emitter<PortfolioState> emit) {
    emit(
      PortfolioState(
        loading: false,
        rows: [
          for (final row in state.rows)
            row.ticker == event.ticker
                ? row.copyWith(balance: event.balance)
                : row,
        ],
      ),
    );
  }

  @override
  Future<void> close() async {
    await _activation?.cancel();
    for (final sub in _balances.values) {
      await sub.cancel();
    }
    return super.close();
  }
}
```

Replace `app/lib/features/wallet/view/home_page.dart` with:

```dart
import 'dart:async';

import 'package:digibyte_dex/app/routes.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:digibyte_dex/features/wallet/bloc/portfolio_bloc.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum _HomeAction { signOut }

/// The portfolio: DGB, BTC and LTC with activation state and balance.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        PortfolioBloc(context.read<AssetsRepository>())
          ..add(const PortfolioStarted()),
    child: const _HomeView(),
  );
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          Tagged(
            'home.lock',
            child: IconButton(
              key: const Key('home.lock'),
              tooltip: l10n.lockNow,
              icon: const Icon(Icons.lock_outline),
              onPressed: context.read<LockCubit>().lockNow,
            ),
          ),
          Tagged(
            'home.menu',
            child: PopupMenuButton<_HomeAction>(
              key: const Key('home.menu'),
              onSelected: (action) {
                switch (action) {
                  case _HomeAction.signOut:
                    unawaited(context.read<AuthCubit>().signOut());
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _HomeAction.signOut,
                  child: Tagged(
                    'home.signOut',
                    child: Text(
                      context.l10n.signOut,
                      key: const Key('home.signOut'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: BlocBuilder<PortfolioBloc, PortfolioState>(
        builder: (context, state) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.loadFailed) {
            return Center(child: Text(l10n.portfolioLoadFailed));
          }
          return ListView(
            children: [for (final row in state.rows) _AssetTile(row: row)],
          );
        },
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.row});

  final PortfolioRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final id = 'home.row.${row.ticker}';
    final active = row.activation == AssetActivationView.active;
    final trailing = switch (row.activation) {
      AssetActivationView.activating => SizedBox.square(
        key: Key('$id.activating'),
        dimension: 24,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
      AssetActivationView.failed => Tagged(
        '$id.retry',
        child: TextButton(
          key: Key('$id.retry'),
          onPressed: () => context.read<PortfolioBloc>().add(
            PortfolioRetryRequested(row.ticker),
          ),
          child: Text(l10n.retry),
        ),
      ),
      AssetActivationView.active => _Balance(id: id, balance: row.balance),
    };
    return Tagged(
      id,
      child: ListTile(
        key: Key(id),
        title: Text(row.ticker),
        subtitle: Text(
          row.activation == AssetActivationView.failed
              ? l10n.activationFailed
              : row.name,
        ),
        trailing: trailing,
        onTap: active
            ? () => context.go(Routes.receive(row.ticker))
            : null,
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.id, required this.balance});

  final String id;
  final BalanceView? balance;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final value = balance;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Tagged(
          '$id.balance',
          child: Text(
            value == null ? l10n.balanceLoading : value.total.toString(),
            key: Key('$id.balance'),
          ),
        ),
        if (value != null && value.hasLockedFunds)
          Text(
            l10n.spendableAmount(value.spendable.toString()),
            key: Key('$id.spendable'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
```

In `app/lib/l10n/arb/app_en.arb`, add before the closing `}`, with a comma after the previous last entry:

```json
  "lockNow": "Lock now",
  "signOut": "Sign out",
  "activationFailed": "Couldn't connect. Tap Retry.",
  "portfolioLoadFailed": "Couldn't load your assets.",
  "balanceLoading": "…",
  "spendableAmount": "Spendable: {amount}",
  "@spendableAmount": {"placeholders": {"amount": {"type": "String"}}}
```

In `app/lib/main.dart`:
- add `import 'package:digibyte_dex/data/repositories/assets_repository.dart';` in sorted position;
- in `providers:`, after the `SeedValidator` provider, add:

```dart
          RepositoryProvider<AssetsRepository>.value(
            value: SdkAssetsRepository(sdk),
          ),
```

In `app/test/support/test_app.dart`:
- add `import 'package:digibyte_dex/data/repositories/assets_repository.dart';` and `import 'fake_assets_repository.dart';`;
- add the field `final assets = FakeAssetsRepository();`;
- in `providers:`, add `RepositoryProvider<AssetsRepository>.value(value: assets),`.

- [ ] **Step 4: Run the tests and the analyzer**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter gen-l10n
fvm dart format lib test
fvm flutter test test/data test/features/wallet test/app
fvm flutter analyze
fvm flutter test
```
Expected: all PASS, including the app tests, which now render the real Home page over `FakeAssetsRepository` and still find the title `Portfolio`; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add lib/data/repositories/assets_repository.dart lib/features/wallet lib/l10n/arb/app_en.arb lib/main.dart test/support test/data/repositories/sdk_assets_repository_test.dart test/features/wallet
git commit -m "feat(app): portfolio with DGB first, per-asset activation and retry, live balances; lock now and sign out" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 13: `ReceiveRepository` and the Receive page — QR, copy with a 60 s clipboard clear, share, new address

**Files:**
- Modify: `app/pubspec.yaml` (add `qr_flutter`, `share_plus`)
- Create: `app/lib/data/repositories/receive_repository.dart`
- Create: `app/lib/platform/clipboard_guard.dart`
- Create: `app/lib/platform/text_sharer.dart`
- Create: `app/lib/features/receive/bloc/receive_cubit.dart`
- Create: `app/lib/features/receive/view/receive_page.dart`
- Create: `app/lib/l10n/receive_messages.dart`
- Modify: `app/lib/l10n/arb/app_en.arb`
- Modify: `app/lib/app/router.dart` (`appRoutes()`, final form)
- Modify: `app/lib/app/app.dart` (final form: clipboard retry on resume)
- Modify: `app/lib/main.dart` (final form)
- Create: `app/test/support/fake_receive_repository.dart`
- Create: `app/test/support/fake_text_sharer.dart`
- Modify: `app/test/support/test_app.dart` (final form)
- Test: `app/test/platform/clipboard_guard_test.dart`
- Test: `app/test/data/repositories/sdk_receive_repository_test.dart`
- Test: `app/test/features/receive/receive_cubit_test.dart`
- Test: `app/test/features/receive/receive_page_test.dart`

**Interfaces:**
- Consumes:
  - `SecurityDefaults.clipboardClearAfter` (Task 3);
  - `Tagged` (Task 8);
  - `Routes.receive` (Task 6);
  - SDK: `sdk.pubkeys.getPubkeys(asset)` → `AssetPubkeys.keys[*].address` / `.derivationPath` and `.availableAddressesCount`; `sdk.pubkeys.createNewPubkey(asset)` → `PubkeyInfo.address`; `(await sdk.auth.currentUser)?.isHd`.
- Produces:
  - `class ReceiveAddress { const ReceiveAddress({required String address, String? derivationPath}); }`
  - `class ReceiveAddresses { const ReceiveAddresses({required List<ReceiveAddress> addresses, required bool canCreateAddress}); ReceiveAddress get current; }`, where `current` is the newest address
  - `enum ReceiveFailure { addressLimit, unsupported, unknown }`; `final class ReceiveException implements Exception`; `ReceiveFailure receiveFailureOf(Object error)`
  - `abstract interface class ReceiveRepository { Future<ReceiveAddresses> addresses(String ticker); Future<String> newAddress(String ticker); }`
  - `typedef PubkeySnapshot = ({List<ReceiveAddress> keys, int available});`
  - `class ReceiveSdkPorts { const ReceiveSdkPorts({required addresses, required newAddress, required isHdWallet}); factory ReceiveSdkPorts.of(KomodoDefiSdk sdk); }`
  - `class SdkReceiveRepository implements ReceiveRepository { SdkReceiveRepository(KomodoDefiSdk sdk); SdkReceiveRepository.withPorts(ReceiveSdkPorts ports); }`
  - `typedef TimerFactory = Timer Function(Duration duration, void Function() callback);`
  - `class ClipboardGuard { ClipboardGuard({Future<void> Function(String)? write, Future<String?> Function()? read, TimerFactory? timer, Duration clearAfter}); Future<void> copy(String text); Future<void> handleResumed(); void dispose(); }`
  - `class TextSharer { const TextSharer(); Future<void> share(String text); }`
  - `sealed class ReceiveState`: `ReceiveLoading()`, `ReceiveError(ReceiveFailure)` and `ReceiveReady({required String address, required bool canCreateAddress, bool creating, ReceiveFailure? failure})`
  - `class ReceiveCubit { ReceiveCubit({required String ticker, required ReceiveRepository receive, required ClipboardGuard clipboard, required TextSharer sharer}); Future<void> load(); Future<void> newAddress(); Future<void> copy(); Future<void> share(); }`
  - `class ReceivePage extends StatelessWidget { const ReceivePage({required String ticker}); }`
  - Receive keys and identifiers: `receive.qr`, `receive.address`, `receive.copy`, `receive.share`, `receive.newAddress`, `receive.error`, `receive.retry`.
  - Test support:
    - `FakeReceiveRepository`, with fields `keys`, `canCreate`, `newAddressFailure`, `loadFailure` and `created`;
    - `FakeTextSharer`, with `shared`;
    - `TestApp.receive`, `TestApp.clipboard`, `TestApp.sharer`.

- [ ] **Step 1: Add the dependencies**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter pub add 'qr_flutter:^4.1.0' 'share_plus:^11.1.0'
grep -nE '^  (qr_flutter|share_plus):' pubspec.yaml
```
Expected:
- `qr_flutter 4.1.0` (with `qr 3.0.2`) is added;
- `share_plus 11.1.0` moves from transitive to direct;
- both are in sorted position after `local_auth`.

- [ ] **Step 2: Write the fakes and the failing tests**

`app/test/support/fake_receive_repository.dart`:

```dart
import 'package:digibyte_dex/data/repositories/receive_repository.dart';

/// Addresses are dummies, not real DigiByte addresses.
class FakeReceiveRepository implements ReceiveRepository {
  List<ReceiveAddress> keys = const [
    ReceiveAddress(
      address: 'DFirstAddress0000',
      derivationPath: "m/44'/20'/0'/0/0",
    ),
  ];
  bool canCreate = true;
  ReceiveFailure? loadFailure;
  ReceiveFailure? newAddressFailure;
  int created = 0;

  @override
  Future<ReceiveAddresses> addresses(String ticker) async {
    final failure = loadFailure;
    if (failure != null) throw ReceiveException(failure);
    return ReceiveAddresses(
      addresses: List.of(keys),
      canCreateAddress: canCreate,
    );
  }

  @override
  Future<String> newAddress(String ticker) async {
    final failure = newAddressFailure;
    if (failure != null) throw ReceiveException(failure);
    created++;
    final address = 'DNewAddress000$created';
    keys = [...keys, ReceiveAddress(address: address)];
    return address;
  }
}
```

`app/test/support/fake_text_sharer.dart`:

```dart
import 'package:digibyte_dex/platform/text_sharer.dart';

class FakeTextSharer implements TextSharer {
  final shared = <String>[];

  @override
  Future<void> share(String text) async {
    shared.add(text);
  }
}
```

`app/test/platform/clipboard_guard_test.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this.callback);

  final void Function() callback;
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

void main() {
  String? clipboard;
  var readable = true;
  late List<_FakeTimer> timers;
  late List<Duration> delays;

  setUp(() {
    clipboard = null;
    readable = true;
    timers = [];
    delays = [];
  });

  ClipboardGuard build() => ClipboardGuard(
    write: (text) async {
      clipboard = text;
    },
    read: () async => readable ? clipboard : null,
    timer: (delay, callback) {
      delays.add(delay);
      final timer = _FakeTimer(callback);
      timers.add(timer);
      return timer;
    },
  );

  Future<void> fireLast() async {
    timers.last.callback();
    await pumpEventQueue();
  }

  test('copies, then clears after 60 s if unchanged', () async {
    final guard = build();
    await guard.copy('DAddr0001');
    expect(clipboard, 'DAddr0001');
    expect(delays.single, const Duration(seconds: 60));
    await fireLast();
    expect(clipboard, '');
  });

  test('leaves the clipboard alone if the user copied something else',
      () async {
    final guard = build();
    await guard.copy('DAddr0001');
    clipboard = 'a note the user copied';
    await fireLast();
    expect(clipboard, 'a note the user copied');
  });

  test('a clear due while backgrounded runs on resume', () async {
    final guard = build();
    await guard.copy('DAddr0001');
    readable = false;
    await fireLast();
    expect(clipboard, 'DAddr0001');
    readable = true;
    await guard.handleResumed();
    expect(clipboard, '');
  });

  test('copying again restarts the timer', () async {
    final guard = build();
    await guard.copy('DAddr0001');
    await guard.copy('DAddr0002');
    expect(timers.first.cancelled, isTrue);
    await fireLast();
    expect(clipboard, '');
  });
}
```

`app/test/data/repositories/sdk_receive_repository_test.dart`:

```dart
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _a0 = ReceiveAddress(address: 'DAddr0000', derivationPath: 'p/0');
const _a1 = ReceiveAddress(address: 'DAddr0001', derivationPath: 'p/1');

Matcher _throwsFailure(ReceiveFailure failure) => throwsA(
  isA<ReceiveException>().having((e) => e.failure, 'failure', failure),
);

void main() {
  SdkReceiveRepository build({
    List<ReceiveAddress> keys = const [_a0, _a1],
    int available = 20,
    bool hd = true,
    Exception? newAddressError,
  }) => SdkReceiveRepository.withPorts(
    ReceiveSdkPorts(
      addresses: (ticker) async => (keys: keys, available: available),
      newAddress: (ticker) async {
        final error = newAddressError;
        if (error != null) throw error;
        return 'DAddr0002';
      },
      isHdWallet: () async => hd,
    ),
  );

  test('shows the newest address; HD with room can create', () async {
    final result = await build().addresses('DGB');
    expect(result.current, _a1);
    expect(result.canCreateAddress, isTrue);
  });

  test('an iguana wallet has one address and cannot create', () async {
    final result = await build(
      keys: const [_a0],
      available: 0,
      hd: false,
    ).addresses('DGB');
    expect(result.current, _a0);
    expect(result.canCreateAddress, isFalse);
  });

  test('no room left means no new address', () async {
    final result = await build(available: 0).addresses('DGB');
    expect(result.canCreateAddress, isFalse);
  });

  test('the address-limit error is addressLimit', () async {
    await expectLater(
      build(
        newAddressError: Exception('EmptyAddressesLimitReached gap 20'),
      ).newAddress('DGB'),
      _throwsFailure(ReceiveFailure.addressLimit),
    );
  });

  test('mapping covers unsupported and unknown', () {
    expect(
      receiveFailureOf(UnsupportedError('single address')),
      ReceiveFailure.unsupported,
    );
    expect(
      receiveFailureOf(Exception('AddressLimitReached')),
      ReceiveFailure.addressLimit,
    );
    expect(receiveFailureOf(Exception('timeout')), ReceiveFailure.unknown);
  });

  test('an empty key list is unknown', () async {
    await expectLater(
      build(keys: const []).addresses('DGB'),
      _throwsFailure(ReceiveFailure.unknown),
    );
  });
}
```

`app/test/features/receive/receive_cubit_test.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/features/receive/bloc/receive_cubit.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_receive_repository.dart';
import '../../support/fake_text_sharer.dart';

/// A timer that never fires: these tests do not wait for the clear.
class _InertTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 0;
}

void main() {
  late FakeReceiveRepository receive;
  late FakeTextSharer sharer;
  late List<String> clipboardWrites;

  setUp(() {
    receive = FakeReceiveRepository();
    sharer = FakeTextSharer();
    clipboardWrites = [];
  });

  Future<ReceiveCubit> build() async {
    final cubit = ReceiveCubit(
      ticker: 'DGB',
      receive: receive,
      clipboard: ClipboardGuard(
        write: (text) async {
          clipboardWrites.add(text);
        },
        read: () async => null,
        timer: (_, _) => _InertTimer(),
      ),
      sharer: sharer,
    );
    addTearDown(cubit.close);
    await cubit.load();
    return cubit;
  }

  test('shows the newest address', () async {
    receive.keys = const [
      ReceiveAddress(address: 'DAddr0000'),
      ReceiveAddress(address: 'DAddr0001'),
    ];
    final cubit = await build();
    expect(
      cubit.state,
      const ReceiveReady(address: 'DAddr0001', canCreateAddress: true),
    );
  });

  test('a single-address wallet cannot create addresses', () async {
    receive.canCreate = false;
    final cubit = await build();
    expect((cubit.state as ReceiveReady).canCreateAddress, isFalse);
  });

  test('a new address replaces the shown one', () async {
    final cubit = await build();
    await cubit.newAddress();
    expect((cubit.state as ReceiveReady).address, 'DNewAddress0001');
  });

  test('the address limit keeps the address and explains', () async {
    receive.newAddressFailure = ReceiveFailure.addressLimit;
    final cubit = await build();
    await cubit.newAddress();
    final state = cubit.state as ReceiveReady;
    expect(state.address, 'DFirstAddress0000');
    expect(state.failure, ReceiveFailure.addressLimit);
  });

  test('copy and share use the shown address', () async {
    final cubit = await build();
    await cubit.copy();
    await cubit.share();
    expect(clipboardWrites, ['DFirstAddress0000']);
    expect(sharer.shared, ['DFirstAddress0000']);
  });

  test('a load failure is shown', () async {
    receive.loadFailure = ReceiveFailure.unknown;
    final cubit = await build();
    expect(cubit.state, const ReceiveError(ReceiveFailure.unknown));
  });
}
```

`app/test/features/receive/receive_page_test.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/features/receive/view/receive_page.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../support/fake_receive_repository.dart';
import '../../support/fake_text_sharer.dart';
import '../../support/pump_app.dart';

/// A timer that never fires, so no timer is left pending after a test.
class _InertTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 0;
}

void main() {
  late FakeReceiveRepository receive;
  late FakeTextSharer sharer;
  late List<String> clipboardWrites;

  setUp(() {
    receive = FakeReceiveRepository();
    sharer = FakeTextSharer();
    clipboardWrites = [];
  });

  Future<void> pump(WidgetTester t) => pumpPage(
    t,
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ReceiveRepository>.value(value: receive),
        RepositoryProvider.value(
          value: ClipboardGuard(
            write: (text) async {
              clipboardWrites.add(text);
            },
            read: () async => null,
            timer: (_, _) => _InertTimer(),
          ),
        ),
        RepositoryProvider<TextSharer>.value(value: sharer),
      ],
      child: const ReceivePage(ticker: 'DGB'),
    ),
  );

  String shownAddress(WidgetTester t) =>
      t.widget<Text>(find.byKey(const Key('receive.address'))).data!;

  testWidgets('a QR code and the address', (t) async {
    await pump(t);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(shownAddress(t), 'DFirstAddress0000');
  });

  testWidgets('copy writes the clipboard and says it will clear', (t) async {
    await pump(t);
    await tapKey(t, 'receive.copy');
    await t.pump();
    expect(clipboardWrites, ['DFirstAddress0000']);
    expect(find.textContaining('60 seconds'), findsOneWidget);
  });

  testWidgets('share opens the share sheet with the address', (t) async {
    await pump(t);
    await tapKey(t, 'receive.share');
    expect(sharer.shared, ['DFirstAddress0000']);
  });

  testWidgets('new address shows the new one', (t) async {
    await pump(t);
    await tapKey(t, 'receive.newAddress');
    await t.pump();
    expect(shownAddress(t), 'DNewAddress0001');
  });

  testWidgets('a single-address wallet has no new-address button', (t) async {
    receive.canCreate = false;
    await pump(t);
    expect(find.byKey(const Key('receive.newAddress')), findsNothing);
  });

  testWidgets('the address limit is explained', (t) async {
    receive.newAddressFailure = ReceiveFailure.addressLimit;
    await pump(t);
    await tapKey(t, 'receive.newAddress');
    await t.pump();
    expect(
      find.text('Use one of your unused addresses first.'),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `cd ~/digibyte-dex/digibyte-wallet/app && fvm flutter test test/platform/clipboard_guard_test.dart test/data/repositories/sdk_receive_repository_test.dart test/features/receive`
Expected: compile errors (`receive_repository.dart`, `clipboard_guard.dart`, `text_sharer.dart`, `receive_cubit.dart` and `receive_page.dart` don't exist).

- [ ] **Step 4: Implement**

`app/lib/data/repositories/receive_repository.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class ReceiveAddress extends Equatable {
  const ReceiveAddress({required this.address, this.derivationPath});

  final String address;
  final String? derivationPath;

  @override
  List<Object?> get props => [address, derivationPath];
}

class ReceiveAddresses extends Equatable {
  const ReceiveAddresses({
    required this.addresses,
    required this.canCreateAddress,
  });

  final List<ReceiveAddress> addresses;

  /// HD wallet with room left under the gap limit (design note 15).
  final bool canCreateAddress;

  /// The newest address: the one to show.
  ReceiveAddress get current => addresses.last;

  @override
  List<Object?> get props => [addresses, canCreateAddress];
}

enum ReceiveFailure { addressLimit, unsupported, unknown }

final class ReceiveException implements Exception {
  const ReceiveException(this.failure);

  final ReceiveFailure failure;

  @override
  String toString() => 'ReceiveException(${failure.name})';
}

/// The only mapping from SDK address errors to [ReceiveFailure]. KDF
/// refuses a new HD address once 20 unused ones are in a row
/// (`EmptyAddressesLimitReached`) or the account is full
/// (`AddressLimitReached`).
ReceiveFailure receiveFailureOf(Object error) {
  if (error is ReceiveException) return error.failure;
  if (error is UnsupportedError) return ReceiveFailure.unsupported;
  final text = error.toString();
  if (text.contains('AddressesLimitReached') ||
      text.contains('AddressLimitReached')) {
    return ReceiveFailure.addressLimit;
  }
  return ReceiveFailure.unknown;
}

abstract interface class ReceiveRepository {
  Future<ReceiveAddresses> addresses(String ticker);

  /// Derives the next HD address and returns it.
  Future<String> newAddress(String ticker);
}

typedef PubkeySnapshot = ({List<ReceiveAddress> keys, int available});

/// The SDK calls [SdkReceiveRepository] needs. A seam for tests, because the
/// SDK's `PubkeyManager` is not exported.
class ReceiveSdkPorts {
  const ReceiveSdkPorts({
    required this.addresses,
    required this.newAddress,
    required this.isHdWallet,
  });

  factory ReceiveSdkPorts.of(KomodoDefiSdk sdk) {
    Asset asset(String ticker) =>
        sdk.assets.findAssetsByConfigId(ticker).single;
    return ReceiveSdkPorts(
      addresses: (ticker) async {
        final pubkeys = await sdk.pubkeys.getPubkeys(asset(ticker));
        return (
          keys: [
            for (final key in pubkeys.keys)
              ReceiveAddress(
                address: key.address,
                derivationPath: key.derivationPath,
              ),
          ],
          available: pubkeys.availableAddressesCount,
        );
      },
      newAddress: (ticker) async =>
          (await sdk.pubkeys.createNewPubkey(asset(ticker))).address,
      isHdWallet: () async => (await sdk.auth.currentUser)?.isHd ?? false,
    );
  }

  final Future<PubkeySnapshot> Function(String ticker) addresses;
  final Future<String> Function(String ticker) newAddress;
  final Future<bool> Function() isHdWallet;
}

class SdkReceiveRepository implements ReceiveRepository {
  SdkReceiveRepository(KomodoDefiSdk sdk)
    : this.withPorts(ReceiveSdkPorts.of(sdk));

  @visibleForTesting
  SdkReceiveRepository.withPorts(this._ports);

  final ReceiveSdkPorts _ports;

  @override
  Future<ReceiveAddresses> addresses(String ticker) async {
    try {
      final snapshot = await _ports.addresses(ticker);
      if (snapshot.keys.isEmpty) {
        throw const ReceiveException(ReceiveFailure.unknown);
      }
      // An iguana wallet has one address; only HD derives new ones.
      final hd = await _ports.isHdWallet();
      return ReceiveAddresses(
        addresses: snapshot.keys,
        canCreateAddress: hd && snapshot.available > 0,
      );
    } on Object catch (error) {
      throw ReceiveException(receiveFailureOf(error));
    }
  }

  @override
  Future<String> newAddress(String ticker) async {
    try {
      return await _ports.newAddress(ticker);
    } on Object catch (error) {
      throw ReceiveException(receiveFailureOf(error));
    }
  }
}
```

`app/lib/platform/clipboard_guard.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/config/security_defaults.dart';
import 'package:flutter/services.dart';

typedef TimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// Copies an address and clears it again after
/// [SecurityDefaults.clipboardClearAfter] (spec §8.2), but only if the
/// clipboard still holds that address.
class ClipboardGuard {
  ClipboardGuard({
    Future<void> Function(String text)? write,
    Future<String?> Function()? read,
    TimerFactory? timer,
    Duration clearAfter = SecurityDefaults.clipboardClearAfter,
  }) : _write = write ?? _systemWrite,
       _read = read ?? _systemRead,
       _timer = timer ?? Timer.new,
       _clearAfter = clearAfter;

  final Future<void> Function(String text) _write;
  final Future<String?> Function() _read;
  final TimerFactory _timer;
  final Duration _clearAfter;
  String? _copied;
  Timer? _pending;
  bool _clearDue = false;

  Future<void> copy(String text) async {
    await _write(text);
    _copied = text;
    _clearDue = false;
    _pending?.cancel();
    _pending = _timer(_clearAfter, () => unawaited(_clearIfUnchanged()));
  }

  /// Android refuses clipboard reads while the app is in the background,
  /// so a clear that came due then is retried here, on resume.
  Future<void> handleResumed() async {
    if (_clearDue) await _clearIfUnchanged();
  }

  Future<void> _clearIfUnchanged() async {
    final copied = _copied;
    if (copied == null) return;
    final current = await _read();
    if (current == null) {
      _clearDue = true;
      return;
    }
    _clearDue = false;
    _copied = null;
    if (current == copied) await _write('');
  }

  void dispose() => _pending?.cancel();

  static Future<void> _systemWrite(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  static Future<String?> _systemRead() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;
}
```

`app/lib/platform/text_sharer.dart`:

```dart
import 'package:share_plus/share_plus.dart';

/// Opens the system share sheet with plain text.
class TextSharer {
  const TextSharer();

  Future<void> share(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}
```

`app/lib/features/receive/bloc/receive_cubit.dart`:

```dart
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class ReceiveState extends Equatable {
  const ReceiveState();
  @override
  List<Object?> get props => [];
}

final class ReceiveLoading extends ReceiveState {
  const ReceiveLoading();
}

final class ReceiveError extends ReceiveState {
  const ReceiveError(this.failure);

  final ReceiveFailure failure;

  @override
  List<Object?> get props => [failure];
}

final class ReceiveReady extends ReceiveState {
  const ReceiveReady({
    required this.address,
    required this.canCreateAddress,
    this.creating = false,
    this.failure,
  });

  final String address;
  final bool canCreateAddress;
  final bool creating;
  final ReceiveFailure? failure;

  @override
  List<Object?> get props => [address, canCreateAddress, creating, failure];
}

/// Receive one listed asset (design note 15).
class ReceiveCubit extends Cubit<ReceiveState> {
  ReceiveCubit({
    required this.ticker,
    required ReceiveRepository receive,
    required ClipboardGuard clipboard,
    required TextSharer sharer,
  }) : _receive = receive,
       _clipboard = clipboard,
       _sharer = sharer,
       super(const ReceiveLoading());

  final String ticker;
  final ReceiveRepository _receive;
  final ClipboardGuard _clipboard;
  final TextSharer _sharer;

  Future<void> load() async {
    _emit(const ReceiveLoading());
    try {
      final result = await _receive.addresses(ticker);
      _emit(
        ReceiveReady(
          address: result.current.address,
          canCreateAddress: result.canCreateAddress,
        ),
      );
    } on ReceiveException catch (e) {
      _emit(ReceiveError(e.failure));
    }
  }

  Future<void> newAddress() async {
    final current = state;
    if (current is! ReceiveReady || current.creating) return;
    _emit(
      ReceiveReady(
        address: current.address,
        canCreateAddress: current.canCreateAddress,
        creating: true,
      ),
    );
    try {
      final address = await _receive.newAddress(ticker);
      final refreshed = await _receive.addresses(ticker);
      _emit(
        ReceiveReady(
          address: address,
          canCreateAddress: refreshed.canCreateAddress,
        ),
      );
    } on ReceiveException catch (e) {
      _emit(
        ReceiveReady(
          address: current.address,
          canCreateAddress: current.canCreateAddress,
          failure: e.failure,
        ),
      );
    }
  }

  Future<void> copy() async {
    final current = state;
    if (current is ReceiveReady) await _clipboard.copy(current.address);
  }

  Future<void> share() async {
    final current = state;
    if (current is ReceiveReady) await _sharer.share(current.address);
  }

  void _emit(ReceiveState next) {
    if (!isClosed) emit(next);
  }
}
```

`app/lib/l10n/receive_messages.dart`:

```dart
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/l10n/l10n.dart';

extension ReceiveFailureMessage on ReceiveFailure {
  String message(AppLocalizations l10n) => switch (this) {
    ReceiveFailure.addressLimit => l10n.receiveAddressLimit,
    ReceiveFailure.unsupported => l10n.receiveUnsupported,
    ReceiveFailure.unknown => l10n.receiveFailed,
  };
}
```

`app/lib/features/receive/view/receive_page.dart`:

```dart
import 'dart:async';

import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/features/receive/bloc/receive_cubit.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/l10n/receive_messages.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:digibyte_dex/widgets/tagged.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// The receive screen of one listed asset (spec §5.1).
class ReceivePage extends StatelessWidget {
  const ReceivePage({required this.ticker, super.key});

  final String ticker;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) {
      final cubit = ReceiveCubit(
        ticker: ticker,
        receive: context.read<ReceiveRepository>(),
        clipboard: context.read<ClipboardGuard>(),
        sharer: context.read<TextSharer>(),
      );
      unawaited(cubit.load());
      return cubit;
    },
    child: _ReceiveView(ticker: ticker),
  );
}

class _ReceiveView extends StatelessWidget {
  const _ReceiveView({required this.ticker});

  final String ticker;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.receiveTitle(ticker))),
      body: SafeArea(
        child: BlocBuilder<ReceiveCubit, ReceiveState>(
          builder: (context, state) => switch (state) {
            ReceiveLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
            ReceiveError() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.receiveLoadFailed),
                  const SizedBox(height: 12),
                  Tagged(
                    'receive.retry',
                    child: TextButton(
                      key: const Key('receive.retry'),
                      onPressed: () =>
                          unawaited(context.read<ReceiveCubit>().load()),
                      child: Text(l10n.retry),
                    ),
                  ),
                ],
              ),
            ),
            ReceiveReady() => _ReadyView(state: state),
          },
        ),
      ),
    );
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.state});

  final ReceiveReady state;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = context.l10n.addressCopied;
    await context.read<ReceiveCubit>().copy();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<ReceiveCubit>();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: QrImageView(
            key: const Key('receive.qr'),
            data: state.address,
            size: 240,
            padding: const EdgeInsets.all(16),
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
            semanticsLabel: l10n.receiveQrLabel,
          ),
        ),
        const SizedBox(height: 16),
        Tagged(
          'receive.address',
          child: Text(
            state.address,
            key: const Key('receive.address'),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Tagged(
                'receive.copy',
                child: FilledButton.icon(
                  key: const Key('receive.copy'),
                  onPressed: () => unawaited(_copy(context)),
                  icon: const Icon(Icons.copy),
                  label: Text(l10n.copy),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Tagged(
                'receive.share',
                child: OutlinedButton.icon(
                  key: const Key('receive.share'),
                  onPressed: () => unawaited(cubit.share()),
                  icon: const Icon(Icons.share),
                  label: Text(l10n.share),
                ),
              ),
            ),
          ],
        ),
        if (state.canCreateAddress) ...[
          const SizedBox(height: 12),
          Tagged(
            'receive.newAddress',
            child: TextButton(
              key: const Key('receive.newAddress'),
              onPressed: state.creating
                  ? null
                  : () => unawaited(cubit.newAddress()),
              child: Text(l10n.newAddress),
            ),
          ),
        ],
        if (state.failure case final failure?) ...[
          const SizedBox(height: 12),
          Text(
            failure.message(l10n),
            key: const Key('receive.error'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
```

In `app/lib/l10n/arb/app_en.arb`, add before the closing `}`, with a comma after the previous last entry:

```json
  "receiveTitle": "Receive {ticker}",
  "@receiveTitle": {"placeholders": {"ticker": {"type": "String"}}},
  "receiveQrLabel": "QR code of your address",
  "receiveLoadFailed": "Couldn't load your address.",
  "copy": "Copy",
  "share": "Share",
  "newAddress": "New address",
  "addressCopied": "Address copied. It will be cleared from the clipboard in 60 seconds.",
  "receiveAddressLimit": "Use one of your unused addresses first.",
  "receiveUnsupported": "This wallet has a single address.",
  "receiveFailed": "Couldn't create a new address. Try again."
```

Replace `appRoutes()` in `app/lib/app/router.dart` with its final form, and add `import 'package:digibyte_dex/features/receive/view/receive_page.dart';` in sorted position:

```dart
/// The route table (design note 12).
List<RouteBase> appRoutes() => [
  GoRoute(
    path: Routes.splash,
    builder: (_, _) =>
        const Scaffold(body: Center(child: CircularProgressIndicator())),
  ),
  GoRoute(
    path: Routes.welcome,
    builder: (_, _) => const WelcomePage(),
    routes: [
      GoRoute(path: 'create', builder: (_, _) => const CreateWalletPage()),
      GoRoute(path: 'restore', builder: (_, _) => const RestoreWalletPage()),
      GoRoute(path: 'backup', builder: (_, _) => const BackupPage()),
    ],
  ),
  GoRoute(path: Routes.signIn, builder: (_, _) => const SignInPage()),
  GoRoute(path: Routes.locked, builder: (_, _) => const LockedPage()),
  GoRoute(
    path: Routes.home,
    builder: (_, _) => const HomePage(),
    routes: [
      GoRoute(
        path: 'receive/:ticker',
        builder: (_, state) =>
            ReceivePage(ticker: state.pathParameters['ticker']!),
      ),
    ],
  ),
];
```

Replace `app/lib/app/app.dart` with its final form:

```dart
import 'dart:async';

import 'package:digibyte_dex/app/router.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/theme/app_theme.dart';
import 'package:digibyte_dex/widgets/privacy_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DigiByteDexApp extends StatefulWidget {
  const DigiByteDexApp({super.key});
  @override
  State<DigiByteDexApp> createState() => _DigiByteDexAppState();
}

class _DigiByteDexAppState extends State<DigiByteDexApp> {
  late final AppRouter _router;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _router = AppRouter(context.read<AuthCubit>(), context.read<LockCubit>());
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleChanged);
  }

  void _onLifecycleChanged(AppLifecycleState state) {
    context.read<LockCubit>().onLifecycleChanged(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(context.read<ClipboardGuard>().handleResumed());
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    onGenerateTitle: (c) => c.l10n.appTitle,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    builder: (context, child) =>
        PrivacyOverlay(child: child ?? const SizedBox.shrink()),
    routerConfig: _router.router,
  );
}
```

Replace `app/lib/main.dart` with its final form:

```dart
import 'dart:io' show Platform;

import 'package:digibyte_dex/app/app.dart';
import 'package:digibyte_dex/app/startup_error_app.dart';
import 'package:digibyte_dex/bootstrap/sdk_bootstrap.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/key_value_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:digibyte_dex/platform/backup_exclusion.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  await _start();
}

Future<void> _start() async {
  await _excludeFromBackupOnIos();
  try {
    final sdk = await startSdk();
    final storage = SecureKeyValueStore();
    final wallet = SdkWalletRepository(sdk);
    final backups = BackupStatusStore(storage);
    final session = PendingBackupSession();
    final seeds = SdkSeedValidator(sdk.mnemonicValidator);
    await seeds.init();
    runApp(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: sdk),
          RepositoryProvider<WalletRepository>.value(value: wallet),
          RepositoryProvider<SeedValidator>.value(value: seeds),
          RepositoryProvider<AssetsRepository>.value(
            value: SdkAssetsRepository(sdk),
          ),
          RepositoryProvider<ReceiveRepository>.value(
            value: SdkReceiveRepository(sdk),
          ),
          RepositoryProvider.value(value: backups),
          RepositoryProvider.value(
            value: PasswordAttempts(LockoutStore(storage)),
          ),
          RepositoryProvider<BiometricStore>.value(
            value: DeviceBiometricStore(markers: storage),
          ),
          RepositoryProvider.value(value: session),
          RepositoryProvider.value(value: ClipboardGuard()),
          RepositoryProvider.value(value: const TextSharer()),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider(
              lazy: false,
              create: (_) => AuthCubit(wallet, backups: backups),
            ),
            BlocProvider(
              lazy: false,
              create: (context) => LockCubit(
                authStates: context.read<AuthCubit>().stream,
                onLocked: session.clear,
              ),
            ),
          ],
          child: const DigiByteDexApp(),
        ),
      ),
    );
  } on Object catch (error, stack) {
    debugPrint('Startup failed: $error\n$stack');
    runApp(StartupErrorApp(error: error, onRetry: _start));
  }
}

Future<void> _excludeFromBackupOnIos() async {
  if (!Platform.isIOS) return;
  try {
    await excludeAppDataFromBackup();
  } on MissingPluginException catch (error) {
    debugPrint('Backup exclusion unavailable: $error');
  } on PlatformException catch (error) {
    debugPrint('Backup exclusion failed: $error');
  }
}
```

Replace `app/test/support/test_app.dart` with its final form:

```dart
import 'package:digibyte_dex/app/app.dart';
import 'package:digibyte_dex/data/biometrics/biometric_store.dart';
import 'package:digibyte_dex/data/repositories/assets_repository.dart';
import 'package:digibyte_dex/data/repositories/receive_repository.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/data/storage/backup_status_store.dart';
import 'package:digibyte_dex/data/storage/lockout_store.dart';
import 'package:digibyte_dex/domain/seed/seed_validator.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/auth/bloc/lock_cubit.dart';
import 'package:digibyte_dex/features/auth/domain/password_attempts.dart';
import 'package:digibyte_dex/features/onboarding/bloc/pending_backup_session.dart';
import 'package:digibyte_dex/platform/clipboard_guard.dart';
import 'package:digibyte_dex/platform/text_sharer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'fake_assets_repository.dart';
import 'fake_biometric_store.dart';
import 'fake_receive_repository.dart';
import 'fake_seed_validator.dart';
import 'fake_text_sharer.dart';
import 'fake_wallet_repository.dart';
import 'in_memory_key_value_store.dart';

/// The whole app over fakes, wired like `main.dart`. [now] drives the lock
/// and lockout clocks.
class TestApp {
  TestApp() {
    auth = AuthCubit(wallet, backups: backups);
    lock = LockCubit(
      authStates: auth.stream,
      now: () => now,
      onLocked: session.clear,
    );
  }

  final wallet = FakeWalletRepository();
  final storage = InMemoryKeyValueStore();
  late final backups = BackupStatusStore(storage);
  late final attempts = PasswordAttempts(
    LockoutStore(storage),
    now: () => now,
  );
  final biometrics = FakeBiometricStore();
  final session = PendingBackupSession();
  final seeds = FakeSeedValidator();
  final assets = FakeAssetsRepository();
  final receive = FakeReceiveRepository();
  final clipboardWrites = <String>[];
  late final clipboard = ClipboardGuard(
    write: (text) async {
      clipboardWrites.add(text);
    },
    read: () async => null,
  );
  final sharer = FakeTextSharer();
  DateTime now = DateTime.utc(2026, 10, 1, 12);
  late final AuthCubit auth;
  late final LockCubit lock;

  Widget build() => MultiRepositoryProvider(
    providers: [
      RepositoryProvider<WalletRepository>.value(value: wallet),
      RepositoryProvider<SeedValidator>.value(value: seeds),
      RepositoryProvider<AssetsRepository>.value(value: assets),
      RepositoryProvider<ReceiveRepository>.value(value: receive),
      RepositoryProvider.value(value: backups),
      RepositoryProvider.value(value: attempts),
      RepositoryProvider<BiometricStore>.value(value: biometrics),
      RepositoryProvider.value(value: session),
      RepositoryProvider.value(value: clipboard),
      RepositoryProvider<TextSharer>.value(value: sharer),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider.value(value: auth),
        BlocProvider.value(value: lock),
      ],
      child: const DigiByteDexApp(),
    ),
  );

  Future<void> dispose() async {
    clipboard.dispose();
    await lock.close();
    await auth.close();
    await wallet.dispose();
  }
}
```

The `TestApp.clipboard` guard uses a real `Timer` (the default). It is only armed by a copy, and app tests do not copy.

- [ ] **Step 5: Run the tests, the analyzer and the debug build**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
fvm flutter gen-l10n
fvm dart format lib test
fvm flutter test test/platform test/data test/features/receive test/app
fvm flutter analyze
fvm flutter test
fvm flutter build apk --debug && bash ../tool/check_permissions.sh
```
Expected: all PASS; `No issues found!`; the APK builds; `permissions OK: 5 entries match allowlist` (share_plus and qr_flutter add no permissions).

- [ ] **Step 6: Commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
git add pubspec.yaml pubspec.lock lib test
git commit -m "feat(app): receive with QR, copy (60 s guarded clear), share and new HD address" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

---

### Task 14: Release 0.2.0, on-device acceptance on the Moto, and the PR

**Files:**
- Modify: `app/pubspec.yaml` (`version: 0.2.0+2`)
- Modify: `docs/release.md` (new section "M1-C acceptance")
- Scratch only, never committed:
  - `$SCRATCH/m1c-accept/env.sh`, `$SCRATCH/m1c-accept/ui.py`;
  - screenshots, the logcat dump, and the PR body.
- Secrets, mode 600, never printed:
  - `~/.config/dgb-dex/m1c-accept-password`, `~/.config/dgb-dex/m1c-wrong-password`, `~/.config/dgb-dex/m1c-iguana-seed`;
  - the existing `~/.config/dgb-dex/m0-phone-seed`.

**Interfaces:**
- Consumes every widget identifier listed in Tasks 8–13; Android reports each as a `resource-id`.
- Produces:
  - an installed 0.2.0 build on `ZY22HVMNKZ`;
  - the AAB in `~/digibyte-dex/release-artifacts/`;
  - the acceptance record in `docs/release.md`;
  - an open PR `feat/m1c-wallet-core` → `main`.

**Rules for this task:**
- Every adb command targets `-s ZY22HVMNKZ`. Never touch the Note 8. Never restart adb.
- Seed words and passwords are typed only through `type_secret` (8 characters per `input text` call, output discarded). Never `cat`, `echo` or print them.
- No screenshot is taken while a seed or password is visible. `secureshot` saves a capture only if it is blank, which proves `FLAG_SECURE`.
- `ui.py text`, `poll` and `changed` print node text. Use them only on addresses and balances.
- Steps marked **[OWNER]** need the owner at the phone (fingerprint). The controller asks the owner before running them.
- No send and no swap. Acceptance never spends funds.

- [ ] **Step 1: Bump the version and commit**

```bash
cd ~/digibyte-dex/digibyte-wallet/app
sed -i 's/^version: 0\.1\.0+1$/version: 0.2.0+2/' pubspec.yaml
grep -n '^version:' pubspec.yaml   # version: 0.2.0+2
fvm flutter analyze && fvm flutter test
git add pubspec.yaml
git commit -m "chore(app): version 0.2.0 (M1-C wallet core)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

- [ ] **Step 2: Build the signed AAB and keep a copy**

`$SCRATCH` is this session's scratchpad directory (see Global Constraints). Set it in every command block of this task.

```bash
cd ~/digibyte-dex/digibyte-wallet
mkdir -p "$SCRATCH/m1c-accept"
set -o pipefail
tool/release_android.sh | tee "$SCRATCH/m1c-accept/release.log"
VC=$(sed -n 's/^versionCode: *//p' "$SCRATCH/m1c-accept/release.log")
cp app/build/app/outputs/bundle/release/app-release.aab \
  ~/digibyte-dex/release-artifacts/digibyte-dex-0.2.0-$VC.aab
ls -l ~/digibyte-dex/release-artifacts/ | tail -2
```
Expected:
- the signer matches the upload certificate;
- every 16 KB row is PASS;
- `versionName: 0.2.0` and a `versionCode`;
- the AAB copy exists.

- [ ] **Step 3: Create the acceptance helpers and the test secrets**

Create `$SCRATCH/m1c-accept/env.sh`:

```bash
# Source me at the start of every acceptance command:
#   source "$SCRATCH/m1c-accept/env.sh"
set +x
ACC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D=ZY22HVMNKZ
S=~/.config/dgb-dex

# Types the content of file $1 into the focused field, 8 characters per
# `input text` call (spaces as %s). Prints nothing.
type_secret() {
  local secret chunk i
  secret="$(tr -d '\n' < "$1")"
  for ((i = 0; i < ${#secret}; i += 8)); do
    chunk="${secret:i:8}"
    chunk="${chunk// /%s}"
    adb -s "$D" shell input text "'${chunk}'" > /dev/null 2>&1
  done
  secret=''
  chunk=''
}

# A normal screenshot. Never use it on a screen showing a seed.
shot() { adb -s "$D" exec-out screencap -p > "$ACC/$1.png"; echo "saved $1.png"; }

ui() { python3 "$ACC/ui.py" "$@"; }

# Short pauses (seconds) go through ui.py; waits over a minute use a
# background `sleep` (foreground sleep is blocked in Claude Code).
pause() { python3 "$ACC/ui.py" pause "$1"; }

launch() { adb -s "$D" shell am start -n me.digiscope.wallet/.MainActivity > /dev/null; }

kill_app() { adb -s "$D" shell am force-stop me.digiscope.wallet; }
```

Create `$SCRATCH/m1c-accept/ui.py`:

```python
#!/usr/bin/env python3
"""Drives DigiByte DEX on the Moto by Semantics identifier.

Flutter reports Semantics(identifier:) as the node's resource-id in
`uiautomator dump`. Only `text`, `poll` and `changed` print node text,
and they are used for addresses and balances only.
"""
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


def backup():
    unfocus()
    root, hits = find(r'backup\.word\.\d+', 120)
    words = {int(n.get('resource-id').rsplit('.', 1)[1]): text_of(n)
             for n in hits}
    print(f'words shown: {len(words)}')
    if len(words) != 24:
        sys.exit('expected 24 words')
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
        if not is_blank(png):
            sys.exit('capture is NOT blank: FLAG_SECURE failed; not saved')
        with open(args[0], 'wb') as f:
            f.write(png)
        print('blank capture saved (FLAG_SECURE works)')
    elif cmd == 'backup':
        backup()
    elif cmd == 'pause':
        time.sleep(min(float(args[0]), 10.0))
    else:
        sys.exit(f'unknown command {cmd}')


if __name__ == '__main__':
    main()
```

Generate the throwaway secrets. They are written straight to mode-600 files and never printed.

```bash
umask 077
python3 - ~/.config/dgb-dex/m1c-accept-password ~/.config/dgb-dex/m1c-wrong-password <<'EOF'
import re, secrets, string, sys
alphabet = string.ascii_letters + string.digits
def make(prefix):
    while True:
        p = prefix + ''.join(secrets.choice(alphabet) for _ in range(12))
        if (re.search('[0-9]', p) and re.search('[a-z]', p)
                and re.search('[A-Z]', p) and not re.search(r'(.)\1\1', p)
                and 'password' not in p.lower()):
            return p
for path, prefix in zip(sys.argv[1:], ['Dgb_', 'Wrong_']):
    open(path, 'w').write(make(prefix))
print('written')
EOF
python3 - ~/.config/dgb-dex/m1c-iguana-seed <<'EOF'
import secrets, sys
wl = '/home/polloloco/digibyte-dex/digibyte-wallet/third_party/komodo-defi-sdk-flutter/packages/komodo_defi_types/assets/bip-0039/english-wordlist.txt'
words = open(wl).read().split()
open(sys.argv[1], 'w').write(' '.join(secrets.choice(words) for _ in range(12)))
print('written')
EOF
chmod 600 ~/.config/dgb-dex/m1c-*
ls -l ~/.config/dgb-dex/m1c-*   # three files, -rw-------
cat >> ~/.config/dgb-dex/SECRETS-INDEX.md <<'EOF'

## M1-C acceptance (Moto ZY22HVMNKZ, app me.digiscope.wallet 0.2.0)
- m1c-accept-password: password of wallets accept1, m0r, legacy1 (throwaway)
- m1c-wrong-password: deliberately wrong password for the lockout test
- m1c-iguana-seed: throwaway 12-word legacy (iguana) seed for wallet legacy1; no funds
- m0r restores m0-phone-seed (HD); funds stay put, nothing is spent
EOF
```

- [ ] **Step 4: Prepare the Moto and install with bundletool**

**[OWNER]** Confirm that the Moto has a screen lock and at least one enrolled fingerprint, and that you can touch the sensor during steps 6c and 6d.

```bash
source "$SCRATCH/m1c-accept/env.sh"
adb -s "$D" get-state                                  # device
adb -s "$D" shell getprop ro.product.model             # moto g 5G (2023)
adb -s "$D" shell pm list packages me.digiscope.wallet # may list .wallet and .wallet.m0
```
- If the exact line `package:me.digiscope.wallet` is present, the Play 0.1.0 build is installed. It is signed with Play's key and holds no wallet, so remove it. Never touch `me.digiscope.wallet.m0`.

  ```bash
  adb -s "$D" uninstall me.digiscope.wallet
  ```

- Then build the device APK set and install it:

```bash
source "$SCRATCH/m1c-accept/env.sh"
BT=$(ls ~/gradle-cache-clean/caches/modules-2/files-2.1/com.android.tools.build/bundletool/1.18.1/*/bundletool-1.18.1.jar | head -1)
K=~/.config/dgb-dex/android
java -jar "$BT" build-apks \
  --bundle=$HOME/digibyte-dex/digibyte-wallet/app/build/app/outputs/bundle/release/app-release.aab \
  --output="$ACC/m1c.apks" --overwrite \
  --connected-device --device-id="$D" --adb="$(command -v adb)" \
  --ks="$K/upload.jks" --ks-key-alias=upload \
  --ks-pass="file:$K/upload.password" --key-pass="file:$K/upload.password"
java -jar "$BT" install-apks --apks="$ACC/m1c.apks" --device-id="$D" --adb="$(command -v adb)"
adb -s "$D" shell dumpsys package me.digiscope.wallet | grep -m1 versionName   # versionName=0.2.0
adb -s "$D" logcat -c
```

- [ ] **Step 5: Create `accept1`, prove the 24-word backup and quiz (Review Focus 3 path)**

```bash
source "$SCRATCH/m1c-accept/env.sh"
launch
ui wait welcome.create 120 && shot 01-welcome
ui tap welcome.create
ui tap create.name && adb -s "$D" shell input text accept1
ui tap create.password && type_secret "$S/m1c-accept-password"
ui tap create.confirm && type_secret "$S/m1c-accept-password"
shot 02-create-form
ui tap create.submit
ui wait backup.continue 180
ui count 'backup\.word\.\d+'          # 24
ui secureshot "$ACC/03-backup-reveal-blank.png"
ui backup                              # words shown: 24 / quiz answered
ui wait home.row.DGB 120 && shot 04-home-accept1
```
Expected:
- `24`;
- "blank capture saved (FLAG_SECURE works)";
- "quiz answered";
- Home lists DGB, BTC, LTC in that order.

- [ ] **Step 6: Sign in after a kill, lock, auto-lock, biometrics, lockout**

6a. Kill, then sign in with the password; all three assets are active with 0 balances.

```bash
source "$SCRATCH/m1c-accept/env.sh"
kill_app && launch
ui wait signin.password 120
ui tap signin.password && type_secret "$S/m1c-accept-password"
ui tap signin.submit
for t in DGB BTC LTC; do echo "$t $(ui poll home.row.$t.balance 240)"; done   # 0 each
shot 05-home-after-kill
```

6b. Lock now, unlock with the password. Then go to the background for more than 2 minutes: the app is locked on return, and the recents thumbnail is blank.

```bash
source "$SCRATCH/m1c-accept/env.sh"
ui tap home.lock && ui wait locked.password 10 && shot 06-locked
ui tap locked.password && type_secret "$S/m1c-accept-password"
ui tap locked.submit && ui wait home.row.DGB 60
adb -s "$D" shell input keyevent KEYCODE_APP_SWITCH && pause 2 && shot 07-recents-blank
adb -s "$D" shell input keyevent KEYCODE_HOME
```
Wait 130 seconds. In Claude Code, foreground `sleep` is blocked, so run `sleep 130` with `run_in_background` and wait for its completion. Then:

```bash
source "$SCRATCH/m1c-accept/env.sh"
launch
ui wait locked.password 20 && shot 08-auto-locked
```

6c. **[OWNER]** Enable biometrics, then unlock with the fingerprint, both warm (local_auth gate) and cold (Keystore prompt).

```bash
source "$SCRATCH/m1c-accept/env.sh"
ui tap locked.enableBiometrics
ui tap locked.password && type_secret "$S/m1c-accept-password"
ui tap locked.submit
echo "OWNER: touch the fingerprint sensor (prompt: Unlock DigiByte DEX)"
ui wait home.row.DGB 90
ui tap home.lock && ui tap locked.biometric
echo "OWNER: touch the fingerprint sensor"
ui wait home.row.DGB 90 && shot 09-bio-unlock-warm
kill_app && launch
ui wait signin.biometric 120 && ui tap signin.biometric
echo "OWNER: touch the fingerprint sensor"
ui wait home.row.DGB 180 && shot 10-bio-signin-cold
```

6d. Five wrong passwords give a 30 s lockout, which survives a kill.

```bash
source "$SCRATCH/m1c-accept/env.sh"
ui tap home.lock
for i in 1 2 3 4 5; do
  ui tap locked.password && type_secret "$S/m1c-wrong-password"
  ui tap locked.submit
  ui busy locked.busy 60
done
ui wait locked.lockout 10 && shot 11-lockout
kill_app && launch
ui wait signin.lockout 120 && shot 12-lockout-after-kill
ui gone signin.lockout 60
ui tap signin.password && type_secret "$S/m1c-accept-password"
ui tap signin.submit && ui wait home.row.DGB 180
```
Expected:
- `locked.lockout` is present after the fifth failure;
- `signin.lockout` is present after the kill, and disappears by itself within 60 s;
- the password then works.

- [ ] **Step 7: Receive: QR, copy with clear, share, new address**

```bash
source "$SCRATCH/m1c-accept/env.sh"
ui tap home.row.DGB && ui wait receive.qr 60
A1=$(ui text receive.address); echo "DGB address: $A1"   # an address, not a secret
shot 13-receive
ui tap receive.copy && shot 14-copied
```
Wait 65 seconds with the app in the foreground (`sleep 65` with `run_in_background`). Then check the clipboard:

```bash
adb -s ZY22HVMNKZ shell cmd clipboard get-primary-clip 2>&1 | head -2
```
If that command is not available on this Android build (the output mentions an unknown command or no service), do the **[OWNER]** check instead:
1. Open Messages and start a new message.
2. Long-press the text box.
3. "Paste" must not offer the address.

Gboard's own clipboard history is a known gap. Then:

```bash
source "$SCRATCH/m1c-accept/env.sh"
ui tap receive.share && pause 2 && shot 15-share-sheet
adb -s "$D" shell input keyevent KEYCODE_BACK
A1=$(ui text receive.address)
ui tap receive.newAddress
ui changed receive.address "$A1" 60      # prints the new address
shot 16-new-address
adb -s "$D" shell input keyevent KEYCODE_BACK
```

- [ ] **Step 8: Restore the M0 phone wallet as `m0r` (HD, 12 words) and see its balances**

The seed is typed into the hidden, `FLAG_SECURE` field, last, so no screenshot or dump ever contains it.

```bash
source "$SCRATCH/m1c-accept/env.sh"
ui tap home.menu && ui tap home.signOut
ui wait signin.other 120 && ui tap signin.other
ui tap welcome.restore
ui tap restore.name && adb -s "$D" shell input text m0r
ui tap restore.password && type_secret "$S/m1c-accept-password"
ui tap restore.confirm && type_secret "$S/m1c-accept-password"
ui tap restore.seed && type_secret "$S/m0-phone-seed"
ui secureshot "$ACC/17-restore-blank.png"
ui tap restore.submit
ui wait home.row.DGB 300
echo "DGB $(ui poll home.row.DGB.balance 600)"   # about 750
echo "LTC $(ui poll home.row.LTC.balance 600)"   # about 0.05
shot 18-m0r-home
```
Expected:
- DGB is about 750 and LTC about 0.05, matching the M0 phone wallet (`SECRETS-INDEX.md`: `DLFhh33P…`, `LiL6drnB…`). This proves restore plus the 20-address scan.
- If a balance is 0, check the address on the receive page against `SECRETS-INDEX.md` before suspecting the scan.

- [ ] **Step 9: Legacy restore (iguana) shows a single address and no "New address"**

```bash
source "$SCRATCH/m1c-accept/env.sh"
ui tap home.menu && ui tap home.signOut
ui wait signin.other 120 && ui tap signin.other
ui tap welcome.restore
ui tap restore.legacy
ui tap restore.name && adb -s "$D" shell input text legacy1
ui tap restore.password && type_secret "$S/m1c-accept-password"
ui tap restore.confirm && type_secret "$S/m1c-accept-password"
ui tap restore.seed && type_secret "$S/m1c-iguana-seed"
ui tap restore.submit
ui wait home.row.DGB 300
ui tap home.row.DGB && ui wait receive.qr 60
ui wait receive.newAddress 5; echo "exit=$?"     # absent / exit=1
shot 19-legacy-receive
```

- [ ] **Step 10: Check that no secret reached the device log**

```bash
source "$SCRATCH/m1c-accept/env.sh"
adb -s "$D" logcat -d > "$ACC/logcat.txt"
python3 - "$ACC/logcat.txt" "$S/m0-phone-seed" "$S/m1c-iguana-seed" "$S/m1c-accept-password" "$S/m1c-wrong-password" <<'EOF'
import sys
log = open(sys.argv[1], errors='replace').read()
hits = 0
for path in sys.argv[2:]:
    secret = open(path).read().strip()
    words = secret.split()
    probes = ([' '.join(words[i:i + 3]) for i in range(len(words) - 2)]
              if len(words) >= 3 else [secret])
    hits += sum(1 for p in probes if p in log)
print('logcat secret scan:', 'clean' if hits == 0 else f'LEAK ({hits} hits)')
EOF
```
Expected: `logcat secret scan: clean`. On `LEAK`, delete `$ACC/logcat.txt` at once, stop, and report which file leaked (not its content).

- [ ] **Step 11: Record the results in `docs/release.md`**

Append this section to `~/digibyte-dex/digibyte-wallet/docs/release.md`. Fill each Result with PASS or FAIL and a short note from Steps 5–10; the evidence file names are the ones saved in `$ACC`.

```markdown
## M1-C acceptance (0.2.0)

Moto G 5G (2023) `ZY22HVMNKZ`, Android 14. Release AAB signed with the upload key, installed with bundletool `--connected-device`.

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Create `accept1`: 24 words shown on a FLAG_SECURE screen, quiz passed | | `03-backup-reveal-blank.png` (blank), `04-home-accept1.png` |
| 2 | Kill, sign in with password: DGB/BTC/LTC active with 0 balances | | `05-home-after-kill.png` |
| 3 | Lock now, unlock with password | | `06-locked.png` |
| 4 | Recents thumbnail blank; >2 min in background locks on return | | `07-recents-blank.png`, `08-auto-locked.png` |
| 5 | Biometrics enabled; fingerprint unlock (warm) and sign-in (cold) | | `09-bio-unlock-warm.png`, `10-bio-signin-cold.png` |
| 6 | 5 wrong passwords: 30 s lockout, survives a kill, then expires | | `11-lockout.png`, `12-lockout-after-kill.png` |
| 7 | Receive DGB: QR, copy, clipboard cleared after 60 s, share, new address | | `13`–`16` |
| 8 | Restore `m0r` (HD, 12 words): DGB ≈ 750, LTC ≈ 0.05 | | `17-restore-blank.png`, `18-m0r-home.png` |
| 9 | Legacy restore `legacy1` (iguana): one address, no New address | | `19-legacy-receive.png` |
| 10 | Logcat contains no seed or password | | scan output |

Known gaps:
- iOS screenshot blocking on seed screens is deferred to the iOS pass.
- Gboard's clipboard history is outside the app's control.

Play upload of this build is at the owner's discretion (`tool/play_upload.py`). If a Play install is planned, first remove this sideloaded build: `adb -s ZY22HVMNKZ uninstall me.digiscope.wallet`. It is signed with the upload key, not Play's key.
```

```bash
cd ~/digibyte-dex/digibyte-wallet
git add docs/release.md
git commit -m "docs(release): M1-C on-device acceptance (0.2.0)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
```

- [ ] **Step 12: Push, open the PR, and wait for CI**

```bash
cd ~/digibyte-dex/digibyte-wallet
bash tool/secret_scan.sh                                   # secret scan: clean
git ls-files | grep -Ei '\.jks$|\.p8$|key\.properties$|service-account' || echo "no secret files tracked"
git push -u origin feat/m1c-wallet-core
cat > "$SCRATCH/m1c-accept/pr-body.md" <<'EOF'
M1-C wallet core for DigiByte DEX 0.2.0.

- SDK fork: `mnemonicWordCount` → KDF `word_count` (24-word seeds); `HdGapLimit.software` = 20.
- Create (KDF-generated 24 words) with a forced, restart-safe backup quiz on FLAG_SECURE screens.
- Restore, HD or legacy iguana, with the seed normalised and validated before register. Sign-in always reuses the stored derivation method.
- KDF-mirror password rules and a strength meter.
- Biometric unlock (Keystore/Keychain bound, invalidated on re-enrolment).
- Auto-lock after 2 minutes and Lock now; unlocking reuses the KDF session.
- Persisted wrong-password lockout (30 s / 1 m / 5 m / 15 m / 1 h).
- Portfolio: DGB first, per-asset activation and retry, live balances.
- Receive: QR, copy with a guarded 60 s clipboard clear, share, new HD address.
- Privacy overlay and a blank recents thumbnail.

On-device acceptance: see `docs/release.md` → "M1-C acceptance".

Plan: `Digi-Dex-Komodo/docs/superpowers/plans/2026-10-01-m1c-wallet-core.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb
EOF
gh pr create -R JohnnyLawDGB/digibyte-wallet --base main --head feat/m1c-wallet-core \
  --title "M1-C: wallet core (create/backup, restore, unlock, portfolio, receive) — 0.2.0" \
  --body-file "$SCRATCH/m1c-accept/pr-body.md"
gh pr checks --watch -R JohnnyLawDGB/digibyte-wallet "$(gh pr view feat/m1c-wallet-core -R JohnnyLawDGB/digibyte-wallet --json number -q .number)"
```
Expected: `secret-scan`, `analyze-test`, `build-android` and `build-ios` are green. Fix any failure on the branch and push again.

**Stop here.** Report the PR URL. The controller runs the final whole-branch review and then merges with `gh pr merge feat/m1c-wallet-core --merge -R JohnnyLawDGB/digibyte-wallet`. The Play upload is at the owner's discretion.
