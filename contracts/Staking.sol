// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IStaking, IERC20Burnable} from "./interfaces/IStaking.sol";

/**
 * ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
 * ┃                                                                       ┃
 * ┃                            🧱  3 B L O C K S  🧱                      ┃
 * ┃                                                                       ┃
 * ┃                      P E C U N I T Y   T O K E N                      ┃
 * ┃                                                                       ┃
 * ┃       Staking Contract with Fixed Max Supply & Burn Mechanism         ┃
 * ┃                                                                       ┃
 * ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
 *
 * @title Staking
 * @notice Staking contract with fixed maximum supply and burn mechanism for unstaked rewards
 * @dev
 * Contract Design:
 * - Fixed total shares: 2353e18 (always constant)
 * - Staked shares: held by individual users
 * - Unstaked shares: held by address(0), representing unallocated shares
 * - Rewards: distributed to ALL shares (staked + unstaked)
 * - Burn mechanism: owner can burn accumulated rewards on unstaked shares
 *
 * Key Features:
 * 1. Reward distribution is pro-rata across all 2353 shares, regardless of staking amount
 * 2. Unstaked shares earn rewards through address(0)
 * 3. Owner can burn address(0) rewards to reduce inflation
 * 4. Dynamic reward rate calculation during active periods
 *
 * Reward Calculation:
 * - Rewards per second = rewardRate
 * - Each user receives: (userShares / MAX_STAKING_SUPPLY) * rewardRate tokens/sec
 * - address(0) receives: (unstakedShares / MAX_STAKING_SUPPLY) * rewardRate tokens/sec
 *
 * Example:
 * - Total shares: 2353
 * - User A stakes: 1000 shares → address(0): 1353 shares
 * - Reward rate: 100 tokens/sec
 * - User A earns: (1000/2353) * 100 = 42.5 tokens/sec
 * - address(0) earns: (1353/2353) * 100 = 57.5 tokens/sec
 */
contract Staking is Ownable, IStaking {
    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃       Constants           ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @notice Maximum total shares in the system (fixed: 2353e18)
    /// @dev This is immutable and represents the total share pool
    /// Staked shares + unstaked shares (at address(0)) always equals this value
    uint256 public constant MAX_STAKING_SUPPLY = 2353 * 1e18;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃       Immutable State     ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @notice Reward token contract interface (supports burn)
    IERC20Burnable public immutable rewardToken;

    /// @notice Staking token contract interface
    IERC20 public immutable stakingToken;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃      Mutable State         ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @notice Total amount of shares currently staked by users
    /// @dev address(0) holds: MAX_STAKING_SUPPLY - totalStakingSupply shares
    /// @dev Invariant: totalStakingSupply + _stakingBalances[address(0)] == MAX_STAKING_SUPPLY
    uint256 public totalStakingSupply;

    /// @notice Mapping of user address to their staked shares
    /// @dev address(0) is special: represents unstaked shares
    /// @dev Invariant: sum of all _stakingBalances == MAX_STAKING_SUPPLY
    mapping(address account => uint256 balance) private _stakingBalances;

    /// @notice Duration of each reward period in seconds
    /// @dev Must be set by owner before rewards can be distributed
    uint256 public duration;

    /// @notice Timestamp when the current reward period ends
    /// @dev If block.timestamp >= finishAt, rewards are no longer accruing
    uint256 public finishAt;

    /// @notice Timestamp of last reward update
    /// @dev Used to calculate time elapsed for reward accrual
    uint256 public updatedAt;

    /// @notice Reward tokens to distribute per second
    /// @dev Calculated as: total_reward_amount / duration
    uint256 public rewardRate;

    /// @notice Accumulated reward per share, multiplied by 1e18 for precision
    /// @dev Updated every time rewards are recalculated
    /// @dev Used to prevent rounding errors in reward distribution
    uint256 public rewardPerTokenStored;

    /// @notice User's last recorded rewardPerTokenStored value
    /// @dev Used to calculate only new rewards earned since last update
    /// @dev Invariant: only updated when user's balance or rewards change
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice Pending rewards for a user, not yet claimed
    /// @dev Updated by updateReward modifier
    /// @dev Includes both stored pending rewards and newly accrued rewards
    mapping(address => uint256) public rewards;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Modifiers         ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Updates reward state for an account
     * @dev
     * Execution order (Checks-Effects-Interactions pattern):
     * 1. Recalculate global rewardPerTokenStored
     * 2. Update global updatedAt timestamp
     * 3. Calculate earned rewards for account
     * 4. Update account's userRewardPerTokenPaid
     *
     * This modifier is applied to all functions that change reward state
     *
     * @param account Address to update rewards for (can be any address, including address(0))
     */
    modifier updateReward(address account) {
        /// @dev Recalculate accumulated reward per token since last update
        rewardPerTokenStored = rewardPerToken();

        /// @dev Update timestamp to current time (or finishAt if rewards ended)
        updatedAt = lastTimeRewardApplicable();

        /// @dev Calculate earned rewards including pending + newly accrued
        rewards[account] = earned(account);

        /// @dev Record the rewardPerToken value used for this calculation
        userRewardPerTokenPaid[account] = rewardPerTokenStored;

        _;
    }

    /**
     * @notice Validates that amount is greater than zero
     * @dev Prevents operations with zero amounts
     * @param amount Amount to validate
     */
    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) {
            revert NonZeroAmount();
        }
        _;
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃       Constructor         ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Initialize the staking contract
     * @dev
     * Sets up:
     * - Reward and staking token references
     * - Contract owner (caller)
     * - address(0) with all MAX_STAKING_SUPPLY shares initially
     *
     * @param _rewardToken Address of the ERC20Burnable reward token
     * @param _stakingToken Address of the ERC20 staking token
     *
     * Requirements:
     * - Both tokens must be valid ERC20 contracts
     * - _rewardToken must support burn functionality (IERC20Burnable)
     */
    constructor(
        address _rewardToken,
        address _stakingToken
    ) Ownable(msg.sender) {
        rewardToken = IERC20Burnable(_rewardToken);
        stakingToken = IERC20(_stakingToken);

        /// @dev Initialize address(0) with all maximum shares
        /// These represent unstaked/unallocated shares
        _stakingBalances[address(0)] = MAX_STAKING_SUPPLY;
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Public Functions      ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Stake shares to start earning rewards
     * @dev
     * Workflow:
     * 1. Validate amount > 0
     * 2. Calculate and update rewards for sender
     * 3. Check sufficient unstaked shares available
     * 4. Transfer staking tokens from user to contract
     * 5. Move shares from address(0) to user
     * 6. Update global staking supply counter
     * 7. Emit Stake event
     *
     * @param amount Number of shares to stake (must be > 0)
     *
     * Requirements:
     * - amount > 0 (checked by nonZeroAmount modifier)
     * - amount <= unstaked shares (MAX_STAKING_SUPPLY - totalStakingSupply)
     * - User must have approved staking tokens for this contract
     * - Contract must have received the staking tokens
     *
     * Effects:
     * - _stakingBalances[msg.sender] += amount
     * - _stakingBalances[address(0)] -= amount
     * - totalStakingSupply += amount
     * - User's rewards are calculated and updated
     *
     * Emits: Stake event with user, amount, updated balance, and total supply
     */
    function stake(
        uint256 amount
    ) external nonZeroAmount(amount) updateReward(msg.sender) {
        /// @dev Get current unstaked shares
        uint256 _unstakedShares = _stakingBalances[address(0)];

        /// @dev Ensure sufficient unstaked shares are available
        if (_unstakedShares < amount) {
            revert InsufficientUnstakedShares();
        }

        /// @dev Transfer staking tokens from user to contract
        stakingToken.transferFrom(msg.sender, address(this), amount);

        /// @dev Move shares from unstaked (address(0)) to user
        _stakingBalances[address(0)] -= amount;

        /// @dev Add to user's staked balance
        _stakingBalances[msg.sender] += amount;

        /// @dev Update global staking supply
        totalStakingSupply += amount;

        emit Stake(
            msg.sender,
            amount,
            _stakingBalances[msg.sender],
            totalStakingSupply
        );
    }

    /**
     * @notice Withdraw previously staked shares
     * @dev
     * Workflow:
     * 1. Validate amount > 0
     * 2. Calculate and update rewards for sender
     * 3. Check user has sufficient staked balance
     * 4. Move shares from user back to address(0)
     * 5. Update global staking supply counter
     * 6. Emit Withdraw event
     * 7. Transfer staking tokens back to user
     *
     * @param amount Number of shares to withdraw (must be > 0)
     *
     * Requirements:
     * - amount > 0 (checked by nonZeroAmount modifier)
     * - amount <= user's staked balance
     *
     * Effects:
     * - _stakingBalances[msg.sender] -= amount
     * - _stakingBalances[address(0)] += amount
     * - totalStakingSupply -= amount
     * - User's rewards are calculated and updated
     * - Staking tokens are transferred to user
     *
     * Emits: Withdraw event with user, amount, updated balance, and total supply
     */
    function withdraw(
        uint256 amount
    ) external nonZeroAmount(amount) updateReward(msg.sender) {
        /// @dev Get user's current staked balance
        uint256 balance = _stakingBalances[msg.sender];

        /// @dev Ensure user has sufficient staked shares
        if (balance < amount) {
            revert WithdrawAmountExceedsStakingBalance();
        }

        /// @dev Move shares from user back to unstaked pool (address(0))
        _stakingBalances[address(0)] += amount;

        /// @dev Reduce user's balance
        balance -= amount;

        /// @dev Update global staking supply
        totalStakingSupply -= amount;

        /// @dev Update user's staking balance in storage
        _stakingBalances[msg.sender] = balance;

        emit Withdraw(msg.sender, amount, balance, totalStakingSupply);

        /// @dev Transfer staking tokens back to user
        stakingToken.transfer(msg.sender, amount);
    }

    /**
     * @notice Claim all accumulated reward tokens
     * @dev
     * Workflow:
     * 1. Calculate and update rewards for sender
     * 2. Get pending rewards amount
     * 3. If rewards > 0:
     *    - Set rewards to zero (prevent double-claiming)
     *    - Transfer reward tokens to user
     *    - Emit RewardClaimed event
     *
     * Shares earned are NOT affected by claiming rewards.
     * User continues to earn rewards even after claiming.
     *
     * Requirements:
     * - User must have pending rewards (rewards > 0)
     *
     * Effects:
     * - rewards[msg.sender] = 0
     * - Reward tokens transferred to user
     *
     * Emits: RewardClaimed event with user and reward amount
     */
    function claimReward() external updateReward(msg.sender) {
        /// @dev Get pending rewards for user
        uint256 reward = rewards[msg.sender];

        /// @dev Only transfer if rewards exist
        if (reward > 0) {
            /// @dev Clear pending rewards to prevent reentrancy/double-claim
            rewards[msg.sender] = 0;

            /// @dev Transfer reward tokens to user
            rewardToken.transfer(msg.sender, reward);

            emit RewardClaimed(msg.sender, reward);
        }
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Owner Functions        ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Update the staking duration for the next reward period
     * @dev
     * Sets the duration parameter for future reward distributions.
     * Does NOT start rewards; must call updateStaking() to begin distribution.
     *
     * Workflow:
     * 1. Verify current reward period has ended
     * 2. Set new duration value
     * 3. Emit StakingDurationUpdated event
     *
     * @param _duration New reward period duration in seconds
     *        Example: 30 days = 2,592,000 seconds
     *
     * Requirements:
     * - Only owner can call
     * - Current reward period must have finished (block.timestamp >= finishAt)
     *
     * Effects:
     * - duration = _duration
     *
     * Emits: StakingDurationUpdated event with new duration
     *
     * Note: Function name has typo "uppdateDuration" (kept for backwards compatibility)
     */
    function uppdateDuration(uint256 _duration) external onlyOwner {
        /// @dev Prevent changing duration during active reward period
        if (block.timestamp < finishAt) {
            revert CurrentDurationNotFinished();
        }

        /// @dev Set new duration
        duration = _duration;

        emit StakingDurationUpdated(_duration);
    }

    /**
     * @notice Set reward amount and start/update reward distribution
     * @dev
     * Core reward distribution function. Can be called multiple times to top-up rewards.
     *
     * Workflow:
     * 1. Validate amount > 0
     * 2. Calculate and update rewards for address(0) (unstaked shares)
     * 3. Check duration is set
     * 4. Calculate new reward rate:
     *    - If no active period: rewardRate = amount / duration
     *    - If active period: rewardRate = (amount + remainingRewards) / duration
     * 5. Validate rewardRate > 0
     * 6. Validate contract has sufficient reward tokens
     * 7. Set finishAt = current time + duration
     * 8. Emit StakingRewardsUpdated event
     *
     * @param amount Total reward tokens to distribute over the duration
     *               Example: 1000e18 tokens over 30 days
     *
     * Requirements:
     * - Only owner can call
     * - amount > 0
     * - duration must be > 0 (must call updateDuration first)
     * - Contract must have: amount + (remainingRewards if active) tokens
     * - Resulting rewardRate must be > 0 (amount must not be too small)
     *
     * Effects:
     * - rewardRate = new calculated rate
     * - finishAt = block.timestamp + duration
     * - updatedAt = block.timestamp
     * - rewards[address(0)] is updated (unstaked rewards included)
     *
     * Emits: StakingRewardsUpdated event with new reward rate
     *
     * Example:
     * - duration = 30 days (2,592,000 seconds)
     * - amount = 2,592,000e18 tokens
     * - rewardRate = 1e18 tokens/second
     * - Each user with 1 share gets: (1/2353) * 1e18 = ~4.25e14 tokens/sec
     */
    function updateStaking(
        uint256 amount
    ) external onlyOwner nonZeroAmount(amount) updateReward(address(0)) {
        /// @dev Duration must be set before rewards can be distributed
        if (duration == 0) {
            revert DurationIsNotSet();
        }

        /// @dev Calculate new reward rate
        if (block.timestamp > finishAt) {
            /// @dev New reward period: simple division
            rewardRate = amount / duration;
        } else {
            /// @dev Ongoing period: combine new amount with remaining rewards
            /// Remaining rewards = (time until finish) * (current rate)
            uint256 remainingRewards = (finishAt - block.timestamp) *
                rewardRate;
            rewardRate = (amount + remainingRewards) / duration;
        }

        /// @dev Reward rate must be non-zero (amount too small?)
        if (rewardRate == 0) {
            revert ZeroRewardRateNotValid();
        }

        /// @dev Verify contract has sufficient reward tokens for full distribution
        /// Total needed: rewardRate * duration
        if (rewardToken.balanceOf(address(this)) < rewardRate * duration) {
            revert StakingAmountExceedsBalance();
        }

        /// @dev Set new finish time and update timestamp
        finishAt = block.timestamp + duration;
        updatedAt = block.timestamp;

        emit StakingRewardsUpdated(rewardRate);
    }

    /**
     * @notice Burn all accumulated rewards for unstaked shares
     * @dev
     * Removes rewards earned on unstaked shares from circulation by burning tokens.
     * This is a deflationary mechanism to offset rewards on non-staked shares.
     *
     * Workflow:
     * 1. Calculate and update rewards for address(0)
     * 2. Get pending burn amount
     * 3. Validate amount > 0
     * 4. Burn tokens using rewardToken.burn()
     * 5. Clear address(0) rewards
     * 6. Emit RewardsBurned event
     *
     * @dev Note: The burn operation actually removes tokens from this contract
     *      This is different from just clearing the rewards[address(0)] mapping
     *
     * Requirements:
     * - Only owner can call
     * - Pending rewards for address(0) must be > 0
     * - Reward token must support burn() function
     *
     * Effects:
     * - Tokens are burned (sent to dead address or permanently removed)
     * - rewards[address(0)] = 0
     * - Total reward token supply decreases
     *
     * Emits: RewardsBurned event with burn amount
     *
     * Example:
     * - address(0) earned 100,000 tokens over 30 days
     * - Owner calls burnUnstakedRewards()
     * - 100,000 tokens are permanently burned
     * - Total reward supply reduced by 100,000
     */
    function burnUnstakedRewards() external onlyOwner updateReward(address(0)) {
        /// @dev Get pending rewards accumulated on unstaked shares
        uint256 burnAmount = rewards[address(0)];

        /// @dev Must have rewards to burn
        if (burnAmount == 0) {
            revert NonZeroAmount();
        }

        /// @dev Permanently remove tokens from circulation
        rewardToken.burn(burnAmount);

        /// @dev Clear pending rewards for address(0)
        rewards[address(0)] = 0;

        emit RewardsBurned(burnAmount);
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Internal Functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Return minimum of two values
     * @dev Used to ensure we don't calculate rewards past the finish time
     *
     * @param x First value
     * @param y Second value
     * @return Minimum value
     */
    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x <= y ? x : y;
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    View/Query Functions   ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Get the latest time when rewards are still accruing
     * @dev
     * Returns minimum of:
     * - finishAt: scheduled end time
     * - block.timestamp: current time
     *
     * If current time >= finishAt, rewards have stopped accruing
     *
     * @return Latest applicable reward timestamp
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return _min(finishAt, block.timestamp);
    }

    /**
     * @notice Calculate the accumulated reward per token/share
     * @dev
     * This is the core reward calculation function.
     * Returns the total reward earned per share since the beginning.
     *
     * Formula:
     * rewardPerTokenStored + (rewardRate * (now - lastUpdate) * 1e18 / MAX_STAKING_SUPPLY)
     *
     * Key points:
     * - Multiplied by 1e18 for precision (avoids rounding errors)
     * - Divided by MAX_STAKING_SUPPLY (constant 2353e18)
     * - Ensures rewards are distributed across ALL shares, not just staked
     * - Includes previously stored value (doesn't recalculate from zero)
     *
     * Edge case:
     * - If MAX_STAKING_SUPPLY == 0 (impossible), returns stored value
     *
     * @return Accumulated reward per token
     *
     * Example calculation:
     * - rewardRate = 100 tokens/second
     * - Time elapsed = 10 seconds
     * - MAX_STAKING_SUPPLY = 2353e18
     * - New rewards per token = (100 * 10 * 1e18) / (2353e18) = 4.26e16
     * - User with 1000 shares earns: (1000 * 4.26e16) / 1e18 = 42.6 tokens
     */
    function rewardPerToken() public view returns (uint256) {
        /// @dev If no shares exist, return stored value (edge case, shouldn't happen)
        if (MAX_STAKING_SUPPLY == 0) {
            return rewardPerTokenStored;
        }

        /// @dev Calculate new rewards accumulated since last update
        return
            rewardPerTokenStored +
            (rewardRate * (lastTimeRewardApplicable() - updatedAt) * 1e18) /
            MAX_STAKING_SUPPLY;
    }

    /**
     * @notice Calculate total earned rewards for an account
     * @dev
     * Works for both regular users AND address(0) for unstaked shares.
     *
     * Formula:
     * (userShares * (currentRewardPerToken - userLastRewardPerToken)) / 1e18 + pendingRewards
     *
     * Breakdown:
     * - First part: rewards earned since last update
     * - Second part: already-pending rewards from previous calculations
     *
     * Key insights:
     * - Can be called for address(0) to see unstaked rewards
     * - Includes both accrued and pending rewards
     * - Pure view function, doesn't modify state
     *
     * @param account User address (or address(0) for unstaked rewards)
     * @return Total earned rewards including pending
     *
     * Example:
     * - User has 1000 shares
     * - rewardPerToken = 4.26e16, userRewardPerTokenPaid = 0
     * - pending rewards = 0
     * - earned = (1000 * 4.26e16) / 1e18 + 0 = 42.6 tokens
     */
    function earned(address account) public view returns (uint256) {
        return
            ((_stakingBalances[account] *
                (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) +
            rewards[account];
    }

    /**
     * @notice Get the current staked balance for a user
     * @dev Does NOT include unstaked shares (those are in address(0))
     *
     * @param account User address
     * @return Staked shares held by the user (0 if never staked)
     */
    function stakingBalance(address account) external view returns (uint256) {
        return _stakingBalances[account];
    }

    /**
     * @notice Get the number of unstaked shares in the system
     * @dev These are the shares held by address(0)
     * Equivalent to: MAX_STAKING_SUPPLY - totalStakingSupply
     *
     * @return Unstaked shares available for staking
     *
     * Example:
     * - MAX_STAKING_SUPPLY = 2353e18
     * - totalStakingSupply = 1000e18
     * - unstakedShares = 1353e18
     */
    function unstakedShares() external view returns (uint256) {
        return _stakingBalances[address(0)];
    }

    /**
     * @notice Get the total shares in the system
     * @dev Always returns MAX_STAKING_SUPPLY (immutable constant)
     *
     * Invariant:
     * sum of all _stakingBalances[users] + _stakingBalances[address(0)] == MAX_STAKING_SUPPLY
     *
     * @return Total shares (2353e18)
     */
    function totalShares() external pure returns (uint256) {
        return MAX_STAKING_SUPPLY;
    }
}
