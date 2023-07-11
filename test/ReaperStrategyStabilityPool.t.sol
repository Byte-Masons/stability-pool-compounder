// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/ReaperStrategyStabilityPool.sol";
import "vault-v2/ReaperSwapper.sol";
import "vault-v2/ReaperVaultV2.sol";
import "vault-v2/ReaperBaseStrategyv4.sol";
import "vault-v2/interfaces/ISwapper.sol";
import "vault-v2/interfaces/IVeloRouter.sol";
import "src/mocks/MockAggregator.sol";
import "src/interfaces/ITroveManager.sol";
import "src/interfaces/IStabilityPool.sol";
import "src/interfaces/IVelodromePair.sol";
import "src/interfaces/IAggregatorAdmin.sol";
import {IStaticOracle} from "src/interfaces/IStaticOracle.sol";
import {IERC20Mintable} from "src/interfaces/IERC20Mintable.sol";
import {ERC1967Proxy} from "oz/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Upgradeable} from "oz-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract ReaperStrategyStabilityPoolTest is Test {
    using stdStorage for StdStorage;
    // Fork Identifier

    uint256 public optimismFork;

    // Registry
    address public treasuryAddress = 0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B;
    address public stabilityPoolAddress = 0x8B147A2d4Fc3598079C64b8BF9Ad2f776786CFed;
    address public priceFeedAddress = 0xC6b3Eea38Cbe0123202650fB49c59ec41a406427;
    address public priceFeedOwnerAddress = 0xf1a717766c1b2Ed3f63b602E6482dD699ce1C79C;
    address public troveManager = 0xd584A5E956106DB2fE74d56A0B14a9d64BE8DC93;
    address public veloRouter = 0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858;
    address public veloFactoryV1 = 0x25CbdDb98b35ab1FF77413456B31EC81A6B6B746;
    address public veloFactoryV2Default = 0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a;
    address public balVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniV2Router = 0xbeeF000000000000000000000000000000000000; // Any non-0 address when UniV2 router does not exist
    address public veloUsdcErnPool = 0x5e4A183Fa83C52B1c55b11f2682f6a8421206633;
    address public uniV3UsdcErnPool = 0x4CE4a1a593Ea9f2e6B2c05016a00a2D300C9fFd8;
    address public chainlinkUsdcOracle = 0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;
    address public sequencerUptimeFeed = 0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389;
    address public uniV3TWAP = 0xB210CE856631EeEB767eFa666EC7C1C57738d438;

    address public superAdminAddress = 0x9BC776dBb134Ef9D7014dB1823Cd755Ac5015203;
    address public adminAddress = 0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B;
    address public guardianAddress = 0xb0C9D5851deF8A2Aac4A23031CA2610f8C3483F9;

    address public wantAddress = 0xc5b001DC33727F8F26880B184090D3E252470D45;
    address public wethAddress = 0x4200000000000000000000000000000000000006;
    address public wbtcAddress = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;
    address public usdcAddress = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address public oathAddress = 0x39FdE572a18448F8139b7788099F0a0740f51205;
    address public opAddress = 0x4200000000000000000000000000000000000042;

    address public strategistAddr = 0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4;
    address public wantHolderAddr = strategistAddr;

    address public borrowerOperationsAddress = 0x0a4582d3d9ecBAb80a66DAd8A881BE3b771d3e5B;
    address public oathOwner = 0x80A16016cC4A2E6a2CACA8a4a498b1699fF0f844;
    address public wbtcHolder = 0x85C31FFA3706d1cce9d525a00f1C7D4A2911754c;
    address public opHolder = 0x790b4086D106Eafd913e71843AED987eFE291c92;

    bytes32 public balErnPoolId = 0x1d95129c18a8c91c464111fdf7d0eb241b37a9850002000000000000000000c1;
    bytes32 public oatsAndGrainPoolId = 0x1cc3e990b23a09fc9715aaf7ccf21c212a9cbc160001000000000000000000bd;

    uint256 BPS_UNIT = 10_000;

    AggregatorV3Interface wbtcAggregator;
    AggregatorV3Interface wethAggregator;
    AggregatorV3Interface opAggregator;
    AggregatorV3Interface usdcAggregator;

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

    bytes32 public constant KEEPER = keccak256("KEEPER");

    address[] public strategists = [strategistAddr];
    address[] public multisigRoles = [superAdminAddress, adminAddress, guardianAddress];

    // Initialized during set up in initial tests
    // vault, strategy, want, wftm, owner, wantHolder, strategist, guardian, admin, superAdmin, unassignedRole
    ReaperVaultV2 public vault;
    string public vaultName = "ERN Stability Pool Vault";
    string public vaultSymbol = "rf-SP-ERN";
    uint256 public vaultTvlCap = type(uint256).max;

    ReaperStrategyStabilityPool public implementation;
    ERC1967Proxy public proxy;
    ReaperStrategyStabilityPool public wrappedProxy;

    ISwapper public swapper;

    ERC20 public want = ERC20(wantAddress);
    ERC20 public wftm = ERC20(wethAddress);

    function setUp() public {
        // Forking
        optimismFork = vm.createSelectFork(
            "https://late-fragrant-rain.optimism.quiknode.pro/08eedcb171832b45c4961c9ff1392491e9b4cfaf/", 106483261
        );
        assertEq(vm.activeFork(), optimismFork);

        // // Deploying stuff
        ReaperSwapper swapperImpl = new ReaperSwapper();
        ERC1967Proxy swapperProxy = new ERC1967Proxy(address(swapperImpl), "");
        ReaperSwapper wrappedSwapperProxy = ReaperSwapper(address(swapperProxy));
        wrappedSwapperProxy.initialize(strategists, guardianAddress, superAdminAddress);
        swapper = ISwapper(address(swapperProxy));

        vault =
        new ReaperVaultV2(wantAddress, vaultName, vaultSymbol, vaultTvlCap, treasuryAddress, strategists, multisigRoles);
        implementation = new ReaperStrategyStabilityPool();
        proxy = new ERC1967Proxy(address(implementation), "");
        wrappedProxy = ReaperStrategyStabilityPool(address(proxy));

        ReaperStrategyStabilityPool.ExchangeSettings memory exchangeSettings;
        exchangeSettings.veloRouter = veloRouter;
        exchangeSettings.balVault = balVault;
        exchangeSettings.uniV3Router = uniV3Router;
        exchangeSettings.uniV2Router = uniV2Router;

        ReaperStrategyStabilityPool.Pools memory pools;
        pools.stabilityPool = stabilityPoolAddress;
        pools.veloUsdcErnPool = veloUsdcErnPool;
        pools.uniV3UsdcErnPool = uniV3UsdcErnPool;

        address[] memory usdcErnPath = new address[](2);
        usdcErnPath[0] = usdcAddress;
        usdcErnPath[1] = wantAddress;

        ReaperStrategyStabilityPool.Tokens memory tokens;
        tokens.want = wantAddress;
        tokens.usdc = usdcAddress;

        ReaperStrategyStabilityPool.TWAP currentUsdcErnTWAP = ReaperStrategyStabilityPool.TWAP.UniV3;

        wrappedProxy.initialize(
            address(vault),
            address(swapper),
            strategists,
            multisigRoles,
            keepers,
            priceFeedAddress,
            sequencerUptimeFeed,
            uniV3TWAP,
            exchangeSettings,
            pools,
            tokens,
            currentUsdcErnTWAP
        );

        uint256 feeBPS = 500;
        uint256 allocation = 10_000;
        vault.addStrategy(address(wrappedProxy), feeBPS, allocation);

        vm.prank(wantHolderAddr);
        want.approve(address(vault), type(uint256).max);
        deal({token: address(want), to: wantHolderAddr, give: _toWant(1000)});

        for (uint256 i = 0; i < keepers.length; i++) {
            address keeper = keepers[i];
            wrappedProxy.grantRole(KEEPER, keeper);
            // console.log("adding keeper: ", keeper);
        }

        IVeloRouter.Route[] memory usdcErnRoute = new IVeloRouter.Route[](1);
        usdcErnRoute[0] =
            IVeloRouter.Route({from: usdcAddress, to: wantAddress, stable: true, factory: veloFactoryV2Default});

        uint24[] memory usdcErnFees = new uint24[](1);
        usdcErnFees[0] = 500;
        UniV3SwapData memory usdcErnSwapData = UniV3SwapData({path: usdcErnPath, fees: usdcErnFees});

        vm.startPrank(strategistAddr);
        swapper.updateVeloSwapPath(usdcAddress, wantAddress, veloRouter, usdcErnRoute);
        swapper.updateUniV3SwapPath(usdcAddress, wantAddress, uniV3Router, usdcErnSwapData);
        swapper.updateBalSwapPoolID(usdcAddress, wantAddress, balVault, balErnPoolId);

        IVeloRouter.Route[] memory wethErnRoute = new IVeloRouter.Route[](2);
        wethErnRoute[0] =
            IVeloRouter.Route({from: wethAddress, to: usdcAddress, stable: false, factory: veloFactoryV2Default});
        wethErnRoute[1] =
            IVeloRouter.Route({from: usdcAddress, to: wantAddress, stable: true, factory: veloFactoryV2Default});
        swapper.updateVeloSwapPath(wethAddress, wantAddress, veloRouter, wethErnRoute);

        IVeloRouter.Route[] memory wbtcErnRoute = new IVeloRouter.Route[](2);
        wbtcErnRoute[0] =
            IVeloRouter.Route({from: wbtcAddress, to: usdcAddress, stable: false, factory: veloFactoryV2Default});
        wbtcErnRoute[1] =
            IVeloRouter.Route({from: usdcAddress, to: wantAddress, stable: true, factory: veloFactoryV2Default});
        swapper.updateVeloSwapPath(wbtcAddress, wantAddress, veloRouter, wbtcErnRoute);

        // IVeloRouter.Route[] memory oathErnRoute = new IVeloRouter.Route[](2);
        // oathErnRoute[0] =
        //     IVeloRouter.Route({from: oathAddress, to: usdcAddress, stable: false, factory: veloFactoryV2Default});
        // oathErnRoute[1] =
        //     IVeloRouter.Route({from: usdcAddress, to: wantAddress, stable: true, factory: veloFactoryV2Default});
        // swapper.updateVeloSwapPath(oathAddress, wantAddress, veloRouter, oathErnRoute);

        // IVeloRouter.Route[] memory oathUsdcRoute = new IVeloRouter.Route[](2);
        // oathUsdcRoute[0] =
        //     IVeloRouter.Route({from: oathAddress, to: usdcAddress, stable: false, factory: veloFactoryV2Default});
        // swapper.updateVeloSwapPath(oathAddress, usdcAddress, veloRouter, oathUsdcRoute);

        swapper.updateBalSwapPoolID(oathAddress, usdcAddress, balVault, oatsAndGrainPoolId);

        address[] memory wethUsdcPath = new address[](2);
        wethUsdcPath[0] = wethAddress;
        wethUsdcPath[1] = usdcAddress;
        uint24[] memory wethUsdcFees = new uint24[](1);
        wethUsdcFees[0] = 500;
        UniV3SwapData memory wethUsdcSwapData = UniV3SwapData({path: wethUsdcPath, fees: wethUsdcFees});
        swapper.updateUniV3SwapPath(wethAddress, usdcAddress, uniV3Router, wethUsdcSwapData);

        address[] memory wbtcUsdcPath = new address[](3);
        wbtcUsdcPath[0] = wbtcAddress;
        wbtcUsdcPath[1] = wethAddress;
        wbtcUsdcPath[2] = usdcAddress;
        uint24[] memory wbtcUsdcFees = new uint24[](2);
        wbtcUsdcFees[0] = 500;
        wbtcUsdcFees[1] = 500;
        UniV3SwapData memory wbtcUsdcSwapData = UniV3SwapData({path: wbtcUsdcPath, fees: wbtcUsdcFees});
        swapper.updateUniV3SwapPath(wbtcAddress, usdcAddress, uniV3Router, wbtcUsdcSwapData);

        address[] memory opUsdcPath = new address[](3);
        opUsdcPath[0] = opAddress;
        opUsdcPath[1] = wethAddress;
        opUsdcPath[2] = usdcAddress;
        uint24[] memory opUsdcFees = new uint24[](2);
        opUsdcFees[0] = 3000;
        opUsdcFees[1] = 500;
        UniV3SwapData memory opUsdcSwapData = UniV3SwapData({path: opUsdcPath, fees: opUsdcFees});
        swapper.updateUniV3SwapPath(opAddress, usdcAddress, uniV3Router, opUsdcSwapData);
        vm.stopPrank();

        // Register CL aggregators in Swapper for WETH, WBTC, OP, and USDC
        // We set high timeouts since we do a lot of manual time skipping in tests
        // 2 days should be plenty = 2 * 24 * 60 * 60 = 172800
        // Since our strategy assumes that USDC ~= ERN, we reuse the USDC aggregator for ERN
        vm.startPrank(superAdminAddress);
        swapper.updateTokenAggregator(wethAddress, 0x13e3Ee699D1909E989722E753853AE30b17e08c5, 172800);
        swapper.updateTokenAggregator(wbtcAddress, 0xD702DD976Fb76Fffc2D3963D037dfDae5b04E593, 172800);
        swapper.updateTokenAggregator(opAddress, 0x0D276FC14719f9292D5C1eA2198673d1f4269246, 172800);
        swapper.updateTokenAggregator(usdcAddress, 0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3, 172800);
        vm.stopPrank();

        // set our swap steps
        // step 1: weth -> usdc using univ3 w/ CL aggregators and minAmountOutBPS as 9950
        // step 2: wbtc -> usdc using univ3 w/ CL aggregators and minAmountOutBPS as 9950
        // step 3: op -> usdc using univ3 w/ CL aggregators and minAmountOutBPS as 9950
        // step 4: oath -> usdc using velo w/ 0 for minAmountOut
        ReaperBaseStrategyv4.SwapStep memory step1 = ReaperBaseStrategyv4.SwapStep({
            exType: ReaperBaseStrategyv4.ExchangeType.UniV3,
            start: wethAddress,
            end: usdcAddress,
            minAmountOutData: MinAmountOutData({kind: MinAmountOutKind.ChainlinkBased, absoluteOrBPSValue: 9950}),
            exchangeAddress: uniV3Router
        });
        ReaperBaseStrategyv4.SwapStep memory step2 = ReaperBaseStrategyv4.SwapStep({
            exType: ReaperBaseStrategyv4.ExchangeType.UniV3,
            start: wbtcAddress,
            end: usdcAddress,
            minAmountOutData: MinAmountOutData({kind: MinAmountOutKind.ChainlinkBased, absoluteOrBPSValue: 9950}),
            exchangeAddress: uniV3Router
        });
        ReaperBaseStrategyv4.SwapStep memory step3 = ReaperBaseStrategyv4.SwapStep({
            exType: ReaperBaseStrategyv4.ExchangeType.UniV3,
            start: opAddress,
            end: usdcAddress,
            minAmountOutData: MinAmountOutData({kind: MinAmountOutKind.ChainlinkBased, absoluteOrBPSValue: 9950}),
            exchangeAddress: uniV3Router
        });
        ReaperBaseStrategyv4.SwapStep memory step4 = ReaperBaseStrategyv4.SwapStep({
            exType: ReaperBaseStrategyv4.ExchangeType.Bal,
            start: oathAddress,
            end: usdcAddress,
            minAmountOutData: MinAmountOutData({kind: MinAmountOutKind.Absolute, absoluteOrBPSValue: 0}),
            exchangeAddress: balVault
        });
        ReaperBaseStrategyv4.SwapStep[] memory steps = new ReaperBaseStrategyv4.SwapStep[](4);
        steps[0] = step1;
        steps[1] = step2;
        steps[2] = step3;
        steps[3] = step4;
        wrappedProxy.setHarvestSwapSteps(steps);

        uint256 mintAmount = 1_000_000 ether;
        vm.prank(borrowerOperationsAddress);
        IERC20Mintable(wantAddress).mint(strategistAddr, mintAmount);
        vm.prank(strategistAddr);
        IERC20Mintable(wantAddress).approve(address(wrappedProxy), mintAmount);

        vm.prank(oathOwner);
        IERC20Mintable(oathAddress).mint(strategistAddr, mintAmount);
        vm.prank(strategistAddr);
        IERC20Mintable(oathAddress).approve(address(wrappedProxy), mintAmount);

        uint256 wbtcBalance = IERC20Mintable(wbtcAddress).balanceOf(wbtcHolder);
        console.log("approving: ", wbtcBalance);
        vm.prank(wbtcHolder);
        IERC20Mintable(wbtcAddress).approve(address(wrappedProxy), wbtcBalance);

        uint256 opBalance = IERC20Mintable(opAddress).balanceOf(opHolder);
        console.log("approving: ", opBalance);
        vm.prank(opHolder);
        IERC20Mintable(opAddress).approve(address(wrappedProxy), opBalance);

        wrappedProxy.updateErnMinAmountOutBPS(9950);
        wrappedProxy.setUsdcToErnExchange(ReaperBaseStrategyv4.ExchangeType.VeloSolid);

        wbtcAggregator = AggregatorV3Interface(IPriceFeed(priceFeedAddress).priceAggregator(wbtcAddress));
        wethAggregator = AggregatorV3Interface(IPriceFeed(priceFeedAddress).priceAggregator(wethAddress));
        opAggregator = AggregatorV3Interface(IPriceFeed(priceFeedAddress).priceAggregator(opAddress));
        usdcAggregator = AggregatorV3Interface(chainlinkUsdcOracle);
    }

    ///------ DEPLOYMENT ------\\\\

    function testVaultDeployedWith0Balance() public {
        uint256 totalBalance = vault.balance();
        uint256 pricePerFullShare = vault.getPricePerFullShare();
        assertEq(totalBalance, 0);
        assertEq(pricePerFullShare, 1e18);
    }

    ///------ ACCESS CONTROL ------\\\

    function testUnassignedRoleCannotPassAccessControl() public {
        vm.startPrank(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266); // random address

        vm.expectRevert("Unauthorized access");
        wrappedProxy.setEmergencyExit();
    }

    function testStrategistHasRightPrivileges() public {
        vm.startPrank(strategistAddr);

        vm.expectRevert("Unauthorized access");
        wrappedProxy.setEmergencyExit();
    }

    function testGuardianHasRightPrivilieges() public {
        vm.startPrank(guardianAddress);

        wrappedProxy.setEmergencyExit();
    }

    function testAdminHasRightPrivileges() public {
        vm.startPrank(adminAddress);

        wrappedProxy.setEmergencyExit();
    }

    function testSuperAdminOrOwnerHasRightPrivileges() public {
        vm.startPrank(superAdminAddress);

        wrappedProxy.setEmergencyExit();
    }

    ///------ VAULT AND STRATEGY------\\\

    function testCanTakeDeposits() public {
        vm.startPrank(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 2000) / 10000;
        console.log("want.balanceOf(wantHolderAddr): ", want.balanceOf(wantHolderAddr));
        console.log(depositAmount);
        vault.deposit(depositAmount);

        uint256 newVaultBalance = vault.balance();
        console.log(newVaultBalance);
        assertApproxEqRel(newVaultBalance, depositAmount, 0.005e18);
    }

    function testVaultCanMintUserPoolShare() public {
        address alice = makeAddr("alice");

        vm.startPrank(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 2000) / 10000;
        vault.deposit(depositAmount);
        uint256 aliceDepositAmount = (want.balanceOf(wantHolderAddr) * 5000) / 10000;
        want.transfer(alice, aliceDepositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        want.approve(address(vault), aliceDepositAmount);
        vault.deposit(aliceDepositAmount);
        vm.stopPrank();

        uint256 allowedImprecision = 1e15;

        uint256 userVaultBalance = vault.balanceOf(wantHolderAddr);
        assertApproxEqRel(userVaultBalance, depositAmount, allowedImprecision);
        uint256 aliceVaultBalance = vault.balanceOf(alice);
        assertApproxEqRel(aliceVaultBalance, aliceDepositAmount, allowedImprecision);

        vm.prank(alice);
        vault.withdrawAll();
        uint256 aliceWantBalance = want.balanceOf(alice);
        assertApproxEqRel(aliceWantBalance, aliceDepositAmount, allowedImprecision);
        aliceVaultBalance = vault.balanceOf(alice);
        assertEq(aliceVaultBalance, 0);
    }

    function testVaultAllowsWithdrawals() public {
        uint256 userBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 5000) / 10000;
        vm.startPrank(wantHolderAddr);
        vault.deposit(depositAmount);
        vault.withdrawAll();
        uint256 userBalanceAfterWithdraw = want.balanceOf(wantHolderAddr);

        assertEq(userBalance, userBalanceAfterWithdraw);
    }

    function testVaultAllowsSmallWithdrawal() public {
        address alice = makeAddr("alice");

        vm.startPrank(wantHolderAddr);
        uint256 aliceDepositAmount = (want.balanceOf(wantHolderAddr) * 1000) / 10000;
        want.transfer(alice, aliceDepositAmount);
        uint256 userBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 100) / 10000;
        vault.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        want.approve(address(vault), type(uint256).max);
        vault.deposit(aliceDepositAmount);
        vm.stopPrank();

        vm.prank(wantHolderAddr);
        vault.withdrawAll();
        uint256 userBalanceAfterWithdraw = want.balanceOf(wantHolderAddr);

        assertEq(userBalance, userBalanceAfterWithdraw);
    }

    function testVaultHandlesSmallDepositAndWithdraw() public {
        uint256 userBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 10) / 10000;
        vm.startPrank(wantHolderAddr);
        vault.deposit(depositAmount);

        vault.withdraw(depositAmount);
        uint256 userBalanceAfterWithdraw = want.balanceOf(wantHolderAddr);

        assertEq(userBalance, userBalanceAfterWithdraw);
    }

    function testCanHarvest() public {
        uint256 timeToSkip = 3600;
        uint256 wantBalance = want.balanceOf(wantHolderAddr);
        vm.prank(wantHolderAddr);
        vault.deposit(wantBalance);
        vm.startPrank(keepers[0]);
        wrappedProxy.harvest();

        uint256 vaultBalanceBefore = vault.balance();
        skip(timeToSkip);
        int256 roi = wrappedProxy.harvest();
        console.log("roi: ");
        console.logInt(roi);
        uint256 vaultBalanceAfter = vault.balance();
        console.log("vaultBalanceBefore: ", vaultBalanceBefore);
        console.log("vaultBalanceAfter: ", vaultBalanceAfter);

        assertEq(vaultBalanceAfter - vaultBalanceBefore, uint256(roi));
    }

    // Make _compound public to test
    // function testGetsCollateralOnLiquidation() public {
    //     console.log("testGetsCollateralOnLiquidation()");
    //     uint256 timeToSkip = 3600;
    //     uint256 wantBalance = want.balanceOf(wantHolderAddr);
    //     vm.prank(wantHolderAddr);
    //     vault.deposit(wantBalance);
    //     vm.prank(keepers[0]);
    //     wrappedProxy.harvest();
    //     skip(timeToSkip);

    //     address wethAggregator = IPriceFeed(priceFeedAddress).priceAggregator(wethAddress);
    //     console.log("wethAggregator: ", wethAggregator);

    //     MockAggregator mockChainlink = new MockAggregator();
    //     mockChainlink.setPrevRoundId(2);
    //     mockChainlink.setLatestRoundId(3);
    //     mockChainlink.setPrice(1500 * 10**8);
    //     mockChainlink.setPrevPrice(1500 * 10**8);
    //     mockChainlink.setUpdateTime(block.timestamp);

    //     MockAggregator mockChainlink2 = new MockAggregator();
    //     mockChainlink2.setPrevRoundId(2);
    //     mockChainlink2.setLatestRoundId(3);
    //     mockChainlink2.setPrice(22_000 * 10**8);
    //     mockChainlink2.setPrevPrice(22_000 * 10**8);
    //     mockChainlink2.setUpdateTime(block.timestamp);

    //     uint256 oldWethPrice = IPriceFeed(priceFeedAddress).fetchPrice(wethAddress);
    //     console.log("oldWethPrice: ", oldWethPrice);
    //     uint256 oldWbtcPrice = IPriceFeed(priceFeedAddress).fetchPrice(wbtcAddress);
    //     console.log("oldWbtcPrice: ", oldWbtcPrice);

    //     vm.startPrank(priceFeedOwnerAddress);
    //     IPriceFeed(priceFeedAddress).updateChainlinkAggregator(wethAddress, address(mockChainlink));
    //     IPriceFeed(priceFeedAddress).updateChainlinkAggregator(wbtcAddress, address(mockChainlink2));
    //     vm.stopPrank();
    //     uint256 newWethPrice = IPriceFeed(priceFeedAddress).fetchPrice(wethAddress);
    //     console.log("newWethPrice: ", newWethPrice);
    //     uint256 newWbtcPrice = IPriceFeed(priceFeedAddress).fetchPrice(wbtcAddress);
    //     console.log("newWbtcPrice: ", newWbtcPrice);

    //     uint256 rewardTokenGain = IStabilityPool(stabilityPoolAddress).getDepositorLQTYGain(address(wrappedProxy));
    //     console.log("rewardTokenGain: ", rewardTokenGain);

    //     // log the balance of the stability pool
    //     console.log("SP ERN bal before wbtc liquidate: ", want.balanceOf(stabilityPoolAddress));
    //     // log the debt + collateral of the wbtc market
    //     liquidateTroves(wbtcAddress);
    //     console.log("SP ERN bal after wbtc liquidate: ", want.balanceOf(stabilityPoolAddress));
    //     // log the balance of the stability pool
    //     // log the debt + collateral of the wbtc market
    //     // log wbtc balance of stability pool

    //     liquidateTroves(wethAddress);

    //     wrappedProxy.getCollateralGain();

    //     rewardTokenGain = IStabilityPool(stabilityPoolAddress).getDepositorLQTYGain(address(wrappedProxy));
    //     console.log("rewardTokenGain: ", rewardTokenGain);

    //     console.log("----------------------------------------------------------------------");
    //     wrappedProxy.balanceOfPool();

    //     wrappedProxy.compound();
    //     console.log("----------------------------------------------------------------------");
    //     wrappedProxy.balanceOfPool();
    //     console.log("----------------------------------------------------------------------");

    //     vm.prank(address(wrappedProxy));
    //     IStabilityPool(stabilityPoolAddress).withdrawFromSP(0);

    //     uint256 poolBalance = wrappedProxy.balanceOfPool();
    //     console.log("poolBalance: ", poolBalance);

    //     uint256 stabilityPoolWethBalance = IERC20Upgradeable(wethAddress).balanceOf(stabilityPoolAddress);
    //     uint256 stabilityPoolWbtcBalance = IERC20Upgradeable(wbtcAddress).balanceOf(stabilityPoolAddress);
    //     console.log("stabilityPoolWethBalance: ", stabilityPoolWethBalance);
    //     console.log("stabilityPoolWbtcBalance: ", stabilityPoolWbtcBalance);

    //     uint256 strategyWethBalance = IERC20Upgradeable(wethAddress).balanceOf(address(wrappedProxy));
    //     uint256 strategyWbtcBalance = IERC20Upgradeable(wbtcAddress).balanceOf(address(wrappedProxy));
    //     console.log("strategyWethBalance: ", strategyWethBalance);
    //     console.log("strategyWbtcBalance: ", strategyWbtcBalance);
    // }

    function testCanProvideYield() public {
        uint256 timeToSkip = 3600;
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 1000) / 10000;

        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);
        uint256 initialVaultBalance = vault.balance();

        uint256 numHarvests = 5;

        for (uint256 i; i < numHarvests; i++) {
            skip(timeToSkip);
            wrappedProxy.harvest();
        }

        uint256 finalVaultBalance = vault.balance();
        console.log("initialVaultBalance: ", initialVaultBalance);
        console.log("finalVaultBalance: ", finalVaultBalance);
        assertEq(finalVaultBalance > initialVaultBalance, true);
    }

    function testStrategyGetsMoreFunds() public {
        uint256 startingAllocationBPS = 9000;
        vault.updateStrategyAllocBPS(address(wrappedProxy), startingAllocationBPS);
        uint256 timeToSkip = 3600;
        uint256 depositAmount = 500 ether;

        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);

        wrappedProxy.harvest();
        skip(timeToSkip);
        uint256 vaultBalance = vault.balance();
        uint256 vaultWantBalance = want.balanceOf(address(vault));
        uint256 strategyBalance = wrappedProxy.balanceOf();
        assertEq(vaultBalance, depositAmount);
        assertEq(vaultWantBalance, 50 ether);
        assertEq(strategyBalance, 450 ether);

        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);

        wrappedProxy.harvest();
        skip(timeToSkip);

        vaultBalance = vault.balance();
        vaultWantBalance = want.balanceOf(address(vault));
        strategyBalance = wrappedProxy.balanceOf();
        console.log("strategyBalance: ", strategyBalance);
        assertGt(vaultBalance, depositAmount * 2);
        assertGt(vaultWantBalance, 100 ether);
        assertEq(strategyBalance, 900 ether);
    }

    function testVaultPullsFunds() public {
        uint256 startingAllocationBPS = 9000;
        vault.updateStrategyAllocBPS(address(wrappedProxy), startingAllocationBPS);
        uint256 timeToSkip = 3600;
        uint256 depositAmount = 100 ether;

        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);

        wrappedProxy.harvest();
        skip(timeToSkip);

        uint256 vaultBalance = vault.balance();
        uint256 vaultWantBalance = want.balanceOf(address(vault));
        uint256 strategyBalance = wrappedProxy.balanceOf();
        assertEq(vaultBalance, depositAmount);
        assertEq(vaultWantBalance, 10 ether);
        assertEq(strategyBalance, 90 ether);

        uint256 newAllocationBPS = 7000;
        vault.updateStrategyAllocBPS(address(wrappedProxy), newAllocationBPS);
        wrappedProxy.harvest();

        vaultBalance = vault.balance();
        vaultWantBalance = want.balanceOf(address(vault));
        strategyBalance = wrappedProxy.balanceOf();
        assertGt(vaultBalance, depositAmount);
        assertGt(vaultWantBalance, 30 ether);
        assertEq(strategyBalance, 70 ether);

        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);

        wrappedProxy.harvest();
        skip(timeToSkip);

        vaultBalance = vault.balance();
        vaultWantBalance = want.balanceOf(address(vault));
        strategyBalance = wrappedProxy.balanceOf();
        assertGt(vaultBalance, depositAmount * 2);
        assertGt(vaultWantBalance, 60 ether);
        assertGt(strategyBalance, 140 ether);
    }

    function testEmergencyShutdown() public {
        uint256 startingAllocationBPS = 9000;
        vault.updateStrategyAllocBPS(address(wrappedProxy), startingAllocationBPS);
        uint256 timeToSkip = 3600;
        uint256 depositAmount = 1000 ether;

        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);

        wrappedProxy.harvest();
        skip(timeToSkip);

        uint256 vaultBalance = vault.balance();
        uint256 vaultWantBalance = want.balanceOf(address(vault));
        uint256 strategyBalance = wrappedProxy.balanceOf();
        assertEq(vaultBalance, depositAmount);
        assertEq(vaultWantBalance, 100 ether);
        assertEq(strategyBalance, 900 ether);

        vault.setEmergencyShutdown(true);
        wrappedProxy.harvest();

        vaultBalance = vault.balance();
        vaultWantBalance = want.balanceOf(address(vault));
        strategyBalance = wrappedProxy.balanceOf();
        console.log("vaultBalance: ", vaultBalance);
        console.log("depositAmount: ", depositAmount);
        console.log("vaultWantBalance: ", vaultWantBalance);
        console.log("strategyBalance: ", strategyBalance);
        assertGt(vaultBalance, depositAmount);
        assertGt(vaultWantBalance, depositAmount);
        assertEq(strategyBalance, 0);
    }

    // function testSharePriceChanges() public {
    //     uint256 sharePrice1 = vault.getPricePerFullShare();
    //     uint256 timeToSkip = 36000;
    //     uint256 wantBalance = want.balanceOf(wantHolderAddr);
    //     vm.prank(wantHolderAddr);
    //     vault.deposit(wantBalance);
    //     uint256 sharePrice2 = vault.getPricePerFullShare();
    //     vm.prank(keepers[0]);
    //     wrappedProxy.harvest();
    //     skip(timeToSkip);
    //     uint256 sharePrice3 = vault.getPricePerFullShare();

    //     address wethAggregator = IPriceFeed(priceFeedAddress).priceAggregator(wethAddress);
    //     console.log("wethAggregator: ", wethAggregator);

    //     MockAggregator mockChainlink = new MockAggregator();
    //     mockChainlink.setPrevRoundId(2);
    //     mockChainlink.setLatestRoundId(3);
    //     mockChainlink.setPrice(1500 * 10 ** 8);
    //     mockChainlink.setPrevPrice(1500 * 10 ** 8);
    //     mockChainlink.setUpdateTime(block.timestamp);

    //     MockAggregator mockChainlink2 = new MockAggregator();
    //     mockChainlink2.setPrevRoundId(2);
    //     mockChainlink2.setLatestRoundId(3);
    //     mockChainlink2.setPrice(25_000 * 10 ** 8);
    //     mockChainlink2.setPrevPrice(25_000 * 10 ** 8);
    //     mockChainlink2.setUpdateTime(block.timestamp);

    //     vm.startPrank(priceFeedOwnerAddress);
    //     // IPriceFeed(priceFeedAddress).updateChainlinkAggregator(wethAddress, address(mockChainlink));
    //     IPriceFeed(priceFeedAddress).updateChainlinkAggregator(wbtcAddress, address(mockChainlink2));
    //     vm.stopPrank();

    //     uint256 rewardTokenGain = IStabilityPool(stabilityPoolAddress).getDepositorLQTYGain(address(wrappedProxy));

    //     liquidateTroves(wbtcAddress);
    //     // liquidateTroves(wethAddress);

    //     wrappedProxy.harvest();
    //     skip(timeToSkip);
    //     uint256 sharePrice4 = vault.getPricePerFullShare();

    //     wrappedProxy.getERNValueOfCollateralGain();

    //     console.log("sharePrice1: ", sharePrice1);
    //     console.log("sharePrice2: ", sharePrice2);
    //     console.log("sharePrice3: ", sharePrice3);
    //     console.log("sharePrice4: ", sharePrice4);
    //     assertGt(sharePrice4, sharePrice1);
    // }

    function testVeloTWAP() public {
        console.log("testVeloTWAP");
        uint256 iterations = 20;
        IVelodromePair pool = IVelodromePair(veloUsdcErnPool);
        uint256 currentPrice = pool.getAmountOut(1 ether, address(want));
        console.log("currentPrice: ", currentPrice);
        for (uint256 index = 1; index < iterations; index++) {
            uint256 currentPriceQuote = pool.quote(address(want), 1 ether, index);
            console.log("currentPriceQuote", index);
            console.log(currentPriceQuote);
        }

        address dumpourBob = makeAddr("bob");
        uint256 usdcUnit = 10 ** 6;
        uint256 usdcToDump = 4_000_000 * usdcUnit;
        deal({token: usdcAddress, to: dumpourBob, give: usdcToDump});

        IVeloRouter router = IVeloRouter(veloRouter);
        IVeloRouter.Route[] memory routes = new IVeloRouter.Route[](1);
        routes[0] = IVeloRouter.Route({from: usdcAddress, to: wantAddress, stable: true, factory: veloFactoryV2Default});
        vm.startPrank(dumpourBob);
        IERC20(usdcAddress).approve(veloRouter, usdcToDump);
        uint256 minAmountOut = 0;
        router.swapExactTokensForTokens(usdcToDump - usdcUnit, minAmountOut, routes, dumpourBob, block.timestamp);

        uint256 timeToSkip = 60 * 30;
        skip(timeToSkip);
        router.swapExactTokensForTokens(usdcUnit, minAmountOut, routes, dumpourBob, block.timestamp);

        uint256 dumpedPrice = pool.getAmountOut(1 ether, address(want));
        console.log("dumpedPrice: ", dumpedPrice);
        for (uint256 index = 1; index < iterations; index++) {
            uint256 dumpedPriceQuote = pool.quote(address(want), 1 ether, index);
            console.log("dumpedPriceQuote", index);
            console.log(dumpedPriceQuote);
        }
    }

    function testUsdcBalanceCalculations() public {
        address usdcOracleOwner = 0xAbC73A7dbd0A1D6576d55F19809a6F017913C078;
        vm.startPrank(usdcOracleOwner);
        IAggregatorAdmin aggregator = IAggregatorAdmin(chainlinkUsdcOracle);

        int256 newUsdcPrice = 950_000_000;
        MockAggregator mockChainlink = new MockAggregator();
        mockChainlink.setPrevRoundId(2);
        mockChainlink.setLatestRoundId(3);
        mockChainlink.setPrice(newUsdcPrice);
        mockChainlink.setPrevPrice(newUsdcPrice);
        mockChainlink.setUpdateTime(block.timestamp);

        // aggregator.proposeAggregator(address(mockChainlink));
        // aggregator.confirmAggregator(address(mockChainlink));

        uint256 valueInCollateralBefore = wrappedProxy.getERNValueOfCollateralGain();
        uint256 poolBalanceBefore = wrappedProxy.balanceOfPool();

        uint256 usdcAmount = 100_000 * (10 ** 6);
        deal({token: usdcAddress, to: address(wrappedProxy), give: usdcAmount});

        uint256 valueInCollateralAfter = wrappedProxy.getERNValueOfCollateralGain();
        uint256 poolBalanceAfter = wrappedProxy.balanceOfPool();
        console.log("valueInCollateralBefore: ", valueInCollateralBefore);
        console.log("valueInCollateralAfter: ", valueInCollateralAfter);
        console.log("poolBalanceBefore: ", poolBalanceBefore);
        console.log("poolBalanceAfter: ", poolBalanceAfter);

        IVelodromePair pool = IVelodromePair(veloUsdcErnPool);
        uint256 granularity = wrappedProxy.veloUsdcErnQuoteGranularity();

        ReaperStrategyStabilityPool.TWAP currentTWAP = wrappedProxy.currentUsdcErnTWAP();

        uint256 priceQuote;
        if (currentTWAP == ReaperStrategyStabilityPool.TWAP.UniV3) {
            address[] memory pools = new address[](1);
            pools[0] = address(uniV3UsdcErnPool);
            priceQuote = IStaticOracle(uniV3TWAP).quoteSpecificPoolsWithTimePeriod(
                uint128(usdcAmount), usdcAddress, wantAddress, pools, 2
            );
        } else if (currentTWAP == ReaperStrategyStabilityPool.TWAP.VeloV2) {
            priceQuote = pool.quote(usdcAddress, usdcAmount, granularity);
        }
        // Values should be the same because the usdc balance will be valued
        // using the Velo TWAP
        assertEq(valueInCollateralAfter, priceQuote);

        uint256 compoundingFeeMarginBPS = wrappedProxy.compoundingFeeMarginBPS();
        uint256 expectedPoolBalance = valueInCollateralAfter * compoundingFeeMarginBPS / BPS_UNIT;
        console.log("expectedPoolBalance: ", expectedPoolBalance);
        assertEq(poolBalanceAfter, expectedPoolBalance);
    }

    function testCollateralBalanceCalculations() public {
        // address usdcOracleOwner = 0xAbC73A7dbd0A1D6576d55F19809a6F017913C078;
        // vm.startPrank(usdcOracleOwner);
        // IAggregatorAdmin aggregator = IAggregatorAdmin(chainlinkUsdcOracle);

        // int256 newUsdcPrice = 950_000_000;
        // MockAggregator mockChainlink = new MockAggregator();
        // mockChainlink.setPrevRoundId(2);
        // mockChainlink.setLatestRoundId(3);
        // mockChainlink.setPrice(newUsdcPrice);
        // mockChainlink.setPrevPrice(newUsdcPrice);
        // mockChainlink.setUpdateTime(block.timestamp);

        // aggregator.proposeAggregator(address(mockChainlink));
        // aggregator.confirmAggregator(address(mockChainlink));

        // Funds need to be deposited in the stability pool for collateral to count in the balance
        uint256 wantBalance = want.balanceOf(wantHolderAddr);
        vm.prank(wantHolderAddr);
        vault.deposit(wantBalance);
        wrappedProxy.harvest();

        // uint256 valueInCollateralBefore = wrappedProxy.getERNValueOfCollateralGain();
        uint256 poolBalanceBefore = wrappedProxy.balanceOfPool();

        uint256 wbtcAmount = 1 * (10 ** 8);
        uint256 wethAmount = 10 ether;
        uint256 opAmount = 1000 ether;
        deal({token: wbtcAddress, to: address(wrappedProxy), give: wbtcAmount});
        deal({token: wethAddress, to: address(wrappedProxy), give: wethAmount});
        deal({token: opAddress, to: address(wrappedProxy), give: opAmount});

        // uint256 valueInCollateralAfter = wrappedProxy.getERNValueOfCollateralGain();
        uint256 poolBalanceAfter = wrappedProxy.balanceOfPool();
        // console.log("valueInCollateralBefore: ", valueInCollateralBefore);
        // console.log("valueInCollateralAfter: ", valueInCollateralAfter);
        // console.log("poolBalanceBefore: ", poolBalanceBefore);
        // console.log("poolBalanceAfter: ", poolBalanceAfter);

        // console.log("poolBalanceIncrease: ", poolBalanceAfter - poolBalanceBefore);

        // console.log("wbtcAggregator: ", wbtcAggregator);
        // console.log("wethAggregator: ", wethAggregator);
        // console.log("opAggregator: ", opAggregator);
        (, int256 wbtcPrice,,,) = wbtcAggregator.latestRoundData();
        (, int256 wethPrice,,,) = wethAggregator.latestRoundData();
        (, int256 opPrice,,,) = opAggregator.latestRoundData();
        console.log("wbtcPrice: ");
        console.logInt(wbtcPrice);
        console.log("wethPrice: ");
        console.logInt(wethPrice);
        console.log("opPrice: ");
        console.logInt(opPrice);

        // All usd values must have 18 decimals for comparison.
        // WETH and OP already have 18 decimals, but we need to scale WBTC.
        uint256 wbtcUsdValue = wbtcAmount * uint256(wbtcPrice) * (10 ** 2);
        uint256 wethUsdValue = wethAmount * uint256(wethPrice) / (10 ** 8);
        uint256 opUsdValue = opAmount * uint256(opPrice) / (10 ** 8);
        uint256 expectedUsdValueInCollateral = wbtcUsdValue + wethUsdValue + opUsdValue;
        console.log("wbtcUsdValue: ", wbtcUsdValue);
        console.log("wethUsdValue: ", wethUsdValue);
        console.log("opUsdValue: ", opUsdValue);

        uint256 usdValueInCollateral = wrappedProxy.getUSDValueOfCollateralGain();
        console.log("expectedUsdValueInCollateral: ", expectedUsdValueInCollateral);
        console.log("usdValueInCollateral: ", usdValueInCollateral);
        assertEq(usdValueInCollateral, expectedUsdValueInCollateral);

        (, int256 usdcAnswer,,,) = usdcAggregator.latestRoundData();
        uint256 usdcPrice = uint256(usdcAnswer);
        console.log("usdcPrice: ", usdcPrice);

        // uint256 scaledUsdValueInCollateral = ;
        uint256 usdcAmount = ((usdValueInCollateral / (10 ** 12)) * (10 ** 8)) / usdcPrice;
        console.log("usdcAmount: ", usdcAmount);

        // IVelodromePair pool = IVelodromePair(veloUsdcErnPool);
        // uint256 granularity = wrappedProxy.veloUsdcErnQuoteGranularity();
        ReaperStrategyStabilityPool.TWAP currentTWAP = wrappedProxy.currentUsdcErnTWAP();
        console.log("currentTWAP: ", uint256(currentTWAP));
        uint256 ernAmount;
        if (currentTWAP == ReaperStrategyStabilityPool.TWAP.UniV3) {
            address[] memory pools = new address[](1);
            pools[0] = address(uniV3UsdcErnPool);
            uint32 twapPeriod = wrappedProxy.uniV3TWAPPeriod();
            console.log("twapPeriod: ", twapPeriod);
            ernAmount = IStaticOracle(uniV3TWAP).quoteSpecificPoolsWithTimePeriod(
                uint128(usdcAmount), usdcAddress, wantAddress, pools, twapPeriod
            );
        } else if (currentTWAP == ReaperStrategyStabilityPool.TWAP.VeloV2) {
            ernAmount = IVelodromePair(veloUsdcErnPool).quote(
                usdcAddress, usdcAmount, wrappedProxy.veloUsdcErnQuoteGranularity()
            );
        }
        uint256 wantValueInCollateral = wrappedProxy.getERNValueOfCollateralGain();

        console.log("ernAmount: ", ernAmount);
        console.log("wantValueInCollateral: ", wantValueInCollateral);
        assertApproxEqRel(ernAmount, wantValueInCollateral, 1e8);

        uint256 compoundingFeeMarginBPS = wrappedProxy.compoundingFeeMarginBPS();
        uint256 expectedPoolIncrease = ernAmount * compoundingFeeMarginBPS / BPS_UNIT;
        // console.log("poolBalanceIncrease: ", poolBalanceAfter - poolBalanceBefore);
        // console.log("expectedPoolIncrease: ", expectedPoolIncrease);
        // assertEq(poolBalanceAfter - poolBalanceBefore, expectedPoolIncrease);
    }

    function testUsdcPriceChange() public {
        address usdcOracleOwner = 0xAbC73A7dbd0A1D6576d55F19809a6F017913C078;
        vm.startPrank(usdcOracleOwner);
        IAggregatorAdmin aggregator = IAggregatorAdmin(chainlinkUsdcOracle);
        uint256 usdcPrice = 10 ** 8;

        MockAggregator mockChainlink = new MockAggregator();
        mockChainlink.setPrevRoundId(2);
        mockChainlink.setLatestRoundId(3);
        mockChainlink.setPrice(int256(usdcPrice));
        mockChainlink.setPrevPrice(int256(usdcPrice));
        mockChainlink.setUpdateTime(block.timestamp);

        aggregator.proposeAggregator(address(mockChainlink));
        aggregator.confirmAggregator(address(mockChainlink));
        // Funds need to be deposited in the stability pool for collateral to count in the balance
        uint256 wantBalance = want.balanceOf(wantHolderAddr);
        vm.stopPrank();
        vm.prank(wantHolderAddr);
        vault.deposit(wantBalance);
        wrappedProxy.harvest();

        uint256 wbtcAmount = 1 * (10 ** 8);
        uint256 wethAmount = 10 ether;
        uint256 opAmount = 1000 ether;
        deal({token: wbtcAddress, to: address(wrappedProxy), give: wbtcAmount});
        deal({token: wethAddress, to: address(wrappedProxy), give: wethAmount});
        deal({token: opAddress, to: address(wrappedProxy), give: opAmount});

        uint256 valueInCollateral = wrappedProxy.getERNValueOfCollateralGain();
        console.log("valueInCollateral: ", valueInCollateral);

        uint256 newUsdcPrice = usdcPrice * 9500 / BPS_UNIT;
        vm.startPrank(usdcOracleOwner);
        mockChainlink.setPrice(int256(newUsdcPrice));
        mockChainlink.setPrevPrice(int256(newUsdcPrice));

        // uint256 usdcPrice = uint256(usdcAggregator.latestAnswer());
        // console.log("usdcPrice: ", usdcPrice);

        uint256 expectedValueInCollateral = valueInCollateral * 10_526 / BPS_UNIT;
        valueInCollateral = wrappedProxy.getERNValueOfCollateralGain();
        console.log("expectedValueInCollateral: ", expectedValueInCollateral);
        console.log("valueInCollateral: ", valueInCollateral);
        assertApproxEqRel(valueInCollateral, expectedValueInCollateral, 0.005e18);
    }

    // function testVeloTWAPQuoteAmounts() public {
    //     uint256 usdcUnit = 10 ** 6;

    //     IVelodromePair pool = IVelodromePair(veloUsdcErnPool);
    //     uint256 granularity = wrappedProxy.veloUsdcErnQuoteGranularity();

    //     uint256 priceQuote1 = pool.quote(usdcAddress, usdcUnit, granularity);
    //     uint256 priceQuote2 = pool.quote(usdcAddress, usdcUnit * 10, granularity);
    //     uint256 priceQuote3 = pool.quote(usdcAddress, usdcUnit * 100, granularity);
    //     uint256 priceQuote4 = pool.quote(usdcAddress, usdcUnit * 1000, granularity);
    //     uint256 priceQuote5 = pool.quote(usdcAddress, usdcUnit * 10_000, granularity);
    //     uint256 priceQuote6 = pool.quote(usdcAddress, usdcUnit * 100_000, granularity);
    //     uint256 priceQuote7 = pool.quote(usdcAddress, usdcUnit * 1_000_000, granularity);
    //     uint256 priceQuote8 = pool.quote(usdcAddress, usdcUnit * 10_000_000, granularity);
    //     uint256 priceQuote9 = pool.quote(usdcAddress, usdcUnit * 100_000_000, granularity);
    //     uint256 priceQuote10 = pool.quote(usdcAddress, usdcUnit * 1_000_000_000, granularity);
    //     console.log("priceQuote1: ", priceQuote1);
    //     console.log("priceQuote2: ", priceQuote2 / 10);
    //     console.log("priceQuote3: ", priceQuote3 / 100);
    //     console.log("priceQuote4: ", priceQuote4 / 1000);
    //     console.log("priceQuote5: ", priceQuote5 / 10_000);
    //     console.log("priceQuote6: ", priceQuote6 / 100_000);
    //     console.log("priceQuote7: ", priceQuote7 / 1_000_000);
    //     console.log("priceQuote8: ", priceQuote8 / 10_000_000);
    //     console.log("priceQuote9: ", priceQuote9 / 100_000_000);
    //     console.log("priceQuote10: ", priceQuote10 / 1_000_000_000);
    // }

    function testUniV3TWAPMultipleSwaps() public {
        uint128 usdcUnit = 10 ** 6;
        uint32 period = 120;
        uint256 timeToSkip = 20;

        uint256 usdcInPool = IERC20Upgradeable(usdcAddress).balanceOf(uniV3UsdcErnPool);
        console.log("usdcInPool: ", usdcInPool);
        uint256 usdcToDump = usdcInPool * 9999 / 10_000;

        deal({token: usdcAddress, to: address(this), give: usdcToDump * 100});

        console.log("calling _swapUsdcToErnUniV3");
        _swapUsdcToErnUniV3(usdcToDump);
        _skipBlockAndTime(timeToSkip);

        uint256 priceQuote = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period);
        uint256 priceQuoteSpot = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, 0);
        console.log("priceQuote1: ", priceQuote);
        console.log("priceQuoteSpot1: ", priceQuoteSpot);

        _swapUsdcToErnUniV3(usdcToDump);
        _skipBlockAndTime(timeToSkip);

        priceQuote = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period);
        priceQuoteSpot = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, 0);
        console.log("priceQuote2: ", priceQuote);
        console.log("priceQuoteSpot2: ", priceQuoteSpot);

        _swapUsdcToErnUniV3(usdcToDump);
        _skipBlockAndTime(timeToSkip);

        priceQuote = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period);
        priceQuoteSpot = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, 0);
        console.log("priceQuote3: ", priceQuote);
        console.log("priceQuoteSpot3: ", priceQuoteSpot);

        _swapUsdcToErnUniV3(usdcToDump);
        _skipBlockAndTime(timeToSkip);

        priceQuote = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period);
        priceQuoteSpot = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, 0);
        console.log("priceQuote4: ", priceQuote);
        console.log("priceQuoteSpot4: ", priceQuoteSpot);

        _swapUsdcToErnUniV3(usdcToDump);
        _skipBlockAndTime(timeToSkip);

        priceQuote = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period);
        priceQuoteSpot = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, 0);
        console.log("priceQuote5: ", priceQuote);
        console.log("priceQuoteSpot5: ", priceQuoteSpot);

        _swapUsdcToErnUniV3(usdcToDump);
        _skipBlockAndTime(timeToSkip);

        priceQuote = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period);
        priceQuoteSpot = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, 0);
        console.log("priceQuote6: ", priceQuote);
        console.log("priceQuoteSpot6: ", priceQuoteSpot);

        _swapUsdcToErnUniV3(usdcToDump);
        _skipBlockAndTime(timeToSkip);

        priceQuote = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period);
        priceQuoteSpot = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, 0);
        console.log("priceQuote7: ", priceQuote);
        console.log("priceQuoteSpot7: ", priceQuoteSpot);

        _swapUsdcToErnUniV3(usdcToDump);
        _skipBlockAndTime(timeToSkip);

        priceQuote = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period);
        priceQuoteSpot = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, 0);
        console.log("priceQuote8: ", priceQuote);
        console.log("priceQuoteSpot8: ", priceQuoteSpot);

        _swapUsdcToErnUniV3(usdcToDump);
        _skipBlockAndTime(timeToSkip);

        priceQuote = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period);
        priceQuoteSpot = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, 0);
        console.log("priceQuote9: ", priceQuote);
        console.log("priceQuoteSpot9: ", priceQuoteSpot);
    }

    function testUniV3TWAPSingleSwap() public {
        uint32 period = 100;

        uint256 usdcInPool = IERC20Upgradeable(usdcAddress).balanceOf(uniV3UsdcErnPool);
        console.log("usdcInPool: ", usdcInPool);
        uint256 usdcToDump = usdcInPool * 9999 / 10_000;
        uint256 ernToDump = 10 * 1 ether;
        deal({token: usdcAddress, to: address(this), give: usdcToDump * 100});
        deal({token: wantAddress, to: address(this), give: ernToDump * 100});

        uint128 usdcUnit = 10 ** 6;

        _skipBlockAndTime(1);
        // Fill up TWAP slots
        for (uint256 index = 0; index < period / 2 + 1; index++) {
            if (index % 2 == 0) {
                _swapUsdcToErnUniV3(usdcUnit);
                // console.log("_swapUsdcToErnUniV3");
            } else {
                _swapErnToUsdcUniV3(1 ether);
                // console.log("_swapErnToUsdcUniV3");
            }
            _skipBlockAndTime(1);
        }

        uint256 priceQuote = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period);

        console.log("priceQuote: ", priceQuote);

        console.log("calling _swapUsdcToErnUniV3");
        _skipBlockAndTime(1);
        _swapUsdcToErnUniV3(usdcToDump);
        _skipBlockAndTime(1);

        priceQuote = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period);
        uint256 priceQuoteHalf = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period / 2);
        uint256 priceQuoteQuarter = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period / 4);
        uint256 priceQuoteEigth = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period / 8);
        uint256 priceQuoteSixteenth = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, period / 16);
        uint256 priceQuoteSpot = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, 0);
        priceQuoteSpot = wrappedProxy.getErnAmountForUsdcUniV3(usdcUnit, 0);
        console.log("priceQuote1: ", priceQuote);
        console.log("priceQuoteHalf: ", priceQuoteHalf);
        console.log("priceQuoteQuarter: ", priceQuoteQuarter);
        console.log("priceQuoteEigth: ", priceQuoteEigth);
        console.log("priceQuoteSixteenth: ", priceQuoteSixteenth);
        console.log("priceQuoteSpot1: ", priceQuoteSpot);
    }

    function liquidateTroves(address asset) internal {
        ITroveManager(troveManager).liquidateTroves(asset, 100);
    }

    function _toWant(uint256 amount) internal returns (uint256) {
        return amount * (10 ** want.decimals());
    }

    function _swapUsdcToErnUniV3(uint256 _amount) internal returns (uint256 amountOut) {
        return _swapUniV3(_amount, usdcAddress, wantAddress);
    }

    function _swapErnToUsdcUniV3(uint256 _amount) internal returns (uint256 amountOut) {
        return _swapUniV3(_amount, wantAddress, usdcAddress);
    }

    function _swapUniV3(uint256 _amount, address token0, address token1) internal returns (uint256 amountOut) {
        if (_amount == 0) {
            return 0;
        }

        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;

        uint24[] memory fees = new uint24[](1);
        fees[0] = 500;

        uint256 minAmountOut = 0;

        bytes memory pathBytes = _encodePathV3(path, fees);
        TransferHelper.safeApprove(path[0], uniV3Router, _amount);
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: pathBytes,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amount,
            amountOutMinimum: minAmountOut
        });
        // console.log("calling exactInput");
        amountOut = ISwapRouter(uniV3Router).exactInput(params);
    }

    /**
     * Encode path / fees to bytes in the format expected by UniV3 router
     *
     * @param _path          List of token address to swap via (starting with input token)
     * @param _fees          List of fee levels identifying the pools to swap via.
     *                       (_fees[0] refers to pool between _path[0] and _path[1])
     *
     * @return encodedPath   Encoded path to be forwared to uniV3 router
     */
    function _encodePathV3(address[] memory _path, uint24[] memory _fees)
        private
        pure
        returns (bytes memory encodedPath)
    {
        encodedPath = abi.encodePacked(_path[0]);
        for (uint256 i = 0; i < _fees.length; i++) {
            encodedPath = abi.encodePacked(encodedPath, _fees[i], _path[i + 1]);
        }
    }

    function _skipBlockAndTime(uint256 _amount) private {
        // console.log("_skipBlockAndTime");

        // console.log("block.timestamp: ", block.timestamp);
        skip(_amount * 2);
        // console.log("block.timestamp: ", block.timestamp);

        // console.log("block.number: ", block.number);
        vm.roll(block.number + _amount);
        // console.log("block.number: ", block.number);
    }
}
