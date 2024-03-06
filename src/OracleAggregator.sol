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

    function getTwapPrices(OracleRoute[] memory oracles, uint256 baseAmount) public returns (uint256[] memory prices) {
        prices = new uint256[](oracles.length);
        for (uint256 i = 0; i < oracles.length; i++) {
            prices[i] = getMultiHopPrice(oracles[i], baseAmount);
        }
    }

    function getMultiHopPrice(OracleRoute memory route, uint256 baseAmount) public returns (uint256 price) {
        for (uint256 i = 0; i < route.oracles.length; i++) {
            price = getPrice(route.oracles[i], baseAmount);
            baseAmount = price;
        }
    }

    function getPrice(Oracle memory oracle, uint256 baseAmount) public returns (uint256 price) {
        if (oracle.kind == OracleKind.Velo) {
            return getVeloPrice(oracle.source, oracle.target, uint32(oracle.period), baseAmount);
        } else if (oracle.kind == OracleKind.UniV3) {
            return getUniV3Price(oracle.source, oracle.target, uint32(oracle.period), baseAmount);
        } else if (oracle.kind == OracleKind.PriceFeed) {
            return getPriceFeedPrice(oracle.source, oracle.target, baseAmount);
        } else {
            revert Oracle_InvalidKind();
        }
    }

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

    uint256[50] private __gap;
}
