import hre from "hardhat";
import path from "path";

import PecunityLockingModule from "../ignition/modules/PecunityLocking";

async function main() {
  await hre.ignition.deploy(PecunityLockingModule, {
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
