import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { ZeroAddress, parseEther } from "ethers";

const MAX_TOKEN_SUPPLY = parseEther("25000000");
const STAKING_AMOUNT = parseEther("2500000");

describe("Staking", () => {
  async function deployStakingFixture() {
    const [pecunityWallet, user] = await hre.ethers.getSigners();

    const PecunityToken = await hre.ethers.getContractFactory("Pecunity");
    const pecunityToken = await PecunityToken.deploy(
      pecunityWallet.address,
      MAX_TOKEN_SUPPLY
    );

    //Launch the token
    await pecunityToken.launch();

    const tokenAddress = await pecunityToken.getAddress();
    const Staking = await hre.ethers.getContractFactory("Staking");
    const staking = await Staking.deploy(tokenAddress);

    return { pecunityToken, pecunityWallet, staking, user };
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
      const { staking, user } = await loadFixture(deployStakingFixture);
    });
  });

  describe("Staking Start", async () => {});
});
