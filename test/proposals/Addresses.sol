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
            0xFD47739E8B8f2c3523c4F98405C373120a11ABA4
        );
        _addAddress("USDC", 84531, 0xA2E7CF5C3B659D33D3D5bf7810564974Ea874Aa7);
        _addAddress("WETH", 84531, 0x737975350808f0975007d62555f52F8236A630fb);
        _addAddress("WBTC", 84531, 0x9988614F302e0506FE11CF56229023BdDdc99663);
        _addAddress("cbETH", 84531, 0xcDA2600818488C2A9d4cecAc6CE0298De2FE65A4);
        _addAddress(
            "wstETH",
            84531,
            0x21961e7FF9f87cAbE1400deb8Cf8823944018006
        );
        _addAddress(
            "cbETH_ORACLE",
            84531,
            0xA42E50B8F0BE5cFF1B965B5ee5C5864f314F7F0F
        );
        _addAddress(
            "wstETH_ORACLE",
            84531,
            0x2F086a1Ad900767d76C853DAC427d570d7189c1F
        );
        _addAddress(
            "MULTI_REWARD_DISTRIBUTOR",
            84531,
            0x152eD2d9a31face4E031f0AF458D82589a3C5dcb
        );
        _addAddress(
            "COMPTROLLER",
            84531,
            0x13a6572798da30bF7779C52ff0fEB1C355313516
        );
        _addAddress(
            "UNITROLLER",
            84531,
            0x5046404DEcE336F2D6FEc94AFF3E55EE4Ea154B5
        );
        _addAddress(
            "MRD_PROXY",
            84531,
            0xa3e44539833075DC6847DC6446A884F9EB06159d
        );
        _addAddress(
            "MRD_PROXY_ADMIN",
            84531,
            0xc5414c598223De46A57c6Ca73c6637490f07d127
        );
        _addAddress(
            "MTOKEN_IMPLEMENTATION",
            84531,
            0x267E65E9df3E9E95078b360c26F6729AE954F44d
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_USDC",
            84531,
            0xD25310e43B9112835B9eCC44FdbD757B99C5aC78
        );
        _addAddress(
            "MOONWELL_USDC",
            84531,
            0xF2994BbAB35AeCfD3DcC26559Fa8c24fAb5A5862
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WETH",
            84531,
            0x7b124f2f442e39Ff6EA2e07a9e826bF3EB63a1af
        );
        _addAddress(
            "MOONWELL_WETH",
            84531,
            0x91e1B7308b5477eD6D2a0B9E12a1B737Ba991d74
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WBTC",
            84531,
            0x246Fa7472ddF3334b1f5187558e2798858bd694a
        );
        _addAddress(
            "MOONWELL_WBTC",
            84531,
            0x49FCf1b315b3eDc6fF65DD6889A8cdF2D4308387
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_cbETH",
            84531,
            0xf1b137DB523980dC9068aBEa5EBB2Cb6e43Bf6cA
        );
        _addAddress(
            "MOONWELL_cbETH",
            84531,
            0xA7E6719009d6a3BB412D530d50f399495d233797
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_wstETH",
            84531,
            0xC6bdEe41ac7ace77b9084B7174Fc59219b2A7459
        );
        _addAddress(
            "MOONWELL_wstETH",
            84531,
            0x2fdC09311b1ea0aBb44E8580B4e7dAcCFf34e6E5
        );
        _addAddress("WELL", 84531, 0xbcA0EE692fD51a4b46269cDf024CCE9920b2AD2A);
        _addAddress(
            "WETH_ROUTER",
            84531,
            0xbb9060edfE28C53890168937835e02438772D513
        );
        _addAddress(
            "CHAINLINK_ORACLE",
            84531,
            0x40B488cA4C1a5279380692f8e79F3855d6c19Bb5
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
