// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ITieredTokenLocker} from "./interfaces/ITieredTokenLocker.sol";

/**
 * @title TieredTokenLocker
 * @dev A smart contract for locking ERC20 tokens with tiered benefit levels
 *
 * Tiers:
 * - Basic: 500 tokens
 * - Bronze: 2,500 tokens
 * - Silver: 5,000 tokens
 * - Gold: 30,000 tokens
 * - Diamond: 125,000 tokens
 *
 * Features:
 * - 120-day minimum lock period after last deposit
 * - Lock period resets when upgrading tiers
 * - Non-transferable during lock period
 * - Can add tokens to upgrade tiers
 */
contract TieredTokenLocker is ReentrancyGuard, ITieredTokenLocker {
    using SafeERC20 for IERC20;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃       Constants           ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    uint256 public constant BASIC_THRESHOLD = 500 * 10 ** 18;
    uint256 public constant BRONZE_THRESHOLD = 2500 * 10 ** 18;
    uint256 public constant SILVER_THRESHOLD = 5000 * 10 ** 18;
    uint256 public constant GOLD_THRESHOLD = 30000 * 10 ** 18;
    uint256 public constant DIAMOND_THRESHOLD = 125000 * 10 ** 18;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃     State Variables       ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
    IERC20 public immutable lockedToken;

    uint256 public immutable lockPeriod;

    mapping(address => LockInfo) public locks;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃       Constructor         ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @dev Constructor
     * @param tokenAddress Address of the ERC20 token to be locked
     */
    constructor(address tokenAddress, uint256 _lockPeriod) {
        require(tokenAddress != address(0), "Invalid token address");
        lockedToken = IERC20(tokenAddress);
        lockPeriod = _lockPeriod;
    }

    /**
     * @dev Lock tokens for the first time or add more tokens
     * @param amount Amount of tokens to lock
     */
    function lockTokens(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert NonZeroAmount();
        }

        LockInfo memory userLock = locks[msg.sender];

        if (userLock.exists) {
            // Adding to existing lock
            _addTokens(amount);
        } else {
            // Creating new lock
            _createLock(amount);
        }
    }

    /**
     * @dev Unlock and withdraw all locked tokens after lock period
     */
    function unlockTokens() external nonReentrant {
        LockInfo memory userLock = locks[msg.sender];

        if (!userLock.exists) {
            revert NoExistingLocking();
        }

        if (block.timestamp < userLock.lastDepositTime + lockPeriod) {
            revert LockPeriodNotExpired();
        }

        uint256 amount = userLock.amount;

        // Delete lock information
        delete locks[msg.sender];

        // Transfer tokens back to user
        lockedToken.safeTransfer(msg.sender, amount);

        emit TokensUnlocked(msg.sender, amount);
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Internal Functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @dev Create a new lock for the user
     * @param amount Amount of tokens to lock
     */
    function _createLock(uint256 amount) internal {
        if (amount < BASIC_THRESHOLD) {
            revert MinimumBasicThreshold();
        }

        // Transfer tokens from user to contract
        lockedToken.safeTransferFrom(msg.sender, address(this), amount);

        Tier tier = _calculateTier(amount);
        uint256 unlockTime = block.timestamp + lockPeriod;

        locks[msg.sender] = LockInfo({
            amount: amount,
            lastDepositTime: block.timestamp,
            currentTier: tier,
            exists: true
        });

        emit TokensLocked(msg.sender, amount, tier, unlockTime);
    }

    /**
     * @dev Add tokens to existing lock
     * @param amount Amount of tokens to add
     */
    function _addTokens(uint256 amount) internal {
        LockInfo storage userLock = locks[msg.sender];

        // Transfer tokens from user to contract
        lockedToken.safeTransferFrom(msg.sender, address(this), amount);

        Tier oldTier = userLock.currentTier;
        uint256 newTotal = userLock.amount + amount;
        Tier newTier = _calculateTier(newTotal);

        // Update lock information
        userLock.amount = newTotal;
        userLock.lastDepositTime = block.timestamp; // Reset lock period
        userLock.currentTier = newTier;

        uint256 newUnlockTime = block.timestamp + lockPeriod;

        emit TokensAdded(msg.sender, amount, oldTier, newTier, newUnlockTime);

        if (newTier > oldTier) {
            emit TierUpgraded(msg.sender, oldTier, newTier);
        }
    }

    /**
     * @dev Calculate tier based on amount
     * @param amount Amount of tokens
     * @return Tier level
     */
    function _calculateTier(uint256 amount) internal pure returns (Tier) {
        if (amount >= DIAMOND_THRESHOLD) {
            return Tier.Diamond;
        } else if (amount >= GOLD_THRESHOLD) {
            return Tier.Gold;
        } else if (amount >= SILVER_THRESHOLD) {
            return Tier.Silver;
        } else if (amount >= BRONZE_THRESHOLD) {
            return Tier.Bronze;
        } else if (amount >= BASIC_THRESHOLD) {
            return Tier.Basic;
        } else {
            return Tier.None;
        }
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    View/Query Functions   ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @dev Get lock information for a user
     * @param user Address of the user
     * @return amount Locked amount
     * @return unlockTime Time when tokens can be unlocked
     * @return tier Current tier
     * @return canUnlock Whether tokens can be unlocked now
     */
    function getLockInfo(
        address user
    )
        external
        view
        returns (uint256 amount, uint256 unlockTime, Tier tier, bool canUnlock)
    {
        LockInfo memory userLock = locks[user];

        if (!userLock.exists) {
            return (0, 0, Tier.None, false);
        }

        unlockTime = userLock.lastDepositTime + lockPeriod;
        canUnlock = block.timestamp >= unlockTime;

        return (userLock.amount, unlockTime, userLock.currentTier, canUnlock);
    }

    /**
     * @dev Get remaining lock time for a user
     * @param user Address of the user
     * @return remainingTime Remaining time in seconds (0 if can unlock)
     */
    function getRemainingLockTime(
        address user
    ) external view returns (uint256 remainingTime) {
        LockInfo memory userLock = locks[user];

        if (!userLock.exists) {
            return 0;
        }

        uint256 unlockTime = userLock.lastDepositTime + lockPeriod;

        if (block.timestamp >= unlockTime) {
            return 0;
        }

        return unlockTime - block.timestamp;
    }

    /**
     * @dev Get tier name as string
     * @param tier Tier enum value
     * @return Tier name
     */
    function getTierName(Tier tier) external pure returns (string memory) {
        if (tier == Tier.Diamond) return "Diamond";
        if (tier == Tier.Gold) return "Gold";
        if (tier == Tier.Silver) return "Silver";
        if (tier == Tier.Bronze) return "Bronze";
        if (tier == Tier.Basic) return "Basic";
        return "None";
    }

    /**
     * @dev Check if user has active lock
     * @param user Address of the user
     * @return Whether user has locked tokens
     */
    function hasActiveLock(address user) external view returns (bool) {
        return locks[user].exists;
    }
}
