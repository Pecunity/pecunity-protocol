import hre from "hardhat";
import { ZeroAddress, parseEther } from "ethers";
import {
  loadFixture,
  time,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";

const MAX_TOKEN_SUPPLY = parseEther("25000000");

describe("Locking", () => {
  async function deplouLockingFixture() {
    const [owner, user] = await hre.ethers.getSigners();

    const PecunityToken = await hre.ethers.getContractFactory("Pecunity");
    const Locking = await hre.ethers.getContractFactory("TieredTokenLocker");

    const token = await PecunityToken.deploy(owner, MAX_TOKEN_SUPPLY);
    const tokenAddress = await token.getAddress();

    await token.connect(owner).launch();

    const locking = await Locking.deploy(tokenAddress);
    const lockingAddress = await locking.getAddress();

    return { locking, token, owner, user, tokenAddress, lockingAddress };
  }

  describe("Lock Tokens", async () => {
    it("should update the locking tier, when lock tokens for the first time", async () => {
      const { user, token, owner, lockingAddress, locking } = await loadFixture(
        deplouLockingFixture
      );

      const tokenAmount = parseEther("500");

      //send first some tokens to user
      await token.connect(owner).transfer(user.address, tokenAmount);

      //approve locking contract
      await token.connect(user).approve(lockingAddress, tokenAmount);

      //lock tokens
      expect(await locking.connect(user).lockTokens(tokenAmount)).to.emit(
        locking,
        "TokensLocked"
      );

      const lockingState = await locking.getLockInfo(user.address);

      expect(lockingState.amount).to.be.equal(tokenAmount);
      expect(lockingState.tier).to.be.gt(0);
    });

    it("should update to the next tier when already locked", async () => {
      const { user, owner, token, locking, lockingAddress } = await loadFixture(
        deplouLockingFixture
      );
      const diamonAmount = await locking.DIAMOND_THRESHOLD();

      //First lock the small amount
      const tokenAmount = parseEther("500");

      //send first some tokens to user
      await token.connect(owner).transfer(user.address, diamonAmount);

      //approve locking contract
      await token.connect(user).approve(lockingAddress, tokenAmount);

      await locking.connect(user).lockTokens(tokenAmount);

      //Lock to Diamond

      const addedTokenValue = diamonAmount - tokenAmount;

      await token.connect(user).approve(lockingAddress, addedTokenValue);

      await locking.connect(user).lockTokens(addedTokenValue);

      const lockingState = await locking.getLockInfo(user.address);

      expect(lockingState.amount).to.be.eq(diamonAmount);

      expect(lockingState.tier).to.be.equal(5);
    });
  });

  describe("Unlock Tokens", async () => {
    it("should unlock tokens after lock period ends", async () => {
      const { user, token, owner, lockingAddress, locking } = await loadFixture(
        deplouLockingFixture
      );

      const diamonAmount = await locking.DIAMOND_THRESHOLD();

      //send first some tokens to user
      await token.connect(owner).transfer(user.address, diamonAmount);

      //approve locking contract
      await token.connect(user).approve(lockingAddress, diamonAmount);

      await locking.connect(user).lockTokens(diamonAmount);

      //increase time
      await time.increase((await locking.LOCK_PERIOD()) + BigInt(1));

      expect(await locking.connect(user).unlockTokens()).to.emit(
        locking,
        "TokensUnlocked"
      );

      expect(await locking.hasActiveLock(user)).to.be.false;
    });

    it("should revert when the period not ended", async () => {
      const { user, token, owner, lockingAddress, locking } = await loadFixture(
        deplouLockingFixture
      );

      const diamonAmount = await locking.DIAMOND_THRESHOLD();

      //send first some tokens to user
      await token.connect(owner).transfer(user.address, diamonAmount);

      //approve locking contract
      await token.connect(user).approve(lockingAddress, diamonAmount);

      await locking.connect(user).lockTokens(diamonAmount);

      await time.increase((await locking.LOCK_PERIOD()) - BigInt(10));

      await expect(
        locking.connect(user).unlockTokens()
      ).to.revertedWithCustomError(locking, "LockPeriodNotExpired()");
    });
  });
});
