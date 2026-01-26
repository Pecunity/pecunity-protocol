import { task } from "hardhat/config";
import { getDeployedAddress } from "../utils/get-deployed-address";

task("send-pec", "Send PEC to a recipient")
  .addParam("recipient", "Recipient address")
  .addParam("amount", "Amount of PECC to send")
  .setAction(async (taskArgs, hre) => {
    const { recipient, amount } = taskArgs;

    const pecAddress = getDeployedAddress(
      "PecunityTokenModule",
      "Pecunity",
      hre.network.config.chainId!
    );

    const token = await hre.ethers.getContractAt("Pecunity", pecAddress);

    const trx = await token.transfer(recipient, hre.ethers.parseEther(amount));

    await trx.wait();

    console.log("PEC sent to", recipient, "amount", amount);
  });
