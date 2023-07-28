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
            0xe8d2B1462C59F527B2C888772A39dbE0Fba4f8b6
        );
        _addAddress("USDC", 84531, 0xD771E77Dd0bC4d60263E0d461c3760D17D456fd6);
        _addAddress("WETH", 84531, 0x431d95E69c50b18fb4e8234C5b9F2f1bb96527a0);
        _addAddress("WBTC", 84531, 0xB31D97a5523cBD1c68f18f45d0f983515E8AD4B2);
        _addAddress("cbETH", 84531, 0x2963B4F88C65e136a18F45F67Df4246fB2Bae944);
        _addAddress(
            "wstETH",
            84531,
            0x8675AB2d8fE76CC628a583b54F709740FDaaaC58
        );
        _addAddress(
            "cbETH_ORACLE",
            84531,
            0x6d3Ef2Cd27d53f90cA7A4bd126FCc1C7664047BA
        );
        _addAddress(
            "wstETH_ORACLE",
            84531,
            0xe8a88C6CD2FD391cF15DA8F81Ae84e4662329C17
        );
        _addAddress(
            "MULTI_REWARD_DISTRIBUTOR",
            84531,
            0x8E6b1e292a04f7EF5B5C2C25ED66D71C4F8d902C
        );
        _addAddress(
            "COMPTROLLER",
            84531,
            0x532eA691cb62500e59441250aCAbAd822ba382B2
        );
        _addAddress(
            "UNITROLLER",
            84531,
            0xa1939Fcf6aA77a68a1f55Ff759c8Fe6a0eC59020
        );
        _addAddress(
            "MRD_PROXY",
            84531,
            0xF9b79cBb06D0B32F23a6c0Db2D34adDbAE0c92F0
        );
        _addAddress(
            "MRD_PROXY_ADMIN",
            84531,
            0x427aF102750f65dfBA69255a9a7a3C7c9E83E0E0
        );
        _addAddress(
            "MTOKEN_IMPLEMENTATION",
            84531,
            0xe21eB69e30a544860aD47Ce92d1D5c51e78528DB
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_USDC",
            84531,
            0xd1E661964e6E179df0125ea49A4c0fC0b5C0AA2C
        );
        _addAddress(
            "MOONWELL_USDC",
            84531,
            0x4016eC004869E35f24B061D27Ca6810A12f80Cfe
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WETH",
            84531,
            0xA42b23AF1fBdca21f89b745AFB87Bf3123C9F215
        );
        _addAddress(
            "MOONWELL_WETH",
            84531,
            0xc71Ed236b67576cf43e2Eb1c961559f31213404b
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WBTC",
            84531,
            0x99ecF6C7C1E52E2a4Fd53D2a929Eb0020F675A13
        );
        _addAddress(
            "MOONWELL_WBTC",
            84531,
            0xBa31280CBd9E4B48B78DEcaDcb850bfd50659c4f
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_cbETH",
            84531,
            0x41bcfF1915D74ccC88aD195e00A29D71D14CB034
        );
        _addAddress(
            "MOONWELL_cbETH",
            84531,
            0x8C3270FeC76c99c7C07926ed76229C91204F9069
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_wstETH",
            84531,
            0x0533A45538E6774dB3AE7a7097d6ab2b19fFd2b0
        );
        _addAddress(
            "MOONWELL_wstETH",
            84531,
            0xd0096B9d6B817EA13b6b98d8b2527C16A093256c
        );
        _addAddress("WELL", 84531, 0xF72741e0F01Af32863f23a1245Cd59d67CDAD406);
        _addAddress(
            "WETH_ROUTER",
            84531,
            0x69d8822ce288059E91aDb427d0Ce0BCa53C6a707
        );
        _addAddress(
            "CHAINLINK_ORACLE",
            84531,
            0x3C74247d043689D58e8CacE181097Ba0fB2F1098
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
