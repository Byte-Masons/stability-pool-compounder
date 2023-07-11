// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface IVelodromePair {
    // gives the current twap price measured from amountIn * tokenIn gives amountOut
    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256 amountOut);

    // as per `current`, however allows user configured granularity, up to the full window size
    function quote(address tokenIn, uint256 amountIn, uint256 granularity) external view returns (uint256 amountOut);
}
