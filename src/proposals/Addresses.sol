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

        _addAddress(
            "TEMPORAL_GOVERNOR_GUARDIAN",
            localChainId,
            0xc191A4db4E05e478778eDB6a201cb7F13A257C23 /// Random address is temporal governor guardian
        );
        _addAddress(
            "TEMPORAL_GOVERNOR_GUARDIAN",
            baseGoerliChainId,
            0xc191A4db4E05e478778eDB6a201cb7F13A257C23 /// Random address is temporal governor guardian on base goerli, for testing purposes only
        );
        _addAddress(
            "TEMPORAL_GOVERNOR_GUARDIAN",
            moonBaseChainId,
            0xc191A4db4E05e478778eDB6a201cb7F13A257C23 /// Random address is temporal governor guardian on moonbase
        );
        _addAddress(
            "EMISSIONS_ADMIN",
            baseGoerliChainId,
            0x74Cbb1E8B68dDD13B28684ECA202a351afD45EAa
        );

        /// MOONBEAM
        _addAddress(
            "BORROW_SUPPLY_GUARDIAN",
            moonBeamChainId,
            0xc191A4db4E05e478778eDB6a201cb7F13A257C23 /// TODO add correct guantlet msig
        );
        _addAddress(
            "ARTEMIS_GOVERNOR",
            moonBeamChainId,
            0xfc4DFB17101A12C5CEc5eeDd8E92B5b16557666d /// TODO add correct guantlet msig
        );
        _addAddress(
            "WELL",
            moonBeamChainId,
            0x511aB53F793683763E5a8829738301368a2411E3
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

        _addAddress( /// moonbeam
            "WORMHOLE_CORE",
            moonBeamChainId,
            0xC8e2b0cD52Cf01b0Ce87d389Daa3d414d4cE29f3
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
            0xBaA4916ACD2d3Db77278A377f1b49A6E1127d6e6
        );
        _addAddress("USDBC", 84531, 0x64487F97E95266a291514574fFe640A4AC45Bcce);
        _addAddress("WBTC", 84531, 0xde1a381cAa4189D39c363985d9969D7D206970Bd);
        _addAddress("cbETH", 84531, 0x74a9f643b2DeA9829b5f2194A7f8d3440D8932F0);
        _addAddress(
            "wstETH",
            84531,
            0x3A4c72391FA1e474663ffB43bbA5c851014c0065
        );
        _addAddress("DAI", 84531, 0x098d2cF3bc642668a28E5633ED15Ca3166D2802d);
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
            0x73EC07c3E67011aa13A70A7466f1aEB0215293f4
        );
        _addAddress(
            "COMPTROLLER",
            84531,
            0x9091D61Cf1897EBa311D4012aEe9027666C59311
        );
        _addAddress(
            "UNITROLLER",
            84531,
            0xD73f191a50D4BFb5301AE0dF27F5164332df4618
        );
        _addAddress(
            "MRD_PROXY",
            84531,
            0x92ad0cEf7E4f89480ab65b9B9F666327E175702f
        );
        _addAddress(
            "MRD_PROXY_ADMIN",
            84531,
            0x7ae93E19639c77a3815d47729DE413346C361FF0
        );
        _addAddress(
            "MTOKEN_IMPLEMENTATION",
            84531,
            0x8DDc78645E18CDb4b6fcE65777642ef4fFdC6115
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_USDBC",
            84531,
            0x4696f537Ad80ef53D314624AD502f9d82397357e
        );
        _addAddress(
            "MOONWELL_USDBC",
            84531,
            0x765741AB1937d85D4758e004Ef906A5E18839EFe
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WETH",
            84531,
            0xd14ab729d48E92C25AC6D18F8D8182d850f485be
        );
        _addAddress(
            "MOONWELL_WETH",
            84531,
            0xdd702A5B463adB3b8AfddDB77B88DFaca8B2D3Ca
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WBTC",
            84531,
            0x9B9929848845269C08160873346f490e6F45e2C7
        );
        _addAddress(
            "MOONWELL_WBTC",
            84531,
            0xe94362a857df3Fc87E80A8b26e16e3C97C861a98
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_cbETH",
            84531,
            0xd86078e8802098A744F7c27D36304d905A1C2F02
        );
        _addAddress(
            "MOONWELL_cbETH",
            84531,
            0x5E31c5753598A6618A4D1bb2d35f63fBa757c9e3
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_wstETH",
            84531,
            0xf96cB4716EC5012c3Ea8c8b71eD79c1be68a8f44
        );
        _addAddress(
            "MOONWELL_wstETH",
            84531,
            0x1DCc89000AE6EAF18bD855098d3670E820A8d0c4
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_DAI",
            84531,
            0x1B1340afB59315C648f45E2E8850C79ac71ad530
        );
        _addAddress(
            "MOONWELL_DAI",
            84531,
            0x1d1e13e0974E8a065C1DE7EbB1E3A1cbE88FC58a
        );
        _addAddress(
            "WETH_ROUTER",
            84531,
            0x0396D41A53a75be8f296353D1ffE72538bE646f5
        );
        _addAddress(
            "CHAINLINK_ORACLE",
            84531,
            0x037fd3c408086E900c71Ca33abF67eC33288eA8c
        );
        _addAddress(
            "MWETH_IMPLEMENTATION",
            84531,
            0x30d3740d8d15004E3D14be74E97Fc4BA189C6400
        );
        _addAddress(
            "WETH_UNWRAPPER",
            84531,
            0xb65604ae9b9250c1973441A03f9Ec7ECF09aaC7e
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
        _addAddress(
            "stETHETH_ORACLE",
            84531,
            0x3a52fB70713032B182F351829573a318a4f8E4E6
        );
        _addAddress(
            "cbETHETH_ORACLE",
            84531,
            0x45E62c1D07365c46631a4F2032c0e630CCA91c55
        );
        _addAddress(
            "DAI_ORACLE",
            84531,
            0x440bD1535a02243d72E0fEED45B137efcC98bF7e
        );

        /// GOERLI BASE

        _addAddress(
            "MOONBEAM_TIMELOCK",
            baseGoerliChainId,
            0x43A720C2690B00Ae0a0F9E4b79ED24184D9e8F0A
        );

        /// ------------ base deployment constants ------------
        /// ---------- DO NOT CHANGE BELOW THIS LINE ----------

        _addAddress(
            "WORMHOLE_CORE",
            baseChainId,
            0xbebdb6C8ddC678FfA9f8748f85C815C556Dd8ac6
        );

        _addAddress(
            "USDBC",
            baseChainId,
            0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA
        );

        _addAddress(
            "USDC",
            baseChainId,
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
        );

        _addAddress(
            "WETH",
            baseChainId,
            0x4200000000000000000000000000000000000006
        );

        _addAddress(
            "WELL",
            baseChainId,
            0xFF8adeC2221f9f4D8dfbAFa6B9a297d17603493D
        );

        _addAddress(
            "DAI",
            baseChainId,
            0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb
        );

        _addAddress(
            "cbETH",
            baseChainId,
            0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22
        );

        _addAddress(
            "USDC_ORACLE",
            baseChainId,
            0x7e860098F58bBFC8648a4311b374B1D669a2bc6B
        );

        _addAddress(
            "ETH_ORACLE",
            baseChainId,
            0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70
        );

        _addAddress(
            "DAI_ORACLE",
            baseChainId,
            0x591e79239a7d679378eC8c847e5038150364C78F
        );

        _addAddress( /// UNUSED for now since are not deploying a wstETH market
            "wstETHstETH_ORACLE",
            baseChainId,
            0xB88BAc61a4Ca37C43a3725912B1f472c9A5bc061
        );

        _addAddress(
            "stETHETH_ORACLE",
            baseChainId,
            0xf586d0728a47229e747d824a939000Cf21dEF5A0
        );

        _addAddress(
            "cbETHETH_ORACLE",
            baseChainId,
            0x806b4Ac04501c29769051e42783cF04dCE41440b
        );

        _addAddress(
            "EMISSIONS_ADMIN",
            baseChainId,
            0xD791292655A1d382FcC1a6Cb9171476cf91F2caa
        );

        _addAddress(
            "PAUSE_GUARDIAN",
            baseChainId,
            0xB9d4acf113a423Bc4A64110B8738a52E51C2AB38
        );

        _addAddress(
            "TEMPORAL_GOVERNOR_GUARDIAN",
            baseChainId,
            0x446342AF4F3bCD374276891C6bb3411bf2F8779E
        );

        _addAddress(
            "BORROW_SUPPLY_GUARDIAN",
            baseChainId,
            0x35b3314EA652899154BbfE937E3cCC2775ba712e
        );

        /// ------------ base deployment ------------

        _addAddress(
            "TEMPORAL_GOVERNOR",
            8453,
            0x8b621804a7637b781e2BbD58e256a591F2dF7d51
        );
        _addAddress(
            "cbETH_ORACLE",
            8453,
            0xB0Ba0C5D7DA4ec400C1C3E5ef2485134F89918C5
        );
        _addAddress(
            "MULTI_REWARD_DISTRIBUTOR",
            8453,
            0xdC649f4fa047a3C98e8705E85B8b1BafCbCFef0f
        );
        _addAddress(
            "COMPTROLLER",
            8453,
            0x73D8A3bF62aACa6690791E57EBaEE4e1d875d8Fe
        );
        _addAddress(
            "UNITROLLER",
            8453,
            0xfBb21d0380beE3312B33c4353c8936a0F13EF26C
        );
        _addAddress(
            "MRD_PROXY",
            8453,
            0xe9005b078701e2A0948D2EaC43010D35870Ad9d2
        );
        _addAddress(
            "MRD_PROXY_ADMIN",
            8453,
            0x8D7d2230A2d195F023588eDd13dBAd56dd69770F
        );
        _addAddress(
            "MTOKEN_IMPLEMENTATION",
            8453,
            0x1FADFF493529C3Fcc7EE04F1f15D19816ddA45B7
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_USDBC",
            8453,
            0x492dcEF1fc5253413fC5576B9522840a1A774DCe
        );
        _addAddress(
            "MOONWELL_DAI",
            8453,
            0x73b06D8d18De422E269645eaCe15400DE7462417
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_DAI",
            8453,
            0x492dcEF1fc5253413fC5576B9522840a1A774DCe
        );
        _addAddress(
            "MOONWELL_USDBC",
            8453,
            0x703843C3379b52F9FF486c9f5892218d2a065cC8
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_USDC",
            8453,
            0x492dcEF1fc5253413fC5576B9522840a1A774DCe
        );
        _addAddress(
            "MOONWELL_USDC",
            8453,
            0xEdc817A28E8B93B03976FBd4a3dDBc9f7D176c22
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_WETH",
            8453,
            0x142DCAEC322aAA25141B2597bf348487aDBd596d
        );
        _addAddress(
            "MOONWELL_WETH",
            8453,
            0x628ff693426583D9a7FB391E54366292F509D457
        );
        _addAddress(
            "JUMP_RATE_IRM_MOONWELL_cbETH",
            8453,
            0x78Fe5d0427E669ba9F964C3495fF381a805a0487
        );
        _addAddress(
            "MOONWELL_cbETH",
            8453,
            0x3bf93770f2d4a794c3d9EBEfBAeBAE2a8f09A5E5
        );
        _addAddress(
            "WETH_ROUTER",
            8453,
            0x70778cfcFC475c7eA0f24cC625Baf6EaE475D0c9
        );
        _addAddress(
            "CHAINLINK_ORACLE",
            8453,
            0xEC942bE8A8114bFD0396A5052c36027f2cA6a9d0
        );
        _addAddress(
            "WETH_UNWRAPPER",
            8453,
            0x1382cFf3CeE10D283DccA55A30496187759e4cAf
        );
        _addAddress(
            "MWETH_IMPLEMENTATION",
            8453,
            0x599D4a1538d686814eE11b331EACBBa166D7C41a
        );

        _addAddress(
            "FOUNDATION_MULTISIG",
            baseChainId,
            0x74Cbb1E8B68dDD13B28684ECA202a351afD45EAa
        );
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
