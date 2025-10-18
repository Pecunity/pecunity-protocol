// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IStaking} from "./interfaces/IStaking.sol";

contract Staking is Ownable, IStaking {
    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         State Vars        ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    IERC20 public immutable rewardToken;

    uint256 public totalStakingSupply;
    mapping(address account => uint256 balance) private _stakingBalances;

    // Duration of rewards to be paid out (in seconds)
    uint256 public duration;
    // Timestamp of when the rewards finish
    uint256 public finishAt;
    // Minimum of last updated time and reward finish time
    uint256 public updatedAt;
    // Reward to be paid out per second
    uint256 public rewardRate;
    // Sum of (reward rate * dt * 1e18 / total supply)
    uint256 public rewardPerTokenStored;
    // User address => rewardPerTokenStored
    mapping(address => uint256) public userRewardPerTokenPaid;
    // User address => rewards to be claimed
    mapping(address => uint256) public rewards;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Modifiers         ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        updatedAt = lastTimeRewardApplicable();

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) {
            revert NonZeroAmount();
        }

        _;
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃       Constructor         ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    constructor(address _rewardToken) Ownable(msg.sender) {
        rewardToken = IERC20(_rewardToken);
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Public Functions      ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    function stake(
        uint256 amount
    ) external nonZeroAmount(amount) updateReward(msg.sender) {
        _stakingBalances[msg.sender] += amount;
        totalStakingSupply += amount;

        emit Stake(
            msg.sender,
            amount,
            _stakingBalances[msg.sender],
            totalStakingSupply
        );
    }

    function withdraw(
        uint256 amount
    ) external nonZeroAmount(amount) updateReward(msg.sender) {
        uint256 stakingBalance = _stakingBalances[msg.sender];

        if (stakingBalance < amount) {
            revert WithdrawAmountExceedsStakingBalance();
        }

        stakingBalance -= amount;
        totalStakingSupply -= amount;

        _stakingBalances[msg.sender] = stakingBalance;

        emit Withdraw(msg.sender, amount, stakingBalance, totalStakingSupply);
    }

    function claimReward() external updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.transfer(msg.sender, reward);

            emit RewardClaimed(msg.sender, reward);
        }
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Owner Functions      ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━┛

    function uppdateDuration(uint256 _duration) external onlyOwner {
        if (block.timestamp < finishAt) {
            revert CurrentDurationNotFinished();
        }

        duration = _duration;

        emit StakingDurationUpdated(_duration);
    }

    function updateStaking(
        uint256 amount
    ) external onlyOwner nonZeroAmount(amount) updateReward(address(0)) {
        if (duration == 0) {
            revert DurationIsNotSet();
        }

        if (block.timestamp > finishAt) {
            rewardRate = amount / duration;
        } else {
            uint256 remainingRewards = (finishAt - block.timestamp) *
                rewardRate;
            rewardRate = (amount + remainingRewards) / duration;
        }

        if (rewardRate == 0) {
            revert ZeroRewardRateNotValid();
        }

        if (rewardToken.balanceOf(address(this)) < rewardRate * duration) {
            revert StakingAmountExceedsBalance();
        }

        finishAt = block.timestamp + duration;
        updatedAt = block.timestamp;
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Internal Functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x <= y ? x : y;
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    View Functions      ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━┛

    function lastTimeRewardApplicable() public view returns (uint256) {
        return _min(finishAt, block.timestamp);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStakingSupply == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            (rewardRate * (lastTimeRewardApplicable() - updatedAt) * 1e18) /
            totalStakingSupply;
    }

    function earned(address account) public view returns (uint256) {
        return
            ((_stakingBalances[account] *
                (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) +
            rewards[account];
    }
}
