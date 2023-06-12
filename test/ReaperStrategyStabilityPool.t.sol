// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/ReaperStrategyStabilityPool.sol";
import "vault-v2/ReaperVaultV2.sol";
import "vault-v2/interfaces/IVeloRouter.sol";
import "src/mocks/MockAggregator.sol";
import "src/interfaces/ITroveManager.sol";
import "src/interfaces/IStabilityPool.sol";
import "src/interfaces/IVelodromePair.sol";
import "src/interfaces/IAggregatorAdmin.sol";
import "src/interfaces/AggregatorV3Interface.sol";
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
    address public veloRouter = 0x9c12939390052919aF3155f41Bf4160Fd3666A6f;
    address public balVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniV3Quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address public veloUsdcErnPool = 0x55624DC97289A19045b4739627BEaEB1E70Ab64c;
    address public chainlinkUsdcOracle = 0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;

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

    ERC20 public want = ERC20(wantAddress);
    ERC20 public wftm = ERC20(wethAddress);

    function setUp() public {
        // Forking
        optimismFork = vm.createSelectFork(
            "https://late-fragrant-rain.optimism.quiknode.pro/08eedcb171832b45c4961c9ff1392491e9b4cfaf/", 105252830
        );
        assertEq(vm.activeFork(), optimismFork);

        // // Deploying stuff
        vault =
        new ReaperVaultV2(wantAddress, vaultName, vaultSymbol, vaultTvlCap, treasuryAddress, strategists, multisigRoles);
        implementation = new ReaperStrategyStabilityPool();
        proxy = new ERC1967Proxy(address(implementation), "");
        wrappedProxy = ReaperStrategyStabilityPool(address(proxy));

        ReaperStrategyStabilityPool.ExchangeSettings memory exchangeSettings;
        exchangeSettings.veloRouter = veloRouter;
        exchangeSettings.balVault = balVault;
        exchangeSettings.uniV3Router = uniV3Router;
        exchangeSettings.uniV3Quoter = uniV3Quoter;

        ReaperStrategyStabilityPool.Pools memory pools;
        pools.stabilityPool = stabilityPoolAddress;
        pools.veloUsdcErnPool = veloUsdcErnPool;

        address[] memory usdcErnPath = new address[](2);
        usdcErnPath[0] = usdcAddress;
        usdcErnPath[1] = wantAddress;

        ReaperStrategyStabilityPool.Tokens memory tokens;
        tokens.want = wantAddress;
        tokens.oath = oathAddress;
        tokens.usdc = usdcAddress;

        wrappedProxy.initialize(
            address(vault),
            strategists,
            multisigRoles,
            keepers,
            priceFeedAddress,
            balErnPoolId,
            chainlinkUsdcOracle,
            exchangeSettings,
            pools,
            usdcErnPath,
            tokens
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

        // function updateVeloSwapPath(address _tokenIn, address _tokenOut, address[] calldata _path)
        address[] memory wethErnPath = new address[](3);
        wethErnPath[0] = wethAddress;
        wethErnPath[1] = usdcAddress;
        wethErnPath[2] = wantAddress;
        wrappedProxy.updateVeloSwapPath(wethAddress, wantAddress, wethErnPath);

        address[] memory wbtcErnPath = new address[](3);
        wbtcErnPath[0] = wbtcAddress;
        wbtcErnPath[1] = usdcAddress;
        wbtcErnPath[2] = wantAddress;
        wrappedProxy.updateVeloSwapPath(wbtcAddress, wantAddress, wbtcErnPath);

        address[] memory oathErnPath = new address[](3);
        oathErnPath[0] = oathAddress;
        oathErnPath[1] = usdcAddress;
        oathErnPath[2] = wantAddress;
        wrappedProxy.updateVeloSwapPath(oathAddress, wantAddress, oathErnPath);

        address[] memory oathUsdcPath = new address[](2);
        oathUsdcPath[0] = oathAddress;
        oathUsdcPath[1] = usdcAddress;
        wrappedProxy.updateVeloSwapPath(oathAddress, usdcAddress, oathUsdcPath);

        address[] memory wethUsdcPath = new address[](2);
        wethUsdcPath[0] = wethAddress;
        wethUsdcPath[1] = usdcAddress;
        wrappedProxy.updateUniV3SwapPath(wethAddress, usdcAddress, wethUsdcPath);

        address[] memory wbtcUsdcPath = new address[](3);
        wbtcUsdcPath[0] = wbtcAddress;
        wbtcUsdcPath[1] = wethAddress;
        wbtcUsdcPath[2] = usdcAddress;
        wrappedProxy.updateUniV3SwapPath(wbtcAddress, usdcAddress, wbtcUsdcPath);

        address[] memory opUsdcPath = new address[](3);
        opUsdcPath[0] = opAddress;
        opUsdcPath[1] = wethAddress;
        opUsdcPath[2] = usdcAddress;
        wrappedProxy.updateUniV3SwapPath(opAddress, usdcAddress, opUsdcPath);

        // address[] memory usdcErnPath = new address[](2);
        // usdcErnPath[0] = usdcAddress;
        // usdcErnPath[1] = wantAddress;
        // wrappedProxy.updateUniV3SwapPath(usdcAddress, wantAddress, usdcErnPath);
        // wrappedProxy.updateVeloSwapPath(usdcAddress, wantAddress, usdcErnPath);

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

        wrappedProxy.updateUsdcMinAmountOutBPS(9950);
        wrappedProxy.updateErnMinAmountOutBPS(9950);

        ReaperStrategyStabilityPool.Exchange currentExchange = ReaperStrategyStabilityPool.Exchange.Velodrome;
        wrappedProxy.setUsdcToErnExchange(currentExchange);

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

    function testSharePriceChanges() public {
        uint256 sharePrice1 = vault.getPricePerFullShare();
        uint256 timeToSkip = 360000;
        uint256 wantBalance = want.balanceOf(wantHolderAddr);
        vm.prank(wantHolderAddr);
        vault.deposit(wantBalance);
        uint256 sharePrice2 = vault.getPricePerFullShare();
        vm.prank(keepers[0]);
        wrappedProxy.harvest();
        skip(timeToSkip);
        uint256 sharePrice3 = vault.getPricePerFullShare();

        address wethAggregator = IPriceFeed(priceFeedAddress).priceAggregator(wethAddress);
        console.log("wethAggregator: ", wethAggregator);

        MockAggregator mockChainlink = new MockAggregator();
        mockChainlink.setPrevRoundId(2);
        mockChainlink.setLatestRoundId(3);
        mockChainlink.setPrice(1500 * 10 ** 8);
        mockChainlink.setPrevPrice(1500 * 10 ** 8);
        mockChainlink.setUpdateTime(block.timestamp);

        MockAggregator mockChainlink2 = new MockAggregator();
        mockChainlink2.setPrevRoundId(2);
        mockChainlink2.setLatestRoundId(3);
        mockChainlink2.setPrice(22_000 * 10 ** 8);
        mockChainlink2.setPrevPrice(22_000 * 10 ** 8);
        mockChainlink2.setUpdateTime(block.timestamp);

        vm.startPrank(priceFeedOwnerAddress);
        // IPriceFeed(priceFeedAddress).updateChainlinkAggregator(wethAddress, address(mockChainlink));
        IPriceFeed(priceFeedAddress).updateChainlinkAggregator(wbtcAddress, address(mockChainlink2));
        vm.stopPrank();

        uint256 rewardTokenGain = IStabilityPool(stabilityPoolAddress).getDepositorLQTYGain(address(wrappedProxy));

        liquidateTroves(wbtcAddress);
        // liquidateTroves(wethAddress);

        wrappedProxy.harvest();
        skip(timeToSkip);
        uint256 sharePrice4 = vault.getPricePerFullShare();

        wrappedProxy.getERNValueOfCollateralGain();

        console.log("sharePrice1: ", sharePrice1);
        console.log("sharePrice2: ", sharePrice2);
        console.log("sharePrice3: ", sharePrice3);
        console.log("sharePrice4: ", sharePrice4);
        assertGt(sharePrice4, sharePrice1);
    }

    function testVeloTWAP() public {
        console.log("testVeloTWAP");
        uint256 iterations = 20;
        IVelodromePair pool = IVelodromePair(veloUsdcErnPool);
        uint256 currentPrice = pool.current(address(want), 1 ether);
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
        IVeloRouter.route[] memory routes = new IVeloRouter.route[](1);
        routes[0] = IVeloRouter.route({from: usdcAddress, to: wantAddress, stable: true});
        vm.startPrank(dumpourBob);
        IERC20(usdcAddress).approve(veloRouter, usdcToDump);
        uint256 minAmountOut = 0;
        router.swapExactTokensForTokens(usdcToDump - usdcUnit, minAmountOut, routes, dumpourBob, block.timestamp);

        uint256 timeToSkip = 60 * 30;
        skip(timeToSkip);
        router.swapExactTokensForTokens(usdcUnit, minAmountOut, routes, dumpourBob, block.timestamp);

        uint256 dumpedPrice = pool.current(address(want), 1 ether);
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
        uint256 priceQuote = pool.quote(usdcAddress, usdcAmount, granularity);
        console.log("priceQuote: ", priceQuote);
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
        int256 wbtcPrice = wbtcAggregator.latestAnswer();
        int256 wethPrice = wethAggregator.latestAnswer();
        int256 opPrice = opAggregator.latestAnswer();
        console.log("wbtcPrice: ");
        console.logInt(wbtcPrice);
        console.log("wethPrice: ");
        console.logInt(wethPrice);
        console.log("opPrice: ");
        console.logInt(opPrice);

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

        uint256 usdcPrice = uint256(usdcAggregator.latestAnswer());
        console.log("usdcPrice: ", usdcPrice);

        // uint256 scaledUsdValueInCollateral = ;
        uint256 usdcAmount = ((usdValueInCollateral / (10 ** 12)) * (10 ** 8)) / usdcPrice;
        console.log("usdcAmount: ", usdcAmount);

        // IVelodromePair pool = IVelodromePair(veloUsdcErnPool);
        // uint256 granularity = wrappedProxy.veloUsdcErnQuoteGranularity();
        uint256 ernAmount =
            IVelodromePair(veloUsdcErnPool).quote(usdcAddress, usdcAmount, wrappedProxy.veloUsdcErnQuoteGranularity());
        uint256 wantValueInCollateral = wrappedProxy.getERNValueOfCollateralGain();

        console.log("ernAmount: ", ernAmount);
        console.log("wantValueInCollateral: ", wantValueInCollateral);
        assertEq(ernAmount, wantValueInCollateral);

        uint256 compoundingFeeMarginBPS = wrappedProxy.compoundingFeeMarginBPS();
        uint256 expectedPoolIncrease = ernAmount * compoundingFeeMarginBPS / BPS_UNIT;
        //console.log("poolBalanceIncrease: ", poolBalanceAfter - poolBalanceBefore);
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

    function testVeloTWAPQuoteAmounts() public {
        uint256 usdcUnit = 10 ** 6;

        IVelodromePair pool = IVelodromePair(veloUsdcErnPool);
        uint256 granularity = wrappedProxy.veloUsdcErnQuoteGranularity();

        uint256 priceQuote1 = pool.quote(usdcAddress, usdcUnit, granularity);
        uint256 priceQuote2 = pool.quote(usdcAddress, usdcUnit * 10, granularity);
        uint256 priceQuote3 = pool.quote(usdcAddress, usdcUnit * 100, granularity);
        uint256 priceQuote4 = pool.quote(usdcAddress, usdcUnit * 1000, granularity);
        uint256 priceQuote5 = pool.quote(usdcAddress, usdcUnit * 10_000, granularity);
        uint256 priceQuote6 = pool.quote(usdcAddress, usdcUnit * 100_000, granularity);
        uint256 priceQuote7 = pool.quote(usdcAddress, usdcUnit * 1_000_000, granularity);
        uint256 priceQuote8 = pool.quote(usdcAddress, usdcUnit * 10_000_000, granularity);
        uint256 priceQuote9 = pool.quote(usdcAddress, usdcUnit * 100_000_000, granularity);
        uint256 priceQuote10 = pool.quote(usdcAddress, usdcUnit * 1_000_000_000, granularity);
        console.log("priceQuote1: ", priceQuote1);
        console.log("priceQuote2: ", priceQuote2 / 10);
        console.log("priceQuote3: ", priceQuote3 / 100);
        console.log("priceQuote4: ", priceQuote4 / 1000);
        console.log("priceQuote5: ", priceQuote5 / 10_000);
        console.log("priceQuote6: ", priceQuote6 / 100_000);
        console.log("priceQuote7: ", priceQuote7 / 1_000_000);
        console.log("priceQuote8: ", priceQuote8 / 10_000_000);
        console.log("priceQuote9: ", priceQuote9 / 100_000_000);
        console.log("priceQuote10: ", priceQuote10 / 1_000_000_000);
    }

    function liquidateTroves(address asset) internal {
        ITroveManager(troveManager).liquidateTroves(asset, 100);
    }

    function _toWant(uint256 amount) internal returns (uint256) {
        return amount * (10 ** want.decimals());
    }
}
