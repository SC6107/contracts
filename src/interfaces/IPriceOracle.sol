// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPriceOracle
 * @notice Interface for price oracle aggregator
 */
interface IPriceOracle {
    /**
     * @notice Gets the price of an asset
     * @param asset The address of the asset
     * @return The price of the asset (scaled by 1e8)
     */
    function getAssetPrice(address asset) external view returns (uint256);

    /**
     * @notice Sets the price feed source for an asset
     * @param asset The address of the asset
     * @param source The address of the Chainlink price feed
     */
    function setAssetSource(address asset, address source) external;

    /**
     * @notice Gets the price feed source for an asset
     * @param asset The address of the asset
     * @return The address of the price feed
     */
    function getAssetSource(address asset) external view returns (address);
}
