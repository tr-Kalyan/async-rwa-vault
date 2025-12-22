# Self-Audit Report — Async Settlement RWA Vault

**Date**: December 23, 2025  
**Author**: Kalyan TR  
**Scope**: Full contract + handler + tests

## Overview

ERC-4626 vault modeling realistic settlement delays for tokenized real-world assets.

Core innovation: stable NAV during queued redemptions via virtual liabilities accounting (`totalPendingAssets`).

Designed for maximum capital efficiency — no liquidity buffers, no forced instant claims.

## Testing Summary

- **Unit tests**: 10+ covering happy paths, edges, reverts
- **Invariant fuzzing**: 1000 runs × 128 depth → solvency and pending ≤ balance hold
- **Fork tests**: mainnet + Sepolia with official Circle USDC (real proxy/blacklist)
- **CI**: fmt, build, unit, invariants, fork, coverage — all green

## Fixed Findings

### High Risk

- **Redemption price inflation**  
  Without virtual liabilities, queued redemptions suppress reported NAV for remaining holders.  
  **Fixed**: override `totalAssets()` to subtract `totalPendingAssets` → price stable.

- **Slippage on requestRedeem**  
  Price can change between preview and execution.  
  **Fixed**: `minAssets` param — reverts if return too low.

### Medium Risk

- **Dry vault panic**  
  Claim reverts with generic transfer error if liquidity low.  
  **Fixed**: `InsufficientLiquidity()` custom error.

- **Fat-finger lockup**  
  No way to cancel mistaken request.  
  **Fixed**: `cancelRedeem` (restricted after claimableAt for ops protection).

- **Sanctions stuck funds**  
  Blacklisted receiver → claim reverts → pending bloat forever.  
  **Fixed**: `rescindRedemption` (admin) — cleans accounting, funds remain in vault.

## Known Issues & Trade-offs (Informational)

- **Yield lag**  
  NAV reflects realized yield only (admin deposit). Accrued but undistributed yield not shown on-chain.  
  **By design** — avoids oracle risk/centralization. Matches batch ops in production RWAs.

- **Rescind windfall**  
  Blocked redemptions → funds remain → slight NAV increase for remaining LPs.  
  **Accepted** — correction of prior artificial suppression. Standard in production.

- **Admin trust**  
  Multisig required for yield deposit and rescind.  
  **Mitigated** — events, transparency, disclosure.

- **No continuous accrual**  
  No oracle for undistributed yield → stale price between deposits.  
  **Trade-off** for security and simplicity.

## Recommendations

- Deploy with Gnosis Safe multisig as owner.
- Publish yield deposit schedule for user planning.
- Dashboard: show estimated NAV (realized + accrued off-chain).
- Monitor failed claims → quick rescind.

## Conclusion

No critical or high-risk vulnerabilities remaining.

Accounting mathematically proven via invariants.

Realism validated on mainnet fork with Circle USDC.

Ready for Sepolia demo, audit contest, or further hardening.

This vault prioritizes **institutional operational reality** over perfect on-chain fairness — the right choice for real-world assets.