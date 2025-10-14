import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const PecunityTokenModule = buildModule("PecunityTokenModule", (m) => {
  const MAX_TOKEN_SUPPLY = m.getParameter("MAX_TOKEN_SUPPLY");

  const pecunityToken = m.contract("PecunityToken", [
    m.getParameter("pecunityWallet"),
    MAX_TOKEN_SUPPLY,
  ]);

  return { pecunityToken };
});

export default PecunityTokenModule;
