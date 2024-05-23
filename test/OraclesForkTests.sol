// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OracleAggregator, OracleKind, OracleRoute, Oracle} from "src/OracleAggregator.sol";
import {ERC20} from "oz/token/ERC20/ERC20.sol";
import {Math} from "oz/utils/math/Math.sol";
import {VeloTwapMixin} from "src/oracles/VeloTwapMixin.sol";
import {IVeloPair, Cumulatives} from "src/interfaces/IVeloPair.sol";
import "forge-std/Test.sol";

contract OracleForkTests is Test {
    uint256 opFork;

    OracleAggregator oracleAggregator;

    address WETH_OP_UNIV3_POOL = 0x68F5C0A2DE713a54991E01858Fd27a3832401849;
    address WETH_OP_VELO_POOL = 0xd25711EdfBf747efCE181442Cc1D8F5F8fc8a0D3;
    address USDC_ERN_VELO_POOL = 0x605cCE502dEe6BD201b493782e351e645D44abBB;
    address USDC_ERN_UNIV3_POOL = 0x4CE4a1a593Ea9f2e6B2c05016a00a2D300C9fFd8;

    address USDC_ADDRESS = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address ERN_ADDRESS = 0xc5b001DC33727F8F26880B184090D3E252470D45;

    address OP_ADDRESS = 0x4200000000000000000000000000000000000042;
    address WETH_ADDRESS = 0x4200000000000000000000000000000000000006;

    address PRICE_FEED = 0xC6b3Eea38Cbe0123202650fB49c59ec41a406427;
    address WBTC_ADDRESS = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;

    function setUp() public {
        opFork = vm.createSelectFork("https://go.getblock.io/bec4b0dd7017435c8880f2cae8ea2d4d"/* , 118638228 */);

        oracleAggregator = new OracleAggregator();
    }

    function test_uniV3() public {
        OracleRoute memory route;
        route.oracles = new Oracle[](1);
        route.oracles[0] =
            Oracle({source: WETH_OP_UNIV3_POOL, tokenIn: WETH_ADDRESS, windowOrDecimalOffset: 3600, kind: OracleKind.UniV3});

        uint256 price = oracleAggregator.fetchMultiHopPrice(route, 1e18);
        assertEq(price, 1194216670556036888562);

        route.oracles[0] =
            Oracle({source: WETH_OP_UNIV3_POOL, tokenIn: OP_ADDRESS, windowOrDecimalOffset: 3600, kind: OracleKind.UniV3});

        uint256 price2 = oracleAggregator.fetchMultiHopPrice(route, 1e18);
        assertEq(price2, 837368983916789);
    }

    function test_velo() public {
        OracleRoute memory route;
        route.oracles = new Oracle[](1);
        route.oracles[0] =
            Oracle({source: WETH_OP_VELO_POOL, tokenIn: WETH_ADDRESS, windowOrDecimalOffset: 3600, kind: OracleKind.Velo});

        uint256 expected = 1192245433864621830052;

        uint256 price = oracleAggregator.fetchMultiHopPrice(route, 1e18);
        assertEq(price, expected);

        route.oracles[0] = Oracle({source: WETH_OP_VELO_POOL, tokenIn: OP_ADDRESS, windowOrDecimalOffset: 3600, kind: OracleKind.Velo});

        uint256 price2 = oracleAggregator.fetchMultiHopPrice(route, 1e18);
        assertEq(price2, 838020130098509);
    }

    // velo stable pairs have a different pricing method
    function test_veloStable() public {
        OracleRoute memory route;
        route.oracles = new Oracle[](1);
        route.oracles[0] =
            Oracle({source: USDC_ERN_VELO_POOL, tokenIn: ERN_ADDRESS, windowOrDecimalOffset: 3600, kind: OracleKind.Velo});

        uint256 expected = 982575;

        uint256 price = oracleAggregator.fetchMultiHopPrice(route, 1e18);
        assertEq(price, expected);

        route.oracles[0] =
            Oracle({source: USDC_ERN_VELO_POOL, tokenIn: USDC_ADDRESS, windowOrDecimalOffset: 3600, kind: OracleKind.Velo});

        uint256 price2 = oracleAggregator.fetchMultiHopPrice(route, 1e6);
        assertEq(price2, 1017733222640936418);
    }

    function test_balancer() public {
        address VMEX = 0x6D2E5b8841a6Aa5f0f973436357f75D3Eeb93312;
        address VMEX_POOL = 0x4Dde571Dc66217a062e4B50f9b20c4D08b3245a0;
        OracleRoute memory route;

        route.oracles = new Oracle[](1);
        route.oracles[0] = Oracle({source: VMEX_POOL, tokenIn: VMEX, windowOrDecimalOffset: 3600, kind: OracleKind.Balancer});
        emit log_named_decimal_uint("price", oracleAggregator.fetchMultiHopPrice(route, 1e18), 18);

        route.oracles[0] = Oracle({source: VMEX_POOL, tokenIn: WETH_ADDRESS, windowOrDecimalOffset: 3600, kind: OracleKind.Balancer});
        emit log_named_decimal_uint("price", oracleAggregator.fetchMultiHopPrice(route, 1e18), 18);

        // check decimal normalization
        vm.mockCall(VMEX, abi.encodeWithSelector(ERC20.decimals.selector), abi.encode(6));

        route.oracles = new Oracle[](1);
        route.oracles[0] = Oracle({source: VMEX_POOL, tokenIn: VMEX, windowOrDecimalOffset: 3600, kind: OracleKind.Balancer});
        emit log_named_decimal_uint("price", oracleAggregator.fetchMultiHopPrice(route, 1e18), 18);

        route.oracles[0] = Oracle({source: VMEX_POOL, tokenIn: WETH_ADDRESS, windowOrDecimalOffset: 3600, kind: OracleKind.Balancer});
        emit log_named_decimal_uint("price", oracleAggregator.fetchMultiHopPrice(route, 1e18), 18);
    }

    /* function test_priceFeed() public {
        OracleRoute memory route;

        route.oracles = new Oracle[](1);
        route.oracles[0] = Oracle({source: PRICE_FEED, tokenIn: WBTC_ADDRESS, windowOrDecimalOffset: 0, kind: OracleKind.PriceFeed});

        uint256 price = oracleAggregator.fetchMultiHopPrice(route, 1e8);
        console.log("price", price);
    } */

    function test_twoPrices() public {
        OracleRoute[] memory _ernForUsdcAllOracles = new OracleRoute[](2);

        OracleRoute memory _veloOracle;
        _veloOracle.oracles = new Oracle[](1);
        _veloOracle.oracles[0] =
            Oracle({source: USDC_ERN_VELO_POOL, tokenIn: USDC_ADDRESS, windowOrDecimalOffset: 3600, kind: OracleKind.Velo});

        OracleRoute memory _uniV3Oracle;
        _uniV3Oracle.oracles = new Oracle[](1);
        _uniV3Oracle.oracles[0] =
            Oracle({source: USDC_ERN_UNIV3_POOL, tokenIn: USDC_ADDRESS, windowOrDecimalOffset: 3600, kind: OracleKind.UniV3});

        // OracleRoute memory _priceFeedOracle;
        // _priceFeedOracle.oracles = new Oracle[](1);
        // _priceFeedOracle.oracles[0] =
        //     Oracle({source: PRICE_FEED, tokenIn: WBTC_ADDRESS, windowOrDecimalOffset: 0, kind: OracleKind.PriceFeed});

        _ernForUsdcAllOracles[0] = _veloOracle;
        _ernForUsdcAllOracles[1] = _uniV3Oracle;
        // _ernForUsdcAllOracles[2] = _priceFeedOracle;

        uint256[] memory prices = oracleAggregator.fetchTwapPrices(_ernForUsdcAllOracles, 10_000 * 1e6);


        uint256 priceUniV3 = oracleAggregator.fetchMultiHopPrice(_uniV3Oracle, 1e10);
        uint256 priceVelo = oracleAggregator.fetchMultiHopPrice(_veloOracle, 1e10);

        console.log("priceVelo", priceVelo);
        console.log("prices1  ", prices[0]);

        console.log("priceUniV3", priceUniV3);
        console.log("prices2   ", prices[1]);
    }
    
    function test_chainLink() public {
        OracleRoute memory route;
        route.oracles = new Oracle[](1);
        route.oracles[0] = Oracle({source: 0x13e3Ee699D1909E989722E753853AE30b17e08c5, tokenIn: address(1), windowOrDecimalOffset: 12, kind: OracleKind.Chainlink});
        uint256 price = oracleAggregator.fetchMultiHopPrice(route, 1e6);
        console.log("price", price);
    }
}
