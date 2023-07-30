// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";

contract Addresses is Test, ChainIds {
    /// mapping for a network such as arbitrum
    mapping(string => mapping(uint256 => address)) _addresses;
    uint256 private constant localChainId = 31337;

    uint256 chainId;

    struct RecordedAddress {
        string name;
        address addr;
    }
    RecordedAddress[] private recordedAddresses;

    constructor() {
        chainId = block.chainid;

        /// ----------------- BORROW_SUPPLY_GUARDIAN -----------------

        /// LOCAL
        _addAddress(
            "BORROW_SUPPLY_GUARDIAN",
            localChainId,
            0xc191A4db4E05e478778eDB6a201cb7F13A257C23 /// Random address is borrow supply guardian
        );
        /// MOONBASE
        _addAddress(
            "BORROW_SUPPLY_GUARDIAN",
            moonBeamChainId,
            0xc191A4db4E05e478778eDB6a201cb7F13A257C23 /// TODO add correct guantlet msig
        );
        /// BASE
        _addAddress(
            "BORROW_SUPPLY_GUARDIAN",
            moonBaseChainId, /// TODO replace with guantlet multisig address
            0xc191A4db4E05e478778eDB6a201cb7F13A257C23 /// TODO add correct guantlet msig
        );
        /// GOERLI
        _addAddress(
            "BORROW_SUPPLY_GUARDIAN",
            goerliChainId,
            0xc191A4db4E05e478778eDB6a201cb7F13A257C23 /// EOA owner
        );
        /// GOERLI
        _addAddress(
            "BORROW_SUPPLY_GUARDIAN",
            baseGoerliChainId,
            0xc191A4db4E05e478778eDB6a201cb7F13A257C23 /// EOA owner
        );
        /// GOERLI
        _addAddress(
            "WETH",
            baseGoerliChainId,
            0x4200000000000000000000000000000000000006
        );

        //// actual moonbeam timelock deployment
        _addAddress(
            "MOONBEAM_TIMELOCK",
            moonBeamChainId,
            0x43A720C2690B00Ae0a0F9E4b79ED24184D9e8F0A /// EOA owner
        );

        /// sepolia

        /// -----------------------------------------------
        /// -------- DO NOT CHANGE BELOW THIS LINE --------
        /// -----------------------------------------------

        _addAddress(
            "MOONBEAM_TIMELOCK",
            sepoliaChainId,
            0x29353c2e5dCDF7dE3c92E81325B0C54Cb451750E /// EOA owner
        );
        _addAddress(
            "WORMHOLE_CORE",
            sepoliaChainId,
            0x4a8bc80Ed5a4067f1CCf107057b8270E0cC11A78
        );

        /// ----------------------------------
        /// ------------ WORMHOLE CORE ------------
        /// ----------------------------------

        _addAddress( /// base goerli
            "WORMHOLE_CORE",
            baseGoerliChainId,
            0x23908A62110e21C04F3A4e011d24F901F911744A
        );

        _addAddress( /// moonbase
            "WORMHOLE_CORE",
            moonBaseChainId,
            0xa5B7D85a8f27dd7907dc8FdC21FA5657D5E2F901
        );

        /// ----------------------------------
        /// ----------------------------------
        /// ----------------------------------

        _addAddress(
            "PAUSE_GUARDIAN",
            baseGoerliChainId,
            0xc191A4db4E05e478778eDB6a201cb7F13A257C23
        );

        _addAddress(
            "PAUSE_GUARDIAN",
            moonBaseChainId,
            0xc191A4db4E05e478778eDB6a201cb7F13A257C23
        );

        /// -----------------------------------------------
        /// -------- CHANGE ALLOWED BELOW THIS LINE -------
        /// -----------------------------------------------

        /// ---------- base goerli deployment ----------
        _addAddress(
            "TEMPORAL_GOVERNOR",
            84531,
            0x743E30cD3E05822E276C072Dc97cDD5c61155a5B
        );
        _addAddress("USDC", 84531, 0xE1722B4dB98dF4098E6DCF2601Ef44ae34d37188);
        _addAddress("WBTC", 84531, 0xdBD73e4e83F387fE0915097Cd3366a0A5EE2FfF2);
        _addAddress(
            "cbETH",
            84531,
            0xA4278EA171700CB7AB5298a0781784397eBBcA0a
        );
        _addAddress(
            "wstETH",
            84531,
            0xf55fe6d1A6285C7469ecfbE6bE9CBa3a83d0f8c6
        );
        _addAddress(
            "MULTI_REWARD_DISTRIBUTOR",
            84531,
            0xC63a91dD858A1000424B806aB1F4625cA99b61d4
        );
        _addAddress(
            "COMPTROLLER",
            84531,
            0x6010A82e28b6cf01629920EF37752F46ad23F2b8
        );
        _addAddress(
            "UNITROLLER",
            84531,
            0x93fbB5bd70357DdDB69F3F9e45553cb853d030D7
        );
        _addAddress(
            "MRD_PROXY",
            84531,
            0xe21B4741E78467c78D98b4B70b26A08b8A189FA9
        );
        _addAddress(
            "MRD_PROXY_ADMIN",
            84531,
            0x7E1A78A6390ef76339816B185F4B1E5eEb28fE13
        );
        _addAddress(
            "MTOKEN_IMPLEMENTATION",
            84531,
            0x692236083b0696c5603712AC9Cd0dd5478F25bdE
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_USDC",
            84531,
            0xEae267908EE0e9794eaEC955a9d5Ee6F9A98Db73
        );
        _addAddress(
            "MOONWELL_USDC",
            84531,
            0xc9b81D60593E5940c3b4A3F089a203ca77E3DD3b
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WETH",
            84531,
            0x64b726A8DeD4438EA7CAcf43CaFa9783A866b36c
        );
        _addAddress(
            "MOONWELL_WETH",
            84531,
            0x7ad8bf72B8ACD7E00989837d88F891309c19067D
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WBTC",
            84531,
            0x6F4608B02fD92d2c0a65425a16C3bdaFfb2D1d79
        );
        _addAddress(
            "MOONWELL_WBTC",
            84531,
            0x0CBFCcdB07e4e8BE1e9c2c07a42F9547819a0f41
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_cbETH",
            84531,
            0x0D36dA9C2bd3d6D3A507F15345D9ba27e62302Ab
        );
        _addAddress(
            "MOONWELL_cbETH",
            84531,
            0xd9E4Ca97A10C53DcFFd55f3fd54dde972C8539d1
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_wstETH",
            84531,
            0x3d752559B103d909c7aaF3E2B86Be5635392Fd99
        );
        _addAddress(
            "MOONWELL_wstETH",
            84531,
            0xc0d99f45cCbB0dAA337671311D6d2EA19DD84430
        );
        _addAddress(
            "WETH_ROUTER",
            84531,
            0xc88ac8f296c438bd2472733131a490A792FEA640
        );
        _addAddress(
            "CHAINLINK_ORACLE",
            84531,
            0x004E1d0DEc7BE21886B193262B0C63f943AD6141
        );

        /// -----------------------------------------------
        ///            BASE GOERLI Contracts
        /// -----------------------------------------------

        /// ORACLES
        _addAddress(
            "USDC_ORACLE",
            84531,
            0xb85765935B4d9Ab6f841c9a00690Da5F34368bc0
        );
        _addAddress(
            "ETH_ORACLE",
            84531,
            0xcD2A119bD1F7DF95d706DE6F2057fDD45A0503E2
        );
        _addAddress(
            "WBTC_ORACLE",
            84531,
            0xAC15714c08986DACC0379193e22382736796496f
        );

        /// GOERLI BASE

        _addAddress(
            "MOONBEAM_TIMELOCK",
            baseGoerliChainId,
            0x43A720C2690B00Ae0a0F9E4b79ED24184D9e8F0A //// TODO Luke to fill in timelock address on Moonbase and uncomment
        );

        /// TODO add WETH and Guardian Multisig address on Base once we have it
    }

    /// @notice add an address for a specific chainId
    function _addAddress(
        string memory name,
        uint256 _chainId,
        address addr
    ) private {
        _addresses[name][_chainId] = addr;
        vm.label(addr, name);
    }

    function _addAddress(string memory name, address addr) private {
        _addresses[name][chainId] = addr;
        vm.label(addr, name);
    }

    function getAddress(string memory name) public view returns (address) {
        return _addresses[name][chainId];
    }

    function getAddress(
        string memory name,
        uint256 _chainId
    ) public view returns (address) {
        return _addresses[name][_chainId];
    }

    function addAddress(string memory name, address addr) public {
        _addAddress(name, addr);

        recordedAddresses.push(RecordedAddress({name: name, addr: addr}));
    }

    function resetRecordingAddresses() external {
        delete recordedAddresses;
    }

    function getRecordedAddresses()
        external
        view
        returns (string[] memory names, address[] memory addresses)
    {
        names = new string[](recordedAddresses.length);
        addresses = new address[](recordedAddresses.length);
        for (uint256 i = 0; i < recordedAddresses.length; i++) {
            names[i] = recordedAddresses[i].name;
            addresses[i] = recordedAddresses[i].addr;
        }
    }
}
