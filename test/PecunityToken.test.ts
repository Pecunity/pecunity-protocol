import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { ZeroAddress, parseEther } from "ethers";

const MAX_TOKEN_SUPPLY = parseEther("25000000");

describe("Pecunity Token", () => {
  async function deployPecunityTokenFixture() {
    const [pecunityWallet] = await hre.ethers.getSigners();
    const PecunityToken = await hre.ethers.getContractFactory("Pecunity");
    const pecunityToken = await PecunityToken.deploy(
      pecunityWallet.address,
      MAX_TOKEN_SUPPLY
    );

    return { pecunityToken, pecunityWallet };
  }

  describe("Deployment", async () => {
    it("Should set the right name and symbol", async () => {
      const { pecunityToken } = await loadFixture(deployPecunityTokenFixture);
      expect(await pecunityToken.name()).to.equal("Pecunity");
      expect(await pecunityToken.symbol()).to.equal("PEC");
    });

    it("should mint the correct token amount to the correct receiver", async () => {
      const { pecunityToken, pecunityWallet } = await loadFixture(
        deployPecunityTokenFixture
      );

      expect(await pecunityToken.totalSupply()).to.equal(MAX_TOKEN_SUPPLY);
      expect(await pecunityToken.balanceOf(pecunityWallet.address)).to.equal(
        MAX_TOKEN_SUPPLY
      );
    });
  });

  describe("Pre Launch Token Transfer", async () => {
    it("should not allow any account to transfer tokens", async () => {
      const { pecunityToken, pecunityWallet } = await loadFixture(
        deployPecunityTokenFixture
      );

      //transfer to a random user
      const randomUser = ethers.Wallet.createRandom().connect(ethers.provider);
      await pecunityWallet.sendTransaction({
        to: randomUser.address,
        value: parseEther("0.01"),
      });

      const transferAmount = parseEther("10");
      await pecunityToken
        .connect(pecunityWallet)
        .transfer(randomUser.address, transferAmount);

      await expect(
        pecunityToken
          .connect(randomUser)
          .transfer(pecunityWallet.address, transferAmount)
      ).to.be.revertedWithCustomError(pecunityToken, "NotTransferRights");
    });

    it("should allow accounts with rights to transfer tokens", async () => {
      const { pecunityToken, pecunityWallet } = await loadFixture(
        deployPecunityTokenFixture
      );

      //transfer to a random user
      const allowedUser = ethers.Wallet.createRandom().connect(ethers.provider);
      await pecunityWallet.sendTransaction({
        to: allowedUser.address,
        value: parseEther("0.01"),
      });

      await expect(pecunityToken.enableTransfer(allowedUser.address))
        .to.emit(pecunityToken, "TransferRightsEnabled")
        .withArgs(allowedUser.address);

      const transferAmount = parseEther("10");
      const receiver = ethers.Wallet.createRandom().address;

      await pecunityToken.transfer(allowedUser.address, transferAmount);

      await expect(
        pecunityToken.connect(allowedUser).transfer(receiver, transferAmount)
      )
        .to.emit(pecunityToken, "Transfer")
        .withArgs(allowedUser.address, receiver, transferAmount);

      expect(await pecunityToken.balanceOf(receiver)).to.equal(transferAmount);
      expect(await pecunityToken.balanceOf(allowedUser.address)).to.equal(0);
    });
  });

  describe("Post Launch Token Transfer", async () => {
    it("should allow each accounts to transfer tokens after launch", async () => {
      const { pecunityToken, pecunityWallet } = await loadFixture(
        deployPecunityTokenFixture
      );

      //launch token before
      await pecunityToken.launch();

      //transfer to a random user
      const randomUser = ethers.Wallet.createRandom().connect(ethers.provider);
      await pecunityWallet.sendTransaction({
        to: randomUser.address,
        value: parseEther("0.01"),
      });

      const transferAmount = parseEther("10");
      await pecunityToken
        .connect(pecunityWallet)
        .transfer(randomUser.address, transferAmount);

      const randomReceiver = ethers.Wallet.createRandom().address;

      await expect(
        pecunityToken
          .connect(randomUser)
          .transfer(randomReceiver, transferAmount)
      )
        .to.emit(pecunityToken, "Transfer")
        .withArgs(randomUser.address, randomReceiver, transferAmount);

      expect(await pecunityToken.balanceOf(randomReceiver)).to.be.equal(
        transferAmount
      );
    });
  });

  describe("Token Burn", async () => {
    it("the owner can burn his token", async () => {
      const { pecunityToken, pecunityWallet } = await loadFixture(
        deployPecunityTokenFixture
      );

      const burnAmount = parseEther("1000");
      await expect(pecunityToken.burn(burnAmount))
        .to.emit(pecunityToken, "Transfer")
        .withArgs(pecunityWallet.address, ZeroAddress, burnAmount);

      expect(await pecunityToken.balanceOf(pecunityWallet.address)).to.equal(
        MAX_TOKEN_SUPPLY - burnAmount
      );
    });

    it("should burn approved tokens", async () => {
      const { pecunityToken, pecunityWallet } = await loadFixture(
        deployPecunityTokenFixture
      );

      //launch token before
      await pecunityToken.launch();

      const burnAmount = parseEther("2000000");
      const randomUser = ethers.Wallet.createRandom().connect(ethers.provider);

      await pecunityWallet.sendTransaction({
        to: randomUser.address,
        value: parseEther("0.01"),
      });

      await pecunityToken
        .connect(pecunityWallet)
        .transfer(randomUser.address, burnAmount);

      await pecunityToken
        .connect(randomUser)
        .approve(pecunityWallet.address, burnAmount);

      await expect(
        pecunityToken
          .connect(pecunityWallet)
          .burnFrom(randomUser.address, burnAmount)
      )
        .to.emit(pecunityToken, "Transfer")
        .withArgs(randomUser.address, ZeroAddress, burnAmount);

      expect(await pecunityToken.balanceOf(randomUser.address)).to.equal(0);
    });

    it("should not burn  tokens if not approved", async () => {
      const { pecunityToken, pecunityWallet } = await loadFixture(
        deployPecunityTokenFixture
      );

      const burnAmount = parseEther("2000000");
      const randomUser = ethers.Wallet.createRandom().connect(ethers.provider);

      await pecunityWallet.sendTransaction({
        to: randomUser.address,
        value: parseEther("0.01"),
      });

      await pecunityToken
        .connect(pecunityWallet)
        .transfer(randomUser.address, burnAmount);

      await expect(
        pecunityToken
          .connect(pecunityWallet)
          .burnFrom(randomUser.address, burnAmount)
      ).to.be.revertedWithCustomError(
        pecunityToken,
        "ERC20InsufficientAllowance"
      );
    });
  });
});
