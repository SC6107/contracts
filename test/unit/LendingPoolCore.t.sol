// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LendingPoolCore} from "../../src/lending/LendingPoolCore.sol";
import {LendingToken} from "../../src/lending/LendingToken.sol";
import {PriceOracle} from "../../src/oracle/PriceOracle.sol";
import {JumpRateModel} from "../../src/lending/JumpRateModel.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockPriceFeed} from "../mocks/MockPriceFeed.sol";
import {WadRayMath} from "../../src/libraries/WadRayMath.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract LendingPoolCoreTest is Test {
    using WadRayMath for uint256;

    LendingPoolCore public lendingPool;
    PriceOracle public priceOracle;
    JumpRateModel public interestRateModel;

    MockERC20 public usdc;
    MockERC20 public weth;
    MockPriceFeed public usdcPriceFeed;
    MockPriceFeed public wethPriceFeed;

    LendingToken public dUSDC;
    LendingToken public dWETH;

    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public liquidator = address(4);

    uint256 constant INITIAL_BALANCE = 10000e18;
    uint256 constant USDC_PRICE = 1e8; // $1
    uint256 constant WETH_PRICE = 2000e8; // $2000

    function setUp() public {
        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 18);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        // Deploy price feeds
        usdcPriceFeed = new MockPriceFeed(int256(USDC_PRICE), 8);
        wethPriceFeed = new MockPriceFeed(int256(WETH_PRICE), 8);

        // Deploy price oracle
        PriceOracle oracleImpl = new PriceOracle();
        priceOracle = PriceOracle(
            address(
                new ERC1967Proxy(
                    address(oracleImpl),
                    abi.encodeCall(PriceOracle.initialize, (owner))
                )
            )
        );

        // Set price sources
        vm.startPrank(owner);
        priceOracle.setAssetSource(address(usdc), address(usdcPriceFeed));
        priceOracle.setAssetSource(address(weth), address(wethPriceFeed));
        vm.stopPrank();

        // Deploy interest rate model
        interestRateModel = new JumpRateModel(0.02e18, 0.1e18, 1e18, 0.8e18);

        // Deploy lending pool
        LendingPoolCore poolImpl = new LendingPoolCore();
        lendingPool = LendingPoolCore(
            address(
                new ERC1967Proxy(
                    address(poolImpl),
                    abi.encodeCall(LendingPoolCore.initialize, (owner, address(priceOracle)))
                )
            )
        );

        // Deploy lending tokens
        dUSDC = _deployLendingToken(address(usdc), "DeFi USDC", "dUSDC");
        dWETH = _deployLendingToken(address(weth), "DeFi WETH", "dWETH");

        // Initialize reserves
        vm.startPrank(owner);
        lendingPool.initReserve(
            address(usdc),
            address(dUSDC),
            address(interestRateModel),
            0.75e18, // 75% collateral factor
            0.8e18,  // 80% liquidation threshold
            1.05e18  // 5% liquidation bonus
        );
        lendingPool.initReserve(
            address(weth),
            address(dWETH),
            address(interestRateModel),
            0.8e18,  // 80% collateral factor
            0.85e18, // 85% liquidation threshold
            1.05e18  // 5% liquidation bonus
        );
        vm.stopPrank();

        // Setup users
        _setupUser(user1);
        _setupUser(user2);
        _setupUser(liquidator);
    }

    function _deployLendingToken(
        address underlying,
        string memory name,
        string memory symbol
    ) internal returns (LendingToken) {
        LendingToken impl = new LendingToken();
        return LendingToken(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        LendingToken.initialize,
                        (underlying, address(lendingPool), address(interestRateModel), 1e18, name, symbol, owner)
                    )
                )
            )
        );
    }

    function _setupUser(address user) internal {
        usdc.mint(user, INITIAL_BALANCE);
        weth.mint(user, INITIAL_BALANCE);

        vm.startPrank(user);
        usdc.approve(address(dUSDC), type(uint256).max);
        weth.approve(address(dWETH), type(uint256).max);
        usdc.approve(address(lendingPool), type(uint256).max);
        weth.approve(address(lendingPool), type(uint256).max);
        vm.stopPrank();
    }

    function test_Initialization() public view {
        assertEq(lendingPool.version(), 1);
        assertEq(lendingPool.getPriceOracle(), address(priceOracle));
        assertEq(lendingPool.paused(), false);
        assertEq(lendingPool.closeFactor(), 0.5e18);
    }

    function test_InitReserve() public view {
        (uint256 collateralFactor, uint256 liquidationThreshold, uint256 liquidationBonus, bool isActive) =
            lendingPool.getReserveConfiguration(address(usdc));

        assertEq(collateralFactor, 0.75e18);
        assertEq(liquidationThreshold, 0.8e18);
        assertEq(liquidationBonus, 1.05e18);
        assertTrue(isActive);

        assertEq(lendingPool.getLendingToken(address(usdc)), address(dUSDC));
    }

    function test_Deposit() public {
        uint256 depositAmount = 1000e18;

        vm.prank(user1);
        uint256 minted = lendingPool.deposit(address(usdc), depositAmount, user1);

        assertEq(minted, depositAmount);
        assertEq(dUSDC.balanceOf(user1), depositAmount);
    }

    function test_Deposit_OnBehalfOf() public {
        uint256 depositAmount = 1000e18;

        vm.prank(user1);
        uint256 minted = lendingPool.deposit(address(usdc), depositAmount, user2);

        assertEq(dUSDC.balanceOf(user2), depositAmount);
        assertEq(dUSDC.balanceOf(user1), 0);
    }

    function test_Withdraw() public {
        // Deposit first
        vm.prank(user1);
        lendingPool.deposit(address(usdc), 1000e18, user1);

        // Withdraw
        vm.prank(user1);
        uint256 withdrawn = lendingPool.withdraw(address(usdc), 500e18, user1);

        assertEq(withdrawn, 500e18);
        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE - 500e18);
    }

    function test_Withdraw_MaxAmount() public {
        vm.prank(user1);
        lendingPool.deposit(address(usdc), 1000e18, user1);

        vm.prank(user1);
        uint256 withdrawn = lendingPool.withdraw(address(usdc), type(uint256).max, user1);

        assertEq(withdrawn, 1000e18);
        assertEq(dUSDC.balanceOf(user1), 0);
    }

    function test_Borrow() public {
        // User1 deposits WETH as collateral
        vm.prank(user1);
        lendingPool.deposit(address(weth), 10e18, user1); // 10 WETH = $20,000

        // User2 deposits USDC for liquidity
        vm.prank(user2);
        lendingPool.deposit(address(usdc), 5000e18, user2);

        // User1 borrows USDC
        uint256 borrowAmount = 1000e18; // $1000

        vm.prank(user1);
        lendingPool.borrow(address(usdc), borrowAmount, user1);

        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE + borrowAmount);
        assertEq(dUSDC.borrowBalanceStored(user1), borrowAmount);
    }

    function test_Borrow_InsufficientCollateral() public {
        // User1 deposits small amount
        vm.prank(user1);
        lendingPool.deposit(address(usdc), 100e18, user1);

        // User2 provides liquidity
        vm.prank(user2);
        lendingPool.deposit(address(usdc), 5000e18, user2);

        // Try to borrow too much
        vm.prank(user1);
        vm.expectRevert(Errors.InsufficientCollateral.selector);
        lendingPool.borrow(address(usdc), 1000e18, user1);
    }

    function test_Repay() public {
        // Setup: deposit and borrow
        vm.prank(user1);
        lendingPool.deposit(address(weth), 10e18, user1);

        vm.prank(user2);
        lendingPool.deposit(address(usdc), 5000e18, user2);

        vm.prank(user1);
        lendingPool.borrow(address(usdc), 1000e18, user1);

        // Repay
        vm.prank(user1);
        uint256 repaid = lendingPool.repay(address(usdc), 500e18, user1);

        assertEq(repaid, 500e18);
        assertEq(dUSDC.borrowBalanceStored(user1), 500e18);
    }

    function test_Repay_FullDebt() public {
        vm.prank(user1);
        lendingPool.deposit(address(weth), 10e18, user1);

        vm.prank(user2);
        lendingPool.deposit(address(usdc), 5000e18, user2);

        vm.prank(user1);
        lendingPool.borrow(address(usdc), 1000e18, user1);

        vm.prank(user1);
        uint256 repaid = lendingPool.repay(address(usdc), type(uint256).max, user1);

        assertEq(repaid, 1000e18);
        assertEq(dUSDC.borrowBalanceStored(user1), 0);
    }

    function test_GetUserAccountData() public {
        // Deposit WETH
        vm.prank(user1);
        lendingPool.deposit(address(weth), 1e18, user1); // 1 WETH = $2000

        (
            uint256 totalCollateral,
            uint256 totalDebt,
            uint256 availableBorrows,
            uint256 liquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = lendingPool.getUserAccountData(user1);

        // 1 WETH at $2000 = $2000 collateral value
        assertGt(totalCollateral, 0);
        assertEq(totalDebt, 0);
        assertGt(availableBorrows, 0);
        assertEq(healthFactor, type(uint256).max); // No debt
    }

    function test_Liquidate() public {
        // User1 deposits WETH as collateral
        vm.prank(user1);
        lendingPool.deposit(address(weth), 1e18, user1); // 1 WETH = $2000

        // User2 deposits USDC for liquidity
        vm.prank(user2);
        lendingPool.deposit(address(usdc), 5000e18, user2);

        // User1 borrows USDC (close to max)
        vm.prank(user1);
        lendingPool.borrow(address(usdc), 1500e18, user1); // $1500 debt against $2000 * 0.8 = $1600 max

        // Drop WETH price to make position liquidatable
        wethPriceFeed.setPrice(1500e8); // WETH drops to $1500

        // Check user is liquidatable
        (, , , , , uint256 healthFactor) = lendingPool.getUserAccountData(user1);
        assertLt(healthFactor, 1e18);

        // Liquidator repays debt and seizes collateral
        vm.prank(liquidator);
        uint256 collateralSeized = lendingPool.liquidate(address(weth), address(usdc), user1, 750e18);

        // Should have seized some WETH
        assertGt(collateralSeized, 0);
    }

    function test_Liquidate_NotLiquidatable() public {
        // User1 deposits WETH
        vm.prank(user1);
        lendingPool.deposit(address(weth), 10e18, user1);

        // User2 deposits USDC
        vm.prank(user2);
        lendingPool.deposit(address(usdc), 5000e18, user2);

        // User1 borrows conservatively
        vm.prank(user1);
        lendingPool.borrow(address(usdc), 1000e18, user1);

        // Try to liquidate healthy position
        vm.prank(liquidator);
        vm.expectRevert(Errors.NotLiquidatable.selector);
        lendingPool.liquidate(address(weth), address(usdc), user1, 500e18);
    }

    function test_Liquidate_SelfLiquidation() public {
        vm.prank(user1);
        lendingPool.deposit(address(weth), 1e18, user1);

        vm.prank(user2);
        lendingPool.deposit(address(usdc), 5000e18, user2);

        vm.prank(user1);
        lendingPool.borrow(address(usdc), 1500e18, user1);

        wethPriceFeed.setPrice(1500e8);

        vm.prank(user1);
        vm.expectRevert(Errors.SelfLiquidation.selector);
        lendingPool.liquidate(address(weth), address(usdc), user1, 500e18);
    }

    function test_SetUserUseReserveAsCollateral() public {
        vm.prank(user1);
        lendingPool.deposit(address(usdc), 1000e18, user1);

        // Disable as collateral
        vm.prank(user1);
        lendingPool.setUserUseReserveAsCollateral(address(usdc), false);

        // Check available borrows should be 0
        (, , uint256 availableBorrows, , , ) = lendingPool.getUserAccountData(user1);
        assertEq(availableBorrows, 0);
    }

    function test_Pause() public {
        vm.prank(owner);
        lendingPool.setPaused(true);

        assertTrue(lendingPool.paused());

        vm.prank(user1);
        vm.expectRevert(Errors.Paused.selector);
        lendingPool.deposit(address(usdc), 1000e18, user1);
    }

    function test_GetReservesList() public view {
        address[] memory reserves = lendingPool.getReservesList();
        assertEq(reserves.length, 2);
        assertEq(reserves[0], address(usdc));
        assertEq(reserves[1], address(weth));
    }

    function testFuzz_DepositWithdraw(uint256 amount) public {
        vm.assume(amount > 0 && amount <= INITIAL_BALANCE);

        vm.prank(user1);
        lendingPool.deposit(address(usdc), amount, user1);

        vm.prank(user1);
        lendingPool.withdraw(address(usdc), amount, user1);

        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE);
    }
}
