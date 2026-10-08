# M1-D2 research: prices / CoinGecko in the SDK (2026-10-07)

Paths are relative to the SDK packages directory.

## Coin IDs
- The CoinGecko ID comes from the `coingecko_id` field in the coin config: DGB is "digibyte", BTC is "bitcoin", LTC is "litecoin".
  - Mapping code: `komodo_defi_types/.../asset_symbol.dart:16` and `id_resolution_strategy.dart:96-148`.
  - If an asset has no ID, `supports()` returns false and the asset is silently skipped.

## SDK market data
`sdk.marketData` lives in `komodo_defi_sdk/lib/src/market_data/market_data_manager.dart` and returns futures only; there are no streams. The app has to poll.
- `fiatPrice(AssetId, {DateTime? priceDate, QuoteCurrency quoteCurrency = Stablecoin.usdt})` → `Decimal`.
- `maybeFiatPrice` and `priceIfKnown` take the same arguments.
- `priceChange24h(AssetId)` → `Decimal?`.
  - The doc comment says the value is a fraction. CoinGecko returns a percent. **Verify the scale before displaying it.**
- `fiatPriceHistory(AssetId, List<DateTime>)` returns daily closes, built from OHLC.

Caching:
- The price cache is cleared every 5 minutes.
- A "last known price" cache survives the clear.

## Provider selection
Config is `MarketDataConfig` (`komodo_cex_market_data/lib/src/bootstrap/market_data_bootstrap.dart:24-75`).
- The `enableX` flags choose which providers are included.
- `DefaultRepositorySelectionStrategy` sorts candidates by a static priority: Komodo 1, Binance 2, CoinPaprika 3, CoinGecko 4. `repositoryPriority` does not affect the order.
- To use CoinGecko only: `MarketDataConfig(enableKomodoPrice:false, enableBinance:false, enableCoinPaprika:false)`.
- The app today sets only `enableKomodoPrice:false` (`app/lib/bootstrap/sdk_bootstrap.dart:29`), so Binance is in effect the primary provider.

## The SDK's CoinGecko provider (`coingecko_cex_provider.dart`, `coingecko_repository.dart`)
- **Current price.** Fetched from `coins/{id}/history`, not `simple/price`.
  - `_formatDate` sends `yyyy-MM-dd`, but CoinGecko `/history` expects `dd-MM-yyyy`. This is a **possible bug** and is unverified.
  - `simple/price` is defined in the provider but never called.
- **24h change.** Uses `coins/markets`.
- **History and sparkline.** Uses `coins/{id}/ohlc`, where the candle size follows the day count.
- **Access and rate limits.**
  - Public host only, with no API-key support and no headers sent.
  - The base URL can be overridden through the constructor.
  - Rate-limit handling is a 5-minute backoff when a request returns 429. There is no client-side throttle.
- **Sparkline repository.** `SparklineRepository.fetchSparkline` exists but is not exposed by `sdk.marketData`.
  - It is hard-coded to 7 days of USDT data.
  - It needs Hive initialised.
  - It prefers Binance.

## Environment
- CoinGecko is blocked from the dev host (`docs/m0-report.md:44`); test on the device or through a proxy.
- Binance is US-restricted.
- The M0 price feed (`dgb-price-feed`) uses CoinPaprika.

## App today
- No price UI.
- Market data is touched only at `sdk_bootstrap.dart:29`.
