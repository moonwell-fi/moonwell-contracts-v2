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
        /// MOONBEAM
        _addAddress(
            "BORROW_SUPPLY_GUARDIAN",
            moonBeamChainId,
            0xc191A4db4E05e478778eDB6a201cb7F13A257C23 /// TODO add correct guantlet msig
        );
        /// MOON BASE
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
        /// BASE GOERLI
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
            0x3a9249d70dCb4A4E9ef4f3AF99a3A130452ec19B
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
            0x840725c0a903521cbA1C0020dBdf54Aa4Ae813A5
        );
        _addAddress("USDC", 84531, 0xFACD0Fc9A841A1E1b960a8E90755C4911C1Dd53A);
        _addAddress("WBTC", 84531, 0xE259C5C337cb78607D286d91d3D1663305e8CD30);
        _addAddress("cbETH", 84531, 0x7A455bf197cF61d33fc1Ae9F74a24D7A40231061);
        _addAddress(
            "wstETH",
            84531,
            0xBE812Ed32135929038B436f594D0835a97fFc12e
        );
        _addAddress(
            "cbETH_ORACLE",
            84531,
            0x45E62c1D07365c46631a4F2032c0e630CCA91c55
        );
        _addAddress(
            "wstETH_ORACLE",
            84531,
            0x3a52fB70713032B182F351829573a318a4f8E4E6
        );
        _addAddress(
            "MULTI_REWARD_DISTRIBUTOR",
            84531,
            0xd321f44038aF2234D6F37f5216820c8c3Aa7b5De
        );
        _addAddress(
            "COMPTROLLER",
            84531,
            0x6eb2bcBEAD4649279C88769316b9eD8A5578BF20
        );
        _addAddress(
            "UNITROLLER",
            84531,
            0x9B0f96C3a99C64d437AC0B901A28C1ea83e7A2e7
        );
        _addAddress(
            "MRD_PROXY",
            84531,
            0x35B5330DB1eff5C52e04f8F32a7FD5814c19593C
        );
        _addAddress(
            "MRD_PROXY_ADMIN",
            84531,
            0xc0af8FEC778be65eC5f2dE755c4253Ab057E9D78
        );
        _addAddress(
            "MTOKEN_IMPLEMENTATION",
            84531,
            0xD97DfBc72131B67E7518448162F233FDdE43B1b0
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_USDC",
            84531,
            0xC84105b1D809CF65B6DFaf2C044980cA37F5fb79
        );
        _addAddress(
            "MOONWELL_USDC",
            84531,
            0xA4Cb22C4bDE7FDBB20b05387dd45c875f18353Ab
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WETH",
            84531,
            0x7973bb764EF6fd10fBFc531CfcE0EcC88683E3C0
        );
        _addAddress(
            "MOONWELL_WETH",
            84531,
            0xB1c7730f7D2ba7FE80476F421e68FA846A187088
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WBTC",
            84531,
            0x71848131bDe3e45294fe9Cd54562358a7AC86203
        );
        _addAddress(
            "MOONWELL_WBTC",
            84531,
            0xd9D5c354063d96Af6d05eF733a53da5500a30bc6
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_cbETH",
            84531,
            0x2521Bde567F64143B47b065c479945208c60e1Ca
        );
        _addAddress(
            "MOONWELL_cbETH",
            84531,
            0x45442965DF9CA611cf59B524C899b6E4c4E2e14A
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_wstETH",
            84531,
            0x2e9edeDF20aaa3178Ba4884441BBa934066153Aa
        );
        _addAddress(
            "MOONWELL_wstETH",
            84531,
            0x475d693703E7c0D2f9Af2aBE53acE89F21f639Ac
        );
        _addAddress("WELL", 84531, 0x6295749d818E3a2caEe60b274700593ffBBdE1d7);
        _addAddress(
            "WETH_ROUTER",
            84531,
            0xc55138f18761BEC3c8d3Ea850D1dB3CfC760e240
        );
        _addAddress(
            "CHAINLINK_ORACLE",
            84531,
            0x8a318A4493f38567528d17B5E91A30BDFAA5Fd06
        );

        /// -----------------------------------------------

        /// -----------------------------------------------
        ///        BASE GOERLI CHAINLINK ORACLES
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
            0x43A720C2690B00Ae0a0F9E4b79ED24184D9e8F0A
        );

        /// ---------- base goerli deployment ----------



        _addAddress(
            "USDC",
            baseChainId,
            0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA
        );

        _addAddress(
            "WETH",
            baseChainId,
            0x4200000000000000000000000000000000000006
        );

        _addAddress(
            "cbETH",
            baseChainId,
            0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22
        );

        /// TODO add Guardian Multisig address on Base once we have it
        /// TODO add chainlink oracle addresses on Base once we have it
        /// stETHETH_ORACLE, wstETHstETH_ORACLE, cbETH_ORACLE, ETH_ORACLE, WBTC_ORACLE, USDC_ORACLE
        /// ADD WBTC, USDC, wstETH, cbETH, WELL
        /// TODO update mainnetMTokens.json and mainnetRewardStreams.json once we have the addresses
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
