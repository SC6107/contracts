// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ILiquidityMining} from "../interfaces/ILiquidityMining.sol";
import {ReentrancyGuardUpgradeable} from "../libraries/ReentrancyGuardStorage.sol";
import {LiquidityMiningStorage} from "./LiquidityMiningStorage.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title LiquidityMining
 * @notice UUPS upgradeable Synthetix-style staking rewards contract
 * @dev Users stake dTokens and earn governance tokens
 *
 * Reward Distribution Formula:
 * rewardPerToken = rewardPerTokenStored + (
 *     (lastTimeRewardApplicable - lastUpdateTime) * rewardRate * 1e18 / totalSupply
 * )
 *
 * earned = balance * (rewardPerToken - userRewardPerTokenPaid) / 1e18 + rewards
 */
contract LiquidityMining is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ILiquidityMining
{
    using SafeERC20 for IERC20;
    using LiquidityMiningStorage for LiquidityMiningStorage.Layout;

    /// @notice Emitted when tokens are staked
    event Staked(address indexed user, uint256 amount);

    /// @notice Emitted when tokens are withdrawn
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Emitted when rewards are paid
    event RewardPaid(address indexed user, uint256 reward);

    /// @notice Emitted when reward is added
    event RewardAdded(uint256 reward);

    /// @notice Emitted when rewards duration is updated
    event RewardsDurationUpdated(uint256 newDuration);

    /// @notice Emitted when rewards distributor is updated
    event RewardsDistributorUpdated(address indexed newDistributor);

    /// @notice Modifier to update rewards for an account
    modifier updateReward(address account) {
        LiquidityMiningStorage.Layout storage $ = LiquidityMiningStorage.layout();

        $.rewardPerTokenStored = rewardPerToken();
        $.lastUpdateTime = lastTimeRewardApplicable();

        if (account != address(0)) {
            $.rewards[account] = earned(account);
            $.userRewardPerTokenPaid[account] = $.rewardPerTokenStored;
        }
        _;
    }

    /// @notice Modifier to restrict to rewards distributor or owner
    modifier onlyRewardsDistributor() {
        LiquidityMiningStorage.Layout storage $ = LiquidityMiningStorage.layout();
        if (msg.sender != $.rewardsDistributor && msg.sender != owner()) {
            revert Errors.Unauthorized();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the liquidity mining contract
     * @param owner_ The owner address
     * @param stakingToken_ The staking token (dToken) address
     * @param rewardsToken_ The rewards token (governance token) address
     * @param rewardsDuration_ The rewards duration in seconds
     */
    function initialize(
        address owner_,
        address stakingToken_,
        address rewardsToken_,
        uint256 rewardsDuration_
    ) external initializer {
        if (owner_ == address(0)) revert Errors.ZeroAddress();
        if (stakingToken_ == address(0)) revert Errors.StakingTokenNotSet();
        if (rewardsToken_ == address(0)) revert Errors.RewardsTokenNotSet();
        if (rewardsDuration_ == 0) revert Errors.ZeroAmount();

        __Ownable_init(owner_);
        __ReentrancyGuard_init();
        __Pausable_init();

        LiquidityMiningStorage.Layout storage $ = LiquidityMiningStorage.layout();
        $.version = 1;
        $.stakingToken = stakingToken_;
        $.rewardsToken = rewardsToken_;
        $.rewardsDuration = rewardsDuration_;
        $.rewardsDistributor = owner_;
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused updateReward(msg.sender) {
        if (amount == 0) revert Errors.ZeroAmount();

        LiquidityMiningStorage.Layout storage $ = LiquidityMiningStorage.layout();

        $.totalSupply += amount;
        $.balances[msg.sender] += amount;

        IERC20($.stakingToken).safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert Errors.ZeroAmount();

        LiquidityMiningStorage.Layout storage $ = LiquidityMiningStorage.layout();

        if (amount > $.balances[msg.sender]) revert Errors.InvalidAmount();

        $.totalSupply -= amount;
        $.balances[msg.sender] -= amount;

        IERC20($.stakingToken).safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function getReward() public nonReentrant updateReward(msg.sender) {
        LiquidityMiningStorage.Layout storage $ = LiquidityMiningStorage.layout();

        uint256 reward = $.rewards[msg.sender];
        if (reward > 0) {
            $.rewards[msg.sender] = 0;
            IERC20($.rewardsToken).safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function exit() external {
        LiquidityMiningStorage.Layout storage $ = LiquidityMiningStorage.layout();
        withdraw($.balances[msg.sender]);
        getReward();
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function earned(address account) public view returns (uint256) {
        LiquidityMiningStorage.Layout storage $ = LiquidityMiningStorage.layout();

        return ($.balances[account] * (rewardPerToken() - $.userRewardPerTokenPaid[account])) / 1e18
            + $.rewards[account];
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function balanceOf(address account) external view returns (uint256) {
        return LiquidityMiningStorage.layout().balances[account];
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function totalSupply() external view returns (uint256) {
        return LiquidityMiningStorage.layout().totalSupply;
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function rewardRate() external view returns (uint256) {
        return LiquidityMiningStorage.layout().rewardRate;
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function rewardPerToken() public view returns (uint256) {
        LiquidityMiningStorage.Layout storage $ = LiquidityMiningStorage.layout();

        if ($.totalSupply == 0) {
            return $.rewardPerTokenStored;
        }

        return $.rewardPerTokenStored
            + ((lastTimeRewardApplicable() - $.lastUpdateTime) * $.rewardRate * 1e18) / $.totalSupply;
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function periodFinish() external view returns (uint256) {
        return LiquidityMiningStorage.layout().periodFinish;
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function rewardsDuration() external view returns (uint256) {
        return LiquidityMiningStorage.layout().rewardsDuration;
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function stakingToken() external view returns (address) {
        return LiquidityMiningStorage.layout().stakingToken;
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function rewardsToken() external view returns (address) {
        return LiquidityMiningStorage.layout().rewardsToken;
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        LiquidityMiningStorage.Layout storage $ = LiquidityMiningStorage.layout();
        return block.timestamp < $.periodFinish ? block.timestamp : $.periodFinish;
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function notifyRewardAmount(uint256 reward) external onlyRewardsDistributor updateReward(address(0)) {
        LiquidityMiningStorage.Layout storage $ = LiquidityMiningStorage.layout();

        if (block.timestamp >= $.periodFinish) {
            $.rewardRate = reward / $.rewardsDuration;
        } else {
            uint256 remaining = $.periodFinish - block.timestamp;
            uint256 leftover = remaining * $.rewardRate;
            $.rewardRate = (reward + leftover) / $.rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = IERC20($.rewardsToken).balanceOf(address(this));
        if ($.rewardRate > balance / $.rewardsDuration) revert Errors.RewardTooHigh();

        $.lastUpdateTime = block.timestamp;
        $.periodFinish = block.timestamp + $.rewardsDuration;

        emit RewardAdded(reward);
    }

    /**
     * @inheritdoc ILiquidityMining
     */
    function setRewardsDuration(uint256 duration) external onlyOwner {
        LiquidityMiningStorage.Layout storage $ = LiquidityMiningStorage.layout();

        if (block.timestamp <= $.periodFinish) revert Errors.RewardPeriodNotFinished();
        if (duration == 0) revert Errors.ZeroAmount();

        $.rewardsDuration = duration;
        emit RewardsDurationUpdated(duration);
    }

    /**
     * @notice Sets the rewards distributor
     * @param distributor_ The new rewards distributor address
     */
    function setRewardsDistributor(address distributor_) external onlyOwner {
        if (distributor_ == address(0)) revert Errors.ZeroAddress();
        LiquidityMiningStorage.layout().rewardsDistributor = distributor_;
        emit RewardsDistributorUpdated(distributor_);
    }

    /**
     * @notice Returns the rewards distributor address
     * @return The rewards distributor address
     */
    function rewardsDistributor() external view returns (address) {
        return LiquidityMiningStorage.layout().rewardsDistributor;
    }

    /**
     * @notice Returns the contract version
     * @return The version number
     */
    function version() external view returns (uint256) {
        return LiquidityMiningStorage.layout().version;
    }

    /**
     * @notice Pauses the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Recovers accidentally sent tokens (not staking or rewards token)
     * @param tokenAddress The token to recover
     * @param tokenAmount The amount to recover
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        LiquidityMiningStorage.Layout storage $ = LiquidityMiningStorage.layout();

        if (tokenAddress == $.stakingToken) revert Errors.InvalidAmount();
        if (tokenAddress == $.rewardsToken) revert Errors.InvalidAmount();

        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
    }

    /**
     * @notice Authorizes an upgrade
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        if (newImplementation == address(0)) revert Errors.InvalidImplementation();
        LiquidityMiningStorage.layout().version++;
    }
}
