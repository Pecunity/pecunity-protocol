// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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
contract TieredTokenLocker is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Tier enumeration
    enum Tier {
        None,
        Basic,
        Bronze,
        Silver,
        Gold,
        Diamond
    }

    // Lock information for each user
    struct LockInfo {
        uint256 amount; // Total locked amount
        uint256 lastDepositTime; // Timestamp of last deposit
        Tier currentTier; // Current tier level
        bool exists; // Whether lock exists
    }

    // Constants
    uint256 public constant LOCK_PERIOD = 120 days;

    // Tier thresholds (in token decimals, assuming 18 decimals)
    uint256 public constant BASIC_THRESHOLD = 500 * 10 ** 18;
    uint256 public constant BRONZE_THRESHOLD = 2500 * 10 ** 18;
    uint256 public constant SILVER_THRESHOLD = 5000 * 10 ** 18;
    uint256 public constant GOLD_THRESHOLD = 30000 * 10 ** 18;
    uint256 public constant DIAMOND_THRESHOLD = 125000 * 10 ** 18;

    // State variables
    IERC20 public immutable lockedToken;
    mapping(address => LockInfo) public locks;

    // Events
    event TokensLocked(
        address indexed user,
        uint256 amount,
        Tier newTier,
        uint256 unlockTime
    );
    event TokensAdded(
        address indexed user,
        uint256 amount,
        Tier oldTier,
        Tier newTier,
        uint256 newUnlockTime
    );
    event TokensUnlocked(address indexed user, uint256 amount);
    event TierUpgraded(address indexed user, Tier oldTier, Tier newTier);

    /**
     * @dev Constructor
     * @param _tokenAddress Address of the ERC20 token to be locked
     */
    constructor(address _tokenAddress) {
        require(_tokenAddress != address(0), "Invalid token address");
        lockedToken = IERC20(_tokenAddress);
    }

    /**
     * @dev Lock tokens for the first time or add more tokens
     * @param amount Amount of tokens to lock
     */
    function lockTokens(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");

        LockInfo storage userLock = locks[msg.sender];

        if (userLock.exists) {
            // Adding to existing lock
            _addTokens(amount);
        } else {
            // Creating new lock
            _createLock(amount);
        }
    }

    /**
     * @dev Create a new lock for the user
     * @param amount Amount of tokens to lock
     */
    function _createLock(uint256 amount) internal {
        require(
            amount >= BASIC_THRESHOLD,
            "Minimum 500 tokens required for Basic tier"
        );

        // Transfer tokens from user to contract
        lockedToken.safeTransferFrom(msg.sender, address(this), amount);

        Tier tier = _calculateTier(amount);
        uint256 unlockTime = block.timestamp + LOCK_PERIOD;

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

        uint256 newUnlockTime = block.timestamp + LOCK_PERIOD;

        emit TokensAdded(msg.sender, amount, oldTier, newTier, newUnlockTime);

        if (newTier > oldTier) {
            emit TierUpgraded(msg.sender, oldTier, newTier);
        }
    }

    /**
     * @dev Unlock and withdraw all locked tokens after lock period
     */
    function unlockTokens() external nonReentrant {
        LockInfo storage userLock = locks[msg.sender];

        require(userLock.exists, "No locked tokens");
        require(
            block.timestamp >= userLock.lastDepositTime + LOCK_PERIOD,
            "Lock period not expired"
        );

        uint256 amount = userLock.amount;

        // Delete lock information
        delete locks[msg.sender];

        // Transfer tokens back to user
        lockedToken.safeTransfer(msg.sender, amount);

        emit TokensUnlocked(msg.sender, amount);
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

        unlockTime = userLock.lastDepositTime + LOCK_PERIOD;
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

        uint256 unlockTime = userLock.lastDepositTime + LOCK_PERIOD;

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
