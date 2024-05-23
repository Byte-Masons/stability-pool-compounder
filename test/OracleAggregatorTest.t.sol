// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OracleAggregator, OracleKind, OracleRoute, Oracle} from "src/OracleAggregator.sol";
import {Math} from "oz/utils/math/Math.sol";
import "forge-std/Test.sol";

struct TestCase {
    uint256 expected;
    uint256[] prices;
    bool shouldRevert;
}

contract OracleTest is Test {
    using stdJson for string;

    OracleAggregator oracleAggregator;

    uint256 maxMadRelativeToMedianBPS = 500; // MADs can be at most 8% of the median
    uint256 maxScoreBPS = 25_000; // prices that are 2.5x MAD away from the median are rejected

    function setUp() public {
        oracleAggregator = new OracleAggregator();
    }

    /// Math related functions


    function test_revertHighSpread3Values(uint256 price1, uint256 price2, uint256 price3) public {
        // avoid prices above 2**128
        price1 = bound(price1, 0, type(uint128).max);
        // make sure the prices are sufficiently apart
        uint256 minPrice2 = Math.max(1, Math.ceilDiv(price1 * 110, 100));
        vm.assume(minPrice2 < type(uint128).max);
        price2 = bound(price2, minPrice2, type(uint128).max);
        uint256 minPrice3 = Math.max(1, Math.ceilDiv(price2 * 110, 100));
        vm.assume(minPrice3 < type(uint128).max);
        price3 = bound(price3, minPrice3, type(uint128).max);

        uint256[] memory prices = new uint256[](3);
        prices[0] = price1;
        prices[1] = price2;
        prices[2] = price3;
        vm.expectRevert(OracleAggregator.Oracle_PricesSpreadTooHigh.selector);
        oracleAggregator._getValidatedMeanPrice(prices, maxMadRelativeToMedianBPS, maxScoreBPS);
    }

    function test_ignoreOutliers(uint256 price1, uint256 price2, uint256 outlier) public {
        price1 = bound(price1, 0, type(uint128).max);
        price2 = bound(price2, Math.ceilDiv(price1 * 96, 100), price1 * 104 / 100); // 8% spread
        uint256 mean = (price1 + price2) / 2;
        outlier = bound(outlier, 0, type(uint128).max);
        vm.assume(outlier < mean * 80 / 100 || outlier > mean * 120 / 100); // make sure the outlier is far from the mean

        uint256[] memory prices = new uint256[](3);
        prices[0] = price1;
        prices[1] = price2;
        prices[2] = outlier;
        uint256 result = oracleAggregator._getValidatedMeanPrice(prices, maxMadRelativeToMedianBPS, maxScoreBPS);

        assertEq(result, mean, "Outlier should be ignored");
    }

    function test_testCases() public {
        string memory json = vm.readFile("test/test_cases.json");
        TestCase[] memory testCases = abi.decode(json.parseRaw(".testCases"), (TestCase[]));

        for (uint256 i = 0; i < testCases.length; i++) {
            TestCase memory testCase = testCases[i];
            uint256 result;
            if (testCase.shouldRevert) {
                vm.expectRevert();
            }
            result = oracleAggregator._getValidatedMeanPrice(testCase.prices, maxMadRelativeToMedianBPS, maxScoreBPS);

            assertEq(result, testCase.expected, "Unexpected result");
        }
    }
}
