// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

import {Errors} from "../libraries/Errors.sol";

/**
 * @title ProtocolTimelock
 * @notice UUPS upgradeable timelock controller for protocol governance
 * @dev Extends OpenZeppelin's TimelockController with upgrade functionality
 */
contract ProtocolTimelock is Initializable, UUPSUpgradeable, TimelockControllerUpgradeable {
    /// @custom:storage-location erc7201:defi.protocol.governance.timelock
    struct TimelockStorage {
        uint256 version;
    }

    // keccak256(abi.encode(uint256(keccak256("defi.protocol.governance.timelock")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x2d3f4e5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d00;

    function _getStorage() private pure returns (TimelockStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /// @notice Minimum delay for timelock operations (24 hours)
    uint256 public constant MIN_DELAY = 24 hours;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the timelock controller
     * @param minDelay_ Minimum delay for operations (must be >= 24 hours)
     * @param proposers_ Addresses that can propose operations
     * @param executors_ Addresses that can execute operations
     * @param admin_ Admin address (can grant/revoke roles)
     */
    function initialize(
        uint256 minDelay_,
        address[] memory proposers_,
        address[] memory executors_,
        address admin_
    ) public override initializer {
        if (minDelay_ < MIN_DELAY) revert Errors.InvalidTimelockDelay();

        __TimelockController_init(minDelay_, proposers_, executors_, admin_);

        TimelockStorage storage $ = _getStorage();
        $.version = 1;
    }

    /**
     * @notice Returns the contract version
     * @return The version number
     */
    function version() external view returns (uint256) {
        return _getStorage().version;
    }

    /**
     * @notice Authorizes an upgrade
     * @dev Only the timelock itself can upgrade
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0)) revert Errors.InvalidImplementation();
        _getStorage().version++;
    }
}
