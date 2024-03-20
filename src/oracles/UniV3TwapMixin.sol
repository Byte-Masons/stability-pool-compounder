// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import {TickMath} from "univ3-core/libraries/TickMath.sol";
import {FullMath} from "univ3-core/libraries/FullMath.sol";
import {IUniswapV3Pool} from "univ3-core/interfaces/IUniswapV3Pool.sol";

contract UniV3TwapMixin {
    function getUniV3Price(address source, address targetToken, uint32 period, uint256 baseAmount)
        public
        view
        returns (uint256 price)
    {
        require(period != 0, "BP");

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = period;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives,) = IUniswapV3Pool(source).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 tick = int24(tickCumulativesDelta / int56(int32(period)));
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        (address token0, address token1) = (IUniswapV3Pool(source).token0(), IUniswapV3Pool(source).token1());
        address baseToken = token0 < token1 ? token0 : token1;

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            price = baseToken < targetToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            price = baseToken < targetToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }
}
