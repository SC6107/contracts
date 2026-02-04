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

## Deployer Account

The deployer is determined by the `PRIVATE_KEY` environment variable. When running locally with `deploy_local.sh`, this is typically **Anvil Account 0**:

| | Value |
|---|---|
| **Address** | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` |
| **Private Key** | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |

The deployer has special privileges:
- **Owner** of all proxy contracts (Comptroller, PriceOracle, LendingTokens, GovernanceToken, Timelock, Governor, LiquidityMining)
- **Minter** of GovernanceToken (can call `govToken.mint(to, amount)`)
- **RewardsDistributor** for LiquidityMining contracts (can call `notifyRewardAmount`)
- **Admin** of ProtocolTimelock

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

Prices are mocked with fixed values. Use `MockPriceFeed.setPrice(newPrice)` to change prices for testing scenarios like liquidation.

Use `PriceOracle.getAssetSource(asset)` to find each feed address.

---

## Example Lifecycle (CLI)

If you want a full end‑to‑end repro of `test_FullLendingLifecycle`:

```bash
script/repro_full_lending_lifecycle.sh
```

This script resolves addresses automatically and runs the lifecycle against your local deployment.

---

## ABI Reference (Full Lending Lifecycle)

Based on `test_FullLendingLifecycle`, here are the function signatures for frontend integration:

### ERC20 (USDC, WETH)

```solidity
// Approve dToken to spend underlying
function approve(address spender, uint256 amount) external returns (bool)

// Check token balance
function balanceOf(address account) external view returns (uint256)
```

### LendingToken (dUSDC, dWETH)

```solidity
// Supply: deposit underlying tokens and receive dTokens
function mint(uint256 mintAmount) external returns (uint256 mintTokens)

// Withdraw: burn dTokens and receive underlying
function redeem(uint256 redeemTokens) external returns (uint256 redeemAmount)

// Withdraw by underlying amount
function redeemUnderlying(uint256 redeemAmount) external returns (uint256 redeemTokens)

// Borrow underlying against collateral
function borrow(uint256 borrowAmount) external

// Repay borrowed amount (use type(uint256).max for full repay)
function repayBorrow(uint256 repayAmount) external returns (uint256 actualRepayAmount)

// Repay on behalf of another borrower
function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256)

// Liquidate undercollateralized position
function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral) external returns (uint256 seizeTokens)

// Update interest (called automatically by other functions)
function accrueInterest() external

// View: get current borrow balance (stale)
function borrowBalanceStored(address account) external view returns (uint256)

// View: get current borrow balance (updates interest first)
function borrowBalanceCurrent(address account) external returns (uint256)

// View: get exchange rate (dToken to underlying)
function exchangeRateStored() external view returns (uint256)

// View: check dToken balance
function balanceOf(address account) external view returns (uint256)

// View: get underlying token address
function underlying() external view returns (address)

// View: get total borrows
function totalBorrows() external view returns (uint256)

// View: get cash (available liquidity)
function getCash() external view returns (uint256)
```

### Comptroller

```solidity
// Enter markets to use assets as collateral (required before borrowing)
function enterMarkets(address[] calldata cTokens) external

// Exit a market (remove asset as collateral)
function exitMarket(address cToken) external

// View: get account liquidity and shortfall
function getAccountLiquidity(address account) external view returns (uint256 liquidity, uint256 shortfall)

// View: get hypothetical liquidity after a transaction
function getHypotheticalAccountLiquidity(
    address account,
    address cTokenModify,
    uint256 redeemTokens,
    uint256 borrowAmount
) external view returns (uint256 liquidity, uint256 shortfall)

// View: check if market is listed
function isMarketListed(address cToken) external view returns (bool)

// View: get all markets
function getAllMarkets() external view returns (address[] memory)

// View: get market config (collateral factor, isListed)
function getMarketConfiguration(address cToken) external view returns (uint256 collateralFactor, bool isListed)

// View: check if protocol is paused
function paused() external view returns (bool)

// View: get close factor (max % of borrow liquidatable)
function closeFactorMantissa() external view returns (uint256)

// View: get liquidation incentive
function liquidationIncentiveMantissa() external view returns (uint256)
```

### Full Lending Lifecycle Example (ethers.js)

```javascript
// 1. Alice supplies USDC
await usdc.connect(alice).approve(dUSDC.address, ethers.MaxUint256);
await dUSDC.connect(alice).mint(ethers.parseEther("10000"));

// 2. Bob supplies WETH as collateral
await weth.connect(bob).approve(dWETH.address, ethers.MaxUint256);
await dWETH.connect(bob).mint(ethers.parseEther("5"));

// 3. Bob enters WETH market (required for using as collateral)
await comptroller.connect(bob).enterMarkets([dWETH.address]);

// 4. Bob borrows USDC
await dUSDC.connect(bob).borrow(ethers.parseEther("5000"));

// 5. Check Bob's debt (after some time)
const debt = await dUSDC.borrowBalanceStored(bob.address);

// 6. Bob repays full debt
await usdc.connect(bob).approve(dUSDC.address, ethers.MaxUint256);
await dUSDC.connect(bob).repayBorrow(ethers.MaxUint256);

// 7. Alice withdraws with interest
const aliceShares = await dUSDC.balanceOf(alice.address);
await dUSDC.connect(alice).redeem(aliceShares);
```

---

## ABI Reference (Liquidity Mining Rewards)

Based on `test_LiquidityMiningRewards`, here are the function signatures for liquidity mining:

### LiquidityMining (USDC_MINING, WETH_MINING)

```solidity
// Stake dTokens to earn rewards
function stake(uint256 amount) external

// Withdraw staked dTokens
function withdraw(uint256 amount) external

// Claim accumulated rewards
function getReward() external

// Withdraw all and claim rewards in one transaction
function exit() external

// View: get pending rewards for account
function earned(address account) external view returns (uint256)

// View: get staked balance for account
function balanceOf(address account) external view returns (uint256)

// View: get total staked in contract
function totalSupply() external view returns (uint256)

// View: get current reward rate (tokens per second)
function rewardRate() external view returns (uint256)

// View: get reward per token (for calculation)
function rewardPerToken() external view returns (uint256)

// View: get timestamp when current reward period ends
function periodFinish() external view returns (uint256)

// View: get rewards duration (in seconds)
function rewardsDuration() external view returns (uint256)

// View: get staking token address (dToken)
function stakingToken() external view returns (address)

// View: get rewards token address (governance token)
function rewardsToken() external view returns (address)

// View: get last time reward was applicable
function lastTimeRewardApplicable() external view returns (uint256)

// Admin: notify contract of new rewards (requires tokens already transferred)
function notifyRewardAmount(uint256 reward) external

// Admin: set rewards duration (only when period finished)
function setRewardsDuration(uint256 duration) external
```

### Liquidity Mining Rewards Example (ethers.js)

```javascript
// Setup: Admin funds mining contract and notifies rewards
await govToken.connect(deployer).mint(usdcMining.address, ethers.parseEther("30000"));
await usdcMining.connect(deployer).notifyRewardAmount(ethers.parseEther("30000"));

// 1. Alice supplies USDC and gets dUSDC
await usdc.connect(alice).approve(dUSDC.address, ethers.MaxUint256);
await dUSDC.connect(alice).mint(ethers.parseEther("10000"));

// 2. Alice approves and stakes dUSDC in mining contract
await dUSDC.connect(alice).approve(usdcMining.address, ethers.MaxUint256);
const aliceDTokens = await dUSDC.balanceOf(alice.address);
await usdcMining.connect(alice).stake(aliceDTokens);

// 3. Bob also supplies and stakes
await usdc.connect(bob).approve(dUSDC.address, ethers.MaxUint256);
await dUSDC.connect(bob).mint(ethers.parseEther("10000"));
await dUSDC.connect(bob).approve(usdcMining.address, ethers.MaxUint256);
const bobDTokens = await dUSDC.balanceOf(bob.address);
await usdcMining.connect(bob).stake(bobDTokens);

// 4. Time passes... (in test: vm.warp; in real: wait)

// 5. Check pending rewards
const alicePending = await usdcMining.earned(alice.address);
const bobPending = await usdcMining.earned(bob.address);

// 6. Claim rewards
await usdcMining.connect(alice).getReward();
await usdcMining.connect(bob).getReward();

// 7. Check received governance tokens
const aliceGovBalance = await govToken.balanceOf(alice.address);
const bobGovBalance = await govToken.balanceOf(bob.address);

// 8. (Optional) Withdraw staked tokens and claim in one tx
await usdcMining.connect(alice).exit();
```

---

## Interest Rate Info (APY Calculation)

The protocol uses a **JumpRateModel** (Compound-style) for interest rates.

### Protocol Constants (from FullSetupLocal)

| Parameter | Value | Description |
|-----------|-------|-------------|
| Base Rate | 2% per year | Minimum borrow rate |
| Multiplier | 10% per year | Rate increase per utilization (before kink) |
| Jump Multiplier | 100% per year | Rate increase per utilization (after kink) |
| Kink | 80% | Utilization threshold for jump rate |
| Reserve Factor | 10% | Protocol's cut of interest |

### Interest Rate Formula

```
Utilization = TotalBorrows / (Cash + TotalBorrows - Reserves)

If Utilization ≤ 80% (kink):
  BorrowRate = BaseRate + Utilization × Multiplier

If Utilization > 80%:
  BorrowRate = BaseRate + Kink × Multiplier + (Utilization - Kink) × JumpMultiplier

SupplyRate = BorrowRate × Utilization × (1 - ReserveFactor)
```

### JumpRateModel ABI

```solidity
// View: get utilization rate (scaled by 1e18, e.g., 0.5e18 = 50%)
function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) external pure returns (uint256)

// View: get borrow rate per second (scaled by 1e18)
function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256)

// View: get supply rate per second (scaled by 1e18)
function getSupplyRate(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactorMantissa) external view returns (uint256)

// View: get borrow rate per year (scaled by 1e18, e.g., 0.05e18 = 5% APR)
function getBorrowRatePerYear(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256)

// View: get supply rate per year (scaled by 1e18)
function getSupplyRatePerYear(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactorMantissa) external view returns (uint256)

// Constants
function kink() external view returns (uint256)
function baseRatePerSecond() external view returns (uint256)
function multiplierPerSecond() external view returns (uint256)
function jumpMultiplierPerSecond() external view returns (uint256)
```

### LendingToken Helper Functions

```solidity
// Get interest rate model address
function interestRateModel() external view returns (address)

// Get reserve factor (scaled by 1e18, e.g., 0.1e18 = 10%)
function reserveFactorMantissa() external view returns (uint256)

// Get values needed for rate calculation
function getCash() external view returns (uint256)
function totalBorrows() external view returns (uint256)
function totalReserves() external view returns (uint256)
```

### APY Calculation Example (ethers.js)

```javascript
const SECONDS_PER_YEAR = 365n * 24n * 60n * 60n; // 31536000
const WAD = ethers.parseEther("1"); // 1e18

// Get market state from LendingToken
const cash = await dUSDC.getCash();
const borrows = await dUSDC.totalBorrows();
const reserves = await dUSDC.totalReserves();
const reserveFactor = await dUSDC.reserveFactorMantissa();

// Get interest rate model
const rateModelAddr = await dUSDC.interestRateModel();
const rateModel = new ethers.Contract(rateModelAddr, JumpRateModelABI, provider);

// Get APR (Annual Percentage Rate)
const borrowRatePerYear = await rateModel.getBorrowRatePerYear(cash, borrows, reserves);
const supplyRatePerYear = await rateModel.getSupplyRatePerYear(cash, borrows, reserves, reserveFactor);

// Convert to percentage (e.g., 0.05e18 -> 5.00%)
const borrowAPR = Number(borrowRatePerYear) / 1e18 * 100;
const supplyAPR = Number(supplyRatePerYear) / 1e18 * 100;

console.log(`Borrow APR: ${borrowAPR.toFixed(2)}%`);
console.log(`Supply APR: ${supplyAPR.toFixed(2)}%`);

// Get utilization
const utilization = await rateModel.utilizationRate(cash, borrows, reserves);
const utilizationPercent = Number(utilization) / 1e18 * 100;
console.log(`Utilization: ${utilizationPercent.toFixed(2)}%`);

// Convert APR to APY (compounded per second)
// APY = (1 + ratePerSecond)^secondsPerYear - 1
function aprToApy(aprWad) {
  const ratePerSecond = Number(aprWad) / Number(SECONDS_PER_YEAR) / 1e18;
  const apy = Math.pow(1 + ratePerSecond, Number(SECONDS_PER_YEAR)) - 1;
  return apy * 100; // percentage
}

const borrowAPY = aprToApy(borrowRatePerYear);
const supplyAPY = aprToApy(supplyRatePerYear);

console.log(`Borrow APY: ${borrowAPY.toFixed(2)}%`);
console.log(`Supply APY: ${supplyAPY.toFixed(2)}%`);
```

### Example Rate Curve

| Utilization | Borrow APR | Supply APR* |
|-------------|------------|-------------|
| 0% | 2.00% | 0.00% |
| 40% | 6.00% | 2.16% |
| 80% (kink) | 10.00% | 7.20% |
| 90% | 20.00% | 16.20% |
| 100% | 30.00% | 27.00% |

*Supply APR assumes 10% reserve factor

---

## Troubleshooting

- **`PriceFeedNotFound`**: make sure the oracle is configured with `setAssetSource` (done in `FullSetupLocal`).
- **`MarketNotListed`**: ensure `Comptroller.supportMarket` was called (done in `FullSetupLocal`).
- **Insufficient balance**: confirm your account is funded with USDC/WETH and ETH for gas.
