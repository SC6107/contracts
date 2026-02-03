// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILendingPool
 * @notice Interface for the main lending pool contract
 */
interface ILendingPool {
    /**
     * @notice Deposits assets into the lending pool
     * @param asset The address of the asset to deposit
     * @param amount The amount to deposit
     * @param onBehalfOf The address that will receive the dTokens
     * @return The amount of dTokens minted
     */
    function deposit(address asset, uint256 amount, address onBehalfOf) external returns (uint256);

    /**
     * @notice Withdraws assets from the lending pool
     * @param asset The address of the asset to withdraw
     * @param amount The amount to withdraw (use type(uint256).max for full balance)
     * @param to The address that will receive the underlying
     * @return The actual amount withdrawn
     */
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    /**
     * @notice Borrows assets from the lending pool
     * @param asset The address of the asset to borrow
     * @param amount The amount to borrow
     * @param onBehalfOf The address that will receive the debt
     */
    function borrow(address asset, uint256 amount, address onBehalfOf) external;

    /**
     * @notice Repays a borrowed asset
     * @param asset The address of the borrowed asset
     * @param amount The amount to repay (use type(uint256).max for full debt)
     * @param onBehalfOf The address of the borrower
     * @return The actual amount repaid
     */
    function repay(address asset, uint256 amount, address onBehalfOf) external returns (uint256);

    /**
     * @notice Liquidates an undercollateralized position
     * @param collateralAsset The address of the collateral asset
     * @param debtAsset The address of the debt asset
     * @param borrower The address of the borrower to liquidate
     * @param debtToCover The amount of debt to cover
     * @return The amount of collateral seized
     */
    function liquidate(
        address collateralAsset,
        address debtAsset,
        address borrower,
        uint256 debtToCover
    ) external returns (uint256);

    /**
     * @notice Returns the lending token (dToken) for an asset
     * @param asset The underlying asset address
     * @return The dToken address
     */
    function getLendingToken(address asset) external view returns (address);

    /**
     * @notice Returns the user's account data
     * @param user The address of the user
     * @return totalCollateralValue The total collateral value in base currency
     * @return totalDebtValue The total debt value in base currency
     * @return availableBorrowsValue The available borrow capacity
     * @return currentLiquidationThreshold The weighted liquidation threshold
     * @return ltv The loan-to-value ratio
     * @return healthFactor The health factor (1e18 = 1.0)
     */
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralValue,
            uint256 totalDebtValue,
            uint256 availableBorrowsValue,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    /**
     * @notice Initializes a new reserve/market
     * @param asset The underlying asset
     * @param lendingToken The dToken address
     * @param interestRateModel The interest rate model address
     * @param collateralFactor The collateral factor (scaled by 1e18)
     * @param liquidationThreshold The liquidation threshold (scaled by 1e18)
     * @param liquidationBonus The liquidation bonus (scaled by 1e18)
     */
    function initReserve(
        address asset,
        address lendingToken,
        address interestRateModel,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external;

    /**
     * @notice Sets the price oracle
     * @param oracle The oracle address
     */
    function setPriceOracle(address oracle) external;

    /**
     * @notice Returns the price oracle
     * @return The oracle address
     */
    function getPriceOracle() external view returns (address);

    /**
     * @notice Sets whether an asset can be used as collateral
     * @param asset The asset address
     * @param useAsCollateral True to enable as collateral
     */
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;

    /**
     * @notice Pauses/unpauses the protocol
     * @param paused True to pause
     */
    function setPaused(bool paused) external;

    /**
     * @notice Returns if the protocol is paused
     * @return True if paused
     */
    function paused() external view returns (bool);

    /**
     * @notice Returns the reserve configuration
     * @param asset The asset address
     * @return collateralFactor The collateral factor
     * @return liquidationThreshold The liquidation threshold
     * @return liquidationBonus The liquidation bonus
     * @return isActive Whether the reserve is active
     */
    function getReserveConfiguration(address asset)
        external
        view
        returns (uint256 collateralFactor, uint256 liquidationThreshold, uint256 liquidationBonus, bool isActive);

    /**
     * @notice Returns the list of supported assets
     * @return The array of asset addresses
     */
    function getReservesList() external view returns (address[] memory);
}
