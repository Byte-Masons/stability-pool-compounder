// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./ICollateralConfig.sol";

// Common interface for the Trove Manager.
interface ITroveManager {
    function getTroveOwnersCount(address _collateral) external view returns (uint256);

    function getTroveFromTroveOwnersArray(address _collateral, uint256 _index) external view returns (address);

    function getNominalICR(address _borrower, address _collateral) external view returns (uint256);

    function getCurrentICR(address _borrower, address _collateral, uint256 _price) external view returns (uint256);

    function liquidate(address _borrower, address _collateral) external;

    function liquidateTroves(address _collateral, uint256 _n) external;

    // function getEntireSystemColl(address _collateral) external view returns (uint);
    // function getEntireSystemColl(address _collateral) external view returns (uint);

    function collateralConfig() external view returns (ICollateralConfig);
}
