// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface IPriceFeed {
    // --- Events ---
    event LastGoodPriceUpdated(address _collateral, uint256 _lastGoodPrice);

    // --- Function ---
    function fetchPrice(address _collateral) external returns (uint256);

    function lastGoodPrice(address _collateral) external view returns (uint256);

    function priceAggregator(address _collateral) external view returns (address);

    function updateChainlinkAggregator(address _collateral, address _priceAggregatorAddress) external;
}
