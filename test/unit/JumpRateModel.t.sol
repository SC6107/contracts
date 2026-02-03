// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {JumpRateModel} from "../../src/lending/JumpRateModel.sol";
import {WadRayMath} from "../../src/libraries/WadRayMath.sol";

contract JumpRateModelTest is Test {
    using WadRayMath for uint256;

    JumpRateModel public model;

    // Parameters
    uint256 constant BASE_RATE_PER_YEAR = 0.02e18; // 2%
    uint256 constant MULTIPLIER_PER_YEAR = 0.1e18; // 10%
    uint256 constant JUMP_MULTIPLIER_PER_YEAR = 1e18; // 100%
    uint256 constant KINK = 0.8e18; // 80%
    uint256 constant SECONDS_PER_YEAR = 365 days;

    function setUp() public {
        model = new JumpRateModel(
            BASE_RATE_PER_YEAR,
            MULTIPLIER_PER_YEAR,
            JUMP_MULTIPLIER_PER_YEAR,
            KINK
        );
    }

    function test_InitialParameters() public view {
        assertEq(model.baseRatePerSecond(), BASE_RATE_PER_YEAR / SECONDS_PER_YEAR);
        assertEq(model.multiplierPerSecond(), MULTIPLIER_PER_YEAR / SECONDS_PER_YEAR);
        assertEq(model.jumpMultiplierPerSecond(), JUMP_MULTIPLIER_PER_YEAR / SECONDS_PER_YEAR);
        assertEq(model.kink(), KINK);
    }

    function test_UtilizationRate_ZeroBorrows() public view {
        uint256 util = model.utilizationRate(1000e18, 0, 0);
        assertEq(util, 0);
    }

    function test_UtilizationRate_50Percent() public view {
        // Cash: 500, Borrows: 500, Reserves: 0
        // Utilization = 500 / (500 + 500 - 0) = 0.5
        uint256 util = model.utilizationRate(500e18, 500e18, 0);
        assertApproxEqRel(util, 0.5e18, 0.0001e18);
    }

    function test_UtilizationRate_80Percent() public view {
        // Cash: 200, Borrows: 800, Reserves: 0
        // Utilization = 800 / (200 + 800 - 0) = 0.8
        uint256 util = model.utilizationRate(200e18, 800e18, 0);
        assertApproxEqRel(util, 0.8e18, 0.0001e18);
    }

    function test_UtilizationRate_WithReserves() public view {
        // Cash: 300, Borrows: 700, Reserves: 100
        // Utilization = 700 / (300 + 700 - 100) = 700/900 ≈ 0.778
        uint256 util = model.utilizationRate(300e18, 700e18, 100e18);
        assertApproxEqRel(util, uint256(700e18).wadDiv(900e18), 0.0001e18);
    }

    function test_BorrowRate_BelowKink() public view {
        // At 50% utilization (below 80% kink)
        // BorrowRate = baseRate + utilization * multiplier
        uint256 cash = 500e18;
        uint256 borrows = 500e18;
        uint256 reserves = 0;

        uint256 borrowRate = model.getBorrowRate(cash, borrows, reserves);
        uint256 util = model.utilizationRate(cash, borrows, reserves);

        // Expected: baseRatePerSecond + 0.5 * multiplierPerSecond
        uint256 expected = model.baseRatePerSecond() + util.wadMul(model.multiplierPerSecond());
        assertEq(borrowRate, expected);
    }

    function test_BorrowRate_AtKink() public view {
        // At 80% utilization (exactly at kink)
        uint256 cash = 200e18;
        uint256 borrows = 800e18;
        uint256 reserves = 0;

        uint256 borrowRate = model.getBorrowRate(cash, borrows, reserves);

        // Expected: baseRatePerSecond + 0.8 * multiplierPerSecond
        uint256 expected = model.baseRatePerSecond() + KINK.wadMul(model.multiplierPerSecond());
        assertApproxEqRel(borrowRate, expected, 0.0001e18);
    }

    function test_BorrowRate_AboveKink() public view {
        // At 90% utilization (above 80% kink)
        uint256 cash = 100e18;
        uint256 borrows = 900e18;
        uint256 reserves = 0;

        uint256 borrowRate = model.getBorrowRate(cash, borrows, reserves);
        uint256 util = model.utilizationRate(cash, borrows, reserves);

        // Expected: baseRate + kink * multiplier + (util - kink) * jumpMultiplier
        uint256 normalRate = model.baseRatePerSecond() + KINK.wadMul(model.multiplierPerSecond());
        uint256 excessUtil = util - KINK;
        uint256 expected = normalRate + excessUtil.wadMul(model.jumpMultiplierPerSecond());

        assertApproxEqRel(borrowRate, expected, 0.0001e18);
    }

    function test_BorrowRatePerYear_Calculation() public view {
        uint256 cash = 500e18;
        uint256 borrows = 500e18;
        uint256 reserves = 0;

        uint256 borrowRatePerYear = model.getBorrowRatePerYear(cash, borrows, reserves);
        uint256 borrowRatePerSecond = model.getBorrowRate(cash, borrows, reserves);

        assertEq(borrowRatePerYear, borrowRatePerSecond * SECONDS_PER_YEAR);
    }

    function test_SupplyRate_Calculation() public view {
        uint256 cash = 500e18;
        uint256 borrows = 500e18;
        uint256 reserves = 0;
        uint256 reserveFactor = 0.1e18; // 10%

        uint256 supplyRate = model.getSupplyRate(cash, borrows, reserves, reserveFactor);
        uint256 borrowRate = model.getBorrowRate(cash, borrows, reserves);
        uint256 util = model.utilizationRate(cash, borrows, reserves);

        // SupplyRate = BorrowRate * (1 - reserveFactor) * utilization
        uint256 oneMinusReserve = 1e18 - reserveFactor;
        uint256 expected = borrowRate.wadMul(oneMinusReserve).wadMul(util);

        assertApproxEqRel(supplyRate, expected, 0.0001e18);
    }

    function test_SupplyRate_ZeroUtilization() public view {
        uint256 supplyRate = model.getSupplyRate(1000e18, 0, 0, 0.1e18);
        assertEq(supplyRate, 0);
    }

    function testFuzz_UtilizationRate(uint256 cash, uint256 borrows) public view {
        // Bound inputs to avoid overflow in wadDiv (a * WAD must not overflow)
        // Max safe value: type(uint256).max / 1e18 ≈ 1.15e59
        vm.assume(cash < 1e59);
        vm.assume(borrows < 1e59);
        vm.assume(borrows > 0);

        uint256 util = model.utilizationRate(cash, borrows, 0);

        // Utilization should always be <= 1e18 (100%)
        assertLe(util, 1e18);

        // Utilization should be > 0 when there are borrows (unless rounding to 0 for very small ratios)
        // When borrows is negligible compared to total assets, utilization rounds to 0
        uint256 totalAssets = cash + borrows;
        if (borrows * 1e18 >= totalAssets) {
            // Only assert > 0 when the ratio is meaningful
            assertGt(util, 0);
        }
    }

    function testFuzz_BorrowRateIncreases(uint256 util1, uint256 util2) public view {
        vm.assume(util1 < util2);
        vm.assume(util2 <= 1e18);
        vm.assume(util1 > 0);

        // Create scenarios with different utilization rates
        uint256 cash1 = 1e18 - util1;
        uint256 borrows1 = util1;

        uint256 cash2 = 1e18 - util2;
        uint256 borrows2 = util2;

        uint256 rate1 = model.getBorrowRate(cash1, borrows1, 0);
        uint256 rate2 = model.getBorrowRate(cash2, borrows2, 0);

        // Higher utilization should mean higher borrow rate
        assertGe(rate2, rate1);
    }
}
