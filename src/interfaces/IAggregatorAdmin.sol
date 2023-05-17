// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface IAggregatorAdmin {
    /**
     * @notice Allows the owner to propose a new address for the aggregator
     * @param _aggregator The new address for the aggregator contract
     */
    function proposeAggregator(address _aggregator) external;

    /**
     * @notice Allows the owner to confirm and change the address
     * to the proposed aggregator
     * @dev Reverts if the given address doesn't match what was previously
     * proposed
     * @param _aggregator The new address for the aggregator contract
     */
    function confirmAggregator(address _aggregator) external;
}
