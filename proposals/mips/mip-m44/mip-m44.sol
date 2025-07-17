//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {EIP20Interface} from "@protocol/EIP20Interface.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {IApi3ReaderProxy} from "@protocol/oracles/IApi3ReaderProxy.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {MOONBEAM_FORK_ID} from "@utils/ChainIds.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract mipm44 is HybridProposal {
    using ProposalActions for *;

    string public constant override name = "MIP-M44";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-m44/MIP-M44.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function build(Addresses addresses) public override {
        EIP20Interface token_xcDOT = EIP20Interface(
            MErc20(address(addresses.getAddress("mxcDOT"))).underlying()
        );
        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setFeed(string,address)",
                token_xcDOT.symbol(),
                addresses.getAddress("API3_DOT_USD_FEED")
            ),
            "Set price feed for xcDOT"
        );

        EIP20Interface token_FRAX = EIP20Interface(
            MErc20(address(addresses.getAddress("mFRAX"))).underlying()
        );
        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setFeed(string,address)",
                token_FRAX.symbol(),
                addresses.getAddress("API3_FRAX_USD_FEED")
            ),
            "Set price feed for FRAX"
        );

        EIP20Interface token_xcUSDC = EIP20Interface(
            MErc20(address(addresses.getAddress("mxcUSDC"))).underlying()
        );
        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setFeed(string,address)",
                token_xcUSDC.symbol(),
                addresses.getAddress("API3_USDC_USD_FEED")
            ),
            "Set price feed for xcUSDC"
        );

        EIP20Interface token_xcUSDT = EIP20Interface(
            MErc20(address(addresses.getAddress("mxcUSDT"))).underlying()
        );
        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setFeed(string,address)",
                token_xcUSDT.symbol(),
                addresses.getAddress("API3_USDT_USD_FEED")
            ),
            "Set price feed for xcUSDT"
        );

        EIP20Interface token_ETHwh = EIP20Interface(
            MErc20(address(addresses.getAddress("mETHwh"))).underlying()
        );
        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setFeed(string,address)",
                token_ETHwh.symbol(),
                addresses.getAddress("API3_ETH_USD_FEED")
            ),
            "Set price feed for ETHwh"
        );

        EIP20Interface token_WBTCwh = EIP20Interface(
            MErc20(address(addresses.getAddress("MOONWELL_mWBTC"))).underlying()
        );
        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setFeed(string,address)",
                token_WBTCwh.symbol(),
                addresses.getAddress("API3_BTC_USD_FEED")
            ),
            "Set price feed for MOONWELL_mWBTC"
        );

        EIP20Interface token_USDCwh = EIP20Interface(
            MErc20(address(addresses.getAddress("mUSDCwh"))).underlying()
        );
        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setFeed(string,address)",
                token_USDCwh.symbol(),
                addresses.getAddress("API3_USDC_USD_FEED")
            ),
            "Set price feed for USDCwh"
        );
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(primaryForkId());

        ChainlinkOracle oracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );

        // Reusable variables
        AggregatorV3Interface feed;
        IApi3ReaderProxy reader;
        string memory symbol;
        address expectedFeed;
        int256 api3Price;
        int256 chainlinkPrice;

        // xcDOT
        symbol = ERC20(MErc20(addresses.getAddress("mxcDOT")).underlying())
            .symbol();
        expectedFeed = addresses.getAddress("API3_DOT_USD_FEED");
        feed = oracle.getFeed(symbol);
        assertEq(address(feed), expectedFeed, "xcDOT feed not set");
        reader = IApi3ReaderProxy(expectedFeed);
        (api3Price, ) = reader.read();
        (, chainlinkPrice, , , ) = feed.latestRoundData();
        assertEq(
            uint256(chainlinkPrice),
            uint256(api3Price),
            "Wrong Price xcDOT"
        );

        // mFRAX
        symbol = ERC20(MErc20(addresses.getAddress("mFRAX")).underlying())
            .symbol();
        expectedFeed = addresses.getAddress("API3_FRAX_USD_FEED");
        feed = oracle.getFeed(symbol);
        assertEq(address(feed), expectedFeed, "mFRAX feed not set");
        reader = IApi3ReaderProxy(expectedFeed);
        (api3Price, ) = reader.read();
        (, chainlinkPrice, , , ) = feed.latestRoundData();
        assertEq(
            uint256(chainlinkPrice),
            uint256(api3Price),
            "Wrong Price mFRAX"
        );

        // xcUSDC
        symbol = ERC20(MErc20(addresses.getAddress("mxcUSDC")).underlying())
            .symbol();
        expectedFeed = addresses.getAddress("API3_USDC_USD_FEED");
        feed = oracle.getFeed(symbol);
        assertEq(address(feed), expectedFeed, "xcUSDC feed not set");
        reader = IApi3ReaderProxy(expectedFeed);
        (api3Price, ) = reader.read();
        (, chainlinkPrice, , , ) = feed.latestRoundData();
        assertEq(
            uint256(chainlinkPrice),
            uint256(api3Price),
            "Wrong Price xcUSDC"
        );

        // xcUSDT
        symbol = ERC20(MErc20(addresses.getAddress("mxcUSDT")).underlying())
            .symbol();
        expectedFeed = addresses.getAddress("API3_USDT_USD_FEED");
        feed = oracle.getFeed(symbol);
        assertEq(address(feed), expectedFeed, "xcUSDT feed not set");
        reader = IApi3ReaderProxy(expectedFeed);
        (api3Price, ) = reader.read();
        (, chainlinkPrice, , , ) = feed.latestRoundData();
        assertEq(
            uint256(chainlinkPrice),
            uint256(api3Price),
            "Wrong Price xcUSDT"
        );

        // mETHwh
        symbol = ERC20(MErc20(addresses.getAddress("mETHwh")).underlying())
            .symbol();
        expectedFeed = addresses.getAddress("API3_ETH_USD_FEED");
        feed = oracle.getFeed(symbol);
        assertEq(address(feed), expectedFeed, "mETHwh feed not set");
        reader = IApi3ReaderProxy(expectedFeed);
        (api3Price, ) = reader.read();
        (, chainlinkPrice, , , ) = feed.latestRoundData();
        assertEq(
            uint256(chainlinkPrice),
            uint256(api3Price),
            "Wrong Price mETHwh"
        );

        // MOONWELL_mWBTC
        symbol = ERC20(
            MErc20(addresses.getAddress("MOONWELL_mWBTC")).underlying()
        ).symbol();
        expectedFeed = addresses.getAddress("API3_BTC_USD_FEED");
        feed = oracle.getFeed(symbol);
        assertEq(address(feed), expectedFeed, "MOONWELL_mWBTC feed not set");
        reader = IApi3ReaderProxy(expectedFeed);
        (api3Price, ) = reader.read();
        (, chainlinkPrice, , , ) = feed.latestRoundData();
        assertEq(
            uint256(chainlinkPrice),
            uint256(api3Price),
            "Wrong Price MOONWELL_mWBTC"
        );

        // mUSDCwh
        symbol = ERC20(MErc20(addresses.getAddress("mUSDCwh")).underlying())
            .symbol();
        expectedFeed = addresses.getAddress("API3_USDC_USD_FEED");
        feed = oracle.getFeed(symbol);
        assertEq(address(feed), expectedFeed, "mUSDCwh feed not set");
        reader = IApi3ReaderProxy(expectedFeed);
        (api3Price, ) = reader.read();
        (, chainlinkPrice, , , ) = feed.latestRoundData();
        assertEq(
            uint256(chainlinkPrice),
            uint256(api3Price),
            "Wrong Price mUSDCwh"
        );
    }
}
