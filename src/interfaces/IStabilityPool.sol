// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./ICollateralConfig.sol";

interface IStabilityPool {
    struct Deposit {
        uint256 initialValue;
    }

    // --- Events ---

    event StabilityPoolCollateralBalanceUpdated(address _collateral, uint256 _newBalance);
    event StabilityPoolLUSDBalanceUpdated(uint256 _newBalance);

    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event ActivePoolAddressChanged(address _newActivePoolAddress);
    event DefaultPoolAddressChanged(address _newDefaultPoolAddress);
    event LUSDTokenAddressChanged(address _newLUSDTokenAddress);
    event SortedTrovesAddressChanged(address _newSortedTrovesAddress);
    event PriceFeedAddressChanged(address _newPriceFeedAddress);
    event CommunityIssuanceAddressChanged(address _newCommunityIssuanceAddress);

    event P_Updated(uint256 _P);
    event S_Updated(address _collateral, uint256 _S, uint128 _epoch, uint128 _scale);
    event G_Updated(uint256 _G, uint128 _epoch, uint128 _scale);
    event EpochUpdated(uint128 _currentEpoch);
    event ScaleUpdated(uint128 _currentScale);

    event DepositSnapshotUpdated(
        address indexed _depositor, uint256 _P, address[] _assets, uint256[] _amounts, uint256 _G
    );
    event UserDepositChanged(address indexed _depositor, uint256 _newDeposit);

    event CollateralGainWithdrawn(address indexed _depositor, address _collateral, uint256 _collAmount);
    event LQTYPaidToDepositor(address indexed _depositor, uint256 _LQTY);
    event CollateralSent(address _collateral, address _to, uint256 _amount);

    // --- Functions ---

    /*
     * Called only once on init, to set addresses of other Liquity contracts
     * Callable only by owner, renounces ownership at the end
     */
    function setAddresses(
        address _borrowerOperationsAddress,
        address _collateralConfigAddress,
        address _troveManagerAddress,
        address _activePoolAddress,
        address _lusdTokenAddress,
        address _sortedTrovesAddress,
        address _priceFeedAddress,
        address _communityIssuanceAddress
    ) external;

    /*
     * Initial checks:
     * - _amount is not zero
     * ---
     * - Triggers a LQTY issuance, based on time passed since the last issuance. The LQTY issuance is shared between *all* depositors
     * - Sends depositor's accumulated gains (LQTY, ETH) to depositor
     * - Increases depositor's deposit, and takes new snapshot.
     */
    function provideToSP(uint256 _amount) external;

    /*
     * Initial checks:
     * - _amount is zero or there are no under collateralized troves left in the system
     * - User has a non zero deposit
     * ---
     * - Triggers a LQTY issuance, based on time passed since the last issuance. The LQTY issuance is shared between *all* depositors
     * - Sends all depositor's accumulated gains (LQTY, ETH) to depositor
     * - Decreases depositor's deposit, and takes new snapshot.
     *
     * If _amount > userDeposit, the user withdraws all of their compounded deposit.
     */
    function withdrawFromSP(uint256 _amount) external;

    /*
     * Initial checks:
     * - Caller is TroveManager
     * ---
     * Cancels out the specified debt against the LUSD contained in the Stability Pool (as far as possible)
     * and transfers the Trove's collateral from ActivePool to StabilityPool.
     * Only called by liquidation functions in the TroveManager.
     */
    function offset(address _collateral, uint256 _debt, uint256 _coll) external;

    /*
     * Returns the total amount of the specified collateral held by the pool, accounted in an internal variable.
     */
    function getCollateral(address _collateral) external view returns (uint256);

    /*
     * Returns LUSD held in the pool. Changes when users deposit/withdraw, and when Trove debt is offset.
     */
    function getTotalLUSDDeposits() external view returns (uint256);

    /*
     * Calculates the collateral gain earned by the deposit since its last snapshots were taken.
     */
    function getDepositorCollateralGain(address _depositor)
        external
        view
        returns (address[] memory assets, uint256[] memory amounts);

    /*
     * Calculate the LQTY gain earned by a deposit since its last snapshots were taken.
     * If not tagged with a front end, the depositor gets a 100% cut of what their deposit earned.
     * Otherwise, their cut of the deposit's earnings is equal to the kickbackRate, set by the front end through
     * which they made their deposit.
     */
    function getDepositorLQTYGain(address _depositor) external view returns (uint256);

    /*
     * Return the user's compounded deposit.
     */
    function getCompoundedLUSDDeposit(address _depositor) external view returns (uint256);

    /*
     * A depositor's snapshot struct now contains a mapping for the running sum (S) for each collateral.
     * Mappings within a struct are not accessible via the auto-generated getters in the ABI, so we provide
     * this separate function that will return the specified depositor's "S" snapshot for the given collateral.
     */
    function depositSnapshots_S(address _depositor, address _collateral) external view returns (uint256);

    /*
     * Fallback function
     * Only callable by Active Pool, it just accounts for ETH received
     * receive() external payable;
     */

    function collateralConfig() external view returns (ICollateralConfig);

    function deposits(address _user) external view returns (IStabilityPool.Deposit memory);
}
