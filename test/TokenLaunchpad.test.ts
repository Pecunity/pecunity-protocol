import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { ZeroAddress, parseEther, parseUnits, formatUnits } from "ethers";
import { TokenLaunchpad__factory } from "../typechain-types";
import { time } from "@nomicfoundation/hardhat-toolbox/network-helpers";

const MAX_TOKEN_SUPPLY = parseEther("25000000");

const MIN_PRICE = parseUnits("0.022", 18);
const MAX_PRICE = parseUnits("0.56", 18);

const SCALE_FACTOR = parseEther("1500000");
const IMMEDIATE_RELEASE_PERCENT = 25;
const VESTING_DURATION = 6;

describe("TokenLaunchpad", () => {
  async function deployPecunityLaunchPadFixture() {
    const [pecunityWallet, buyer] = await hre.ethers.getSigners();

    const PecunityToken = await hre.ethers.getContractFactory("Pecunity");
    const pecunityToken = await PecunityToken.deploy(
      pecunityWallet.address,
      MAX_TOKEN_SUPPLY
    );

    const USDC = await hre.ethers.getContractFactory("USDC");
    const usdcToken = await USDC.deploy();

    const PecunityLaunchpad = (await hre.ethers.getContractFactory(
      "TokenLaunchpad"
    )) as TokenLaunchpad__factory;
    const pecunityLaunchpad = await PecunityLaunchpad.deploy(
      pecunityToken.getAddress(),
      usdcToken.getAddress(),
      MIN_PRICE,
      MAX_PRICE,
      SCALE_FACTOR,
      IMMEDIATE_RELEASE_PERCENT,
      VESTING_DURATION
    );

    return {
      pecunityLaunchpad,
      pecunityToken,
      usdcToken,
      pecunityWallet,
      buyer,
    };
  }

  describe("Deployment", async () => {
    it("should be the right vesting paramerter", async () => {
      const { pecunityLaunchpad } = await loadFixture(
        deployPecunityLaunchPadFixture
      );

      expect((await pecunityLaunchpad.getVestingParameter())[0]).to.be.equal(
        BigInt(IMMEDIATE_RELEASE_PERCENT)
      );

      expect((await pecunityLaunchpad.getVestingParameter())[1]).to.be.equal(
        BigInt(VESTING_DURATION)
      );
    });

    it("should have the right sale parameters", async () => {
      const { pecunityLaunchpad } = await loadFixture(
        deployPecunityLaunchPadFixture
      );

      expect(
        (await pecunityLaunchpad.getSaleParameters()).minPrice
      ).to.be.equal(MIN_PRICE);

      expect(
        (await pecunityLaunchpad.getSaleParameters()).maxPrice
      ).to.be.equal(MAX_PRICE);

      expect(
        (await pecunityLaunchpad.getSaleParameters()).scaleFactor
      ).to.be.equal(SCALE_FACTOR);
    });
  });

  describe("initialize sale", async () => {
    it("should start the sale with the correct parameters", async () => {
      const { pecunityLaunchpad, pecunityToken, pecunityWallet } =
        await loadFixture(deployPecunityLaunchPadFixture);

      const maxTokensSold = parseEther("2500000");

      const currentTime = await hre.ethers.provider
        .getBlock("latest")
        .then((block) => block?.timestamp || 0);

      const start = currentTime + 60 * 60;
      const end = start + 5 * 60;

      //approve launchpad for the tokens
      await pecunityToken.approve(
        pecunityLaunchpad.getAddress(),
        maxTokensSold
      );

      //initialize the sale
      await pecunityLaunchpad.initializeSale(start, end, maxTokensSold);

      expect(
        (await pecunityLaunchpad.getSaleParameters()).startTime
      ).to.be.equal(start);

      expect(
        await pecunityToken.balanceOf(pecunityLaunchpad.getAddress())
      ).to.be.equal(maxTokensSold);
    });

    it("Should return active sale after reaching start time", async () => {
      const { pecunityLaunchpad, pecunityToken, pecunityWallet } =
        await loadFixture(deployPecunityLaunchPadFixture);

      const maxTokensSold = parseEther("2500000");

      const currentTime = await hre.ethers.provider
        .getBlock("latest")
        .then((block) => block?.timestamp || 0);

      const start = currentTime + 60 * 60;
      const end = start + 5 * 60;

      //approve launchpad for the tokens
      await pecunityToken.approve(
        pecunityLaunchpad.getAddress(),
        maxTokensSold
      );

      //initialize the sale
      await pecunityLaunchpad.initializeSale(start, end, maxTokensSold);

      await time.increaseTo(start + 1);

      expect(await pecunityLaunchpad.isSaleActive()).to.be.true;
    });
  });

  describe("buy tokens", async () => {
    it("should return the expected tokes", async () => {
      const {
        pecunityLaunchpad,
        pecunityToken,
        usdcToken,
        pecunityWallet,
        buyer,
      } = await loadFixture(deployPecunityLaunchPadFixture);

      const maxTokensSold = parseEther("2500000");

      const currentTime = await hre.ethers.provider
        .getBlock("latest")
        .then((block) => block?.timestamp || 0);

      const start = currentTime + 60 * 60;
      const end = start + 5 * 60;

      //approve launchpad for the tokens
      await pecunityToken.approve(
        pecunityLaunchpad.getAddress(),
        maxTokensSold
      );
      //initialize the sale
      await pecunityLaunchpad.initializeSale(start, end, maxTokensSold);
      await time.increaseTo(start + 1);

      const purchaseTokens = parseEther("1000");

      const purchaseCost = await pecunityLaunchpad.calculatePurchaseCost(
        purchaseTokens
      );

      console.log(formatUnits(purchaseCost.totalCost, 18));

      await usdcToken.transfer(buyer.address, purchaseCost.totalCost);

      //buy the tokens
      await usdcToken
        .connect(buyer)
        .approve(pecunityLaunchpad.getAddress(), purchaseCost.totalCost);
      await pecunityLaunchpad.connect(buyer).buyTokens(purchaseTokens);

      expect(
        (await pecunityLaunchpad.getPurchaseInfo(buyer.address)).totalTokens
      ).to.be.equal(purchaseTokens);
    });
  });

  describe("Withdraw Payment Tokens", async () => {
    it("should be possible to withdraw as owner the tokens after someone bought", async () => {
      const {
        pecunityLaunchpad,
        pecunityToken,
        usdcToken,
        pecunityWallet,
        buyer,
      } = await loadFixture(deployPecunityLaunchPadFixture);

      const maxTokensSold = parseEther("2500000");

      const currentTime = await hre.ethers.provider
        .getBlock("latest")
        .then((block) => block?.timestamp || 0);

      const start = currentTime + 60 * 60;
      const end = start + 5 * 60;

      //approve launchpad for the tokens
      await pecunityToken.approve(
        pecunityLaunchpad.getAddress(),
        maxTokensSold
      );
      //initialize the sale
      await pecunityLaunchpad.initializeSale(start, end, maxTokensSold);
      await time.increaseTo(start + 1);

      const purchaseTokens = parseEther("1000");

      const purchaseCost = await pecunityLaunchpad.calculatePurchaseCost(
        purchaseTokens
      );

      await usdcToken.transfer(buyer.address, purchaseCost.totalCost);

      //buy the tokens
      await usdcToken
        .connect(buyer)
        .approve(pecunityLaunchpad.getAddress(), purchaseCost.totalCost);
      await pecunityLaunchpad.connect(buyer).buyTokens(purchaseTokens);

      //withdraw the payment tokens

      const balanceBefore = await usdcToken.balanceOf(pecunityWallet.address);

      await pecunityLaunchpad.connect(pecunityWallet).withdrawPaymentTokens();

      const balanceAfter = await usdcToken.balanceOf(
        pecunityLaunchpad.getAddress()
      );

      expect(
        await usdcToken.balanceOf(pecunityLaunchpad.getAddress())
      ).to.be.equal(0);
      expect(
        await usdcToken.balanceOf(pecunityWallet.address)
      ).to.be.greaterThan(balanceBefore);
    });
  });

  describe("Vesting phase", async () => {
    it("should the initial amount claimable", async () => {
      const {
        pecunityLaunchpad,
        pecunityToken,
        usdcToken,
        pecunityWallet,
        buyer,
      } = await loadFixture(deployPecunityLaunchPadFixture);

      const maxTokensSold = parseEther("2500000");

      const currentTime = await hre.ethers.provider
        .getBlock("latest")
        .then((block) => block?.timestamp || 0);

      const start = currentTime + 60 * 60;
      const end = start + 5 * 60;

      //approve launchpad for the tokens
      await pecunityToken.approve(
        pecunityLaunchpad.getAddress(),
        maxTokensSold
      );
      //initialize the sale
      await pecunityLaunchpad.initializeSale(start, end, maxTokensSold);
      await time.increaseTo(start + 1);

      const purchaseTokens = parseEther("1000");

      const purchaseCost = await pecunityLaunchpad.calculatePurchaseCost(
        purchaseTokens
      );

      await usdcToken.transfer(buyer.address, purchaseCost.totalCost);

      //buy the tokens
      await usdcToken
        .connect(buyer)
        .approve(pecunityLaunchpad.getAddress(), purchaseCost.totalCost);
      await pecunityLaunchpad.connect(buyer).buyTokens(purchaseTokens);

      await time.increaseTo(end + 1);
      await pecunityToken
        .connect(pecunityWallet)
        .enableTransfer(pecunityLaunchpad.getAddress());

      const claimable = await pecunityLaunchpad.getPurchaseInfo(buyer.address);

      console.log(hre.ethers.formatEther(claimable.claimable));

      await pecunityLaunchpad.connect(buyer).claimTokens();

      expect(await pecunityToken.balanceOf(buyer.address)).to.be.equal(
        claimable.claimable
      );
    });

    it("should be all claimable after the vesting duration", async () => {
      const {
        pecunityLaunchpad,
        pecunityToken,
        usdcToken,
        pecunityWallet,
        buyer,
      } = await loadFixture(deployPecunityLaunchPadFixture);

      const maxTokensSold = parseEther("2500000");

      const currentTime = await hre.ethers.provider
        .getBlock("latest")
        .then((block) => block?.timestamp || 0);

      const start = currentTime + 60 * 60;
      const end = start + 5 * 60;

      //approve launchpad for the tokens
      await pecunityToken.approve(
        pecunityLaunchpad.getAddress(),
        maxTokensSold
      );
      //initialize the sale
      await pecunityLaunchpad.initializeSale(start, end, maxTokensSold);
      await time.increaseTo(start + 1);

      const purchaseTokens = parseEther("1000");

      const purchaseCost = await pecunityLaunchpad.calculatePurchaseCost(
        purchaseTokens
      );

      await usdcToken.transfer(buyer.address, purchaseCost.totalCost);

      //buy the tokens
      await usdcToken
        .connect(buyer)
        .approve(pecunityLaunchpad.getAddress(), purchaseCost.totalCost);
      await pecunityLaunchpad.connect(buyer).buyTokens(purchaseTokens);

      await time.increaseTo(end + VESTING_DURATION * 30 * 24 * 60 * 60 + 1);
      await pecunityToken
        .connect(pecunityWallet)
        .enableTransfer(pecunityLaunchpad.getAddress());

      const claimable = await pecunityLaunchpad.getPurchaseInfo(buyer.address);

      expect(claimable.claimable).to.be.equal(purchaseTokens);

      await pecunityLaunchpad.connect(buyer).claimTokens();

      expect(await pecunityToken.balanceOf(buyer.address)).to.be.equal(
        purchaseTokens
      );
    });
  });
});
