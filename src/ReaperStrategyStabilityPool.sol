// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import {ReaperBaseStrategyv4} from "vault-v2/ReaperBaseStrategyv4.sol";
import {IStabilityPool} from "./interfaces/IStabilityPool.sol";
import {IPriceFeed} from "./interfaces/IPriceFeed.sol";
import {IVault} from "vault-v2/interfaces/IVault.sol";
import {ICollateralConfig} from "./interfaces/ICollateralConfig.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {VeloSolidMixin} from "mixins/VeloSolidMixin.sol";
import {UniV3Mixin} from "mixins/UniV3Mixin.sol";
import {BalMixin} from "mixins/BalMixin.sol";
import {IERC20MetadataUpgradeable} from "oz-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {SafeERC20Upgradeable} from "oz-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {MathUpgradeable} from "oz-upgradeable/utils/math/MathUpgradeable.sol";

/**
 * @dev Strategy to _compound rewards and liquidation collateral gains in the Ethos stability pool
 */
contract ReaperStrategyStabilityPool is ReaperBaseStrategyv4, VeloSolidMixin, UniV3Mixin, BalMixin {
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;

    // 3rd-party contract addresses
    IStabilityPool public stabilityPool;
    IPriceFeed public priceFeed;
    IERC20MetadataUpgradeable public oath;
    IERC20MetadataUpgradeable public usdc;
    ExchangeSettings public exchangeSettings;
    AggregatorV3Interface public chainlinkUsdcOracle;

    uint256 public constant ETHOS_PRICE_PRECISION = 1 ether;
    uint256 public constant ETHOS_DECIMALS = 18;
    uint256 public minAmountOutBPS;
    uint256 public ernMinAmountOutBPS;

    enum Exchange {
        Velodrome,
        Beethoven,
        UniV3
    }

    Exchange public usdcToErnExchange;

    struct ExchangeSettings {
        address veloRouter;
        address balVault;
        address uniV3Router;
        address uniV3Quoter;
    }

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address[] memory _strategists,
        address[] memory _multisigRoles,
        address[] memory _keepers,
        address _want,
        address _stabilityPool,
        address _priceFeed,
        address _oath,
        address _usdc,
        bytes32 _balErnPoolID,
        ExchangeSettings calldata _exchangeSettings,
        address _chainlinkUsdcOracle
    ) public initializer {
        require(_vault != address(0), "vault is 0 address");
        require(_want != address(0), "want is 0 address");
        require(_stabilityPool != address(0), "stabilityPool is 0 address");
        require(_priceFeed != address(0), "priceFeed is 0 address");
        require(_oath != address(0), "oath is 0 address");
        require(_usdc != address(0), "usdc is 0 address");
        require(_exchangeSettings.veloRouter != address(0), "veloRouter is 0 address");
        require(_exchangeSettings.balVault != address(0), "balVault is 0 address");
        require(_exchangeSettings.uniV3Router != address(0), "uniV3Router is 0 address");
        require(_exchangeSettings.uniV3Quoter != address(0), "uniV3Quoter is 0 address");
        require(_strategists.length != 0, "no strategists");
        require(_multisigRoles.length == 3, "invalid amount of multisig roles");
        __ReaperBaseStrategy_init(_vault, _want, _strategists, _multisigRoles, _keepers);
        stabilityPool = IStabilityPool(_stabilityPool);
        priceFeed = IPriceFeed(_priceFeed);
        oath = IERC20MetadataUpgradeable(_oath);
        usdc = IERC20MetadataUpgradeable(_usdc);
        exchangeSettings = _exchangeSettings;

        minAmountOutBPS = 9900;
        ernMinAmountOutBPS = 9200;
        usdcToErnExchange = Exchange.Velodrome;

        address[] memory usdcErnPath = new address[](2);
        usdcErnPath[0] = _usdc;
        usdcErnPath[1] = _want;
        veloSwapPaths[_usdc][_want] = usdcErnPath;
        uniV3SwapPaths[_usdc][_want] = usdcErnPath;
        balSwapPoolIDs[_usdc][_want] = _balErnPoolID;
        chainlinkUsdcOracle = AggregatorV3Interface(_chainlinkUsdcOracle);
    }

    function _adjustPosition(uint256 _debt) internal override {
        if (emergencyExit) {
            return;
        }

        uint256 wantBalance = balanceOfWant();
        if (wantBalance > _debt) {
            uint256 toReinvest = wantBalance - _debt;
            _deposit(toReinvest);
        }
    }

    function _liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 liquidatedAmount, uint256 loss)
    {
        uint256 wantBal = balanceOfWant();
        if (wantBal < _amountNeeded) {
            _withdraw(_amountNeeded - wantBal);
            liquidatedAmount = balanceOfWant();
        } else {
            liquidatedAmount = _amountNeeded;
        }

        if (_amountNeeded > liquidatedAmount) {
            loss = _amountNeeded - liquidatedAmount;
        }
    }

    function _liquidateAllPositions() internal override returns (uint256 amountFreed) {
        _withdraw(type(uint256).max);
        _compound();
        return balanceOfWant();
    }

    /**
     * @dev Core function of the strat, in charge of collecting and swapping rewards + collateral
     *      to produce more want.
     */
    function _harvestCore(uint256 _debt) internal override returns (int256 roi, uint256 repayment) {
        _claimRewards();
        _compound();

        uint256 allocated = IVault(vault).strategies(address(this)).allocated;
        uint256 totalAssets = balanceOf();
        uint256 toFree = MathUpgradeable.min(_debt, totalAssets);

        if (totalAssets > allocated) {
            uint256 profit = totalAssets - allocated;
            toFree += profit;
            roi = int256(profit);
        } else if (totalAssets < allocated) {
            roi = -int256(allocated - totalAssets);
        }

        (uint256 amountFreed, uint256 loss) = _liquidatePosition(toFree);
        repayment = MathUpgradeable.min(_debt, amountFreed);
        roi -= int256(loss);
    }

    function _compound() internal {
        ICollateralConfig collateralConfig = stabilityPool.collateralConfig();
        address[] memory assets = collateralConfig.getAllowedCollaterals();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];

            uint256 collateralBalance = IERC20MetadataUpgradeable(asset).balanceOf(address(this));
            if (collateralBalance != 0) {
                uint256 assetValue = _getUSDEquivalentOfCollateral(asset, collateralBalance);
                uint256 assetValueUsdc = assetValue * _getUsdcPrice() / (10 ** _getUsdcDecimals());
                uint256 minAmountOut = (assetValueUsdc * minAmountOutBPS) / PERCENT_DIVISOR;
                uint256 scaledMinAmountOut = _getScaledToCollAmount(minAmountOut, usdc.decimals());
                _swapUniV3(asset, address(usdc), collateralBalance, scaledMinAmountOut, exchangeSettings.uniV3Router, exchangeSettings.uniV3Quoter);
            }
        }

        uint256 oathBalance = oath.balanceOf(address(this));
        if (oathBalance != 0) {
            _swapVelo(address(oath), address(usdc), oathBalance, 0, exchangeSettings.veloRouter);
        }

        uint256 usdcBalance = usdc.balanceOf(address(this));
        if (usdcBalance != 0) {
            // assumes 1 ERN = 1 USDC
            uint256 scaledUsdcBalance = _getScaledFromCollAmount(usdcBalance, usdc.decimals());
            uint256 minAmountOut = (scaledUsdcBalance * ernMinAmountOutBPS) / PERCENT_DIVISOR;
            if (usdcToErnExchange == Exchange.Beethoven) {
                _swapBal(address(usdc), want, usdcBalance, minAmountOut);
            } else if (usdcToErnExchange == Exchange.Velodrome) {
                _swapVelo(address(usdc), want, usdcBalance, minAmountOut, exchangeSettings.veloRouter);
            } else if (usdcToErnExchange == Exchange.UniV3) {
                _swapUniV3(address(usdc), want, usdcBalance, minAmountOut, exchangeSettings.uniV3Router, exchangeSettings.uniV3Quoter);
            }
        }
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * !audit we increase the allowance in the balance amount but we deposit the amount specified
     */
    function _deposit(uint256 toReinvest) internal {
        if (toReinvest != 0) {
            stabilityPool.provideToSP(toReinvest);
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal {
        if (_hasInitialDeposit(address(this))) {
            stabilityPool.withdrawFromSP(_amount);
        }
    }

    /**
     * @dev Claim rewards for supply and borrow
     */
    function _claimRewards() internal {
        _withdraw(0);
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     * It takes into account both the funds in hand, the funds in the stability pool,
     * and also balance of collateral tokens.
     */
    function balanceOf() public view override returns (uint256) {
        return balanceOfPool() + balanceOfWant();
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20MetadataUpgradeable(want).balanceOf(address(this));
    }

    function balanceOfPool() public view returns (uint256) {
        uint256 lusdValue = stabilityPool.getCompoundedLUSDDeposit(address(this));
        uint256 collateralValue = getCollateralGain();
        // assumes 1 ERN = 1 USD
        return lusdValue + collateralValue;
    }

    function getCollateralGain() public view returns (uint256 collateralGain) {
        (address[] memory assets, uint256[] memory amounts) = stabilityPool.getDepositorCollateralGain(address(this));

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 amount = amounts[i] + IERC20MetadataUpgradeable(asset).balanceOf(address(this));
            collateralGain += _getUSDEquivalentOfCollateral(asset, amount);
        }
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 usdcValue = _getUSDEquivalentOfUsdc(usdcBalance);

        collateralGain += usdcValue;
    }

    // Returns USD equivalent of {_amount} of {_collateral} with 18 digits of decimal precision.
    // The precision of {_amount} is whatever {_collateral}'s native decimals are (ex. 8 for wBTC)
    function _getUSDEquivalentOfCollateral(address _collateral, uint256 _amount) internal view returns (uint256) {
        uint256 scaledAmount = _getScaledFromCollAmount(_amount, IERC20MetadataUpgradeable(_collateral).decimals());
        uint256 price = _getCollateralPrice(_collateral);
        uint256 USDAssetValue = (scaledAmount * price) / (10 ** _getCollateralDecimals(_collateral));
        return USDAssetValue;
    }

    function _getUSDEquivalentOfUsdc(uint256 _amount) internal view returns (uint256) {
        uint256 scaledAmount = _getScaledFromCollAmount(_amount, usdc.decimals());
        uint256 price = _getUsdcPrice();
        uint256 USDAssetValue = (scaledAmount * price) / (10 ** _getUsdcDecimals());
        return USDAssetValue;
    }

    function _balVault() internal view override returns (address) {
        return exchangeSettings.balVault;
    }

    function _hasInitialDeposit(address _user) internal view returns (bool) {
        return stabilityPool.deposits(_user).initialValue != 0;
    }

    function _getUsdcPrice() internal view returns (uint256 price) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(chainlinkUsdcOracle);
        price = uint256(aggregator.latestAnswer());
    }

    function _getUsdcDecimals() internal view returns (uint256 decimals) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(chainlinkUsdcOracle);
        decimals = uint256(aggregator.decimals());
    }

    function _getCollateralPrice(address _collateral) internal view returns (uint256 price) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(priceFeed.priceAggregator(_collateral));
        price = uint256(aggregator.latestAnswer());
    }

    function _getCollateralDecimals(address _collateral) internal view returns (uint256 decimals) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(priceFeed.priceAggregator(_collateral));
        decimals = uint256(aggregator.decimals());
    }

    function _getScaledFromCollAmount(uint256 _collAmount, uint256 _collDecimals)
        internal
        pure
        returns (uint256 scaledColl)
    {
        scaledColl = _collAmount;
        if (_collDecimals > ETHOS_DECIMALS) {
            scaledColl = scaledColl / (10 ** (_collDecimals - ETHOS_DECIMALS));
        } else if (_collDecimals < ETHOS_DECIMALS) {
            scaledColl = scaledColl * (10 ** (ETHOS_DECIMALS - _collDecimals));
        }
    }

    function _getScaledToCollAmount(uint256 _collAmount, uint256 _collDecimals)
        internal
        pure
        returns (uint256 scaledColl)
    {
        scaledColl = _collAmount;
        if (_collDecimals > ETHOS_DECIMALS) {
            scaledColl = scaledColl * (10 ** (_collDecimals - ETHOS_DECIMALS));
        } else if (_collDecimals < ETHOS_DECIMALS) {
            scaledColl = scaledColl / (10 ** (ETHOS_DECIMALS - _collDecimals));
        }
    }

    function updateVeloSwapPath(address _tokenIn, address _tokenOut, address[] calldata _path) external override {
        _atLeastRole(STRATEGIST);
        _updateVeloSwapPath(_tokenIn, _tokenOut, _path);
    }

    function updateUniV3SwapPath(address _tokenIn, address _tokenOut, address[] calldata _path) external override {
        _atLeastRole(STRATEGIST);
        _updateUniV3SwapPath(_tokenIn, _tokenOut, _path);
    }

    function updateBalSwapPoolID(address _tokenIn, address _tokenOut, bytes32 _poolID) external override {
        _atLeastRole(STRATEGIST);
        _updateBalSwapPoolID(_tokenIn, _tokenOut, _poolID);
    }

    function updateMinAmountOutBPS(uint256 _minAmountOutBPS) external {
        _atLeastRole(STRATEGIST);
        require(_minAmountOutBPS > 8000 && _minAmountOutBPS < PERCENT_DIVISOR, "Invalid slippage value");
        minAmountOutBPS = _minAmountOutBPS;
    }

    function updateErnMinAmountOutBPS(uint256 _ernMinAmountOutBPS) external {
        _atLeastRole(STRATEGIST);
        require(_ernMinAmountOutBPS > 8000 && _ernMinAmountOutBPS < PERCENT_DIVISOR, "Invalid slippage value");
        ernMinAmountOutBPS = _ernMinAmountOutBPS;
    }

    function setUsdcToErnExchange(Exchange _exchange) external {
        _atLeastRole(STRATEGIST);
        usdcToErnExchange = _exchange;
    }

    function _getFeeCandidates() internal override returns (uint24[] memory) {
        uint24[] memory feeCandidates = new uint24[](2);
        feeCandidates[0] = 500;
        feeCandidates[1] = 3_000;
        return feeCandidates;
    }
}
