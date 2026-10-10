# M1-D3 "Settings": design spec

- **Date:** 2026-10-10
- **Status:** design approved by the owner in conversation 2026-10-10; written spec awaiting review.
- **Parent spec:** `2026-09-27-digibyte-wallet-design.md`, §5.1 (Settings).
- **Previous milestone:** `2026-10-08-m1d2-prices-usd-design.md`. M1-D2 merged as PR #6; 0.4.1 followed as PR #7, and is on Play internal.
- **Repo:** app `JohnnyLawDGB/digibyte-wallet`, branch `feat/m1d3-settings`. **No SDK fork change is expected** — see §7.

## 1. Purpose and scope

The wallet has no settings at all: `lib/features/` has no `settings` directory, the auto-lock timeout is a compile-time constant, and the only way to see a seed is the onboarding backup page, which bypasses the shared lockout. M1-D3 adds the settings surface and the controls that sit over primitives the app already has.

**In scope:**
- A Settings screen, reached from the Home overflow menu.
- View seed, through `PasswordGate` (this is also the fix for the M1-D1 defect).
- Biometric toggle.
- Auto-lock timeout.
- Theme (light / dark / system).
- Assets on/off.
- About.
- Delete wallet.

**Explicitly out of scope, each its own later lane:**
- **Fiat currency.** The price layer is USD-only (`UsdFormat`, CoinGecko `usd`). Multi-fiat touches the price repository, its cache, the portfolio total, the sparklines and Send's "≈ $". It is not a dropdown.
- **Log export.** There is no log capture to export: about 55 ad-hoc `debugPrint` sites and no buffer. It needs capture plus redaction, and after the M1-D1 incident where a throwaway seed reached a transcript, redaction is a design problem in its own right.
- **Language.** English only at v1 (parent spec §5.1).

## 2. Decisions (owner, 2026-10-10)

| # | Question | Decision |
| --- | --- | --- |
| 1 | Lane scope | Split. The screen and the controls that sit over existing primitives now; fiat currency and log export become their own lanes. |
| 2 | Delete wallet | `PasswordGate`, then type the wallet's name. Deletes that wallet only; other wallets are untouched; the last one deleted returns to onboarding. |
| 3 | Assets on/off | Off really deactivates the coin in KDF. A coin holding a balance refuses, with a warning. DGB is pinned and cannot be switched off. |
| 4 | Auto-lock choices | Immediately, 1 min, 2 min (default, today's constant), 5 min, 15 min. **No "Never".** |
| 5 | Setting scope | Security settings follow the wallet; appearance is app-wide. |

## 3. Storage

The repo already has the pattern: small typed stores over `KeyValueStore` (`backup_status_store.dart`, `lockout_store.dart`, `last_wallet_store.dart`). M1-D3 follows it rather than introducing a settings framework.

| Store | Scope | Key | Holds |
| --- | --- | --- | --- |
| `ThemeStore` | App | `theme_mode` | `system` (default), `light`, `dark` |
| `AutoLockStore` | Wallet | `autolock_<wallet>` | One of the durations in decision 4 above; absent means 2 min |
| `EnabledAssetsStore` | Wallet | `assets_off_<wallet>` | Persists the tickers switched **off** and exposes the enabled list. Storing the off-list means an asset added in a later release is on by default |

Biometric state already lives in `DeviceBiometricStore` as `bio_on_<wallet>` and `bio_pw_<wallet>`. The toggle reads and writes those; it does not duplicate them.

Per-wallet keys use the wallet-name suffix biometrics already uses. **One module owns the list of per-wallet key prefixes**, and delete-wallet sweeps the list rather than naming keys at the call site. That is what keeps a future setting from being orphaned when a wallet is deleted; §5.3 tests it directly.

## 4. Architecture

`SettingsCubit` backs the **page only**: it reads the stores, exposes one view-model for the screen, and writes back.

The consumers deliberately do not go through it:

- `LockCubit` takes its timeout from `AutoLockStore`, replacing `SecurityDefaults.autoLockTimeout`. A change applies to the running session, not just the next sign-in.
- `PortfolioBloc` takes its asset list from `EnabledAssetsStore`.
- The root `MaterialApp` takes its `themeMode` from `ThemeStore`.

The alternative — one `Settings` value object streamed everywhere — was rejected: it couples lock, portfolio and theme so any change rebuilds all of them, and every test needs the whole object. For eight controls that cost is not worth paying.

`SecurityDefaults.autoLockTimeout` stays as the default the store falls back to, so the security default remains stated in one place.

## 5. The screen

One page, reached from the existing Home overflow menu (`home.menu`, which already holds sign-out). Sections, in order:

1. **Security** — view seed, biometrics, auto-lock timeout.
2. **Appearance** — theme.
3. **Assets** — one switch per asset.
4. **About** — app version and versionCode (from `package_info_plus`, so they cannot drift from the installed build), a link to digiscope.me, and licences via `showLicensePage`. Fork commit hashes are **not** shown: nothing surfaces them at runtime today, and adding a build-time constant for them belongs with the log-export lane, which needs the same data.
5. **Danger zone**, visually separated — delete wallet.

Every row carries a `Tagged` semantics identifier (`settings.<item>`), as the acceptance tooling drives the app by identifier.

### 5.1 View seed

Settings → `PasswordGate` (the shared lockout, so attempts count) → the reveal screen with `FLAG_SECURE`, no selection and no copy.

This closes the M1-D1 finding that the backup page's own password prompt bypassed `PasswordAttempts`. The reveal widget is reused; the onboarding quiz is not — this path is for an existing wallet whose owner already passed it.

### 5.2 Biometric toggle

- **On** runs the existing strong-only opt-in, including the 2 min backstop and the 1 s resume grace shipped in 0.4.1. A refusal shows the existing notice and leaves the switch off.
- **Off** deletes `bio_pw_<wallet>` and `bio_on_<wallet>`.

### 5.3 Delete wallet

The SDK already provides this; §7 records what was verified. The flow is two-phase, which matches the SDK's own shape:

1. `sdk.walletDeletion.prepare(name)` returns a `WalletDeletionReview` — the warning to show. It can name **pending transfers**, which the screen must surface: deleting with a payment in flight loses it.
2. `PasswordGate`, then the user types the wallet name.
3. `sdk.walletDeletion.delete(acknowledgedReview:, password:)` returns a `WalletDeletionResult`:
   - `deleted` — sweep every per-wallet key for that wallet (§3), then sign out; if no wallets remain, go to onboarding.
   - `reviewChanged` — show the returned review and ask again. Do not delete on the stale acknowledgement.
   - `targetChanged` — return to wallet selection.
   - `busy` — tell the user to retry; never retry automatically.

A test asserts that after `deleted`, no key for that wallet remains in the store — `bio_pw_`, `bio_on_`, `autolock_`, `assets_off_`, backup status and the last-wallet pointer.

### 5.4 Assets on/off

Off calls the SDK's deactivation path (`disable_coin` underneath) so the coin stops connecting to electrum, which is the only reason the switch is worth having. DGB is pinned: its row renders without a switch.

A coin whose balance is above zero refuses, with a warning naming the balance, so funds never silently leave the portfolio total. The check reads the balance the portfolio already holds; it does not introduce a second source of truth.

## 6. Testing

- A cubit test per store, including the default when a key is absent.
- `LockCubit` honours a changed timeout **in the running session**.
- `PortfolioBloc` drops and restores a row as assets are switched off and on.
- Switching off a funded coin refuses and leaves it active.
- Delete wallet: each of the four statuses, plus the key-sweep assertion in §5.3.
- View seed goes through `PasswordGate` and counts a wrong password against the shared lockout.
- A widget test at **320 px × textScale 2.0** over the settings rows. 0.4.0 shipped a Home row that collapsed at that setting; the lesson is applied here rather than relearned.

## 7. Risks and open items

- **Verified on 2026-10-10, read-only:** `sdk.walletDeletion` is public (`komodo_defi_sdk.dart:224`), with `prepare` / `delete`, the `WalletDeletionStatus` enum above, and a KDF `delete_wallet` v2 RPC. `disable_coin` exists in the RPC methods and the activation manager. **So the lane needs no SDK fork change** — the risk raised during design is closed.
- **Not yet verified:** the exact SDK call the app should use to deactivate one asset, and whether deactivating while the portfolio is watching activation states produces a transient `failed` row. To be settled in the plan, with a test.
- Deleting the signed-in wallet while a send is in flight: the single-send-per-session rule from M1-D1 already blocks a second send, and the deletion review names pending transfers. The screen must not offer delete while a send is mid-broadcast.
- Theme is app-wide, so it must be readable before sign-in, at the sign-in page.

## 8. Release

0.5.0, as the first release of M1-D3. Local release lane, Play internal first, then on-device acceptance on the Moto covering: each setting persists across a cold start, auto-lock actually locks at the chosen timeout, an asset switched off stops its electrum connection (`conns.py`), view seed goes through the lockout, and delete wallet removes a throwaway wallet and returns to sign-in.
