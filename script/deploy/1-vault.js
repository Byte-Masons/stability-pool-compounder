const {ethers} = require("hardhat");

async function main() {
  const Vault = await ethers.getContractFactory("ReaperVaultERC4626");

  const wantAddress = "0xc5b001DC33727F8F26880B184090D3E252470D45";
  const wantSymbol = "ERN";
  const tokenName = `${wantSymbol} Multi-Strategy Vault`;
  const tokenSymbol = `rf-${wantSymbol}`;
  const tvlCap = ethers.constants.MaxUint256;
  const treasuryAddress = "0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B";
  const strategists = [
    "0x1E71AEE6081f62053123140aacC7a06021D77348",
    "0x81876677843D00a7D792E1617459aC2E93202576",
    "0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4",
    "0x4C3490dF15edFa178333445ce568EC6D99b5d71c",
  ];
  const multisigRoles = [
    "0x9BC776dBb134Ef9D7014dB1823Cd755Ac5015203", // super admin
    "0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B", // admin
    "0xb0C9D5851deF8A2Aac4A23031CA2610f8C3483F9", // guardian
  ];

  const vault = await Vault.deploy(
    wantAddress,
    tokenName,
    tokenSymbol,
    tvlCap,
    treasuryAddress,
    strategists,
    multisigRoles,
  );

  await vault.deployed();
  console.log("Vault deployed to:", vault.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
