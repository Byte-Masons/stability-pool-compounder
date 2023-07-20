const { ethers, upgrades } = require("hardhat");

async function upgrade(proxyAddress) {
  const StrategyV2 = await ethers.getContractFactory("ReaperStrategyStabilityPool");
  await upgrades.upgradeProxy(proxyAddress, StrategyV2, { kind: "uups" });
}

async function main() {
  await upgrade("0x766Da60CC688E45B5948F05cb947D3B8Df7274f5");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
