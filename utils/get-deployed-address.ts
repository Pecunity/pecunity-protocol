import fs from "fs";
import path from "path";

/**
 * Retrieves the deployed address of a contract from Ignition's deployment JSON.
 *
 * @param moduleName The name of the Ignition module (e.g., "OctoChestModule")
 * @param contractName The name of the contract within that module (e.g., "OctoChest")
 * @param chainId The numeric chain ID of the network (e.g., 1, 31337)
 * @param baseDir Optional: path to the deployments folder (default is "ignition/deployments")
 * @returns The deployed contract address as a string
 */
export function getDeployedAddress(
  moduleName: string,
  contractName: string,
  chainId: number,
  baseDir = "ignition/deployments"
): string {
  const filePath = path.join(
    baseDir,
    `chain-${chainId}`,
    "deployed_addresses.json"
  );

  if (!fs.existsSync(filePath)) {
    throw new Error(`Deployment file not found at: ${filePath}`);
  }

  const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));

  const key = `${moduleName}#${contractName}`;

  const address = data[key];
  if (!address) {
    throw new Error(`Contract key "${key}" not found in ${filePath}`);
  }

  return address;
}
