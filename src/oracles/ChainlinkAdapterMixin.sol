// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

contract ChainlinkAdapterMixin {
    // @notice Fetches the price from a Chainlink oracle
    // @param source Chainlink oracle address
    // @param tokenIn address(0) for price, address(1) for inverted price
    // @param decimalOffset Difference between tokenIn and tokenOut decimals
    // @param amountIn Input amount of the base token
    function getChainlinkPrice(address source, uint256 decimalOffset, address tokenIn, uint256 amountIn)
        internal
        view
        returns (uint256 price)
    {
        AggregatorV3Interface chainlinkOracle = AggregatorV3Interface(source);
        (, int256 answer,,,) = chainlinkOracle.latestRoundData();
        uint8 chainlinkDecimals = chainlinkOracle.decimals();
        if (tokenIn == address(0)) {
            price = amountIn * uint256(answer) / (10 ** uint256(chainlinkDecimals)) / (10 ** decimalOffset);
        } else {
            price = amountIn * (10 ** uint256(chainlinkDecimals)) / uint256(answer) * (10 ** decimalOffset);
        }
    }
}
