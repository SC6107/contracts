// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Comptroller} from "../../src/lending/Comptroller.sol";
import {LendingToken} from "../../src/lending/LendingToken.sol";
import {PriceOracle} from "../../src/oracle/PriceOracle.sol";
import {JumpRateModel} from "../../src/lending/JumpRateModel.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockPriceFeed} from "../mocks/MockPriceFeed.sol";
import {WadRayMath} from "../../src/libraries/WadRayMath.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract ComptrollerTest is Test {
    using WadRayMath for uint256;

    Comptroller public comptroller;
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
        priceOracle = PriceOracle(
            address(
                new ERC1967Proxy(
                    address(new PriceOracle()),
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

        // Deploy comptroller
        comptroller = Comptroller(
            address(
                new ERC1967Proxy(
                    address(new Comptroller()),
                    abi.encodeCall(Comptroller.initialize, (owner, address(priceOracle)))
                )
            )
        );

        // Deploy lending tokens
        dUSDC = _deployLendingToken(address(usdc), "DeFi USDC", "dUSDC");
        dWETH = _deployLendingToken(address(weth), "DeFi WETH", "dWETH");

        // List markets
        vm.startPrank(owner);
        comptroller.supportMarket(address(dUSDC), 0.75e18); // 75% collateral factor
        comptroller.supportMarket(address(dWETH), 0.8e18); // 80% collateral factor
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
                        (underlying, address(comptroller), address(interestRateModel), 1e18, name, symbol, owner)
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
        vm.stopPrank();
    }

    function test_Initialization() public view {
        assertEq(comptroller.version(), 1);
        assertEq(comptroller.getPriceOracle(), address(priceOracle));
        assertEq(comptroller.paused(), false);
        assertEq(comptroller.closeFactorMantissa(), 0.5e18);
        assertEq(comptroller.liquidationIncentiveMantissa(), 1.05e18);
    }

    function test_SupportMarket() public view {
        (uint256 collateralFactor, bool isListed) = comptroller.getMarketConfiguration(address(dUSDC));
        assertEq(collateralFactor, 0.75e18);
        assertTrue(isListed);

        address[] memory markets = comptroller.getAllMarkets();
        assertEq(markets.length, 2);
    }

    function test_Mint() public {
        uint256 mintAmount = 1000e18;

        vm.prank(user1);
        uint256 minted = dUSDC.mint(mintAmount);

        assertEq(minted, mintAmount);
        assertEq(dUSDC.balanceOf(user1), mintAmount);
    }

    function test_Redeem() public {
        vm.prank(user1);
        dUSDC.mint(1000e18);

        vm.prank(user1);
        uint256 redeemed = dUSDC.redeem(500e18);

        assertEq(redeemed, 500e18);
        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE - 500e18);
    }

    function test_Borrow() public {
        // User1 deposits WETH as collateral
        vm.startPrank(user1);
        dWETH.mint(10e18); // 10 WETH = $20,000
        address[] memory markets = new address[](1);
        markets[0] = address(dWETH);
        comptroller.enterMarkets(markets);
        vm.stopPrank();

        // User2 deposits USDC for liquidity
        vm.prank(user2);
        dUSDC.mint(5000e18);

        // User1 borrows USDC
        uint256 borrowAmount = 1000e18; // $1000
        vm.prank(user1);
        dUSDC.borrow(borrowAmount);

        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE + borrowAmount);
        assertEq(dUSDC.borrowBalanceStored(user1), borrowAmount);
    }

    function test_Borrow_InsufficientCollateral() public {
        // User1 deposits small amount
        vm.startPrank(user1);
        dUSDC.mint(100e18);
        address[] memory markets = new address[](1);
        markets[0] = address(dUSDC);
        comptroller.enterMarkets(markets);
        vm.stopPrank();

        // User2 provides liquidity
        vm.prank(user2);
        dUSDC.mint(5000e18);

        // Try to borrow too much
        vm.prank(user1);
        vm.expectRevert(Errors.InsufficientCollateral.selector);
        dUSDC.borrow(1000e18);
    }

    function test_Repay() public {
        // Setup: deposit and borrow
        vm.startPrank(user1);
        dWETH.mint(10e18);
        address[] memory markets = new address[](1);
        markets[0] = address(dWETH);
        comptroller.enterMarkets(markets);
        vm.stopPrank();

        vm.prank(user2);
        dUSDC.mint(5000e18);

        vm.prank(user1);
        dUSDC.borrow(1000e18);

        // Repay
        vm.prank(user1);
        uint256 repaid = dUSDC.repayBorrow(500e18);

        assertEq(repaid, 500e18);
        assertEq(dUSDC.borrowBalanceStored(user1), 500e18);
    }

    function test_Repay_FullDebt() public {
        vm.startPrank(user1);
        dWETH.mint(10e18);
        address[] memory markets = new address[](1);
        markets[0] = address(dWETH);
        comptroller.enterMarkets(markets);
        vm.stopPrank();

        vm.prank(user2);
        dUSDC.mint(5000e18);

        vm.prank(user1);
        dUSDC.borrow(1000e18);

        vm.prank(user1);
        uint256 repaid = dUSDC.repayBorrow(type(uint256).max);

        assertEq(repaid, 1000e18);
        assertEq(dUSDC.borrowBalanceStored(user1), 0);
    }

    function test_GetAccountLiquidity() public {
        vm.startPrank(user1);
        dWETH.mint(1e18); // 1 WETH = $2000
        address[] memory markets = new address[](1);
        markets[0] = address(dWETH);
        comptroller.enterMarkets(markets);
        vm.stopPrank();

        (uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(user1);

        assertGt(liquidity, 0);
        assertEq(shortfall, 0);
    }

    function test_Liquidate() public {
        // User1 deposits WETH as collateral
        vm.startPrank(user1);
        dWETH.mint(1e18); // 1 WETH = $2000
        address[] memory markets = new address[](1);
        markets[0] = address(dWETH);
        comptroller.enterMarkets(markets);
        vm.stopPrank();

        // User2 deposits USDC for liquidity
        vm.prank(user2);
        dUSDC.mint(5000e18);

        // User1 borrows USDC (close to max)
        vm.prank(user1);
        dUSDC.borrow(1500e18); // $1500 debt against $2000 * 0.8 = $1600 max

        // Drop WETH price to make position liquidatable
        wethPriceFeed.setPrice(1500e8); // WETH drops to $1500

        // Check user has shortfall
        (, uint256 shortfall) = comptroller.getAccountLiquidity(user1);
        assertGt(shortfall, 0);

        // Liquidator repays debt and seizes collateral
        vm.prank(liquidator);
        uint256 seized = dUSDC.liquidateBorrow(user1, 750e18, address(dWETH));

        assertGt(seized, 0);
    }

    function test_Liquidate_NotLiquidatable() public {
        // User1 deposits WETH
        vm.startPrank(user1);
        dWETH.mint(10e18);
        address[] memory markets = new address[](1);
        markets[0] = address(dWETH);
        comptroller.enterMarkets(markets);
        vm.stopPrank();

        // User2 deposits USDC
        vm.prank(user2);
        dUSDC.mint(5000e18);

        // User1 borrows conservatively
        vm.prank(user1);
        dUSDC.borrow(1000e18);

        // Try to liquidate healthy position
        vm.prank(liquidator);
        vm.expectRevert(Errors.NotLiquidatable.selector);
        dUSDC.liquidateBorrow(user1, 500e18, address(dWETH));
    }

    function test_Liquidate_SelfLiquidation() public {
        vm.startPrank(user1);
        dWETH.mint(1e18);
        address[] memory markets = new address[](1);
        markets[0] = address(dWETH);
        comptroller.enterMarkets(markets);
        vm.stopPrank();

        vm.prank(user2);
        dUSDC.mint(5000e18);

        vm.prank(user1);
        dUSDC.borrow(1500e18);

        wethPriceFeed.setPrice(1500e8);

        vm.prank(user1);
        vm.expectRevert(Errors.SelfLiquidation.selector);
        dUSDC.liquidateBorrow(user1, 500e18, address(dWETH));
    }

    function test_EnterExitMarket() public {
        vm.startPrank(user1);
        dUSDC.mint(1000e18);
        address[] memory markets = new address[](1);
        markets[0] = address(dUSDC);
        comptroller.enterMarkets(markets);
        comptroller.exitMarket(address(dUSDC));
        vm.stopPrank();
    }

    function test_Pause() public {
        vm.prank(owner);
        comptroller.setPaused(true);

        assertTrue(comptroller.paused());

        vm.prank(user1);
        vm.expectRevert(Errors.Paused.selector);
        dUSDC.mint(1000e18);
    }

    function test_GetAllMarkets() public view {
        address[] memory markets = comptroller.getAllMarkets();
        assertEq(markets.length, 2);
        assertEq(markets[0], address(dUSDC));
        assertEq(markets[1], address(dWETH));
    }

    function testFuzz_MintRedeem(uint256 amount) public {
        vm.assume(amount > 0 && amount <= INITIAL_BALANCE);

        vm.prank(user1);
        dUSDC.mint(amount);

        vm.prank(user1);
        dUSDC.redeem(amount);

        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE);
    }
}
