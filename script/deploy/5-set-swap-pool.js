const {ethers} = require("hardhat");

async function main() {
  const Strategy = await ethers.getContractFactory("ReaperStrategyStabilityPool");

  const strategyAddress = "TODO";
  const strategy = Strategy.attach(strategyAddress);

  const usdcAddress = "0x7F5c764cBc14f9669B88837ca1490cCa17c31607";
  const wantAddress = "";

  const balancerUsdcToWantPoolId = "0x39965c9dab5448482cf7e002f583c812ceb53046000100000000000000000003"; // Happy road
  await strategy.setSwapPoolIds(usdcAddress, wantAddress, balancerUsdcToWantPoolId);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
