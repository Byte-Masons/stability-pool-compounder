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

    function getMeanPrice(uint256[] memory prices, uint256 maxStdRelativeToMeanBPS, uint256 maxScoreBPS)
        public
        pure
        returns (uint256)
    {
        (bool[] memory isInvalid) = getValidityByZScore(prices, maxScoreBPS);
        (uint256 std, uint256 mean, uint256 nrOfValidPrices) = standardDeviation(prices, isInvalid);
        if (std * BPS / mean > maxStdRelativeToMeanBPS) revert Oracle_OraclesUnreliable();
        if (nrOfValidPrices < 2) revert Oracle_OraclesUnreliable();
        return mean;
    }

    function getValidityByZScore(uint256[] memory prices, uint256 maxScoreBPS)
        public
        pure
        returns (bool[] memory isInvalid)
    {
        (uint256 std, uint256 mean,) = standardDeviation(prices, new bool[](prices.length));
        isInvalid = new bool[](prices.length);
        for (uint256 i = 0; i < prices.length; i++) {
            int256 score = (int256(prices[i]) - int256(mean)) * int256(BPS) / int256(std);
            isInvalid[i] = score < -int256(maxScoreBPS) || score > int256(maxScoreBPS);
        }
    }

    function standardDeviation(uint256[] memory prices, bool[] memory isInvalid)
        public
        pure
        returns (uint256 std, uint256 mean, uint256 nrValidPrices)
    {
        uint256 sum = 0;
        for (uint256 i = 0; i < prices.length; i++) {
            if (!isInvalid[i]) {
                sum += prices[i];
                nrValidPrices++;
            }
        }
        mean = sum / nrValidPrices;
        uint256[] memory deviationsSq = new uint256[](nrValidPrices);
        for (uint256 i = 0; i < nrValidPrices; i++) {
            int256 deviation = int256(prices[i]) - int256(mean);
            deviationsSq[i] = uint256(deviation * deviation);
        }
        uint256 sumDeviationsSq = 0;
        for (uint256 i = 0; i < deviationsSq.length; i++) {
            sumDeviationsSq += deviationsSq[i];
        }
        std = MathUpgradeable.sqrt(sumDeviationsSq / nrValidPrices, MathUpgradeable.Rounding.Up);
    }

    function getPriceFeedPrice(address source, address target, uint256 baseAmount) public returns (uint256 price) {
        return IPriceFeed(source).fetchPrice(target) * baseAmount;
    }

    uint256[50] private __gap;
}
