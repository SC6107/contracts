// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LendingToken} from "../../src/lending/LendingToken.sol";
import {JumpRateModel} from "../../src/lending/JumpRateModel.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {WadRayMath} from "../../src/libraries/WadRayMath.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract LendingTokenTest is Test {
    using WadRayMath for uint256;

    LendingToken public lendingToken;
    MockERC20 public underlying;
    JumpRateModel public interestRateModel;

    address public owner = address(1);
    address public lendingPool = address(2);
    address public user1 = address(3);
    address public user2 = address(4);

    uint256 constant INITIAL_EXCHANGE_RATE = 1e18;
    uint256 constant INITIAL_BALANCE = 10000e18;

    function setUp() public {
        // Deploy underlying token
        underlying = new MockERC20("USD Coin", "USDC", 18);

        // Deploy interest rate model
        interestRateModel = new JumpRateModel(
            0.02e18, // 2% base rate
            0.1e18,  // 10% multiplier
            1e18,    // 100% jump multiplier
            0.8e18   // 80% kink
        );

        // Deploy LendingToken
        LendingToken impl = new LendingToken();
        lendingToken = LendingToken(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        LendingToken.initialize,
                        (
                            address(underlying),
                            lendingPool,
                            address(interestRateModel),
                            INITIAL_EXCHANGE_RATE,
                            "DeFi USDC",
                            "dUSDC",
                            owner
                        )
                    )
                )
            )
        );

        // Setup users with tokens
        underlying.mint(user1, INITIAL_BALANCE);
        underlying.mint(user2, INITIAL_BALANCE);

        vm.prank(user1);
        underlying.approve(address(lendingToken), type(uint256).max);

        vm.prank(user2);
        underlying.approve(address(lendingToken), type(uint256).max);
    }

    function test_Initialization() public view {
        assertEq(lendingToken.name(), "DeFi USDC");
        assertEq(lendingToken.symbol(), "dUSDC");
        assertEq(lendingToken.underlying(), address(underlying));
        assertEq(lendingToken.lendingPool(), lendingPool);
        assertEq(lendingToken.interestRateModel(), address(interestRateModel));
        assertEq(lendingToken.exchangeRateStored(), INITIAL_EXCHANGE_RATE);
        assertEq(lendingToken.version(), 1);
        assertEq(lendingToken.reserveFactorMantissa(), 0.1e18); // 10% default
    }

    function test_Mint() public {
        uint256 mintAmount = 1000e18;

        vm.prank(lendingPool);
        uint256 mintedTokens = lendingToken.mint(user1, user1, mintAmount);

        // At 1:1 exchange rate, should mint equal dTokens
        assertEq(mintedTokens, mintAmount);
        assertEq(lendingToken.balanceOf(user1), mintAmount);
        assertEq(underlying.balanceOf(address(lendingToken)), mintAmount);
    }

    function test_Mint_OnlyLendingPool() public {
        vm.prank(user1);
        vm.expectRevert(Errors.OnlyLendingPool.selector);
        lendingToken.mint(user1, user1, 1000e18);
    }

    function test_Redeem() public {
        uint256 mintAmount = 1000e18;

        // First mint
        vm.prank(lendingPool);
        lendingToken.mint(user1, user1, mintAmount);

        // Then redeem half
        uint256 redeemTokens = 500e18;

        vm.prank(lendingPool);
        uint256 underlyingReturned = lendingToken.redeem(user1, user1, redeemTokens);

        assertEq(underlyingReturned, redeemTokens); // 1:1 exchange rate
        assertEq(lendingToken.balanceOf(user1), mintAmount - redeemTokens);
    }

    function test_RedeemUnderlying() public {
        uint256 mintAmount = 1000e18;

        vm.prank(lendingPool);
        lendingToken.mint(user1, user1, mintAmount);

        // Redeem specific underlying amount
        uint256 redeemAmount = 300e18;

        vm.prank(lendingPool);
        uint256 tokensBurned = lendingToken.redeemUnderlying(user1, user1, redeemAmount);

        assertEq(tokensBurned, redeemAmount); // 1:1 exchange rate
        assertEq(lendingToken.balanceOf(user1), mintAmount - tokensBurned);
    }

    function test_Borrow() public {
        // First provide liquidity
        vm.prank(lendingPool);
        lendingToken.mint(user1, user1, 1000e18);

        // Borrow
        uint256 borrowAmount = 500e18;
        vm.prank(lendingPool);
        lendingToken.borrow(user2, borrowAmount);

        assertEq(lendingToken.borrowBalanceStored(user2), borrowAmount);
        assertEq(lendingToken.totalBorrows(), borrowAmount);
        assertEq(underlying.balanceOf(user2), INITIAL_BALANCE + borrowAmount);
    }

    function test_Borrow_InsufficientLiquidity() public {
        vm.prank(lendingPool);
        lendingToken.mint(user1, user1, 100e18);

        vm.prank(lendingPool);
        vm.expectRevert(Errors.InsufficientLiquidity.selector);
        lendingToken.borrow(user2, 200e18);
    }

    function test_RepayBorrow() public {
        // Setup: mint and borrow
        vm.prank(lendingPool);
        lendingToken.mint(user1, user1, 1000e18);

        vm.prank(lendingPool);
        lendingToken.borrow(user2, 500e18);

        // Repay
        uint256 repayAmount = 200e18;
        vm.prank(lendingPool);
        uint256 actualRepaid = lendingToken.repayBorrow(user2, user2, repayAmount);

        assertEq(actualRepaid, repayAmount);
        assertEq(lendingToken.borrowBalanceStored(user2), 500e18 - repayAmount);
    }

    function test_RepayBorrow_FullDebt() public {
        vm.prank(lendingPool);
        lendingToken.mint(user1, user1, 1000e18);

        vm.prank(lendingPool);
        lendingToken.borrow(user2, 500e18);

        // Repay full debt using max uint
        vm.prank(lendingPool);
        uint256 actualRepaid = lendingToken.repayBorrow(user2, user2, type(uint256).max);

        assertEq(actualRepaid, 500e18);
        assertEq(lendingToken.borrowBalanceStored(user2), 0);
    }

    function test_AccrueInterest() public {
        // Mint and borrow
        vm.prank(lendingPool);
        lendingToken.mint(user1, user1, 1000e18);

        vm.prank(lendingPool);
        lendingToken.borrow(user2, 500e18);

        uint256 totalBorrowsBefore = lendingToken.totalBorrows();

        // Advance time
        vm.warp(block.timestamp + 365 days);

        // Accrue interest
        lendingToken.accrueInterest();

        uint256 totalBorrowsAfter = lendingToken.totalBorrows();

        // Interest should have accrued
        assertGt(totalBorrowsAfter, totalBorrowsBefore);
    }

    function test_ExchangeRateGrows() public {
        // Mint tokens
        vm.prank(lendingPool);
        lendingToken.mint(user1, user1, 1000e18);

        // Borrow tokens
        vm.prank(lendingPool);
        lendingToken.borrow(user2, 500e18);

        uint256 exchangeRateBefore = lendingToken.exchangeRateStored();

        // Advance time for interest to accrue
        vm.warp(block.timestamp + 365 days);
        lendingToken.accrueInterest();

        uint256 exchangeRateAfter = lendingToken.exchangeRateStored();

        // Exchange rate should increase as interest accrues
        assertGt(exchangeRateAfter, exchangeRateBefore);
    }

    function test_BorrowBalanceGrows() public {
        vm.prank(lendingPool);
        lendingToken.mint(user1, user1, 1000e18);

        vm.prank(lendingPool);
        lendingToken.borrow(user2, 500e18);

        uint256 borrowBefore = lendingToken.borrowBalanceStored(user2);

        // Advance time
        vm.warp(block.timestamp + 365 days);

        // Get current balance (which accrues interest)
        vm.prank(lendingPool);
        uint256 borrowAfter = lendingToken.borrowBalanceCurrent(user2);

        assertGt(borrowAfter, borrowBefore);
    }

    function test_SetReserveFactor() public {
        uint256 newReserveFactor = 0.2e18; // 20%

        vm.prank(owner);
        lendingToken.setReserveFactor(newReserveFactor);

        assertEq(lendingToken.reserveFactorMantissa(), newReserveFactor);
    }

    function test_SetReserveFactor_InvalidValue() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidReserveFactor.selector);
        lendingToken.setReserveFactor(1.1e18); // > 100%
    }

    function test_SetInterestRateModel() public {
        JumpRateModel newModel = new JumpRateModel(0.03e18, 0.15e18, 1.5e18, 0.75e18);

        vm.prank(owner);
        lendingToken.setInterestRateModel(address(newModel));

        assertEq(lendingToken.interestRateModel(), address(newModel));
    }

    function test_Seize() public {
        // Mint tokens to user1
        vm.prank(lendingPool);
        lendingToken.mint(user1, user1, 1000e18);

        uint256 seizeTokens = 100e18;

        // Seize tokens (simulating liquidation)
        vm.prank(lendingPool);
        lendingToken.seize(user2, user1, seizeTokens);

        assertEq(lendingToken.balanceOf(user1), 900e18);
        assertEq(lendingToken.balanceOf(user2), 100e18);
    }

    function test_GetCash() public {
        vm.prank(lendingPool);
        lendingToken.mint(user1, user1, 1000e18);

        assertEq(lendingToken.getCash(), 1000e18);

        vm.prank(lendingPool);
        lendingToken.borrow(user2, 300e18);

        assertEq(lendingToken.getCash(), 700e18);
    }

    function testFuzz_MintRedeem(uint256 amount) public {
        vm.assume(amount > 0 && amount <= INITIAL_BALANCE);

        vm.prank(lendingPool);
        uint256 minted = lendingToken.mint(user1, user1, amount);

        vm.prank(lendingPool);
        uint256 redeemed = lendingToken.redeem(user1, user1, minted);

        // Should get back original amount (no interest accrued yet)
        assertEq(redeemed, amount);
        assertEq(lendingToken.balanceOf(user1), 0);
    }
}
