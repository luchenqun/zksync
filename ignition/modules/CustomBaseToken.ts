import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const CustomBaseTokenModule = buildModule("CustomBaseTokenModule", (m) => {
  const tokenName = m.getParameter("name", "ZK Base Token");
  const tokenSymbol = m.getParameter("symbol", "ZKBT");

  const baseToken = m.contract("CustomBaseToken", [tokenName, tokenSymbol]);

  return { baseToken };
});

export default CustomBaseTokenModule;
