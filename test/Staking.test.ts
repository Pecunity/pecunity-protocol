import {
  loadFixture,
  time,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { ZeroAddress, parseEther } from "ethers";

const MAX_TOKEN_SUPPLY = parseEther("25000000");
const REWARD_TOKENS_SUPPLY = parseEther("7500000");

const STAKING_DURATION = 60 * 60 * 24 * 365 * 4; //4 Years

describe("Staking", () => {
  async function deployStakingFixture() {
    const [pecunityWallet, user] = await hre.ethers.getSigners();

    const PecunityToken = await hre.ethers.getContractFactory("Pecunity");
    const pecunityToken = await PecunityToken.deploy(
      pecunityWallet.address,
      MAX_TOKEN_SUPPLY
    );

    const MockToken = await hre.ethers.getContractFactory("ERC20Mock");
    const stakingToken = await MockToken.deploy();
    const stakingTokenAddress = await stakingToken.getAddress();

    //Launch the token
    await pecunityToken.launch();

    const tokenAddress = await pecunityToken.getAddress();
    const Staking = await hre.ethers.getContractFactory("Staking");
    const staking = await Staking.deploy(tokenAddress, stakingTokenAddress);

    const stakingContractAddress = await staking.getAddress();

    return {
      pecunityToken,
      pecunityWallet,
      staking,
      user,
      stakingToken,
      stakingTokenAddress,
      stakingContractAddress,
    };
  }

  describe("Deployment", async () => {
    it("should set the right reward token", async () => {
      const { staking, pecunityToken } = await loadFixture(
        deployStakingFixture
      );

      expect(await staking.rewardToken()).to.equal(
        await pecunityToken.getAddress()
      );
    });

    it("should set the right owner", async () => {
      const { staking, pecunityWallet } = await loadFixture(
        deployStakingFixture
      );

      expect(await staking.owner()).to.equal(pecunityWallet.address);
    });
  });

  describe("Stake", async () => {
    it("should update the staking balance of the account", async () => {
      const {
        staking,
        user,
        pecunityToken,
        stakingToken,
        pecunityWallet,
        stakingContractAddress,
      } = await loadFixture(deployStakingFixture);

      const stakeAmount = parseEther("250");

      await stakingToken
        .connect(pecunityWallet)
        .transfer(user.address, stakeAmount);

      await stakingToken
        .connect(user)
        .approve(stakingContractAddress, stakeAmount);

      expect(await staking.connect(user).stake(stakeAmount))
        .to.emit(staking, "Stake")
        .withArgs(user.address, stakeAmount);

      expect(await staking.stakingBalance(user.address)).to.equal(stakeAmount);
    });
  });

  describe("Update Duration", async () => {
    it("should update the duration, when staking not started", async () => {
      const { staking, pecunityWallet } = await loadFixture(
        deployStakingFixture
      );

      expect(
        await staking.connect(pecunityWallet).uppdateDuration(STAKING_DURATION)
      )
        .to.emit(staking, "StakingDurationUpdated")
        .withArgs(STAKING_DURATION);
    });
  });

  describe("Staking Start", async () => {
    it("should start the staking, when staking not started", async () => {
      const { staking, pecunityWallet, pecunityToken, stakingContractAddress } =
        await loadFixture(deployStakingFixture);

      await pecunityToken
        .connect(pecunityWallet)
        .transfer(stakingContractAddress, REWARD_TOKENS_SUPPLY);

      await staking.connect(pecunityWallet).uppdateDuration(STAKING_DURATION);

      expect(
        await staking
          .connect(pecunityWallet)
          .updateStaking(REWARD_TOKENS_SUPPLY)
      )
        .to.emit(staking, "StakingStarted")
        .withArgs(REWARD_TOKENS_SUPPLY / BigInt(STAKING_DURATION));
    });

    it("should burn the correct value of the unstake shares rewards", async () => {
      const { staking, pecunityWallet, pecunityToken, stakingContractAddress } =
        await loadFixture(deployStakingFixture);

      await pecunityToken
        .connect(pecunityWallet)
        .transfer(stakingContractAddress, REWARD_TOKENS_SUPPLY);

      await staking.connect(pecunityWallet).uppdateDuration(STAKING_DURATION);

      await staking.connect(pecunityWallet).updateStaking(REWARD_TOKENS_SUPPLY);

      const stakingTime = STAKING_DURATION / 2;

      await time.increase(stakingTime);

      await staking.connect(pecunityWallet).burnUnstakedRewards();

      const leftRewards = await pecunityToken.balanceOf(stakingContractAddress);

      expect(leftRewards).lt(REWARD_TOKENS_SUPPLY);
    });
  });

  describe("Claim Rewards", async () => {
    it("should calculate the correct reward to the account", async () => {
      const {
        user,
        staking,
        pecunityToken,
        pecunityWallet,
        stakingContractAddress,
        stakingToken,
      } = await loadFixture(deployStakingFixture);

      //Start the staking rewards and stake the tokens
      const stakingAmount = parseEther("100");
      await stakingToken
        .connect(pecunityWallet)
        .transfer(user.address, stakingAmount);

      await stakingToken
        .connect(user)
        .approve(stakingContractAddress, stakingAmount);
      await staking.connect(user).stake(stakingAmount);

      await pecunityToken
        .connect(pecunityWallet)
        .transfer(stakingContractAddress, REWARD_TOKENS_SUPPLY);

      await staking.connect(pecunityWallet).uppdateDuration(STAKING_DURATION);

      await staking.connect(pecunityWallet).updateStaking(REWARD_TOKENS_SUPPLY);

      //Calulate the reward
      const rewardRate = await staking.rewardRate();

      const stakingTime = 60 * 60 * 24 * 7; // 7 days

      const expectedReward =
        (((rewardRate * BigInt(stakingTime + 1) * BigInt(1e18)) /
          (await staking.totalShares())) *
          stakingAmount) /
        BigInt(1e18);

      await time.increase(stakingTime);

      expect(await staking.connect(user).claimReward())
        .to.emit(staking, "RewardClaimed")
        .withArgs(user.address);

      const rewardTokenBalance = await pecunityToken.balanceOf(user.address);

      expect(rewardTokenBalance).to.be.equals(expectedReward);
    });
  });
});
