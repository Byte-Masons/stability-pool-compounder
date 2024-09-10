// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import {IVeloPair, Cumulatives} from "../interfaces/IVeloPair.sol";
import {ERC20} from "oz/token/ERC20/ERC20.sol";
import {MathUpgradeable} from "oz-upgradeable/utils/math/MathUpgradeable.sol";

contract VeloTwapMixin {
    uint256 constant VELO_OBSERVATION_PERIOD = 1800;

    function getVeloPrice(address source, address tokenIn, uint32 period, uint32 ago, uint256 amountIn)
        public
        view
        returns (uint256 price)
    {
        IVeloPair pair = IVeloPair(source);
        Cumulatives memory end;
        Cumulatives memory start;
        uint256 observationLength = pair.observationLength();

        if (ago == 0) {
            end = pair.currentCumulativePrices();
            
            (Cumulatives memory _before, Cumulatives memory _after) = _getObservations(pair, block.timestamp - period, observationLength);
            
            start = _averageObservations(_before, _after, end.blockTimestamp - period);
        } else {
            end.blockTimestamp = block.timestamp - ago;
            (Cumulatives memory _before, Cumulatives memory _after) = _getObservations(pair, end.blockTimestamp, observationLength);
            // get mean of the two observations weighted by the target
            end = _averageObservations(_before, _after, end.blockTimestamp);

            start.blockTimestamp = end.blockTimestamp - period;
            if (start.blockTimestamp >= _before.blockTimestamp) {
                // this means that the start timestamp is within the same observation period above,
                // so we can just use the same observations
                start = _averageObservations(_before, _after, start.blockTimestamp);
            } else {
                (_before, _after) = _getObservations(pair, start.blockTimestamp, observationLength);
                start = _averageObservations(_before, _after, start.blockTimestamp);
            }
        }

        uint256 timeElapsed = end.blockTimestamp - start.blockTimestamp;
        uint256 reserve0 = (end.reserve0Cumulative - start.reserve0Cumulative) / timeElapsed;
        uint256 reserve1 = (end.reserve1Cumulative - start.reserve1Cumulative) / timeElapsed;

        price = _veloGetAmountOut(amountIn, tokenIn, reserve0, reserve1, pair.stable(), pair);
    }

    // gets the observations immediately before and after the target timestamp using binary search
    function _getObservations(IVeloPair pair, uint256 targetTimestamp, uint256 observationLength)
        public
        view
        returns (Cumulatives memory _before, Cumulatives memory _after)
    {
        uint256 minObservationsPassed = MathUpgradeable.ceilDiv(block.timestamp - targetTimestamp, VELO_OBSERVATION_PERIOD);
        // this observation is guaranteed to be from before the period (left side of the binary search)
        uint256 L = observationLength - minObservationsPassed - 1;
        uint256 R = observationLength - 1; // right side of the binary search

        // Binary search to find the closest observation before targetTimestamp
        while (L < R) {
            uint256 observationIndex = (L + R + 1) / 2; // round up
            (uint256 blockTimestamp, uint256 reserve0Cumulative, uint256 reserve1Cumulative) = pair.observations(observationIndex);
            if (blockTimestamp > targetTimestamp) {
                R = observationIndex - 1;
            } else {
                L = observationIndex;
                _before.blockTimestamp = blockTimestamp;
                _before.reserve0Cumulative = reserve0Cumulative;
                _before.reserve1Cumulative = reserve1Cumulative;
            }
        }
        if (_before.blockTimestamp == 0) {
            // ensure that the observation is assigned
            (_before.blockTimestamp, _before.reserve0Cumulative, _before.reserve1Cumulative) = pair.observations(L);
        }
        if (L == observationLength - 1) {
            _after = pair.currentCumulativePrices();
        } else {
            (_after.blockTimestamp, _after.reserve0Cumulative, _after.reserve1Cumulative) = pair.observations(L + 1);
        }
    }

    // This function is used to calculate the average of two observations, after and before the target timestamp,
    // weighted by the target timestamp.
    function _averageObservations(Cumulatives memory _before, Cumulatives memory _after, uint256 targetTimestamp)
        private
        view
        returns (Cumulatives memory)
    {
        uint256 weight1 = targetTimestamp - _before.blockTimestamp;
        uint256 weight2 = _after.blockTimestamp - targetTimestamp;
        uint256 weightSum = weight1 + weight2;
        return
            Cumulatives({
                reserve0Cumulative: (_before.reserve0Cumulative * weight2 + _after.reserve0Cumulative * weight1) / weightSum,
                reserve1Cumulative: (_before.reserve1Cumulative * weight2 + _after.reserve1Cumulative * weight1) / weightSum,
                blockTimestamp: targetTimestamp
            });
    }

    /**
     * Utils
     * Below are the functions that are used to calculate the price of a token in a Velo pool.
     * This code is adapted from Velodrome's contracts directly, with changes to use parameters
     * instead of state variables, and additional comments for clarification.
     */
    struct GetAmountOutLocalVars {
        uint256 decimals0;
        uint256 decimals1;
        uint256 xy;
    }

    // This function calculates the amount of tokenOut that will be received for a given amount of tokenIn
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

    // This function calculates the product of the reserves of a Velo pool
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

    // The following functions are used to calculate the price of a token in a stable Velo pool

    // _f calculates an estimate of the product of x3y+y3x
    // for the first estimate, it's given reserveIn + amountIn and reserveOut
    function _f(uint256 x0, uint256 y) private pure returns (uint256) {
        uint256 _a = (x0 * y) / 1e18;
        uint256 _b = ((x0 * x0) / 1e18 + (y * y) / 1e18);
        return (_a * _b) / 1e18;
    }

    function _d(uint256 x0, uint256 y) private pure returns (uint256) {
        return (3 * x0 * ((y * y) / 1e18)) / 1e18 + ((((x0 * x0) / 1e18) * x0) / 1e18);
    }

    // _get_y calculates the reserveOut for a given trade
    // it uses an optimized binary search to find the correct value
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
    
}
