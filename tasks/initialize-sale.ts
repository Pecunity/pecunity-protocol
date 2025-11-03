import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeployedAddress } from "../utils/get-deployed-address";

task("initialize-sale", "Initialize the sale").setAction(
  async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    //TODO: Fixe times

    const now = Date.now() / 1000;

    const startTime = Math.round(now + 60 * 5); // 5 minutes from now
    const endTime = Math.round(startTime + 60 * 60 * 2); // 2 hours from now

    const totalTokens = hre.ethers.parseUnits("2500000", 18);

    const launchpadAddress = getDeployedAddress(
      "PecunityLaunchpadModule",
      "TokenLaunchpad",
      hre.network.config.chainId!
    );

    const launchpad = await hre.ethers.getContractAt(
      "TokenLaunchpad",
      launchpadAddress
    );

    const pecunityTokenAddress = await launchpad.saleToken();

    const pecunityToken = await hre.ethers.getContractAt(
      "Pecunity",
      pecunityTokenAddress
    );

    console.log("Approve tokens");
    await pecunityToken.approve(launchpadAddress, totalTokens);

    console.log("Initialize sale");
    await launchpad.initializeSale(startTime, endTime, totalTokens);
  }
);
