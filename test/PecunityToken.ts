import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { ZeroAddress, parseEther } from "ethers";

const MAX_TOKEN_SUPPLY = parseEther("25000000");

describe("PecunityToken", () => {
  async function deployPecunityTokenFixture() {
    const [pecunityWallet] = await hre.ethers.getSigners();
    const PecunityToken = await hre.ethers.getContractFactory("PecunityToken");
    const pecunityToken = await PecunityToken.deploy(
      pecunityWallet.address,
      MAX_TOKEN_SUPPLY,
    );

    return { pecunityToken, pecunityWallet };
  }

  describe("Deployment", async () => {
    it("Should set the right name and symbol", async () => {
      const { pecunityToken } = await loadFixture(deployPecunityTokenFixture);
      expect(await pecunityToken.name()).to.equal("Pecunity Token");
      expect(await pecunityToken.symbol()).to.equal("PEC");
    });

    it("should mint the correct token amount to the correct receiver", async () => {
      const { pecunityToken, pecunityWallet } = await loadFixture(
        deployPecunityTokenFixture,
      );

      expect(await pecunityToken.totalSupply()).to.equal(MAX_TOKEN_SUPPLY);
      expect(await pecunityToken.balanceOf(pecunityWallet.address)).to.equal(
        MAX_TOKEN_SUPPLY,
      );
    });
  });

  describe("Token Burn", async () => {
    it("the owner can burn his token", async () => {
      const { pecunityToken, pecunityWallet } = await loadFixture(
        deployPecunityTokenFixture,
      );

      const burnAmount = parseEther("1000");
      await expect(pecunityToken.burn(burnAmount))
        .to.emit(pecunityToken, "Transfer")
        .withArgs(pecunityWallet.address, ZeroAddress, burnAmount);

      expect(await pecunityToken.balanceOf(pecunityWallet.address)).to.equal(
        MAX_TOKEN_SUPPLY - burnAmount,
      );
    });

    it("should burn approved tokens", async () => {
      const { pecunityToken, pecunityWallet } = await loadFixture(
        deployPecunityTokenFixture,
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

      await pecunityToken
        .connect(randomUser)
        .approve(pecunityWallet.address, burnAmount);

      await expect(
        pecunityToken
          .connect(pecunityWallet)
          .burnFrom(randomUser.address, burnAmount),
      )
        .to.emit(pecunityToken, "Transfer")
        .withArgs(randomUser.address, ZeroAddress, burnAmount);

      expect(await pecunityToken.balanceOf(randomUser.address)).to.equal(0);
    });

    it("should not burn  tokens if not approved", async () => {
      const { pecunityToken, pecunityWallet } = await loadFixture(
        deployPecunityTokenFixture,
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
          .burnFrom(randomUser.address, burnAmount),
      ).to.be.revertedWithCustomError(
        pecunityToken,
        "ERC20InsufficientAllowance",
      );
    });
  });
});
