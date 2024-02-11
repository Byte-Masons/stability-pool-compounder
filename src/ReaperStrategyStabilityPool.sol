// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import "vault-v2/interfaces/ISwapper.sol";
import {ReaperBaseStrategyv4} from "vault-v2/ReaperBaseStrategyv4.sol";
import {IStabilityPool} from "./interfaces/IStabilityPool.sol";
import {IPriceFeed} from "./interfaces/IPriceFeed.sol";
import {IVault} from "vault-v2/interfaces/IVault.sol";
import {AggregatorV3Interface} from "vault-v2/interfaces/AggregatorV3Interface.sol";
import {ReaperMathUtils} from "vault-v2/libraries/ReaperMathUtils.sol";
import {IStaticOracle} from "./interfaces/IStaticOracle.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {IERC20MetadataUpgradeable} from "oz-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {SafeERC20Upgradeable} from "oz-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {MathUpgradeable} from "oz-upgradeable/utils/math/MathUpgradeable.sol";
import {IVeloPair} from "./interfaces/IVeloPair.sol";

/**
 * @dev Strategy to compound rewards and liquidation collateral gains in the Ethos stability pool
 */

contract ReaperStrategyStabilityPool is ReaperBaseStrategyv4 {
    using ReaperMathUtils for uint256;
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;

    // constants
    uint256 constant MIN_VELO_PRICE_UPDATE_INTERVAL = 1 days;
    uint256 constant MIN_ALLOWED_PERIOD_VELO = 2 days;
    uint256 constant MIN_NR_OF_POINTS = 1;
    uint256 constant MIN_LENGTH_OF_WINDOW = 1;
    uint256 constant MAXIMUM_ALLOWED_RELATIVE_CHANGE = 300; // 3%
    uint256 constant PRICE_VALIDITY_THRESHOLD = 5000; // 50%
    uint32 constant MAX_ALLOWED_TOLERANCE = 200; // 2%

    // 3rd-party contract addresses
    IStabilityPool public stabilityPool;
    IPriceFeed public priceFeed;
    IERC20MetadataUpgradeable public usdc;
    IERC20MetadataUpgradeable public weth;
    ExchangeSettings public exchangeSettings; // Holds addresses to use Velo, UniV3 and Bal through Swapper
    IUniswapV3Pool public uniV3UsdcErnPool;
    IVeloPair public veloUsdcErnPool;
    IVeloPair public veloWethErnPool;
    IStaticOracle public uniV3TWAP;

    uint256 public constant ETHOS_DECIMALS = 18; // Decimals used by ETHOS
    uint256 public ernMinAmountOutBPS; // The max allowed slippage when trading in to ERN
    uint256 public compoundingFeeMarginBPS; // How much collateral value is lowered to account for the costs of swapping
    uint32 public uniV3TWAPPeriod; // How many seconds the uniV3 TWAP will look at
    uint32 public veloTWAPPeriod; // How many seconds the velo TWAP will look at
    ExchangeType public usdcToErnExchange; // Controls which exchange is used to swap USDC to ERN
    bool public shouldOverrideHarvestBlock; // If reverts on TWAP out of normal range should be ignored
    uint256 acceptableTWAPUpperBound; // The normal upper price for the TWAP, reverts harvest if above
    uint256 acceptableTWAPLowerBound; // The normal lower price for the , reverts harvest if below

    struct ExchangeSettings {
        address veloRouter;
        address balVault;
        address uniV3Router;
        address uniV2Router;
    }

    struct Pools {
        address stabilityPool;
        address uniV3UsdcErnPool;
        address veloUsdcErnPool;
        address veloWethErnPool;
    }

    struct Tokens {
        address want;
        address usdc;
        address weth;
    }

    error InvalidUsdcToErnExchange(uint256 exchangeEnum);
    error InvalidUsdcToErnTWAP(uint256 twapEnum);
    error TWAPOutsideAllowedRange(uint256 usdcPrice);
    error InvalidSwapStep();
    error CouldntDetermineMeanPrice();
    error WindowLongerThanOrZero();
    error TooShortPeriod();

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address _swapper,
        address[] memory _strategists,
        address[] memory _multisigRoles,
        address[] memory _keepers,
        address _priceFeed,
        address _uniV3TWAP,
        ExchangeSettings calldata _exchangeSettings,
        Pools calldata _pools,
        Tokens calldata _tokens
    ) public initializer {
        require(_vault != address(0), "vault is 0 address");
        require(_swapper != address(0), "swapper is 0 address");
        require(_strategists.length != 0, "no strategists");
        require(_multisigRoles.length == 3, "invalid amount of multisig roles");
        require(_tokens.want != address(0), "want is 0 address");
        require(_priceFeed != address(0), "priceFeed is 0 address");
        require(_tokens.usdc != address(0), "usdc is 0 address");
        require(_tokens.weth != address(0), "weth is 0 address");
        require(_uniV3TWAP != address(0), "uniV3TWAP is 0 address");
        require(_exchangeSettings.veloRouter != address(0), "veloRouter is 0 address");
        require(_exchangeSettings.balVault != address(0), "balVault is 0 address");
        require(_exchangeSettings.uniV3Router != address(0), "uniV3Router is 0 address");
        require(_exchangeSettings.uniV2Router != address(0), "uniV2Router is 0 address");
        require(_pools.stabilityPool != address(0), "stabilityPool is 0 address");
        require(_pools.uniV3UsdcErnPool != address(0), "uniV3UsdcErnPool is 0 address");
        require(_pools.veloUsdcErnPool != address(0), "veloUsdcErnPool is 0 address");
        require(_pools.veloWethErnPool != address(0), "veloWethErnPool is 0 address");

        __ReaperBaseStrategy_init(_vault, _swapper, _tokens.want, _strategists, _multisigRoles, _keepers);
        stabilityPool = IStabilityPool(_pools.stabilityPool);
        priceFeed = IPriceFeed(_priceFeed);
        usdc = IERC20MetadataUpgradeable(_tokens.usdc);
        weth = IERC20MetadataUpgradeable(_tokens.weth);
        exchangeSettings = _exchangeSettings;

        updateErnMinAmountOutBPS(9800);
        usdcToErnExchange = ExchangeType.UniV3;

        uniV3TWAP = IStaticOracle(_uniV3TWAP);
        uniV3UsdcErnPool = IUniswapV3Pool(_pools.uniV3UsdcErnPool);
        veloUsdcErnPool = IVeloPair(_pools.veloUsdcErnPool);
        veloWethErnPool = IVeloPair(_pools.veloWethErnPool);
        compoundingFeeMarginBPS = 9950;
        updateUniV3TWAPPeriod(7200);
        veloTWAPPeriod = 2 days;
        updateAcceptableTWAPBounds(980_000, 1_100_000);
    }

    /**
     * @dev Emergency function to quickly exit the position and return the funds to the vault
     */
    function _liquidateAllPositions() internal override returns (uint256 amountFreed) {
        _withdraw(type(uint256).max);
        _harvestCore();
        return balanceOfWant();
    }

    /**
     * @dev Hook run before harvest to claim rewards
     */
    function _beforeHarvestSwapSteps() internal override {
        _withdraw(0); // claim rewards
        _revertOnTWAPOutsideRange();
    }

    function compound() public returns (uint256 usdcGained) {
        _atLeastRole(KEEPER);
        _withdraw(0); // claim rewards

        uint256 usdcBalanceBefore = usdc.balanceOf(address(this));
        _executeHarvestSwapSteps();
        usdcGained = usdc.balanceOf(address(this)) - usdcBalanceBefore;
    }

    // Swap steps will:
    // 1. liquidate collateral rewards into USDC using the external Swapper (+ Chainlink oracles)
    // 2. liquidate oath rewards into USDC using the external swapper (with 0 minAmountOut)
    // As a final step, we need to convert the USDC into ERN using the UniV3 TWAP.
    // Since the external Swapper cannot support arbitrary TWAPs at this time, we use this hook so
    // we can calculate the minAmountOut ourselves and call the swapper directly.
    function _afterHarvestSwapSteps() internal override {
        uint256 usdcBalance = usdc.balanceOf(address(this));
        if (usdcBalance != 0) {
            uint256 expectedErnAmount = _getErnAmountForUsdc(usdcBalance);
            uint256 minAmountOut = (expectedErnAmount * ernMinAmountOutBPS) / PERCENT_DIVISOR;
            MinAmountOutData memory data =
                MinAmountOutData({kind: MinAmountOutKind.Absolute, absoluteOrBPSValue: minAmountOut});
            usdc.safeApprove(address(swapper), 0);
            usdc.safeIncreaseAllowance(address(swapper), usdcBalance);
            if (usdcToErnExchange == ExchangeType.Bal) {
                swapper.swapBal(address(usdc), want, usdcBalance, data, exchangeSettings.balVault);
            } else if (usdcToErnExchange == ExchangeType.VeloSolid) {
                swapper.swapVelo(address(usdc), want, usdcBalance, data, exchangeSettings.veloRouter);
            } else if (usdcToErnExchange == ExchangeType.UniV3) {
                swapper.swapUniV3(address(usdc), want, usdcBalance, data, exchangeSettings.uniV3Router);
            } else if (usdcToErnExchange == ExchangeType.UniV2) {
                swapper.swapUniV2(address(usdc), want, usdcBalance, data, exchangeSettings.uniV2Router);
            } else {
                revert InvalidUsdcToErnExchange(uint256(usdcToErnExchange));
            }
        }
    }

    function _revertOnTWAPOutsideRange() internal view {
        if (shouldOverrideHarvestBlock) {
            return;
        }
        uint128 ernAmount = 1 ether; // 1 ERN
        uint256 usdcAmount = getErnAmountForUsdcAll(ernAmount, MAX_ALLOWED_TOLERANCE);

        if (usdcAmount < acceptableTWAPLowerBound || usdcAmount > acceptableTWAPUpperBound) {
            revert TWAPOutsideAllowedRange(usdcAmount);
        }
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract
     * or when funds are reinvested in to the strategy.
     */
    function _deposit(uint256 toReinvest) internal override {
        if (toReinvest != 0) {
            stabilityPool.provideToSP(toReinvest);
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        if (_hasInitialDeposit(address(this))) {
            stabilityPool.withdrawFromSP(_amount);
        }
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     * It takes into account both the funds in hand, the funds in the stability pool,
     * and also the balance of collateral tokens + USDC.
     */
    function _estimatedTotalAssets() internal override returns (uint256) {
        return balanceOfPoolUsingPriceFeed() + balanceOfWant();
    }

    /**
     * @dev Estimates the amount of ERN held in the stability pool and any
     * balance of collateral or USDC. The values are converted using oracles and
     * the Velodrome USDC-ERN TWAP and collateral+USDC value discounted slightly.
     */
    function balanceOfPool() public view override returns (uint256) {
        uint256 ernCollateralValue = getERNValueOfCollateralGain();
        return balanceOfPoolCommon(ernCollateralValue);
    }

    /**
     * @dev Estimates the amount of ERN held in the stability pool and any
     * balance of collateral or USDC. The values are converted using oracles and
     * the Velodrome USDC-ERN TWAP and collateral+USDC value discounted slightly.
     * Uses the Ethos price feed so backup oracles are used if chainlink fails.
     * Will likely not revert so can be used in harvest even if Chainlink is down.
     */
    function balanceOfPoolUsingPriceFeed() public returns (uint256) {
        uint256 ernCollateralValue = getERNValueOfCollateralGainUsingPriceFeed();
        return balanceOfPoolCommon(ernCollateralValue);
    }

    /**
     * @dev Shared logic for balanceOfPool functions
     */
    function balanceOfPoolCommon(uint256 _ernCollateralValue) public view returns (uint256) {
        uint256 depositedErn = stabilityPool.getCompoundedLUSDDeposit(address(this));
        uint256 adjustedCollateralValue = _ernCollateralValue * compoundingFeeMarginBPS / PERCENT_DIVISOR;

        return depositedErn + adjustedCollateralValue;
    }

    /**
     * @dev Calculates the estimated ERN value of collateral and USDC using Chainlink oracles
     * and the Velodrome USDC-ERN TWAP.
     */
    function getERNValueOfCollateralGain() public view returns (uint256 ernValueOfCollateral) {
        uint256 usdValueOfCollateralGain = getUSDValueOfCollateralGain();
        ernValueOfCollateral = getERNValueOfCollateralGainCommon(usdValueOfCollateralGain);
    }

    /**
     * @dev Calculates the estimated ERN value of collateral using the Ethos price feed, Chainlink oracle for USDC
     * and the Velodrome USDC-ERN TWAP.
     */
    function getERNValueOfCollateralGainUsingPriceFeed() public returns (uint256 ernValueOfCollateral) {
        uint256 usdValueOfCollateralGain = getUSDValueOfCollateralGainUsingPriceFeed();
        ernValueOfCollateral = getERNValueOfCollateralGainCommon(usdValueOfCollateralGain);
    }

    /**
     * @dev Shared logic for getERNValueOfCollateralGain functions.
     */
    function getERNValueOfCollateralGainCommon(uint256 _usdValueOfCollateralGain)
        public
        view
        returns (uint256 ernValueOfCollateral)
    {
        uint256 usdcValueOfCollateral = _getUsdcEquivalentOfUSD(_usdValueOfCollateralGain);
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 totalUsdcValue = usdcBalance + usdcValueOfCollateral;
        ernValueOfCollateral = _getErnAmountForUsdc(totalUsdcValue);
    }

    /**
     * @dev Calculates the estimated USD value of collateral gains using Chainlink oracles
     * {usdValueOfCollateralGain} is the USD value of all collateral in 18 decimals
     */
    function getUSDValueOfCollateralGain() public view returns (uint256 usdValueOfCollateralGain) {
        (address[] memory assets, uint256[] memory amounts) = stabilityPool.getDepositorCollateralGain(address(this));
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 amount;
            if (asset == address(usdc) || asset == want) {
                amount = amounts[i];
            } else {
                amount = amounts[i] + IERC20MetadataUpgradeable(asset).balanceOf(address(this));
            }
            if (amount != 0) {
                usdValueOfCollateralGain += _getUSDEquivalentOfCollateral(asset, amount);
            }
        }
    }

    /**
     * @dev Calculates the estimated USD value of collateral gains using the Ethos price feed
     * {usdValueOfCollateralGain} is the USD value of all collateral in 18 decimals
     */
    function getUSDValueOfCollateralGainUsingPriceFeed() public returns (uint256 usdValueOfCollateralGain) {
        (address[] memory assets, uint256[] memory amounts) = stabilityPool.getDepositorCollateralGain(address(this));
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            if (asset == address(usdc) || asset == want) {
                continue;
            }
            uint256 amount = amounts[i] + IERC20MetadataUpgradeable(asset).balanceOf(address(this));
            if (amount != 0) {
                usdValueOfCollateralGain += _getUSDEquivalentOfCollateralUsingPriceFeed(asset, amount);
            }
        }
    }

    /**
     * @dev Returns the {expectedErnAmount} for the specified {_usdcAmount} of USDC using
     * the UniV3 TWAP.
     */
    function _getErnAmountForUsdc(uint256 _usdcAmount) internal view returns (uint256 expectedErnAmount) {
        if (_usdcAmount != 0) {
            expectedErnAmount = getErnAmountForUsdcUniV3(uint128(_usdcAmount), uniV3TWAPPeriod);
        }
    }

    /**
     * @dev Returns the {ernAmount} for the specified {_baseAmount} of USDC over a given {_period} (in seconds)
     * using the UniV3 TWAP.
     */
    function getErnAmountForUsdcUniV3(uint128 _baseAmount, uint32 _period) public view returns (uint256 ernAmount) {
        address[] memory pools = new address[](1);
        pools[0] = address(uniV3UsdcErnPool);
        uint256 quoteAmount =
            uniV3TWAP.quoteSpecificPoolsWithTimePeriod(_baseAmount, address(usdc), want, pools, _period);
        return quoteAmount;
    }

    /**
     * @dev Returns the {ernAmount} for the specified {_baseAmount} of USDC over a given {_period} (in seconds)
     * using the Velo TWAP
     * @notice One sample with wide window (calculations are done inside sample function between two last priceCumulatives and timestamps).
     */
    function getErnAmountForUsdcVeloWindow(uint128 _baseAmount, uint32 _period) public view returns (uint256) {
        if (_period < MIN_ALLOWED_PERIOD_VELO) {
            revert TooShortPeriod();
        }
        uint256 window = _period / MIN_VELO_PRICE_UPDATE_INTERVAL;
        if (window >= veloUsdcErnPool.observationLength() || window == 0) {
            revert WindowLongerThanOrZero();
        }
        uint256 wantDecimals = IERC20MetadataUpgradeable(want).decimals();
        uint256[] memory quoteAmount =
            veloUsdcErnPool.sample(address(usdc), (10 ** usdc.decimals()), MIN_NR_OF_POINTS, window);
        return (_baseAmount * quoteAmount[0] * (10 ** (wantDecimals - usdc.decimals())) / 1 ether); // better math
    }

    /**
     * @dev provides twap price with user configured granularity, up to the full window size
     *
     */
    function _quote(address tokenIn, uint256 amountIn, uint256 granularity) private view returns (uint256 amountOut) {
        uint256[] memory _prices = veloUsdcErnPool.sample(tokenIn, amountIn, granularity, MIN_LENGTH_OF_WINDOW);
        uint256 priceAverageCumulative;
        uint256 _length = _prices.length;
        for (uint256 i = 0; i < _length; i++) {
            priceAverageCumulative += _prices[i];
        }
        return priceAverageCumulative / granularity;
    }

    /**
     * @dev Returns the {ernAmount} for the specified {_baseAmount} of USDC over a given {_period} (in seconds)
     * using the Velo TWAP
     * @notice Multiple samples with shortest window possible (calculations are the average of small samples calculated from shortest possible window).
     */
    function getErnAmountForUsdcVeloPoints(uint128 _baseAmount, uint32 _period) public view returns (uint256) {
        if (_period < MIN_ALLOWED_PERIOD_VELO) {
            revert TooShortPeriod();
        }
        uint256 granuality = _period / MIN_VELO_PRICE_UPDATE_INTERVAL;
        if (granuality >= veloUsdcErnPool.observationLength() || granuality == 0) {
            revert WindowLongerThanOrZero();
        }
        uint256 quoteAmount = _quote(address(usdc), (10 ** usdc.decimals()), granuality);
        uint256 wantDecimals = IERC20MetadataUpgradeable(want).decimals();

        return (_baseAmount * quoteAmount * (10 ** (wantDecimals - usdc.decimals())) / 1 ether); // better math
    }

    function getUsdcAmountForWethUsingPriceFeeds() public returns (uint256) {
        uint256 tmpPrice = _getUSDEquivalentOfCollateralUsingPriceFeed(address(weth), 1 ether);
        return _getUsdcEquivalentOfUSD(tmpPrice);
    }

    /**
     * @dev Returns the {ernAmount} for the specified {_baseAmount} of USDC over a given {_period} (in seconds)
     * using the Velo TWAP.
     */
    function getErnAmountForWethVelo(uint128 _baseAmount, uint32 _period) public view returns (uint256) {
        if (_period < MIN_ALLOWED_PERIOD_VELO) {
            revert TooShortPeriod();
        }
        address[] memory pools = new address[](1);
        uint256 window = _period / MIN_VELO_PRICE_UPDATE_INTERVAL;
        if (window >= veloUsdcErnPool.observationLength() || window == 0) {
            revert WindowLongerThanOrZero();
        }

        uint256[] memory quoteAmount = veloWethErnPool.sample(address(weth), 1e18, 1, window);
        return (_baseAmount * quoteAmount[0] / 1 ether); // better math
    }

    /**
     * @dev Returns the {ernAmount} for the specified {_baseAmount} of USDC over a given {_period} (in seconds)
     * using the Velo ERN/WETH TWAP and chainlink price feed.
     *
     * Math:
     * 1e18 wei - x ern
     * 1e18 wei - y usdc
     * ern = 1e18 wei / x => ern = y usdc / x
     * @notice Due to price feeds interface this function cannot be viewable - it usage makes difficullties
     */
    function getErnAmountForUsdcVeloWeth(uint128 _baseAmount, uint32 _period) public returns (uint256) {
        uint256 usdcAmountForWethPriceFeeds = (getUsdcAmountForWethUsingPriceFeeds() * _baseAmount);
        // console2.log("Feed: ", usdcAmountForWethPriceFeeds);
        uint256 veloAmountForWethVelo = getErnAmountForWethVelo(_baseAmount, _period);
        // console2.log("Velo: ", veloAmountForWethVelo);
        return ((usdcAmountForWethPriceFeeds * 1 ether * 10 ** usdc.decimals()) / veloAmountForWethVelo);
    }

    /**
     * @dev Function consumes array of {prices} and check them against one reference price pointed by {idx}.
     * If the prices are inside range specified in {tolerance}, function marks it in {indexes} array and increment {nrOfValidPrices}.
     * @param prices - array of prices from oracles
     * @param idx - array index at which the price will be taken as a reference
     * @param tolerance - allowed tolerance of deviation
     * @return indexes - indexes at which the prices are in range
     * @return nrOfValidPrices - number of prices which are in range
     */
    function getInfoAboutTwapOracles(uint256[] memory prices, uint32 idx, uint32 tolerance)
        private
        pure
        returns (bool[] memory, uint32)
    {
        require(idx <= prices.length);
        bool[] memory indexes = new bool[](prices.length);
        uint256 referencePrice = prices[idx];
        uint32 nrOfValidPrices = 1;
        indexes[idx] = true;

        /* For loop assumptions:
        - {cnt} shall start with value greater than passed {idx} but cannot be greater than length of array of prices
        - loop ends when {cnt} reaches value of {idx} - it must happen as we are iterating over finite number of values (modulo {price.length})
        - {cnt} increments by one and starts from 0 when reaches {prices.length}
        */
        for (uint32 cnt = (idx + 1) % uint32(prices.length); cnt != idx; cnt = (cnt + 1) % uint32(prices.length)) {
            if (
                referencePrice + (referencePrice * tolerance / PERCENT_DIVISOR) >= prices[cnt]
                    && referencePrice - (referencePrice * tolerance / PERCENT_DIVISOR) <= prices[cnt]
            ) {
                /* The price is inside the range - store index and increment number of valid prices */
                nrOfValidPrices++;
                indexes[cnt] = true;
            }
        }
        return (indexes, nrOfValidPrices);
    }

    /**
     * @dev Returns the {ernAmount} for the specified {_baseAmount} of USDC over a given {_period} (in seconds)
     * using the all possible oracles.
     */
    function getErnAmountForUsdcAll(uint128 _baseAmount, uint32 _tolerance) public view returns (uint256) {
        uint256[] memory _prices = new uint256[](2);
        _prices[0] = getErnAmountForUsdcVeloPoints(_baseAmount, veloTWAPPeriod);
        _prices[1] = getErnAmountForUsdcUniV3(_baseAmount, uniV3TWAPPeriod);
        //_prices[2] = getErnAmountForUsdcVeloWeth(_baseAmount, _period); // This function is not view

        return getErnAmountForUsdcAll(_prices, _tolerance);
    }

    /**
     * @dev Returns the {ernAmount} for the specified {_baseAmount} of USDC over a given {_period} (in seconds)
     * using the all possible oracles.
     */
    function getErnAmountForUsdcAll(uint256[] memory _prices, uint32 _tolerance) public view returns (uint256) {
        uint256 meanTwap = 0;
        if (_prices.length > 1) {
            for (uint32 idx = 0; idx < _prices.length; idx++) {
                (bool[] memory indexes, uint32 nrOfValidPrices) = getInfoAboutTwapOracles(_prices, idx, _tolerance);
                // Amount of valid prices must be greater than {PRICE_VALIDITY_THRESHOLD}%
                if (nrOfValidPrices > (_prices.length * PRICE_VALIDITY_THRESHOLD / PERCENT_DIVISOR)) {
                    uint256 sumOfPrices = 0;
                    // Iterate through {indexes} array to see which index of price array shall be taken into {meanTwap} calculations
                    for (uint32 cnt = 0; cnt < indexes.length; cnt++) {
                        if (indexes[cnt] != false) {
                            sumOfPrices += _prices[cnt];
                        }
                    }
                    meanTwap = sumOfPrices / nrOfValidPrices;
                    break;
                }
            }
            if (meanTwap == 0) {
                revert CouldntDetermineMeanPrice();
            }
        } else if (_prices.length == 1) {
            meanTwap = _prices[0];
        } else {
            revert CouldntDetermineMeanPrice();
        }
        return meanTwap;
    }

    /**
     * @dev Returns USD equivalent of {_amount} of {_collateral} with 18 digits of decimal precision.
     * The precision of {_amount} is whatever {_collateral}'s native decimals are (ex. 8 for wBTC)
     */
    function _getUSDEquivalentOfCollateral(address _collateral, uint256 _amount) internal view returns (uint256) {
        uint256 price = swapper.getChainlinkPriceTargetDigits(_collateral);
        return _getUSDEquivalentOfCollateralCommon(_collateral, _amount, price, ETHOS_DECIMALS);
    }

    /**
     * @dev Returns USD equivalent of {_amount} of {_collateral} with 18 digits of decimal precision.
     * The precision of {_amount} is whatever {_collateral}'s native decimals are (ex. 8 for wBTC)
     * This uses the price feed directly which has a Tellor backup oracle should Chainlink fail.
     * However it is not view so can only be used in none-view functions
     */
    function _getUSDEquivalentOfCollateralUsingPriceFeed(address _collateral, uint256 _amount)
        internal
        returns (uint256)
    {
        uint256 price = priceFeed.fetchPrice(_collateral); // Question: This make function not viewable an must be propagated upper
        return _getUSDEquivalentOfCollateralCommon(_collateral, _amount, price, ETHOS_DECIMALS);
    }

    /**
     * @dev Shared logic for getUSDEquivalentOfCollateral functions
     */
    function _getUSDEquivalentOfCollateralCommon(
        address _collateral,
        uint256 _amount,
        uint256 _price,
        uint256 _priceDecimals
    ) internal view returns (uint256) {
        uint256 scaledAmount = _scaleToEthosDecimals(_amount, IERC20MetadataUpgradeable(_collateral).decimals());
        uint256 USDAssetValue = (scaledAmount * _price) / (10 ** _priceDecimals);
        return USDAssetValue;
    }

    /**
     * @dev Returns Usdc equivalent of {_amount} of USD with 6 digits of decimal precision.
     * The precision of {_amount} is 18 decimals
     */
    function _getUsdcEquivalentOfUSD(uint256 _amount) internal view returns (uint256) {
        uint256 usdcPrice18Decimals;
        try swapper.getChainlinkPriceTargetDigits(address(usdc)) returns (uint256 price) {
            usdcPrice18Decimals = price;
        } catch {
            usdcPrice18Decimals = 1 ether; // default to 1$
        }

        return (_amount * 10 ** uint256(usdc.decimals())) / usdcPrice18Decimals;
    }

    /**
     * @dev Check to ensure an initial deposit has been made in the stability pool
     * Which is a requirement to call withdraw.
     */
    function _hasInitialDeposit(address _user) internal view returns (bool) {
        return stabilityPool.deposits(_user).initialValue != 0;
    }

    /**
     * @dev Scales {_collAmount} given in {_collDecimals} to an 18 decimal amount (used by Ethos)
     */
    function _scaleToEthosDecimals(uint256 _collAmount, uint256 _collDecimals)
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
    function _scaleToCollateralDecimals(uint256 _collAmount, uint256 _collDecimals)
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
     * Swapping to ERN (want) is hardcoded in this strategy and relies on TWAP so
     * a swap step should not be set to swap to it.
     */
    function _verifySwapStepVirtual(SwapStep memory _step) internal view override {
        if (_step.end == want) {
            revert InvalidSwapStep();
        }
    }

    /**
     * @dev Updates the {ernMinAmountOutBPS} which is the minimum amount accepted in a USDC->ERN/want swap.
     * In BPS so 9500 would allow a 5% slippage.
     */
    function updateErnMinAmountOutBPS(uint256 _ernMinAmountOutBPS) public {
        _atLeastRole(STRATEGIST);
        require(_ernMinAmountOutBPS > 8000 && _ernMinAmountOutBPS < PERCENT_DIVISOR, "Invalid slippage value");
        if (_ernMinAmountOutBPS < 9500) {
            _atLeastRole(ADMIN);
        }
        ernMinAmountOutBPS = _ernMinAmountOutBPS;
    }

    /**
     * @dev Sets the exchange used to swap USDC to ERN/want (can be Velo, UniV3, Balancer)
     */
    function updateUsdcToErnExchange(ExchangeType _exchange) external {
        _atLeastRole(STRATEGIST);
        usdcToErnExchange = _exchange;
    }

    /**
     * @dev Updates the value used to adjust the value of collateral down slightly (between 0-2%)
     * To account for swap fees and slippage to go from collateral to want
     */
    function updateCompoundingFeeMarginBPS(uint256 _compoundingFeeMarginBPS) external {
        _atLeastRole(GUARDIAN);
        require(
            _compoundingFeeMarginBPS > 9800 && _compoundingFeeMarginBPS <= PERCENT_DIVISOR,
            "Invalid compoundingFeeMarginBPS value"
        );
        compoundingFeeMarginBPS = _compoundingFeeMarginBPS;
    }

    /**
     * @dev Sets the period (in seconds) used to query the UniV3 TWAP
     * The pool itself has a {currentCardinality} by calling
     * increaseObservationCardinalityNext on the UniV3 pool.
     * The earliest observation in the pool must be within the given time period.
     * Will revert if the observation period is too long.
     * DEFAULT_ADMIN is allowed to change the value regardless, but for lower access
     * roles a check is performed to see if changing duration would effect the price
     * past some threshold, if the strategy holds collateral value (priced by TWAP).
     */
    function updateUniV3TWAPPeriod(uint32 _uniV3TWAPPeriod) public {
        _atLeastRole(ADMIN);
        require(_uniV3TWAPPeriod >= 7200, "TWAP period is too short");

        uint256 newErnAmount = getErnAmountForUsdcUniV3(uint128(1_000_000), _uniV3TWAPPeriod);
        uint256 oldErnAmount = getErnAmountForUsdcUniV3(uint128(1_000_000), uniV3TWAPPeriod);

        uniV3TWAPPeriod = _uniV3TWAPPeriod;

        if (_hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) return;

        uint256 ernCollateralValue = getERNValueOfCollateralGainUsingPriceFeed();

        if (ernCollateralValue != 0) {
            uint256 difference = newErnAmount > oldErnAmount ? newErnAmount - oldErnAmount : oldErnAmount - newErnAmount;
            uint256 relativeChange = difference * PERCENT_DIVISOR / oldErnAmount;
            require(relativeChange < MAXIMUM_ALLOWED_RELATIVE_CHANGE, "TWAP duration change would change price");
        }
    }

    function updateVeloTWAPPeriod(uint32 _veloTWAPPeriod) public {
        _atLeastRole(ADMIN);
        require(_veloTWAPPeriod >= MIN_ALLOWED_PERIOD_VELO, "TWAP period is too short");

        uint256 newErnAmount = getErnAmountForUsdcVeloPoints(uint128(1_000_000), _veloTWAPPeriod);
        uint256 oldErnAmount = getErnAmountForUsdcVeloPoints(uint128(1_000_000), veloTWAPPeriod);

        veloTWAPPeriod = _veloTWAPPeriod;

        if (_hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) return;

        uint256 ernCollateralValue = getERNValueOfCollateralGainUsingPriceFeed();

        if (ernCollateralValue != 0) {
            uint256 difference = newErnAmount > oldErnAmount ? newErnAmount - oldErnAmount : oldErnAmount - newErnAmount;
            uint256 relativeChange = difference * PERCENT_DIVISOR / oldErnAmount;
            require(relativeChange < MAXIMUM_ALLOWED_RELATIVE_CHANGE, "TWAP duration change would change price");
        }
    }

    /**
     * @dev Sets if harvest reverts on TWAP being outside of the normal range should
     * be overriden (ignored).
     */
    function updateShouldOverrideHarvestBlock(bool _shouldOverrideHarvestBlock) external {
        _atLeastRole(DEFAULT_ADMIN_ROLE);
        shouldOverrideHarvestBlock = _shouldOverrideHarvestBlock;
    }

    /**
     * @dev Defines the normal range of the TWAP, outside of which harvests will be reverted
     * to protect against TWAP price manipulation.
     */
    function updateAcceptableTWAPBounds(uint256 _acceptableTWAPLowerBound, uint256 _acceptableTWAPUpperBound) public {
        _atLeastRole(DEFAULT_ADMIN_ROLE);
        bool aboveMinLimit = _acceptableTWAPLowerBound >= 900_000;
        bool belowMaxLimit = _acceptableTWAPUpperBound <= 1_100_000;
        bool lowerBoundBelowUpperBound = _acceptableTWAPLowerBound < _acceptableTWAPUpperBound;
        bool hasValidBounds = lowerBoundBelowUpperBound && aboveMinLimit && belowMaxLimit;

        require(hasValidBounds, "Invalid bounds");
        acceptableTWAPLowerBound = _acceptableTWAPLowerBound;
        acceptableTWAPUpperBound = _acceptableTWAPUpperBound;
    }
}
