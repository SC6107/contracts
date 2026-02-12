// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {PriceOracle} from "../src/oracle/PriceOracle.sol";
import {ProtocolGovernor} from "../src/governance/ProtocolGovernor.sol";
import {ProtocolTimelock} from "../src/governance/ProtocolTimelock.sol";

contract ReproGovernanceUpgradeFlow is Script {
    string internal constant PROPOSAL_DESCRIPTION = "Upgrade PriceOracle";

    function run() external {
        string memory phase = vm.envOr("PHASE", string("prepare"));

        uint256 adminPk = vm.envUint("ADMIN_PK");
        uint256 alicePk = vm.envUint("ALICE_PK");
        uint256 bobPk = vm.envUint("BOB_PK");
        uint256 carolPk = vm.envUint("CAROL_PK");

        address admin = vm.addr(adminPk);
        address alice = vm.addr(alicePk);
        address bob = vm.addr(bobPk);
        address carol = vm.addr(carolPk);

        address priceOracleAddr = vm.envAddress("PRICE_ORACLE");
        address timelockAddr = vm.envAddress("PROTOCOL_TIMELOCK");
        address governorAddr = vm.envAddress("PROTOCOL_GOVERNOR");

        PriceOracle priceOracle = PriceOracle(priceOracleAddr);
        ProtocolTimelock timelock = ProtocolTimelock(payable(timelockAddr));
        ProtocolGovernor governor = ProtocolGovernor(payable(governorAddr));

        console2.log("Phase:", phase);
        console2.log("  Admin:", admin);
        console2.log("  Alice:", alice);
        console2.log("  Bob:", bob);
        console2.log("  Carol:", carol);
        console2.log("  PriceOracle:", priceOracleAddr);
        console2.log("  ProtocolTimelock:", timelockAddr);
        console2.log("  ProtocolGovernor:", governorAddr);

        if (_eq(phase, "prepare")) {
            _prepare(adminPk, admin, priceOracle, timelock, governor);
            return;
        }

        address newPriceOracleImpl = vm.envAddress("NEW_PRICE_ORACLE_IMPL");
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descriptionHash,
            uint256 proposalId
        ) = _proposalData(governor, priceOracleAddr, newPriceOracleImpl);

        if (_eq(phase, "propose")) {
            console2.log("Proposal ID:", proposalId);
            vm.startBroadcast(alicePk);
            governor.propose(targets, values, calldatas, PROPOSAL_DESCRIPTION);
            vm.stopBroadcast();
            return;
        }

        if (_eq(phase, "vote")) {
            console2.log("Proposal ID:", proposalId);
            bool castAllVotes = vm.envOr("CAST_ALL_VOTES", false);

            // Alice alone has enough voting power for quorum in this repro flow.
            vm.startBroadcast(alicePk);
            governor.castVote(proposalId, 1);
            vm.stopBroadcast();

            if (castAllVotes) {
                vm.startBroadcast(bobPk);
                governor.castVote(proposalId, 1);
                vm.stopBroadcast();

                vm.startBroadcast(carolPk);
                governor.castVote(proposalId, 1);
                vm.stopBroadcast();
            }
            return;
        }

        if (_eq(phase, "queue")) {
            console2.log("Proposal ID:", proposalId);
            vm.startBroadcast(adminPk);
            governor.queue(targets, values, calldatas, descriptionHash);
            vm.stopBroadcast();
            return;
        }

        if (_eq(phase, "execute")) {
            console2.log("Proposal ID:", proposalId);
            uint256 versionBefore = priceOracle.version();

            vm.startBroadcast(adminPk);
            governor.execute(targets, values, calldatas, descriptionHash);
            vm.stopBroadcast();

            uint256 versionAfter = priceOracle.version();
            require(versionAfter == versionBefore + 1, "UPGRADE_VERSION_MISMATCH");

            console2.log("Repro completed.");
            console2.log("PriceOracle implementation:", newPriceOracleImpl);
            console2.log("PriceOracle version before:", versionBefore);
            console2.log("PriceOracle version after:", versionAfter);
            return;
        }

        revert("INVALID_PHASE");
    }

    function _prepare(
        uint256 adminPk,
        address admin,
        PriceOracle priceOracle,
        ProtocolTimelock timelock,
        ProtocolGovernor governor
    ) internal {
        address newPriceOracleImpl = vm.envOr("NEW_PRICE_ORACLE_IMPL", address(0));
        if (newPriceOracleImpl == address(0)) {
            vm.startBroadcast(adminPk);
            newPriceOracleImpl = address(new PriceOracle());
            vm.stopBroadcast();
        }

        if (priceOracle.owner() != address(timelock)) {
            require(priceOracle.owner() == admin, "ADMIN_NOT_ORACLE_OWNER");
            vm.startBroadcast(adminPk);
            priceOracle.transferOwnership(address(timelock));
            vm.stopBroadcast();
        }

        console2.log("New PriceOracle implementation:", newPriceOracleImpl);
        (, , , , uint256 expectedProposalId) = _proposalData(governor, address(priceOracle), newPriceOracleImpl);
        console2.log("Expected Proposal ID:", expectedProposalId);
    }

    function _proposalData(
        ProtocolGovernor governor,
        address priceOracleAddr,
        address newPriceOracleImpl
    )
        internal
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descriptionHash,
            uint256 proposalId
        )
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);

        targets[0] = priceOracleAddr;
        values[0] = 0;
        calldatas[0] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newPriceOracleImpl, ""));
        descriptionHash = keccak256(bytes(PROPOSAL_DESCRIPTION));
        proposalId = governor.hashProposal(targets, values, calldatas, descriptionHash);
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
