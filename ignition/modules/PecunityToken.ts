import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const PecunityTokenModule = buildModule("PecunityTokenModule", (m) => {
  const MAX_TOKEN_SUPPLY = m.getParameter("MAX_TOKEN_SUPPLY");

  const pecunity = m.contract("Pecunity", [
    m.getParameter("pecunityWallet"),
    MAX_TOKEN_SUPPLY,
  ]);

  return { pecunity };
});

export default PecunityTokenModule;
