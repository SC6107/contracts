// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ILendingToken
 * @notice Interface for lending receipt tokens (dTokens)
 */
interface ILendingToken is IERC20 {
    /**
     * @notice Returns the underlying asset address
     * @return The address of the underlying asset
     */
    function underlying() external view returns (address);

    /**
     * @notice Returns the current exchange rate between dTokens and underlying
     * @dev This function accrues interest, so it's not view
     * @return The exchange rate (scaled by 1e18)
     */
    function exchangeRate() external returns (uint256);

    /**
     * @notice Returns the exchange rate stored without accruing interest
     * @return The stored exchange rate (scaled by 1e18)
     */
    function exchangeRateStored() external view returns (uint256);

    /**
     * @notice Accrues interest and updates the exchange rate
     */
    function accrueInterest() external;

    /**
     * @notice Mints dTokens for a depositor
     * @param from The address providing the underlying tokens
     * @param to The address receiving the dTokens
     * @param mintAmount The amount of underlying to deposit
     * @return The amount of dTokens minted
     */
    function mint(address from, address to, uint256 mintAmount) external returns (uint256);

    /**
     * @notice Redeems dTokens for underlying
     * @param from The address whose dTokens to burn
     * @param to The address receiving the underlying
     * @param redeemTokens The amount of dTokens to redeem
     * @return The amount of underlying returned
     */
    function redeem(address from, address to, uint256 redeemTokens) external returns (uint256);

    /**
     * @notice Redeems dTokens for a specific amount of underlying
     * @param from The address whose dTokens to burn
     * @param to The address receiving the underlying
     * @param redeemAmount The amount of underlying to receive
     * @return The amount of dTokens burned
     */
    function redeemUnderlying(address from, address to, uint256 redeemAmount) external returns (uint256);

    /**
     * @notice Borrows underlying from the market
     * @param borrower The address borrowing
     * @param borrowAmount The amount to borrow
     */
    function borrow(address borrower, uint256 borrowAmount) external;

    /**
     * @notice Repays a borrow
     * @param payer The address paying the debt
     * @param borrower The address whose debt is being repaid
     * @param repayAmount The amount to repay
     * @return The actual amount repaid
     */
    function repayBorrow(address payer, address borrower, uint256 repayAmount) external returns (uint256);

    /**
     * @notice Returns the borrow balance of an account including interest
     * @param account The address to query
     * @return The borrow balance with accrued interest
     */
    function borrowBalanceCurrent(address account) external returns (uint256);

    /**
     * @notice Returns the stored borrow balance without accruing
     * @param account The address to query
     * @return The stored borrow balance
     */
    function borrowBalanceStored(address account) external view returns (uint256);

    /**
     * @notice Returns total borrows including accrued interest
     * @return The total borrows
     */
    function totalBorrowsCurrent() external returns (uint256);

    /**
     * @notice Returns stored total borrows
     * @return The stored total borrows
     */
    function totalBorrows() external view returns (uint256);

    /**
     * @notice Returns total reserves
     * @return The total reserves
     */
    function totalReserves() external view returns (uint256);

    /**
     * @notice Returns the reserve factor
     * @return The reserve factor (scaled by 1e18)
     */
    function reserveFactorMantissa() external view returns (uint256);

    /**
     * @notice Returns the interest rate model
     * @return The address of the interest rate model
     */
    function interestRateModel() external view returns (address);

    /**
     * @notice Returns the accrual block timestamp
     * @return The last accrual timestamp
     */
    function accrualBlockTimestamp() external view returns (uint256);

    /**
     * @notice Returns the borrow index
     * @return The borrow index (scaled by 1e18)
     */
    function borrowIndex() external view returns (uint256);

    /**
     * @notice Returns available cash in the market
     * @return The cash balance
     */
    function getCash() external view returns (uint256);

    /**
     * @notice Seizes collateral tokens during liquidation
     * @param liquidator The address performing liquidation
     * @param borrower The address being liquidated
     * @param seizeTokens The amount of tokens to seize
     */
    function seize(address liquidator, address borrower, uint256 seizeTokens) external;

    /**
     * @notice Sets the reserve factor
     * @param newReserveFactorMantissa The new reserve factor
     */
    function setReserveFactor(uint256 newReserveFactorMantissa) external;

    /**
     * @notice Sets the interest rate model
     * @param newInterestRateModel The new interest rate model address
     */
    function setInterestRateModel(address newInterestRateModel) external;

    /**
     * @notice Returns the lending pool address
     * @return The lending pool address
     */
    function lendingPool() external view returns (address);
}
