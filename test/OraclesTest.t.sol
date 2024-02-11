// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/ReaperStrategyStabilityPool.sol";
import "vault-v2/ReaperVaultV2.sol";
import {IERC20Upgradeable} from "oz-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ERC1967Proxy} from "oz/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {ReaperSwapper, MinAmountOutData, MinAmountOutKind} from "vault-v2/ReaperSwapper.sol";
import {IVeloRouter} from "vault-v2/interfaces/IVeloRouter.sol";

contract TarotOracleTest is Test {
    uint256 FORK_BLOCK = 115641661;

    ReaperVaultV2 public vault;
    string public vaultName = "ERN Stability Pool Vault";
    string public vaultSymbol = "rf-SP-ERN";
    uint256 public vaultTvlCap = type(uint256).max;
    address public treasuryAddress = 0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B;
    address public strategistAddr = 0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4;
    address public superAdminAddress = 0x9BC776dBb134Ef9D7014dB1823Cd755Ac5015203;
    address public adminAddress = 0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B;
    address public guardianAddress = 0xb0C9D5851deF8A2Aac4A23031CA2610f8C3483F9;
    address public uniV3UsdcErnPool = 0x4CE4a1a593Ea9f2e6B2c05016a00a2D300C9fFd8;
    address public wantHolderAddr = strategistAddr;
    address[] public strategists = [strategistAddr];
    address[] public multisigRoles = [superAdminAddress, adminAddress, guardianAddress];

    address public balVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniV2Router = 0xbeeF000000000000000000000000000000000000;
    address public uniV3TWAP = 0xB210CE856631EeEB767eFa666EC7C1C57738d438;

    address[] keepers = [
        0xe0268Aa6d55FfE1AA7A77587e56784e5b29004A2,
        0x34Df14D42988e4Dc622e37dc318e70429336B6c5,
        0x73C882796Ea481fe0A2B8DE499d95e60ff971663,
        0x36a63324edFc157bE22CF63A6Bf1C3B49a0E72C0,
        0x9a2AdcbFb972e0EC2946A342f46895702930064F,
        0x7B540a4D24C906E5fB3d3EcD0Bb7B1aEd3823897,
        0x8456a746e09A18F9187E5babEe6C60211CA728D1,
        0x55a078AFC2e20C8c20d1aa4420710d827Ee494d4,
        0x5241F63D0C1f2970c45234a0F5b345036117E3C2,
        0xf58d534290Ce9fc4Ea639B8b9eE238Fe83d2efA6,
        0x5318250BD0b44D1740f47a5b6BE4F7fD5042682D,
        0x33D6cB7E91C62Dd6980F16D61e0cfae082CaBFCA,
        0x51263D56ec81B5e823e34d7665A1F505C327b014,
        0x87A5AfC8cdDa71B5054C698366E97DB2F3C2BC2f
    ];

    address public wethAddress = 0x4200000000000000000000000000000000000006;
    address public wbtcAddress = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;
    address public usdcAddress = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address public ernAddress = 0xc5b001DC33727F8F26880B184090D3E252470D45;
    address public usdceAddress = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address public veloRouter = 0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858;
    address public veloFactoryV1 = 0x25CbdDb98b35ab1FF77413456B31EC81A6B6B746;
    address public veloFactoryV2Default = 0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a;
    address public veloUsdcErnPool = 0x605cCE502dEe6BD201b493782e351e645D44abBB;
    address public veloWethErnPool = 0xFFf37730744930Cb61Be34c0014068F4f1eC28cF;
    address public wantAddress = ernAddress;
    //address public veloUsdcErnPoolOLD = 0x5e4A183Fa83C52B1c55b11f2682f6a8421206633;
    address public stabilityPoolAddress = 0x8B147A2d4Fc3598079C64b8BF9Ad2f776786CFed;

    address public priceFeedAddress = 0xC6b3Eea38Cbe0123202650fB49c59ec41a406427;
    address public priceFeedOwnerAddress = 0xf1a717766c1b2Ed3f63b602E6482dD699ce1C79C;

    bytes32 public balErnPoolId = 0x1d95129c18a8c91c464111fdf7d0eb241b37a9850002000000000000000000c1;

    address public ernWhale = 0x223341f84E784f0cFD3e30438DBDF5Aa4384A8b9;
    address public usdcWhale = 0xf491d040110384DBcf7F241fFE2A546513fD873d;

    uint256 public optimismFork;

    ReaperSwapper reaperSwapper;
    ReaperStrategyStabilityPool implementation;
    ReaperStrategyStabilityPool wrappedProxy;

    function setUp() public {
        // Forking
        string memory rpc = vm.envString("RPC");
        optimismFork = vm.createSelectFork(rpc, FORK_BLOCK);
        assertEq(vm.activeFork(), optimismFork);

        /* Reaper deployment and configuration */
        ERC1967Proxy tmpProxy;
        reaperSwapper = new ReaperSwapper();
        tmpProxy = new ERC1967Proxy(address(reaperSwapper), "");
        reaperSwapper = ReaperSwapper(address(tmpProxy));
        reaperSwapper.initialize(strategists, address(this), address(this));
        IVeloRouter.Route[] memory veloPath = new IVeloRouter.Route[](1);
        veloPath[0] = IVeloRouter.Route(ernAddress, usdcAddress, true, veloFactoryV2Default);
        reaperSwapper.updateVeloSwapPath(ernAddress, usdcAddress, address(veloRouter), veloPath);
        veloPath[0] = IVeloRouter.Route(usdcAddress, ernAddress, true, veloFactoryV2Default);
        reaperSwapper.updateVeloSwapPath(usdcAddress, ernAddress, address(veloRouter), veloPath);

        vault = new ReaperVaultV2(
            wantAddress,
            vaultName,
            vaultSymbol,
            vaultTvlCap,
            treasuryAddress,
            strategists,
            multisigRoles
        );

        ReaperStrategyStabilityPool.ExchangeSettings memory exchangeSettings;
        exchangeSettings.veloRouter = veloRouter;
        exchangeSettings.balVault = balVault;
        exchangeSettings.uniV3Router = uniV3Router;
        exchangeSettings.uniV2Router = uniV2Router;

        ReaperStrategyStabilityPool.Pools memory pools;
        pools.stabilityPool = stabilityPoolAddress;
        pools.uniV3UsdcErnPool = uniV3UsdcErnPool;
        pools.veloUsdcErnPool = veloUsdcErnPool;
        pools.veloWethErnPool = veloWethErnPool;

        ReaperStrategyStabilityPool.Tokens memory tokens;
        tokens.want = wantAddress;
        tokens.usdc = usdcAddress;
        tokens.weth = wethAddress;

        implementation = new ReaperStrategyStabilityPool();
        tmpProxy = new ERC1967Proxy(address(implementation), "");
        wrappedProxy = ReaperStrategyStabilityPool(address(tmpProxy));

        wrappedProxy.initialize(
            address(vault),
            address(reaperSwapper),
            strategists,
            multisigRoles,
            keepers,
            priceFeedAddress,
            uniV3TWAP,
            exchangeSettings,
            pools,
            tokens
        );
    }

    function testMultipleOracles_PositiveOnePrice(uint128 baseAmount, uint32 period) public {
        baseAmount = uint128(bound(baseAmount, 1, 10_000 ether));
        period = uint32(bound(period, 2 days, 9 days));
        uint32 tolerance = 500;
        uint256[] memory prices = new uint256[](1);
        prices[0] = wrappedProxy.getErnAmountForUsdcVeloPoints(baseAmount, period);
        console2.log("Price Velo: ", prices[0]);
        uint256 finalPrice = wrappedProxy.getErnAmountForUsdcAll(prices, tolerance);
        console2.log("2.Price All: ", finalPrice);
        uint256 highBoundary = (baseAmount * 1e12) + ((baseAmount * 1e12) * tolerance) / 10_000;
        uint256 lowBoundary = (baseAmount * 1e12) - ((baseAmount * 1e12) * tolerance) / 10_000;
        assert(finalPrice < highBoundary && finalPrice > lowBoundary);
    }

    function testMultipleOracles_Positive(uint128 baseAmount, uint32 period) public {
        baseAmount = uint128(bound(baseAmount, 1, 10_000 ether));
        period = uint32(bound(period, 2 days, 9 days));
        uint32 tolerance = 500;
        uint256[] memory prices = new uint256[](6);
        prices[0] = wrappedProxy.getErnAmountForUsdcVeloWindow(baseAmount, period);
        prices[1] = wrappedProxy.getErnAmountForUsdcUniV3(baseAmount, period);
        prices[2] = 1059945924123 * baseAmount;
        prices[3] = 959945924123 * baseAmount;
        prices[4] = 1009945924123 * baseAmount;
        prices[5] = 0 * baseAmount;
        console2.log("Price Velo: ", prices[0]);
        console2.log("Price UniV3: ", prices[1]);
        uint256 finalPrice_1 = wrappedProxy.getErnAmountForUsdcAll(prices, tolerance);
        console2.log("2.Price_1 All: ", finalPrice_1);

        uint256 finalPrice_2 = wrappedProxy.getErnAmountForUsdcAll(baseAmount, tolerance);
        console2.log("2.Price_2 All: ", finalPrice_2);
        uint256 highBoundary = (baseAmount * 1e12) + ((baseAmount * 1e12) * tolerance) / 10_000;
        uint256 lowBoundary = (baseAmount * 1e12) - ((baseAmount * 1e12) * tolerance) / 10_000;
        assert(finalPrice_1 < highBoundary && finalPrice_1 > lowBoundary);
        assert(finalPrice_2 < highBoundary && finalPrice_2 > lowBoundary);
    }

    function testMultipleOracles_Negative(uint128 baseAmount, uint32 period) public {
        baseAmount = uint128(bound(baseAmount, 1, 10_000 ether));
        period = uint32(bound(period, 2 days, 9 days));
        uint32 tolerance = 200; // tolerance set to narrow values
        uint256[] memory prices = new uint256[](6);
        prices[0] = wrappedProxy.getErnAmountForUsdcVeloWindow(baseAmount, period);
        prices[1] = wrappedProxy.getErnAmountForUsdcUniV3(baseAmount, period);
        prices[2] = 1059945924123 * baseAmount;
        prices[3] = 959945924123 * baseAmount;
        prices[4] = 1009945924123 * baseAmount;
        prices[5] = 0 * baseAmount;
        console2.log("Price Velo: ", prices[0]);
        console2.log("Price UniV3: ", prices[1]);
        vm.expectRevert(bytes4(keccak256("CouldntDetermineMeanPrice()")));
        wrappedProxy.getErnAmountForUsdcAll(prices, tolerance);
    }

    function testSeparaeteOracles() public {
        console2.log("Velo 1 WETH = %d ERN", wrappedProxy.getErnAmountForWethVelo(1 ether, 2 days));
        console2.log("Chainlink 1 WETH = %d USDC", wrappedProxy.getUsdcAmountForWethUsingPriceFeeds());
        console2.log(wrappedProxy.getErnAmountForUsdcVeloWindow(1 ether, 2 days));
        console2.log(wrappedProxy.getErnAmountForUsdcVeloPoints(1 ether, 2 days));
        console2.log(wrappedProxy.getErnAmountForUsdcUniV3(1 ether, 2 days));
        console2.log(wrappedProxy.getErnAmountForUsdcVeloWeth(1 ether, 2 days));
    }

    function testOraclesOnPriceManipulationsComparison_ErnWhale() public {
        uint256 amount = IERC20(ernAddress).balanceOf(ernWhale);
        MinAmountOutData memory minAmountOutData = MinAmountOutData(MinAmountOutKind.Absolute, 0);

        uint256 result = wrappedProxy.getErnAmountForUsdcVeloPoints(1 ether, 2 days);
        console2.log("1. Result before swap: ", result);
        result = wrappedProxy.getErnAmountForUsdcVeloWindow(1 ether, 2 days);
        console2.log("1. Result1 before swap: ", result);
        vm.startPrank(ernWhale);
        console2.log("1. Whale balance of ERN", IERC20(ernAddress).balanceOf(ernWhale));
        console2.log("1. Whale balance of USDC", IERC20(usdcAddress).balanceOf(ernWhale) * 1e12);
        IERC20Upgradeable(ernAddress).approve(address(reaperSwapper), amount);
        reaperSwapper.swapVelo(ernAddress, usdcAddress, amount, minAmountOutData, address(veloRouter));
        console2.log("2. Whale balance of ERN", IERC20(ernAddress).balanceOf(ernWhale));
        console2.log("2. Whale balance of USDC", IERC20(usdcAddress).balanceOf(ernWhale) * 1e12);
        vm.warp(block.timestamp + 1 days);
        IVeloPair(veloUsdcErnPool).sync(); // imitates vm.warp(block.timestamp + 1 days);
        result = wrappedProxy.getErnAmountForUsdcVeloPoints(1 ether, 2 days);
        console2.log("2. Result (points) after 1 day from swap: ", result);
        result = wrappedProxy.getErnAmountForUsdcVeloWindow(1 ether, 2 days);
        console2.log("2. Result (window) after 1 day from swap: ", result);
        vm.warp(block.timestamp + 1 weeks);
        IVeloPair(veloUsdcErnPool).sync(); //Imitates vm.warp(block.timestamp + 1 weeks);
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        result = wrappedProxy.getErnAmountForUsdcVeloPoints(1 ether, 2 days);
        console2.log("2. Result (points) after 1 week from swap: ", result);
        result = wrappedProxy.getErnAmountForUsdcVeloWindow(1 ether, 2 days);
        console2.log("2. Result (window) after 1 week from swap: ", result);
    }

    function testOraclesOnPriceManipulationsComparison_UsdcWhale() public {
        uint256 amount = IERC20(usdcAddress).balanceOf(usdcWhale);
        MinAmountOutData memory minAmountOutData = MinAmountOutData(MinAmountOutKind.Absolute, 0);

        uint256 result = wrappedProxy.getErnAmountForUsdcVeloPoints(1 ether, 2 days);
        console2.log("1. Result before swap: ", result);
        result = wrappedProxy.getErnAmountForUsdcVeloWindow(1 ether, 2 days);
        console2.log("1. Result1 before swap: ", result);
        vm.startPrank(usdcWhale);
        console2.log("1. Whale balance of ERN", IERC20(ernAddress).balanceOf(usdcWhale));
        console2.log("1. Whale balance of USDC", amount * 1e12);
        IERC20Upgradeable(usdcAddress).approve(address(reaperSwapper), amount);
        reaperSwapper.swapVelo(usdcAddress, ernAddress, amount, minAmountOutData, address(veloRouter));
        console2.log("2. Whale balance of ERN", IERC20(ernAddress).balanceOf(ernWhale));
        console2.log("2. Whale balance of USDC", IERC20(usdcAddress).balanceOf(ernWhale) * 1e12);
        vm.warp(block.timestamp + 1 days);
        IVeloPair(veloUsdcErnPool).sync(); // imitates vm.warp(block.timestamp + 1 days);
        result = wrappedProxy.getErnAmountForUsdcVeloPoints(1 ether, 2 days);
        console2.log("2. Result (points) after 1 day from swap: ", result);
        result = wrappedProxy.getErnAmountForUsdcVeloWindow(1 ether, 2 days);
        console2.log("2. Result (window) after 1 day from swap: ", result);
        vm.warp(block.timestamp + 1 weeks);
        IVeloPair(veloUsdcErnPool).sync(); //Imitates vm.warp(block.timestamp + 1 weeks);
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        result = wrappedProxy.getErnAmountForUsdcVeloPoints(1 ether, 2 days);
        console2.log("2. Result (points) after 1 week from swap: ", result);
        result = wrappedProxy.getErnAmountForUsdcVeloWindow(1 ether, 2 days);
        console2.log("2. Result (window) after 1 week from swap: ", result);
        vm.warp(block.timestamp + 1 weeks);
        IVeloPair(veloUsdcErnPool).sync(); //Imitates vm.warp(block.timestamp + 1 weeks);
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        IVeloPair(veloUsdcErnPool).sync();
        result = wrappedProxy.getErnAmountForUsdcVeloPoints(1 ether, 2 days);
        console2.log("2. Result (points) after 2 weeks from swap: ", result);
        result = wrappedProxy.getErnAmountForUsdcVeloWindow(1 ether, 2 days);
        console2.log("2. Result (window) after 2 weeks from swap: ", result);
    }
}
