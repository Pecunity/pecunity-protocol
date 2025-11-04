import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeployedAddress } from "../utils/get-deployed-address";

interface InitializeSaleTaskArgs {
  start: number;
  end: number;
  tokens: number;
}

task("initialize-sale", "Initialize the sale")
  .addParam("start", "Start time of the sale")
  .addParam("end", "End time of the sale")
  .addParam("tokens", "Total tokens to be sold")
  .setAction(
    async (
      taskArgs: InitializeSaleTaskArgs,
      hre: HardhatRuntimeEnvironment
    ) => {
      const { start, end, tokens } = taskArgs;

      const startTime = start;
      const endTime = end;

      const totalTokens = hre.ethers.parseUnits(tokens.toString(), 18);

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
      const trx = await pecunityToken.approve(launchpadAddress, totalTokens);

      await trx.wait();

      console.log("Initialize sale");
      await launchpad.initializeSale(startTime, endTime, totalTokens);
    }
  );
