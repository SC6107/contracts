// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LendingTokenStorage
 * @notice ERC-7201 namespaced storage for LendingToken
 */
library LendingTokenStorage {
    /// @custom:storage-location erc7201:defi.protocol.lending.token
    struct Layout {
        /// @notice Contract version for upgrades
        uint256 version;
        /// @notice Address of the underlying asset
        address underlying;
        /// @notice Address of the comptroller
        address comptroller;
        /// @notice Address of the interest rate model
        address interestRateModel;
        /// @notice Initial exchange rate (scaled by 1e18)
        uint256 initialExchangeRateMantissa;
        /// @notice Reserve factor (scaled by 1e18)
        uint256 reserveFactorMantissa;
        /// @notice Block timestamp when interest was last accrued
        uint256 accrualBlockTimestamp;
        /// @notice Accumulator of total earned interest (scaled by 1e18)
        uint256 borrowIndex;
        /// @notice Total amount of outstanding borrows of the underlying
        uint256 totalBorrows;
        /// @notice Total amount of reserves of the underlying
        uint256 totalReserves;
        /// @notice Mapping of account addresses to their borrow balances
        mapping(address => BorrowSnapshot) accountBorrows;
    }

    /**
     * @notice Container for borrow balance information
     * @member principal Total balance (with accrued interest) at the time of the most recent action
     * @member interestIndex Global borrowIndex at the time of the most recent action
     */
    struct BorrowSnapshot {
        uint256 principal;
        uint256 interestIndex;
    }

    // keccak256(abi.encode(uint256(keccak256("defi.protocol.lending.token")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_LOCATION;
        assembly {
            l.slot := slot
        }
    }
}
