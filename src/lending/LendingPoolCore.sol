// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {ReentrancyGuardUpgradeable} from "../libraries/ReentrancyGuardStorage.sol";
import {ILendingToken} from "../interfaces/ILendingToken.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {LendingPoolStorage} from "./LendingPoolStorage.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title LendingPoolCore
 * @notice UUPS upgradeable main lending pool contract
 * @dev Uses ERC-7201 namespaced storage
 */
contract LendingPoolCore is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ILendingPool
{
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using LendingPoolStorage for LendingPoolStorage.Layout;

    /// @notice Emitted when a deposit is made
    event Deposit(address indexed asset, address indexed user, address indexed onBehalfOf, uint256 amount);

    /// @notice Emitted when a withdrawal is made
    event Withdraw(address indexed asset, address indexed user, address indexed to, uint256 amount);

    /// @notice Emitted when a borrow is made
    event Borrow(address indexed asset, address indexed user, address indexed onBehalfOf, uint256 amount);

    /// @notice Emitted when a repayment is made
    event Repay(address indexed asset, address indexed user, address indexed onBehalfOf, uint256 amount);

    /// @notice Emitted when a liquidation occurs
    event Liquidate(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed borrower,
        uint256 debtToCover,
        uint256 liquidatedCollateral,
        address liquidator
    );

    /// @notice Emitted when a reserve is initialized
    event ReserveInitialized(
        address indexed asset,
        address indexed lendingToken,
        address interestRateModel
    );

    /// @notice Emitted when collateral status changes
    event CollateralStatusChanged(address indexed user, address indexed asset, bool useAsCollateral);

    /// @notice Emitted when the protocol is paused/unpaused
    event PausedStatusChanged(bool paused);

    /// @notice Emitted when the price oracle is updated
    event PriceOracleUpdated(address indexed newOracle);

    /// @notice Modifier to check if protocol is not paused
    modifier whenNotPaused() {
        if (LendingPoolStorage.layout().paused) revert Errors.Paused();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the lending pool
     * @param owner_ The owner address
     * @param priceOracle_ The price oracle address
     */
    function initialize(address owner_, address priceOracle_) external initializer {
        if (owner_ == address(0)) revert Errors.ZeroAddress();
        if (priceOracle_ == address(0)) revert Errors.ZeroAddress();

        __Ownable_init(owner_);
        __ReentrancyGuard_init();

        LendingPoolStorage.Layout storage $ = LendingPoolStorage.layout();
        $.version = 1;
        $.priceOracle = priceOracle_;
        $.closeFactor = 0.5e18; // 50% close factor
        $.maxReserves = 128;
    }

    /**
     * @inheritdoc ILendingPool
     */
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external nonReentrant whenNotPaused returns (uint256) {
        if (amount == 0) revert Errors.ZeroAmount();
        if (onBehalfOf == address(0)) revert Errors.ZeroAddress();

        LendingPoolStorage.Layout storage $ = LendingPoolStorage.layout();
        DataTypes.ReserveData storage reserve = $.reserves[asset];

        if (!reserve.isActive) revert Errors.ReserveNotActive();

        // Mint dTokens - transfer from msg.sender, mint to onBehalfOf
        uint256 mintedTokens = ILendingToken(reserve.lendingToken).mint(msg.sender, onBehalfOf, amount);

        // Enable as collateral by default for new depositors
        if (!$.userUsingAsCollateral[onBehalfOf][asset]) {
            $.userUsingAsCollateral[onBehalfOf][asset] = true;
            emit CollateralStatusChanged(onBehalfOf, asset, true);
        }

        emit Deposit(asset, msg.sender, onBehalfOf, amount);
        return mintedTokens;
    }

    /**
     * @inheritdoc ILendingPool
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external nonReentrant whenNotPaused returns (uint256) {
        if (to == address(0)) revert Errors.ZeroAddress();

        LendingPoolStorage.Layout storage $ = LendingPoolStorage.layout();
        DataTypes.ReserveData storage reserve = $.reserves[asset];

        if (!reserve.isActive) revert Errors.ReserveNotActive();

        ILendingToken lendingToken = ILendingToken(reserve.lendingToken);
        uint256 userBalance = IERC20(reserve.lendingToken).balanceOf(msg.sender);

        uint256 amountToWithdraw;
        if (amount == type(uint256).max) {
            amountToWithdraw = userBalance.wadMul(lendingToken.exchangeRate());
        } else {
            amountToWithdraw = amount;
        }

        // Calculate tokens to redeem
        uint256 tokensToRedeem = amountToWithdraw.wadDiv(lendingToken.exchangeRateStored());
        if (tokensToRedeem > userBalance) revert Errors.WithdrawMoreThanBalance();

        // Check health factor after withdrawal
        _validateHealthFactorAfterWithdraw(msg.sender, asset, amountToWithdraw);

        // Redeem tokens - burn from msg.sender, transfer to recipient
        uint256 actualAmount = lendingToken.redeem(msg.sender, to, tokensToRedeem);

        emit Withdraw(asset, msg.sender, to, actualAmount);
        return actualAmount;
    }

    /**
     * @inheritdoc ILendingPool
     */
    function borrow(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external nonReentrant whenNotPaused {
        if (amount == 0) revert Errors.ZeroAmount();
        if (onBehalfOf == address(0)) revert Errors.ZeroAddress();

        LendingPoolStorage.Layout storage $ = LendingPoolStorage.layout();
        DataTypes.ReserveData storage reserve = $.reserves[asset];

        if (!reserve.isActive) revert Errors.ReserveNotActive();

        // Check if user has enough collateral
        _validateBorrow(onBehalfOf, asset, amount);

        // Execute borrow
        ILendingToken(reserve.lendingToken).borrow(onBehalfOf, amount);

        emit Borrow(asset, msg.sender, onBehalfOf, amount);
    }

    /**
     * @inheritdoc ILendingPool
     */
    function repay(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external nonReentrant whenNotPaused returns (uint256) {
        if (onBehalfOf == address(0)) revert Errors.ZeroAddress();

        LendingPoolStorage.Layout storage $ = LendingPoolStorage.layout();
        DataTypes.ReserveData storage reserve = $.reserves[asset];

        if (!reserve.isActive) revert Errors.ReserveNotActive();

        uint256 paybackAmount = ILendingToken(reserve.lendingToken).repayBorrow(
            msg.sender,
            onBehalfOf,
            amount
        );

        emit Repay(asset, msg.sender, onBehalfOf, paybackAmount);
        return paybackAmount;
    }

    /**
     * @inheritdoc ILendingPool
     */
    function liquidate(
        address collateralAsset,
        address debtAsset,
        address borrower,
        uint256 debtToCover
    ) external nonReentrant whenNotPaused returns (uint256) {
        if (borrower == msg.sender) revert Errors.SelfLiquidation();
        if (debtToCover == 0) revert Errors.ZeroAmount();

        LendingPoolStorage.Layout storage $ = LendingPoolStorage.layout();

        // Check if position is liquidatable
        (, , , , , uint256 healthFactor) = getUserAccountData(borrower);
        if (healthFactor >= WadRayMath.WAD) revert Errors.NotLiquidatable();

        DataTypes.ReserveData storage collateralReserve = $.reserves[collateralAsset];
        DataTypes.ReserveData storage debtReserve = $.reserves[debtAsset];

        if (!collateralReserve.isActive || !debtReserve.isActive) revert Errors.ReserveNotActive();
        if (!$.userUsingAsCollateral[borrower][collateralAsset]) revert Errors.CollateralCannotBeLiquidated();

        // Calculate maximum debt that can be liquidated
        ILendingToken debtToken = ILendingToken(debtReserve.lendingToken);
        uint256 userDebt = debtToken.borrowBalanceCurrent(borrower);
        uint256 maxLiquidatable = userDebt.wadMul($.closeFactor);

        uint256 actualDebtToCover = debtToCover > maxLiquidatable ? maxLiquidatable : debtToCover;

        // Calculate collateral to seize
        uint256 collateralToSeize = _calculateCollateralToSeize(
            collateralAsset,
            debtAsset,
            actualDebtToCover,
            collateralReserve.liquidationBonus
        );

        // Execute liquidation
        // 1. Repay debt
        debtToken.repayBorrow(msg.sender, borrower, actualDebtToCover);

        // 2. Seize collateral
        ILendingToken collateralToken = ILendingToken(collateralReserve.lendingToken);
        uint256 collateralTokensToSeize = collateralToSeize.wadDiv(collateralToken.exchangeRate());
        collateralToken.seize(msg.sender, borrower, collateralTokensToSeize);

        emit Liquidate(collateralAsset, debtAsset, borrower, actualDebtToCover, collateralToSeize, msg.sender);

        return collateralToSeize;
    }

    /**
     * @inheritdoc ILendingPool
     */
    function getLendingToken(address asset) external view returns (address) {
        return LendingPoolStorage.layout().reserves[asset].lendingToken;
    }

    /**
     * @inheritdoc ILendingPool
     */
    function getUserAccountData(address user)
        public
        view
        returns (
            uint256 totalCollateralValue,
            uint256 totalDebtValue,
            uint256 availableBorrowsValue,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        LendingPoolStorage.Layout storage $ = LendingPoolStorage.layout();
        IPriceOracle oracle = IPriceOracle($.priceOracle);

        uint256 totalCollateralInBase;
        uint256 totalDebtInBase;
        uint256 avgLtv;
        uint256 avgLiquidationThreshold;

        for (uint256 i = 0; i < $.reservesList.length; i++) {
            address asset = $.reservesList[i];
            DataTypes.ReserveData storage reserve = $.reserves[asset];

            if (!reserve.isActive) continue;

            ILendingToken lendingToken = ILendingToken(reserve.lendingToken);
            uint256 assetPrice = oracle.getAssetPrice(asset);

            // Calculate collateral value
            if ($.userUsingAsCollateral[user][asset]) {
                uint256 userBalance = IERC20(reserve.lendingToken).balanceOf(user);
                if (userBalance > 0) {
                    uint256 underlyingBalance = userBalance.wadMul(lendingToken.exchangeRateStored());
                    uint256 collateralValueInBase = underlyingBalance * assetPrice / 1e18;
                    totalCollateralInBase += collateralValueInBase;
                    avgLtv += collateralValueInBase.wadMul(reserve.collateralFactor);
                    avgLiquidationThreshold += collateralValueInBase.wadMul(reserve.liquidationThreshold);
                }
            }

            // Calculate debt value
            uint256 userDebt = lendingToken.borrowBalanceStored(user);
            if (userDebt > 0) {
                totalDebtInBase += userDebt * assetPrice / 1e18;
            }
        }

        totalCollateralValue = totalCollateralInBase;
        totalDebtValue = totalDebtInBase;

        if (totalCollateralInBase > 0) {
            // avgLtv and avgLiquidationThreshold already contain weighted values
            // avgLtv = sum(collateralValue * factor) needs to be divided by totalCollateral
            // to get the weighted average factor, keeping WAD precision
            avgLtv = avgLtv.wadDiv(totalCollateralInBase);
            avgLiquidationThreshold = avgLiquidationThreshold.wadDiv(totalCollateralInBase);
        }

        ltv = avgLtv;
        currentLiquidationThreshold = avgLiquidationThreshold;

        if (totalDebtInBase > 0) {
            // availableBorrows = totalCollateral * ltv - debt
            uint256 maxBorrow = totalCollateralInBase.wadMul(avgLtv);
            availableBorrowsValue = maxBorrow > totalDebtInBase ? maxBorrow - totalDebtInBase : 0;
            // healthFactor = (collateral * liquidationThreshold) / debt
            healthFactor = totalCollateralInBase.wadMul(avgLiquidationThreshold).wadDiv(totalDebtInBase);
        } else {
            availableBorrowsValue = totalCollateralInBase.wadMul(avgLtv);
            healthFactor = type(uint256).max;
        }
    }

    /**
     * @inheritdoc ILendingPool
     */
    function initReserve(
        address asset,
        address lendingToken,
        address interestRateModel,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external onlyOwner {
        if (asset == address(0)) revert Errors.ZeroAddress();
        if (lendingToken == address(0)) revert Errors.ZeroAddress();

        LendingPoolStorage.Layout storage $ = LendingPoolStorage.layout();

        if ($.reserves[asset].isActive) revert Errors.ReserveAlreadyExists();
        if ($.reservesList.length >= $.maxReserves) revert Errors.InvalidAmount();
        if (collateralFactor > WadRayMath.WAD) revert Errors.InvalidCollateralFactor();
        if (liquidationThreshold > WadRayMath.WAD) revert Errors.InvalidLiquidationThreshold();
        if (liquidationThreshold < collateralFactor) revert Errors.InvalidLiquidationThreshold();
        if (liquidationBonus < WadRayMath.WAD) revert Errors.InvalidLiquidationBonus();

        $.reserves[asset] = DataTypes.ReserveData({
            lendingToken: lendingToken,
            interestRateModel: interestRateModel,
            collateralFactor: collateralFactor,
            liquidationThreshold: liquidationThreshold,
            liquidationBonus: liquidationBonus,
            isActive: true,
            id: $.reservesList.length
        });

        $.reservesList.push(asset);

        emit ReserveInitialized(asset, lendingToken, interestRateModel);
    }

    /**
     * @inheritdoc ILendingPool
     */
    function setPriceOracle(address oracle) external onlyOwner {
        if (oracle == address(0)) revert Errors.ZeroAddress();
        LendingPoolStorage.layout().priceOracle = oracle;
        emit PriceOracleUpdated(oracle);
    }

    /**
     * @inheritdoc ILendingPool
     */
    function getPriceOracle() external view returns (address) {
        return LendingPoolStorage.layout().priceOracle;
    }

    /**
     * @inheritdoc ILendingPool
     */
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external {
        LendingPoolStorage.Layout storage $ = LendingPoolStorage.layout();

        if (!$.reserves[asset].isActive) revert Errors.ReserveNotActive();

        if (!useAsCollateral) {
            // Validate health factor if disabling collateral
            _validateHealthFactorAfterCollateralDisable(msg.sender, asset);
        }

        $.userUsingAsCollateral[msg.sender][asset] = useAsCollateral;
        emit CollateralStatusChanged(msg.sender, asset, useAsCollateral);
    }

    /**
     * @inheritdoc ILendingPool
     */
    function setPaused(bool paused_) external onlyOwner {
        LendingPoolStorage.layout().paused = paused_;
        emit PausedStatusChanged(paused_);
    }

    /**
     * @inheritdoc ILendingPool
     */
    function paused() external view returns (bool) {
        return LendingPoolStorage.layout().paused;
    }

    /**
     * @inheritdoc ILendingPool
     */
    function getReserveConfiguration(address asset)
        external
        view
        returns (uint256 collateralFactor, uint256 liquidationThreshold, uint256 liquidationBonus, bool isActive)
    {
        DataTypes.ReserveData storage reserve = LendingPoolStorage.layout().reserves[asset];
        return (reserve.collateralFactor, reserve.liquidationThreshold, reserve.liquidationBonus, reserve.isActive);
    }

    /**
     * @inheritdoc ILendingPool
     */
    function getReservesList() external view returns (address[] memory) {
        return LendingPoolStorage.layout().reservesList;
    }

    /**
     * @notice Returns the contract version
     * @return The version number
     */
    function version() external view returns (uint256) {
        return LendingPoolStorage.layout().version;
    }

    /**
     * @notice Returns the close factor
     * @return The close factor (scaled by 1e18)
     */
    function closeFactor() external view returns (uint256) {
        return LendingPoolStorage.layout().closeFactor;
    }

    /**
     * @notice Sets the close factor
     * @param newCloseFactor The new close factor
     */
    function setCloseFactor(uint256 newCloseFactor) external onlyOwner {
        if (newCloseFactor > WadRayMath.WAD) revert Errors.InvalidAmount();
        LendingPoolStorage.layout().closeFactor = newCloseFactor;
    }

    /**
     * @notice Validates borrow operation
     */
    function _validateBorrow(address user, address asset, uint256 amount) internal view {
        LendingPoolStorage.Layout storage $ = LendingPoolStorage.layout();
        IPriceOracle oracle = IPriceOracle($.priceOracle);

        (, , uint256 availableBorrows, , , ) = getUserAccountData(user);
        uint256 assetPrice = oracle.getAssetPrice(asset);
        uint256 borrowValueInBase = amount * assetPrice / 1e18;

        if (borrowValueInBase > availableBorrows) revert Errors.InsufficientCollateral();
    }

    /**
     * @notice Validates health factor after withdrawal
     */
    function _validateHealthFactorAfterWithdraw(address user, address asset, uint256 amount) internal view {
        LendingPoolStorage.Layout storage $ = LendingPoolStorage.layout();

        if (!$.userUsingAsCollateral[user][asset]) return;

        (uint256 totalCollateral, uint256 totalDebt, , , , ) = getUserAccountData(user);

        if (totalDebt == 0) return;

        IPriceOracle oracle = IPriceOracle($.priceOracle);
        DataTypes.ReserveData storage reserve = $.reserves[asset];

        uint256 withdrawValueInBase = amount * oracle.getAssetPrice(asset) / 1e18;
        uint256 newCollateral = totalCollateral > withdrawValueInBase ? totalCollateral - withdrawValueInBase : 0;
        uint256 newHealthFactor = newCollateral.wadMul(reserve.liquidationThreshold).wadDiv(totalDebt);

        if (newHealthFactor < WadRayMath.WAD) revert Errors.HealthFactorBelowThreshold();
    }

    /**
     * @notice Validates health factor after disabling collateral
     */
    function _validateHealthFactorAfterCollateralDisable(address user, address asset) internal view {
        LendingPoolStorage.Layout storage $ = LendingPoolStorage.layout();

        (, uint256 totalDebt, , , , ) = getUserAccountData(user);
        if (totalDebt == 0) return;

        ILendingToken lendingToken = ILendingToken($.reserves[asset].lendingToken);
        IPriceOracle oracle = IPriceOracle($.priceOracle);

        uint256 userBalance = IERC20($.reserves[asset].lendingToken).balanceOf(user);
        uint256 underlyingBalance = userBalance.wadMul(lendingToken.exchangeRateStored());
        uint256 collateralValueToRemove = underlyingBalance * oracle.getAssetPrice(asset) / 1e18;

        (uint256 totalCollateral, , , , , uint256 currentHealthFactor) = getUserAccountData(user);

        if (totalCollateral <= collateralValueToRemove) revert Errors.HealthFactorBelowThreshold();

        // Simplified check - actual implementation would recalculate with weighted thresholds
        uint256 newCollateral = totalCollateral - collateralValueToRemove;
        uint256 newHealthFactor = newCollateral.wadMul($.reserves[asset].liquidationThreshold).wadDiv(totalDebt);

        if (newHealthFactor < WadRayMath.WAD) revert Errors.HealthFactorBelowThreshold();
    }

    /**
     * @notice Calculates collateral to seize during liquidation
     */
    function _calculateCollateralToSeize(
        address collateralAsset,
        address debtAsset,
        uint256 debtToCover,
        uint256 liquidationBonus
    ) internal view returns (uint256) {
        LendingPoolStorage.Layout storage $ = LendingPoolStorage.layout();
        IPriceOracle oracle = IPriceOracle($.priceOracle);

        uint256 debtAssetPrice = oracle.getAssetPrice(debtAsset);
        uint256 collateralAssetPrice = oracle.getAssetPrice(collateralAsset);

        // collateralToSeize = debtToCover * debtPrice / collateralPrice * liquidationBonus
        uint256 debtValueInBase = debtToCover * debtAssetPrice / 1e18;
        uint256 collateralAmount = debtValueInBase * 1e18 / collateralAssetPrice;

        return collateralAmount.wadMul(liquidationBonus);
    }

    /**
     * @notice Authorizes an upgrade
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        if (newImplementation == address(0)) revert Errors.InvalidImplementation();
        LendingPoolStorage.layout().version++;
    }
}
