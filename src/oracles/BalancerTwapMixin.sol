// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import {Math} from "oz/utils/math/Math.sol";
import {IBalancerTwapOracle} from "../interfaces/IBalancerTwapOracle.sol";
import {IVault} from "../interfaces/IBalancerVault.sol";
import {ERC20} from "oz/token/ERC20/ERC20.sol"; // for decimals()

contract BalancerTwapMixin {
    error BalancerOracle__TWAPOracleNotReady();

    function getBalancerPrice(address source, address tokenIn, uint32 period, uint256 amountIn)
        public
        view
        returns (uint256 price)
    {
        IBalancerTwapOracle balancerTwapOracle = IBalancerTwapOracle(source);
        // "PAIR_PRICE: the price of the tokens in the Pool,
        // expressed as the price of the second token in units of the first token."
        // "Note that the price is computed *including* the tokens decimals. This means that the pair price of a Pool with
        // DAI and USDC will be close to 1.0, despite DAI having 18 decimals and USDC 6"
        uint256 oraclePrice;

        // ensure the Balancer oracle can return a TWAP value for the specified window
        {
            uint256 largestSafeQueryWindow = balancerTwapOracle.getLargestSafeQueryWindow();
            if (period > largestSafeQueryWindow) revert BalancerOracle__TWAPOracleNotReady();
        }

        {
            IBalancerTwapOracle.OracleAverageQuery[] memory queries = new IBalancerTwapOracle.OracleAverageQuery[](1);
            queries[0] = IBalancerTwapOracle.OracleAverageQuery({
                variable: IBalancerTwapOracle.Variable.PAIR_PRICE,
                secs: period,
                ago: 0
            });
            oraclePrice = balancerTwapOracle.getTimeWeightedAverage(queries)[0];
        }

        // get target price
        // must call the vault, as the pool may have improperly ordered tokens
        IVault balVault = IVault(balancerTwapOracle.getVault());
        (address[] memory poolTokens,,) = balVault.getPoolTokens(balancerTwapOracle.getPoolId());
        bool tokenInToken0 = poolTokens[0] == tokenIn;
        if (tokenInToken0) {
            // price query returns the inverse, so we need to invert it
            oraclePrice = Math.ceilDiv(1e18 * amountIn, oraclePrice);
        }

        uint256 targetPrice = amountIn * oraclePrice / 1e18;

        // fix decimal precision
        uint256 decimals0 = ERC20(poolTokens[0]).decimals();
        uint256 decimals1 = ERC20(poolTokens[1]).decimals();
        if (decimals0 >= decimals1) {
            uint256 decimalDifference = decimals0 - decimals1;
            if (tokenInToken0) {
                price = targetPrice / 10 ** decimalDifference;
            } else {
                price = targetPrice * 10 ** decimalDifference;
            }
        } else if (decimals0 < decimals1) {
            uint256 decimalDifference = decimals1 - decimals0;
            if (tokenInToken0) {
                price = targetPrice * 10 ** decimalDifference;
            } else {
                price = targetPrice / 10 ** decimalDifference;
            }
        }
    }
}
