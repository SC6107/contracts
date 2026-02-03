// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PercentageMath
 * @notice Library for percentage calculations with basis points (10000 = 100%)
 */
library PercentageMath {
    /// @notice 100% in basis points
    uint256 internal constant PERCENTAGE_FACTOR = 1e4;
    /// @notice Half percentage for rounding
    uint256 internal constant HALF_PERCENTAGE_FACTOR = 0.5e4;

    /**
     * @notice Calculates percentage of a value
     * @param value The value to calculate percentage of
     * @param percentage The percentage in basis points (10000 = 100%)
     * @return The result of value * percentage / 10000, rounded half up
     */
    function percentMul(uint256 value, uint256 percentage) internal pure returns (uint256) {
        if (value == 0 || percentage == 0) {
            return 0;
        }
        return (value * percentage + HALF_PERCENTAGE_FACTOR) / PERCENTAGE_FACTOR;
    }

    /**
     * @notice Divides a value by a percentage
     * @param value The value to divide
     * @param percentage The percentage in basis points (10000 = 100%)
     * @return The result of value * 10000 / percentage, rounded half up
     */
    function percentDiv(uint256 value, uint256 percentage) internal pure returns (uint256) {
        require(percentage != 0, "PercentageMath: division by zero");
        uint256 halfPercentage = percentage / 2;
        return (value * PERCENTAGE_FACTOR + halfPercentage) / percentage;
    }
}
