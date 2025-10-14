import hre from "hardhat";
import path from "path";

import PecunityTokenModule from "../ignition/modules/PecunityToken";

async function main() {
  await hre.ignition.deploy(PecunityTokenModule, {
    parameters: path.resolve(
      __dirname,
      `../ignition/parameters/parameters-${hre.network.name}.json`,
    ),
    displayUi: true,
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
