import { task } from "hardhat/config";

task("send-usdc", "Send USDC to a recipient")
  .addParam("recipient", "Recipient address")
  .addParam("amount", "Amount of USDC to send")
  .setAction(async (taskArgs, hre) => {
    const { recipient, amount } = taskArgs;

    const usdc = await hre.ethers.getContractAt(
      "USDC",
      "0x4095B6aC5abbDEFFb690447dF6F487E8a2B387DF"
    );

    const trx = await usdc.transfer(recipient, hre.ethers.parseEther(amount));

    await trx.wait();

    console.log("USDC sent to", recipient, "amount", amount);
  });
