// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "../libraries/DataTypes.sol";

/**
 * @title LendingPoolStorage
 * @notice ERC-7201 namespaced storage for LendingPoolCore
 */
library LendingPoolStorage {
    /// @custom:storage-location erc7201:defi.protocol.lending.pool
    struct Layout {
        /// @notice Contract version for upgrades
        uint256 version;
        /// @notice Mapping from asset address to reserve data
        mapping(address => DataTypes.ReserveData) reserves;
        /// @notice Mapping from user to asset to whether using as collateral
        mapping(address => mapping(address => bool)) userUsingAsCollateral;
        /// @notice Address of the price oracle
        address priceOracle;
        /// @notice Whether the protocol is paused
        bool paused;
        /// @notice List of all reserve assets
        address[] reservesList;
        /// @notice Close factor for liquidations (scaled by 1e18)
        uint256 closeFactor;
        /// @notice Maximum number of reserves
        uint256 maxReserves;
    }

    // keccak256(abi.encode(uint256(keccak256("defi.protocol.lending.pool")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x4a2f2b9e3c5d8f1a0b6e7c4d9a8b5c2f1e0d9c8b7a6f5e4d3c2b1a0908070600;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_LOCATION;
        assembly {
            l.slot := slot
        }
    }
}
