// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Errors
 * @notice Library containing custom error definitions for the protocol
 */
library Errors {
    // General errors
    error ZeroAddress();
    error ZeroAmount();
    error InvalidAmount();
    error Unauthorized();
    error Paused();
    error NotPaused();

    // Lending pool errors
    error ReserveNotActive();
    error ReserveAlreadyExists();
    error ReserveNotFound();
    error InsufficientCollateral();
    error InsufficientLiquidity();
    error BorrowNotAllowed();
    error RepayMoreThanDebt();
    error WithdrawMoreThanBalance();

    // Comptroller errors
    error MarketNotListed();
    error MarketAlreadyListed();
    error NotInMarket();
    error ExitMarketNotAllowed();

    // Health factor errors
    error HealthFactorOk();
    error HealthFactorBelowThreshold();
    error InvalidHealthFactor();

    // Liquidation errors
    error NotLiquidatable();
    error LiquidationAmountTooHigh();
    error SelfLiquidation();
    error CollateralCannotBeLiquidated();

    // LendingToken errors
    error OnlyLendingPool();
    error MintFailed();
    error RedeemFailed();
    error BorrowFailed();
    error RepayFailed();
    error SeizeFailed();
    error AccrueInterestFailed();

    // Interest rate errors
    error InvalidInterestRateModel();
    error InvalidReserveFactor();
    error InvalidCollateralFactor();
    error InvalidLiquidationThreshold();
    error InvalidLiquidationBonus();

    // Oracle errors
    error InvalidPrice();
    error StalePrice();
    error OracleNotSet();
    error PriceFeedNotFound();

    // Liquidity mining errors
    error RewardPeriodNotFinished();
    error RewardTooHigh();
    error StakingTokenNotSet();
    error RewardsTokenNotSet();

    // Governance errors
    error ProposalThresholdNotMet();
    error VotingPeriodNotEnded();
    error ProposalNotSuccessful();
    error TimelockDelayNotMet();
    error InvalidTimelockDelay();
    error OperationNotReady();
    error OperationAlreadyExecuted();

    // Upgrade errors
    error InvalidImplementation();
    error NotUpgradeAuthorized();
    error UpgradeNotScheduled();
}
