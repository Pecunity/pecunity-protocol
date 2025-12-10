// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ITieredTokenLocker {
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

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Events           ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛

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

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Errors           ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    error NonZeroAmount();
    error NoExistingLocking();
    error LockPeriodNotExpired();
    error MinimumBasicThreshold();
}
