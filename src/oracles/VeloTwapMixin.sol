// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import {IVeloPair, Cumulatives} from "../interfaces/IVeloPair.sol";
import {ERC20} from "oz/token/ERC20/ERC20.sol";
import {MathUpgradeable} from "oz-upgradeable/utils/math/MathUpgradeable.sol";

contract VeloTwapMixin {
    uint256 constant VELO_OBSERVATION_PERIOD = 1800;

    function getVeloPrice(address source, address target, uint32 period, uint256 baseAmount)
        public
        view
        returns (uint256)
    {
        IVeloPair pair = IVeloPair(source);
        Cumulatives memory current = pair.currentCumulativePrices();
        Cumulatives memory last;
        uint256 observationLength = pair.observationLength();

        uint256 time;

        // avoid stack too deep
        {
            uint256 maxTimestampRequired = current.blockTimestamp - period;
            // the minimum amount of observations the pair must have registered in the period of the query.
            // the actual amount of observations since (block.timestamp - period) is likely to be smaller
            uint256 minObservationsPassed = MathUpgradeable.ceilDiv(period, VELO_OBSERVATION_PERIOD);
            // this observation is guaranteed to be from before the period (left side of the binary search)
            uint256 L = observationLength - minObservationsPassed - 1;
            uint256 R = observationLength - 1; // right side of the binary search
            // binary search for the observation that's closest to the most recent one, yet still within the period
            while (L < R) {
                uint256 observationIndex = (L + R) / 2;

                (last.blockTimestamp, last.reserve0Cumulative, last.reserve1Cumulative) =
                    pair.observations(observationIndex);
                if (last.blockTimestamp > maxTimestampRequired) {
                    R = observationIndex - 1;
                } else {
                    L = observationIndex + 1;
                }
            }
            time = current.blockTimestamp - last.blockTimestamp;
        }

        uint112 reserve0 = safe112((current.reserve0Cumulative - last.reserve0Cumulative) / time);
        uint112 reserve1 = safe112((current.reserve1Cumulative - last.reserve1Cumulative) / time);

        return _veloGetAmountOut(baseAmount, target, reserve0, reserve1, pair.stable(), pair);
    }

    // Utils

    struct GetAmountOutLocalVars {
        uint256 decimals0;
        uint256 decimals1;
        uint256 xy;
    }

    function _veloGetAmountOut(
        uint256 amountIn,
        address tokenIn,
        uint256 _reserve0,
        uint256 _reserve1,
        bool stable,
        IVeloPair pair
    ) private view returns (uint256) {
        (address token0, address token1) = pair.tokens();
        if (stable) {
            GetAmountOutLocalVars memory vars;
            vars.decimals0 = 10 ** ERC20(token0).decimals();
            vars.decimals1 = 10 ** ERC20(token1).decimals();
            vars.xy = _k(_reserve0, _reserve1, vars.decimals0, vars.decimals1, stable);
            _reserve0 = (_reserve0 * 1e18) / vars.decimals0;
            _reserve1 = (_reserve1 * 1e18) / vars.decimals1;
            (uint256 reserveA, uint256 reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
            amountIn = tokenIn == token0 ? (amountIn * 1e18) / vars.decimals0 : (amountIn * 1e18) / vars.decimals1;
            uint256 y =
                reserveB - _get_y(amountIn + reserveA, vars.xy, reserveB, vars.decimals0, vars.decimals1, stable);
            return (y * (tokenIn == token0 ? vars.decimals1 : vars.decimals0)) / 1e18;
        } else {
            (uint256 reserveA, uint256 reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
            return (amountIn * reserveB) / (reserveA + amountIn);
        }
    }

    function _k(uint256 x, uint256 y, uint256 decimals0, uint256 decimals1, bool stable)
        private
        pure
        returns (uint256)
    {
        if (stable) {
            uint256 _x = (x * 1e18) / decimals0;
            uint256 _y = (y * 1e18) / decimals1;
            uint256 _a = (_x * _y) / 1e18;
            uint256 _b = ((_x * _x) / 1e18 + (_y * _y) / 1e18);
            return (_a * _b) / 1e18; // x3y+y3x >= k
        } else {
            return x * y; // xy >= k
        }
    }

    function _f(uint256 x0, uint256 y) private pure returns (uint256) {
        uint256 _a = (x0 * y) / 1e18;
        uint256 _b = ((x0 * x0) / 1e18 + (y * y) / 1e18);
        return (_a * _b) / 1e18;
    }

    function _d(uint256 x0, uint256 y) private pure returns (uint256) {
        return (3 * x0 * ((y * y) / 1e18)) / 1e18 + ((((x0 * x0) / 1e18) * x0) / 1e18);
    }

    function _get_y(uint256 x0, uint256 xy, uint256 y, uint256 decimals0, uint256 decimals1, bool stable)
        private
        pure
        returns (uint256)
    {
        for (uint256 i = 0; i < 255; i++) {
            uint256 k = _f(x0, y);
            if (k < xy) {
                // there are two cases where dy == 0
                // case 1: The y is converged and we find the correct answer
                // case 2: _d(x0, y) is too large compare to (xy - k) and the rounding error
                //         screwed us.
                //         In this case, we need to increase y by 1
                uint256 dy = ((xy - k) * 1e18) / _d(x0, y);
                if (dy == 0) {
                    if (k == xy) {
                        // We found the correct answer. Return y
                        return y;
                    }
                    if (_k(x0, y + 1, decimals0, decimals1, stable) > xy) {
                        // If _k(x0, y + 1) > xy, then we are close to the correct answer.
                        // There's no closer answer than y + 1
                        return y + 1;
                    }
                    dy = 1;
                }
                y = y + dy;
            } else {
                uint256 dy = ((k - xy) * 1e18) / _d(x0, y);
                if (dy == 0) {
                    if (k == xy || _f(x0, y - 1) < xy) {
                        // Likewise, if k == xy, we found the correct answer.
                        // If _f(x0, y - 1) < xy, then we are close to the correct answer.
                        // There's no closer answer than "y"
                        // It's worth mentioning that we need to find y where f(x0, y) >= xy
                        // As a result, we can't return y - 1 even it's closer to the correct answer
                        return y;
                    }
                    dy = 1;
                }
                y = y - dy;
            }
        }
        revert("!y");
    }

    function safe112(uint256 n) private pure returns (uint112) {
        if (n >= 2 ** 112) revert("lol");
        return uint112(n);
    }
}
