// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {PriceOracleStorage} from "./PriceOracleStorage.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title AggregatorV3Interface
 * @notice Chainlink price feed interface
 */
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/**
 * @title PriceOracle
 * @notice UUPS upgradeable Chainlink price feed aggregator
 * @dev Uses ERC-7201 namespaced storage
 */
contract PriceOracle is Initializable, UUPSUpgradeable, OwnableUpgradeable, IPriceOracle {
    using PriceOracleStorage for PriceOracleStorage.Layout;

    /// @notice Base currency unit (8 decimals for USD)
    uint256 public constant BASE_CURRENCY_UNIT = 1e8;

    /// @notice Emitted when an asset source is set
    event AssetSourceUpdated(address indexed asset, address indexed source);

    /// @notice Emitted when fallback oracle is set
    event FallbackOracleUpdated(address indexed fallbackOracle);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the price oracle
     * @param owner_ The owner address
     */
    function initialize(address owner_) external initializer {
        if (owner_ == address(0)) revert Errors.ZeroAddress();

        __Ownable_init(owner_);

        PriceOracleStorage.Layout storage $ = PriceOracleStorage.layout();
        $.version = 1;
        $.baseCurrencyUnit = BASE_CURRENCY_UNIT;
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function getAssetPrice(address asset) external view returns (uint256) {
        PriceOracleStorage.Layout storage $ = PriceOracleStorage.layout();
        address source = $.assetSources[asset];

        if (source == address(0)) {
            // Try fallback oracle
            if ($.fallbackOracle != address(0)) {
                return IPriceOracle($.fallbackOracle).getAssetPrice(asset);
            }
            revert Errors.PriceFeedNotFound();
        }

        return _getPriceFromChainlink(source);
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function setAssetSource(address asset, address source) external onlyOwner {
        if (asset == address(0)) revert Errors.ZeroAddress();

        PriceOracleStorage.Layout storage $ = PriceOracleStorage.layout();

        // Add to assets list if new
        if (!$.assetsExist[asset]) {
            $.assetsList.push(asset);
            $.assetsExist[asset] = true;
        }

        $.assetSources[asset] = source;

        emit AssetSourceUpdated(asset, source);
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function getAssetSource(address asset) external view returns (address) {
        return PriceOracleStorage.layout().assetSources[asset];
    }

    /**
     * @notice Sets multiple asset sources at once
     * @param assets Array of asset addresses
     * @param sources Array of price feed addresses
     */
    function setAssetSources(address[] calldata assets, address[] calldata sources) external onlyOwner {
        if (assets.length != sources.length) revert Errors.InvalidAmount();

        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == address(0)) revert Errors.ZeroAddress();

            PriceOracleStorage.Layout storage $ = PriceOracleStorage.layout();

            if (!$.assetsExist[assets[i]]) {
                $.assetsList.push(assets[i]);
                $.assetsExist[assets[i]] = true;
            }

            $.assetSources[assets[i]] = sources[i];

            emit AssetSourceUpdated(assets[i], sources[i]);
        }
    }

    /**
     * @notice Sets the fallback oracle
     * @param fallbackOracle_ The fallback oracle address
     */
    function setFallbackOracle(address fallbackOracle_) external onlyOwner {
        PriceOracleStorage.layout().fallbackOracle = fallbackOracle_;
        emit FallbackOracleUpdated(fallbackOracle_);
    }

    /**
     * @notice Returns the fallback oracle address
     * @return The fallback oracle address
     */
    function getFallbackOracle() external view returns (address) {
        return PriceOracleStorage.layout().fallbackOracle;
    }

    /**
     * @notice Returns the list of supported assets
     * @return Array of asset addresses
     */
    function getAssetsList() external view returns (address[] memory) {
        return PriceOracleStorage.layout().assetsList;
    }

    /**
     * @notice Returns the contract version
     * @return The version number
     */
    function version() external view returns (uint256) {
        return PriceOracleStorage.layout().version;
    }

    /**
     * @notice Gets price from Chainlink feed with validation
     * @param source The Chainlink aggregator address
     * @return The price (8 decimals)
     */
    function _getPriceFromChainlink(address source) internal view returns (uint256) {
        AggregatorV3Interface feed = AggregatorV3Interface(source);

        (, int256 answer,,,) = feed.latestRoundData();

        if (answer <= 0) revert Errors.InvalidPrice();

        // Normalize to 8 decimals
        uint8 feedDecimals = feed.decimals();
        if (feedDecimals == 8) {
            return uint256(answer);
        } else if (feedDecimals < 8) {
            return uint256(answer) * (10 ** (8 - feedDecimals));
        } else {
            return uint256(answer) / (10 ** (feedDecimals - 8));
        }
    }

    /**
     * @notice Authorizes an upgrade
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        if (newImplementation == address(0)) revert Errors.InvalidImplementation();
        PriceOracleStorage.layout().version++;
    }
}
