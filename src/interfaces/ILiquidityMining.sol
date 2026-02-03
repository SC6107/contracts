// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILiquidityMining
 * @notice Interface for the Synthetix-style liquidity mining contract
 */
interface ILiquidityMining {
    /**
     * @notice Stakes tokens to earn rewards
     * @param amount The amount to stake
     */
    function stake(uint256 amount) external;

    /**
     * @notice Withdraws staked tokens
     * @param amount The amount to withdraw
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Claims accumulated rewards
     */
    function getReward() external;

    /**
     * @notice Withdraws all staked tokens and claims rewards
     */
    function exit() external;

    /**
     * @notice Returns the amount of rewards earned by an account
     * @param account The address to query
     * @return The amount of rewards earned
     */
    function earned(address account) external view returns (uint256);

    /**
     * @notice Returns the staked balance of an account
     * @param account The address to query
     * @return The staked balance
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Returns the total staked supply
     * @return The total staked amount
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Returns the reward rate per second
     * @return The reward rate
     */
    function rewardRate() external view returns (uint256);

    /**
     * @notice Returns the reward per token stored
     * @return The reward per token
     */
    function rewardPerToken() external view returns (uint256);

    /**
     * @notice Returns the timestamp when rewards finish
     * @return The finish timestamp
     */
    function periodFinish() external view returns (uint256);

    /**
     * @notice Returns the rewards duration
     * @return The duration in seconds
     */
    function rewardsDuration() external view returns (uint256);

    /**
     * @notice Returns the staking token address
     * @return The staking token address
     */
    function stakingToken() external view returns (address);

    /**
     * @notice Returns the rewards token address
     * @return The rewards token address
     */
    function rewardsToken() external view returns (address);

    /**
     * @notice Notifies the contract of a new reward amount
     * @param reward The reward amount to distribute
     */
    function notifyRewardAmount(uint256 reward) external;

    /**
     * @notice Sets the rewards duration
     * @param duration The new duration in seconds
     */
    function setRewardsDuration(uint256 duration) external;

    /**
     * @notice Returns the last time rewards were applicable
     * @return The timestamp
     */
    function lastTimeRewardApplicable() external view returns (uint256);
}
