// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ReentrancyGuardUpgradeable} from "../libraries/ReentrancyGuardStorage.sol";
import {ComptrollerStorage} from "./ComptrollerStorage.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {ILendingToken} from "../interfaces/ILendingToken.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title Comptroller
 * @notice Compound v2-style risk manager for multiple cTokens
 * @dev Uses ERC-7201 namespaced storage
 */
contract Comptroller is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using WadRayMath for uint256;
    using ComptrollerStorage for ComptrollerStorage.Layout;

    /// @notice Emitted when a market is listed
    event MarketListed(address indexed cToken, uint256 collateralFactor);

    /// @notice Emitted when a user enters a market
    event MarketEntered(address indexed account, address indexed cToken);

    /// @notice Emitted when a user exits a market
    event MarketExited(address indexed account, address indexed cToken);

    /// @notice Emitted when a market collateral factor is updated
    event NewCollateralFactor(address indexed cToken, uint256 oldFactor, uint256 newFactor);

    /// @notice Emitted when close factor is updated
    event CloseFactorUpdated(uint256 oldCloseFactor, uint256 newCloseFactor);

    /// @notice Emitted when liquidation incentive is updated
    event LiquidationIncentiveUpdated(uint256 oldIncentive, uint256 newIncentive);

    /// @notice Emitted when the protocol is paused/unpaused
    event PausedStatusChanged(bool paused);

    /// @notice Emitted when the price oracle is updated
    event PriceOracleUpdated(address indexed newOracle);

    /// @notice Modifier to check if protocol is not paused
    modifier whenNotPaused() {
        if (ComptrollerStorage.layout().paused) revert Errors.Paused();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the comptroller
     * @param owner_ The owner address
     * @param priceOracle_ The price oracle address
     */
    function initialize(address owner_, address priceOracle_) external initializer {
        if (owner_ == address(0)) revert Errors.ZeroAddress();
        if (priceOracle_ == address(0)) revert Errors.ZeroAddress();

        __Ownable_init(owner_);
        __ReentrancyGuard_init();

        ComptrollerStorage.Layout storage $ = ComptrollerStorage.layout();
        $.version = 1;
        $.priceOracle = priceOracle_;
        $.closeFactorMantissa = 0.5e18;
        $.liquidationIncentiveMantissa = 1.05e18;
    }

    /**
     * @notice Returns the contract version
     */
    function version() external view returns (uint256) {
        return ComptrollerStorage.layout().version;
    }

    /**
     * @notice Returns the price oracle address
     */
    function getPriceOracle() external view returns (address) {
        return ComptrollerStorage.layout().priceOracle;
    }

    /**
     * @notice Sets the price oracle
     */
    function setPriceOracle(address oracle) external onlyOwner {
        if (oracle == address(0)) revert Errors.ZeroAddress();
        ComptrollerStorage.layout().priceOracle = oracle;
        emit PriceOracleUpdated(oracle);
    }

    /**
     * @notice Returns whether the protocol is paused
     */
    function paused() external view returns (bool) {
        return ComptrollerStorage.layout().paused;
    }

    /**
     * @notice Pauses/unpauses the protocol
     */
    function setPaused(bool paused_) external onlyOwner {
        ComptrollerStorage.layout().paused = paused_;
        emit PausedStatusChanged(paused_);
    }

    /**
     * @notice Returns the close factor
     */
    function closeFactorMantissa() external view returns (uint256) {
        return ComptrollerStorage.layout().closeFactorMantissa;
    }

    /**
     * @notice Returns the liquidation incentive
     */
    function liquidationIncentiveMantissa() external view returns (uint256) {
        return ComptrollerStorage.layout().liquidationIncentiveMantissa;
    }

    /**
     * @notice Sets the close factor
     */
    function setCloseFactor(uint256 newCloseFactorMantissa) external onlyOwner {
        if (newCloseFactorMantissa > WadRayMath.WAD) revert Errors.InvalidAmount();
        ComptrollerStorage.Layout storage $ = ComptrollerStorage.layout();
        uint256 oldCloseFactor = $.closeFactorMantissa;
        $.closeFactorMantissa = newCloseFactorMantissa;
        emit CloseFactorUpdated(oldCloseFactor, newCloseFactorMantissa);
    }

    /**
     * @notice Sets the liquidation incentive
     */
    function setLiquidationIncentive(uint256 newLiquidationIncentiveMantissa) external onlyOwner {
        if (newLiquidationIncentiveMantissa < WadRayMath.WAD) revert Errors.InvalidAmount();
        ComptrollerStorage.Layout storage $ = ComptrollerStorage.layout();
        uint256 oldIncentive = $.liquidationIncentiveMantissa;
        $.liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;
        emit LiquidationIncentiveUpdated(oldIncentive, newLiquidationIncentiveMantissa);
    }

    /**
     * @notice Lists a new market
     */
    function supportMarket(address cToken, uint256 collateralFactorMantissa) external onlyOwner {
        if (cToken == address(0)) revert Errors.ZeroAddress();
        if (collateralFactorMantissa > WadRayMath.WAD) revert Errors.InvalidCollateralFactor();

        ComptrollerStorage.Layout storage $ = ComptrollerStorage.layout();
        ComptrollerStorage.Market storage market = $.markets[cToken];
        if (market.isListed) revert Errors.MarketAlreadyListed();

        market.isListed = true;
        market.collateralFactorMantissa = collateralFactorMantissa;
        $.allMarkets.push(cToken);

        emit MarketListed(cToken, collateralFactorMantissa);
    }

    /**
     * @notice Sets collateral factor for a market
     */
    function setCollateralFactor(address cToken, uint256 newCollateralFactorMantissa) external onlyOwner {
        if (newCollateralFactorMantissa > WadRayMath.WAD) revert Errors.InvalidCollateralFactor();

        ComptrollerStorage.Layout storage $ = ComptrollerStorage.layout();
        ComptrollerStorage.Market storage market = $.markets[cToken];
        if (!market.isListed) revert Errors.MarketNotListed();

        uint256 oldFactor = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        emit NewCollateralFactor(cToken, oldFactor, newCollateralFactorMantissa);
    }

    /**
     * @notice Returns whether a market is listed
     */
    function isMarketListed(address cToken) external view returns (bool) {
        return ComptrollerStorage.layout().markets[cToken].isListed;
    }

    /**
     * @notice Returns market configuration
     */
    function getMarketConfiguration(address cToken) external view returns (uint256 collateralFactor, bool isListed) {
        ComptrollerStorage.Market storage market = ComptrollerStorage.layout().markets[cToken];
        return (market.collateralFactorMantissa, market.isListed);
    }

    /**
     * @notice Returns the list of all markets
     */
    function getAllMarkets() external view returns (address[] memory) {
        return ComptrollerStorage.layout().allMarkets;
    }

    /**
     * @notice Enters multiple markets to use supplied assets as collateral
     */
    function enterMarkets(address[] calldata cTokens) external whenNotPaused {
        ComptrollerStorage.Layout storage $ = ComptrollerStorage.layout();

        for (uint256 i = 0; i < cTokens.length; i++) {
            address cToken = cTokens[i];
            ComptrollerStorage.Market storage market = $.markets[cToken];
            if (!market.isListed) revert Errors.MarketNotListed();

            if (!$.accountMembership[msg.sender][cToken]) {
                $.accountMembership[msg.sender][cToken] = true;
                emit MarketEntered(msg.sender, cToken);
            }
        }
    }

    /**
     * @notice Exits a market, disabling a supplied asset as collateral
     */
    function exitMarket(address cToken) external whenNotPaused {
        ComptrollerStorage.Layout storage $ = ComptrollerStorage.layout();
        ComptrollerStorage.Market storage market = $.markets[cToken];
        if (!market.isListed) revert Errors.MarketNotListed();
        if (!$.accountMembership[msg.sender][cToken]) revert Errors.NotInMarket();

        // Cannot exit if there is outstanding borrow in this market
        if (ILendingToken(cToken).borrowBalanceStored(msg.sender) != 0) {
            revert Errors.ExitMarketNotAllowed();
        }

        uint256 cTokenBalance = ILendingToken(cToken).balanceOf(msg.sender);
        (uint256 liquidity, uint256 shortfall) = _getHypotheticalAccountLiquidity(
            msg.sender,
            cToken,
            cTokenBalance,
            0
        );

        if (shortfall > 0) revert Errors.ExitMarketNotAllowed();

        $.accountMembership[msg.sender][cToken] = false;
        emit MarketExited(msg.sender, cToken);
    }

    /**
     * @notice Returns account liquidity and shortfall (both in base currency)
     */
    function getAccountLiquidity(address account)
        external
        view
        returns (uint256 liquidity, uint256 shortfall)
    {
        return _getHypotheticalAccountLiquidity(account, address(0), 0, 0);
    }

    /**
     * @notice Returns hypothetical account liquidity and shortfall
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address cTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) external view returns (uint256 liquidity, uint256 shortfall) {
        return _getHypotheticalAccountLiquidity(account, cTokenModify, redeemTokens, borrowAmount);
    }

    /**
     * @notice Checks if mint is allowed
     */
    function mintAllowed(address cToken, address, uint256) external view {
        if (ComptrollerStorage.layout().paused) revert Errors.Paused();
        if (!ComptrollerStorage.layout().markets[cToken].isListed) revert Errors.MarketNotListed();
    }

    /**
     * @notice Checks if redeem is allowed
     */
    function redeemAllowed(address cToken, address redeemer, uint256 redeemTokens) external view {
        ComptrollerStorage.Layout storage $ = ComptrollerStorage.layout();
        if ($.paused) revert Errors.Paused();
        if (!$.markets[cToken].isListed) revert Errors.MarketNotListed();

        if (!$.accountMembership[redeemer][cToken]) {
            return;
        }

        (, uint256 shortfall) = _getHypotheticalAccountLiquidity(redeemer, cToken, redeemTokens, 0);
        if (shortfall > 0) revert Errors.InsufficientLiquidity();
    }

    /**
     * @notice Checks if borrow is allowed
     */
    function borrowAllowed(address cToken, address borrower, uint256 borrowAmount) external view {
        ComptrollerStorage.Layout storage $ = ComptrollerStorage.layout();
        if ($.paused) revert Errors.Paused();
        if (!$.markets[cToken].isListed) revert Errors.MarketNotListed();

        (, uint256 shortfall) = _getHypotheticalAccountLiquidity(borrower, cToken, 0, borrowAmount);
        if (shortfall > 0) revert Errors.InsufficientCollateral();
    }

    /**
     * @notice Checks if repay is allowed
     */
    function repayBorrowAllowed(address cToken, address, address, uint256) external view {
        if (ComptrollerStorage.layout().paused) revert Errors.Paused();
        if (!ComptrollerStorage.layout().markets[cToken].isListed) revert Errors.MarketNotListed();
    }

    /**
     * @notice Checks if liquidation is allowed
     */
    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address,
        address borrower,
        uint256 repayAmount
    ) external view {
        ComptrollerStorage.Layout storage $ = ComptrollerStorage.layout();
        if ($.paused) revert Errors.Paused();
        if (!$.markets[cTokenBorrowed].isListed || !$.markets[cTokenCollateral].isListed) {
            revert Errors.MarketNotListed();
        }

        (, uint256 shortfall) = _getHypotheticalAccountLiquidity(borrower, address(0), 0, 0);
        if (shortfall == 0) revert Errors.NotLiquidatable();

        uint256 borrowBalance = ILendingToken(cTokenBorrowed).borrowBalanceStored(borrower);
        uint256 maxRepay = borrowBalance.wadMul($.closeFactorMantissa);
        if (repayAmount > maxRepay) revert Errors.LiquidationAmountTooHigh();
    }

    /**
     * @notice Checks if seize is allowed
     */
    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address,
        address,
        uint256
    ) external view {
        ComptrollerStorage.Layout storage $ = ComptrollerStorage.layout();
        if ($.paused) revert Errors.Paused();
        if (!$.markets[cTokenCollateral].isListed || !$.markets[cTokenBorrowed].isListed) {
            revert Errors.MarketNotListed();
        }
    }

    /**
     * @notice Calculates seize tokens for liquidation
     */
    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint256 repayAmount
    ) external view returns (uint256 seizeTokens) {
        ComptrollerStorage.Layout storage $ = ComptrollerStorage.layout();
        IPriceOracle oracle = IPriceOracle($.priceOracle);

        uint256 priceBorrowed = oracle.getAssetPrice(ILendingToken(cTokenBorrowed).underlying());
        uint256 priceCollateral = oracle.getAssetPrice(ILendingToken(cTokenCollateral).underlying());

        // Value of repaid amount in base currency (8 decimals)
        uint256 repayValue = repayAmount * priceBorrowed / 1e18;
        uint256 seizeValue = repayValue.wadMul($.liquidationIncentiveMantissa);

        // Convert seize value to collateral amount, then to cTokens
        uint256 seizeAmount = seizeValue * 1e18 / priceCollateral;
        uint256 exchangeRate = ILendingToken(cTokenCollateral).exchangeRateStored();

        seizeTokens = seizeAmount.wadDiv(exchangeRate);
    }

    /**
     * @notice Internal liquidity calculation
     */
    function _getHypotheticalAccountLiquidity(
        address account,
        address cTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) internal view returns (uint256 liquidity, uint256 shortfall) {
        ComptrollerStorage.Layout storage $ = ComptrollerStorage.layout();
        IPriceOracle oracle = IPriceOracle($.priceOracle);

        uint256 sumCollateral;
        uint256 sumBorrow;

        address[] storage markets = $.allMarkets;
        for (uint256 i = 0; i < markets.length; i++) {
            address cToken = markets[i];
            ComptrollerStorage.Market storage market = $.markets[cToken];
            if (!market.isListed) continue;

            uint256 price = oracle.getAssetPrice(ILendingToken(cToken).underlying());
            uint256 exchangeRate = ILendingToken(cToken).exchangeRateStored();

            uint256 tokens = ILendingToken(cToken).balanceOf(account);
            uint256 borrowBalance = ILendingToken(cToken).borrowBalanceStored(account);

            if ($.accountMembership[account][cToken]) {
                uint256 collateralAmount = tokens.wadMul(exchangeRate);
                uint256 collateralValue = collateralAmount * price / 1e18;
                uint256 collateralValueAdjusted = collateralValue.wadMul(market.collateralFactorMantissa);
                sumCollateral += collateralValueAdjusted;
            }

            if (borrowBalance > 0) {
                uint256 borrowValue = borrowBalance * price / 1e18;
                sumBorrow += borrowValue;
            }

            if (cToken == cTokenModify) {
                if (redeemTokens > 0 && $.accountMembership[account][cToken]) {
                    uint256 redeemAmount = redeemTokens.wadMul(exchangeRate);
                    uint256 redeemValue = redeemAmount * price / 1e18;
                    uint256 redeemValueAdjusted = redeemValue.wadMul(market.collateralFactorMantissa);
                    sumCollateral = sumCollateral > redeemValueAdjusted
                        ? sumCollateral - redeemValueAdjusted
                        : 0;
                }

                if (borrowAmount > 0) {
                    uint256 borrowValueDelta = borrowAmount * price / 1e18;
                    sumBorrow += borrowValueDelta;
                }
            }
        }

        if (sumCollateral > sumBorrow) {
            liquidity = sumCollateral - sumBorrow;
            shortfall = 0;
        } else {
            liquidity = 0;
            shortfall = sumBorrow - sumCollateral;
        }
    }

    /**
     * @notice Authorizes an upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        if (newImplementation == address(0)) revert Errors.InvalidImplementation();
        ComptrollerStorage.layout().version++;
    }
}
