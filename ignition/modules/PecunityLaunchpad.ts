import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const PecunityLaunchpadModule = buildModule("PecunityLaunchpadModule", (m) => {
  const usdcContract = m.getParameter("paymentToken");

  const minPrice = m.getParameter("minPrice");
  const maxPrice = m.getParameter("maxPrice");
  const scaleFactor = m.getParameter("scaleFactor");
  const immediateReleasePercent = m.getParameter("immediateReleasePercent");
  const vestingDuration = m.getParameter("vestingDuration");

  const launchpad = m.contract("TokenLaunchpad", [
    m.getParameter("saleToken"),
    usdcContract,
    minPrice,
    maxPrice,
    scaleFactor,
    immediateReleasePercent,
    vestingDuration,
  ]);

  return { launchpad };
});

export default PecunityLaunchpadModule;
