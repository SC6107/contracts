// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IInterestRateModel
 * @notice Interface for interest rate calculation models
 */
interface IInterestRateModel {
    /**
     * @notice Calculates the current borrow rate per second
     * @param cash The total amount of cash in the market
     * @param borrows The total amount of borrows in the market
     * @param reserves The total amount of reserves in the market
     * @return The borrow rate per second (scaled by 1e18)
     */
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256);

    /**
     * @notice Calculates the current supply rate per second
     * @param cash The total amount of cash in the market
     * @param borrows The total amount of borrows in the market
     * @param reserves The total amount of reserves in the market
     * @param reserveFactorMantissa The reserve factor (scaled by 1e18)
     * @return The supply rate per second (scaled by 1e18)
     */
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external view returns (uint256);

    /**
     * @notice Calculates the utilization rate of the market
     * @param cash The total amount of cash in the market
     * @param borrows The total amount of borrows in the market
     * @param reserves The total amount of reserves in the market
     * @return The utilization rate (scaled by 1e18)
     */
    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) external pure returns (uint256);
}
