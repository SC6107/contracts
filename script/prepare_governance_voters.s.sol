// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {GovernanceToken} from "../src/governance/GovernanceToken.sol";

contract PrepareGovernanceVoters is Script {
    uint256 internal constant GOV_ALLOCATION = 1_000_000e18;
    uint256 internal constant DEFAULT_GAS_TOPUP_WEI = 10 ether;

    function run() external {
        uint256 adminPk = vm.envUint("ADMIN_PK");
        uint256 alicePk = vm.envUint("ALICE_PK");
        uint256 bobPk = vm.envUint("BOB_PK");
        uint256 carolPk = vm.envUint("CAROL_PK");

        address admin = vm.addr(adminPk);
        address alice = vm.addr(alicePk);
        address bob = vm.addr(bobPk);
        address carol = vm.addr(carolPk);

        address govTokenAddr = vm.envAddress("GOVERNANCE_TOKEN");
        uint256 gasTopupWei = vm.envOr("GAS_TOPUP_WEI", DEFAULT_GAS_TOPUP_WEI);
        GovernanceToken govToken = GovernanceToken(govTokenAddr);

        require(admin == govToken.owner(), "ADMIN_NOT_GOV_OWNER");

        vm.startBroadcast(adminPk);
        _sendEth(admin, alice, gasTopupWei);
        _sendEth(admin, bob, gasTopupWei);
        _sendEth(admin, carol, gasTopupWei);
        govToken.mint(alice, GOV_ALLOCATION);
        govToken.mint(bob, GOV_ALLOCATION);
        govToken.mint(carol, GOV_ALLOCATION);
        vm.stopBroadcast();

        vm.startBroadcast(alicePk);
        govToken.delegate(alice);
        vm.stopBroadcast();

        vm.startBroadcast(bobPk);
        govToken.delegate(bob);
        vm.stopBroadcast();

        vm.startBroadcast(carolPk);
        govToken.delegate(carol);
        vm.stopBroadcast();

        console2.log("Governance voter preparation complete.");
        console2.log("Alice GOV:", govToken.balanceOf(alice));
        console2.log("Bob GOV:", govToken.balanceOf(bob));
        console2.log("Carol GOV:", govToken.balanceOf(carol));
        console2.log("Alice votes:", govToken.getVotes(alice));
        console2.log("Bob votes:", govToken.getVotes(bob));
        console2.log("Carol votes:", govToken.getVotes(carol));
    }

    function _sendEth(address from, address to, uint256 amount) internal {
        if (from.balance < amount) {
            return;
        }
        (bool ok,) = to.call{value: amount}("");
        require(ok, "ETH_TRANSFER_FAILED");
    }
}
