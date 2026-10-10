# DigiByte DEX roadmap — live status

**Rewritten in place, not appended.** This is the current picture; the per-milestone
narrative is in `2026-09-29-session-handoff.md`, and the authoritative plan of record is
§10 of `specs/2026-09-27-digibyte-wallet-design.md`.

Last updated: 2026-10-10, after M1-D3 merged (PR #8).

## Where we are

| Milestone | Status |
| --- | --- |
| **M0 — Proving the stack** | **Done** (2026-09-30). Mainnet DGB↔LTC swap on the DigiByte network ID, fee received by the fork's address. Four repos published under JohnnyLawDGB. |
| **M1 — Wallet** | **In progress.** See the lane table below. |
| **M2 — Swaps** | Not started. The actual DEX: swap screen, quotes and fees, progress, history and recovery. Needs mainnet seed nodes and market makers for DGB/BTC and DGB/LTC. |
| **M3 — Production** | Not started. Remaining pairs, monitoring, external security review, store listings, legacy sunset. |

## M1 lanes

| Lane | Status | Released as |
| --- | --- | --- |
| M1-A — KDF fork, fee key rotation | **Parked** on the owner's offline fee key | — |
| M1-B — App foundation, CI | Done | 0.1.0 |
| M1-C — Wallet core (onboarding, unlock, biometrics, portfolio) | Done, PR merged | 0.2.0 / 0.2.1 |
| M1-D1 — Move money (send, receive, history, QR, links) | Done, PR #5 | 0.3.0 / 0.3.1 |
| M1-D2 — Prices and USD | Done, PR #6 | 0.4.0 |
| 0.4.1 — large-font row, 2 min biometric backstop, DGB electrum order | Done, PR #7 | 0.4.1 |
| **M1-D3 — Settings** | **Done, PR #8** (merge 72262b5), accepted on device 13/14 | **0.5.0** |
| M1-D4 — Fiat currency | **Next candidate.** Not scoped | — |
| M1-D5 — Log export | **Next candidate.** Not scoped | — |
| M1 exit — iOS pass on the Mac, TestFlight | Pending the owner's Mac | — |

**M1 exit criterion:** internal TestFlight and Play builds, usable on mainnet as a wallet.
Play internal is live; TestFlight and the iOS device pass are outstanding.

## The two candidate lanes

Both were split out of M1-D3 deliberately, because each is a subsystem rather than a control.

**Fiat currency.** The price layer is USD-only (`UsdFormat`, CoinGecko `usd`). Multi-fiat
reaches the price repository, its cache, the portfolio total, the sparklines and Send's
"≈ $". It is not a dropdown.

**Log export.** There is nothing to export yet — about 55 ad-hoc `debugPrint` sites and no
buffer. Needs capture plus redaction. Redaction deserves real care: this project has already
found seed words exposed as `content-desc` in `uiautomator` dumps and an Equatable state
printing them through `toString`.

*Recommendation: log export first*, because it decides what can safely be collected from
testers. Fiat is the more visible product gap, so this is a judgement call, not an obvious one.

## Carried debt, none blocking

From 0.5.0:
- Asset deactivation generation check through `activate`/`activateListed` (a stale `active`
  marker; the row is filtered out and electrum genuinely disconnects, so it is cosmetic).
- A known-failed asset cannot be switched off, because the balance check fails closed. A safe
  escape needs SDK-private `hydratedPubkeys` and its own spec.
- `PasswordGate.tryBiometrics` reports a generic `unknown` where `wrongPassword` with
  `biometricsEnabled: true` would be clearer.
- A wallet with a **pending backup** cannot reach Settings at all, so it cannot be deleted
  in-app until backed up. Behaviour, not a defect — but surprising.

From 0.4.1 and earlier:
- The biometric prompt stays on screen after the backstop fires (flutter_secure_storage
  cannot cancel it).
- `Confirming n/7` does not advance live on an open asset screen.

## Standing blockers and owner inputs

| Item | Needed for |
| --- | --- |
| Offline fee key | M1-A (rotation), and it gates the DEX fee path |
| Approved mainnet seed node list | M2 |
| Market makers for DGB/BTC and DGB/LTC | M2 |
| A Mac session | iOS pass, TestFlight, M1 exit |

## Beyond M1

**DigiDollar as a swap peg.** The owner confirmed (2026-10-10) that DigiDollar is an asset on
the DigiByte blockchain and is **protocol level** in `digibyted` — not a DigiAssets token and
not a separate chain. That means KDF must understand its outputs and mint/redeem transactions
before it can swap them: real work in the KDF fork, on top of what M1-A already carries.
**Scope it as a milestone, not a ticket**, and establish first whether it is live on mainnet or
still in the 9.26.x release candidates, and which digibyted version carries it.
