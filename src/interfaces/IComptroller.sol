// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IComptroller
 * @notice Interface for Compound v2-style comptroller
 */
interface IComptroller {
    function getPriceOracle() external view returns (address);

    function paused() external view returns (bool);

    function closeFactorMantissa() external view returns (uint256);

    function liquidationIncentiveMantissa() external view returns (uint256);

    function isMarketListed(address cToken) external view returns (bool);

    function getAllMarkets() external view returns (address[] memory);

    function enterMarkets(address[] calldata cTokens) external;

    function exitMarket(address cToken) external;

    function getAccountLiquidity(address account)
        external
        view
        returns (uint256 liquidity, uint256 shortfall);

    function getHypotheticalAccountLiquidity(
        address account,
        address cTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) external view returns (uint256 liquidity, uint256 shortfall);

    function mintAllowed(address cToken, address minter, uint256 mintAmount) external view;

    function redeemAllowed(address cToken, address redeemer, uint256 redeemTokens) external view;

    function borrowAllowed(address cToken, address borrower, uint256 borrowAmount) external view;

    function repayBorrowAllowed(address cToken, address payer, address borrower, uint256 repayAmount) external view;

    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external view;

    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external view;

    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint256 repayAmount
    ) external view returns (uint256 seizeTokens);
}
