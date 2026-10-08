# M1-D2 "Prices and USD": design spec

- **Date:** 2026-10-08
- **Status:** approved by the owner 2026-10-08 (design in conversation, written spec reviewed; plan d646b0af).
- **Parent spec:** `2026-09-27-digibyte-wallet-design.md`, §5.1 (Portfolio fiat values and total; asset-detail sparkline) and §7.1 (market data).
- **Previous milestone:** `2026-10-04-m1d1-move-money-design.md`. M1-D1 was merged as PR #5, and 0.3.1 is on Play internal.
- **Research:** `.superpowers/research/m1d2-prices.md`. It covers the SDK market data and the CoinGecko findings.
- **Repo:** app `JohnnyLawDGB/digibyte-wallet`, branch `feat/m1d2-prices-usd`. This milestone needs no SDK fork change.

## 1. Purpose and scope

The wallet shows balances only in coin units. M1-D2 adds USD values sourced from CoinGecko, and fixes three cosmetic issues found during M1-D1 acceptance.

**In scope:**
- USD price, value and 24h change on Home.
- A portfolio USD total.
- USD value, unit price and a 24h/7d/30d sparkline on asset detail.
- "≈ $" on the Send form and the Confirm screen.
- Follow-ups R3-1, R3-2 and S3-2 (§6).

**Out of scope:**
- Fiat currencies other than USD. There is no currency picker; this replaces the parent spec's "fiat currency" setting.
- Entering an amount in USD.
- Per-transaction historical USD values.
- Settings and log export, which move to a later milestone (M1-D3).
- A digiscope.me price proxy. The design keeps the base URL configurable so a proxy can be added later.
- iOS verification, which is deferred to the iOS pass.

**Success criteria:**
1. On the Moto with 0.4.0 from Play internal:
   - Home shows a USD total and a USD value plus 24h change for each coin, within about 1% of coingecko.com at the same moment.
   - Asset detail shows 24h, 7d and 30d sparklines.
   - Send and Confirm show "≈ $".
2. With the network off, the price fields show "Price unavailable" or a stale note, and every wallet function still works. Prices come back by themselves when the network returns.
3. The three follow-ups are verified on the device.
4. The app makes network calls only to CoinGecko and the configured electrum or KDF peers. The SDK market-data providers are off.
5. The task reviews and the whole-branch review are clean, and the log scan is clean.

## 2. Decisions (owner, 2026-10-07/08)

| # | Decision |
|---|---|
| P1 | The price source is CoinGecko. |
| P2 | The only fiat currency is USD. |
| P3 | M1-D2 covers prices and USD plus three follow-ups. Settings and log export become M1-D3. |
| P4 | The app has its own small CoinGecko client. The SDK market data is not used: all of its providers are disabled. The base URL lives in `brand.dart`, so a proxy can be swapped in later. |

## 3. Price data layer

### 3.1 `PriceRepository` (interface) and `CoinGeckoPriceRepository`

The repository sits behind a small HTTP port so tests can fake it.

**Spot prices:**
- Request: `GET {base}/api/v3/simple/price?ids=digibyte,bitcoin,litecoin&vs_currencies=usd&include_24hr_change=true`.
  - The ids come from each listed asset's `coingecko_id` in the coin config: DGB maps to `digibyte`, BTC to `bitcoin` and LTC to `litecoin`.
  - One call covers all listed assets.
- Result: a `Map<String ticker, PriceQuote>`. A `PriceQuote` holds:
  - `usd` as a `Decimal`, parsed from the JSON number's string form so it never goes through a `double`;
  - `change24hPct` as a `Decimal?`;
  - `fetchedAt`.
- An asset that is missing from the response has no quote. That is not an error.

**Sparklines:**
- Request: `GET {base}/api/v3/coins/{id}/market_chart?vs_currency=usd&days=N`, with N being 1, 7 or 30.
- Result: a list of `(DateTime, double)` points. Doubles are acceptable here because the chart is display-only.

**Configuration and errors:**
- **Base URL:** `Brand.priceApiBase`, default `https://api.coingecko.com`. There is no API key in M1-D2.
- **Timeout:** 10 s per request.
- **Errors:** a timeout, network error, 429, 5xx or malformed body maps to a typed `PriceFailure` (`network`, `rateLimited`, `server`, `malformed`). The repository never throws to the UI.
- **Headers and privacy:** requests carry `Accept: application/json` and no identifying data. Wallet addresses and balances are never sent.

### 3.2 `PriceService` (app-wide, one per running app)

**Exposed state:** `Stream<PriceSnapshot>`. A snapshot holds the quotes per ticker, the last successful fetch time, a `stale` flag (true when the last success is more than 15 minutes old) and an optional last failure.

**Polling:**
- Interval: every 3 minutes, but only while signed in, unlocked and in the foreground (lifecycle `resumed`).
- It also refreshes immediately on sign-in, on unlock and on resume.
- It stops when the app is locked, backgrounded or signed out.

**Backoff on `rateLimited` or `server`:** 3 → 6 → 12 → 24 → 30 minutes (capped). It resets after a success.

**Timers:** all timers are injectable.

**Cache:**
- The last good snapshot is kept in memory.
- A small on-disk copy (quotes and time only, nothing secret) is stored through the existing `KeyValueStore`, so the first paint after a cold start can show the last prices marked stale.

**Sparklines:**
- `chart(ticker, days)` fetches on demand.
- Results are cached in memory for 10 minutes per (ticker, days), per parent spec §7.1.

### 3.3 SDK market data off

`buildSdkConfig` passes `MarketDataConfig(enableKomodoPrice: false, enableBinance: false, enableCoinPaprika: false, enableCoinGecko: false)`. If the SDK API names differ, use the closest equivalent that disables every provider.

A unit test asserts that the config disables every provider.

## 4. Where USD appears

### 4.1 Home (Portfolio)

**Header total:** the sum of balance × price over the listed assets.
- If every asset has a price, it shows "$1,234.56".
- If some listed asset with a non-zero balance has no price, it shows "≈ $X" plus a note: "excludes BTC" (naming the missing ones).
- If nothing is priced, it shows "Price unavailable".

**Each row:**
- the coin balance (as now);
- the USD value below it;
- the 24h change: ▲ in green or ▼ in red, as a percent with 2 decimals.

**Stale prices:** a subtle note "Prices as of HH:MM".

### 4.2 Asset detail

**Header:**
- the coin balance;
- its USD value;
- the unit price, for example "1 DGB = $0.012345".

**Sparkline:**
- tabs for 24h, 7d and 30d (default 7d);
- the % change over the period;
- a skeleton while loading;
- "Chart unavailable" plus Retry on failure.

History rows are unchanged: coin amounts only.

### 4.3 Send

**Form:** "≈ $X.XX" under the amount, updated as the user types. It is shown only when the amount parses validly and a price is known.

**Confirm:** the amount, fee and total each get "≈ $X.XX" next to them.

**Rules:**
- The coin amount from the signed preview remains the only source of truth.
- USD is display-only and never feeds into the amount, the fee or validation.
- If there is no price, no "≈" is shown.

### 4.4 Formatting (`UsdFormat`, pure)

| Value | Format |
|---|---|
| ≥ $0.01 | `$` with 2 decimals, half-up for display, with thousands separators. Example: `$1,234.56`. |
| > 0 and < $0.01 | Up to 6 significant digits, never in scientific notation. Example: `$0.012345`, `$0.000123`. |
| 0 | `$0.00` |
| 24h change | Sign arrow plus 2 decimals plus `%`. Example: `▲ 3.21%`. |

Every string goes through ARB. Every new interactive widget is wrapped in `Tagged(id)`, using id prefixes `price.*`, `home.total`, `asset.price`, `asset.chart.*`, `send.usd` and `confirm.usd`.

## 5. Architecture

The existing layering stays (§4.2 of the parent spec, and M1-D1). The new units:

| Unit | Responsibility |
|---|---|
| `domain/usd_format.dart` | Pure formatting (§4.4). |
| `domain/portfolio_value.dart` | Pure total and partial-total calculation (§4.1). |
| `data/repositories/price_repository.dart` | The interface, `CoinGeckoPriceRepository`, the `PriceQuote` and `PricePoint` types, and the `PriceFailure` mapping. The HTTP port uses `package:http` or `dart:io`, whichever the app already depends on. |
| `data/price_service.dart` | Polling, lifecycle gating, backoff, the stale flag, the disk cache and the chart cache. |
| Provider wiring | `AppServices.prices` in `app_scope.dart`. The service is created at app start and started or stopped by the auth and lock state. |
| `features/portfolio/…` | Total and per-row USD. |
| `features/asset/…` | Header USD, unit price and the sparkline widget (a custom painter; no chart dependency unless an existing one is already used). |
| `features/send/…` | "≈ $" on the form and on Confirm. |

**New dependencies:** none, if `package:http` is already a transitive dependency of the app. If it isn't, add `http` as a direct dependency. That adds no Android permission, because INTERNET is already granted.

## 6. M1-D1 follow-ups included

1. **R3-1, "Dec 31, 1969" on received mempool transactions.**
   - A transaction whose timestamp is at or before the Unix epoch (0) is treated as having an unknown time.
   - The row and the sheet show "Pending" and no date until it is mined, and then show the real time.
   - This is a pure mapping fix in `TxView` or history formatting, with tests.
2. **R3-2, fingerprint prompt left on screen after "Use password".**
   - **Why it happens:** on Android, the system BiometricPrompt's negative button never reports back to flutter_secure_storage, so the app waits for its 30 s timeout while the prompt stays up.
   - **Fix:** while a biometric prompt is pending, if the app lifecycle goes to `inactive` and then back to `resumed` without a plugin result, wait about 1 s and treat the prompt as cancelled.
     - The password field returns immediately.
     - For an opt-in, the "wasn't turned on" notice shows immediately.
   - The existing 30 s timeout and the late-write cleanup stay as backstops.
   - Unit tests must cover:
     - a resume with no result → cancelled after the grace period;
     - a result arriving within the grace period → that result wins;
     - a late result after the resume-cancel → dropped, with the late write cleaned up.
   - If the device shows this isn't reliable, it is recorded and falls back to the timeout.
3. **S3-2, sign-in preselects the first wallet.**
   - Persist the last signed-in wallet name in the existing state `KeyValueStore`.
   - Sign-in preselects that wallet if it still exists; otherwise the first one.
   - Tests cover the preselect, a deleted wallet and an empty store.

## 7. Testing

**TDD:** RED then GREEN for every unit. Analyze must be clean (very_good_analysis; infos are fatal), and format must be clean.

| Area | What is tested |
|---|---|
| Client | Parsing of recorded real-shaped fixtures for `simple/price` and `market_chart`. Missing ids. Each `PriceFailure` mapping (timeout, 429, 5xx, malformed). `Decimal` parsing from the JSON number text. |
| Service | Fake timers and a fake lifecycle and auth source: the 3-minute poll, immediate refresh on unlock and resume, no polling while locked, backgrounded or signed out, the backoff sequence and its reset, the stale flag at 15 minutes, the disk cache round-trip, and the 10-minute chart cache. |
| Pure functions | `UsdFormat` (cents, sub-cent, zero, separators, change arrows) and `PortfolioValue` (all priced, partial, none). |
| Widgets | Home total and rows (priced, partial, unavailable, stale); the asset header; sparkline tabs, loading and error; Send and Confirm "≈ $" (shown, hidden without a price, never altering the amount); the three follow-ups. |
| Config | SDK market data fully disabled. |

The development machine cannot reach CoinGecko. Tests use fakes and fixtures only, and the live check is done on the device.

**Review:** subagent-driven execution. Each task gets its own review, and there is one whole-branch review before the release build.

## 8. On-device acceptance (Moto, 0.4.0 from Play internal)

1. **Home.** It shows a USD total and per-coin USD values with 24h change. Compare them with coingecko.com at the same moment: they must agree within about 1%.
2. **Asset detail (DGB).** Check the unit price and USD value, and that the 24h, 7d and 30d sparklines render.
3. **Send.** Typing an amount shows "≈ $" on the form, and Confirm shows it too. Cancel without sending.
4. **No network.** Turn on airplane mode. The price fields show "Price unavailable" or a stale note, and balances, history and Receive still work. Turn airplane mode off and confirm prices return by themselves within about 3 minutes.
5. **R3-1.** The controller sends about 0.1 DGB from the M0 mule to a test wallet using the local `fund.py`; the seed is never typed on the phone. The pending received row must show "Pending" and no 1969 date.
6. **R3-2.** On a fingerprint prompt, the owner taps "Use password". The password field, and the notice for an opt-in, must appear within about 1 s.
7. **S3-2.** Sign in to wallet B, then sign out. Sign-in must preselect B.
8. **Logs and network.** The log scan is clean. A network check (for example `dumpsys netstats`, or DNS in logcat) shows no Binance or CoinPaprika traffic.

**Acceptance rules from M1-D1 apply:**
- Never print UI node text on seed screens; use the ids-only dump helper.
- Only throwaway values go through adb, and `logcat -c` runs after each one.
- Read a checkbox's state before tapping it.
- STOP-and-relay before every fingerprint prompt.

## 9. Release

- **Version:** 0.4.0, with a new versionCode from the local release lane. targetSdk stays 36.
- **Upload:** `tool/play_upload.py --track internal --status completed`. This is hands-off, because the service account can release to testing tracks.
- **PR:** one PR, `feat/m1d2-prices-usd` → `main`, merged after the final review and green CI.

## 10. Risks and open items

- **CoinGecko public API limits.** The free public tier is limited per IP and its exact limits vary. At one call every 3 minutes, plus occasional chart calls, usage stays far below them. Backoff covers spikes. If limits become a problem, switch `Brand.priceApiBase` to a digiscope.me proxy using a Demo or Pro key; that change is in no milestone yet.
- **Privacy.** Each phone contacts CoinGecko directly, so CoinGecko sees the IP and which three coins are requested, but never addresses or balances. A future proxy would remove this.
- **R3-2 lifecycle heuristic.** The inactive→resumed signal around the system prompt is device-dependent and is verified on the Moto. The fallback is the existing 30 s timeout.
- **CoinGecko outage or regional blocking.** The app degrades to "Price unavailable" and the wallet keeps working.
