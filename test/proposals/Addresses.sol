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
            0x491a706b5c67D0AFd6d47D598C48D742EA81224B
        );
        _addAddress("USDC", 84531, 0x9437D72632D65eD3555dBf14Bb073b3aD51b7D11);
        _addAddress("WBTC", 84531, 0xD9F71201D872836fE9E1cCc975Ed2e42F65c675F);
        _addAddress("cbETH", 84531, 0x7cb221de6ebb6f82b698bb758c55E895A819Be91);
        _addAddress(
            "wstETH",
            84531,
            0x093282bac66E5c99cDD9a89127b5F07CD13726ff
        );
        _addAddress(
            "cbETH_ORACLE",
            84531,
            0xA30872b4a4Fd90F331403BA78f034D121a5E68A6
        );
        _addAddress(
            "wstETH_ORACLE",
            84531,
            0xA4C50a6c71193c777d9F47e53dCF51d77050700C
        );
        _addAddress(
            "MULTI_REWARD_DISTRIBUTOR",
            84531,
            0x904611A9aDE4616F6995F74bDE54c5C753BBb5f6
        );
        _addAddress(
            "COMPTROLLER",
            84531,
            0x072D6B177929D4733ef372234a8eAfC1182936Ab
        );
        _addAddress(
            "UNITROLLER",
            84531,
            0x76A5f69c1463E246a5f7e4B0ff77837E14632f91
        );
        _addAddress(
            "MRD_PROXY",
            84531,
            0x256E87D70008bAD43906577D3Fd5000c48C7EFdd
        );
        _addAddress(
            "MRD_PROXY_ADMIN",
            84531,
            0x7fc8612C04C56211a4a1AC1F1BCAD67A2022538b
        );
        _addAddress(
            "MTOKEN_IMPLEMENTATION",
            84531,
            0xFF1AB71D92c1bA1d9fBDb5C8b44304bedD415F65
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_USDC",
            84531,
            0x2aFB1F22cA6724c988B9fc6E06A23B1BE6C480A2
        );
        _addAddress(
            "MOONWELL_USDC",
            84531,
            0x758B0dC9B4FD6dF4254AED781E45e29F286b8a66
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WETH",
            84531,
            0x3429FEF13159b86562207b5a35E5f09DE26226C6
        );
        _addAddress(
            "MOONWELL_WETH",
            84531,
            0x35da0D92b9C5955ff6306886A00Ebbb380B27A61
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WBTC",
            84531,
            0x2B7d7ef70FAbECdb548E358ecdFf67A04DCB6332
        );
        _addAddress(
            "MOONWELL_WBTC",
            84531,
            0x6015dbBCBd736a2B713946823ee7799125a1b3Ac
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_cbETH",
            84531,
            0x55af06bc23858f8e4070629FFfbf9DD75Ef1e45C
        );
        _addAddress(
            "MOONWELL_cbETH",
            84531,
            0x7078F2d9de0B5CbAebAdb9F0e5a94281006Ff27c
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_wstETH",
            84531,
            0x53AD167aa94CEc249Af4dE59abA1787E706e449B
        );
        _addAddress(
            "MOONWELL_wstETH",
            84531,
            0x7aE810995dB8656d035e0703b44152B9F0F965f3
        );
        _addAddress("WELL", 84531, 0xD8d10a120FF9F754bf8EB9dd82fe8F85C79E6054);
        _addAddress(
            "WETH_ROUTER",
            84531,
            0x3C7A684546d729C61948e09f146cD8a6D3B8567E
        );
        _addAddress(
            "CHAINLINK_ORACLE",
            84531,
            0x472688624d9b11dE33792843Fa5AB0A29d064d44
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
