// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {LendingPoolCore} from "../../src/lending/LendingPoolCore.sol";
import {LendingToken} from "../../src/lending/LendingToken.sol";
import {JumpRateModel} from "../../src/lending/JumpRateModel.sol";
import {PriceOracle} from "../../src/oracle/PriceOracle.sol";
import {GovernanceToken} from "../../src/governance/GovernanceToken.sol";
import {LiquidityMining} from "../../src/mining/LiquidityMining.sol";
import {ProtocolTimelock} from "../../src/governance/ProtocolTimelock.sol";
import {ProtocolGovernor} from "../../src/governance/ProtocolGovernor.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockPriceFeed} from "../mocks/MockPriceFeed.sol";
import {WadRayMath} from "../../src/libraries/WadRayMath.sol";

/**
 * @title FullProtocolTest
 * @notice Integration tests for the complete DeFi protocol
 */
contract FullProtocolTest is Test {
    using WadRayMath for uint256;

    // Core contracts
    LendingPoolCore public lendingPool;
    PriceOracle public priceOracle;
    JumpRateModel public interestRateModel;
    GovernanceToken public govToken;
    ProtocolGovernor public governor;
    ProtocolTimelock public timelock;

    // Lending tokens
    LendingToken public dUSDC;
    LendingToken public dWETH;

    // Mining contracts
    LiquidityMining public usdcMining;
    LiquidityMining public wethMining;

    // Mock tokens
    MockERC20 public usdc;
    MockERC20 public weth;

    // Mock price feeds
    MockPriceFeed public usdcFeed;
    MockPriceFeed public wethFeed;

    // Users
    address public deployer = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public carol = address(4);
    address public liquidator = address(5);

    // Constants
    uint256 constant INITIAL_BALANCE = 100_000e18;
    uint256 constant USDC_PRICE = 1e8;
    uint256 constant WETH_PRICE = 2000e8;
    uint256 constant MAX_GOV_SUPPLY = 100_000_000e18;

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 18);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        // Deploy mock price feeds
        usdcFeed = new MockPriceFeed(int256(USDC_PRICE), 8);
        wethFeed = new MockPriceFeed(int256(WETH_PRICE), 8);

        // Deploy price oracle
        priceOracle = PriceOracle(
            _deployProxy(
                address(new PriceOracle()),
                abi.encodeCall(PriceOracle.initialize, (deployer))
            )
        );
        priceOracle.setAssetSource(address(usdc), address(usdcFeed));
        priceOracle.setAssetSource(address(weth), address(wethFeed));

        // Deploy interest rate model
        interestRateModel = new JumpRateModel(0.02e18, 0.1e18, 1e18, 0.8e18);

        // Deploy lending pool
        lendingPool = LendingPoolCore(
            _deployProxy(
                address(new LendingPoolCore()),
                abi.encodeCall(LendingPoolCore.initialize, (deployer, address(priceOracle)))
            )
        );

        // Deploy lending tokens
        dUSDC = LendingToken(
            _deployProxy(
                address(new LendingToken()),
                abi.encodeCall(
                    LendingToken.initialize,
                    (address(usdc), address(lendingPool), address(interestRateModel), 1e18, "dUSDC", "dUSDC", deployer)
                )
            )
        );
        dWETH = LendingToken(
            _deployProxy(
                address(new LendingToken()),
                abi.encodeCall(
                    LendingToken.initialize,
                    (address(weth), address(lendingPool), address(interestRateModel), 1e18, "dWETH", "dWETH", deployer)
                )
            )
        );

        // Initialize reserves
        lendingPool.initReserve(address(usdc), address(dUSDC), address(interestRateModel), 0.75e18, 0.8e18, 1.05e18);
        lendingPool.initReserve(address(weth), address(dWETH), address(interestRateModel), 0.8e18, 0.85e18, 1.05e18);

        // Deploy governance token
        govToken = GovernanceToken(
            _deployProxy(
                address(new GovernanceToken()),
                abi.encodeCall(GovernanceToken.initialize, ("GOV", "GOV", deployer, MAX_GOV_SUPPLY))
            )
        );

        // Deploy timelock
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = deployer;
        executors[0] = address(0);

        timelock = ProtocolTimelock(
            payable(
                _deployProxy(
                    address(new ProtocolTimelock()),
                    abi.encodeCall(ProtocolTimelock.initialize, (1 days, proposers, executors, deployer))
                )
            )
        );

        // Deploy governor
        governor = ProtocolGovernor(
            payable(
                _deployProxy(
                    address(new ProtocolGovernor()),
                    abi.encodeCall(
                        ProtocolGovernor.initialize,
                        (
                            IVotes(address(govToken)),
                            TimelockControllerUpgradeable(payable(address(timelock))),
                            uint48(1 days),
                            uint32(1 weeks),
                            100_000e18,
                            4
                        )
                    )
                )
            )
        );

        // Grant governor roles on timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // Deploy liquidity mining
        usdcMining = LiquidityMining(
            _deployProxy(
                address(new LiquidityMining()),
                abi.encodeCall(
                    LiquidityMining.initialize,
                    (deployer, address(dUSDC), address(govToken), 30 days)
                )
            )
        );
        wethMining = LiquidityMining(
            _deployProxy(
                address(new LiquidityMining()),
                abi.encodeCall(
                    LiquidityMining.initialize,
                    (deployer, address(dWETH), address(govToken), 30 days)
                )
            )
        );

        vm.stopPrank();

        // Setup users
        _setupUser(alice);
        _setupUser(bob);
        _setupUser(carol);
        _setupUser(liquidator);
    }

    function _deployProxy(address impl, bytes memory data) internal returns (address) {
        return address(new ERC1967Proxy(impl, data));
    }

    function _setupUser(address user) internal {
        usdc.mint(user, INITIAL_BALANCE);
        weth.mint(user, INITIAL_BALANCE);

        vm.startPrank(user);
        usdc.approve(address(dUSDC), type(uint256).max);
        weth.approve(address(dWETH), type(uint256).max);
        usdc.approve(address(lendingPool), type(uint256).max);
        weth.approve(address(lendingPool), type(uint256).max);
        dUSDC.approve(address(usdcMining), type(uint256).max);
        dWETH.approve(address(wethMining), type(uint256).max);
        vm.stopPrank();
    }

    // ============ LENDING LIFECYCLE TESTS ============

    function test_FullLendingLifecycle() public {
        // 1. Alice deposits USDC
        vm.prank(alice);
        lendingPool.deposit(address(usdc), 10000e18, alice);
        assertEq(dUSDC.balanceOf(alice), 10000e18);

        // 2. Bob deposits WETH as collateral
        vm.prank(bob);
        lendingPool.deposit(address(weth), 5e18, bob); // 5 WETH = $10,000

        // 3. Bob borrows USDC
        vm.prank(bob);
        lendingPool.borrow(address(usdc), 5000e18, bob); // $5000 against $10,000 * 0.8 = $8,000 max
        assertEq(usdc.balanceOf(bob), INITIAL_BALANCE + 5000e18);

        // 4. Time passes, interest accrues
        vm.warp(block.timestamp + 365 days);
        // Refresh price feeds to avoid stale price error
        usdcFeed.refresh();
        wethFeed.refresh();
        dUSDC.accrueInterest();

        uint256 bobDebt = dUSDC.borrowBalanceStored(bob);
        assertGt(bobDebt, 5000e18); // Debt increased

        // 5. Bob repays debt
        vm.prank(bob);
        lendingPool.repay(address(usdc), type(uint256).max, bob);
        assertEq(dUSDC.borrowBalanceStored(bob), 0);

        // 6. Alice withdraws with interest
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        lendingPool.withdraw(address(usdc), type(uint256).max, alice);

        uint256 aliceWithdrawn = usdc.balanceOf(alice) - aliceBalanceBefore;
        assertGt(aliceWithdrawn, 10000e18); // Got more than deposited due to interest
    }

    function test_LiquidationWithPriceDrop() public {
        // 1. Setup: Alice provides liquidity
        vm.prank(alice);
        lendingPool.deposit(address(usdc), 50000e18, alice);

        // 2. Bob deposits WETH and borrows max
        vm.prank(bob);
        lendingPool.deposit(address(weth), 1e18, bob); // 1 WETH = $2000

        vm.prank(bob);
        lendingPool.borrow(address(usdc), 1500e18, bob); // Close to max

        // 3. Price drops
        wethFeed.setPrice(1500e8); // WETH drops to $1500

        // 4. Check health factor
        (, , , , , uint256 healthFactor) = lendingPool.getUserAccountData(bob);
        assertLt(healthFactor, 1e18);

        // 5. Liquidator repays debt and gets collateral
        uint256 liquidatorWethBefore = dWETH.balanceOf(liquidator);

        vm.prank(liquidator);
        lendingPool.liquidate(address(weth), address(usdc), bob, 750e18);

        // Liquidator should have received dWETH
        assertGt(dWETH.balanceOf(liquidator), liquidatorWethBefore);
    }

    // ============ LIQUIDITY MINING TESTS ============

    function test_LiquidityMiningRewards() public {
        // 1. Fund mining contract with rewards
        vm.prank(deployer);
        govToken.mint(address(usdcMining), 30000e18);

        // 2. Notify rewards
        vm.prank(deployer);
        usdcMining.notifyRewardAmount(30000e18); // 1000 tokens/day

        // 3. Alice deposits and stakes
        vm.startPrank(alice);
        lendingPool.deposit(address(usdc), 10000e18, alice);
        usdcMining.stake(dUSDC.balanceOf(alice));
        vm.stopPrank();

        // 4. Bob also stakes
        vm.startPrank(bob);
        lendingPool.deposit(address(usdc), 10000e18, bob);
        usdcMining.stake(dUSDC.balanceOf(bob));
        vm.stopPrank();

        // 5. Time passes
        vm.warp(block.timestamp + 15 days);

        // 6. Both claim rewards
        vm.prank(alice);
        usdcMining.getReward();

        vm.prank(bob);
        usdcMining.getReward();

        // Both should have rewards (approximately equal since staked same amount at same time)
        assertApproxEqRel(govToken.balanceOf(alice), govToken.balanceOf(bob), 0.01e18);
        assertGt(govToken.balanceOf(alice), 0);
    }

    function test_MiningWithDifferentStakeTimes() public {
        vm.prank(deployer);
        govToken.mint(address(usdcMining), 30000e18);

        vm.prank(deployer);
        usdcMining.notifyRewardAmount(30000e18);

        // Alice stakes immediately
        vm.startPrank(alice);
        lendingPool.deposit(address(usdc), 10000e18, alice);
        usdcMining.stake(dUSDC.balanceOf(alice));
        vm.stopPrank();

        // 10 days pass
        vm.warp(block.timestamp + 10 days);

        // Bob stakes later
        vm.startPrank(bob);
        lendingPool.deposit(address(usdc), 10000e18, bob);
        usdcMining.stake(dUSDC.balanceOf(bob));
        vm.stopPrank();

        // 20 more days pass
        vm.warp(block.timestamp + 20 days);

        // Claim rewards
        vm.prank(alice);
        usdcMining.getReward();

        vm.prank(bob);
        usdcMining.getReward();

        // Alice should have more rewards (staked longer)
        assertGt(govToken.balanceOf(alice), govToken.balanceOf(bob));
    }

    // ============ GOVERNANCE TESTS ============

    function test_GovernanceUpgradeFlow() public {
        // 1. Distribute governance tokens and delegate
        vm.startPrank(deployer);
        govToken.mint(alice, 1_000_000e18);
        govToken.mint(bob, 1_000_000e18);
        govToken.mint(carol, 1_000_000e18);
        vm.stopPrank();

        vm.prank(alice);
        govToken.delegate(alice);

        vm.prank(bob);
        govToken.delegate(bob);

        vm.prank(carol);
        govToken.delegate(carol);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // 2. Create upgrade proposal
        address newPriceOracleImpl = address(new PriceOracle());

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(priceOracle);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newPriceOracleImpl, ""));

        // Need to transfer ownership to timelock first
        vm.prank(deployer);
        priceOracle.transferOwnership(address(timelock));

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Upgrade PriceOracle");

        // 3. Pass voting delay (timestamp-based) - use explicit timestamps
        uint256 votingStartTime = block.timestamp + 1 days + 1;
        vm.warp(votingStartTime);

        // 4. Vote
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.prank(bob);
        governor.castVote(proposalId, 1);

        vm.prank(carol);
        governor.castVote(proposalId, 1);

        // 5. Pass voting period
        uint256 votingEndTime = votingStartTime + 1 weeks + 1;
        vm.warp(votingEndTime);

        // 6. Queue
        bytes32 descHash = keccak256(bytes("Upgrade PriceOracle"));
        governor.queue(targets, values, calldatas, descHash);

        // 7. Pass timelock delay
        uint256 executeTime = votingEndTime + 1 days + 1;
        vm.warp(executeTime);

        // 8. Execute
        uint256 versionBefore = priceOracle.version();
        governor.execute(targets, values, calldatas, descHash);

        // 9. Verify upgrade
        assertEq(priceOracle.version(), versionBefore + 1);
    }

    // ============ STORAGE UPGRADE TESTS ============

    function test_StoragePreservationAcrossUpgrade() public {
        // 1. Setup state
        vm.prank(alice);
        lendingPool.deposit(address(usdc), 10000e18, alice);

        uint256 aliceBalanceBefore = dUSDC.balanceOf(alice);
        uint256 versionBefore = lendingPool.version();

        // 2. Deploy new implementation
        address newImpl = address(new LendingPoolCore());

        // 3. Upgrade
        vm.prank(deployer);
        UUPSUpgradeable(address(lendingPool)).upgradeToAndCall(newImpl, "");

        // 4. Verify storage preserved
        assertEq(dUSDC.balanceOf(alice), aliceBalanceBefore);
        assertEq(lendingPool.version(), versionBefore + 1);
        assertEq(lendingPool.getLendingToken(address(usdc)), address(dUSDC));
    }

    function test_LendingTokenStoragePreservation() public {
        // 1. Setup state with borrows
        vm.prank(alice);
        lendingPool.deposit(address(usdc), 10000e18, alice);

        vm.prank(bob);
        lendingPool.deposit(address(weth), 5e18, bob);

        vm.prank(bob);
        lendingPool.borrow(address(usdc), 5000e18, bob);

        // Time passes for interest
        vm.warp(block.timestamp + 30 days);
        dUSDC.accrueInterest();

        uint256 totalBorrowsBefore = dUSDC.totalBorrows();
        uint256 bobDebtBefore = dUSDC.borrowBalanceStored(bob);
        uint256 exchangeRateBefore = dUSDC.exchangeRateStored();

        // 2. Upgrade
        address newImpl = address(new LendingToken());
        vm.prank(deployer);
        UUPSUpgradeable(address(dUSDC)).upgradeToAndCall(newImpl, "");

        // 3. Verify state preserved
        assertEq(dUSDC.totalBorrows(), totalBorrowsBefore);
        assertEq(dUSDC.borrowBalanceStored(bob), bobDebtBefore);
        assertEq(dUSDC.exchangeRateStored(), exchangeRateBefore);
    }

    // ============ EDGE CASE TESTS ============

    function test_MultipleAssetCollateral() public {
        // Alice provides liquidity
        vm.prank(alice);
        lendingPool.deposit(address(usdc), 50000e18, alice);

        // Bob deposits multiple assets as collateral
        vm.startPrank(bob);
        lendingPool.deposit(address(usdc), 5000e18, bob); // $5000
        lendingPool.deposit(address(weth), 2e18, bob); // $4000

        // Total collateral: $9000, with weighted LTV
        // USDC: $5000 * 0.75 = $3750
        // WETH: $4000 * 0.8 = $3200
        // Total borrowing power: $6950

        lendingPool.borrow(address(usdc), 6000e18, bob); // Should succeed
        vm.stopPrank();

        (uint256 totalCollateral, uint256 totalDebt, , , , uint256 healthFactor) =
            lendingPool.getUserAccountData(bob);

        assertGt(totalCollateral, 0);
        assertEq(totalDebt, 6000e8); // $6000 in 8 decimals = 6000 * 1e8
        assertGt(healthFactor, 1e18);
    }

    function test_ProtocolPauseAndResume() public {
        // Setup
        vm.prank(alice);
        lendingPool.deposit(address(usdc), 10000e18, alice);

        // Pause
        vm.prank(deployer);
        lendingPool.setPaused(true);

        // Operations should fail
        vm.prank(bob);
        vm.expectRevert();
        lendingPool.deposit(address(usdc), 1000e18, bob);

        // Resume
        vm.prank(deployer);
        lendingPool.setPaused(false);

        // Operations should work again
        vm.prank(bob);
        lendingPool.deposit(address(usdc), 1000e18, bob);
        assertEq(dUSDC.balanceOf(bob), 1000e18);
    }

    function test_InterestAccrualOverTime() public {
        // Alice deposits
        vm.prank(alice);
        lendingPool.deposit(address(usdc), 10000e18, alice);

        // Bob borrows
        vm.prank(bob);
        lendingPool.deposit(address(weth), 10e18, bob);

        vm.prank(bob);
        lendingPool.borrow(address(usdc), 5000e18, bob);

        uint256 prevDebt = dUSDC.borrowBalanceStored(bob);
        uint256 prevRate = dUSDC.exchangeRateStored();

        // Check at different time points
        uint256 currentTime = block.timestamp;
        for (uint256 i = 0; i < 4; i++) {
            currentTime += 90 days;
            vm.warp(currentTime);
            // Refresh price feeds to avoid stale price error
            usdcFeed.refresh();
            wethFeed.refresh();
            dUSDC.accrueInterest();

            uint256 currentDebt = dUSDC.borrowBalanceStored(bob);
            uint256 currentRate = dUSDC.exchangeRateStored();

            // Debt and exchange rate should consistently grow
            assertGt(currentDebt, prevDebt, "Debt should grow over time");
            assertGt(currentRate, prevRate, "Exchange rate should grow over time");

            prevDebt = currentDebt;
            prevRate = currentRate;
        }
    }
}
