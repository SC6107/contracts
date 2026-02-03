// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DataTypes
 * @notice Library containing data structures used in the lending protocol
 */
library DataTypes {
    /**
     * @notice Reserve/market data for an asset
     */
    struct ReserveData {
        /// @notice The lending token (dToken) address
        address lendingToken;
        /// @notice The interest rate model address
        address interestRateModel;
        /// @notice Collateral factor (max LTV) in WAD (1e18 = 100%)
        uint256 collateralFactor;
        /// @notice Liquidation bonus in WAD (1.05e18 = 5% bonus)
        uint256 liquidationBonus;
        /// @notice Whether the reserve is active
        bool isActive;
        /// @notice Reserve index in the reserves list
        uint256 id;
    }

    /**
     * @notice User configuration for collateral and borrowing
     */
    struct UserConfigurationMap {
        /// @notice Bitmap: even bits = using as collateral, odd bits = borrowing
        uint256 data;
    }

    /**
     * @notice User account data
     */
    struct UserAccountData {
        /// @notice Total collateral value in base currency (8 decimals)
        uint256 totalCollateralValue;
        /// @notice Total debt value in base currency (8 decimals)
        uint256 totalDebtValue;
        /// @notice Available borrows in base currency (8 decimals)
        uint256 availableBorrowsValue;
        /// @notice Current weighted liquidation threshold
        uint256 currentLiquidationThreshold;
        /// @notice Loan-to-value ratio
        uint256 ltv;
        /// @notice Health factor (1e18 = 1.0)
        uint256 healthFactor;
    }

    /**
     * @notice Interest rate model parameters
     */
    struct InterestRateModelParams {
        /// @notice Base rate per year (WAD)
        uint256 baseRatePerYear;
        /// @notice Multiplier per year before kink (WAD)
        uint256 multiplierPerYear;
        /// @notice Jump multiplier per year after kink (WAD)
        uint256 jumpMultiplierPerYear;
        /// @notice Utilization rate kink point (WAD)
        uint256 kink;
    }

    /**
     * @notice Liquidation parameters
     */
    struct LiquidationParams {
        address collateralAsset;
        address debtAsset;
        address borrower;
        uint256 debtToCover;
        address liquidator;
    }
}
