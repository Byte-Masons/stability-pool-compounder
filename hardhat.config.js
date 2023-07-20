require("@nomicfoundation/hardhat-foundry");
require("dotenv").config();
require("@openzeppelin/hardhat-upgrades");

const PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const FTMSCAN_KEY = process.env.FTMSCAN_API_KEY;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    mainnet: {
      url: "https://rpc.ftm.tools",
      chainId: 250,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    testnet: {
      url: "https://rpcapi-tracing.testnet.fantom.network",
      chainId: 4002,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    op: {
      url: "https://mainnet.optimism.io",
      chainId: 10,
      accounts: [`0x${PRIVATE_KEY}`],
    },
  },
  etherscan: {
    apiKey: FTMSCAN_KEY,
  },
};
