# M1-D SDK research: send, fees, validation, history, URIs (2026-10-04)

Path abbreviations:
- SDK = `~/digibyte-dex/digibyte-wallet/third_party/komodo-defi-sdk-flutter/packages`
- KDF = `~/digibyte-dex/kdf/mm2src`

The m1c-sdk-api.md §11 withdraw citations were re-verified.

## 1. Withdraw (`sdk.withdrawals`)

The flow has two steps.
- **Preview.** `Future<WithdrawalPreview> previewWithdrawal(WithdrawParameters)` (komodo_defi_sdk/lib/src/withdrawals/withdrawal_manager.dart:1108).
  - Runs KDF `task::withdraw::init`, which builds and signs the tx but does not broadcast it.
  - Returns `txHex`, `txHash`, `from`, `to`, `balanceChanges`, `fee` and `timestamp`.
- **Execute.** `Stream<WithdrawalProgress> executeWithdrawal(WithdrawalPreview, String assetId)` (:1248).
  - Broadcasts the pre-signed hex via `sendRawTransaction` (:1369).
  - The txid is in `progress.withdrawalResult.txHash` when the status is complete.
- The deprecated one-shot `withdraw(params)` is at :3101.

Parameters and errors:
- **Amount.** `WithdrawParameters.amount` is a `Decimal?` (komodo_defi_types/lib/src/withdrawal/withdrawal_types.dart:396-470).
- **Send-all.** `isMax: true` with `amount: null`; exactly one of the two may be set, and `toJson` sends `'max': true`.
- **Preview errors.** It throws `SdkError` (:1199-1203): insufficientFunds, amountTooLow (with dust threshold), invalidAddress, invalidFee.
- **Execute errors.** Delivered as a stream error carrying `SdkError` (:1576-1578).
- **Cancel.** `cancelWithdrawal(taskId)` exists (:253), but the preview doesn't expose the taskId.

Concurrency:
- KDF holds a global `UTXO_LOCK` while it builds a withdraw (kdf/coins/utxo/utxo_withdraw.rs:171).
- Inputs are not reserved between preview and execute. Two previews made before broadcast can pick the same UTXOs, and the second broadcast then fails as a double-spend.
- So the app runs one send at a time per wallet.

## 2. Fees

- The SDK does no UTXO fee estimation.
  - `_feeEstimationEnabled = false` (fees/fee_manager.dart:54; withdrawal_manager.dart:157).
  - `feePriority` is ignored.
- A custom fee goes in `WithdrawParameters.fee`:
  - `FeeInfo.utxoFixed` (per kB) or `utxoPerKbyte` (utxo_withdraw.rs:182-196);
  - the math is `rate * tx_size / 1000` (utxo.rs:316-319).
- Default fee from the coin config (utxo_conf_builder.rs:381-389): `txfee == 0` means a dynamic electrum `estimatefee`; any other value is a fixed per-kB fee.

| Ticker | txfee | dust | Notes |
|---|---|---|---|
| DGB | 10000000 (0.1 DGB/kB, fixed) | 5460 | required_confirmations 7, segwit true, hrp dgb |
| BTC | 0 (dynamic, ECONOMICAL) | unset (KDF default) | segwit true, hrp bc |
| LTC | 1000 sat/kB (fixed) | 5460 | segwit true, hrp ltc |

- No `force_min_relay_fee` (utxo_common.rs:891-912).
- The preview `fee.totalFee` is the real fee. A typical 1-in/2-out P2PKH tx comes to about 0.0226 DGB.
- Never go below 0.1 DGB/kB for DGB.
- BTC `estimatefee` can fail on transport. Treat that as retryable.

## 3. Address validation

- `sdk.addresses.validateAddress({asset, address}) → AddressValidation{isValid, address, asset, invalidReason}` (komodo_defi_sdk/lib/src/addresses/address_operations.dart:12-36).
  - It never throws. An RPC failure gives `isValid:false` and the reason "Validation failed: …".
  - It wraps KDF `validateaddress` (lp_coins.rs:5468; utxo_common.rs:3617-3643).
- It does not reject bech32 for the legacy tickers. The parser tries legacy, then segwit, then cashaddr (utxo_common.rs:375-394), and segwit is accepted when `conf.segwit && hrp == conf.bech32_hrp` (:3631-3634, withdraw check :5258-5270).
  - All three configs have `segwit: true`, so `dgb1…`, `bc1…` and `ltc1…` probably validate and can be sent to.
  - **This is inferred from source. Verify it live.**
- Cross-chain addresses are rejected by prefix or hrp.

## 4. Transaction history (`sdk.transactions`)

Methods (transaction_history_manager.dart):
- `getTransactionHistory(Asset, {pagination}) → TransactionPage{transactions,total,currentPage,totalPages,nextPageId}` (:277)
- `watchTransactions(Asset) → Stream<Transaction>` (:544)
- `getTransactionsStreamed` (:391)
- **`watchTransactionHistoryMerged(Asset, {transform}) → Stream<List<Transaction>>`** (:508). This is the one for the UI: it emits stored and fetched history, then live updates.
- `syncTransactionHistory` (:573), `clearTransactionHistory` (:715)

Pagination: UTXO coins use `V2TransactionStrategy` with `PagePagination` or `TransactionBasedPagination(fromId, itemCount)` over `my_tx_history` v2 (transaction_history_strategies.dart:46-108).

`Transaction` fields (komodo_defi_types/lib/src/transactions/transaction.dart):
- `id`, `internalId`, `assetId`, `balanceChanges{netChange, receivedByMe, spentByMe, totalAmount}`, `timestamp`, `confirmations`, `blockHeight`, `from`/`to` (List<String>), `txHash`, `fee` (FeeInfo?), `memo`
- Incoming means `netChange > 0`. A self-send has `spentByMe>0 && receivedByMe>0` and `netChange = -fee`.

Activation and wallet type:
- History needs `tx_history: true` at activation. The app's UTXO activation already sets it.
- HD wallets read account 0 across all addresses (`HdHistoryTarget.accountId(0)`). Iguana wallets use `IguanaHistoryTarget`.
- History is persisted encrypted.
- A newly created, non-imported wallet's first page 1 returns empty without a KDF call (:300-330).

## 5. URIs

There is no BIP21 parsing in the SDK or the app. The app parses `digibyte:ADDR?amount=&label=&message=` itself, then runs `validateAddress` and `Decimal.parse`.

## 6. Balances

- `BalanceInfo{total, spendable, unspendable}` (balance_manager.dart:34-71, 550-590).
- For UTXO coins, spendable = balance, which likely includes unconfirmed (utxo_common.rs:253-262). **Verify this live.**
- HD: `total` is the sum over all addresses.

## 7. Gotchas

**HD requires `from`.**
- KDF returns `FromAddressNotFound` without it (utxo_common.rs:3555-3563), and the SDK never fills it in.
- For HD wallets the app passes `WithdrawalSource.hdWalletId(accountId: 0, addressId: n, chain: Bip44Chain.external)` or `hdDerivationPath(...)` (types :489-520).
- Iguana wallets must not pass `from` (utxo_common.rs:3572).

**Spending is single-address.**
- Inputs come only from the `from` address (utxo_withdraw.rs:171-176), and max uses only that address's UTXOs (DeductFromOutput).
- A balance spread across HD addresses cannot go out in one tx. Use per-address balances from `sdk.pubkeys`.

**Change** goes back to the same `from` address (utxo_common.rs:~740-760).

**Dust.**
- Any output below dust fails with `OutputValueLessThanDust`, which becomes amountTooLow (utxo_common.rs:688-701).
- Change below dust goes to the fee (:646).
- Max needs the output to exceed fee + dust (:664-680).

**Precision.** At most 8 decimals; `sat_from_big_decimal` fails beyond that. Validate in the UI.

**After a send**, refresh the balance with `forceRefresh: true`. The pubkeys cache has no TTL.
