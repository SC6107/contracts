// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";

/**
 * @title JumpRateModel
 * @notice Compound-style interest rate model with a kink
 * @dev Non-upgradeable, immutable parameters
 *
 * Interest rate formula:
 * If utilization < kink:
 *   BorrowRate = baseRate + utilization * multiplier
 * Else:
 *   BorrowRate = baseRate + kink * multiplier + (utilization - kink) * jumpMultiplier
 *
 * SupplyRate = BorrowRate * utilization * (1 - reserveFactor)
 */
contract JumpRateModel is IInterestRateModel {
    using WadRayMath for uint256;

    /// @notice Seconds per year (approximate)
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice Base interest rate per second (scaled by 1e18)
    uint256 public immutable baseRatePerSecond;

    /// @notice Multiplier per second before kink (scaled by 1e18)
    uint256 public immutable multiplierPerSecond;

    /// @notice Jump multiplier per second after kink (scaled by 1e18)
    uint256 public immutable jumpMultiplierPerSecond;

    /// @notice Utilization rate at which jump multiplier kicks in (scaled by 1e18)
    uint256 public immutable kink;

    /**
     * @notice Constructs the interest rate model
     * @param baseRatePerYear_ Base rate per year (scaled by 1e18)
     * @param multiplierPerYear_ Multiplier per year before kink (scaled by 1e18)
     * @param jumpMultiplierPerYear_ Jump multiplier per year after kink (scaled by 1e18)
     * @param kink_ Utilization rate at kink point (scaled by 1e18)
     */
    constructor(
        uint256 baseRatePerYear_,
        uint256 multiplierPerYear_,
        uint256 jumpMultiplierPerYear_,
        uint256 kink_
    ) {
        baseRatePerSecond = baseRatePerYear_ / SECONDS_PER_YEAR;
        multiplierPerSecond = multiplierPerYear_ / SECONDS_PER_YEAR;
        jumpMultiplierPerSecond = jumpMultiplierPerYear_ / SECONDS_PER_YEAR;
        kink = kink_;
    }

    /**
     * @inheritdoc IInterestRateModel
     */
    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) public pure returns (uint256) {
        // Utilization = Borrows / (Cash + Borrows - Reserves)
        if (borrows == 0) {
            return 0;
        }

        uint256 totalAssets = cash + borrows;
        if (totalAssets <= reserves) {
            return 0;
        }

        return borrows.wadDiv(totalAssets - reserves);
    }

    /**
     * @inheritdoc IInterestRateModel
     */
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) public view returns (uint256) {
        uint256 util = utilizationRate(cash, borrows, reserves);

        if (util <= kink) {
            // Normal rate: baseRate + utilization * multiplier
            return baseRatePerSecond + util.wadMul(multiplierPerSecond);
        } else {
            // Jump rate: baseRate + kink * multiplier + (utilization - kink) * jumpMultiplier
            uint256 normalRate = baseRatePerSecond + kink.wadMul(multiplierPerSecond);
            uint256 excessUtil = util - kink;
            return normalRate + excessUtil.wadMul(jumpMultiplierPerSecond);
        }
    }

    /**
     * @inheritdoc IInterestRateModel
     */
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) public view returns (uint256) {
        uint256 oneMinusReserveFactor = WadRayMath.WAD - reserveFactorMantissa;
        uint256 borrowRate = getBorrowRate(cash, borrows, reserves);
        uint256 rateToPool = borrowRate.wadMul(oneMinusReserveFactor);
        uint256 util = utilizationRate(cash, borrows, reserves);
        return util.wadMul(rateToPool);
    }

    /**
     * @notice Returns the borrow rate per year
     * @param cash The total cash in the market
     * @param borrows The total borrows in the market
     * @param reserves The total reserves in the market
     * @return The borrow rate per year (scaled by 1e18)
     */
    function getBorrowRatePerYear(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256) {
        return getBorrowRate(cash, borrows, reserves) * SECONDS_PER_YEAR;
    }

    /**
     * @notice Returns the supply rate per year
     * @param cash The total cash in the market
     * @param borrows The total borrows in the market
     * @param reserves The total reserves in the market
     * @param reserveFactorMantissa The reserve factor
     * @return The supply rate per year (scaled by 1e18)
     */
    function getSupplyRatePerYear(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external view returns (uint256) {
        return getSupplyRate(cash, borrows, reserves, reserveFactorMantissa) * SECONDS_PER_YEAR;
    }
}
