// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {LendingToken} from "../src/lending/LendingToken.sol";
import {Comptroller} from "../src/lending/Comptroller.sol";

contract ReproFullLendingLifecycle is Script {
    function run() external {
        uint256 adminPk = vm.envUint("ADMIN_PK");
        uint256 alicePk = vm.envUint("ALICE_PK");
        uint256 bobPk = vm.envUint("BOB_PK");
        address admin = vm.addr(adminPk);
        address alice = vm.addr(alicePk);
        address bob = vm.addr(bobPk);

        address comptrollerAddr = vm.envAddress("COMPTROLLER");
        address usdcAddr = vm.envAddress("USDC");
        address wethAddr = vm.envAddress("WETH");
        address dUsdcAddr = vm.envAddress("DUSDC");
        address dWethAddr = vm.envAddress("DWETH");

        Comptroller comptroller = Comptroller(comptrollerAddr);
        MockERC20 usdc = MockERC20(usdcAddr);
        MockERC20 weth = MockERC20(wethAddr);
        LendingToken dUSDC = LendingToken(dUsdcAddr);
        LendingToken dWETH = LendingToken(dWethAddr);

        // Ensure Alice and Bob have ETH for gas
        vm.startBroadcast(adminPk);
        _sendEth(admin, alice, 10 ether);
        _sendEth(admin, bob, 10 ether);
        vm.stopBroadcast();

        // Ensure Alice and Bob have balances (mock tokens are unrestricted)
        vm.startBroadcast(adminPk);
        usdc.mint(alice, 100_000e18);
        usdc.mint(bob, 100_000e18);
        weth.mint(alice, 100_000e18);
        weth.mint(bob, 100_000e18);
        vm.stopBroadcast();

        // 1) Alice supplies USDC
        vm.startBroadcast(alicePk);
        usdc.approve(dUsdcAddr, 10_000e18);
        dUSDC.mint(10_000e18);
        vm.stopBroadcast();

        // 2) Bob supplies WETH and enters market
        vm.startBroadcast(bobPk);
        weth.approve(dWethAddr, 5e18);
        dWETH.mint(5e18);
        address[] memory markets = new address[](1);
        markets[0] = dWethAddr;
        comptroller.enterMarkets(markets);
        vm.stopBroadcast();

        // 3) Bob borrows USDC
        vm.startBroadcast(bobPk);
        dUSDC.borrow(5_000e18);
        vm.stopBroadcast();

        // 4) Time passes, accrue interest
        vm.warp(block.timestamp + 365 days);
        vm.startBroadcast(adminPk);
        dUSDC.accrueInterest();
        vm.stopBroadcast();

        // 5) Bob repays all debt
        vm.startBroadcast(bobPk);
        usdc.approve(dUsdcAddr, type(uint256).max);
        dUSDC.repayBorrow(type(uint256).max);
        vm.stopBroadcast();

        // 6) Alice redeems all dUSDC
        vm.startBroadcast(alicePk);
        uint256 aliceBal = dUSDC.balanceOf(alice);
        dUSDC.redeem(aliceBal);
        vm.stopBroadcast();

        console2.log("Repro completed.");
        uint256 aliceUsdc = usdc.balanceOf(alice);
        uint256 bobUsdc = usdc.balanceOf(bob);
        console2.log("Alice USDC (raw):", aliceUsdc);
        console2.log("Bob USDC (raw):", bobUsdc);
        console2.log("Alice USDC (whole):", aliceUsdc / 1e18);
        console2.log("Bob USDC (whole):", bobUsdc / 1e18);
    }

    function _sendEth(address from, address to, uint256 amount) internal {
        if (from.balance < amount) {
            return;
        }
        (bool ok,) = to.call{value: amount}("");
        require(ok, "ETH_TRANSFER_FAILED");
    }
}
