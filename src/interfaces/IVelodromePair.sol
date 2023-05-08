// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface IVelodromePair {
    // gives the current twap price measured from amountIn * tokenIn gives amountOut
    function current(address tokenIn, uint amountIn) external view returns (uint amountOut);

     // as per `current`, however allows user configured granularity, up to the full window size
    function quote(address tokenIn, uint amountIn, uint granularity) external view returns (uint amountOut);
}