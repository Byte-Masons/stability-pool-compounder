const {ethers} = require("hardhat");

async function main() {
  const vaultAddress = "TODO";
  const strategyAddress = "TODO";

  const Vault = await ethers.getContractFactory("ReaperVaultV2");
  const vault = Vault.attach(vaultAddress);

  const feeBPS = 1000;
  const allocation = 9000;
  await vault.addStrategy(strategyAddress, feeBPS, allocation);
  console.log("Strategy added");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
