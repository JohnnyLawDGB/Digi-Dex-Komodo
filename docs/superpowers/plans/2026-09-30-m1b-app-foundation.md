# M1-B: App Foundation — "DigiByte DEX" skeleton, SDK bootstrap, CI and store pipeline

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An installable **DigiByte DEX** app (`me.digiscope.wallet`) with:
- the production SDK bootstrap: network 2014, only DGB/BTC/LTC, no Gleec services, pinned coin configs;
- auth-guarded routing, the DigiByte theme and icons, and English localisation scaffolding;
- platform hardening;
- CI on every PR, plus a signed release lane that uploads to **Play internal testing** and **TestFlight**.

Wallet features come later, in M1-C. This plan leaves `/welcome` and `/home` as placeholder screens behind the auth guard.

**Architecture:**
- A new Flutter project at `digibyte-wallet/app/`, with layout by feature per spec §4.2.
- The SDK is consumed through the existing submodule `third_party/komodo-defi-sdk-flutter`, repointed to HTTPS for CI.
- Two small SDK-fork patches:
  - auto-update of coin configs can be switched off;
  - the SDK fails fast instead of falling back to GLEECBTC coin configs.
- Dependencies are wired once in `main.dart` through `RepositoryProvider`/`BlocProvider`, with no mutable singletons.
- `go_router` redirects on the auth state from an `AuthCubit` over a `WalletRepository`.

**Tech Stack:**
- Flutter 3.41.4 (fvm), Dart ≥3.9, flutter_bloc 9.1.1, go_router, very_good_analysis, gen_l10n;
- GitHub Actions, Gradle/Xcode signing, App Store Connect API key, Google Play service account.

**Spec:** `docs/superpowers/specs/2026-09-27-digibyte-wallet-design.md`:
- §4.2 app layering, §5.1 translations, §7.1 market data, §7.2 electrum, §7.3 build, signing and store requirements;
- §8.2 transport, backups and hardening, §10 M1, §10a M1 decisions (app id, name, stores, branding).

## Global Constraints

- **Identity:**
  - App name **DigiByte DEX**. Android `applicationId` and iOS bundle ID **`me.digiscope.wallet`**; this can never change after the first Play upload.
  - Dart package name `digibyte_dex`.
  - The M0 probe (`me.digiscope.wallet.m0`) stays untouched.
- **Network:** netid `2014`, seed nodes `['seed1.digiscope.me']`. These are set only in `lib/config/brand.dart` and passed through `KomodoDefiSdkConfig.network`.
- **Assets:**
  - Listed wallet assets are exactly `DGB`, `BTC`, `LTC` (the curated list; spec §5.1 "no custom tokens").
  - `KomodoDefiSdkConfig.defaultAssets` must be exactly this set. The SDK default of KMD/BTC/ETH/DOC/MARTY must never apply.
- **No Gleec or Komodo services at runtime:**
  - `MarketDataConfig(enableKomodoPrice: false)`;
  - coin-config auto-update off;
  - no fallback to GLEECBTC coin configs.
- **Toolchain:** Flutter `3.41.4` via `.fvmrc` at the repo root, and `very_good_analysis` lints. `fvm flutter analyze` must be clean.
- **Platforms:**
  - Android: minSdk 28, targetSdk 35, 16 KB page alignment. Permissions are only `CAMERA` and `USE_BIOMETRIC` (plus `INTERNET`). `android:allowBackup="false"`, `android:usesCleartextTraffic="false"`.
  - iOS: 13+, `PrivacyInfo.xcprivacy`, app data excluded from iCloud backup, ATS defaults kept.
- **Secrets:**
  - The signing keystore, Play service-account JSON and ASC API key live only in GitHub Actions secrets on `JohnnyLawDGB/digibyte-wallet` and in `~/.config/dgb-dex/` (mode 600).
  - Never commit them. Never echo them in logs.
- **Devices:** the Moto `ZY22HVMNKZ` only. Never touch the Note 8 `ce061716640b191c017e`, and never restart adb.
- **Commits:** every commit message ends with a blank line and the two trailer lines (`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, `Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb`). The SDK fork's `digibyte/main` is protected against force-pushes and deletion; push normally.

## Review Focus

1. **A build must not silently pick up SDK defaults**: KMD/ETH assets, netid 6133, the Gleec price API, or GLEECBTC coin-config updates. → Task 5 `sdk_bootstrap_test.dart` asserts every field of the built `KomodoDefiSdkConfig`.
2. **A missing or corrupt bundled `build_config.json`** must fail loudly, not fall back to GLEECBTC. → Task 2 tests at each of the three fallback sites.
3. **Deep links or routes while signed out** must not reach any wallet screen. → Task 7 router redirect tests (`/home` while signed out redirects to `/welcome`; `/welcome` while signed in redirects to `/home`).
4. **Backup/cleartext regressions in manifests.** A later dependency merge could re-enable `allowBackup` or cleartext traffic. → Task 9 `platform_config_test.dart` parses the Android manifest and iOS plists in CI.
5. **Signing material leaking into the repo or CI logs.** → Task 11 Step 6 runs a secret scan over git history, and the workflow never prints decoded secrets. Task 10 CI runs the same scan on every PR.

---

### Task 1: SDK fork — make coin-config auto-update switchable

**Files (SDK fork `~/digibyte-dex/sdk`, branch `digibyte/main`):**
- Modify: `packages/komodo_defi_sdk/lib/src/sdk/komodo_defi_sdk_config.dart`: add a field, a constructor param and `copyWith`.
- Modify: `packages/komodo_defi_sdk/lib/src/bootstrap.dart` (~l.190-198): pass the flag to `KomodoAssetsUpdateManager`.
- Test: `packages/komodo_defi_sdk/test/sdk_config_asset_auto_update_test.dart`.

**Interfaces:**
- Produces: `KomodoDefiSdkConfig({..., bool enableAssetAutoUpdate = true})`, `final bool enableAssetAutoUpdate`, and `copyWith(enableAssetAutoUpdate:)`.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';

void main() {
  test('asset auto-update defaults on and can be switched off', () {
    const c = KomodoDefiSdkConfig();
    expect(c.enableAssetAutoUpdate, isTrue);
    final off = c.copyWith(enableAssetAutoUpdate: false);
    expect(off.enableAssetAutoUpdate, isFalse);
    expect(off.copyWith().enableAssetAutoUpdate, isFalse);
  });
}
```

- [ ] **Step 2: Run it and confirm it fails.** Run `cd packages/komodo_defi_sdk && fvm flutter test test/sdk_config_asset_auto_update_test.dart`. Expected: a compile error (no `enableAssetAutoUpdate`).

- [ ] **Step 3: Implement.**
  - Add the constructor param `this.enableAssetAutoUpdate = true,`.
  - Add the field `/// Whether coin configs are refreshed from the coins repo in the background.\n  final bool enableAssetAutoUpdate;`.
  - Add a `copyWith` param `bool? enableAssetAutoUpdate` and the body entry `enableAssetAutoUpdate: enableAssetAutoUpdate ?? this.enableAssetAutoUpdate,`.
  - In `bootstrap.dart`, change the `KomodoAssetsUpdateManager(` construction so it also passes `enableAutoUpdate: config.enableAssetAutoUpdate,`.

- [ ] **Step 4: Run it and confirm it passes, with the package suite and analysis green.**
  - Run `fvm flutter test test/sdk_config_asset_auto_update_test.dart && fvm flutter test && fvm dart analyze .`.
  - Revert `packages/komodo_defi_framework/app_build/build_config.json` if a run touched it.
  - Run `fvm dart format` on the touched files.

- [ ] **Step 5: Commit** `feat(sdk): KomodoDefiSdkConfig.enableAssetAutoUpdate` (with trailers). Do not push; Task 2 pushes both commits.

---

### Task 2: SDK fork — fail fast instead of falling back to GLEECBTC coin configs

**Files (SDK fork):**
- Modify: `packages/komodo_coins/lib/src/komodo_asset_update_manager.dart:232`
- Modify: `packages/komodo_coins/lib/src/startup/startup_coins_provider.dart:58-59`
- Modify: `packages/komodo_defi_framework/lib/src/services/seed_node_service.dart:23`
- Create: `packages/komodo_coin_updates/lib/src/runtime_update_config/require_runtime_config.dart`, and export it from `packages/komodo_coin_updates/lib/komodo_coin_updates.dart`
- Test: `packages/komodo_coin_updates/test/require_runtime_config_test.dart`

**Interfaces:**
- Produces: `Future<AssetRuntimeUpdateConfig> requireRuntimeConfig(AssetRuntimeUpdateConfigRepository repo)`. It returns the loaded config or throws a `StateError` whose message contains `build_config.json`.

- [ ] **Step 1: Failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class _NullRepo extends AssetRuntimeUpdateConfigRepository {
  @override
  Future<AssetRuntimeUpdateConfig?> tryLoad() async => null;
}

class _OkRepo extends AssetRuntimeUpdateConfigRepository {
  _OkRepo(this.c);
  final AssetRuntimeUpdateConfig c;
  @override
  Future<AssetRuntimeUpdateConfig?> tryLoad() async => c;
}

void main() {
  test('missing bundled config throws instead of using GLEECBTC defaults', () async {
    await expectLater(
      requireRuntimeConfig(_NullRepo()),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('build_config.json'))),
    );
  });

  test('loaded config is returned unchanged', () async {
    const c = AssetRuntimeUpdateConfig(coinsRepoBranch: 'digibyte/main');
    expect(await requireRuntimeConfig(_OkRepo(c)), same(c));
  });
}
```
If `AssetRuntimeUpdateConfigRepository` has a required constructor argument or `tryLoad` isn't overridable as written, match its real signature (read the class first) and keep the two assertions.

- [ ] **Step 2: Run it and confirm it fails.** Run `cd packages/komodo_coin_updates && fvm flutter test test/require_runtime_config_test.dart`. Expected: a compile error (no `requireRuntimeConfig`).

- [ ] **Step 3: Implement.** Create `require_runtime_config.dart`:

```dart
import 'package:komodo_coin_updates/src/runtime_update_config/asset_runtime_update_config_repository.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Loads the bundled runtime config or fails loudly.
///
/// DigiByte fork: the built-in `AssetRuntimeUpdateConfig()` defaults point at GLEECBTC/coins.
/// Falling back to them would silently switch a DigiByte build to another project's coin list,
/// so a missing or unreadable `build_config.json` is a fatal packaging error instead.
Future<AssetRuntimeUpdateConfig> requireRuntimeConfig(
  AssetRuntimeUpdateConfigRepository repo,
) async {
  final config = await repo.tryLoad();
  if (config == null) {
    throw StateError(
      'packages/komodo_defi_framework/app_build/build_config.json is missing or invalid; '
      'refusing to fall back to upstream coin configs.',
    );
  }
  return config;
}
```
- Export it from `komodo_coin_updates.dart`.
- Replace each of the three `await X.tryLoad() ?? const AssetRuntimeUpdateConfig()` expressions with `await requireRuntimeConfig(X)`, adding the import. For `seed_node_service.dart`, the package `komodo_defi_framework` must already depend on `komodo_coin_updates`; check its `pubspec.yaml`. If it doesn't, inline the same null-check with the same message there instead of adding a dependency.

- [ ] **Step 4: Run all three packages' suites**

```bash
for p in komodo_coin_updates komodo_coins komodo_defi_framework komodo_defi_sdk; do (cd packages/$p && fvm flutter test) || echo "FAIL $p"; done
git checkout -- packages/komodo_defi_framework/app_build/build_config.json 2>/dev/null; true
```
Expected: no `FAIL` lines. A test that previously relied on the silent default must now provide a config; fix those tests by giving them one, not by restoring the fallback.

- [ ] **Step 5: Commit and push**

```bash
git add packages && git commit -m "fix(sdk): fail fast when bundled build_config.json is missing (no GLEECBTC fallback)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011ayAYafJ16WYxRNyFFznGb"
git push origin refs/heads/digibyte/main:refs/heads/digibyte/main
echo "SDK_SHA_M1B=$(git rev-parse HEAD)" >> ~/.config/dgb-dex/kdf-release.env
```

---

### Task 3: App scaffold (`digibyte-wallet/app/`)

**Files (repo `~/digibyte-dex/digibyte-wallet`):**
- Modify: `.gitmodules` (URL → `https://github.com/JohnnyLawDGB/komodo-defi-sdk-flutter.git`), submodule pointer → `SDK_SHA_M1B`
- Create: `app/` via `flutter create`, then edit `app/pubspec.yaml`, `app/analysis_options.yaml`, `app/android/app/build.gradle.kts` (or `.gradle`), `app/ios/Runner.xcodeproj` (bundle ID), `app/ios/Runner/Info.plist` (display name)
- Test: `app/test/app_smoke_test.dart`

**Interfaces:**
- Produces: the Flutter package `digibyte_dex` at `app/`. Import prefix: `package:digibyte_dex/...`.

- [ ] **Step 1: Submodule to HTTPS and the new SDK commit**

```bash
cd ~/digibyte-dex/digibyte-wallet && source ~/.config/dgb-dex/kdf-release.env
git config -f .gitmodules submodule.third_party/komodo-defi-sdk-flutter.url https://github.com/JohnnyLawDGB/komodo-defi-sdk-flutter.git
git submodule sync && git -C third_party/komodo-defi-sdk-flutter fetch origin digibyte/main && git -C third_party/komodo-defi-sdk-flutter checkout "$SDK_SHA_M1B"
```

- [ ] **Step 2: Create the project**

```bash
fvm flutter create --org me.digiscope --project-name digibyte_dex --platforms android,ios --description "DigiByte DEX: DigiByte wallet and atomic-swap DEX" app
rm app/test/widget_test.dart
```

- [ ] **Step 3: Identity.**
  - **Android** (`app/android/app/build.gradle.kts`):
    - `namespace = "me.digiscope.wallet"`, `applicationId = "me.digiscope.wallet"`, `minSdk = 28`, `targetSdk = 35`.
    - Move `MainActivity.kt` to package `me.digiscope.wallet`: update both the directory `kotlin/me/digiscope/wallet/` and its `package` line.
    - In `AndroidManifest.xml`, set `android:label="DigiByte DEX"`.
  - **iOS:**
    - In `ios/Runner.xcodeproj/project.pbxproj`, set every `PRODUCT_BUNDLE_IDENTIFIER = me.digiscope.digibyteDex;` to `me.digiscope.wallet;`. The `RunnerTests` bundle becomes `me.digiscope.wallet.RunnerTests`.
    - Set `IPHONEOS_DEPLOYMENT_TARGET = 13.0;`.
    - In `Info.plist`, set `CFBundleDisplayName` to `DigiByte DEX`.

- [ ] **Step 4: pubspec.** Set `environment: sdk: '>=3.9.0 <4.0.0'`, `flutter: '>=3.35.0'`, and `version: 0.1.0+1`.
  - Dependencies: `flutter`, `flutter_localizations` (sdk), `intl: any`, `flutter_bloc: ^9.1.1`, `equatable: ^2.0.7`, `decimal: ^3.2.1`, `go_router` (add with `fvm flutter pub add go_router` and keep the resolved caret version), `komodo_defi_sdk` and `komodo_defi_types` as path deps to `../third_party/komodo-defi-sdk-flutter/packages/<name>`.
  - Dev dependencies: `flutter_test`, `bloc_test: ^10.0.0`, `mocktail: ^1.0.4`, `very_good_analysis` (via `pub add --dev`).
  - `dependency_overrides`: copy the 12 path overrides verbatim from `m0_probe/pubspec.yaml`. They are the same relative paths, since `app/` and `m0_probe/` are siblings.
  - `flutter:` section: `uses-material-design: true`, `generate: true`.

  `app/analysis_options.yaml`:

```yaml
include: package:very_good_analysis/analysis_options.yaml
analyzer:
  exclude:
    - lib/l10n/gen/**
    - web/**
linter:
  rules:
    public_member_api_docs: false
```

- [ ] **Step 5: Smoke test** (`app/test/app_smoke_test.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scaffold boots', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('DigiByte DEX'))));
    expect(find.text('DigiByte DEX'), findsOneWidget);
  });
}
```

- [ ] **Step 6: Verify**

Run: `cd app && fvm flutter pub get && fvm flutter analyze && fvm flutter test`
Expected: pub get resolves; the only analyzer issues are in `lib/main.dart` (the generated counter), which Task 7 replaces. Fix any others. The smoke test passes. Revert any build_config churn inside the submodule (`git -C ../third_party/komodo-defi-sdk-flutter status --short` must be empty).

- [ ] **Step 7: Commit** `feat(app): DigiByte DEX scaffold (me.digiscope.wallet); SDK submodule over HTTPS @ <short>`.

---

### Task 4: Brand, theme and icons

**Files:**
- Create: `app/lib/config/brand.dart`, `app/lib/theme/app_theme.dart`, `app/assets/brand/digibyte.svg`, `app/assets/brand/icon_1024.png`, `app/assets/brand/icon_foreground_1024.png`, `app/tool/render_icons.py`
- Modify: `app/pubspec.yaml` (assets, `flutter_launcher_icons` config and dev dep)
- Test: `app/test/config/brand_test.dart`, `app/test/theme/app_theme_test.dart`

**Interfaces:**
- Produces:
  - `abstract final class Brand { static const appName; static const netId; static const seedNodes; static const listedAssets; static const primaryColor; static const websiteUrl; static const supportUrl; }`
  - `ThemeData buildTheme(Brightness b)`

- [ ] **Step 1: Fetch the official logo and record its source**

```bash
cd ~/digibyte-dex/digibyte-wallet/app && mkdir -p assets/brand tool
curl -fsSL https://raw.githubusercontent.com/DigiByte-Core/digibyte/develop/src/qt/res/src/digibyte.svg -o assets/brand/digibyte.svg
printf 'Source: https://github.com/DigiByte-Core/digibyte/blob/develop/src/qt/res/src/digibyte.svg (MIT, DigiByte Core developers)\n' > assets/brand/SOURCE.txt
python3 - <<'EOF'
import re,collections
s=open('assets/brand/digibyte.svg').read()
c=collections.Counter(m.lower() for m in re.findall(r'#[0-9a-fA-F]{6}', s))
print(c.most_common(5))
EOF
```
Take the most common non-white, non-black colour as `Brand.primaryColor`. Record the hex in the commit message.

- [ ] **Step 2: Render the icons.** `tool/render_icons.py` uses `cairosvg` in a throwaway venv:
  - `icon_1024.png`: the logo centred at 80 % on a white 1024×1024 canvas. iOS icons must be opaque.
  - `icon_foreground_1024.png`: the logo at 66 % on a transparent canvas, for the Android adaptive-icon foreground. The Android adaptive background is white.

```python
import io, sys, cairosvg
from PIL import Image
svg = open('assets/brand/digibyte.svg','rb').read()
def render(size): return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg, output_width=size, output_height=size))).convert('RGBA')
def canvas(scale, bg):
    c = Image.new('RGBA', (1024,1024), bg); logo = render(int(1024*scale))
    c.alpha_composite(logo, ((1024-logo.width)//2, (1024-logo.height)//2)); return c
canvas(0.80, (255,255,255,255)).convert('RGB').save('assets/brand/icon_1024.png')
canvas(0.66, (0,0,0,0)).save('assets/brand/icon_foreground_1024.png')
print('ok')
```
Run it with `python3 -m venv /tmp/claude-1000/-home-polloloco-Digi-Dex-Komodo/01d56841-7970-4b28-ba34-65645351704c/scratchpad/iconvenv && …/iconvenv/bin/pip -q install cairosvg pillow && …/iconvenv/bin/python tool/render_icons.py`.

- [ ] **Step 3: Launcher icons.** Run `fvm flutter pub add --dev flutter_launcher_icons`, then add to `pubspec.yaml`:

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: assets/brand/icon_1024.png
  adaptive_icon_background: "#FFFFFF"
  adaptive_icon_foreground: assets/brand/icon_foreground_1024.png
  remove_alpha_ios: true
  min_sdk_android: 28
```
Then run `fvm dart run flutter_launcher_icons`.

- [ ] **Step 4: Failing tests**

`test/config/brand_test.dart`:
```dart
import 'package:digibyte_dex/config/brand.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identity and network are DigiByte, not upstream defaults', () {
    expect(Brand.appName, 'DigiByte DEX');
    expect(Brand.netId, 2014);
    expect(Brand.netId, isNot(anyOf(6133, 8762, 7777)));
    expect(Brand.seedNodes, ['seed1.digiscope.me']);
    expect(Brand.listedAssets, ['DGB', 'BTC', 'LTC']);
    expect(Brand.listedAssets.first, 'DGB', reason: 'DGB is pinned first in the portfolio');
  });
}
```
`test/theme/app_theme_test.dart`:
```dart
import 'package:digibyte_dex/config/brand.dart';
import 'package:digibyte_dex/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final b in Brightness.values) {
    test('theme ${b.name} is Material 3, seeded from the DigiByte colour', () {
      final t = buildTheme(b);
      expect(t.useMaterial3, isTrue);
      expect(t.brightness, b);
      expect(t.colorScheme, ColorScheme.fromSeed(seedColor: Brand.primaryColor, brightness: b));
    });
  }
}
```

- [ ] **Step 5: Run the tests and confirm they fail** (the imports don't exist yet). Run `fvm flutter test test/config test/theme`.

- [ ] **Step 6: Implement**

`lib/config/brand.dart`:
```dart
import 'package:flutter/painting.dart';

/// Every brand- and network-identity value lives here (spec §4.2).
abstract final class Brand {
  static const appName = 'DigiByte DEX';
  static const netId = 2014;
  static const seedNodes = <String>['seed1.digiscope.me'];

  /// Curated wallet assets, in portfolio order. DGB first.
  static const listedAssets = <String>['DGB', 'BTC', 'LTC'];

  /// Dominant colour of the official DigiByte logo (assets/brand/digibyte.svg).
  static const primaryColor = Color(0xFF______);

  static const websiteUrl = 'https://digibyte.org';
  static const supportUrl = 'https://digiscope.me';
}
```
Replace `______` with the six hex digits from Step 1. The plan cannot know that value until the SVG is read.

`lib/theme/app_theme.dart`:
```dart
import 'package:digibyte_dex/config/brand.dart';
import 'package:flutter/material.dart';

ThemeData buildTheme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(seedColor: Brand.primaryColor, brightness: brightness),
    );
```

- [ ] **Step 7: Run the tests, the analyzer and the launcher-icon output check**

Run: `fvm flutter test test/config test/theme && fvm flutter analyze && ls android/app/src/main/res/mipmap-anydpi-v26/ ios/Runner/Assets.xcassets/AppIcon.appiconset/ | head`
Expected: the tests pass and the icon files exist.

- [ ] **Step 8: Commit** `feat(app): DigiByte brand config, M3 theme, launcher icons from official logo (#<hex>)`.

---

### Task 5: Production SDK bootstrap

**Files:**
- Create: `app/lib/bootstrap/sdk_bootstrap.dart`
- Test: `app/test/bootstrap/sdk_bootstrap_test.dart`

**Interfaces:**
- Consumes: `Brand` (Task 4), `KomodoDefiSdkConfig.enableAssetAutoUpdate` (Task 1)
- Produces: `KomodoDefiSdkConfig buildSdkConfig()` and `Future<KomodoDefiSdk> startSdk()`

- [ ] **Step 1: Failing test (Review Focus 1)**

```dart
import 'package:digibyte_dex/bootstrap/sdk_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

void main() {
  final c = buildSdkConfig();

  test('network is DigiByte 2014 with explicit seeds', () {
    expect(c.network.netId, 2014);
    expect(c.network.seedNodes, ['seed1.digiscope.me']);
    expect(c.network.hasExplicitSeedNodes, isTrue);
  });

  test('only DGB, BTC, LTC are pre-activated', () {
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
}
```

- [ ] **Step 2: Run it and confirm it fails** (no `sdk_bootstrap.dart`).

- [ ] **Step 3: Implement**

```dart
import 'package:digibyte_dex/config/brand.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// The only place the SDK is configured. Every non-default here is a product decision (spec §7.1, §7.2).
KomodoDefiSdkConfig buildSdkConfig() => KomodoDefiSdkConfig(
      defaultAssets: Brand.listedAssets.toSet(),
      preActivateHistoricalAssets: false,
      preActivateCustomTokenAssets: false,
      marketDataConfig: const MarketDataConfig(enableKomodoPrice: false),
      enableAssetAutoUpdate: false,
      network: const KdfNetworkConfig(netId: Brand.netId, seedNodes: Brand.seedNodes),
    );

Future<KomodoDefiSdk> startSdk() async {
  final sdk = KomodoDefiSdk(config: buildSdkConfig());
  await sdk.initialize();
  return sdk;
}
```
If `MarketDataConfig` isn't exported by `komodo_defi_sdk`, import it from `package:komodo_cex_market_data/komodo_cex_market_data.dart`. In that case add `komodo_cex_market_data` as a path dependency: it is already in the overrides.

- [ ] **Step 4: Run it and confirm it passes**, then run `fvm flutter analyze`.

- [ ] **Step 5: Commit** `feat(app): production SDK bootstrap (netid 2014, DGB/BTC/LTC, no Gleec, pinned coin configs)`.

---

### Task 6: `WalletRepository` and `AuthCubit`

**Files:**
- Create: `app/lib/data/repositories/wallet_repository.dart`
- Create: `app/lib/features/auth/bloc/auth_cubit.dart`
- Test: `app/test/features/auth/auth_cubit_test.dart`
- Test: `app/test/support/fake_wallet_repository.dart`

**Interfaces:**
- Produces:
  - `abstract interface class WalletRepository { Stream<WalletUser?> watchUser(); Future<List<String>> walletNames(); Future<void> signOut(); }`. M1-C adds register, signIn and mnemonic methods.
  - `class WalletUser extends Equatable { const WalletUser(this.name); final String name; }`
  - `class SdkWalletRepository implements WalletRepository`, a constructor taking `KomodoDefiSdk`.
  - `sealed class AuthState` with `AuthUnknown`, `AuthSignedOut`, and `AuthSignedIn(WalletUser user)`.
  - `class AuthCubit extends Cubit<AuthState>`, constructor `AuthCubit(WalletRepository repo)`. It subscribes on construction and closes the subscription in `close()`.

- [ ] **Step 1: Failing tests**

`test/support/fake_wallet_repository.dart`:
```dart
import 'dart:async';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';

class FakeWalletRepository implements WalletRepository {
  final _users = StreamController<WalletUser?>.broadcast();
  void emit(WalletUser? u) => _users.add(u);
  @override
  Stream<WalletUser?> watchUser() => _users.stream;
  @override
  Future<List<String>> walletNames() async => const [];
  @override
  Future<void> signOut() async => emit(null);
  Future<void> dispose() => _users.close();
}
```
`test/features/auth/auth_cubit_test.dart`:
```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/fake_wallet_repository.dart';

void main() {
  late FakeWalletRepository repo;
  setUp(() => repo = FakeWalletRepository());
  tearDown(() => repo.dispose());

  test('starts unknown', () => expect(AuthCubit(repo).state, const AuthUnknown()));

  blocTest<AuthCubit, AuthState>(
    'maps repository user stream to signed-in / signed-out',
    build: () => AuthCubit(repo),
    act: (_) async {
      repo.emit(const WalletUser('main'));
      await Future<void>.delayed(Duration.zero);
      repo.emit(null);
    },
    expect: () => const [AuthSignedIn(WalletUser('main')), AuthSignedOut()],
  );
}
```

- [ ] **Step 2: Run the tests and confirm they fail.**

- [ ] **Step 3: Implement**

`lib/data/repositories/wallet_repository.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';

class WalletUser extends Equatable {
  const WalletUser(this.name);
  final String name;
  @override
  List<Object?> get props => [name];
}

abstract interface class WalletRepository {
  Stream<WalletUser?> watchUser();
  Future<List<String>> walletNames();
  Future<void> signOut();
}

class SdkWalletRepository implements WalletRepository {
  SdkWalletRepository(this._sdk);
  final KomodoDefiSdk _sdk;

  @override
  Stream<WalletUser?> watchUser() =>
      _sdk.auth.watchCurrentUser().map((u) => u == null ? null : WalletUser(u.walletId.name));

  @override
  Future<List<String>> walletNames() async =>
      (await _sdk.auth.getUsers()).map((u) => u.walletId.name).toList();

  @override
  Future<void> signOut() => _sdk.auth.signOut();
}
```
`lib/features/auth/bloc/auth_cubit.dart`:
```dart
import 'dart:async';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
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

final class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

final class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user);
  final WalletUser user;
  @override
  List<Object?> get props => [user];
}

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(WalletRepository repo) : super(const AuthUnknown()) {
    _sub = repo.watchUser().listen((u) => emit(u == null ? const AuthSignedOut() : AuthSignedIn(u)));
  }
  late final StreamSubscription<WalletUser?> _sub;

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**, then run the analyzer.
- [ ] **Step 5: Commit** `feat(app): WalletRepository and AuthCubit`.

---

### Task 7: Router with auth guard and app shell

**Files:**
- Create: `app/lib/app/router.dart`, `app/lib/app/app.dart`, `app/lib/features/onboarding/view/welcome_page.dart`, `app/lib/features/wallet/view/home_page.dart`
- Modify: `app/lib/main.dart` (replace)
- Test: `app/test/app/router_test.dart`

**Interfaces:**
- Consumes: `AuthCubit`, `AuthState` (Task 6); `startSdk()` (Task 5); `buildTheme` (Task 4)
- Produces:
  - `String? authRedirect(AuthState state, String location)`, pure and testable;
  - `GoRouter buildRouter(AuthCubit auth)`;
  - `class DigiByteDexApp extends StatelessWidget`;
  - route paths `Routes.welcome = '/welcome'`, `Routes.home = '/home'`, `Routes.splash = '/'`.

- [ ] **Step 1: Failing tests (Review Focus 3)**

```dart
import 'package:digibyte_dex/app/router.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const signedIn = AuthSignedIn(WalletUser('main'));
  group('authRedirect', () {
    test('unknown state holds on splash', () {
      expect(authRedirect(const AuthUnknown(), Routes.home), Routes.splash);
      expect(authRedirect(const AuthUnknown(), Routes.splash), isNull);
    });
    test('signed out never reaches wallet routes', () {
      expect(authRedirect(const AuthSignedOut(), Routes.home), Routes.welcome);
      expect(authRedirect(const AuthSignedOut(), '/home/asset/DGB'), Routes.welcome);
      expect(authRedirect(const AuthSignedOut(), Routes.splash), Routes.welcome);
      expect(authRedirect(const AuthSignedOut(), Routes.welcome), isNull);
    });
    test('signed in skips onboarding and splash', () {
      expect(authRedirect(signedIn, Routes.welcome), Routes.home);
      expect(authRedirect(signedIn, Routes.splash), Routes.home);
      expect(authRedirect(signedIn, Routes.home), isNull);
    });
  });
}
```

- [ ] **Step 2: Run the tests and confirm they fail.**

- [ ] **Step 3: Implement**

`lib/app/router.dart`:
```dart
import 'dart:async';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/features/onboarding/view/welcome_page.dart';
import 'package:digibyte_dex/features/wallet/view/home_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class Routes {
  static const splash = '/';
  static const welcome = '/welcome';
  static const home = '/home';
}

/// Pure redirect rule: signed-out users only see onboarding; signed-in users skip it.
String? authRedirect(AuthState state, String location) {
  final onboarding = location == Routes.welcome || location.startsWith('${Routes.welcome}/');
  return switch (state) {
    AuthUnknown() => location == Routes.splash ? null : Routes.splash,
    AuthSignedOut() => onboarding ? null : Routes.welcome,
    AuthSignedIn() => (onboarding || location == Routes.splash) ? Routes.home : null,
  };
}

class _CubitListenable extends ChangeNotifier {
  _CubitListenable(AuthCubit cubit) {
    _sub = cubit.stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<AuthState> _sub;
  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}

GoRouter buildRouter(AuthCubit auth) => GoRouter(
      initialLocation: Routes.splash,
      refreshListenable: _CubitListenable(auth),
      redirect: (context, state) => authRedirect(auth.state, state.matchedLocation),
      routes: [
        GoRoute(
          path: Routes.splash,
          builder: (_, __) => const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
        GoRoute(path: Routes.welcome, builder: (_, __) => const WelcomePage()),
        GoRoute(path: Routes.home, builder: (_, __) => const HomePage()),
      ],
    );
```
`welcome_page.dart` and `home_page.dart` are placeholders. Each is a `StatelessWidget` returning `Scaffold(appBar: AppBar(title: Text(context.l10n.<key>)), body: const SizedBox.shrink())`. Use a literal `'DigiByte DEX'` until Task 8 adds l10n; Task 8 then switches them.

`lib/app/app.dart`:
```dart
import 'package:digibyte_dex/app/router.dart';
import 'package:digibyte_dex/config/brand.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:digibyte_dex/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class DigiByteDexApp extends StatefulWidget {
  const DigiByteDexApp({super.key});
  @override
  State<DigiByteDexApp> createState() => _DigiByteDexAppState();
}

class _DigiByteDexAppState extends State<DigiByteDexApp> {
  late final GoRouter _router = buildRouter(context.read<AuthCubit>());
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: Brand.appName,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        routerConfig: _router,
      );
}
```
`lib/main.dart`:
```dart
import 'package:digibyte_dex/app/app.dart';
import 'package:digibyte_dex/bootstrap/sdk_bootstrap.dart';
import 'package:digibyte_dex/data/repositories/wallet_repository.dart';
import 'package:digibyte_dex/features/auth/bloc/auth_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sdk = await startSdk();
  final wallet = SdkWalletRepository(sdk);
  runApp(
    MultiRepositoryProvider(
      providers: [RepositoryProvider.value(value: sdk), RepositoryProvider<WalletRepository>.value(value: wallet)],
      child: BlocProvider(create: (_) => AuthCubit(wallet), child: const DigiByteDexApp()),
    ),
  );
}
```

- [ ] **Step 4: Run the tests and analyzer, and confirm they pass.**
- [ ] **Step 5: Commit** `feat(app): go_router auth guard and app shell`.

---

### Task 8: Localisation scaffolding (English)

**Files:**
- Create: `app/l10n.yaml`, `app/lib/l10n/arb/app_en.arb`, `app/lib/l10n/l10n.dart`
- Modify: `app/lib/app/app.dart` (delegates), the two placeholder pages
- Test: `app/test/l10n/l10n_test.dart`

**Interfaces:**
- Produces: the extension `BuildContext.l10n` → `AppLocalizations`, with the keys `appTitle`, `welcomeTitle`, `homeTitle`.

- [ ] **Step 1: Files**

`l10n.yaml`:
```yaml
arb-dir: lib/l10n/arb
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-dir: lib/l10n/gen
nullable-getter: false
```
`lib/l10n/arb/app_en.arb`:
```json
{
  "@@locale": "en",
  "appTitle": "DigiByte DEX",
  "welcomeTitle": "Welcome to DigiByte DEX",
  "homeTitle": "Portfolio"
}
```
`lib/l10n/l10n.dart`:
```dart
import 'package:digibyte_dex/l10n/gen/app_localizations.dart';
import 'package:flutter/widgets.dart';

export 'package:digibyte_dex/l10n/gen/app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
```

- [ ] **Step 2: Failing test**

```dart
import 'package:digibyte_dex/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('English strings resolve', (tester) async {
    late String title;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (c) { title = c.l10n.appTitle; return const SizedBox(); }),
    ));
    expect(title, 'DigiByte DEX');
  });
}
```
Run `fvm flutter gen-l10n && fvm flutter test test/l10n`. It fails until the generated files exist and the import resolves. Generate them, then rerun: PASS.

- [ ] **Step 3: Wire it up.**
  - In `MaterialApp.router`, add `localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,` and `onGenerateTitle: (c) => c.l10n.appTitle`.
  - Placeholder pages use `context.l10n.welcomeTitle` and `context.l10n.homeTitle`.
  - Add `lib/l10n/gen/` to `.gitignore`; CI runs `flutter gen-l10n`, which `flutter pub get` does because `generate: true` is set.
- [ ] **Step 4: Run the full test suite and analyzer.**
- [ ] **Step 5: Commit** `feat(app): gen_l10n English scaffolding`.

---

### Task 9: Platform hardening

**Files:**
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Create: `app/android/app/src/main/res/xml/data_extraction_rules.xml`
- Modify: `app/ios/Runner/Info.plist`
- Create: `app/ios/Runner/PrivacyInfo.xcprivacy`, added to the Runner target's resources in `project.pbxproj`
- Modify: `app/lib/main.dart` (iOS backup exclusion call)
- Create: `app/lib/platform/backup_exclusion.dart`
- Create: `app/ios/Runner/AppDelegate.swift` method channel handler
- Test: `app/test/platform/platform_config_test.dart`

**Interfaces:**
- Produces: `Future<void> excludeAppDataFromBackup()`, which is a no-op on Android because backup is disabled in the manifest.

- [ ] **Step 1: Failing test (Review Focus 4).** It parses the real files; it needs `xml: ^6.5.0` as a dev dep.

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _android = 'http://schemas.android.com/apk/res/android';

void main() {
  final manifest = XmlDocument.parse(File('android/app/src/main/AndroidManifest.xml').readAsStringSync());
  final app = manifest.findAllElements('application').single;

  test('no backups and no cleartext traffic', () {
    expect(app.getAttribute('allowBackup', namespace: _android), 'false');
    expect(app.getAttribute('usesCleartextTraffic', namespace: _android), 'false');
    expect(app.getAttribute('dataExtractionRules', namespace: _android), '@xml/data_extraction_rules');
  });

  test('only camera, biometric and internet permissions', () {
    final perms = manifest.findAllElements('uses-permission').map((e) => e.getAttribute('name', namespace: _android)).toSet();
    expect(perms, {'android.permission.INTERNET', 'android.permission.CAMERA', 'android.permission.USE_BIOMETRIC'});
  });

  test('iOS declares camera and Face ID usage and ships a privacy manifest', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('NSCameraUsageDescription'));
    expect(plist, contains('NSFaceIDUsageDescription'));
    expect(plist, isNot(contains('NSAllowsArbitraryLoads')));
    expect(File('ios/Runner/PrivacyInfo.xcprivacy').existsSync(), isTrue);
    expect(File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(), contains('PrivacyInfo.xcprivacy'));
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails.**

- [ ] **Step 3: Implement.**
  - **Android manifest:**
    - On `<application>` add `android:allowBackup="false" android:fullBackupContent="false" android:usesCleartextTraffic="false" android:dataExtractionRules="@xml/data_extraction_rules"`.
    - Add `<uses-permission android:name="android.permission.INTERNET"/>`, `…CAMERA` and `…USE_BIOMETRIC`.
    - `data_extraction_rules.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
  <cloud-backup><exclude domain="root" path="."/><exclude domain="file" path="."/><exclude domain="database" path="."/><exclude domain="sharedpref" path="."/></cloud-backup>
  <device-transfer><exclude domain="root" path="."/><exclude domain="file" path="."/><exclude domain="database" path="."/><exclude domain="sharedpref" path="."/></device-transfer>
</data-extraction-rules>
```
  - **iOS `Info.plist`:**
    - `NSCameraUsageDescription`: "Scan a QR code to fill in a payment address."
    - `NSFaceIDUsageDescription`: "Unlock DigiByte DEX with Face ID."
  - **`PrivacyInfo.xcprivacy`:** no tracking, and `NSPrivacyAccessedAPITypes` with the reasons Flutter's plugins require. Use the template from Flutter's docs for `NSPrivacyAccessedAPICategoryUserDefaults` (CA92.1) and `NSPrivacyAccessedAPICategoryFileTimestamp` (C617.1). Add it to the Runner target in Xcode: file reference, PBXBuildFile and Resources phase.
  - **Backup exclusion:** `backup_exclusion.dart` calls a `MethodChannel('me.digiscope.wallet/platform')` method `excludeFromBackup`. `AppDelegate.swift` handles it by setting `URLResourceValues.isExcludedFromBackup = true` on the Application Support and Documents directories. Call it in `main()` before `startSdk()`, guarded by `Platform.isIOS`.
- [ ] **Step 4: Run the tests and confirm they pass.** Run `fvm flutter build apk --debug` to confirm the manifest merges; the merged manifest must still pass. Check with `grep -c 'allowBackup="false"' build/app/intermediates/merged_manifests/debug/*/AndroidManifest.xml`.
- [ ] **Step 5: Commit** `feat(app): platform hardening (no backup, no cleartext, minimal permissions, privacy manifest)`.

---

### Task 10: CI on every PR

**Files:**
- Create: `.github/workflows/app-ci.yml`
- Create: `tool/secret_scan.sh` (repo root)

**Interfaces:**
- Produces: required checks `analyze-test`, `build-android`, `build-ios`, `secret-scan`.

- [ ] **Step 1: The secret scan** (`tool/secret_scan.sh`):

```bash
#!/usr/bin/env bash
# Fails if signing material or wallet secrets are tracked or were ever committed.
set -euo pipefail
bad=$(git log --all --name-only --format= | grep -Ei '\.(jks|keystore|p12|p8|mobileprovision)$|key\.properties$|service-account.*\.json$|MM2\.json$' | sort -u || true)
if [ -n "$bad" ]; then echo "signing/secret files in history:"; echo "$bad"; exit 1; fi
if git grep -nE '"passphrase"\s*:\s*"[^G"][^"]{20,}"|BEGIN (EC |RSA )?PRIVATE KEY' -- . ':!tool/secret_scan.sh'; then exit 1; fi
echo "secret scan: clean"
```
Run `bash tool/secret_scan.sh` and expect `secret scan: clean`. If it flags M0 files, investigate them before proceeding. `ops/*/MM2.json.example` does not match `MM2\.json$`.

- [ ] **Step 2: The workflow**

```yaml
name: app-ci
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with: { fetch-depth: 0 }
      - run: bash tool/secret_scan.sh
  analyze-test:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with: { submodules: recursive }
      - uses: subosito/flutter-action@<SHA> # pin: resolve with gh api repos/subosito/flutter-action/git/ref/tags/v2.x
        with: { flutter-version: '3.41.4', channel: stable }
      - working-directory: app
        env: { GITHUB_API_PUBLIC_READONLY_TOKEN: '${{ github.token }}' }
        run: |
          flutter pub get
          flutter analyze
          flutter test
  build-android:
    needs: analyze-test
    runs-on: ubuntu-latest
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with: { submodules: recursive }
      - uses: actions/setup-java@<SHA> # temurin 17
        with: { distribution: temurin, java-version: '17' }
      - uses: subosito/flutter-action@<SHA>
        with: { flutter-version: '3.41.4', channel: stable }
      - working-directory: app
        env: { GITHUB_API_PUBLIC_READONLY_TOKEN: '${{ github.token }}' }
        run: flutter build apk --debug
  build-ios:
    needs: analyze-test
    runs-on: macos-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with: { submodules: recursive }
      - uses: subosito/flutter-action@<SHA>
        with: { flutter-version: '3.41.4', channel: stable }
      - working-directory: app
        env: { GITHUB_API_PUBLIC_READONLY_TOKEN: '${{ github.token }}' }
        run: flutter build ios --debug --no-codesign
```
Before committing:
- Resolve each `<SHA>` with `gh api repos/<owner>/<repo>/git/ref/tags/<tag> -q .object.sha`, dereferencing annotated tags. Keep a `# vX.Y.Z` comment.
- Lint with the scratchpad `actionlint`.
- Check that `grep -nE '@v[0-9]+\s*$|@<SHA>' .github/workflows/app-ci.yml` finds nothing.

- [ ] **Step 3: Push a branch and open a PR to run CI.** Run `git checkout -b ci/app-foundation && git push -u origin ci/app-foundation && gh pr create --fill --base main -R JohnnyLawDGB/digibyte-wallet`. Watch with `gh pr checks --watch`. Expected: all 4 checks green. Fix and push until they are, then merge with `gh pr merge --squash`.

---

### Task 11: Signed release lane — Play internal testing and TestFlight

**Owner prerequisites (Step 1). Everything else is automated.**

**Files:**
- Modify: `app/android/app/build.gradle.kts` (release signingConfig from env/`key.properties`, which is never committed)
- Create: `.github/workflows/app-release.yml`
- Create: `app/ios/ExportOptions.plist`
- Create: `docs/release.md`

**Interfaces:**
- Consumes these repo secrets:
  - `ANDROID_UPLOAD_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
  - `PLAY_SERVICE_ACCOUNT_JSON`
  - `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_B64`, `APPLE_TEAM_ID`

- [ ] **Step 1: Owner, in the Play Console:**
  - create the app "DigiByte DEX" with package `me.digiscope.wallet`;
  - enable Play App Signing;
  - create a Google Cloud service account with the "Release to testing tracks" permission on this app, and give Claude its JSON key through `~/.config/dgb-dex/play-service-account.json` (mode 600).

  **Owner, in App Store Connect:**
  - register the bundle ID `me.digiscope.wallet` and create the app "DigiByte DEX";
  - create an App Store Connect API key with the "App Manager" role;
  - save `~/.config/dgb-dex/asc/AuthKey_<KEYID>.p8` plus `key_id` and `issuer_id` files, and record the Team ID.

  Record completion in `~/.config/dgb-dex/SECRETS-INDEX.md`.

- [ ] **Step 2: Generate the new Android upload key** (spec §7.3: new key, Play App Signing):

```bash
umask 077; mkdir -p ~/.config/dgb-dex/android
P=$(bash ~/digibyte-dex/digibyte-wallet/ops/tools/gen_rpc_password.sh)
keytool -genkeypair -v -keystore ~/.config/dgb-dex/android/upload.jks -alias upload -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$P" -keypass "$P" -dname "CN=DigiByte DEX, O=DigiScope, C=US"
printf '%s' "$P" > ~/.config/dgb-dex/android/upload.password
keytool -list -v -keystore ~/.config/dgb-dex/android/upload.jks -storepass "$P" | grep -E 'SHA256:' | head -1
```
Back up `upload.jks` and the password offline, then update `SECRETS-INDEX.md`.

- [ ] **Step 3: Load the CI secrets.** Pipe from files; never put a value on the command line:

```bash
R=JohnnyLawDGB/digibyte-wallet; C=~/.config/dgb-dex
base64 -w0 $C/android/upload.jks | gh secret set ANDROID_UPLOAD_KEYSTORE_B64 -R $R
gh secret set ANDROID_KEYSTORE_PASSWORD -R $R < $C/android/upload.password
gh secret set ANDROID_KEY_PASSWORD -R $R < $C/android/upload.password
printf upload | gh secret set ANDROID_KEY_ALIAS -R $R
gh secret set PLAY_SERVICE_ACCOUNT_JSON -R $R < $C/play-service-account.json
base64 -w0 $C/asc/AuthKey_*.p8 | gh secret set ASC_KEY_P8_B64 -R $R
gh secret set ASC_KEY_ID -R $R < $C/asc/key_id; gh secret set ASC_ISSUER_ID -R $R < $C/asc/issuer_id
gh secret set APPLE_TEAM_ID -R $R < $C/asc/team_id
gh secret list -R $R
```

- [ ] **Step 4: Gradle release signing** (`build.gradle.kts`). Read from environment variables, which are set in CI only:

```kotlin
signingConfigs {
    create("release") {
        val ks = System.getenv("ANDROID_KEYSTORE_PATH")
        if (ks != null) {
            storeFile = file(ks)
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
}
buildTypes {
    release {
        signingConfig = if (System.getenv("ANDROID_KEYSTORE_PATH") != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
    }
}
```

- [ ] **Step 5: `app-release.yml`.** Triggers are `workflow_dispatch` and tags `app-v*`. Jobs, all with pinned action SHAs:
  - **android:**
    1. decode the keystore to `$RUNNER_TEMP/upload.jks` and export `ANDROID_KEYSTORE_PATH`;
    2. `flutter build appbundle --release --build-number ${{ github.run_number }}`;
    3. upload to the internal track with `r0adkll/upload-google-play@<SHA>` (`serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}`, `packageName: me.digiscope.wallet`, `track: internal`, `status: draft`);
    4. delete the decoded keystore in an `if: always()` step.
  - **ios** (on `macos-latest`):
    1. write the `.p8` to `$RUNNER_TEMP/AuthKey_$ASC_KEY_ID.p8`;
    2. `flutter build ipa --release --build-number ${{ github.run_number }} --export-options-plist=ios/ExportOptions.plist` with automatic signing, via `-allowProvisioningUpdates` and the API key flags `-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID`. These go through `--export-options-plist` plus `FLUTTER_XCODE_*` env, or a follow-up `xcodebuild -exportArchive`;
    3. upload with `xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios --apiKey $ASC_KEY_ID --apiIssuer $ASC_ISSUER_ID` (altool reads the key from `~/.appstoreconnect/private_keys/`);
    4. `ExportOptions.plist`: `method` `app-store-connect`, `teamID` from `APPLE_TEAM_ID` (substituted at build time), `signingStyle` `automatic`.
  - Neither job may `echo` a secret. Use `::add-mask::` for any derived value.

- [ ] **Step 6: Run the first release (Review Focus 5 check first).**
  - Run `bash tool/secret_scan.sh`, then `git ls-files | grep -Ei 'jks|p8|key.properties|service-account'`. The second must print nothing.
  - Then `git tag app-v0.1.0 && git push origin app-v0.1.0` and watch the run.
  - Expected: a build appears in Play Console → Internal testing (draft) and in TestFlight (processing, then available).
  - The owner adds internal testers in both consoles.

- [ ] **Step 7: `docs/release.md`.** Document the lanes, the secret names, and how to rotate each secret. State the 16 KB check: `zipalign -c -P 16 -v 4 app-release.aab` or the Play pre-launch report. Commit `ci: signed Play internal and TestFlight release lane`.

---

### Task 12: Foundation acceptance on the Moto

- [ ] **Step 1: Install the Play internal-testing build** on `ZY22HVMNKZ` via the Play Store internal-test link. The owner accepts the tester invite on the phone.
- [ ] **Step 2: Verify:**
  - the launcher shows "DigiByte DEX" with the DigiByte icon;
  - the app opens on `/welcome` (signed out);
  - `adb -s ZY22HVMNKZ shell dumpsys package me.digiscope.wallet | grep -E 'versionName|flags=.*ALLOW_BACKUP'` shows versionName 0.1.0 and **no** `ALLOW_BACKUP` flag.
- [ ] **Step 3: Check no Gleec traffic at startup.** Run `adb -s ZY22HVMNKZ logcat -c`, launch the app, wait 60 s, then `adb -s ZY22HVMNKZ shell dumpsys netstats detail | grep -c me.digiscope.wallet`. The hostname check itself is by DNS: on the dev machine, point the phone at a DNS logger or use `adb shell` `dumpsys connectivity`. At minimum, confirm with a debug build and `--dart-define=LOG_HTTP=true` that no request goes to `*.gleec.com`, `*.cipig.net/…prices`, or `gleecbtc.github.io`. Record the method used and the result in `docs/release.md`.
- [ ] **Step 4:** The owner confirms the TestFlight build installs on their iPhone and opens on the welcome page.
