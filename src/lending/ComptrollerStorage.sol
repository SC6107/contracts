// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ComptrollerStorage
 * @notice ERC-7201 namespaced storage for Comptroller
 */
library ComptrollerStorage {
    struct Market {
        bool isListed;
        uint256 collateralFactorMantissa;
    }

    /// @custom:storage-location erc7201:defi.protocol.comptroller
    struct Layout {
        /// @notice Contract version for upgrades
        uint256 version;
        /// @notice Address of the price oracle
        address priceOracle;
        /// @notice Whether the protocol is paused
        bool paused;
        /// @notice Close factor for liquidations (scaled by 1e18)
        uint256 closeFactorMantissa;
        /// @notice Liquidation incentive (scaled by 1e18)
        uint256 liquidationIncentiveMantissa;
        /// @notice List of all supported markets (cTokens)
        address[] allMarkets;
        /// @notice Mapping from cToken to market configuration
        mapping(address => Market) markets;
        /// @notice Mapping from account to cToken to membership status
        mapping(address => mapping(address => bool)) accountMembership;
    }

    // keccak256(abi.encode(uint256(keccak256("defi.protocol.comptroller")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x2f52f4dbd7d7e16a6501e5c63cbff5b3cbb0a0c53b8f3df098e0c0c0a4e7b300;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_LOCATION;
        assembly {
            l.slot := slot
        }
    }
}
