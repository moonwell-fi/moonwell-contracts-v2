// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {DeployCypher} from "script/DeployCypher.s.sol";
import {CypherAutoLoad} from "@protocol/cypher/CypherAutoLoad.sol";
import {MoonwellERC4626} from "@protocol/4626/MoonwellERC4626.sol";
import {IMetaMorphoFactory} from "@protocol/morpho/IMetaMorphoFactory.sol";
import {IMetaMorpho, MarketParams} from "@protocol/morpho/IMetaMorpho.sol";
import {ERC4626RateLimitedAllowance} from "@protocol/cypher/ERC4626RateLimitedAllowance.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract CypherIntegrationTest is Test {
    using SafeCast for *;

    Addresses public addresses;
    CypherAutoLoad public autoLoad;
    ERC4626RateLimitedAllowance public limitedAllowance;
    IMetaMorpho public vault;
    ERC20 public underlying;

    bytes32 public constant CBETH_USDC_MARKET_ID =
        0xdba352d93a64b17c71104cbddc6aef85cd432322a1446b5b65163cbbc615cd0c;

    address public beneficiary;
    address public executor;

    function setUp() public {
        addresses = new Addresses();

        DeployCypher cypherDeployer = new DeployCypher();

        autoLoad = cypherDeployer.deployAutoLoad(addresses);

        limitedAllowance = cypherDeployer.deployERC4626RateLimitedAllowance(
            addresses,
            address(autoLoad)
        );

        underlying = ERC20(addresses.getAddress("USDC"));

        IMetaMorphoFactory factory = IMetaMorphoFactory(
            addresses.getAddress("META_MORPHO_FACTORY")
        );

        vault = IMetaMorpho(
            factory.createMetaMorpho(
                address(this),
                1 days,
                address(underlying),
                "MetaMorpho USDC",
                "mUSDC",
                keccak256(abi.encodePacked("mUSDC"))
            )
        );

        vm.label(address(vault), "MetaMorpho USDC");

        beneficiary = addresses.getAddress("CYPHER_BENEFICIARY");
        executor = addresses.getAddress("CYPHER_EXECUTOR");
    }

    function testExecutorCanWithdraw() public {
        uint128 bufferCap = 1_000_000e6;
        uint128 rateLimitPerSecond = 0.01e6;
        uint256 underlyingAmount = 1000e6;

        MarketParams memory params = MarketParams({
            loanToken: address(underlying),
            collateralToken: addresses.getAddress("cbETH"),
            oracle: addresses.getAddress("MORPHO_CHAINLINK_cbETH_ORACLE"),
            irm: addresses.getAddress("MORPHO_ADAPTIVE_CURVE_IRM"),
            lltv: 0.86e18
        });

        vault.submitCap(params, underlyingAmount * 100);

        vm.warp(block.timestamp + 1 days);

        vault.acceptCap(params);

        bytes32[] memory newSupplyQueue = new bytes32[](1);
        newSupplyQueue[0] = CBETH_USDC_MARKET_ID;
        vault.setSupplyQueue(newSupplyQueue);

        deal(address(underlying), address(this), underlyingAmount);
        underlying.approve(address(vault), underlyingAmount);
        vault.deposit(underlyingAmount, address(this));

        vault.approve(address(limitedAllowance), type(uint256).max);

        limitedAllowance.approve(address(vault), rateLimitPerSecond, bufferCap);

        uint256 receiverBalanceBefore = underlying.balanceOf(beneficiary);

        vm.prank(executor);
        autoLoad.debit(
            address(limitedAllowance),
            address(vault),
            address(this),
            underlyingAmount / 100
        );

        assertEq(
            receiverBalanceBefore + underlyingAmount / 100,
            underlying.balanceOf(beneficiary),
            "Wrong receiver balance after withdrawn"
        );
    }
}
