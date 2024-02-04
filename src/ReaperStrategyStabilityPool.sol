// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
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
    uint32 public twapPeriod; // How many seconds the uniV3 TWAP will look at
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
    error StabilityPool__CouldntDetermineMeanPrice();
    error StabilityPool__WindowLongerThanOrZero();
    error StabilityPool__TooShortPeriod();

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
        twapPeriod = 7200; // Question: Couldn't understand how it will work with function and twapPeriod as a 0 at the init,
        // Can it be initialization of global variable instead of update function ?
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
        address[] memory pools = new address[](1);
        pools[0] = address(uniV3UsdcErnPool);
        uint256 usdcAmount =
            uniV3TWAP.quoteSpecificPoolsWithTimePeriod(ernAmount, want, address(usdc), pools, twapPeriod);

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
            expectedErnAmount = getErnAmountForUsdcAll(uint128(_usdcAmount), twapPeriod);
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
     * using the Velo TWAP.
     */
    function getErnAmountForUsdcVelo(uint128 _baseAmount, uint32 _period) public view returns (uint256) {
        if (_period < 2 days) {
            revert StabilityPool__TooShortPeriod();
        }
        address[] memory pools = new address[](1);
        uint256 window = _period / 1 days;
        if (window >= veloUsdcErnPool.observationLength() || window == 0) {
            revert StabilityPool__WindowLongerThanOrZero();
        }

        uint256 wantDecimals = IERC20MetadataUpgradeable(want).decimals();
        uint256[] memory quoteAmount = veloUsdcErnPool.sample(address(usdc), (10 ** usdc.decimals()), 1, window);
        return (_baseAmount * quoteAmount[0] * (10 ** (wantDecimals - usdc.decimals())) / 1 ether); // better math
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
        if (_period < 2 days) {
            revert StabilityPool__TooShortPeriod();
        }
        address[] memory pools = new address[](1);
        uint256 window = _period / 1 days;
        if (window >= veloUsdcErnPool.observationLength() || window == 0) {
            revert StabilityPool__WindowLongerThanOrZero();
        }

        uint256 wantDecimals = IERC20MetadataUpgradeable(want).decimals();
        uint256[] memory quoteAmount = veloWethErnPool.sample(address(weth), 1e18, 1, window);
        return (_baseAmount * quoteAmount[0] / 1 ether); // better math
    }

    /**
     * @dev Returns the {ernAmount} for the specified {_baseAmount} of USDC over a given {_period} (in seconds)
     * using the Velo TWAP.
     *
     * Math:
     * 1e18 wei - x ern
     * 1e18 wei - y usdc
     * ern = 1e18 wei / x => ern = y usdc / x
     */
    function getErnAmountForUsdcVeloWeth(uint128 _baseAmount, uint32 _period) public returns (uint256) {
        uint256 usdcAmountForWethPriceFeeds = (getUsdcAmountForWethUsingPriceFeeds() * _baseAmount);
        // console2.log("Feed: ", usdcAmountForWethPriceFeeds);
        uint256 veloAmountForWethVelo = getErnAmountForWethVelo(_baseAmount, _period);
        // console2.log("Velo: ", veloAmountForWethVelo);
        return ((usdcAmountForWethPriceFeeds * 1 ether * 10 ** usdc.decimals()) / veloAmountForWethVelo);
    }

    function getInfoAboutTwapOracles(uint256[] memory prices, uint32 idx, uint32 tolerance)
        private
        view
        returns (bool[] memory indexes, uint32 validAmount)
    {
        indexes = new bool[](prices.length);
        uint256 referencePrice = prices[idx];
        indexes[idx] = true;
        validAmount = 1;

        for (uint32 cnt = (idx + 1) % uint32(prices.length); cnt != idx; cnt = (cnt + 1) % uint32(prices.length)) {
            console2.log("Reference price: ", referencePrice);
            console2.log("vs prices[cnt]: ", prices[cnt]);
            // Question: Can be acceptableTWAPLowerBound and acceptableTWAPUpperBound be applied here ?
            if (
                referencePrice + (referencePrice * tolerance / PERCENT_DIVISOR) >= prices[cnt]
                    && referencePrice - (referencePrice * tolerance / PERCENT_DIVISOR) <= prices[cnt]
            ) {
                validAmount++;
                indexes[cnt] = true;
            }
        }
    }

    /**
     * @dev Returns the {ernAmount} for the specified {_baseAmount} of USDC over a given {_period} (in seconds)
     * using the all possible oracles.
     */
    function getErnAmountForUsdcAll(uint128 _baseAmount, uint32 _period) public view returns (uint256) {
        uint256[] memory _prices = new uint256[](2);
        _prices[0] = getErnAmountForUsdcVelo(_baseAmount, _period);
        _prices[1] = getErnAmountForUsdcUniV3(_baseAmount, _period);
        //_prices[2] = getErnAmountForUsdcVeloWeth(_baseAmount, _period); // This function is not view

        return getErnAmountForUsdcAll(_prices, _baseAmount, _period, 200);
    }

    /**
     * @dev Returns the {ernAmount} for the specified {_baseAmount} of USDC over a given {_period} (in seconds)
     * using the all possible oracles.
     */
    function getErnAmountForUsdcAll(uint256[] memory _prices, uint128 _baseAmount, uint32 _period, uint32 _tolerance)
        public
        view
        returns (uint256)
    {
        uint256 meanTwap = 0;

        for (uint32 idx = 0; idx < _prices.length; idx++) {
            (bool[] memory indexes, uint32 validAmount) = getInfoAboutTwapOracles(_prices, idx, _tolerance);
            console2.log("Idx: ", idx);
            console2.log("Valid amount: ", validAmount);
            // Amount of valid prices must be greater than 50%
            if (validAmount > (_prices.length / 2)) {
                uint256 sumOfPrices = 0;
                for (uint32 cnt = 0; cnt < indexes.length; cnt++) {
                    if (indexes[cnt] != false) {
                        sumOfPrices += _prices[cnt];
                        console2.log("Sum of prices: ", sumOfPrices);
                    }
                }
                meanTwap = sumOfPrices / validAmount;
                break;
            }
        }
        if (meanTwap == 0) {
            revert StabilityPool__CouldntDetermineMeanPrice();
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
    function updateTwapPeriod(uint32 _twapPeriod) public {
        _atLeastRole(ADMIN);
        require(_twapPeriod >= 7200, "TWAP period is too short");

        uint256 newErnAmount = getErnAmountForUsdcAll(uint128(1_000_000), _twapPeriod);
        uint256 oldErnAmount = getErnAmountForUsdcAll(uint128(1_000_000), twapPeriod);

        twapPeriod = _twapPeriod;

        if (_hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) return;

        uint256 ernCollateralValue = getERNValueOfCollateralGainUsingPriceFeed();

        if (ernCollateralValue != 0) {
            uint256 difference = newErnAmount > oldErnAmount ? newErnAmount - oldErnAmount : oldErnAmount - newErnAmount;
            uint256 relativeChange = difference * PERCENT_DIVISOR / oldErnAmount;
            require(relativeChange < 300, "TWAP duration change would change price");
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
