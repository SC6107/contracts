// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ILendingToken
 * @notice Interface for Compound v2-style cTokens
 */
interface ILendingToken is IERC20 {
    /**
     * @notice Returns the underlying asset address
     */
    function underlying() external view returns (address);

    /**
     * @notice Returns the comptroller address
     */
    function comptroller() external view returns (address);

    /**
     * @notice Returns the current exchange rate between cTokens and underlying
     * @dev This function accrues interest, so it's not view
     */
    function exchangeRate() external returns (uint256);

    /**
     * @notice Returns the exchange rate stored without accruing interest
     */
    function exchangeRateStored() external view returns (uint256);

    /**
     * @notice Accrues interest and updates the exchange rate
     */
    function accrueInterest() external;

    /**
     * @notice Mints cTokens for a depositor
     */
    function mint(uint256 mintAmount) external returns (uint256);

    /**
     * @notice Mints cTokens on behalf of a depositor
     * @param payer The address paying the underlying
     * @param onBehalfOf The address receiving the cTokens
     * @param mintAmount The amount of underlying to deposit
     */
    function mint(address payer, address onBehalfOf, uint256 mintAmount) external returns (uint256);

    /**
     * @notice Redeems cTokens for underlying
     */
    function redeem(uint256 redeemTokens) external returns (uint256);

    /**
     * @notice Redeems cTokens on behalf of an account
     * @param from The address whose cTokens are burned
     * @param to The address receiving the underlying
     * @param redeemTokens The amount of cTokens to redeem
     */
    function redeem(address from, address to, uint256 redeemTokens) external returns (uint256);

    /**
     * @notice Redeems cTokens for a specific amount of underlying
     */
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    /**
     * @notice Borrows underlying from the market
     */
    function borrow(uint256 borrowAmount) external;

    /**
     * @notice Borrows underlying on behalf of an account
     * @param borrower The address receiving the debt and underlying
     * @param borrowAmount The amount of underlying to borrow
     */
    function borrow(address borrower, uint256 borrowAmount) external;

    /**
     * @notice Repays a borrow for msg.sender
     */
    function repayBorrow(uint256 repayAmount) external returns (uint256);

    /**
     * @notice Repays a borrow on behalf of an account
     * @param payer The address paying the underlying
     * @param borrower The address whose debt is reduced
     * @param repayAmount The amount of underlying to repay
     */
    function repayBorrow(address payer, address borrower, uint256 repayAmount) external returns (uint256);

    /**
     * @notice Repays a borrow on behalf of another account
     */
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);

    /**
     * @notice Liquidates a borrow
     */
    function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral)
        external
        returns (uint256 seizeTokens);

    /**
     * @notice Returns the borrow balance of an account including interest
     */
    function borrowBalanceCurrent(address account) external returns (uint256);

    /**
     * @notice Returns the stored borrow balance without accruing
     */
    function borrowBalanceStored(address account) external view returns (uint256);

    /**
     * @notice Returns total borrows including accrued interest
     */
    function totalBorrowsCurrent() external returns (uint256);

    /**
     * @notice Returns stored total borrows
     */
    function totalBorrows() external view returns (uint256);

    /**
     * @notice Returns total reserves
     */
    function totalReserves() external view returns (uint256);

    /**
     * @notice Returns the reserve factor
     */
    function reserveFactorMantissa() external view returns (uint256);

    /**
     * @notice Returns the interest rate model
     */
    function interestRateModel() external view returns (address);

    /**
     * @notice Returns the accrual block timestamp
     */
    function accrualBlockTimestamp() external view returns (uint256);

    /**
     * @notice Returns the borrow index
     */
    function borrowIndex() external view returns (uint256);

    /**
     * @notice Returns available cash in the market
     */
    function getCash() external view returns (uint256);

    /**
     * @notice Seizes collateral tokens during liquidation
     */
    function seize(address liquidator, address borrower, uint256 seizeTokens) external;

    /**
     * @notice Sets the reserve factor
     */
    function setReserveFactor(uint256 newReserveFactorMantissa) external;

    /**
     * @notice Sets the interest rate model
     */
    function setInterestRateModel(address newInterestRateModel) external;
}
