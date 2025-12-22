# Async Settlement RWA Vault

An ERC-4626 vault that enforces **real T+1/T+2 settlement delays** for tokenized real-world assets (Treasuries, private credit) while maintaining maximum capital efficiency and stable NAV.

No forced liquidity buffers. No artificial instant redemptions. Just realistic operations — on-chain.

### Why This Exists

Most RWA vaults in 2025 are either:
- Instant (sacrifice yield for liquidity)
- Fully permissioned/off-chain (no composability)

This vault models the **real operational friction** of institutional assets:
- Redemption requests lock price immediately
- 48-hour configurable delay before claim
- Admin deposits realized yield in batches

Async redemption flow with RWA-specific enhancements (stable NAV, slippage, compliance rescind).

### Key Features

- **Stable NAV accounting** — override `totalAssets()` to subtract pending liabilities → no redemption-induced price spikes
- **_decimalsOffset = 12** — maximum inflation attack protection for 6-decimal USDC
- **Slippage protection** — `minAssets` param in `requestRedeem`
- **cancelRedeem** — fat-finger recovery before claimable (with late-cancel block for ops protection)
- **rescindRedemption** — admin compliance override (sanctions/blocked claims)
- **InsufficientLiquidity** error — clear UX when vault is dry
- **depositYield** — admin injects off-chain realized returns

### Testing & Proof

- **Unit tests** — happy paths, edges, reverts
- **Invariant fuzzing** — 1000 runs × 128 depth → solvency and accounting invariants hold
- **Fork tests** — mainnet + Sepolia with **official Circle USDC** (real proxy, blacklist logic)
- **CI** — fmt, build, unit, invariants, fork, gas snapshot, coverage

### Assumptions & Known Trade-offs

- Yield is **realized only** — admin deposits net returns (matches batch ops)
- Pending redeemers forfeit accrual during delay — incentive to stay
- Admin is trusted multisig for yield deposit and rescind
- Compliance events handled by `rescindRedemption` (funds remain in vault)
- No on-chain continuous accrual oracle (by design — avoids centralization)

### Running Locally

```bash
forge test -vvv                    # unit + invariants (local Anvil)
forge test --fork-url $MAINNET_RPC # fork tests on mainnet
```

## 👨‍💻 Author

**Kalyan TR**

> Former regulated-domain QA (Finance + Healthcare) → transitioning to Web3 Security
Active on CodeHawks & Code4rena


[![GitHub](https://img.shields.io/badge/GitHub-tr--Kalyan-black?style=for-the-badge&logo=github)](https://github.com/tr-Kalyan)

---

## 📄 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.