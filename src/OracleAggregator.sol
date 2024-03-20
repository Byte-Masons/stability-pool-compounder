// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import {VeloTwapMixin} from "./oracles/VeloTwapMixin.sol";
import {UniV3TwapMixin} from "./oracles/UniV3TwapMixin.sol";
import {IPriceFeed} from "./interfaces/IPriceFeed.sol";

import {MathUpgradeable} from "oz-upgradeable/utils/math/MathUpgradeable.sol";

// This contract contains tools for computing TWAP values and
// making averages between the results, for more reliable prices.
// Has support for multiple oracles
contract OracleAggregator is VeloTwapMixin, UniV3TwapMixin {
    error Oracle_VeloOverflow();
    error Oracle_InvalidKind();
    error Oracle_OraclesUnreliable();

    uint256 constant BPS = 1_000_000;

    enum OracleKind {
        Velo,
        UniV3,
        PriceFeed
    }

    struct OracleRoute {
        Oracle[] oracles;
    }

    struct Oracle {
        address source;
        address target;
        uint256 period;
        OracleKind kind;
    }

    function getTwapPricesView(OracleRoute[] memory oracles, uint256 baseAmount)
        public
        view
        returns (uint256[] memory prices)
    {
        prices = new uint256[](oracles.length);
        for (uint256 i = 0; i < oracles.length; i++) {
            prices[i] = getMultiHopPriceView(oracles[i], baseAmount);
        }
    }

    /// @param route List of oracles for multihop price
    /// @param baseAmount Input amount of the base token
    function getMultiHopPriceView(OracleRoute memory route, uint256 baseAmount) public view returns (uint256 price) {
        for (uint256 i = 0; i < route.oracles.length; i++) {
            price = getPrice(route.oracles[i], baseAmount);
            baseAmount = price;
        }
    }

    /**
     * state-changing versions of the above functions
     * This allows the Kind of oracle to be PriceFeed
     */
    function getTwapPrices(OracleRoute[] memory oracles, uint256 baseAmount) public returns (uint256[] memory prices) {
        prices = new uint256[](oracles.length);
        for (uint256 i = 0; i < oracles.length; i++) {
            prices[i] = getMultiHopPrice(oracles[i], baseAmount);
        }
    }

    /// @param route List of oracles for multihop price
    /// @param baseAmount Input amount of the base token
    function getMultiHopPrice(OracleRoute memory route, uint256 baseAmount) public returns (uint256 price) {
        for (uint256 i = 0; i < route.oracles.length; i++) {
            if (route.oracles[i].kind == OracleKind.PriceFeed) {
                price = getPriceFeedPrice(route.oracles[i].source, route.oracles[i].target, baseAmount);
            } else {
                price = getPrice(route.oracles[i], baseAmount);
            }
            price = getPrice(route.oracles[i], baseAmount);
            baseAmount = price;
        }
    }

    /// @param oracle Kind of oracle to use -- see OracleKind
    /// @param baseAmount  Input amount of the base token
    function getPrice(Oracle memory oracle, uint256 baseAmount) public view returns (uint256 price) {
        if (oracle.kind == OracleKind.Velo) {
            return getVeloPrice(oracle.source, oracle.target, uint32(oracle.period), baseAmount);
        } else if (oracle.kind == OracleKind.UniV3) {
            return getUniV3Price(oracle.source, oracle.target, uint32(oracle.period), baseAmount);
        } else {
            revert Oracle_InvalidKind();
        }
    }

    /// @notice Get the mean price of a list of prices, filtering out outliers
    /// @param prices List of prices
    /// @param maxMadRelativeToMedianBPS How many BPS the MAD can be relative to the median.
    /// For example, a MAD higher than 10% of the median means the prices are too spread out,
    /// and the whole list is considered unreliable.
    /// @param maxScoreBPS If a price has a Z-score higher than this, it's considered an outlier and filtered out
    function getMeanPrice(uint256[] memory prices, uint256 maxMadRelativeToMedianBPS, uint256 maxScoreBPS)
        public
        pure
        returns (uint256)
    {
        (bool[] memory isInvalid, uint256 mad, uint256 median) = getValidityByZScore(prices, maxScoreBPS);
        (uint256 mean, uint256 nrOfValidPrices) = getMean(prices, isInvalid);
        if (mad > (median * maxMadRelativeToMedianBPS) / BPS) revert Oracle_OraclesUnreliable();
        if (nrOfValidPrices < ((prices.length * 3) / 5)) revert Oracle_OraclesUnreliable();
        return mean;
    }

    /// @param prices List of prices to be checked
    /// @param maxScoreBPS If a price has a Z-score higher than this, it's considered an outlier and filtered out
    /// @return An array mask for the prices array, where true means the price is invalid
    /// @return The MAD - Median Absolute Deviation
    /// @return The median of the prices
    function getValidityByZScore(uint256[] memory prices, uint256 maxScoreBPS)
        public
        pure
        returns (bool[] memory, uint256, uint256)
    {
        (uint256 mad, uint256 median) = getMAD(prices);
        bool[] memory isInvalid = new bool[](prices.length);
        for (uint256 i = 0; i < prices.length; i++) {
            int256 score = (int256(prices[i]) - int256(median)) * int256(BPS) / int256(mad);
            isInvalid[i] = score < -int256(maxScoreBPS) || score > int256(maxScoreBPS);
        }
        return (isInvalid, mad, median);
    }

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
    function getMAD(uint256[] memory arr) public pure returns (uint256 mad, uint256 median) {
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
        public
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
        mean = sum / nrValidPrices;
    }

    function getPriceFeedPrice(address source, address target, uint256 baseAmount) public returns (uint256 price) {
        return IPriceFeed(source).fetchPrice(target) * baseAmount;
    }

    // in the case contracts that inhrerit from this one are upgradeable
    uint256[50] private __gap;
}
