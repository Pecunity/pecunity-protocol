// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IStaking {
    // ┏━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Errors         ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━┛

    error NonZeroAmount();
    error WithdrawAmountExceedsStakingBalance();
    error StakingAmountExceedsBalance();
    error StakingAlreadyActive();
    error CurrentDurationNotFinished();
    error DurationIsNotSet();
    error ZeroRewardRateNotValid();

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Events         ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━┛

    event Stake(
        address indexed account,
        uint256 amount,
        uint256 accountStakeAmount,
        uint256 totalStakingSupply
    );

    event Withdraw(
        address indexed account,
        uint256 amount,
        uint256 accountStakeAmount,
        uint256 totalStakingSupply
    );

    event RewardClaimed(address indexed account, uint256 reward);

    event StakingDurationUpdated(uint256 duration);

    event StakingRewardsUpdated(uint256 rewardRate);
}
