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

        /// WORMHOLE
        _addAddress(
            "WORMHOLE_CORE",
            baseGoerliChainId,
            0xA31aa3FDb7aF7Db93d18DDA4e19F811342EDF780
        );

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

        _addAddress(
            "TEMPORAL_GOVERNOR",
            11155111,
            0x0E173860E6F80C735f5DFE6354c9Ee4aE5Dc60E1
        );
        _addAddress(
            "USDC",
            11155111,
            0xD3bc55237Fea3f11643C95e766358484582F466A
        );
        _addAddress(
            "WETH",
            11155111,
            0xDa150F475DA060C59554dFbED16C6c53991A28Ca
        );
        _addAddress(
            "COMPTROLLER",
            11155111,
            0x084C3828ef96247dE4b48DB349C7B93Bb3918281
        );
        _addAddress(
            "UNITROLLER",
            11155111,
            0x31678AB506A672453D1235040a6Ad1776DB75E1D
        );
        _addAddress(
            "MULTI_REWARD_DISTRIBUTOR",
            11155111,
            0xAb5be0947E31c89BfdE5659a82267DbC27840DcE
        );
        _addAddress(
            "MRD_PROXY",
            11155111,
            0xd0C931730Dd05c13003B1B52B4459521B42fC061
        );
        _addAddress(
            "MRD_PROXY_ADMIN",
            11155111,
            0x17833e0C5633A71f64C33F7C81170dB256E4257A
        );
        _addAddress(
            "JUMP_RATE_IRM",
            11155111,
            0x47fdDe91A305bD2dF3Ac8a179c909D1cB30e4c84
        );
        _addAddress(
            "MTOKEN_IMPLEMENTATION",
            11155111,
            0x9d728fE8B7388D28b2B11E9B3f96Ef73ae1b3f57
        );
        _addAddress(
            "MOONWELL_USDC",
            11155111,
            0x682E7b16C21FE5b8F4e578da90870347f181Fb3c
        );
        _addAddress(
            "MOONWELL_WETH",
            11155111,
            0xbf08A960B7443E971ea9a0173B95FE31E946f611
        );
        _addAddress(
            "WETH_ROUTER",
            11155111,
            0x37Afc3BEe22B5CF23fD14B026e6861B50a90CE42
        );
        _addAddress(
            "CHAINLINK_ORACLE",
            11155111,
            0xBdD7E56E456583cfdc2Be122CfD6C8321D7fBF89
        );

        /// ---------- base goerli deployment ----------

        _addAddress("USDC", 84531, 0xcF66301FfFe00b27C9ed869B431dC06bE63102f0);
        _addAddress("WETH", 84531, 0x3e0e24b307388C82781080C4C0a844C707779c37);
        _addAddress("WBTC", 84531, 0xc4A363d8347818AD672005A64E92141F63878D81);
        _addAddress(
            "TEMPORAL_GOVERNOR",
            84531,
            0x36d1CCd52b7DF66b9038728540A1bB558902A364
        );
        _addAddress(
            "MULTI_REWARD_DISTRIBUTOR",
            84531,
            0xc3413Af985d258de265014Cc4684091cb7e4ebB5
        );
        _addAddress(
            "COMPTROLLER",
            84531,
            0xC4f7b614fe1ceF2f5bcecf5ABB6f84f36E7d54A1
        );
        _addAddress(
            "UNITROLLER",
            84531,
            0xE7074819f2418E553a07450eEd3Bb089207aB0a4
        );
        _addAddress(
            "MRD_PROXY",
            84531,
            0xA09c095735c0BaEEfC7F60E198edec34390A615C
        );
        _addAddress(
            "MRD_PROXY_ADMIN",
            84531,
            0x663650b1C311438313285D9Ebf9b937C0664254d
        );
        _addAddress(
            "MTOKEN_IMPLEMENTATION",
            84531,
            0x36e2f6a92FF24164010333fADc6bF50CF162dC0D
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_USDC",
            84531,
            0xbEA29A9704c0Bcbc0e1124E103bea5353fbE5b1D
        );
        _addAddress(
            "MOONWELL_USDC",
            84531,
            0xfd693042E524284796226234c4878F9b790Ef6C2
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WETH",
            84531,
            0x152DEDB508bE6F5c050f44Fb5AefcA150CD7eB34
        );
        _addAddress(
            "MOONWELL_WETH",
            84531,
            0x1376a2d851209cb4EcA0288C8d4e10c3C67526F7
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WBTC",
            84531,
            0x8eb6176Aee8cE5B67b07f1f6fa4f910123dCD3B8
        );
        _addAddress(
            "MOONWELL_WBTC",
            84531,
            0x6FaEA4BD6FecaBA689bd0Eb678b34584Fe3C3772
        );
        _addAddress(
            "WETH_ROUTER",
            84531,
            0xDdEbC7CB8Bd866F7f879465A97c7fc459a269AE8
        );
        _addAddress(
            "CHAINLINK_ORACLE",
            84531,
            0xf7E1F609a4EBF0B0e38bBDb1D6a1f637d25679D0
        );

        /// TODO add moonwell contracts

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
