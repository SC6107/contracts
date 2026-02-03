// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PriceOracleStorage
 * @notice ERC-7201 namespaced storage for PriceOracle
 */
library PriceOracleStorage {
    /// @custom:storage-location erc7201:defi.protocol.oracle.price
    struct Layout {
        /// @notice Contract version for upgrades
        uint256 version;
        /// @notice Mapping from asset address to Chainlink price feed address
        mapping(address => address) assetSources;
        /// @notice List of supported assets
        address[] assetsList;
        /// @notice Mapping to check if asset exists in list
        mapping(address => bool) assetsExist;
        /// @notice Fallback oracle for assets without Chainlink feed
        address fallbackOracle;
        /// @notice Base currency unit (for USD it's 1e8)
        uint256 baseCurrencyUnit;
    }

    // keccak256(abi.encode(uint256(keccak256("defi.protocol.oracle.price")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x9b56c9a1c29b2d1c9e5e8a8a3f2e1d0c9b8a7f6e5d4c3b2a1908070605040300;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_LOCATION;
        assembly {
            l.slot := slot
        }
    }
}
