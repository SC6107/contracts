// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {LendingToken} from "../../src/lending/LendingToken.sol";
import {Comptroller} from "../../src/lending/Comptroller.sol";
import {PriceOracle} from "../../src/oracle/PriceOracle.sol";
import {JumpRateModel} from "../../src/lending/JumpRateModel.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockPriceFeed} from "../mocks/MockPriceFeed.sol";
import {WadRayMath} from "../../src/libraries/WadRayMath.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract LendingTokenTest is Test {
    using WadRayMath for uint256;

    LendingToken public lendingToken;
    Comptroller public comptroller;
    PriceOracle public priceOracle;
    MockERC20 public underlying;
    MockPriceFeed public priceFeed;
    JumpRateModel public interestRateModel;

    address public owner = address(1);
    address public user1 = address(3);
    address public user2 = address(4);

    uint256 constant INITIAL_EXCHANGE_RATE = 1e18;
    uint256 constant INITIAL_BALANCE = 10000e18;
    uint256 constant UNDERLYING_PRICE = 1e8;

    function setUp() public {
        // Deploy underlying token
        underlying = new MockERC20("USD Coin", "USDC", 18);

        // Deploy price feed + oracle
        priceFeed = new MockPriceFeed(int256(UNDERLYING_PRICE), 8);
        priceOracle = PriceOracle(
            address(
                new ERC1967Proxy(
                    address(new PriceOracle()),
                    abi.encodeCall(PriceOracle.initialize, (owner))
                )
            )
        );

        vm.prank(owner);
        priceOracle.setAssetSource(address(underlying), address(priceFeed));

        // Deploy comptroller
        comptroller = Comptroller(
            address(
                new ERC1967Proxy(
                    address(new Comptroller()),
                    abi.encodeCall(Comptroller.initialize, (owner, address(priceOracle)))
                )
            )
        );

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
                            address(comptroller),
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

        vm.prank(owner);
        comptroller.supportMarket(address(lendingToken), 0.75e18);

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
        assertEq(lendingToken.comptroller(), address(comptroller));
        assertEq(lendingToken.interestRateModel(), address(interestRateModel));
        assertEq(lendingToken.exchangeRateStored(), INITIAL_EXCHANGE_RATE);
        assertEq(lendingToken.version(), 1);
        assertEq(lendingToken.reserveFactorMantissa(), 0.1e18); // 10% default
    }

    function test_Mint() public {
        uint256 mintAmount = 1000e18;

        vm.prank(user1);
        uint256 mintedTokens = lendingToken.mint(mintAmount);

        // At 1:1 exchange rate, should mint equal cTokens
        assertEq(mintedTokens, mintAmount);
        assertEq(lendingToken.balanceOf(user1), mintAmount);
        assertEq(underlying.balanceOf(address(lendingToken)), mintAmount);
    }

    function test_Redeem() public {
        uint256 mintAmount = 1000e18;

        vm.prank(user1);
        lendingToken.mint(mintAmount);

        // Then redeem half
        uint256 redeemTokens = 500e18;

        vm.prank(user1);
        uint256 underlyingReturned = lendingToken.redeem(redeemTokens);

        assertEq(underlyingReturned, redeemTokens); // 1:1 exchange rate
        assertEq(lendingToken.balanceOf(user1), mintAmount - redeemTokens);
    }

    function test_RedeemUnderlying() public {
        uint256 mintAmount = 1000e18;

        vm.prank(user1);
        lendingToken.mint(mintAmount);

        // Redeem specific underlying amount
        uint256 redeemAmount = 300e18;

        vm.prank(user1);
        uint256 tokensBurned = lendingToken.redeemUnderlying(redeemAmount);

        assertEq(tokensBurned, redeemAmount); // 1:1 exchange rate
        assertEq(lendingToken.balanceOf(user1), mintAmount - tokensBurned);
    }

    function test_Borrow() public {
        // Provide liquidity
        uint256 mintAmount = 1000e18;
        vm.prank(user1);
        lendingToken.mint(mintAmount);

        // User2 supplies collateral and enters market
        vm.startPrank(user2);
        lendingToken.mint(mintAmount);
        address[] memory markets = new address[](1);
        markets[0] = address(lendingToken);
        comptroller.enterMarkets(markets);
        vm.stopPrank();

        // Borrow
        uint256 borrowAmount = 500e18;
        vm.prank(user2);
        lendingToken.borrow(borrowAmount);

        assertEq(lendingToken.borrowBalanceStored(user2), borrowAmount);
        assertEq(lendingToken.totalBorrows(), borrowAmount);
        assertEq(underlying.balanceOf(user2), INITIAL_BALANCE - mintAmount + borrowAmount);
    }

    function test_Borrow_InsufficientCollateral() public {
        // Provide liquidity
        vm.prank(user1);
        lendingToken.mint(1000e18);

        // User2 supplies small collateral and enters market
        vm.startPrank(user2);
        lendingToken.mint(100e18);
        address[] memory markets = new address[](1);
        markets[0] = address(lendingToken);
        comptroller.enterMarkets(markets);
        vm.expectRevert(Errors.InsufficientCollateral.selector);
        lendingToken.borrow(500e18);
        vm.stopPrank();
    }

    function test_RepayBorrow() public {
        // Setup: mint and borrow
        vm.prank(user1);
        lendingToken.mint(1000e18);

        vm.startPrank(user2);
        lendingToken.mint(1000e18);
        address[] memory markets = new address[](1);
        markets[0] = address(lendingToken);
        comptroller.enterMarkets(markets);
        lendingToken.borrow(500e18);

        // Repay
        uint256 repayAmount = 200e18;
        uint256 actualRepaid = lendingToken.repayBorrow(repayAmount);
        vm.stopPrank();

        assertEq(actualRepaid, repayAmount);
        assertEq(lendingToken.borrowBalanceStored(user2), 500e18 - repayAmount);
    }

    function test_RepayBorrow_FullDebt() public {
        vm.prank(user1);
        lendingToken.mint(1000e18);

        vm.startPrank(user2);
        lendingToken.mint(1000e18);
        address[] memory markets = new address[](1);
        markets[0] = address(lendingToken);
        comptroller.enterMarkets(markets);
        lendingToken.borrow(500e18);

        uint256 actualRepaid = lendingToken.repayBorrow(type(uint256).max);
        vm.stopPrank();

        assertEq(actualRepaid, 500e18);
        assertEq(lendingToken.borrowBalanceStored(user2), 0);
    }

    function test_AccrueInterest() public {
        // Mint and borrow
        vm.prank(user1);
        lendingToken.mint(1000e18);

        vm.startPrank(user2);
        lendingToken.mint(1000e18);
        address[] memory markets = new address[](1);
        markets[0] = address(lendingToken);
        comptroller.enterMarkets(markets);
        lendingToken.borrow(500e18);
        vm.stopPrank();

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
        vm.prank(user1);
        lendingToken.mint(1000e18);

        // Borrow tokens
        vm.startPrank(user2);
        lendingToken.mint(1000e18);
        address[] memory markets = new address[](1);
        markets[0] = address(lendingToken);
        comptroller.enterMarkets(markets);
        lendingToken.borrow(500e18);
        vm.stopPrank();

        uint256 exchangeRateBefore = lendingToken.exchangeRateStored();

        // Advance time for interest to accrue
        vm.warp(block.timestamp + 365 days);
        lendingToken.accrueInterest();

        uint256 exchangeRateAfter = lendingToken.exchangeRateStored();

        // Exchange rate should increase as interest accrues
        assertGt(exchangeRateAfter, exchangeRateBefore);
    }

    function test_BorrowBalanceGrows() public {
        vm.prank(user1);
        lendingToken.mint(1000e18);

        vm.startPrank(user2);
        lendingToken.mint(1000e18);
        address[] memory markets = new address[](1);
        markets[0] = address(lendingToken);
        comptroller.enterMarkets(markets);
        lendingToken.borrow(500e18);
        vm.stopPrank();

        uint256 borrowBefore = lendingToken.borrowBalanceStored(user2);

        // Advance time
        vm.warp(block.timestamp + 365 days);

        // Get current balance (which accrues interest)
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
        vm.prank(user1);
        lendingToken.mint(1000e18);

        uint256 seizeTokens = 100e18;

        // Seize tokens (simulating liquidation)
        vm.prank(address(lendingToken));
        lendingToken.seize(user2, user1, seizeTokens);

        assertEq(lendingToken.balanceOf(user1), 900e18);
        assertEq(lendingToken.balanceOf(user2), 100e18);
    }

    function test_GetCash() public {
        vm.prank(user1);
        lendingToken.mint(1000e18);

        assertEq(lendingToken.getCash(), 1000e18);

        vm.startPrank(user2);
        lendingToken.mint(1000e18);
        address[] memory markets = new address[](1);
        markets[0] = address(lendingToken);
        comptroller.enterMarkets(markets);
        lendingToken.borrow(300e18);
        vm.stopPrank();

        assertEq(lendingToken.getCash(), 1700e18);
    }

    function testFuzz_MintRedeem(uint256 amount) public {
        vm.assume(amount > 0 && amount <= INITIAL_BALANCE);

        vm.prank(user1);
        uint256 minted = lendingToken.mint(amount);

        vm.prank(user1);
        uint256 redeemed = lendingToken.redeem(minted);

        // Should get back original amount (no interest accrued yet)
        assertEq(redeemed, amount);
        assertEq(lendingToken.balanceOf(user1), 0);
    }
}
