const {ethers, upgrades} = require("hardhat");

async function main() {
  

  const Strategy = await ethers.getContractFactory("ReaperStrategyStabilityPool");

  const vaultAddress = "0x3eE6107d9C93955acBb3f39871D32B02F82B78AB";

  const swapper = "0x1FFa0AF1Fa5bdfca491a21BD4Eab55304c623ab8";

  const strategists = [
    "0x1E71AEE6081f62053123140aacC7a06021D77348", // bongo
    "0x81876677843D00a7D792E1617459aC2E93202576", // degenicus
    "0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4", // tess
    "0x4C3490dF15edFa178333445ce568EC6D99b5d71c", // eidolon
    "0xb26cd6633db6b0c9ae919049c1437271ae496d15", // zokunei
    "0x60BC5E0440C867eEb4CbcE84bB1123fad2b262B1", // goober
  ];

  const multisigRoles = [
    "0x9BC776dBb134Ef9D7014dB1823Cd755Ac5015203", // super admin
    "0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B", // admin
    "0xb0C9D5851deF8A2Aac4A23031CA2610f8C3483F9", // guardian
  ];

  const keepers = [
    "0x33D6cB7E91C62Dd6980F16D61e0cfae082CaBFCA",
    "0x34Df14D42988e4Dc622e37dc318e70429336B6c5",
    "0x36a63324edFc157bE22CF63A6Bf1C3B49a0E72C0",
    "0x51263D56ec81B5e823e34d7665A1F505C327b014",
    "0x5241F63D0C1f2970c45234a0F5b345036117E3C2",
    "0x5318250BD0b44D1740f47a5b6BE4F7fD5042682D",
    "0x55a078AFC2e20C8c20d1aa4420710d827Ee494d4",
    "0x73C882796Ea481fe0A2B8DE499d95e60ff971663",
    "0x7B540a4D24C906E5fB3d3EcD0Bb7B1aEd3823897",
    "0x8456a746e09A18F9187E5babEe6C60211CA728D1",
    "0x87A5AfC8cdDa71B5054C698366E97DB2F3C2BC2f",
    "0x9a2AdcbFb972e0EC2946A342f46895702930064F",
    "0xd21e0fe4ba0379ec8df6263795c8120414acd0a3",
    "0xe0268Aa6d55FfE1AA7A77587e56784e5b29004A2",
    "0xf58d534290Ce9fc4Ea639B8b9eE238Fe83d2efA6",
    "0xCcb4f4B05739b6C62D9663a5fA7f1E2693048019",
  ];

  const priceFeedAddress = "0xC6b3Eea38Cbe0123202650fB49c59ec41a406427";
  const uniV3TWAP = "0xB210CE856631EeEB767eFa666EC7C1C57738d438";

  const exchangeSettings = {
    balVault: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
    uniV3Router: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
    uniV2Router: "0xbeeF000000000000000000000000000000000000",
    veloRouter: "0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858",
  };

  const stabilityPool = "0x8B147A2d4Fc3598079C64b8BF9Ad2f776786CFed";
  const veloUsdcErnPool = "0x55624DC97289A19045b4739627BEaEB1E70Ab64c";
  const uniV3UsdcErnPool = "0x4CE4a1a593Ea9f2e6B2c05016a00a2D300C9fFd8";
  const pools = {
    stabilityPool,
    veloUsdcErnPool,
    uniV3UsdcErnPool,
  };

  const want = "0xc5b001DC33727F8F26880B184090D3E252470D45";
  const usdc = "0x7F5c764cBc14f9669B88837ca1490cCa17c31607";
  const tokens = {
    want,
    usdc
  };

  const uniV3Twap = 0;
  const currentUsdcErnTWAP = uniV3Twap;

  const strategy = await upgrades.deployProxy(
    Strategy,
    [
      vaultAddress,
      swapper,
      strategists,
      multisigRoles,
      keepers,
      priceFeedAddress,
      uniV3TWAP,
      exchangeSettings,
      pools,
      tokens,
      currentUsdcErnTWAP
    ],
    {kind: "uups", timeout: 0},
  );

  await strategy.deployed();
  console.log("Strategy deployed to:", strategy.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
