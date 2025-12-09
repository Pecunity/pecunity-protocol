import { task } from "hardhat/config";

task("deploy-usdc").setAction(async (taskArgs, hre) => {
  const usdc = await hre.ethers.deployContract("USDC");
  await usdc.waitForDeployment();
  console.log("USDC deployed to:", await usdc.getAddress());
});
