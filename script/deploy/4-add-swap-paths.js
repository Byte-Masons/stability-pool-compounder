const {ethers} = require("hardhat");

async function main() {

  const usdcAddress = "0x7F5c764cBc14f9669B88837ca1490cCa17c31607";
  // const wethAddress = "0x4200000000000000000000000000000000000006";
  // const wbtcAddress = "0x68f180fcCe6836688e9084f035309E29Bf0A2095";
  const opAddress = "0x4200000000000000000000000000000000000042";
  // const wantAddress = "0xc5b001DC33727F8F26880B184090D3E252470D45";

  const uniV3Router = "0xE592427A0AEce92De3Edee1F18E0157C05861564";
  const swapperAddress = "0x1FFa0AF1Fa5bdfca491a21BD4Eab55304c623ab8";
  const swapper = await ethers.getContractAt("ISwapper", swapperAddress);

  const path = [opAddress, usdcAddress];
  const fees = [3000];
  const swapData = {
    path,
    fees,
  };

  await swapper.updateUniV3SwapPath(opAddress, usdcAddress, uniV3Router, swapData);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
