//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";
import "@protocol/utils/ChainIds.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Address} from "@utils/Address.sol";
import {Configs} from "@proposals/Configs.sol";
import {Unitroller} from "@protocol/Unitroller.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {PriceOracle} from "@protocol/oracles/PriceOracle.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";
import {HybridProposalV2} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {MoonwellViewsV3} from "@protocol/views/MoonwellViewsV3.sol";
/// MultichainGovernorV2 is deployed by initProposal() via MIP-X58 on Ethereum as the governance hub
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {JumpRateModel, InterestRateModel} from "@protocol/irm/JumpRateModel.sol";
import {Comptroller, ComptrollerInterface} from "@protocol/Comptroller.sol";
import {ChainIds, ETHEREUM_FORK_ID, ETHEREUM_CHAIN_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID} from "@utils/ChainIds.sol";
import {ActionType} from "@proposals/proposalTypes/IProposal.sol";

contract mipe00 is HybridProposalV2, Configs {
    using Address for address;
    using ChainIds for uint256;

    string public constant override name = "MIP-E00";
    uint256 public constant liquidationIncentive = 1.1e18; /// liquidation incentive is 110%
    uint256 public constant closeFactor = 0.5e18; /// close factor is 50%, i.e. seize share
    uint8 public constant mTokenDecimals = 8; /// all mTokens have 8 decimals

    struct CTokenAddresses {
        address mTokenImpl;
        address irModel;
        address unitroller;
    }

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-e00/MIP-E00.md")
        );
        _setProposalDescription(proposalDescription);

        nonce = 2;
    }

    function primaryForkId() public pure override returns (uint256) {
        return ETHEREUM_FORK_ID;
    }

    /// @notice Run MIP-X58 to deploy MultichainGovernorV2 before MIP-E00 deployment
    function initProposal(Addresses) public override {
        /// MIP-X58 is already executed on-chain; MULTICHAIN_GOVERNOR_V2_PROXY
        /// is registered in chains/1.json. No setup needed — just select the
        /// Ethereum fork for MIP-E00 deployment.
        vm.selectFork(ETHEREUM_FORK_ID);
    }

    /// @notice the deployer should have WETH, USDC, USDT, WBTC, weETH, wstETH to be able to deploy on Ethereum.
    /// This allows the deployer to be able to initialize the markets with a balance to avoid exploits
    function deploy(Addresses addresses, address deployer) public override {
        /// ------- MultichainGovernorV2 (deployed by initProposal via MIP-X58) -------
        /// The MultichainGovernorV2 is deployed in initProposal() which runs MIP-X58.
        /// MIP-E00 uses the existing governor for all protocol contracts.
        localInit(addresses);

        /// Verify MultichainGovernorV2 was deployed by initProposal
        require(
            addresses.isAddressSet("MULTICHAIN_GOVERNOR_V2_PROXY"),
            "MIP-E00: MultichainGovernorV2 not deployed. initProposal should have deployed it."
        );

        deployAndMint(addresses);
        init(addresses);

        /// ------- Reward Distributor -------
        if (!addresses.isAddressSet("MRD_IMPL")) {
            MultiRewardDistributor distributor = new MultiRewardDistributor();
            addresses.addAddress("MRD_IMPL", address(distributor));
        }
        /// ------- Unitroller/Comptroller + MRD proxy -------
        /// Guard on MRD_PROXY (last address created in the block) so a
        /// partial re-run never re-wires `_setPendingImplementation` /
        /// `_become` against fresh contracts.
        if (!addresses.isAddressSet("MRD_PROXY")) {
            Unitroller unitroller = new Unitroller();
            Comptroller comptroller = new Comptroller();
            unitroller._setPendingImplementation(address(comptroller));
            comptroller._become(unitroller);
            addresses.addAddress("COMPTROLLER", address(comptroller));
            addresses.addAddress("UNITROLLER", address(unitroller));
            ProxyAdmin proxyAdmin = new ProxyAdmin();
            addresses.addAddress("MRD_PROXY_ADMIN", address(proxyAdmin));

            bytes memory initData = abi.encodeWithSignature(
                "initialize(address,address)",
                address(unitroller),
                addresses.getAddress("PAUSE_GUARDIAN")
            );
            TransparentUpgradeableProxy mrdProxy = new TransparentUpgradeableProxy(
                    addresses.getAddress("MRD_IMPL"),
                    address(proxyAdmin),
                    initData
                );
            addresses.addAddress("MRD_PROXY", address(mrdProxy));
        }
        /// ------ MTOKENS -------
        if (!addresses.isAddressSet("MTOKEN_IMPLEMENTATION")) {
            MErc20Delegate mTokenLogic = new MErc20Delegate();
            addresses.addAddress("MTOKEN_IMPLEMENTATION", address(mTokenLogic));
        }

        _setMTokenConfiguration("proposals/mips/mip-e00/mTokens.json");
        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);
        uint256 cTokenConfigsLength = cTokenConfigs.length;
        //// create all of the CTokens according to the configuration in Config.sol
        unchecked {
            for (uint256 i = 0; i < cTokenConfigsLength; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];
                /// ----- Jump Rate IRM -------
                if (
                    !addresses.isAddressSet(
                        string(
                            abi.encodePacked(
                                "JUMP_RATE_IRM_",
                                config.addressesString
                            )
                        )
                    )
                ) {
                    address irModel = address(
                        new JumpRateModel(
                            config.jrm.baseRatePerYear,
                            config.jrm.multiplierPerYear,
                            config.jrm.jumpMultiplierPerYear,
                            config.jrm.kink
                        )
                    );
                    addresses.addAddress(
                        string(
                            abi.encodePacked(
                                "JUMP_RATE_IRM_",
                                config.addressesString
                            )
                        ),
                        address(irModel)
                    );
                }
                /// stack isn't too deep
                CTokenAddresses memory addr = CTokenAddresses({
                    mTokenImpl: addresses.getAddress("MTOKEN_IMPLEMENTATION"),
                    irModel: addresses.getAddress(
                        string(
                            abi.encodePacked(
                                "JUMP_RATE_IRM_",
                                config.addressesString
                            )
                        )
                    ),
                    unitroller: addresses.getAddress("UNITROLLER")
                });
                /// calculate initial exchange rate
                /// BigNumber.from("10").pow(token.decimals + 8).mul("2");
                /// (10 ** (18 + 8)) * 2 // 18 decimals example
                ///    = 2e26
                /// (10 ** (6 + 8)) * 2 // 6 decimals example
                ///    = 2e14
                if (!addresses.isAddressSet(config.addressesString)) {
                    uint256 initialExchangeRate = (10 **
                        (ERC20(addresses.getAddress(config.tokenAddressName))
                            .decimals() + 8)) * 2;
                    MErc20Delegator mToken = new MErc20Delegator(
                        addresses.getAddress(config.tokenAddressName),
                        ComptrollerInterface(addr.unitroller),
                        InterestRateModel(addr.irModel),
                        initialExchangeRate,
                        config.name,
                        config.symbol,
                        mTokenDecimals,
                        payable(deployer),
                        addr.mTokenImpl,
                        ""
                    );
                    addresses.addAddress(
                        config.addressesString,
                        address(mToken)
                    );
                }
            }
        }

        initEmissions(addresses, deployer);
        if (!addresses.isAddressSet("WETH_ROUTER")) {
            WETHRouter router = new WETHRouter(
                WETH9(addresses.getAddress("WETH")),
                MErc20(addresses.getAddress("MOONWELL_WETH"))
            );
            addresses.addAddress("WETH_ROUTER", address(router));
        }
        /// deploy oracle, set price oracle
        if (!addresses.isAddressSet("CHAINLINK_ORACLE")) {
            ChainlinkOracle oracle = new ChainlinkOracle("null_asset");
            addresses.addAddress("CHAINLINK_ORACLE", address(oracle));
        }

        /// ------- MoonwellViewsV3 (read-only views aggregator) -------
        /// impl + dedicated ProxyAdmin + initialized TransparentUpgradeableProxy.
        /// The dedicated ProxyAdmin keeps view-only upgrades out of governance.
        /// On Ethereum the stkWELL safety module is registered as
        /// STK_GOVTOKEN_PROXY (the Base key is stkWELL_PROXY).
        /// Guard on MOONWELL_VIEWS_PROXY (last address created) so a partial
        /// re-run never re-initializes the proxy against a fresh impl/admin.
        if (!addresses.isAddressSet("MOONWELL_VIEWS_PROXY")) {
            MoonwellViewsV3 viewsImpl = new MoonwellViewsV3();
            addresses.addAddress(
                "MOONWELL_VIEWS_IMPLEMENTATION",
                address(viewsImpl)
            );

            ProxyAdmin viewsProxyAdmin = new ProxyAdmin();
            addresses.addAddress(
                "MOONWELL_VIEWS_PROXY_ADMIN",
                address(viewsProxyAdmin)
            );

            bytes memory viewsInitData = abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                addresses.getAddress("UNITROLLER"),
                address(0), /// tokenSaleDistributor
                addresses.getAddress("STK_GOVTOKEN_PROXY"), /// safetyModule (stkWELL)
                addresses.getAddress("xWELL_PROXY"),
                address(0), /// nativeMarket
                address(0) /// governanceTokenLP
            );
            TransparentUpgradeableProxy viewsProxy = new TransparentUpgradeableProxy(
                    address(viewsImpl),
                    address(viewsProxyAdmin),
                    viewsInitData
                );
            addresses.addAddress("MOONWELL_VIEWS_PROXY", address(viewsProxy));
        }
    }

    function afterDeploy(Addresses addresses, address) public override {
        {
            ProxyAdmin proxyAdmin = ProxyAdmin(
                addresses.getAddress("MRD_PROXY_ADMIN")
            );
            Unitroller unitroller = Unitroller(
                addresses.getAddress("UNITROLLER")
            );

            address governor = addresses.getAddress(
                "MULTICHAIN_GOVERNOR_V2_PROXY"
            );

            ChainlinkOracle oracle = ChainlinkOracle(
                addresses.getAddress("CHAINLINK_ORACLE")
            );

            /// set MultichainGovernorV2 as owner of the proxy admin
            proxyAdmin.transferOwnership(governor);

            /// set chainlink oracle on the comptroller implementation contract
            Comptroller(address(unitroller))._setPriceOracle(
                PriceOracle(address(oracle))
            );

            Configs.CTokenConfiguration[]
                memory cTokenConfigs = getCTokenConfigurations(block.chainid);
            MToken[] memory mTokens = new MToken[](cTokenConfigs.length);
            uint256[] memory supplyCaps = new uint256[](cTokenConfigs.length);
            uint256[] memory borrowCaps = new uint256[](cTokenConfigs.length);

            //// set mint paused for all of the deployed MTokens
            unchecked {
                for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                    Configs.CTokenConfiguration memory config = cTokenConfigs[
                        i
                    ];
                    supplyCaps[i] = config.supplyCap;
                    borrowCaps[i] = config.borrowCap;

                    oracle.setFeed(
                        ERC20(addresses.getAddress(config.tokenAddressName))
                            .symbol(),
                        addresses.getAddress(config.priceFeedName)
                    );

                    /// list mToken in the comptroller
                    Comptroller(address(unitroller))._supportMarket(
                        MToken(addresses.getAddress(config.addressesString))
                    );

                    /// set mint paused for all MTokens on mainnet
                    Comptroller(address(unitroller))._setMintPaused(
                        MToken(addresses.getAddress(config.addressesString)),
                        true
                    );

                    /// get the mToken
                    mTokens[i] = MToken(
                        addresses.getAddress(config.addressesString)
                    );

                    mTokens[i]._setReserveFactor(config.reserveFactor);
                    mTokens[i]._setProtocolSeizeShare(config.seizeShare);
                    mTokens[i]._setPendingAdmin(payable(governor)); /// set MultichainGovernorV2 as pending admin of the mToken

                    Comptroller(address(unitroller))._setCollateralFactor(
                        mTokens[i],
                        config.collateralFactor
                    );
                }
            }

            Comptroller(address(unitroller))._setMarketSupplyCaps(
                mTokens,
                supplyCaps
            );
            Comptroller(address(unitroller))._setMarketBorrowCaps(
                mTokens,
                borrowCaps
            );
            Comptroller(address(unitroller))._setRewardDistributor(
                MultiRewardDistributor(addresses.getAddress("MRD_PROXY"))
            );
            Comptroller(address(unitroller))._setLiquidationIncentive(
                liquidationIncentive
            );
            Comptroller(address(unitroller))._setCloseFactor(closeFactor);

            /// ------------ SET GUARDIANS ------------

            Comptroller(address(unitroller))._setBorrowCapGuardian(
                addresses.getAddress("BORROW_SUPPLY_GUARDIAN")
            );
            Comptroller(address(unitroller))._setSupplyCapGuardian(
                addresses.getAddress("BORROW_SUPPLY_GUARDIAN")
            );
            Comptroller(address(unitroller))._setPauseGuardian(
                addresses.getAddress("PAUSE_GUARDIAN")
            );

            /// set MultichainGovernorV2 as the pending admin
            unitroller._setPendingAdmin(governor);

            /// set MultichainGovernorV2 as the admin of the chainlink feed
            oracle.setAdmin(governor);
        }
        /// -------------- EMISSION CONFIGURATION --------------

        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            block.chainid
        );
        MultiRewardDistributor mrd = MultiRewardDistributor(
            addresses.getAddress("MRD_PROXY")
        );

        unchecked {
            for (uint256 i = 0; i < emissionConfig.length; i++) {
                EmissionConfig memory config = emissionConfig[i];

                mrd._addEmissionConfig(
                    MToken(addresses.getAddress(config.mToken)),
                    addresses.getAddress(config.owner),
                    addresses.getAddress(config.emissionToken),
                    config.supplyEmissionPerSec,
                    config.borrowEmissionsPerSec,
                    config.endTime
                );
            }
        }
    }

    function beforeSimulationHook(Addresses addresses) public override {
        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);

        address recipient = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_PROXY"
        );
        address usdt = addresses.getAddress("USDT");

        uint256 cTokenConfigsLength = cTokenConfigs.length;
        unchecked {
            for (uint256 i = 0; i < cTokenConfigsLength; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];
                address tokenAddress = addresses.getAddress(
                    config.tokenAddressName
                );
                uint256 amount = cTokenConfigs[i].initialMintAmount;

                if (tokenAddress == usdt) {
                    /// forge-std deal() cannot fund Tether USDT: its slot
                    /// brute-force writes a marker into USDT slot 10
                    /// (upgradedAddress + deprecated), flipping the contract
                    /// into its deprecated branch so balanceOf reverts before
                    /// the real balances slot is located. Write the balances
                    /// mapping (slot 2) directly instead.
                    vm.store(
                        usdt,
                        keccak256(abi.encode(recipient, uint256(2))),
                        bytes32(amount)
                    );
                } else {
                    deal(tokenAddress, recipient, amount);
                }
            }
        }
    }

    function build(Addresses addresses) public override {
        /// ------------ UNITROLLER ACCEPT ADMIN ------------

        /// Unitroller configuration
        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "MultichainGovernorV2 accepts admin on Unitroller"
        );

        /// ------------ ACCEPT OWNERSHIP (Ownable2Step) ------------
        /// MIP-X58 sets pendingOwner on these contracts; the new
        /// MultichainGovernorV2 (Ethereum) and TemporalGovernor (other chains)
        /// must accept ownership in MIP-E00 to complete the transfer.

        /// Ethereum: WormholeBridgeAdapter — MultichainGovernorV2 accepts
        _pushAction(
            addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                ETHEREUM_CHAIN_ID
            ),
            abi.encodeWithSignature("acceptOwnership()"),
            "MultichainGovernorV2 accepts ownership of WormholeBridgeAdapter on Ethereum"
        );

        /// Ethereum: xWELL — MultichainGovernorV2 accepts. PAUSE_GUARDIAN
        /// multisig has already executed transferOwnership(MULTICHAIN_GOVERNOR_V2_PROXY)
        /// off-chain; this completes the Ownable2Step handoff.
        _pushAction(
            addresses.getAddress("xWELL_PROXY", ETHEREUM_CHAIN_ID),
            abi.encodeWithSignature("acceptOwnership()"),
            "MultichainGovernorV2 accepts ownership of xWELL on Ethereum"
        );

        /// Moonbeam: WormholeBridgeAdapter — TemporalGovernor accepts
        _pushAction(
            addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                MOONBEAM_CHAIN_ID
            ),
            abi.encodeWithSignature("acceptOwnership()"),
            "TemporalGovernor accepts ownership of WormholeBridgeAdapter on Moonbeam",
            ActionType.Moonbeam
        );

        /// Moonbeam: VotingPowerAggregator — TemporalGovernor accepts.
        /// This is the only Ownable2Step pending-owner accept needed in E00:
        /// MIP-X58 calls the public `transferOwnership` on the Moonbeam VPA,
        /// which sets `pendingOwner = TemporalGovernor` and requires the new
        /// owner to call `acceptOwnership()` here to complete the transfer.
        ///
        /// The Moonbeam VC and Base/Optimism VPAs are intentionally NOT
        /// included: they are initialized in MIP-X58 with the TemporalGovernor
        /// as their direct owner (via `_transferOwnership` inside `initialize`,
        /// see MultichainVoteCollectionMoonbeam.sol:59 and
        /// VotingPowerAggregator.sol:36), so `pendingOwner` is `address(0)` on
        /// all three — calling `acceptOwnership()` would revert.
        _pushAction(
            addresses.getAddress("VOTING_POWER_AGGREGATOR", MOONBEAM_CHAIN_ID),
            abi.encodeWithSignature("acceptOwnership()"),
            "TemporalGovernor accepts ownership of VotingPowerAggregator on Moonbeam",
            ActionType.Moonbeam
        );

        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);

        address unitrollerAddress = addresses.getAddress("UNITROLLER");

        /// set mint unpaused for all of the deployed MTokens
        unchecked {
            for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];

                address cTokenAddress = addresses.getAddress(
                    config.addressesString
                );

                /// ------------ MTOKEN MARKET ACTIVIATION ------------

                /// MultichainGovernorV2 accepts admin of mToken
                _pushAction(
                    cTokenAddress,
                    abi.encodeWithSignature("_acceptAdmin()"),
                    "MultichainGovernorV2 accepts admin on mToken"
                );

                _pushAction(
                    unitrollerAddress,
                    abi.encodeWithSignature(
                        "_setMintPaused(address,bool)",
                        cTokenAddress,
                        false
                    ),
                    "Unpause MToken market"
                );

                /// Approvals
                _pushAction(
                    addresses.getAddress(config.tokenAddressName),
                    abi.encodeWithSignature(
                        "approve(address,uint256)",
                        cTokenAddress,
                        config.initialMintAmount
                    ),
                    "Approve underlying token to be spent by market"
                );

                /// Initialize markets
                _pushAction(
                    cTokenAddress,
                    abi.encodeWithSignature(
                        "mint(uint256)",
                        config.initialMintAmount
                    ),
                    "Initialize token market to prevent exploit"
                );

                _pushAction(
                    cTokenAddress,
                    abi.encodeWithSignature(
                        "transfer(address,uint256)",
                        address(0),
                        1
                    ),
                    "Send 1 wei to address 0 to prevent a state where market has 0 mToken"
                );

                if (!vm.envOr("EXCLUDE_MARKET_ADD_CHECKER", false)) {
                    _pushAction(
                        addresses.getAddress("MARKET_ADD_CHECKER"),
                        abi.encodeWithSignature(
                            "checkMarketAdd(address)",
                            cTokenAddress
                        ),
                        "Check the market has been correctly initialized and collateral token minted"
                    );
                }
            }
        }
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        /// MultichainGovernorV2 is deployed by initProposal via MIP-X58 - just get the address
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY");

        {
            ChainlinkOracle oracle = ChainlinkOracle(
                addresses.getAddress("CHAINLINK_ORACLE")
            );

            assertEq(oracle.admin(), address(governor));
            /// validate chainlink price feeds are correctly set according to config in oracle

            Configs.CTokenConfiguration[]
                memory cTokenConfigs = getCTokenConfigurations(block.chainid);

            //// set mint paused for all of the deployed MTokens
            unchecked {
                for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                    Configs.CTokenConfiguration memory config = cTokenConfigs[
                        i
                    ];

                    assertEq(
                        address(
                            oracle.getFeed(
                                ERC20(
                                    addresses.getAddress(
                                        config.tokenAddressName
                                    )
                                ).symbol()
                            )
                        ),
                        addresses.getAddress(config.priceFeedName)
                    );
                }
            }
        }

        /// assert comptroller and unitroller are wired together properly
        {
            Unitroller unitroller = Unitroller(
                addresses.getAddress("UNITROLLER")
            );
            Comptroller comptroller = Comptroller(
                addresses.getAddress("COMPTROLLER")
            );

            assertEq(comptroller.pendingAdmin(), address(0));
            assertEq(comptroller.pauseGuardian(), address(0));
            assertEq(comptroller.borrowCapGuardian(), address(0));
            assertEq(comptroller.supplyCapGuardian(), address(0));
            assertEq(address(comptroller.rewardDistributor()), address(0));

            assertEq(
                Comptroller(address(unitroller)).admin(),
                addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY")
            );
            assertEq(
                Comptroller(address(unitroller)).pendingAdmin(),
                address(0)
            );
            assertEq(
                Comptroller(address(unitroller)).pauseGuardian(),
                addresses.getAddress("PAUSE_GUARDIAN")
            );
            assertEq(
                Comptroller(address(unitroller)).supplyCapGuardian(),
                addresses.getAddress("BORROW_SUPPLY_GUARDIAN")
            );
            assertEq(
                Comptroller(address(unitroller)).borrowCapGuardian(),
                addresses.getAddress("BORROW_SUPPLY_GUARDIAN")
            );
            assertEq(
                address(Comptroller(address(unitroller)).rewardDistributor()),
                addresses.getAddress("MRD_PROXY")
            );

            assertEq(
                address(unitroller.comptrollerImplementation()),
                address(comptroller)
            );
            assertEq(
                address(unitroller.pendingComptrollerImplementation()),
                address(0)
            );
        }

        /// assert WETH router is properly wired into the system
        {
            WETHRouter router = WETHRouter(
                payable(addresses.getAddress("WETH_ROUTER"))
            );
            assertEq(address(router.weth()), addresses.getAddress("WETH"));
            assertEq(
                address(router.mToken()),
                addresses.getAddress("MOONWELL_WETH")
            );
        }

        /// assert multi reward distributor proxy is wired into unitroller correctly
        {
            MultiRewardDistributor distributor = MultiRewardDistributor(
                addresses.getAddress("MRD_PROXY")
            );
            assertEq(
                address(distributor.comptroller()),
                addresses.getAddress("UNITROLLER")
            );
            assertEq(
                address(distributor.pauseGuardian()),
                addresses.getAddress("PAUSE_GUARDIAN")
            );
            assertEq(distributor.emissionCap(), 100e18);
            assertEq(distributor.initialIndexConstant(), 1e36);
        }

        /// assert multi reward distributor comptroller and guardian are unset
        {
            MultiRewardDistributor distributor = MultiRewardDistributor(
                addresses.getAddress("MRD_IMPL")
            );
            assertEq(address(distributor.comptroller()), address(0));
            assertEq(address(distributor.pauseGuardian()), address(0));
        }

        /// assert proxy admin is owned by MultichainGovernorV2
        {
            ProxyAdmin proxyAdmin = ProxyAdmin(
                addresses.getAddress("MRD_PROXY_ADMIN")
            );
            assertEq(proxyAdmin.owner(), governor);
        }

        /// admin is owned by proxy admin
        {
            bytes32 _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

            bytes32 data = vm.load(
                addresses.getAddress("MRD_PROXY"),
                _ADMIN_SLOT
            );
            assertEq(
                bytes32(
                    uint256(uint160(addresses.getAddress("MRD_PROXY_ADMIN")))
                ),
                data
            );

            bytes32 _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

            data = vm.load(
                addresses.getAddress("MRD_PROXY"),
                _IMPLEMENTATION_SLOT
            );
            assertEq(
                bytes32(uint256(uint160(addresses.getAddress("MRD_IMPL")))),
                data
            );
        }

        /// MultichainGovernorV2 specific validations are handled by MIP-X58

        {
            Comptroller comptroller = Comptroller(
                addresses.getAddress("UNITROLLER")
            );

            assertEq(comptroller.closeFactorMantissa(), closeFactor);
            assertEq(
                comptroller.liquidationIncentiveMantissa(),
                liquidationIncentive
            );

            Configs.CTokenConfiguration[]
                memory cTokenConfigs = getCTokenConfigurations(block.chainid);

            unchecked {
                for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                    Configs.CTokenConfiguration memory config = cTokenConfigs[
                        i
                    ];

                    /// CToken Assertions
                    assertFalse(
                        comptroller.mintGuardianPaused(
                            addresses.getAddress(config.addressesString)
                        )
                    ); /// minting allowed by guardian
                    assertFalse(
                        comptroller.borrowGuardianPaused(
                            addresses.getAddress(config.addressesString)
                        )
                    ); /// borrowing allowed by guardian
                    assertEq(
                        comptroller.borrowCaps(
                            addresses.getAddress(config.addressesString)
                        ),
                        config.borrowCap
                    );
                    assertEq(
                        comptroller.supplyCaps(
                            addresses.getAddress(config.addressesString)
                        ),
                        config.supplyCap
                    );

                    /// assert cToken irModel is correct
                    JumpRateModel jrm = JumpRateModel(
                        addresses.getAddress(
                            string(
                                abi.encodePacked(
                                    "JUMP_RATE_IRM_",
                                    config.addressesString
                                )
                            )
                        )
                    );
                    assertEq(
                        address(
                            MToken(addresses.getAddress(config.addressesString))
                                .interestRateModel()
                        ),
                        address(jrm)
                    );

                    MErc20 mToken = MErc20(
                        addresses.getAddress(config.addressesString)
                    );

                    /// reserve factor and protocol seize share
                    assertEq(
                        mToken.protocolSeizeShareMantissa(),
                        config.seizeShare
                    );
                    assertEq(
                        mToken.reserveFactorMantissa(),
                        config.reserveFactor
                    );

                    /// assert initial mToken balances are correct
                    assertTrue(mToken.balanceOf(address(governor)) > 0); /// governor has some
                    assertEq(mToken.balanceOf(address(0)), 1); /// address 0 has 1 wei of assets

                    /// assert mToken admin is the MultichainGovernorV2
                    assertEq(address(mToken.admin()), governor);

                    /// assert mToken comptroller is correct
                    assertEq(
                        address(mToken.comptroller()),
                        addresses.getAddress("UNITROLLER")
                    );

                    /// assert mToken underlying is correct
                    assertEq(
                        address(mToken.underlying()),
                        addresses.getAddress(config.tokenAddressName)
                    );

                    /// assert mToken delegate is uniform across contracts
                    assertEq(
                        address(
                            MErc20Delegator(payable(address(mToken)))
                                .implementation()
                        ),
                        addresses.getAddress("MTOKEN_IMPLEMENTATION")
                    );

                    uint256 initialExchangeRate = (10 **
                        (8 +
                            ERC20(addresses.getAddress(config.tokenAddressName))
                                .decimals())) * 2;

                    /// assert mToken initial exchange rate is correct
                    assertEq(mToken.exchangeRateCurrent(), initialExchangeRate);

                    /// assert mToken name and symbol are correct
                    assertEq(mToken.name(), config.name);
                    assertEq(mToken.symbol(), config.symbol);
                    assertEq(mToken.decimals(), mTokenDecimals);

                    /// Jump Rate Model Assertions
                    {
                        assertEq(
                            jrm.baseRatePerTimestamp(),
                            (config.jrm.baseRatePerYear * 1e18) /
                                jrm.timestampsPerYear() /
                                1e18
                        );
                        assertEq(
                            jrm.multiplierPerTimestamp(),
                            (config.jrm.multiplierPerYear * 1e18) /
                                jrm.timestampsPerYear() /
                                1e18
                        );
                        assertEq(
                            jrm.jumpMultiplierPerTimestamp(),
                            (config.jrm.jumpMultiplierPerYear * 1e18) /
                                jrm.timestampsPerYear() /
                                1e18
                        );
                        assertEq(jrm.kink(), config.jrm.kink);
                    }
                }
            }
        }

        {
            /// assert admin of implementation contract is address 0 so it cannot be initialized
            assertEq(
                MErc20Delegate(addresses.getAddress("MTOKEN_IMPLEMENTATION"))
                    .admin(),
                address(0)
            );
        }

        {
            EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
                block.chainid
            );
            MultiRewardDistributor distributor = MultiRewardDistributor(
                addresses.getAddress("MRD_PROXY")
            );

            unchecked {
                for (uint256 i = 0; i < emissionConfig.length; i++) {
                    EmissionConfig memory config = emissionConfig[i];
                    MultiRewardDistributorCommon.MarketConfig
                        memory marketConfig = distributor.getConfigForMarket(
                            MToken(addresses.getAddress(config.mToken)),
                            addresses.getAddress(config.emissionToken)
                        );

                    assertEq(
                        marketConfig.owner,
                        addresses.getAddress(config.owner)
                    );
                    assertEq(
                        marketConfig.emissionToken,
                        addresses.getAddress(config.emissionToken)
                    );
                    assertEq(marketConfig.endTime, config.endTime);
                    assertEq(
                        marketConfig.supplyEmissionsPerSec,
                        config.supplyEmissionPerSec
                    );
                    assertEq(
                        marketConfig.borrowEmissionsPerSec,
                        config.borrowEmissionsPerSec
                    );
                    assertEq(marketConfig.supplyGlobalIndex, 1e36);
                    assertEq(marketConfig.borrowGlobalIndex, 1e36);
                }
            }
        }

        /// assert MoonwellViewsV3 proxy is deployed and wired correctly
        {
            MoonwellViewsV3 views = MoonwellViewsV3(
                addresses.getAddress("MOONWELL_VIEWS_PROXY")
            );
            assertEq(
                address(views.comptroller()),
                addresses.getAddress("UNITROLLER")
            );

            bytes32 _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
            assertEq(
                vm.load(
                    addresses.getAddress("MOONWELL_VIEWS_PROXY"),
                    _IMPLEMENTATION_SLOT
                ),
                bytes32(
                    uint256(
                        uint160(
                            addresses.getAddress(
                                "MOONWELL_VIEWS_IMPLEMENTATION"
                            )
                        )
                    )
                )
            );

            bytes32 _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
            assertEq(
                vm.load(
                    addresses.getAddress("MOONWELL_VIEWS_PROXY"),
                    _ADMIN_SLOT
                ),
                bytes32(
                    uint256(
                        uint160(
                            addresses.getAddress("MOONWELL_VIEWS_PROXY_ADMIN")
                        )
                    )
                )
            );
        }

        _validateProposalDescriptionUri();
    }

    /// @notice Assert this proposal's mips.json entry carries a pinned IPFS
    /// descriptionUri and — when the in-memory URI was injected by
    /// ProposalMap.runProposal — that the two agree. Guards against shipping
    /// the proposal with the IPFS pin step skipped or with mips.json drifted
    /// from the runtime value loaded by the test harness.
    function _validateProposalDescriptionUri() internal {
        string memory mipsJson = vm.readFile(
            string.concat(vm.projectRoot(), "/proposals/mips/mips.json")
        );

        // Match by `.path` not array index — mips.json entries are reordered
        // constantly and pinning to index 0 would silently break the moment
        // someone reshuffles the file.
        string memory targetPath = "mip-e00.sol/mipe00.json";
        string memory uriFromJson;
        bool found;

        uint256 i = 0;
        while (
            vm.keyExistsJson(
                mipsJson,
                string.concat(".[", vm.toString(i), "].path")
            )
        ) {
            string memory pathValue = vm.parseJsonString(
                mipsJson,
                string.concat(".[", vm.toString(i), "].path")
            );
            if (keccak256(bytes(pathValue)) == keccak256(bytes(targetPath))) {
                string memory uriKey = string.concat(
                    ".[",
                    vm.toString(i),
                    "].descriptionUri"
                );
                require(
                    vm.keyExistsJson(mipsJson, uriKey),
                    "MIP-E00: mips.json entry missing descriptionUri - run pin-proposal-description workflow"
                );
                uriFromJson = vm.parseJsonString(mipsJson, uriKey);
                found = true;
                break;
            }
            i++;
        }

        require(found, "MIP-E00: entry not found in mips.json");

        bytes memory uriBytes = bytes(uriFromJson);
        require(
            uriBytes.length > 7 &&
                uriBytes[0] == "i" &&
                uriBytes[1] == "p" &&
                uriBytes[2] == "f" &&
                uriBytes[3] == "s" &&
                uriBytes[4] == ":" &&
                uriBytes[5] == "/" &&
                uriBytes[6] == "/",
            "MIP-E00: descriptionUri must be a non-empty ipfs:// URI"
        );

        // When run via ProposalMap.runProposal, PROPOSAL_DESCRIPTION_URI is
        // populated from the same mips.json entry. Catch any drift between
        // the file and the runtime value. Skipped for raw forge script runs
        // where PROPOSAL_DESCRIPTION_URI is empty by design.
        if (bytes(PROPOSAL_DESCRIPTION_URI).length > 0) {
            assertEq(
                PROPOSAL_DESCRIPTION_URI,
                uriFromJson,
                "MIP-E00: PROPOSAL_DESCRIPTION_URI does not match mips.json descriptionUri"
            );
        }
    }
}
