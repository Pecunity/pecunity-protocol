import hre from "hardhat";
import path from "path";

import PecunityLaunchpadModule from "../ignition/modules/PecunityLaunchpad";

async function main() {
  await hre.ignition.deploy(PecunityLaunchpadModule, {
    parameters: path.resolve(
      __dirname,
      `../ignition/parameters/parameters-${hre.network.name}.json`
    ),
    displayUi: true,
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
