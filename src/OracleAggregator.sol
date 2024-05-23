// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import {VeloTwapMixin} from "./oracles/VeloTwapMixin.sol";
import {UniV3TwapMixin} from "./oracles/UniV3TwapMixin.sol";
import {BalancerTwapMixin} from "./oracles/BalancerTwapMixin.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {ERC20} from "oz/token/ERC20/ERC20.sol"; // has decimals(), as opposed to IERC20
import {MathUpgradeable} from "oz-upgradeable/utils/math/MathUpgradeable.sol";

enum OracleKind {
    Velo,
    UniV3,
    Balancer,
    Chainlink
}

struct OracleRoute {
    Oracle[] oracles;
}

struct Oracle {
    address source;
    address tokenIn;
    uint256 windowOrDecimalOffset;
    OracleKind kind;
}

// This contract contains tools for computing TWAP values and
// making averages between the results, for more reliable prices.
// Has support for multiple oracles
contract OracleAggregator is VeloTwapMixin, UniV3TwapMixin, BalancerTwapMixin {
    error Oracle_InvalidKind();
    error Oracle_PricesSpreadTooHigh();
    error Oracle_PricesUnreliable();

    uint256 constant BPS = 10_000;

    // @notice Fetches the mean price of a list of oracles, filtering out outliers
    // and checking if the prices are reliable.
    function getReliablePrice(OracleRoute[] memory oracles, uint256 amountIn, uint256 spreadTolerance, uint256 maxScoreBPS)
        external
        view
        returns (uint256 price)
    {
        uint256[] memory prices = new uint256[](oracles.length);
        for (uint256 i = 0; i < oracles.length; i++) {
            prices[i] = _fetchMultiHopPrice(oracles[i], amountIn, false);
        }
        if (prices.length == 1) {
            return prices[0];
        }
        if (prices.length == 2) {
            uint256[] memory delayedPrices = new uint256[](2);
            for (uint256 i = 0; i < oracles.length; i++) {
                delayedPrices[i] = _fetchMultiHopPrice(oracles[i], amountIn, true);
            }
            (uint256 delayedMean, ) = getMean(delayedPrices, new bool[](2));
            uint256[] memory combinedPrices = new uint256[](3);
            combinedPrices[0] = prices[0];
            combinedPrices[2] = delayedMean;
            combinedPrices[1] = prices[1];
            return _getValidatedMeanPrice(combinedPrices, spreadTolerance, maxScoreBPS);
        }
        return _getValidatedMeanPrice(prices, spreadTolerance, maxScoreBPS);
    }

    // @notice Fetches the prices without performing any validation
    function fetchTwapPrices(OracleRoute[] memory oracles, uint256 amountIn)
        external
        view
        returns (uint256[] memory prices)
    {
        prices = new uint256[](oracles.length);
        for (uint256 i = 0; i < oracles.length; i++) {
            prices[i] = _fetchMultiHopPrice(oracles[i], amountIn, false);
        }
    }

    /// @param route List of oracles for multihop price
    /// @param amountIn Input amount of the base token
    function fetchMultiHopPrice(OracleRoute memory route, uint256 amountIn) external view returns (uint256 price) {
        for (uint256 i = 0; i < route.oracles.length; i++) {
            price = _fetchPrice(route.oracles[i], amountIn, false);
            amountIn = price;
        }
    }

    function fetchPrice(Oracle memory oracle, uint256 amountIn) external view returns (uint256 price) {
        return _fetchPrice(oracle, amountIn, false);
    }

    /// @param route List of oracles for multihop price
    /// @param amountIn Input amount of the base token
    function _fetchMultiHopPrice(OracleRoute memory route, uint256 amountIn, bool delayWindow) internal view returns (uint256 price) {
        for (uint256 i = 0; i < route.oracles.length; i++) {
            price = _fetchPrice(route.oracles[i], amountIn, delayWindow);
            amountIn = price;
        }
    }

    /// @param oracle Kind of oracle to use -- see OracleKind
    /// @param amountIn Input amount of the base token
    /// @param delayWindow If true, the price is calculated with a delayed window - used for 2 price comparisons - incompatible with Chainlink
    function _fetchPrice(Oracle memory oracle, uint256 amountIn, bool delayWindow) internal view returns (uint256 price) {
        uint32 period;
        uint32 ago;
        if (delayWindow) {
            period = uint32(oracle.windowOrDecimalOffset * 2);
            ago = uint32(oracle.windowOrDecimalOffset);
        } else {
            period = uint32(oracle.windowOrDecimalOffset);
            ago = 0;
        }
        
        if (oracle.kind == OracleKind.Velo) {
            return getVeloPrice(oracle.source, oracle.tokenIn, period, ago, amountIn);
        } else if (oracle.kind == OracleKind.UniV3) {
            return getUniV3Price(oracle.source, oracle.tokenIn, period, ago, amountIn);
        } else if (oracle.kind == OracleKind.Balancer) {
            return getBalancerPrice(oracle.source, oracle.tokenIn, period, ago, amountIn);
        } else if (oracle.kind == OracleKind.Chainlink) {
            return getChainlinkPrice(oracle.source, oracle.windowOrDecimalOffset, oracle.tokenIn, amountIn);
        } else {
            revert Oracle_InvalidKind();
        }
    }

    /// @notice Get the mean price of a list of prices, filtering out outliers from 3+ price lists.
    /// @param prices List of prices
    /// @param spreadTolerance The spread tolerance in BPS
    /// How many BPS the MAD can be relative to the median.
    /// For example, a MAD higher than 10% of the median means the prices are too spread out,
    /// and the whole list is considered unreliable.
    /// @param maxScoreBPS If a price has a Z-score higher than this, it's considered an outlier and filtered out
    function _getValidatedMeanPrice(uint256[] memory prices, uint256 spreadTolerance, uint256 maxScoreBPS)
        public
        pure
        returns (uint256 mean)
    {
        (bool[] memory isInvalid, uint256 mad, uint256 median) = _getValidityByZScore(prices, maxScoreBPS);
        uint256 nrOfValidPrices;
        (mean, nrOfValidPrices) = getMean(prices, isInvalid);
        if (mad > (median * spreadTolerance) / BPS) revert Oracle_PricesSpreadTooHigh();
        // if more than 1/3 of the prices are invalid, the whole list is considered unreliable
        if ((prices.length - nrOfValidPrices) > ((prices.length) / 3)) revert Oracle_PricesUnreliable();
        return mean;
    }

    /// @param prices List of prices to be checked
    /// @param maxScoreBPS If a price has a Z-score higher than this, it's considered an outlier and filtered out
    /// @return isInvalid An array mask for the prices array, where true means the price is invalid
    /// @return mad The MAD - Median Absolute Deviation
    /// @return median The median of the prices
    function _getValidityByZScore(uint256[] memory prices, uint256 maxScoreBPS)
        internal
        pure
        returns (bool[] memory isInvalid, uint256 mad, uint256 median)
    {
        (mad, median) = getMAD(prices);
        isInvalid = new bool[](prices.length);
        for (uint256 i = 0; i < prices.length; i++) {
            int256 score = (int256(prices[i]) - int256(median)) * int256(BPS) / int256(mad);
            isInvalid[i] = score < -int256(maxScoreBPS) || score > int256(maxScoreBPS);
        }
        return (isInvalid, mad, median);
    }

    // https://ethereum.stackexchange.com/questions/1517/sorting-an-array-of-integer-with-ethereum
    function quickSort(uint256[] memory arr, int256 left, int256 right) internal pure {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        uint256 pivot = arr[uint256(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint256(i)] < pivot) i++;
            while (pivot < arr[uint256(j)]) j--;
            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (arr[uint256(j)], arr[uint256(i)]);
                i++;
                j--;
            }
        }
        if (left < j) {
            quickSort(arr, left, j);
        }
        if (i < right) {
            quickSort(arr, i, right);
        }
    }

    /// @notice Get the Median Absolute Deviation of a list of values
    /// @param arr List of values
    function getMAD(uint256[] memory arr) internal pure returns (uint256 mad, uint256 median) {
        uint256 n = arr.length;
        quickSort(arr, 0, int256(n - 1));
        if (n % 2 == 0) {
            median = (arr[n / 2 - 1] + arr[n / 2]) / 2;
        } else {
            median = arr[n / 2];
        }
        uint256[] memory deviations = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            if (arr[i] > median) {
                deviations[i] = arr[i] - median;
            } else {
                deviations[i] = median - arr[i];
            }
        }
        quickSort(deviations, 0, int256(n - 1));
        mad = deviations[n / 2];
    }

    function getMean(uint256[] memory prices, bool[] memory isInvalid)
        internal
        pure
        returns (uint256 mean, uint256 nrValidPrices)
    {
        uint256 sum = 0;
        for (uint256 i = 0; i < prices.length; i++) {
            if (!isInvalid[i]) {
                sum += prices[i];
                nrValidPrices++;
            }
        }

        if (nrValidPrices > 0) mean = sum / nrValidPrices;
    }


    // @notice Fetches the price from a Chainlink oracle
    // @param source Chainlink oracle address
    // @param tokenIn address(0) for price, address(1) for inverted price
    // @param decimalOffset Difference between tokenIn and tokenOut decimals
    // @param amountIn Input amount of the base token
    function getChainlinkPrice(address source, uint256 decimalOffset, address tokenIn, uint256 amountIn) internal view returns (uint256 price) {
        AggregatorV3Interface chainlinkOracle = AggregatorV3Interface(source);
        (, int256 answer, , , ) = chainlinkOracle.latestRoundData();
        uint8 chainlinkDecimals = chainlinkOracle.decimals();
        if (tokenIn == address(0)) {
            price = amountIn * uint256(answer) / (10**uint256(chainlinkDecimals)) / (10**decimalOffset);
        } else {
            price = amountIn * (10**uint256(chainlinkDecimals)) / uint256(answer) * (10**decimalOffset);
        }
    }

}
