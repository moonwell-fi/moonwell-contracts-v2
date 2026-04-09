// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/console.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ChainlinkOracleConfigs} from "@proposals/ChainlinkOracleConfigs.sol";
import {BASE_FORK_ID, OPTIMISM_FORK_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {IChainlinkOracle} from "@protocol/interfaces/IChainlinkOracle.sol";
import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {ChainlinkOEVMorphoWrapper} from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {OEVProtocolFeeRedeemer} from "@protocol/OEVProtocolFeeRedeemer.sol";

/// @notice MIP-B57: Revert the configured oracle for cbETH market on Base from the OEV wrapper to cbETH_COMPOSITE_ORACLE
contract mipb57 is HybridProposal, ChainlinkOracleConfigs, Networks {
    using ChainIds for uint256;
    string public constant override name = "MIP-B57";

    int256 public oraclePriceBefore;

    constructor() {
        _setProposalDescription(
            bytes(vm.readFile("./proposals/mips/mip-b57/b57.md"))
        );
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function beforeSimulationHook(Addresses addresses) public override {
        vm.selectFork(BASE_FORK_ID);
        (, oraclePriceBefore, , , ) = AggregatorV3Interface(
            addresses.getAddress("cbETH_COMPOSITE_ORACLE")
        ).latestRoundData();
    }

    function build(Addresses addresses) public override {
        address chainlinkOracle = addresses.getAddress("CHAINLINK_ORACLE");
        string memory symbol = "cbETH";

        _pushAction(
            chainlinkOracle,
            abi.encodeWithSignature(
                "setFeed(string,address)",
                symbol,
                addresses.getAddress("cbETH_COMPOSITE_ORACLE")
            ),
            string.concat("Set feed to cbETH_COMPOSITE_ORACLE for ", symbol)
        );
    }

    function validate(Addresses addresses, address) public view override {
        address configured = address(
            ChainlinkOracle(addresses.getAddress("CHAINLINK_ORACLE")).getFeed(
                "cbETH"
            )
        );
        address expected = addresses.getAddress("cbETH_COMPOSITE_ORACLE");
        assertEq(
            configured,
            expected,
            "cbETH feed not reverted to cbETH_COMPOSITE_ORACLE"
        );

        // WETH price should be ~15% same as cbETH price
        address otherConfigured = address(
            ChainlinkOracle(addresses.getAddress("CHAINLINK_ORACLE")).getFeed(
                "WETH"
            )
        );

        (, int256 price, , , ) = AggregatorV3Interface(configured)
            .latestRoundData();
        uint8 priceDecimals = AggregatorV3Interface(configured).decimals();

        (, int256 otherPrice, , , ) = AggregatorV3Interface(otherConfigured)
            .latestRoundData();
        uint8 otherDecimals = AggregatorV3Interface(otherConfigured).decimals();

        /// normalize both prices to 18 decimals before comparing
        uint256 normalizedPrice = uint256(price) * 10 ** (18 - priceDecimals);
        uint256 normalizedOtherPrice = uint256(otherPrice) *
            10 ** (18 - otherDecimals);

        assertApproxEqRel(
            normalizedPrice,
            normalizedOtherPrice,
            0.15e18,
            "cbETH and WETH prices deviated more than 15%"
        );

        // configured cbETH price should roughly the same as the before simulation price
        assertApproxEqRel(
            uint256(price),
            uint256(oraclePriceBefore),
            0.01e18,
            "cbETH price deviated from before simulation price"
        );
    }
}
