import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const PecunityStakingModule = buildModule("PecunityStakingModule", (m) => {
  const pecunityToken = m.getParameter("pecunityToken");
  const stakingToken = m.getParameter("stakingPassToken");

  const duration = m.getParameter("duration");

  const pecunityStaking = m.contract("Staking", [pecunityToken, stakingToken]);

  m.call(pecunityStaking, "uppdateDuration", [duration]);

  return { pecunityStaking };
});

export default PecunityStakingModule;
