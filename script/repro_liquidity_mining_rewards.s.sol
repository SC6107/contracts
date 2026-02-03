// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {LiquidityMining} from "../src/mining/LiquidityMining.sol";
import {GovernanceToken} from "../src/governance/GovernanceToken.sol";
import {LendingToken} from "../src/lending/LendingToken.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

contract ReproLiquidityMiningRewards is Script {
    function run() external {
        uint256 adminPk = vm.envUint("ADMIN_PK");
        uint256 alicePk = vm.envUint("ALICE_PK");
        uint256 bobPk = vm.envUint("BOB_PK");
        address admin = vm.addr(adminPk);
        address alice = vm.addr(alicePk);
        address bob = vm.addr(bobPk);

        address govTokenAddr = vm.envAddress("GOVERNANCE_TOKEN");
        address usdcAddr = vm.envAddress("USDC");
        address dUsdcAddr = vm.envAddress("DUSDC");
        address usdcMiningAddr = vm.envAddress("USDC_MINING");

        GovernanceToken govToken = GovernanceToken(govTokenAddr);
        MockERC20 usdc = MockERC20(usdcAddr);
        LendingToken dUSDC = LendingToken(dUsdcAddr);
        LiquidityMining usdcMining = LiquidityMining(usdcMiningAddr);

        console2.log("Configuration");
        console2.log("  GOV owner:", govToken.owner());
        console2.log("  GOV minter:", govToken.minter());
        console2.log("  Mining owner:", usdcMining.owner());
        console2.log("  Mining rewardsDistributor:", usdcMining.rewardsDistributor());
        console2.log("  Mining stakingToken:", usdcMining.stakingToken());
        console2.log("  Mining rewardsToken:", usdcMining.rewardsToken());
        console2.log("  rewardsDuration:", usdcMining.rewardsDuration());
        console2.log("  rewardRate:", usdcMining.rewardRate());
        console2.log("  periodFinish:", usdcMining.periodFinish());

        if (usdcMining.stakingToken() != dUsdcAddr) {
            console2.log("ERROR: stakingToken does not match dUSDC. Aborting.");
            return;
        }
        if (usdcMining.rewardsToken() != govTokenAddr) {
            console2.log("ERROR: rewardsToken does not match GOV. Aborting.");
            return;
        }
        if (admin != govToken.owner() || admin != usdcMining.rewardsDistributor()) {
            console2.log("ERROR: ADMIN_PK is not the GOV owner or rewards distributor.");
            console2.log("Set ADMIN_PK to the deployer key used in FullSetupLocal.");
            return;
        }

        console2.log("Initial Balances");
        console2.log("  Alice USDC:", usdc.balanceOf(alice));
        console2.log("  Bob USDC:", usdc.balanceOf(bob));
        console2.log("  Alice dUSDC:", dUSDC.balanceOf(alice));
        console2.log("  Bob dUSDC:", dUSDC.balanceOf(bob));
        console2.log("  Alice GOV:", govToken.balanceOf(alice));
        console2.log("  Bob GOV:", govToken.balanceOf(bob));
        console2.log("  Mining GOV balance:", govToken.balanceOf(address(usdcMining)));

        // Ensure Alice and Bob have ETH for gas
        vm.startBroadcast(adminPk);
        _sendEth(admin, alice, 10 ether);
        _sendEth(admin, bob, 10 ether);
        vm.stopBroadcast();

        // Ensure Alice and Bob have USDC
        vm.startBroadcast(adminPk);
        usdc.mint(alice, 100_000e18);
        usdc.mint(bob, 100_000e18);
        vm.stopBroadcast();

        console2.log("After Minting USDC");
        console2.log("  Alice USDC:", usdc.balanceOf(alice));
        console2.log("  Bob USDC:", usdc.balanceOf(bob));

        console2.log("USDC Mining:", usdcMiningAddr);
        console2.log("dUSDC:", dUsdcAddr);
        console2.log("GOV Token:", govTokenAddr);

        // 1) Fund mining contract with rewards
        uint256 reward = 30_000e18;
        uint256 balanceBefore = govToken.balanceOf(address(usdcMining));
        uint256 duration = usdcMining.rewardsDuration();
        uint256 periodFinish = usdcMining.periodFinish();
        uint256 rewardRate = usdcMining.rewardRate();
        uint256 required = reward;
        if (block.timestamp < periodFinish) {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            required = reward + leftover;
        }
        if (balanceBefore < required) {
            uint256 topUp = required - balanceBefore;
            console2.log("Funding rewards (top up):", topUp);
            vm.startBroadcast(adminPk);
            govToken.mint(address(usdcMining), topUp);
            vm.stopBroadcast();
        } else {
            console2.log("Mining contract already funded. Balance:", balanceBefore);
        }

        console2.log("After Funding Rewards");
        console2.log("  Mining GOV balance:", govToken.balanceOf(address(usdcMining)));

        // 2) Notify rewards
        vm.startBroadcast(adminPk);
        usdcMining.notifyRewardAmount(30_000e18);
        vm.stopBroadcast();

        console2.log("After notifyRewardAmount");
        console2.log("  rewardRate:", usdcMining.rewardRate());
        console2.log("  periodFinish:", usdcMining.periodFinish());

        // 3) Alice supplies and stakes
        vm.startBroadcast(alicePk);
        usdc.approve(dUsdcAddr, 10_000e18);
        dUSDC.mint(10_000e18);
        console2.log("Alice dUSDC:", dUSDC.balanceOf(alice));
        dUSDC.approve(usdcMiningAddr, type(uint256).max);
        usdcMining.stake(dUSDC.balanceOf(alice));
        console2.log("Alice staked:", usdcMining.balanceOf(alice));
        vm.stopBroadcast();

        console2.log("After Alice Stake");
        console2.log("  Alice USDC:", usdc.balanceOf(alice));
        console2.log("  Alice dUSDC:", dUSDC.balanceOf(alice));
        console2.log("  Alice staked:", usdcMining.balanceOf(alice));

        // 4) Bob also stakes
        vm.startBroadcast(bobPk);
        usdc.approve(dUsdcAddr, 10_000e18);
        dUSDC.mint(10_000e18);
        console2.log("Bob dUSDC:", dUSDC.balanceOf(bob));
        dUSDC.approve(usdcMiningAddr, type(uint256).max);
        usdcMining.stake(dUSDC.balanceOf(bob));
        console2.log("Bob staked:", usdcMining.balanceOf(bob));
        vm.stopBroadcast();

        console2.log("After Bob Stake");
        console2.log("  Bob USDC:", usdc.balanceOf(bob));
        console2.log("  Bob dUSDC:", dUSDC.balanceOf(bob));
        console2.log("  Bob staked:", usdcMining.balanceOf(bob));

        // 5) Time passes (15 days)
        vm.warp(block.timestamp + 15 days);
        console2.log("Time advanced 15 days.");

        // 6) Both claim rewards
        uint256 aliceGovBefore = govToken.balanceOf(alice);
        uint256 bobGovBefore = govToken.balanceOf(bob);

        vm.startBroadcast(alicePk);
        usdcMining.getReward();
        vm.stopBroadcast();

        vm.startBroadcast(bobPk);
        usdcMining.getReward();
        vm.stopBroadcast();

        uint256 aliceGov = govToken.balanceOf(alice);
        uint256 bobGov = govToken.balanceOf(bob);

        console2.log("Repro completed.");
        console2.log("Alice GOV before:", aliceGovBefore);
        console2.log("Bob GOV before:", bobGovBefore);
        console2.log("Alice GOV after (raw):", aliceGov);
        console2.log("Bob GOV after (raw):", bobGov);
        console2.log("Alice GOV delta:", aliceGov - aliceGovBefore);
        console2.log("Bob GOV delta:", bobGov - bobGovBefore);
        console2.log("Alice GOV (whole):", aliceGov / 1e18);
        console2.log("Bob GOV (whole):", bobGov / 1e18);
    }

    function _sendEth(address from, address to, uint256 amount) internal {
        if (from.balance < amount) {
            return;
        }
        (bool ok,) = to.call{value: amount}("");
        require(ok, "ETH_TRANSFER_FAILED");
    }
}
