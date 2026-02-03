# Upgradeable DeFi Protocol Suite (Foundry)

An end‑to‑end DeFi protocol built with upgradeable Solidity contracts and tested with Foundry. The suite includes:
- Lending markets (deposit, borrow, repay, withdraw, liquidation)
- Liquidity mining (staking rewards)
- Governance + timelock for upgrades and configuration
- On‑chain price oracle

This repo is intended as a readable, audited-style reference implementation. Start with the Quick Start, then scan Contracts at a Glance.

---

## Quick Start

1. Install Foundry
```shell
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Build
```shell
forge build
```

3. Test
```shell
forge test
```

---

## Repo Layout

Top level:
- `src/` protocol contracts
- `test/` unit and integration tests
- `script/` deploy and upgrade scripts
- `lib/` external dependencies (OpenZeppelin, forge-std)
- `foundry.toml` Foundry config
- `requirement.md` project requirements and gaps

Key `src/` subfolders:
- `src/lending/` lending pool, cToken logic, interest rate model
- `src/mining/` liquidity mining
- `src/governance/` governance and timelock
- `src/oracle/` price oracle
- `src/interfaces/` shared interfaces
- `src/libraries/` math, errors, storage helpers

---

## Contracts at a Glance

Lending:
- `src/lending/LendingPoolCore.sol` core pool entrypoint for deposits, borrows, repay, withdraw, liquidation (UUPS)
- `src/lending/LendingToken.sol` receipt token (Compound‑style cToken) with interest accrual (UUPS)
- `src/lending/Comptroller.sol` risk manager for cTokens (UUPS)
- `src/lending/JumpRateModel.sol` utilization‑based interest model (immutable params)
- `src/lending/*Storage.sol` ERC‑7201 storage layout helpers

Liquidity mining:
- `src/mining/LiquidityMining.sol` staking rewards for receipt tokens (UUPS)
- `src/mining/LiquidityMiningStorage.sol` storage layout

Governance:
- `src/governance/GovernanceToken.sol` ERC20Votes token (UUPS)
- `src/governance/ProtocolGovernor.sol` OpenZeppelin Governor (UUPS)
- `src/governance/ProtocolTimelock.sol` timelock controller (UUPS)

Oracle:
- `src/oracle/PriceOracle.sol` price feed aggregation (UUPS)

Libraries:
- `src/libraries/WadRayMath.sol` fixed‑point math (1e18 and 1e27)
- `src/libraries/Errors.sol` shared custom errors

---

## How the Lending Flow Works

Deposit:
- Call `LendingPoolCore.deposit(asset, amount, onBehalfOf)`
- Pool validates reserve status and amount
- Pool calls `LendingToken.mint(payer, onBehalfOf, amount)`
- Underlying is transferred into the token contract and receipt shares are minted

Borrow:
- Call `LendingPoolCore.borrow(asset, amount, onBehalfOf)`
- Pool checks price oracle and health factor
- Pool calls `LendingToken.borrow(borrower, amount)`
- Borrower receives underlying and debt accrues over time

Repay:
- Call `LendingPoolCore.repay(asset, amount, onBehalfOf)`
- Pool calls `LendingToken.repayBorrow(payer, borrower, amount)`
- Debt is reduced immediately

Withdraw:
- Call `LendingPoolCore.withdraw(asset, amount, to)`
- Pool checks health factor after the withdrawal
- Pool calls `LendingToken.redeem(from, to, shares)`

Liquidation:
- Call `LendingPoolCore.liquidate(collateralAsset, debtAsset, borrower, debtToCover)`
- Liquidator repays part of the debt
- Protocol seizes collateral with a bonus

---

## Upgradeability Model

**UUPS basics**
UUPS (Universal Upgradeable Proxy Standard) keeps a thin proxy at a stable address and routes calls to an implementation using `delegatecall`. The proxy stores all state; the implementation provides the logic.

**Why this matters**
- Users never change the address they interact with.
- Upgrades replace logic without wiping balances or positions.
- Authorization lives in the implementation via `_authorizeUpgrade(...)`.

**Call flow**
- User calls proxy address.
- Proxy `delegatecall`s into the current implementation.
- Storage reads and writes happen in the proxy’s storage.

**Upgrade flow in this repo**
1. Governance proposes an upgrade (new implementation address).
2. Proposal passes voting and is queued in the timelock.
3. Timelock executes `upgradeToAndCall` on the proxy.
4. `_authorizeUpgrade(...)` validates the caller (governance/timelock).

**Storage layout rules**
- State is isolated in `*Storage.sol` libraries.
- Slots follow ERC‑7201 to minimize collisions.
- New versions must only append fields to existing storage structs.
- Constructors are disabled; `initialize(...)` is used instead.

**Safety checks**
- Integration tests cover upgrade flows.
- Storage‑preservation tests assert balances and borrows survive upgrades.

---

## Interest Rate Math

**Definitions (WAD = 1e18)**
- `cash`: underlying available in the pool
- `borrows`: total outstanding debt
- `reserves`: protocol‑owned funds
- `utilization`: how much of the pool is borrowed

Utilization formula:
```text
U = borrows / (cash + borrows - reserves)
```

**Borrow rate (JumpRateModel)**
The borrow rate is piecewise with a kink:
```text
if U <= kink:
  borrowRate = baseRate + U * multiplier
else:
  borrowRate = baseRate + kink * multiplier + (U - kink) * jumpMultiplier
```
All rates are per‑second in the model; per‑year helpers are also exposed.

**Supply rate**
Depositors earn the borrow rate scaled by utilization and reduced by the reserve factor:
```text
supplyRate = borrowRate * U * (1 - reserveFactor)
```

**Accrual in `LendingToken`**
On state‑changing actions, `accrueInterest()` updates global state:
- `interestAccumulated = borrowRatePerSecond * timeElapsed * totalBorrows`
- `totalBorrows` increases by `interestAccumulated`
- `totalReserves` increases by `interestAccumulated * reserveFactor`
- `borrowIndex` increases by the same simple interest factor

Per‑user debt is derived from the snapshot:
```text
borrowBalance = principal * borrowIndex / userInterestIndex
```

**Exchange rate for receipt tokens**
The receipt token exchange rate grows as interest accrues:
```text
exchangeRate = (cash + borrows - reserves) / totalSupply
```
Depositors redeem more underlying when the exchange rate increases.

---

## Oracle (Price Feeds)

**What it is**
`PriceOracle` is a lightweight aggregator that maps each asset to a Chainlink‑style feed and returns a normalized USD price with 8 decimals. It’s upgradeable (UUPS) and owner‑managed.

**How prices are fetched**
- The oracle stores `assetSources[asset] -> feed`.
- `getAssetPrice(asset)` reads `latestRoundData()` from the feed.
- Prices are normalized to 8 decimals regardless of the feed’s native decimals.

**Safety checks**
- `answer` must be positive (`InvalidPrice` if not).
- `updatedAt` must be recent (`StalePrice` if older than `MAX_STALENESS`, set to 1 hour).
- If an asset has no feed, the oracle tries a `fallbackOracle`; if none exists, it reverts.

**Admin controls**
- `setAssetSource(asset, feed)` and `setAssetSources(...)` are owner‑only.
- Assets are tracked in `assetsList` for discoverability.
- `setFallbackOracle(...)` sets an optional backup oracle.

**Where it’s used**
- `LendingPoolCore` and `Comptroller` use the oracle to value collateral and debt, calculate health factors, and determine liquidation eligibility.
- Integration tests use `MockPriceFeed`, with `refresh()` calls to avoid stale‑price errors.

---

## Tests

Tests are located in `test/`:
- `test/unit/` contract‑level tests
- `test/integration/` end‑to‑end protocol flows
- `test/mocks/` mock ERC20s and price feeds

Run all tests:
```shell
forge test
```

Run a single test file:
```shell
forge test --match-path test/integration/FullProtocol.t.sol
```

---

## Scripts

Deployment:
- `script/DeployProtocol.s.sol`

Upgrade flow example:
- `script/UpgradeProtocol.s.sol`

Run a script:
```shell
forge script script/DeployProtocol.s.sol:DeployProtocolScript --rpc-url <RPC> --private-key <KEY>
```

---

## Key Parameters (Glossary)

- `LTV`: loan‑to‑value ratio (borrow limit vs collateral)
- `Liquidation threshold`: debt level at which liquidation is allowed
- `Health factor`: safety ratio; below 1 is liquidatable
- `Reserve factor`: portion of interest retained by the protocol
- `Utilization`: borrows / (cash + borrows − reserves)

---

## Known Limitations

From `requirement.md`, not yet implemented:
- Multiple reward tokens in liquidity mining
- Emergency multisig override for governance
- Explicit rollback mechanism for upgrades

---

## Walkthrough Example (from `test/integration/FullProtocol.t.sol`)

Assumptions used in the integration suite:
- USDC price = $1
- WETH price = $2,000
- USDC: LTV 75%, liquidation threshold 80%, liquidation bonus 1.05
- WETH: LTV 80%, liquidation threshold 85%, liquidation bonus 1.05
- Close factor = 50%

### `test_FullLendingLifecycle`

Goal: show a full deposit → borrow → interest accrual → repay → withdraw loop.

1. Alice supplies liquidity by minting 10,000 dUSDC (`dUSDC.mint(10000e18)`), which transfers 10,000 USDC into the pool and mints 10,000 receipt tokens.
2. Bob supplies 5 WETH as collateral, enters the WETH market, and enables borrowing.
3. Bob borrows 5,000 USDC against his collateral. His wallet now holds `INITIAL_BALANCE + 5000e18` USDC.
4. The test fast‑forwards 365 days, refreshes oracle feeds, and accrues interest on dUSDC. Bob’s debt increases above 5,000 USDC.
5. Bob repays his full debt with `repayBorrow(type(uint256).max)` and his borrow balance goes to zero.
6. Alice redeems all dUSDC. Because interest accrued, her withdrawal is greater than 10,000 USDC.

### `test_LiquidityMiningRewards`

Goal: show reward distribution is proportional to stake and time.

1. The deployer mints 30,000 GOV to the USDC mining contract and starts a reward period via `notifyRewardAmount(30000e18)` (≈1,000 GOV/day for 30 days).
2. Alice mints 10,000 dUSDC and stakes all of it.
3. Bob mints 10,000 dUSDC and stakes all of it at the same time.
4. The test fast‑forwards 15 days.
5. Alice and Bob claim rewards. Since stake amount and timing are identical, their GOV balances are approximately equal and non‑zero.

### `test_GovernanceUpgradeFlow`

Goal: show a full governance‑controlled upgrade through the timelock.

1. The deployer mints 1,000,000 GOV each to Alice, Bob, and Carol. Each delegates to themselves to activate voting power.
2. A new `PriceOracle` implementation is deployed and encoded into a proposal call:
   `UUPSUpgradeable.upgradeToAndCall(newImpl, "")`.
3. Ownership of the current price oracle is transferred to the timelock so the upgrade can be executed.
4. Alice proposes the upgrade. The test advances to the voting start time, then all three vote “for”.
5. After the voting period, the proposal is queued in the timelock.
6. After the timelock delay, the proposal is executed and `priceOracle.version()` increments by 1.

---
