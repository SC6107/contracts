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
- `docs/` architecture artifacts
- `lib/` external dependencies (OpenZeppelin, forge-std)
- `foundry.toml` Foundry config

Key `src/` subfolders:
- `src/lending/` lending markets (cToken logic, comptroller, interest rate model)
- `src/mining/` liquidity mining
- `src/governance/` governance and timelock
- `src/oracle/` price oracle
- `src/interfaces/` shared interfaces
- `src/libraries/` math, errors, storage helpers

---

## Contracts at a Glance

Lending:
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
- `src/oracle/PriceOracleStorage.sol` ERC‑7201 storage layout

Libraries:
- `src/libraries/WadRayMath.sol` fixed‑point math (1e18 and 1e27)
- `src/libraries/PercentageMath.sol` percentage calculations (basis points)
- `src/libraries/Errors.sol` shared custom errors
- `src/libraries/DataTypes.sol` shared data structures (ReserveData, etc.)
- `src/libraries/ReentrancyGuardStorage.sol` reentrancy guard with ERC‑7201 storage

Interfaces:
- `src/interfaces/IComptroller.sol` Comptroller interface
- `src/interfaces/ILendingToken.sol` LendingToken (cToken) interface
- `src/interfaces/IInterestRateModel.sol` interest rate model interface
- `src/interfaces/ILiquidityMining.sol` liquidity mining interface
- `src/interfaces/IPriceOracle.sol` price oracle interface

---

## How the Lending Flow Works (Comptroller Flow)

Supply:
- Approve underlying to the dToken
- Call `dToken.mint(amount)` to receive receipt shares

Borrow:
- Call `comptroller.enterMarkets([dToken])` to enable collateral
- Call `dToken.borrow(amount)`
- Borrower receives underlying and debt accrues over time

Repay:
- Approve underlying to the dToken
- Call `dToken.repayBorrow(amount)`
- Debt is reduced immediately

Withdraw:
- Call `dToken.redeem(shares)` to redeem underlying

Liquidation:
- Call `dTokenBorrowed.liquidateBorrow(borrower, repayAmount, dTokenCollateral)`
- Comptroller validates liquidation eligibility and close factor

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
4. `_authorizeUpgrade(...)` validates the caller (owner/governance/admin role, depending on contract).

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

## Liquidity Mining Math

The liquidity mining module uses a Synthetix‑style reward accounting model that is O(1) per user action.

**Key state (scaled by 1e18)**
- `rewardRate`: tokens distributed per second
- `rewardPerTokenStored`: cumulative rewards per staked token
- `userRewardPerTokenPaid[user]`: snapshot of `rewardPerTokenStored` for each user
- `rewards[user]`: accrued rewards not yet claimed
- `totalSupply`: total staked dTokens

**Reward per token**
```text
rewardPerToken =
  rewardPerTokenStored
  + (lastTimeRewardApplicable - lastUpdateTime) * rewardRate * 1e18 / totalSupply
```
If `totalSupply == 0`, the function returns the stored value unchanged.

**User earnings**
```text
earned(user) =
  balance[user] * (rewardPerToken - userRewardPerTokenPaid[user]) / 1e18
  + rewards[user]
```

**Time window**
- `lastTimeRewardApplicable = min(block.timestamp, periodFinish)`
- This caps rewards at the end of the distribution period.

**Starting or extending a reward period**
When `notifyRewardAmount(reward)` is called:
```text
if now >= periodFinish:
  rewardRate = reward / rewardsDuration
else:
  leftover = (periodFinish - now) * rewardRate
  rewardRate = (reward + leftover) / rewardsDuration
```
This ensures smooth continuation if a new reward is added before the old period ends.

**Why the accounting stays accurate**
- Every stake/withdraw/claim runs `updateReward(user)`:
  - Advances `rewardPerTokenStored`
  - Updates `rewards[user]` and `userRewardPerTokenPaid[user]`
- Rewards are proportional to stake size and the time staked.

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
- If an asset has no feed, the oracle tries a `fallbackOracle`; if none exists, it reverts.

**Admin controls**
- `setAssetSource(asset, feed)` and `setAssetSources(...)` are owner‑only.
- Assets are tracked in `assetsList` for discoverability.
- `setFallbackOracle(...)` sets an optional backup oracle.

**Where it's used**
- `Comptroller` uses the oracle to value collateral and debt, calculate liquidity/shortfall, and determine liquidation eligibility.
- Integration tests use `MockPriceFeed` for fixed prices.

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

### Deployment

| Script | Description |
|--------|-------------|
| `script/DeployProtocol.s.sol` | Deploys core protocol proxies and governance contracts (no markets/mocks) |
| `script/FullSetupLocal.s.sol` | Full setup with mocks + oracle + comptroller + dUSDC/dWETH + governance + mining, then seeds initial balances/positions |
| `script/deploy_local.sh` | Local orchestrator for `DeployProtocol` / `FullSetupLocal` (Anvil must already be running) |
| `script/deploy_sepolia.sh` | Sepolia orchestrator with retries, optional verify, optional governance setup and governance upgrade phases |

### Upgrades

| Script | Description |
|--------|-------------|
| `script/UpgradeProtocol.s.sol` | Upgrade script for UUPS proxies |
| `script/test_upgrade_local.sh` | Local upgrade test helper |
| `script/upgrade_network.sh` | Direct UUPS upgrade by kind (`price_oracle`, `comptroller`, `lending_token`, `governance_token`, `liquidity_mining`) |

### Governance Flow Scripts

| Script | Description |
|--------|-------------|
| `script/prepare_governance_voters.s.sol` | Mints/delegates GOV for Alice/Bob/Carol and funds gas for voting wallets |
| `script/prepare_governance_voters.sh` | Resolves addresses from broadcast and runs voter preparation |
| `script/repro_governance_upgrade_flow.s.sol` | Phase-based governance upgrade logic (`prepare`, `propose`, `vote`, `queue`, `execute`) |
| `script/repro_governance_upgrade_flow.sh` | Wrapper for scripted governance phases (supports local `all` mode with time auto-advance) |
| `script/repro_governance_upgrade_flow_with_sleep.sh` | Real-time governance flow runner for public networks with polling/retry/sleeps |

### Reproduction / Demo Scripts

| Script | Description |
|--------|-------------|
| `script/repro_full_lending_lifecycle.s.sol` | Reproduces the full lending lifecycle: supply → borrow → accrue → repay → withdraw |
| `script/repro_full_lending_lifecycle.sh` | Shell wrapper that extracts addresses and runs the lending lifecycle script |
| `script/repro_liquidity_mining_rewards.s.sol` | Reproduces liquidity mining rewards: stake → time passes → claim |
| `script/repro_liquidity_mining_rewards.sh` | Shell wrapper that extracts addresses and runs the mining rewards script |

### Utilities

| Script | Description |
|--------|-------------|
| `script/quick_extract_local.sh` | Extracts deployed contract addresses from `broadcast/FullSetupLocal.s.sol/*/run-latest.json`. Outputs environment variables for all proxies, underlying tokens, and feeds |
| `script/quick_extract_governance.sh` | Extracts governance-related addresses (PriceOracle/GOV/Timelock/Governor) from `FullSetupLocal` broadcast JSON |

### Usage Examples

Run a script:
```shell
forge script script/DeployProtocol.s.sol:DeployProtocol \
  --rpc-url <RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast
```

Run an upgrade (example: PriceOracle):
```shell
forge script script/UpgradeProtocol.s.sol:UpgradeProtocol \
  --sig "upgradePriceOracle(address)" <PROXY_ADDRESS> \
  --rpc-url <RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast
```

Network upgrade (direct UUPS call):
```shell
RPC_URL=<RPC_URL> \
PRIVATE_KEY=<PRIVATE_KEY> \
PROXY_ADDRESS=<PROXY_ADDRESS> \
UPGRADE_KIND=price_oracle \
CONFIRM_NETWORK=YES \
script/upgrade_network.sh
```
Notes:
- This only works if the proxy owner is the key you provide.
- In production, upgrades should go through governance + timelock.

Local full setup (Anvil):
```shell
# Terminal 1
anvil

# Terminal 2
FULL_SETUP=1 \
PREPARE_GOVERNANCE_VOTERS=1 \
script/deploy_local.sh
```
Notes:
- `script/deploy_local.sh` does not start Anvil; start it manually first.

Sepolia deployment/full setup:
```shell
SEPOLIA_RPC_URL=<SEPOLIA_RPC_URL> \
PRIVATE_KEY=<PRIVATE_KEY> \
ETHERSCAN_API_KEY=<ETHERSCAN_API_KEY> \
VERIFY=1 \
FULL_SETUP=1 \
CONFIRM_NETWORK=YES \
script/deploy_sepolia.sh
```

Prepare governance voters from latest `FullSetupLocal` broadcast:
```shell
RPC_URL=<RPC_URL> script/prepare_governance_voters.sh
```

Run full governance upgrade flow on local Anvil (all phases):
```shell
RPC_URL=<RPC_URL> \
GOVERNANCE_PHASE=all \
AUTO_ADVANCE_TIME=1 \
script/repro_governance_upgrade_flow.sh
```

Run governance flow on Sepolia one phase at a time:
```shell
RPC_URL=<SEPOLIA_RPC_URL> GOVERNANCE_PHASE=prepare script/repro_governance_upgrade_flow.sh
RPC_URL=<SEPOLIA_RPC_URL> GOVERNANCE_PHASE=propose script/repro_governance_upgrade_flow.sh
RPC_URL=<SEPOLIA_RPC_URL> GOVERNANCE_PHASE=vote script/repro_governance_upgrade_flow.sh
RPC_URL=<SEPOLIA_RPC_URL> GOVERNANCE_PHASE=queue script/repro_governance_upgrade_flow.sh
RPC_URL=<SEPOLIA_RPC_URL> GOVERNANCE_PHASE=execute script/repro_governance_upgrade_flow.sh
```

Local upgrade test (assumes deployed):
```shell
script/test_upgrade_local.sh
```

Local upgrade test with explicit proxy:
```shell
PRICE_ORACLE_PROXY=<proxy> script/test_upgrade_local.sh
```

---

## Key Parameters (Glossary)

- `LTV`: loan‑to‑value ratio (borrow limit vs collateral)
- `Liquidation threshold`: in this setup it equals the collateral factor (Compound‑style)
- `Health factor`: safety ratio; below 1 is liquidatable
- `Reserve factor`: portion of interest retained by the protocol
- `Utilization`: borrows / (cash + borrows − reserves)

---

## Walkthrough Example (from `test/integration/FullProtocol.t.sol`)

Assumptions used in the integration suite (Compound‑style liquidation threshold = collateral factor):
- USDC price = $1
- WETH price = $2,000
- USDC: collateral factor 75%, liquidation bonus 1.05
- WETH: collateral factor 80%, liquidation bonus 1.05
- Close factor = 50%

### `test_FullLendingLifecycle`

Goal: show a full deposit → borrow → interest accrual → repay → withdraw loop.

1. Alice supplies liquidity by minting 10,000 dUSDC (`dUSDC.mint(10000e18)`), which transfers 10,000 USDC into the pool and mints 10,000 receipt tokens.
2. Bob supplies 5 WETH as collateral, enters the WETH market, and enables borrowing.
3. Bob borrows 5,000 USDC against his collateral. His wallet now holds `INITIAL_BALANCE + 5000e18` USDC.
4. The test fast‑forwards 365 days and accrues interest on dUSDC. Bob’s debt increases above 5,000 USDC.
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
