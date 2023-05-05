// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/ReaperStrategyStabilityPool.sol";
import "vault-v2/ReaperVaultV2.sol";
import "mixins/interfaces/IVeloRouter.sol";
import "src/mocks/MockAggregator.sol";
import "src/interfaces/ITroveManager.sol";
import "src/interfaces/IStabilityPool.sol";
import "src/interfaces/IVelodromePair.sol";
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
        optimismFork = vm.createSelectFork("https://opt-mainnet.g.alchemy.com/v2/demo", 96499629);
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

        wrappedProxy.initialize(
            address(vault),
            strategists,
            multisigRoles,
            keepers,
            wantAddress,
            priceFeedAddress,
            oathAddress,
            usdcAddress,
            balErnPoolId,
            exchangeSettings,
            chainlinkUsdcOracle,
            pools
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

        wrappedProxy.updateMinAmountOutBPS(9950);
        wrappedProxy.updateErnMinAmountOutBPS(9950);

        ReaperStrategyStabilityPool.Exchange currentExchange = ReaperStrategyStabilityPool.Exchange.Velodrome;
        wrappedProxy.setUsdcToErnExchange(currentExchange);
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

        wrappedProxy.getCollateralGain();

        console.log("sharePrice1: ", sharePrice1);
        console.log("sharePrice2: ", sharePrice2);
        console.log("sharePrice3: ", sharePrice3);
        console.log("sharePrice4: ", sharePrice4);
        assertGt(sharePrice4, sharePrice1);
    }

    function testVeloTWAP() public {
        console.log("testVeloTWAP");
        IVelodromePair pool = IVelodromePair(veloUsdcErnPool);
        uint256 currentPrice = pool.current(address(want), 1 ether);
        console.log("currentPrice: ", currentPrice);
        uint256 currentPriceQuote1 = pool.quote(address(want), 1 ether, 1);
        console.log("currentPriceQuote1: ", currentPriceQuote1);
        uint256 currentPriceQuote2 = pool.quote(address(want), 1 ether, 2);
        console.log("currentPriceQuote2: ", currentPriceQuote2);
        uint256 currentPriceQuote3 = pool.quote(address(want), 1 ether, 3);
        console.log("currentPriceQuote3: ", currentPriceQuote3);
        uint256 currentPriceQuote4 = pool.quote(address(want), 1 ether, 4);
        console.log("currentPriceQuote4: ", currentPriceQuote4);
        uint256 currentPriceQuote5 = pool.quote(address(want), 1 ether, 5);
        console.log("currentPriceQuote5: ", currentPriceQuote5);

        address dumpourBob = makeAddr("bob");
        uint256 usdcUnit = 10 ** 6;
        uint256 usdcToDump = 4_000_000 * usdcUnit;
        deal({token: usdcAddress, to: dumpourBob, give: usdcToDump});

        IVeloRouter router = IVeloRouter(veloRouter);
        IVeloRouter.route[] memory routes = new IVeloRouter.route[](1);
        routes[0] = IVeloRouter.route({ from: usdcAddress, to: wantAddress, stable: true });
        vm.startPrank(dumpourBob);
        IERC20(usdcAddress).approve(veloRouter, usdcToDump);
        uint256 minAmountOut = 0;
        router.swapExactTokensForTokens(usdcToDump - usdcUnit, minAmountOut, routes, dumpourBob, block.timestamp);

        uint256 timeToSkip = 60 * 30;
        skip(timeToSkip);
        router.swapExactTokensForTokens(usdcUnit, minAmountOut, routes, dumpourBob, block.timestamp);
        
        uint256 dumpedPrice = pool.current(address(want), 1 ether);
        console.log("dumpedPrice: ", dumpedPrice);
        uint256 dumpedPriceQuote = pool.quote(address(want), 1 ether, 1);
        console.log("dumpedPriceQuote1: ", dumpedPriceQuote);
        dumpedPriceQuote = pool.quote(address(want), 1 ether, 2);
        console.log("dumpedPriceQuote2: ", dumpedPriceQuote);
        dumpedPriceQuote = pool.quote(address(want), 1 ether, 3);
        console.log("dumpedPriceQuote3: ", dumpedPriceQuote);
        dumpedPriceQuote = pool.quote(address(want), 1 ether, 4);
        console.log("dumpedPriceQuote4: ", dumpedPriceQuote);
        dumpedPriceQuote = pool.quote(address(want), 1 ether, 5);
        console.log("dumpedPriceQuote5: ", dumpedPriceQuote);
    }

    function liquidateTroves(address asset) internal {
        ITroveManager(troveManager).liquidateTroves(asset, 100);
    }

    function _toWant(uint256 amount) internal returns (uint256) {
        return amount * (10 ** want.decimals());
    }
}
