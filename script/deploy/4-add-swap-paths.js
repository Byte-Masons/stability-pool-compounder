const {ethers} = require("hardhat");

async function main() {
  const Strategy = await ethers.getContractFactory("ReaperStrategyStabilityPool");

  const strategyAddress = "TODO";
  const strategy = Strategy.attach(strategyAddress);

  const usdcAddress = "0x7F5c764cBc14f9669B88837ca1490cCa17c31607";
  const wantAddress = "";

  const usdcWantPath = [usdcAddress, wantAddress];

  await strategy.updateUniV3SwapPath(usdcAddress, wantAddress, usdcWantPath);
  // await strategy.updateVeloSwapPath(usdcAddress, wantAddress, usdcWantPath);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
