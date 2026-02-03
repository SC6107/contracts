# Frontend Local Setup (Anvil + FullSetupLocal)

This guide assumes you’ve already run:

```bash
# Terminal 1
anvil

# Terminal 2
script/deploy_local.sh
```

`deploy_local.sh` runs `FullSetupLocal` (Comptroller flow), which deploys mocks, markets, governance, and mining.

---

## What Gets Deployed

`FullSetupLocal` deploys:
- `MockERC20` tokens: **USDC** and **WETH**
- `MockPriceFeed` for each token
- `PriceOracle` (proxy)
- `Comptroller` (proxy)
- `JumpRateModel`
- `LendingToken` markets: **dUSDC** and **dWETH**
- `GovernanceToken` (proxy)
- `ProtocolTimelock` (proxy)
- `ProtocolGovernor` (proxy)
- `LiquidityMining` for **dUSDC** and **dWETH** (proxies)

It also:
- Registers feeds in the oracle
- Lists dUSDC/dWETH in the comptroller
- Mints test balances to common Anvil accounts
- Grants governor proposer/canceller roles on the timelock

You interact **directly with `LendingToken` markets** (Comptroller flow).

---

## Find Deployed Addresses

Use the helper script (recommended):

```bash
script/quick_extract_local.sh
```

It prints:
- `COMPTROLLER`, `PRICE_ORACLE`
- `GOVERNANCE_TOKEN`, `PROTOCOL_TIMELOCK`, `PROTOCOL_GOVERNOR`
- `USDC`, `WETH`, `DUSDC`, `DWETH`
- `USDC_FEED`, `WETH_FEED`
- `USDC_MINING`, `WETH_MINING`
- `RPC_URL`

If needed, you can override the broadcast file:

```bash
RUN_JSON=path/to/run-latest.json script/quick_extract_local.sh
```

---

## Frontend Connection Settings

- **RPC URL:** `http://127.0.0.1:8545`
- **Chain ID:** `31337`
- **Block Explorer:** none (local)

---

## Test Accounts (Recommended)

`deploy_local.sh` runs `FullSetupLocal`, which **mints mock USDC/WETH** to these Anvil accounts by default:

- Account 0: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- Account 1: `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`
- Account 2: `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC`
- Account 3: `0x90F79bf6EB2c4f870365E785982E1f101E93b906`
- Account 4: `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65`

Use these for frontend testing (they already have token balances).

Private keys (only for Accounts 0–4, which are pre‑minted by `FullSetupLocal`):

```
(0) 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
(1) 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
(2) 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
(3) 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
(4) 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
```

Mnemonic:

```
test test test test test test test test test test test junk
```

---

## Common Frontend Calls (Comptroller Flow)

### Supply

1. Approve underlying to dToken
2. Call `dToken.mint(amount)`

### Enter Market (required before borrowing)

```solidity
comptroller.enterMarkets([dWETH])
```

### Borrow

```solidity
dUSDC.borrow(amount)
```

### Repay

```solidity
usdc.approve(dUSDC, amount)
dUSDC.repayBorrow(amount)
```

### Redeem

```solidity
dUSDC.redeem(shares)
```

---

## Oracle Notes (Mock Feeds)

Prices are mocked and can become **stale** after 1 hour. If you warp time in tests, refresh feeds:

```solidity
MockPriceFeed.refresh()
```

Use `PriceOracle.getAssetSource(asset)` to find each feed.

---

## Example Lifecycle (CLI)

If you want a full end‑to‑end repro of `test_FullLendingLifecycle`:

```bash
script/repro_full_lending_lifecycle.sh
```

This script resolves addresses automatically and runs the lifecycle against your local deployment.

---

## Troubleshooting

- **`PriceFeedNotFound`**: make sure the oracle is configured with `setAssetSource` (done in `FullSetupLocal`).
- **`MarketNotListed`**: ensure `Comptroller.supportMarket` was called (done in `FullSetupLocal`).
- **`StalePrice`**: call `refresh()` on the mock feeds.
- **Insufficient balance**: confirm your account is funded with USDC/WETH and ETH for gas.
