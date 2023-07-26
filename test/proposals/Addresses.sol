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

        _addAddress(
            "TEMPORAL_GOVERNOR",
            84531,
            0x2412fADb7C04C12882bE4bEd32346Ff503454Cc0
        );
        _addAddress("USDC", 84531, 0xA432EEb722cceB019846C848922836aD09155116);
        _addAddress("WETH", 84531, 0x0ff4De6183305cAdDA777c7b6058377E68040c89);
        _addAddress("WBTC", 84531, 0xf75E25fE4a190A8ACEfd25dC41EB368a78eecBfD);
        _addAddress("cbETH", 84531, 0xF5DE1DabbB427F649Db5E26f3BbD01cA32DB5719);
        _addAddress(
            "wstETH",
            84531,
            0x39C313879B2A5Db3F59e541Ba29935d9fDCf3649
        );
        _addAddress(
            "cbETH_ORACLE",
            84531,
            0x5B8284F6f5B9758E039B98c341912f0eeB25e9cB
        );
        _addAddress(
            "wstETH_ORACLE",
            84531,
            0x77392278F7e5b2eE28Ef0c90D82D5B509726b6f0
        );
        _addAddress(
            "MULTI_REWARD_DISTRIBUTOR",
            84531,
            0x83e9e0d2A6C3Db280E6AfDCF8Da28d59FE242c0e
        );
        _addAddress(
            "COMPTROLLER",
            84531,
            0xc4275B3B92a23de534510eED93e40362077E3018
        );
        _addAddress(
            "UNITROLLER",
            84531,
            0x5B3a097839c3B044b6ee66278F15c834e4c8C976
        );
        _addAddress(
            "MRD_PROXY",
            84531,
            0x69736bEA2B7071491ACE10d47b3AB06C04B16f43
        );
        _addAddress(
            "MRD_PROXY_ADMIN",
            84531,
            0xab7042E8216453Fb93813Ba06cEB465042e10e7E
        );
        _addAddress(
            "MTOKEN_IMPLEMENTATION",
            84531,
            0xc812Cc85d5b99Ff1bE9B71fe41742E29cf8996d6
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_USDC",
            84531,
            0xfbc8582131ba637fdC72fA76AD809f01753cEc35
        );
        _addAddress(
            "MOONWELL_USDC",
            84531,
            0x06505EcD20961d43dE8D32d78Ede58cbA08aE486
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WETH",
            84531,
            0x0F9fEa3A79dBb1958827585ea94DB4C8AeA0c577
        );
        _addAddress(
            "MOONWELL_WETH",
            84531,
            0x19D28495843724333A6B23b8949974ac6A6E4eA6
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WBTC",
            84531,
            0x42c28d3EC1df17FD1Ac554269EDE678D4DF79798
        );
        _addAddress(
            "MOONWELL_WBTC",
            84531,
            0x5b38517586d251D2864F9802FdfE47343547C2b1
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_cbETH",
            84531,
            0xa2F03bB061fDcd00664b48A77506487d212Db398
        );
        _addAddress(
            "MOONWELL_cbETH",
            84531,
            0x573C684D5782d8Fbf41031DEd2b8D313b5E26515
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_wstETH",
            84531,
            0x762c5b0C749026d6234189C8818dDDc718eAb515
        );
        _addAddress(
            "MOONWELL_wstETH",
            84531,
            0xBa5C5565BA434A0814938E76Bcb06eF2c38583aA
        );
        _addAddress("WELL", 84531, 0xe0ADcC5Ba9ADFE8d2c9fC9e0E79bEc3dF11f46E2);
        _addAddress(
            "WETH_ROUTER",
            84531,
            0x51daE5Db1eE85335b21bEf8661F90B1D5f141C28
        );
        _addAddress(
            "CHAINLINK_ORACLE",
            84531,
            0xcBf263b8d5a59656026117a10062AFF1bD1C7DB8
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
