// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title WadRayMath
 * @notice Library for fixed-point math with 18 decimals (WAD) and 27 decimals (RAY)
 */
library WadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = 0.5e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = 0.5e27;
    uint256 internal constant WAD_RAY_RATIO = 1e9;

    /**
     * @notice Multiplies two WAD numbers, rounding half up
     * @param a First WAD number
     * @param b Second WAD number
     * @return The product of a and b in WAD
     */
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }
        return (a * b + HALF_WAD) / WAD;
    }

    /**
     * @notice Divides two WAD numbers, rounding half up
     * @param a Numerator (WAD)
     * @param b Denominator (WAD)
     * @return The quotient of a and b in WAD
     */
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "WadRayMath: division by zero");
        uint256 halfB = b / 2;
        return (a * WAD + halfB) / b;
    }

    /**
     * @notice Multiplies two RAY numbers, rounding half up
     * @param a First RAY number
     * @param b Second RAY number
     * @return The product of a and b in RAY
     */
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }
        return (a * b + HALF_RAY) / RAY;
    }

    /**
     * @notice Divides two RAY numbers, rounding half up
     * @param a Numerator (RAY)
     * @param b Denominator (RAY)
     * @return The quotient of a and b in RAY
     */
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "WadRayMath: division by zero");
        uint256 halfB = b / 2;
        return (a * RAY + halfB) / b;
    }

    /**
     * @notice Converts a RAY number to WAD, rounding half up
     * @param a RAY number
     * @return The WAD equivalent
     */
    function rayToWad(uint256 a) internal pure returns (uint256) {
        uint256 halfRatio = WAD_RAY_RATIO / 2;
        return (a + halfRatio) / WAD_RAY_RATIO;
    }

    /**
     * @notice Converts a WAD number to RAY
     * @param a WAD number
     * @return The RAY equivalent
     */
    function wadToRay(uint256 a) internal pure returns (uint256) {
        return a * WAD_RAY_RATIO;
    }

    /**
     * @notice Calculates the power of a base with an exponent using Taylor series
     * @dev Used for compound interest calculations
     * @param x Base (RAY)
     * @param n Exponent
     * @return z Result in RAY
     */
    function rayPow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        z = n % 2 != 0 ? x : RAY;

        for (n /= 2; n != 0; n /= 2) {
            x = rayMul(x, x);

            if (n % 2 != 0) {
                z = rayMul(z, x);
            }
        }
    }
}
