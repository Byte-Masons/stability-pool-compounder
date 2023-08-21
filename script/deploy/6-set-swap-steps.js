const {ethers} = require("hardhat");

async function main() {
  const Strategy = await ethers.getContractFactory("ReaperStrategyStabilityPool");

  const strategyAddress = "0xFBD08A6869D3e4EC8A21895c1e269f4b980813f0";
  const strategy = Strategy.attach(strategyAddress);

  const usdcAddress = "0x7F5c764cBc14f9669B88837ca1490cCa17c31607";
  const wethAddress = "0x4200000000000000000000000000000000000006";
  const wbtcAddress = "0x68f180fcCe6836688e9084f035309E29Bf0A2095";
  const opAddress = "0x4200000000000000000000000000000000000042";
  const oathAddress = "0x39FdE572a18448F8139b7788099F0a0740f51205";

  const uniV3 = 3;
  const bal = 1;
  const chainlinkBased = 1;
  const absolute = 0;
  const allowedSlippageBPS = 9950;
  const uniV3Router = "0xE592427A0AEce92De3Edee1F18E0157C05861564";
  const balVault = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";

  const step1 = {
    exType: uniV3,
    start: wethAddress,
    end: usdcAddress,
    minAmountOutData: {
      kind: chainlinkBased,
      absoluteOrBPSValue: allowedSlippageBPS,
    },
    exchangeAddress: uniV3Router,
  };

  const step2 = {
    exType: uniV3,
    start: wbtcAddress,
    end: usdcAddress,
    minAmountOutData: {
      kind: chainlinkBased,
      absoluteOrBPSValue: allowedSlippageBPS,
    },
    exchangeAddress: uniV3Router,
  };

  const step3 = {
    exType: uniV3,
    start: opAddress,
    end: usdcAddress,
    minAmountOutData: {
      kind: chainlinkBased,
      absoluteOrBPSValue: allowedSlippageBPS,
    },
    exchangeAddress: uniV3Router,
  };

  const step4 = {
    exType: bal,
    start: oathAddress,
    end: usdcAddress,
    minAmountOutData: {
      kind: absolute,
      absoluteOrBPSValue: 0,
    },
    exchangeAddress: balVault,
  };
  
  const steps = [step1, step2, step3, step4];
  await strategy.setHarvestSwapSteps(steps);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
