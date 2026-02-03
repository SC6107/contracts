## Upgradeable DeFi Protocol Suite (Foundry)

This repo contains a full on-chain DeFi protocol built with upgradeable smart contracts.
It includes:
- A lending pool (deposit, borrow, repay, withdraw, liquidation)
- A liquidity mining (staking rewards) module
- A governance system that controls upgrades through a timelock
- A price oracle

It is written in Solidity and tested with Foundry.

If you are new to DeFi, read this top to bottom. It starts with plain concepts and
ends with contract-by-contract details.

---

## Big picture (no jargon)

People deposit tokens into a shared pool. Others can borrow those tokens if they
put up enough collateral. Borrowers pay interest. Depositors earn interest.

This protocol has three big parts:
1) Lending pool: where deposits and borrows happen
2) Liquidity mining: rewards people who stake their deposit tokens
3) Governance: token holders vote on upgrades and configuration changes

Everything is upgradeable, so the protocol can evolve without losing state.
Upgrades are controlled by governance and delayed by a timelock.

---

## Repo map

Top level:
- `src/` core protocol contracts
- `test/` unit + integration tests
- `script/` deploy and upgrade scripts
- `lib/` external libraries (OpenZeppelin, forge-std)
- `foundry.toml` Foundry config
- `requirement.md` project requirements

Key folders in `src/`:
- `src/lending/` lending pool and interest logic
- `src/mining/` staking rewards
- `src/governance/` governance and timelock
- `src/oracle/` price oracle
- `src/interfaces/` shared interfaces
- `src/libraries/` math, errors, and storage helpers

---

## Core ideas you should know

### 1) Deposits create receipt tokens
When you deposit USDC into the pool, you receive a receipt token (like a share).
Here the receipt token is called `LendingToken` (for example `dUSDC`).
You can redeem it later for your original deposit plus interest.

### 2) Borrowing uses collateral
To borrow, you must deposit collateral. The protocol checks the value of your
collateral vs your debt using the price oracle. If your health factor falls too
low, your position can be liquidated.

### 3) Interest grows over time
Borrowers pay interest. Interest is calculated using a utilization-based model
(Compound-style "jump rate model"). When borrowers owe more, the exchange rate
for depositors increases.

### 4) Upgradable contracts
These contracts use the UUPS proxy pattern. The proxy holds the data (state).
The implementation holds the logic. Governance can upgrade the logic while the
state remains intact.

### 5) Governance and timelock
The governance token gives voting power. Token holders create proposals and vote.
If a proposal passes, it goes to a timelock before execution (minimum 24 hours).
Upgrades are executed by governance after the timelock delay.

---

## How the lending flow works (expanded)

### Deposit (step-by-step)
1) User calls `LendingPoolCore.deposit(asset, amount, onBehalfOf)`
2) The pool checks that the reserve is active and the amount is non-zero
3) The pool calls `LendingToken.mint(from, to, amount)`:
   - Underlying tokens move from the user into the `LendingToken` contract
   - The `LendingToken` mints receipt shares to the user
4) The pool marks the asset as collateral for the user by default
5) The user now holds receipt tokens (`dUSDC`, `dWETH`) that represent a claim
   on the pool's underlying assets

### Borrow (step-by-step)
1) User calls `LendingPoolCore.borrow(asset, amount, onBehalfOf)`
2) The pool asks the price oracle to value the user's collateral and debt
3) The pool checks the health factor after the new borrow
4) If the health factor would fall below 1, the transaction reverts
5) If safe, the pool calls `LendingToken.borrow(borrower, amount)`
6) The `LendingToken`:
   - Accrues interest to update indexes
   - Increases the borrower's principal
   - Transfers underlying tokens to the borrower
7) The borrower now owes debt that grows over time

### Repay (step-by-step)
1) User calls `LendingPoolCore.repay(asset, amount, onBehalfOf)`
2) The pool calls `LendingToken.repayBorrow(payer, borrower, amount)`
3) The `LendingToken`:
   - Accrues interest
   - Transfers underlying from payer to itself
   - Reduces the borrower's principal
4) Debt is reduced immediately

### Withdraw (step-by-step)
1) User calls `LendingPoolCore.withdraw(asset, amount, to)`
2) The pool converts the amount into receipt-token shares
3) The pool checks that the user's health factor stays >= 1
4) If safe, the pool calls `LendingToken.redeem(from, to, shares)`
5) The `LendingToken` burns shares and transfers underlying to the user

### Liquidation (step-by-step)
If a borrower becomes unsafe (health factor < 1):
1) A liquidator calls `LendingPoolCore.liquidate(...)`
2) The liquidator repays part of the borrower's debt
3) The protocol seizes collateral receipt tokens from the borrower
4) The liquidator receives collateral with a bonus (incentive)
5) Borrower debt is reduced and the position becomes safer

---

## Contracts, by module

### Lending

`src/lending/LendingPoolCore.sol`
- Main entry point for deposits, borrows, repay, withdraw, and liquidation.
- Tracks reserves for each supported asset.
- Calculates health factor and enforces collateral rules.
- Upgradeable (UUPS).

`src/lending/LendingToken.sol`
- Receipt token for deposits (similar to Compound cTokens).
- Keeps track of total borrows, reserves, and the borrow index.
- Accrues interest over time.
- Upgradeable (UUPS).

`src/lending/JumpRateModel.sol`
- Interest rate model with a "kink".
- When utilization is low, rate grows slowly.
- When utilization is high, rate grows faster.
- Non-upgradeable by design (immutable parameters).

Storage helpers:
- `src/lending/LendingPoolStorage.sol`
- `src/lending/LendingTokenStorage.sol`
These isolate storage layout to keep upgrades safe.

---

### Liquidity Mining (staking rewards)

`src/mining/LiquidityMining.sol`
- Users stake their receipt tokens (e.g., dUSDC).
- Rewards are distributed over time, Synthetix-style.
- Reward token is the governance token.
- Upgradeable (UUPS).

`src/mining/LiquidityMiningStorage.sol`
- Storage layout for staking.

---

### Governance

`src/governance/GovernanceToken.sol`
- ERC20 token with voting power (OpenZeppelin Votes).
- Upgradeable (UUPS).

`src/governance/ProtocolGovernor.sol`
- On-chain governance (OpenZeppelin Governor).
- Handles proposals, voting, and execution.
- Upgradeable (UUPS).

`src/governance/ProtocolTimelock.sol`
- Timelock controller that delays execution of governance actions.
- Minimum delay is 24 hours.
- Upgradeable (UUPS).

---

### Oracle

`src/oracle/PriceOracle.sol`
- Aggregates price feeds (mocked in tests).
- Used for health factor and liquidation calculations.
- Upgradeable (UUPS).

---

### Libraries and interfaces

`src/libraries/WadRayMath.sol`
- Fixed-point math helpers (1e18 and 1e27 precision).

`src/libraries/Errors.sol`
- Shared custom errors for consistent revert messages.

`src/interfaces/*.sol`
- Interfaces for the lending pool, oracle, and tokens.

---

## Upgradeability (UUPS) explained for beginners (expanded)

Think of a proxy like a permanent address that users interact with.
The proxy stores all data. The "implementation" is the logic code.

When the protocol upgrades:
- The proxy keeps the same address and data
- Governance tells the proxy to use a new implementation
- Users do not lose balances

This repo uses:
- UUPS proxies (`UUPSUpgradeable`)
- Explicit storage layout libraries (ERC-7201 slots)
- Upgrade authorization guarded by governance/timelock

### UUPS in plain terms
- The proxy is a thin forwarder that holds all state
- The implementation contains upgrade logic
- The proxy delegates calls to the implementation
- The implementation decides who can upgrade

### Where upgrades happen in this repo
- Each core contract overrides `_authorizeUpgrade(...)`
- The timelock is the final authority for upgrades
- The governor schedules upgrades through the timelock

### Why storage layout matters
- Upgrades reuse the same storage slots
- If a new version changes the layout incorrectly, old data gets corrupted
- This repo isolates storage with `*Storage.sol` libraries to keep layout stable

---

## Governance + timelock (expanded)

### The governance token
`GovernanceToken` is an ERC20 with voting power.
Users must delegate to themselves (or someone else) to activate votes.

### The governor contract
`ProtocolGovernor` handles:
- proposal creation
- voting windows
- quorum checks
- queueing successful proposals

### The timelock
`ProtocolTimelock` enforces a delay before execution:
- Minimum delay is 24 hours
- This gives users time to exit if they disagree with an upgrade

### The full governance flow
1) Token holders propose an action (for example, upgrade a contract)
2) There is a voting delay (time before voting starts)
3) The voting period begins; holders vote "for" or "against"
4) If quorum and vote thresholds pass, the proposal is queued
5) The timelock delay passes
6) The proposal is executed

### How upgrades are governed here
The upgrade call is encoded as:
`UUPSUpgradeable.upgradeToAndCall(newImpl, data)`
The governor schedules that call, then the timelock executes it.

---

## Interest rate math (expanded)

This protocol uses a Compound-style "jump rate" model.
The idea: borrowing gets more expensive as the pool gets more utilized.

### Key definitions
- Cash: how much underlying is available in the pool
- Borrows: how much users owe
- Reserves: protocol-owned funds
- Utilization = borrows / (cash + borrows - reserves)

### Rates
- Base rate: minimum borrow rate
- Multiplier: slope before the kink
- Jump multiplier: slope after the kink
- Kink: utilization point where rates rise faster

### What happens as utilization changes?
Low utilization:
- Borrowing is cheaper to encourage borrowing

High utilization:
- Borrowing becomes more expensive to slow demand

### How depositors earn interest
- Borrowers pay interest
- The pool's total borrows grow over time
- The exchange rate for receipt tokens increases
- When depositors redeem, they get more underlying than they put in

### How interest accrues in code
The `LendingToken.accrueInterest()` function:
1) Calculates the borrow rate per second
2) Computes how much time elapsed
3) Increases total borrows
4) Updates the global borrow index

This is why debt grows even if a borrower does nothing.

---

## Liquidation mechanics (expanded)

Liquidation is the safety valve that keeps lenders protected.
If a borrower's position becomes unsafe, anyone can liquidate it.

### The health factor
The pool calculates a health factor based on:
- collateral value
- debt value
- liquidation threshold

If health factor < 1, the position can be liquidated.

### What a liquidator does
1) Repays part of the borrower's debt
2) Receives collateral with a bonus
3) Helps restore the system's solvency

### Why liquidators are incentivized
The collateral bonus is the reward. It encourages third parties to keep the
system healthy by closing risky positions.

---

## Tests

Tests are in `test/`:
- `test/unit/` unit tests for each contract
- `test/integration/` full protocol flows
- `test/mocks/` mock ERC20 and price feeds

Key integration test:
- `test/integration/FullProtocol.t.sol`
  - deposit/borrow/repay/withdraw
  - liquidation
  - interest accrual
  - governance upgrade flow
  - storage preservation across upgrades

Run tests:
```shell
forge test
```

---

## Scripts

`script/DeployProtocol.s.sol`
- Example deployment logic for the whole suite

`script/UpgradeProtocol.s.sol`
- Example upgrade flow

Run a script:
```shell
forge script script/DeployProtocol.s.sol:DeployProtocolScript --rpc-url <RPC> --private-key <KEY>
```

---

## How to run locally (quick start)

1) Install Foundry:
   https://book.getfoundry.sh/getting-started/installation

2) Build:
```shell
forge build
```

3) Test:
```shell
forge test
```

---

## Important parameters you will see

- `LTV` (loan-to-value): how much you can borrow vs collateral
- `Liquidation threshold`: when liquidation becomes possible
- `Health factor`: safety ratio; below 1 is unsafe
- `Reserve factor`: part of interest kept as reserves
- `Utilization`: borrowed / total available

---

---

## Walkthrough example (numbers)

This example matches the constants used in `test/integration/FullProtocol.t.sol`.
Assume:
- USDC price = $1
- WETH price = $2,000
- USDC reserve: LTV 75%, liquidation threshold 80%, liquidation bonus 1.05
- WETH reserve: LTV 80%, liquidation threshold 85%, liquidation bonus 1.05
- Close factor = 50% (max debt repaid per liquidation)

### Step 1: Alice deposits USDC
Alice deposits 10,000 USDC.
- She receives 10,000 dUSDC (1:1 at the initial exchange rate)
- The pool now has 10,000 USDC cash

### Step 2: Bob deposits WETH as collateral
Bob deposits 5 WETH.
- Value = 5 * $2,000 = $10,000
- With 80% LTV, his max borrow is $8,000

### Step 3: Bob borrows USDC
Bob borrows 5,000 USDC.
- Pool cash drops from 10,000 to 5,000
- Total borrows becomes 5,000
- Bob's debt starts accruing interest

### Step 4: Time passes and interest accrues
After some time, Bob's debt grows (example):
- Bob owes 5,086.30136982944 USDC (sample from test logs)
- Total borrows increase, so the dUSDC exchange rate rises
- Alice can redeem more than her original 10,000 USDC

### Step 5: Price drop and liquidation risk (from liquidation test)
Now consider the liquidation scenario used in tests:
- Bob deposits 1 WETH (worth $2,000)
- Bob borrows 1,500 USDC
- WETH price drops to $1,500

Re-evaluate Bob:
- Collateral value = 1 * $1,500 = $1,500
- Liquidation threshold (85%) => max safe debt = $1,275
- Bob owes $1,500, so he is liquidatable

### Step 6: Liquidation
A liquidator repays part of Bob's debt.
- Close factor is 50%, so max repay is 750 USDC
- Liquidator receives collateral worth 750 * 1.05 = 787.5 USDC
  (paid out as dWETH shares at current prices)
- Bob's debt is reduced, improving his health factor

### Step 7: Alice withdraws
Alice redeems her dUSDC.
- Because the exchange rate increased from interest, she receives more than
  10,000 USDC.

This walkthrough mirrors the same constants and behaviors tested in
`test/integration/FullProtocol.t.sol`.

---

## Common questions (beginner-friendly)

### Why is it upgradeable?
DeFi protocols need upgrades for bugs, new features, and parameter changes.
Upgradeable contracts allow that without losing user funds.

### What gives deposits value over time?
Borrowers pay interest, which increases `totalBorrows`. This increases the
exchange rate, so depositors can redeem more than they put in.

### What protects users from instant upgrades?
Governance proposals go through a timelock (minimum 24 hours).
That gives users time to react.

---

## Known limitations (from requirement.md)

Some requirement items are not implemented yet:
- Multiple reward token support in liquidity mining (only one rewards token)
- Emergency multisig override for governance
- Explicit rollback mechanism for upgrades

---

## Glossary

- Collateral: assets you lock to secure a loan
- Borrower: user who takes a loan
- Lender: user who deposits and earns interest
- Liquidation: forced repayment when a position is unsafe
- Proxy: contract that forwards calls to the current implementation
- UUPS: upgrade pattern where the implementation contains upgrade logic
- Timelock: delay before governance actions execute

---

## Want a guided walk-through?

If you want, tell me which part is most confusing:
1) lending flow
2) upgradeable proxies
3) governance and timelock
4) interest rate math
5) liquidation mechanics
