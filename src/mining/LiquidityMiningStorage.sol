// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LiquidityMiningStorage
 * @notice ERC-7201 namespaced storage for LiquidityMining
 */
library LiquidityMiningStorage {
    /// @custom:storage-location erc7201:defi.protocol.mining.liquidity
    struct Layout {
        /// @notice Contract version for upgrades
        uint256 version;
        /// @notice Address of the staking token (dToken)
        address stakingToken;
        /// @notice Address of the rewards token (governance token)
        address rewardsToken;
        /// @notice Duration of rewards distribution in seconds
        uint256 rewardsDuration;
        /// @notice Timestamp when current reward period finishes
        uint256 periodFinish;
        /// @notice Reward rate per second
        uint256 rewardRate;
        /// @notice Last time rewards were updated
        uint256 lastUpdateTime;
        /// @notice Accumulated reward per token stored
        uint256 rewardPerTokenStored;
        /// @notice Total amount of tokens staked
        uint256 totalSupply;
        /// @notice Mapping of user address to their staked balance
        mapping(address => uint256) balances;
        /// @notice Mapping of user address to their reward per token paid
        mapping(address => uint256) userRewardPerTokenPaid;
        /// @notice Mapping of user address to their pending rewards
        mapping(address => uint256) rewards;
        /// @notice Address of the rewards distributor
        address rewardsDistributor;
    }

    // keccak256(abi.encode(uint256(keccak256("defi.protocol.mining.liquidity")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x6f7e8d9c0b1a2f3e4d5c6b7a8f9e0d1c2b3a4f5e6d7c8b9a0f1e2d3c4b5a6700;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_LOCATION;
        assembly {
            l.slot := slot
        }
    }
}
