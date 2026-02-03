// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {PriceOracle} from "../src/oracle/PriceOracle.sol";
import {LendingToken} from "../src/lending/LendingToken.sol";
import {Comptroller} from "../src/lending/Comptroller.sol";
import {GovernanceToken} from "../src/governance/GovernanceToken.sol";
import {LiquidityMining} from "../src/mining/LiquidityMining.sol";
import {ProtocolTimelock} from "../src/governance/ProtocolTimelock.sol";
import {ProtocolGovernor} from "../src/governance/ProtocolGovernor.sol";

/**
 * @title UpgradeProtocol
 * @notice Scripts for upgrading protocol contracts
 */
contract UpgradeProtocol is Script {
    /**
     * @notice Upgrades the PriceOracle contract
     * @param proxyAddress The proxy address
     */
    function upgradePriceOracle(address proxyAddress) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        address newImpl = address(new PriceOracle());
        console2.log("New PriceOracle implementation:", newImpl);

        // Upgrade proxy
        UUPSUpgradeable(proxyAddress).upgradeToAndCall(newImpl, "");
        console2.log("PriceOracle upgraded successfully");

        // Verify version
        uint256 newVersion = PriceOracle(proxyAddress).version();
        console2.log("New version:", newVersion);

        vm.stopBroadcast();
    }

    /**
     * @notice Upgrades the Comptroller contract
     * @param proxyAddress The proxy address
     */
    function upgradeComptroller(address proxyAddress) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address newImpl = address(new Comptroller());
        console2.log("New Comptroller implementation:", newImpl);

        UUPSUpgradeable(proxyAddress).upgradeToAndCall(newImpl, "");
        console2.log("Comptroller upgraded successfully");

        uint256 newVersion = Comptroller(proxyAddress).version();
        console2.log("New version:", newVersion);

        vm.stopBroadcast();
    }

    /**
     * @notice Upgrades the LendingToken contract
     * @param proxyAddress The proxy address
     */
    function upgradeLendingToken(address proxyAddress) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address newImpl = address(new LendingToken());
        console2.log("New LendingToken implementation:", newImpl);

        UUPSUpgradeable(proxyAddress).upgradeToAndCall(newImpl, "");
        console2.log("LendingToken upgraded successfully");

        uint256 newVersion = LendingToken(proxyAddress).version();
        console2.log("New version:", newVersion);

        vm.stopBroadcast();
    }

    /**
     * @notice Upgrades the GovernanceToken contract
     * @param proxyAddress The proxy address
     */
    function upgradeGovernanceToken(address proxyAddress) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address newImpl = address(new GovernanceToken());
        console2.log("New GovernanceToken implementation:", newImpl);

        UUPSUpgradeable(proxyAddress).upgradeToAndCall(newImpl, "");
        console2.log("GovernanceToken upgraded successfully");

        uint256 newVersion = GovernanceToken(proxyAddress).version();
        console2.log("New version:", newVersion);

        vm.stopBroadcast();
    }

    /**
     * @notice Upgrades the LiquidityMining contract
     * @param proxyAddress The proxy address
     */
    function upgradeLiquidityMining(address proxyAddress) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address newImpl = address(new LiquidityMining());
        console2.log("New LiquidityMining implementation:", newImpl);

        UUPSUpgradeable(proxyAddress).upgradeToAndCall(newImpl, "");
        console2.log("LiquidityMining upgraded successfully");

        uint256 newVersion = LiquidityMining(proxyAddress).version();
        console2.log("New version:", newVersion);

        vm.stopBroadcast();
    }

    /**
     * @notice Prepares a governance proposal for upgrading a contract
     * @dev This creates the calldata for a governance proposal
     * @param proxyAddress The proxy address to upgrade
     * @param newImplementation The new implementation address
     * @return The encoded calldata for the upgrade
     */
    function prepareUpgradeProposal(
        address proxyAddress,
        address newImplementation
    ) external pure returns (bytes memory) {
        return abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newImplementation, ""));
    }

    /**
     * @notice Creates a governance proposal for an upgrade
     * @param governor The governor contract address
     * @param proxyAddress The proxy to upgrade
     * @param newImplementation The new implementation
     * @param description The proposal description
     */
    function createUpgradeProposal(
        address governor,
        address proxyAddress,
        address newImplementation,
        string memory description
    ) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = proxyAddress;
        values[0] = 0;
        calldatas[0] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newImplementation, ""));

        uint256 proposalId = ProtocolGovernor(payable(governor)).propose(
            targets,
            values,
            calldatas,
            description
        );

        console2.log("Proposal created with ID:", proposalId);

        vm.stopBroadcast();
    }
}
