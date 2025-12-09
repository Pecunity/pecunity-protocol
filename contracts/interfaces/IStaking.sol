// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IStaking
 * @notice Interface for the Staking contract with Max Supply and Burn Mechanism
 * @dev Defines all public and external functions, events, and errors
 */
interface IStaking {
    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Events           ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Emitted when a user stakes shares
     * @param user Address of the user staking
     * @param amount Number of shares staked
     * @param userBalance Updated balance of the user
     * @param totalStaked Updated total staked supply
     */
    event Stake(
        address indexed user,
        uint256 amount,
        uint256 userBalance,
        uint256 totalStaked
    );

    /**
     * @notice Emitted when a user withdraws staked shares
     * @param user Address of the user withdrawing
     * @param amount Number of shares withdrawn
     * @param userBalance Updated balance of the user after withdrawal
     * @param totalStaked Updated total staked supply
     */
    event Withdraw(
        address indexed user,
        uint256 amount,
        uint256 userBalance,
        uint256 totalStaked
    );

    /**
     * @notice Emitted when a user claims their reward tokens
     * @param user Address of the user claiming rewards
     * @param reward Amount of reward tokens claimed
     */
    event RewardClaimed(address indexed user, uint256 reward);

    /**
     * @notice Emitted when the staking duration is updated
     * @param duration New duration in seconds
     */
    event StakingDurationUpdated(uint256 duration);

    /**
     * @notice Emitted when the staking reward amount is updated
     * @param rewardRate New reward rate per second
     */
    event StakingRewardsUpdated(uint256 rewardRate);

    /**
     * @notice Emitted when unstaked rewards (from address(0)) are burned
     * @param amount Amount of rewards burned
     */
    event RewardsBurned(uint256 amount);

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Errors           ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Thrown when attempting a transaction with zero amount
     */
    error NonZeroAmount();

    /**
     * @notice Thrown when trying to stake more shares than available (unstaked)
     */
    error InsufficientUnstakedShares();

    /**
     * @notice Thrown when trying to withdraw more than user's staked balance
     */
    error WithdrawAmountExceedsStakingBalance();

    /**
     * @notice Thrown when trying to update duration before current duration finishes
     */
    error CurrentDurationNotFinished();

    /**
     * @notice Thrown when duration is not set before updating staking rewards
     */
    error DurationIsNotSet();

    /**
     * @notice Thrown when calculated reward rate is zero
     */
    error ZeroRewardRateNotValid();

    /**
     * @notice Thrown when reward amount exceeds available reward token balance
     */
    error StakingAmountExceedsBalance();

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃   State Variables View    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Get the maximum total shares in the system (constant = 2353e18)
     * @return Maximum staking supply
     */
    function MAX_STAKING_SUPPLY() external view returns (uint256);

    /**
     * @notice Get the reward token contract
     * @return IERC20Burnable interface for the reward token
     */
    function rewardToken() external view returns (IERC20Burnable);

    /**
     * @notice Get the staking token contract
     * @return IERC20 interface for the staking token
     */
    function stakingToken() external view returns (IERC20);

    /**
     * @notice Get the total amount of shares currently staked
     * @return Total staked shares (address(0) holds MAX_STAKING_SUPPLY - totalStakingSupply)
     */
    function totalStakingSupply() external view returns (uint256);

    /**
     * @notice Get the staking reward duration in seconds
     * @return Duration in seconds
     */
    function duration() external view returns (uint256);

    /**
     * @notice Get the timestamp when rewards finish
     * @return Finish timestamp
     */
    function finishAt() external view returns (uint256);

    /**
     * @notice Get the last time rewards were updated
     * @return Updated timestamp
     */
    function updatedAt() external view returns (uint256);

    /**
     * @notice Get the reward rate per second
     * @return Reward rate in tokens per second
     */
    function rewardRate() external view returns (uint256);

    /**
     * @notice Get the accumulated reward per token (per share)
     * @return Reward per token stored
     */
    function rewardPerTokenStored() external view returns (uint256);

    /**
     * @notice Get the user's recorded reward per token paid
     * @param user User address
     * @return Reward per token paid for the user
     */
    function userRewardPerTokenPaid(
        address user
    ) external view returns (uint256);

    /**
     * @notice Get the pending rewards for a user
     * @param user User address
     * @return Pending rewards to claim
     */
    function rewards(address user) external view returns (uint256);

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Core Staking Functions ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Stake shares to earn rewards
     * @dev
     * - Transfers staking tokens from user to contract
     * - Moves shares from address(0) (unstaked) to user (staked)
     * - Updates reward calculations for the user
     * - Emits Stake event
     *
     * @param amount Number of shares to stake (must be > 0 and <= unstaked shares)
     *
     * Requirements:
     * - amount > 0
     * - amount <= unstaked shares available (MAX_STAKING_SUPPLY - totalStakingSupply)
     * - User has approved staking tokens for this contract
     *
     * @dev Calls updateReward modifier to recalculate rewards
     */
    function stake(uint256 amount) external;

    /**
     * @notice Withdraw staked shares
     * @dev
     * - Returns shares to unstaked pool (address(0))
     * - Transfers staking tokens back to user
     * - Updates reward calculations for the user
     * - Emits Withdraw event
     *
     * @param amount Number of shares to withdraw (must be > 0 and <= user's balance)
     *
     * Requirements:
     * - amount > 0
     * - amount <= user's staked balance
     *
     * @dev Calls updateReward modifier to recalculate rewards
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Claim pending reward tokens
     * @dev
     * - Transfers accumulated rewards to user
     * - Sets user's rewards to zero
     * - Updates reward calculations
     * - Emits RewardClaimed event
     *
     * @dev Only claims if rewards > 0
     * @dev Calls updateReward modifier
     */
    function claimReward() external;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Owner Functions        ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Update the staking duration for the next reward period
     * @dev
     * - Can only be called when current duration has finished
     * - Sets a new duration for the next reward cycle
     * - Emits StakingDurationUpdated event
     *
     * @param _duration New duration in seconds
     *
     * Requirements:
     * - Only owner can call
     * - Current reward period must be finished (block.timestamp >= finishAt)
     *
     * NOTE: This only updates the duration parameter, does not start rewards.
     * Call updateStaking() to initialize rewards with the new duration.
     */
    function uppdateDuration(uint256 _duration) external;

    /**
     * @notice Set/update the reward amount and recalculate reward rate
     * @dev
     * - Recalculates reward rate based on amount and duration
     * - If currently in a reward period, adds new amount to remaining rewards
     * - Sets finishAt timestamp to current time + duration
     * - Updates rewards for address(0) (unstaked shares)
     * - Emits StakingRewardsUpdated event
     *
     * @param amount Total reward amount to distribute over the duration
     *
     * Requirements:
     * - Only owner can call
     * - amount > 0
     * - duration must be set (duration != 0)
     * - Contract must have sufficient reward token balance
     * - Resulting rewardRate must be > 0
     *
     * Calculation:
     * - If not in active period: rewardRate = amount / duration
     * - If in active period: rewardRate = (amount + remainingRewards) / duration
     *
     * @dev Calls updateReward(address(0)) to update unstaked rewards
     */
    function updateStaking(uint256 amount) external;

    /**
     * @notice Burn all accumulated rewards for unstaked shares (address(0))
     * @dev
     * - Calculates pending rewards for address(0)
     * - Burns the tokens using the burn() function
     * - Sets address(0) rewards to zero
     * - Emits RewardsBurned event
     *
     * Requirements:
     * - Only owner can call
     * - Pending rewards for address(0) must be > 0
     *
     * Effect:
     * - Rewards accumulated on unstaked shares are permanently removed from circulation
     * - This reduces total reward tokens in the system
     *
     * @dev Calls updateReward(address(0)) before burning
     */
    function burnUnstakedRewards() external;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    View/Query Functions   ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Get the last time when rewards were applicable (applicable until finishAt)
     * @dev Returns minimum of finishAt and current block.timestamp
     * @return Latest applicable reward timestamp
     */
    function lastTimeRewardApplicable() external view returns (uint256);

    /**
     * @notice Calculate the accumulated reward per token (per share)
     * @dev
     * - Calculates based on reward rate and time elapsed
     * - Divides by MAX_STAKING_SUPPLY (constant 2353e18)
     * - Includes stored reward per token from previous periods
     *
     * Formula: rewardPerTokenStored + (rewardRate * (now - lastUpdate) * 1e18 / MAX_STAKING_SUPPLY)
     *
     * @return Reward accumulated per token/share
     */
    function rewardPerToken() external view returns (uint256);

    /**
     * @notice Calculate earned rewards for an account
     * @dev
     * - Works for regular users AND address(0) (unstaked shares)
     * - Includes both accumulated rewards and stored pending rewards
     *
     * Formula: (balance * (currentRewardPerToken - userRewardPerTokenPaid)) / 1e18 + pendingRewards
     *
     * @param account User address or address(0) for unstaked shares
     * @return Total earned rewards for the account
     */
    function earned(address account) external view returns (uint256);

    /**
     * @notice Get the staked balance for a user
     * @dev Does not include unstaked shares (address(0))
     *
     * @param account User address
     * @return Staked shares held by the user
     */
    function stakingBalance(address account) external view returns (uint256);

    /**
     * @notice Get the number of unstaked shares
     * @dev Returns shares held by address(0)
     * @return Unstaked shares (= MAX_STAKING_SUPPLY - totalStakingSupply)
     */
    function unstakedShares() external view returns (uint256);

    /**
     * @notice Get the total shares in the system
     * @dev Always returns MAX_STAKING_SUPPLY (constant)
     * @return Total shares (2353e18)
     */
    function totalShares() external view returns (uint256);
}

/**
 * @title IERC20Burnable
 * @notice Extended ERC20 interface with burn functionality
 */
interface IERC20Burnable is IERC20 {
    /**
     * @notice Burn tokens from the caller's account
     * @param value Amount of tokens to burn
     */
    function burn(uint256 value) external;

    /**
     * @notice Burn tokens from another account (requires approval)
     * @param account Account to burn from
     * @param value Amount of tokens to burn
     */
    function burnFrom(address account, uint256 value) external;
}
