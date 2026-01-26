import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const PecunityLockingModule = buildModule("PecunityLockingModule", (m) => {
  const lockingToken = m.getParameter("lockingToken");
  const lockPeriod = m.getParameter("lockPeriod");

  const pecunityLocking = m.contract("TieredTokenLocker", [
    lockingToken,
    lockPeriod,
  ]);

  return { pecunityLocking };
});

export default PecunityLockingModule;
