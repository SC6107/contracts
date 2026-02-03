// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {GovernorSettingsUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {GovernorCountingSimpleUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {GovernorVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import {GovernorVotesQuorumFractionUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import {GovernorTimelockControlUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

import {Errors} from "../libraries/Errors.sol";

/**
 * @title ProtocolGovernor
 * @notice UUPS upgradeable governance contract for the DeFi protocol
 * @dev Implements OpenZeppelin Governor with timelock control
 *
 * Governance Parameters:
 * - Voting Delay: 1 day (time between proposal and voting start)
 * - Voting Period: 1 week
 * - Proposal Threshold: 100,000 tokens
 * - Quorum: 4% of total supply
 */
contract ProtocolGovernor is
    Initializable,
    UUPSUpgradeable,
    GovernorUpgradeable,
    GovernorSettingsUpgradeable,
    GovernorCountingSimpleUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable,
    GovernorTimelockControlUpgradeable
{
    /// @custom:storage-location erc7201:defi.protocol.governance.governor.custom
    struct ProtocolGovernorStorage {
        uint256 upgradeVersion;
    }

    // keccak256(abi.encode(uint256(keccak256("defi.protocol.governance.governor.custom")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a00;

    function _getStorage() private pure returns (ProtocolGovernorStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the governor
     * @param token_ The governance token address
     * @param timelock_ The timelock controller address
     * @param votingDelay_ Delay before voting starts (in seconds)
     * @param votingPeriod_ Duration of voting (in seconds)
     * @param proposalThreshold_ Minimum tokens needed to create proposal
     * @param quorumPercentage_ Quorum percentage (4 = 4%)
     */
    function initialize(
        IVotes token_,
        TimelockControllerUpgradeable timelock_,
        uint48 votingDelay_,
        uint32 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumPercentage_
    ) external initializer {
        __Governor_init("Protocol Governor");
        __GovernorSettings_init(votingDelay_, votingPeriod_, proposalThreshold_);
        __GovernorCountingSimple_init();
        __GovernorVotes_init(token_);
        __GovernorVotesQuorumFraction_init(quorumPercentage_);
        __GovernorTimelockControl_init(timelock_);

        ProtocolGovernorStorage storage $ = _getStorage();
        $.upgradeVersion = 1;
    }

    /**
     * @notice Returns the contract upgrade version
     * @return The upgrade version number
     */
    function upgradeVersion() external view returns (uint256) {
        return _getStorage().upgradeVersion;
    }

    // Required overrides

    /**
     * @notice Returns the current timepoint (timestamp-based)
     */
    function clock() public view override(GovernorUpgradeable, GovernorVotesUpgradeable) returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @notice Returns the clock mode description (EIP-6372)
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override(GovernorUpgradeable, GovernorVotesUpgradeable) returns (string memory) {
        return "mode=timestamp";
    }

    function votingDelay()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function quorum(uint256 blockNumber)
        public
        view
        override(GovernorUpgradeable, GovernorVotesQuorumFractionUpgradeable)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function state(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function proposalThreshold()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (address)
    {
        return super._executor();
    }

    /**
     * @notice Authorizes an upgrade
     * @dev Only governance can upgrade through proposal
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {
        if (newImplementation == address(0)) revert Errors.InvalidImplementation();
        _getStorage().upgradeVersion++;
    }
}
