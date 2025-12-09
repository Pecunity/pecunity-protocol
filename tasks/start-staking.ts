import { task } from "hardhat/config";
import { getDeployedAddress } from "../utils/get-deployed-address";

task("start-staking")
  .addParam("amount", "stakingAmount")
  .setAction(async (taskArgs, hre) => {
    const { amount } = taskArgs;

    const stakingAddress = getDeployedAddress(
      "PecunityStakingModule",
      "Staking",
      hre.network.config.chainId!
    );

    const staking = await hre.ethers.getContractAt("Staking", stakingAddress);

    await staking.updateStaking(hre.ethers.parseEther(amount));

    console.log("Staking started");
  });
