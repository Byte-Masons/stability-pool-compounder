// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import {ReaperBaseStrategyv4} from "vault-v2/ReaperBaseStrategyv4.sol";
import {IStabilityPool} from "./interfaces/IStabilityPool.sol";
import {IPriceFeed} from "./interfaces/IPriceFeed.sol";
import {IVault} from "vault-v2/interfaces/IVault.sol";
import {ICollateralConfig} from "./interfaces/ICollateralConfig.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IVelodromePair} from "./interfaces/IVelodromePair.sol";
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
    IVelodromePair public veloUsdcErnPool;

    uint256 public constant ETHOS_DECIMALS = 18;
    uint256 public minAmountOutBPS;
    uint256 public ernMinAmountOutBPS;
    uint256 public collateralValueAdjustmentBPS;
    uint256 public veloUsdcErnQuoteGranularity;

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

    struct Pools {
        address stabilityPool;
        address veloUsdcErnPool;
    }

    struct Tokens {
        address want;
        address oath;
        address usdc;
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
        address _priceFeed,
        bytes32 _balErnPoolID,
        address _chainlinkUsdcOracle,
        ExchangeSettings calldata _exchangeSettings,
        Pools calldata _pools,
        address[] calldata _usdcErnPath,
        Tokens calldata _tokens
    ) public initializer {
        require(_vault != address(0), "vault is 0 address");
        require(_strategists.length != 0, "no strategists");
        require(_multisigRoles.length == 3, "invalid amount of multisig roles");
        require(_tokens.want != address(0), "want is 0 address");
        require(_priceFeed != address(0), "priceFeed is 0 address");
        require(_tokens.oath != address(0), "oath is 0 address");
        require(_tokens.usdc != address(0), "usdc is 0 address");
        require(_chainlinkUsdcOracle != address(0), "chainlinkUsdcOracle is 0 address");
        require(_exchangeSettings.veloRouter != address(0), "veloRouter is 0 address");
        require(_exchangeSettings.balVault != address(0), "balVault is 0 address");
        require(_exchangeSettings.uniV3Router != address(0), "uniV3Router is 0 address");
        require(_exchangeSettings.uniV3Quoter != address(0), "uniV3Quoter is 0 address");
        require(_pools.stabilityPool != address(0), "stabilityPool is 0 address");
        require(_pools.veloUsdcErnPool != address(0), "veloUsdcErnPool is 0 address");

        __ReaperBaseStrategy_init(_vault, _tokens.want, _strategists, _multisigRoles, _keepers);
        stabilityPool = IStabilityPool(_pools.stabilityPool);
        priceFeed = IPriceFeed(_priceFeed);
        oath = IERC20MetadataUpgradeable(_tokens.oath);
        usdc = IERC20MetadataUpgradeable(_tokens.usdc);
        exchangeSettings = _exchangeSettings;

        minAmountOutBPS = 9800;
        ernMinAmountOutBPS = 9800;
        usdcToErnExchange = Exchange.Velodrome;

        _updateVeloSwapPath(_tokens.usdc, _tokens.want, _usdcErnPath);
        _updateUniV3SwapPath(_tokens.usdc, _tokens.want, _usdcErnPath);
        _updateBalSwapPoolID(_tokens.usdc, _tokens.want, _balErnPoolID);

        chainlinkUsdcOracle = AggregatorV3Interface(_chainlinkUsdcOracle);
        veloUsdcErnPool = IVelodromePair(_pools.veloUsdcErnPool);
        veloUsdcErnQuoteGranularity = 2;
        collateralValueAdjustmentBPS = 9800;
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

    /**
     * @dev Takes collateral earned from liquidations (could be WBTC, WETH, OP) and compounds it.
     * Will also take Oath incentive rewards and compound. The collateral will be priced by Ethos
     * Chainlink oracles for slippage control. USDC as an intermediary is priced using a separate
     * oracle. Oath is not priced so any slippage is allowed.
     * ERN is priced using the built in Velodrome TWAP.
     */
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
                _swapUniV3(
                    asset,
                    address(usdc),
                    collateralBalance,
                    scaledMinAmountOut,
                    exchangeSettings.uniV3Router,
                    exchangeSettings.uniV3Quoter
                );
            }
        }

        uint256 oathBalance = oath.balanceOf(address(this));
        if (oathBalance != 0) {
            _swapVelo(address(oath), address(usdc), oathBalance, 0, exchangeSettings.veloRouter);
        }

        uint256 usdcBalance = usdc.balanceOf(address(this));
        if (usdcBalance != 0) {
            uint256 expectedErnAmount = veloUsdcErnPool.quote(address(usdc), usdcBalance, veloUsdcErnQuoteGranularity);
            uint256 minAmountOut = (expectedErnAmount * ernMinAmountOutBPS) / PERCENT_DIVISOR;
            if (usdcToErnExchange == Exchange.Beethoven) {
                _swapBal(address(usdc), want, usdcBalance, minAmountOut);
            } else if (usdcToErnExchange == Exchange.Velodrome) {
                _swapVelo(address(usdc), want, usdcBalance, minAmountOut, exchangeSettings.veloRouter);
            } else if (usdcToErnExchange == Exchange.UniV3) {
                _swapUniV3(
                    address(usdc),
                    want,
                    usdcBalance,
                    minAmountOut,
                    exchangeSettings.uniV3Router,
                    exchangeSettings.uniV3Quoter
                );
            }
        }
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract
     * or when funds are reinvested in to the strategy.
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
     * @dev Claim rewards
     */
    function _claimRewards() internal {
        _withdraw(0);
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     * It takes into account both the funds in hand, the funds in the stability pool,
     * and also the balance of collateral tokens + USDC.
     */
    function balanceOf() public view override returns (uint256) {
        return balanceOfPool() + balanceOfWant();
    }

    /**
     * @dev The want balance directly held in the strategy itself.
     */
    function balanceOfWant() public view returns (uint256) {
        return IERC20MetadataUpgradeable(want).balanceOf(address(this));
    }

    /**
     * @dev Estimates the amount of want held in the stability pool and any
     * balance of collateral or USDC. The values are converted using oracles and
     * the Velodrome USDC-ERN TWAP and collateral+USDC value discounted slightly.
     */
    function balanceOfPool() public view returns (uint256) {
        uint256 lusdValue = stabilityPool.getCompoundedLUSDDeposit(address(this));
        uint256 collateralValue = getWantValueInCollateral();
        uint256 adjustedCollateralValue = collateralValue * collateralValueAdjustmentBPS / PERCENT_DIVISOR;

        return lusdValue + adjustedCollateralValue;
    }

    /**
     * @dev Calculates the estimated want value of collateral and USDC using Chainlink oracles
     * and the Velodrome USDC-ERN TWAP.
     */
    function getWantValueInCollateral() public view returns (uint256 wantValueInCollateral) {
        uint256 usdValueOfCollateral = getUsdValueInCollateral();
        uint256 usdcValueOfCollateral = _getUsdcEquivalentOfUSD(usdValueOfCollateral);
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 totalUsdcValue = usdcBalance + usdcValueOfCollateral;
        wantValueInCollateral = veloUsdcErnPool.quote(address(usdc), totalUsdcValue, veloUsdcErnQuoteGranularity);
    }

    function getUsdValueInCollateral() public view returns (uint256 usdValueOfCollateral) {
        (address[] memory assets, uint256[] memory amounts) = stabilityPool.getDepositorCollateralGain(address(this));
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 amount = amounts[i] + IERC20MetadataUpgradeable(asset).balanceOf(address(this));
            usdValueOfCollateral += _getUSDEquivalentOfCollateral(asset, amount);
        }
    }

    /**
     * @dev Returns USD equivalent of {_amount} of {_collateral} with 18 digits of decimal precision.
     * The precision of {_amount} is whatever {_collateral}'s native decimals are (ex. 8 for wBTC)
     */
    function _getUSDEquivalentOfCollateral(address _collateral, uint256 _amount) internal view returns (uint256) {
        uint256 scaledAmount = _getScaledFromCollAmount(_amount, IERC20MetadataUpgradeable(_collateral).decimals());
        uint256 price = _getCollateralPrice(_collateral);
        uint256 USDAssetValue = (scaledAmount * price) / (10 ** _getCollateralDecimals(_collateral));
        return USDAssetValue;
    }

    /**
     * @dev Returns Usdc equivalent of {_amount} of USD with 6 digits of decimal precision.
     * The precision of {_amount} is 18 decimals
     */
    function _getUsdcEquivalentOfUSD(uint256 _amount) internal view returns (uint256) {
        uint256 scaledAmount = _getScaledToCollAmount(_amount, usdc.decimals());
        uint256 price = _getUsdcPrice();
        uint256 usdcAmount = (scaledAmount * (10 ** _getUsdcDecimals())) / price;
        return usdcAmount;
    }

    /**
     * @dev Returns the address of the Balancer/BeetX vault used by the Balancer mixin
     */
    function _balVault() internal view override returns (address) {
        return exchangeSettings.balVault;
    }

    /**
     * @dev Check to ensure an initial deposit has been made in the stability pool
     * Which is a requirement to call withdraw.
     */
    function _hasInitialDeposit(address _user) internal view returns (bool) {
        return stabilityPool.deposits(_user).initialValue != 0;
    }

    /**
     * @dev Returns the price of USDC in USD in whatever decimals the aggregator uses (usually 8)
     */
    function _getUsdcPrice() internal view returns (uint256 price) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(chainlinkUsdcOracle);
        price = uint256(aggregator.latestAnswer());
    }

    /**
     * @dev Returns the decimals the aggregator uses for USDC (usually 8)
     */
    function _getUsdcDecimals() internal view returns (uint256 decimals) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(chainlinkUsdcOracle);
        decimals = uint256(aggregator.decimals());
    }

    /**
     * @dev Returns the price of {_collateral} in USD in whatever decimals the aggregator uses (usually 8)
     */
    function _getCollateralPrice(address _collateral) internal view returns (uint256 price) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(priceFeed.priceAggregator(_collateral));
        price = uint256(aggregator.latestAnswer());
    }

    /**
     * @dev Returns the decimals the aggregator uses for {_collateral} (usually 8)
     */
    function _getCollateralDecimals(address _collateral) internal view returns (uint256 decimals) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(priceFeed.priceAggregator(_collateral));
        decimals = uint256(aggregator.decimals());
    }

    /**
     * @dev Scales {_collAmount} given in {_collDecimals} to an 18 decimal amount
     */
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

    /**
     * @dev Scales {_collAmount} given in 18 decimals to an amount in {_collDecimals}
     */
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

    /**
     * @dev Updates the Velodrome swap path to go from {_tokenIn} to {_tokenOut}
     */
    function updateVeloSwapPath(address _tokenIn, address _tokenOut, address[] calldata _path) external override {
        _atLeastRole(STRATEGIST);
        _updateVeloSwapPath(_tokenIn, _tokenOut, _path);
    }

    /**
     * @dev Updates the UniV3 swap path to go from {_tokenIn} to {_tokenOut}
     */
    function updateUniV3SwapPath(address _tokenIn, address _tokenOut, address[] calldata _path) external override {
        _atLeastRole(STRATEGIST);
        _updateUniV3SwapPath(_tokenIn, _tokenOut, _path);
    }

    /**
     * @dev Updates the Balancer/BeetX pool used to go from {_tokenIn} to {_tokenOut}
     */
    function updateBalSwapPoolID(address _tokenIn, address _tokenOut, bytes32 _poolID) external override {
        _atLeastRole(STRATEGIST);
        _updateBalSwapPoolID(_tokenIn, _tokenOut, _poolID);
    }

    /**
     * @dev Updates the {minAmountOutBPS} which is the minimum amount accepted in a collateral swap in BPS
     * So 9500 would allow a 5% slippage.
     */
    function updateMinAmountOutBPS(uint256 _minAmountOutBPS) external {
        _atLeastRole(STRATEGIST);
        require(_minAmountOutBPS > 8000 && _minAmountOutBPS < PERCENT_DIVISOR, "Invalid slippage value");
        minAmountOutBPS = _minAmountOutBPS;
    }

    /**
     * @dev Updates the {ernMinAmountOutBPS} which is the minimum amount accepted in a USDC->ERN/want swap in BPS
     * So 9500 would allow a 5% slippage.
     */
    function updateErnMinAmountOutBPS(uint256 _ernMinAmountOutBPS) external {
        _atLeastRole(STRATEGIST);
        require(_ernMinAmountOutBPS > 8000 && _ernMinAmountOutBPS < PERCENT_DIVISOR, "Invalid slippage value");
        ernMinAmountOutBPS = _ernMinAmountOutBPS;
    }

    /**
     * @dev Sets the exchange used to swap USDC to ERN/want (can be Velo, UniV3, Balancer)
     */
    function setUsdcToErnExchange(Exchange _exchange) external {
        _atLeastRole(STRATEGIST);
        usdcToErnExchange = _exchange;
    }

    /**
     * @dev The pool fees used to swap using UniV3
     */
    function _getFeeCandidates() internal override returns (uint24[] memory) {
        uint24[] memory feeCandidates = new uint24[](2);
        feeCandidates[0] = 500;
        feeCandidates[1] = 3_000;
        return feeCandidates;
    }

    /**
     * @dev Updates the granularity used to check Velodrome TWAP (larger value looks at more samples/longer time)
     */
    function updateVeloUsdcErnQuoteGranularity(uint256 _veloUsdcErnQuoteGranularity) external {
        _atLeastRole(STRATEGIST);
        require(_veloUsdcErnQuoteGranularity >= 2 && _veloUsdcErnQuoteGranularity <= 10, "Invalid granularity value");
        veloUsdcErnQuoteGranularity = _veloUsdcErnQuoteGranularity;
    }

    /**
     * @dev Updates the value used to adjust the value of collateral down slightly (between 0-5%)
     * To account for inaccurate TWAP values and also swap fees and slippage to go from collateral to want
     */
    function updateCollateralValueAdjustmentBPS(uint256 _collateralValueAdjustmentBPS) external {
        _atLeastRole(STRATEGIST);
        require(_collateralValueAdjustmentBPS > 9500 && _collateralValueAdjustmentBPS <= PERCENT_DIVISOR, "Invalid collateral adjustment value");
        collateralValueAdjustmentBPS = _collateralValueAdjustmentBPS;
    }
}
