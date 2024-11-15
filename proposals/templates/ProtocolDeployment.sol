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
import {WethUnwrapper} from "@protocol/WethUnwrapper.sol";
import {MWethDelegate} from "@protocol/MWethDelegate.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {ChainIds, OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {JumpRateModel, InterestRateModel} from "@protocol/irm/JumpRateModel.sol";
import {Comptroller, ComptrollerInterface} from "@protocol/Comptroller.sol";

/*
to deploy:

DO_DEPLOY=true DO_AFTER_DEPLOY=true DO_BUILD=true \
DO_RUN=true DO_VALIDATE=true forge script \
src/proposals/mips/mip00.sol:mip00 -vvv --broadcast --account ~/.foundry/keystores/<your-account-keystore-name>

to dry-run:

DO_DEPLOY=true DO_AFTER_DEPLOY=true DO_BUILD=true \
  DO_RUN=true DO_VALIDATE=true forge script \
  src/proposals/mips/mip00.sol:mip00 -vvv --account ~/.foundry/keystores/<your-account-keystore-name>

MIP-O00 deployment environment variables:

```
export DESCRIPTION_PATH=src/proposals/mips/mip-o00/MIP-O00.md
export PRIMARY_FORK_ID=2
export EMISSIONS_PATH=src/proposals/mips/mip-o00/emissionConfigWell.json
export MTOKENS_PATH=src/proposals/mips/mip-o00/mTokens.json
```


*/

contract ProtocolDeplloymentTemplate is HybridProposal, Configs {
    using Address for address;
    using ChainIds for uint256;
    using ProposalActions for *;

    string public constant override name = "MIP-00: System Deploy";
    uint256 public constant liquidationIncentive = 1.1e18; /// liquidation incentive is 110%
    uint256 public constant closeFactor = 0.5e18; /// close factor is 50%, i.e. seize share
    uint8 public constant mTokenDecimals = 8; /// all mTokens have 8 decimals

    /// @notice time before anyone can unpause the contract after a guardian pause
    uint256 public constant permissionlessUnpauseTime = 30 days;

    /// -------------------------------------------------------------------------------------------------- ///
    /// Chain Name	       Wormhole Chain ID   Network ID	Address                                      | ///
    ///  Ethereum (Goerli)   	  2	                5	    0x706abc4E45D419950511e474C7B9Ed348A4a716c   | ///
    ///  Ethereum (Sepolia)	  10002          11155111	    0x4a8bc80Ed5a4067f1CCf107057b8270E0cC11A78   | ///
    ///  Base	                 30    	        84531	    0xA31aa3FDb7aF7Db93d18DDA4e19F811342EDF780   | ///
    ///  Moonbeam	             16	             1284 	    0xC8e2b0cD52Cf01b0Ce87d389Daa3d414d4cE29f3   | ///
    ///  Moonbase alpha          16	             1287	    0xa5B7D85a8f27dd7907dc8FdC21FA5657D5E2F901   | ///
    /// -------------------------------------------------------------------------------------------------- ///

    struct CTokenAddresses {
        address mTokenImpl;
        address irModel;
        address unitroller;
    }

    /// ---------------------- BREAK GLASS GUARDIAN CALLDATA ----------------------

    /// @notice whitelisted calldata for the break glass guardian
    bytes[] public approvedCalldata;

    /// @notice whitelisted calldata for the temporal governor
    bytes[] public temporalGovernanceCalldata;

    /// @notice address of the temporal governor
    address[] public temporalGovernanceTargets;

    /// @notice trusted senders for the temporal governor
    ITemporalGovernor.TrustedSender[] public temporalGovernanceTrustedSenders;

    function initProposal(Addresses) public override {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(vm.envString("DESCRIPTION_PATH"))
        );

        _setProposalDescription(proposalDescription);

        /// MToken/Emission configurations
        _setMTokenConfiguration(vm.envString("MTOKENS_PATH"));

        /// If deploying to mainnet again these values must be adjusted
        /// - endTimestamp must be in the future
        /// - removed mock values that were set in initEmissions function for test execution
        _setEmissionConfiguration(vm.envString("EMISSIONS_PATH"));
    }

    function primaryForkId() public view override returns (uint256 forkId) {
        forkId = vm.envUint("PRIMARY_FORK_ID");

        require(forkId <= OPTIMISM_FORK_ID, "invalid primary fork id");
    }

    /// @notice the deployer should have both USDBC, WETH and any other assets that will be started as
    /// listed to be able to deploy on base. This allows the deployer to be able to initialize the
    /// markets with a balance to avoid exploits
    function deploy(Addresses addresses, address deployer) public override {
        /// emission config sanity check
        require(
            cTokenConfigurations[block.chainid].length ==
                emissions[block.chainid].length,
            "emissions length not equal to cTokenConfigurations length"
        );
        addresses.addRestriction(block.chainid);

        /// ------- TemporalGovernor -------

        if (!addresses.isAddressSet("TEMPORAL_GOVERNOR")) {
            TemporalGovernor.TrustedSender[]
                memory trustedSenders = new TemporalGovernor.TrustedSender[](1);

            addresses.addRestriction(block.chainid.toMoonbeamChainId());
            /// this should return the moonbeam/moonbase wormhole chain id
            trustedSenders[0].chainId = block
                .chainid
                .toMoonbeamWormholeChainId();
            trustedSenders[0].addr = addresses.getAddress(
                "MULTICHAIN_GOVERNOR_PROXY",
                /// this should return the moonbeam/moonbase chain id
                block.chainid.toMoonbeamChainId()
            );

            /// disallow getting any addreses from moonbeam from this point forward
            addresses.removeRestriction();

            /// this will be the governor for all the contracts
            TemporalGovernor governor = new TemporalGovernor(
                addresses.getAddress("WORMHOLE_CORE"), /// get wormhole core address for the chain deployment is on
                temporalGovDelay[block.chainid], /// get timelock period for deployment chain is on
                permissionlessUnpauseTime,
                trustedSenders
            );
            addresses.addAddress("TEMPORAL_GOVERNOR", address(governor));
        }

        deployAndMint(addresses);
        init(addresses);

        /// ------- Reward Distributor -------

        if (!addresses.isAddressSet("MRD_IMPL")) {
            MultiRewardDistributor distributor = new MultiRewardDistributor();
            addresses.addAddress("MRD_IMPL", address(distributor));
        }

        /// ------- Unitroller/Comptroller -------

        if (
            !addresses.isAddressSet("UNITROLLER") &&
            !addresses.isAddressSet("COMPTROLLER")
        ) {
            Unitroller unitroller = new Unitroller();
            Comptroller comptroller = new Comptroller();
            unitroller._setPendingImplementation(address(comptroller));
            comptroller._become(unitroller);

            addresses.addAddress("COMPTROLLER", address(comptroller));
            addresses.addAddress("UNITROLLER", address(unitroller));
        }

        /// ------- PROXY ADMIN / MRD_IMPL -------

        if (
            !addresses.isAddressSet("MRD_PROXY_ADMIN") &&
            !addresses.isAddressSet("MRD_PROXY")
        ) {
            ProxyAdmin proxyAdmin = new ProxyAdmin();
            addresses.addAddress("MRD_PROXY_ADMIN", address(proxyAdmin));

            bytes memory initData = abi.encodeWithSignature(
                "initialize(address,address)",
                addresses.getAddress("UNITROLLER"),
                addresses.getAddress("SECURITY_COUNCIL")
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

        if (!addresses.isAddressSet("WETH_UNWRAPPER")) {
            WethUnwrapper unwrapper = new WethUnwrapper(
                addresses.getAddress("WETH")
            );
            addresses.addAddress("WETH_UNWRAPPER", address(unwrapper));
        }

        if (!addresses.isAddressSet("MWETH_IMPLEMENTATION")) {
            MWethDelegate delegate = new MWethDelegate(
                addresses.getAddress("WETH_UNWRAPPER")
            );

            addresses.addAddress("MWETH_IMPLEMENTATION", address(delegate));
        }

        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);

        //// create all of the CTokens according to the configuration in Config.sol
        for (uint256 i = 0; i < cTokenConfigs.length; i++) {
            Configs.CTokenConfiguration memory config = cTokenConfigs[i];

            /// ----- Jump Rate IRM -------

            string memory addressString = string(
                abi.encodePacked("JUMP_RATE_IRM_", config.addressesString)
            );

            if (!addresses.isAddressSet(addressString)) {
                address irModel = address(
                    new JumpRateModel(
                        config.jrm.baseRatePerYear,
                        config.jrm.multiplierPerYear,
                        config.jrm.jumpMultiplierPerYear,
                        config.jrm.kink
                    )
                );

                addresses.addAddress(addressString, address(irModel));
            }

            if (!addresses.isAddressSet(config.addressesString)) {
                /// stack isn't too deep
                CTokenAddresses memory addr = CTokenAddresses({
                    mTokenImpl: keccak256(
                        abi.encodePacked(config.addressesString)
                    ) == keccak256(abi.encodePacked("MOONWELL_WETH"))
                        ? addresses.getAddress("MWETH_IMPLEMENTATION")
                        : addresses.getAddress("MTOKEN_IMPLEMENTATION"),
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

                addresses.addAddress(config.addressesString, address(mToken));
            }
        }
        if (!addresses.isAddressSet("CHAINLINK_ORACLE")) {
            /// deploy oracle, set price oracle
            ChainlinkOracle oracle = new ChainlinkOracle("null_asset");
            addresses.addAddress("CHAINLINK_ORACLE", address(oracle));
        }

        if (!addresses.isAddressSet("WETH_ROUTER")) {
            WETHRouter router = new WETHRouter(
                WETH9(addresses.getAddress("WETH")),
                MErc20(addresses.getAddress("MOONWELL_WETH"))
            );
            addresses.addAddress("WETH_ROUTER", address(router));
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

            address governor = addresses.getAddress("TEMPORAL_GOVERNOR");

            ChainlinkOracle oracle = ChainlinkOracle(
                addresses.getAddress("CHAINLINK_ORACLE")
            );

            /// set temporal governor as owner of the proxy admin
            proxyAdmin.transferOwnership(governor);

            TemporalGovernor(payable(governor)).transferOwnership(
                addresses.getAddress("SECURITY_COUNCIL")
            );

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

                    /// set mint paused for all MTokens
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
                    mTokens[i]._setPendingAdmin(payable(governor)); /// set governor as pending admin of the mToken

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
                addresses.getAddress("CAP_GUARDIAN")
            );
            Comptroller(address(unitroller))._setSupplyCapGuardian(
                addresses.getAddress("CAP_GUARDIAN")
            );
            Comptroller(address(unitroller))._setPauseGuardian(
                addresses.getAddress("SECURITY_COUNCIL")
            );

            /// set temporal governor as the pending admin
            unitroller._setPendingAdmin(governor);

            /// set temporal governor as the admin of the chainlink feed
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

        uint256 cTokenConfigsLength = cTokenConfigs.length;
        unchecked {
            for (uint256 i = 0; i < cTokenConfigsLength; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];
                address tokenAddress = addresses.getAddress(
                    config.tokenAddressName
                );
                deal(
                    tokenAddress,
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    cTokenConfigs[i].initialMintAmount
                );
            }
        }
    }

    function build(Addresses addresses) public override {
        if (approvedCalldata.length == 0) {
            _buildCalldata(addresses);
        }

        addresses.addRestriction(block.chainid.toMoonbeamChainId());

        /// update approved break glass guardian calldata in Multichain Governor
        _pushAction(
            addresses.getAddress(
                "MULTICHAIN_GOVERNOR_PROXY",
                block.chainid.toMoonbeamChainId()
            ),
            abi.encodeWithSignature(
                "updateApprovedCalldata(bytes,bool)",
                approvedCalldata[0],
                true
            ),
            "Whitelist break glass calldata to add the Artemis Timelock as a trusted sender in the Temporal Governor",
            ActionType.Moonbeam
        );

        /// remove all restrictions
        addresses.removeRestriction();

        /// ------------ UNITROLLER ACCEPT ADMIN ------------

        /// Unitroller configuration
        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Temporal governor accepts admin on Unitroller"
        );
        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);

        unchecked {
            for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];

                address cTokenAddress = addresses.getAddress(
                    config.addressesString
                );

                /// ------------ MTOKEN MARKET ACTIVIATION ------------

                /// temporal governor accepts admin of mToken
                _pushAction(
                    cTokenAddress,
                    abi.encodeWithSignature("_acceptAdmin()"),
                    "Temporal governor accepts admin on mToken"
                );
            }
        }

        // TODO remove this after mipo00 deployment
        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            block.chainid
        );

        unchecked {
            for (uint256 i = 0; i < emissionConfig.length; i++) {
                EmissionConfig memory config = emissionConfig[i];

                _pushAction(
                    addresses.getAddress("MRD_PROXY"),
                    abi.encodeWithSignature(
                        "_addEmissionConfig(address,address,address,uint256,uint256,uint256)",
                        addresses.getAddress(config.mToken),
                        addresses.getAddress(config.owner),
                        addresses.getAddress(config.emissionToken),
                        config.supplyEmissionPerSec,
                        config.borrowEmissionsPerSec,
                        config.endTime
                    ),
                    "Add emission config"
                );
            }
        }
    }

    function run(Addresses addresses, address) public override {
        require(
            actions.proposalActionTypeCount(ActionType(primaryForkId())) > 0,
            "MIP-00: should have actions on the chain being deployed to"
        );

        require(
            actions.proposalActionTypeCount(ActionType.Moonbeam) == 1,
            "MIP-00: should have 1 moonbeam actions"
        );

        super.run(addresses, address(0));
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        TemporalGovernor governor = TemporalGovernor(
            payable(addresses.getAddress("TEMPORAL_GOVERNOR"))
        );

        assertEq(governor.owner(), addresses.getAddress("SECURITY_COUNCIL"));
        assertEq(temporalGovDelay[block.chainid], governor.proposalDelay());

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
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                "temporal governor not admin of unitroller"
            );
            assertEq(
                Comptroller(address(unitroller)).pendingAdmin(),
                address(0)
            );
            assertEq(
                Comptroller(address(unitroller)).pauseGuardian(),
                addresses.getAddress("SECURITY_COUNCIL")
            );
            assertEq(
                Comptroller(address(unitroller)).supplyCapGuardian(),
                addresses.getAddress("CAP_GUARDIAN")
            );
            assertEq(
                Comptroller(address(unitroller)).borrowCapGuardian(),
                addresses.getAddress("CAP_GUARDIAN")
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

        /// assert weth unwrapper is properly tied to the weth contract and
        /// that mWETH delegate is tied to the unwrapper

        {
            WethUnwrapper unwrapper = WethUnwrapper(
                payable(addresses.getAddress("WETH_UNWRAPPER"))
            );
            assertEq(
                unwrapper.weth(),
                addresses.getAddress("WETH"),
                "weth incorrectly set in unwrapper"
            );

            MWethDelegate delegate = MWethDelegate(
                addresses.getAddress("MWETH_IMPLEMENTATION")
            );
            assertEq(
                delegate.wethUnwrapper(),
                address(unwrapper),
                "unwrapper incorrectly set in delegate"
            );

            MWethDelegate mToken = MWethDelegate(
                addresses.getAddress("MOONWELL_WETH")
            );
            assertEq(
                mToken.wethUnwrapper(),
                address(unwrapper),
                "unwrapper incorrectly set in mToken proxy"
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
                addresses.getAddress("SECURITY_COUNCIL")
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

        /// assert proxy admin is owned by temporal governor
        {
            ProxyAdmin proxyAdmin = ProxyAdmin(
                addresses.getAddress("MRD_PROXY_ADMIN")
            );
            assertEq(proxyAdmin.owner(), address(governor));
        }

        /// admin is owned by proxy admin
        {
            validateProxy(
                vm,
                addresses.getAddress("MRD_PROXY"),
                addresses.getAddress("MRD_IMPL"),
                addresses.getAddress("MRD_PROXY_ADMIN"),
                "MRD_PROXY"
            );
        }

        assertEq(
            address(governor.wormholeBridge()),
            addresses.getAddress("WORMHOLE_CORE"),
            "temporal governor wormhole core set incorrectly"
        );

        addresses.addRestriction(block.chainid.toMoonbeamChainId());
        assertTrue(
            governor.isTrustedSender(
                block.chainid.toMoonbeamWormholeChainId(),
                addresses
                    .getAddress(
                        "MULTICHAIN_GOVERNOR_PROXY",
                        block.chainid.toMoonbeamChainId()
                    )
                    .toBytes()
            ),
            "multichain governor not trusted"
        );
        addresses.removeRestriction();

        assertEq(
            governor
                .allTrustedSenders(block.chainid.toMoonbeamWormholeChainId())
                .length,
            1,
            "multichain governor incorrect trusted sender count from Moonbeam"
        );

        {
            Comptroller comptroller = Comptroller(
                addresses.getAddress("UNITROLLER")
            );

            assertEq(comptroller.closeFactorMantissa(), closeFactor);
            assertEq(
                comptroller.liquidationIncentiveMantissa(),
                liquidationIncentive
            );
            ChainlinkOracle oracle = ChainlinkOracle(
                addresses.getAddress("CHAINLINK_ORACLE")
            );

            assertEq(oracle.admin(), address(governor));

            Configs.CTokenConfiguration[]
                memory cTokenConfigs = getCTokenConfigurations(block.chainid);

            unchecked {
                for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                    Configs.CTokenConfiguration memory config = cTokenConfigs[
                        i
                    ];

                    /// oracle price feed checks
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

                    /// CToken Assertions
                    assertTrue(
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

                    /// assert cToken admin is the temporal governor
                    assertEq(address(mToken.admin()), address(governor));

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

                    if (
                        address(mToken.underlying()) ==
                        addresses.getAddress("WETH")
                    ) {
                        /// assert mToken delegate for MOONWELL_WETH is mWETH_DELEGATE
                        assertEq(
                            address(
                                MErc20Delegator(payable(address(mToken)))
                                    .implementation()
                            ),
                            addresses.getAddress("MWETH_IMPLEMENTATION"),
                            "mweth delegate implementation address incorrect"
                        );
                    } else {
                        /// assert mToken delegate is uniform across contracts
                        assertEq(
                            address(
                                MErc20Delegator(payable(address(mToken)))
                                    .implementation()
                            ),
                            addresses.getAddress("MTOKEN_IMPLEMENTATION"),
                            "mtoken delegate implementation address incorrect"
                        );
                    }

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

        if (approvedCalldata.length == 0) {
            _buildCalldata(addresses);
        }

        bytes memory whitelistedCalldata = approvedCalldata[0];

        vm.selectFork(MOONBEAM_FORK_ID);
        addresses.addRestriction(block.chainid.toMoonbeamChainId());

        MultichainGovernor multiChainGovernor = MultichainGovernor(
            payable(
                addresses.getAddress(
                    "MULTICHAIN_GOVERNOR_PROXY",
                    block.chainid.toMoonbeamChainId()
                )
            )
        );
        /// remove the moonbeam restriction from addresses
        addresses.removeRestriction();

        assertTrue(
            multiChainGovernor.whitelistedCalldatas(whitelistedCalldata),
            "multichain governor should have whitelisted break glass guardian calldata"
        );

        vm.selectFork(primaryForkId());
    }

    function _buildCalldata(Addresses addresses) internal {
        addresses.addRestriction(block.chainid.toMoonbeamChainId());
        /// get timelock from Moonbeam
        address artemisTimelock = addresses.getAddress(
            "MOONBEAM_TIMELOCK",
            block.chainid.toMoonbeamChainId()
        );
        addresses.removeRestriction();

        /// get temporal governor
        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");

        temporalGovernanceTargets.push(temporalGovernor);

        temporalGovernanceTrustedSenders.push(
            ITemporalGovernor.TrustedSender({
                chainId: MOONBEAM_WORMHOLE_CHAIN_ID, /// this chainId is 16 (MOONBEAM_WORMHOLE_CHAIN_ID) regardless of testnet or mainnet
                addr: artemisTimelock /// the timelock on moonbeam
            })
        );

        /// roll back trusted senders to the artemis timelock
        /// in reality this just adds the artemis timelock as a trusted sender
        /// a second proposal is needed to revoke the Multichain Governor as a trusted sender
        temporalGovernanceCalldata.push(
            abi.encodeWithSignature(
                "setTrustedSenders((uint16,address)[])",
                temporalGovernanceTrustedSenders
            )
        );

        approvedCalldata.push(
            abi.encodeWithSignature(
                "publishMessage(uint32,bytes,uint8)",
                /// arbitrary nonce
                1000,
                abi.encode(
                    /// target is temporal governor, this passes intended recipient check
                    temporalGovernanceTargets[0],
                    /// sets temporal governor target to itself
                    temporalGovernanceTargets,
                    /// sets values to array filled with 0 values
                    new uint256[](1),
                    /// sets calldata to a call to the setTrustedSenders((uint16,address)[])
                    /// function with artemis timelock as the address and moonbeam wormhole
                    /// chain id as the chain id
                    temporalGovernanceCalldata
                ),
                /// consistency level ignored as Moonbeam has instant finality
                200
            )
        );
    }
}
