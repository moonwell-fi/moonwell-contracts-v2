//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";
import "@protocol/utils/ChainIds.sol";
import "@protocol/utils/String.sol";

import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {MToken} from "@protocol/MToken.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {JumpRateModel, InterestRateModel} from "@protocol/irm/JumpRateModel.sol";
import {Comptroller, ComptrollerInterface} from "@protocol/Comptroller.sol";

/**
 * After setting up the shell file, execute the proposal with the following command:
 * source path/to/env.sh && forge script proposals/templates/MarketAdd.sol -vvv
 */
contract MarketAddTemplate is HybridProposal, Networks, ParameterValidation {
    using String for string;
    using stdJson for string;
    using ChainIds for uint256;
    using ProposalActions for *;
    using stdStorage for StdStorage;

    /// @notice all MTokens have 8 decimals
    uint8 public constant mTokenDecimals = 8;

    struct JRMParams {
        uint256 baseRatePerYear;
        uint256 jumpMultiplierPerYear;
        uint256 kink;
        uint256 multiplierPerYear;
    }

    struct MTokenConfiguration {
        string addressesString;
        uint256 borrowCap;
        uint256 collateralFactor;
        uint256 initialMintAmount;
        JRMParams jrm;
        string name;
        string priceFeedName;
        uint256 reserveFactor;
        uint256 seizeShare;
        uint256 supplyCap;
        string symbol;
        string tokenAddressName;
    }

    struct EmissionConfiguration {
        uint56 borrowEmissionsPerSec;
        string emissionToken;
        uint56 endTime;
        string mToken;
        string owner;
        uint56 supplyEmissionPerSec;
    }

    mapping(uint256 chainid => MTokenConfiguration[]) mTokens;
    mapping(uint256 chainid => EmissionConfiguration[]) emissionConfigurations;

    modifier selectPrimaryFork() {
        _;

        if (vm.activeFork() != primaryForkId()) {
            vm.selectFork(primaryForkId());
        }
    }

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(vm.envString("DESCRIPTION_PATH"))
        );

        _setProposalDescription(proposalDescription);
    }

    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        initProposal(addresses);

        (, address deployerAddress, ) = vm.readCallers();

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);

        if (DO_BUILD) build(addresses);
        if (DO_RUN) run(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_VALIDATE) {
            validate(addresses, deployerAddress);
            console.log("Validation completed for proposal ", this.name());
        }
        if (DO_PRINT) {
            printProposalActionSteps();

            addresses.removeAllRestrictions();
            printCalldata(addresses);

            _printAddressesChanges(addresses);
        }
    }

    function name() external pure override returns (string memory) {
        return "MIP Market Add";
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function initProposal(Addresses) public override {
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            _saveMTokens(chainId);
            _saveEmissionConfigurations(chainId);
        }
    }

    function deploy(
        Addresses addresses,
        address deployer
    ) public override selectPrimaryFork {
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            _deployToChain(addresses, deployer, chainId);
        }
    }

    function afterDeploy(
        Addresses addresses,
        address deployer
    ) public override selectPrimaryFork {
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            _afterDeployToChain(addresses, chainId, deployer);
        }
    }

    function build(Addresses addresses) public override selectPrimaryFork {
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            _buildToChain(addresses, chainId);
        }
    }

    function validate(
        Addresses addresses,
        address
    ) public override selectPrimaryFork {
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            _validate(addresses, chainId);
        }
    }

    function _validate(Addresses addresses, uint256 chainId) internal {
        vm.selectFork(chainId.toForkId());

        MTokenConfiguration[] memory _mTokens = mTokens[chainId];

        address governor;
        if (vm.activeFork() == MOONBEAM_FORK_ID) {
            governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");
        } else {
            governor = addresses.getAddress("TEMPORAL_GOVERNOR");
        }

        Comptroller comptroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );

        for (uint256 i = 0; i < _mTokens.length; i++) {
            MTokenConfiguration memory config = _mTokens[i];

            uint256 borrowCap = comptroller.borrowCaps(
                addresses.getAddress(config.addressesString)
            );
            uint256 supplyCap = comptroller.supplyCaps(
                addresses.getAddress(config.addressesString)
            );

            uint256 maxBorrowCap = (supplyCap * 10) / 9;

            assertTrue(
                borrowCap <= maxBorrowCap,
                "borrow cap exceeds max borrow"
            );

            /// CToken Assertions
            assertFalse(
                comptroller.mintGuardianPaused(
                    addresses.getAddress(config.addressesString)
                ),
                "minting paused by guardian"
            ); /// minting allowed by guardian

            assertFalse(
                comptroller.borrowGuardianPaused(
                    addresses.getAddress(config.addressesString)
                ),
                "borrowing paused by guardian"
            ); /// borrowing allowed by guardian

            assertEq(borrowCap, config.borrowCap, "borrow cap incorrect");
            assertEq(supplyCap, config.supplyCap, "supply cap incorrect");

            /// assert mToken irModel is correct
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
            assertEq(mToken.protocolSeizeShareMantissa(), config.seizeShare);
            assertEq(mToken.reserveFactorMantissa(), config.reserveFactor);

            /// assert initial mToken balances are correct
            assertTrue(mToken.balanceOf(address(governor)) > 0); /// governor has some
            assertEq(mToken.balanceOf(address(0)), 1); /// address 0 has 1 wei of assets

            /// assert mToken admin is the temporal governor / multichain governor
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

            /// assert mToken delegate is uniform across contracts
            assertEq(
                address(
                    MErc20Delegator(payable(address(mToken))).implementation()
                ),
                addresses.getAddress("MTOKEN_IMPLEMENTATION")
            );

            uint256 initialExchangeRate = (10 **
                (8 +
                    IERC20(addresses.getAddress(config.tokenAddressName))
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

        if (vm.activeFork() != MOONBEAM_FORK_ID) {
            MultiRewardDistributor distributor = MultiRewardDistributor(
                addresses.getAddress("MRD_PROXY")
            );
            EmissionConfiguration[]
                memory emissionConfig = emissionConfigurations[chainId];

            for (uint256 i = 0; i < emissionConfig.length; i++) {
                EmissionConfiguration memory config = emissionConfig[i];
                MultiRewardDistributorCommon.MarketConfig
                    memory marketConfig = distributor.getConfigForMarket(
                        MToken(addresses.getAddress(config.mToken)),
                        addresses.getAddress(config.emissionToken)
                    );

                assertEq(
                    marketConfig.owner,
                    addresses.getAddress(config.owner),
                    "MRD owner config incorrect"
                );
                assertEq(
                    marketConfig.owner,
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    "MRD owner config incorrect"
                );
                assertEq(
                    marketConfig.emissionToken,
                    addresses.getAddress(config.emissionToken),
                    "MRD emission token config incorrect"
                );
                assertEq(
                    marketConfig.endTime,
                    config.endTime,
                    "MRD end time config incorrect"
                );
                assertEq(
                    marketConfig.supplyEmissionsPerSec,
                    config.supplyEmissionPerSec,
                    "MRD supply emissions config incorrect"
                );
                assertEq(
                    marketConfig.borrowEmissionsPerSec,
                    config.borrowEmissionsPerSec,
                    "MRD borrow emissions config incorrect"
                );
                assertEq(
                    marketConfig.supplyGlobalIndex,
                    1e36,
                    "MRD supply global index incorrect"
                );
                assertEq(
                    marketConfig.borrowGlobalIndex,
                    1e36,
                    "MRD borrow global index incorrect"
                );
            }
        }
    }

    function _deployToChain(
        Addresses addresses,
        address deployer,
        uint256 chainId
    ) internal {
        MTokenConfiguration[] memory _mTokens = mTokens[chainId];

        if (_mTokens.length == 0) {
            return;
        }

        vm.selectFork(chainId.toForkId());

        for (uint256 i = 0; i < _mTokens.length; i++) {
            MTokenConfiguration memory config = _mTokens[i];
            _validateCaps(addresses, config);

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
                vm.startBroadcast(deployer);
                JumpRateModel irModel = new JumpRateModel(
                    config.jrm.baseRatePerYear,
                    config.jrm.multiplierPerYear,
                    config.jrm.jumpMultiplierPerYear,
                    config.jrm.kink
                );

                vm.stopBroadcast();
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

            /// ---------- MToken ----------
            if (!addresses.isAddressSet(config.addressesString)) {
                /// calculate initial exchange rate
                /// BigNumber.from("10").pow(token.decimals + 8).mul("2");
                /// (10 ** (18 + 8)) * 2 // 18 decimals example
                ///    = 2e26
                /// (10 ** (6 + 8)) * 2 // 6 decimals example
                ///    = 2e14
                uint256 initialExchangeRate = (10 **
                    (IERC20(addresses.getAddress(config.tokenAddressName))
                        .decimals() + 8)) * 2;

                vm.startBroadcast(deployer);

                MErc20Delegator mToken = new MErc20Delegator(
                    addresses.getAddress(config.tokenAddressName),
                    ComptrollerInterface(addresses.getAddress("UNITROLLER")),
                    InterestRateModel(
                        addresses.getAddress(
                            string(
                                abi.encodePacked(
                                    "JUMP_RATE_IRM_",
                                    config.addressesString
                                )
                            )
                        )
                    ),
                    initialExchangeRate,
                    config.name,
                    config.symbol,
                    mTokenDecimals,
                    payable(deployer),
                    addresses.getAddress("MTOKEN_IMPLEMENTATION"),
                    ""
                );

                vm.stopBroadcast();

                addresses.addAddress(config.addressesString, address(mToken));
            }
        }
    }

    function _afterDeployToChain(
        Addresses addresses,
        uint256 chainId,
        address deployer
    ) internal {
        MTokenConfiguration[] memory _mTokens = mTokens[chainId];

        if (_mTokens.length == 0) {
            return;
        }

        vm.selectFork(chainId.toForkId());
        vm.startBroadcast(deployer);
        address governor = addresses.getAddress("TEMPORAL_GOVERNOR");

        for (uint256 i = 0; i < _mTokens.length; i++) {
            MTokenConfiguration memory config = _mTokens[i];
            address mToken = addresses.getAddress(config.addressesString);

            _validateCaps(addresses, config); /// validate supply and borrow caps

            if (
                MToken(mToken).reserveFactorMantissa() !=
                config.reserveFactor &&
                MToken(mToken).protocolSeizeShareMantissa() != config.seizeShare
            ) {
                MToken(mToken)._setReserveFactor(config.reserveFactor);
                MToken(mToken)._setProtocolSeizeShare(config.seizeShare);
                MToken(mToken)._setPendingAdmin(payable(governor)); /// set governor as pending admin of the mToken
            }
        }

        vm.stopBroadcast();
    }

    function _buildToChain(Addresses addresses, uint256 chainId) internal {
        MTokenConfiguration[] memory _mTokens = mTokens[chainId];

        vm.selectFork(chainId.toForkId());
        if (_mTokens.length > 0) {
            address[] memory markets = new address[](_mTokens.length);
            uint256[] memory supplyCaps = new uint256[](_mTokens.length);
            uint256[] memory borrowCaps = new uint256[](_mTokens.length);

            for (uint256 i = 0; i < _mTokens.length; i++) {
                MTokenConfiguration memory config = _mTokens[i];

                supplyCaps[i] = config.supplyCap;
                borrowCaps[i] = config.borrowCap;
                markets[i] = addresses.getAddress(config.addressesString);
            }

            address unitrollerAddress = addresses.getAddress("UNITROLLER");
            address chainlinkOracleAddress = addresses.getAddress(
                "CHAINLINK_ORACLE"
            );

            _pushAction(
                unitrollerAddress,
                abi.encodeWithSignature(
                    "_setMarketSupplyCaps(address[],uint256[])",
                    markets,
                    supplyCaps
                ),
                "Set supply caps MToken market"
            );

            _pushAction(
                unitrollerAddress,
                abi.encodeWithSignature(
                    "_setMarketBorrowCaps(address[],uint256[])",
                    markets,
                    borrowCaps
                ),
                "Set borrow caps MToken market"
            );

            for (uint256 i = 0; i < _mTokens.length; i++) {
                MTokenConfiguration memory config = _mTokens[i];

                address cTokenAddress = addresses.getAddress(
                    config.addressesString
                );

                _pushAction(
                    chainlinkOracleAddress,
                    abi.encodeWithSignature(
                        "setFeed(string,address)",
                        IERC20(addresses.getAddress(config.tokenAddressName))
                            .symbol(),
                        addresses.getAddress(config.priceFeedName)
                    ),
                    "Set price feed for underlying address in MToken market"
                );

                _pushAction(
                    unitrollerAddress,
                    abi.encodeWithSignature(
                        "_supportMarket(address)",
                        addresses.getAddress(config.addressesString)
                    ),
                    "Support MToken market in comptroller"
                );

                /// temporal governor accepts admin of mToken
                _pushAction(
                    cTokenAddress,
                    abi.encodeWithSignature("_acceptAdmin()"),
                    "Temporal governor accepts admin on mToken"
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

                _pushAction(
                    unitrollerAddress,
                    abi.encodeWithSignature(
                        "_setCollateralFactor(address,uint256)",
                        addresses.getAddress(config.addressesString),
                        config.collateralFactor
                    ),
                    "Set Collateral Factor for MToken market in comptroller"
                );
            }
        }

        /// -------------- EMISSION CONFIGURATION --------------
        EmissionConfiguration[] memory emissionConfig = emissionConfigurations[
            chainId
        ];

        if (emissionConfig.length > 0) {
            MultiRewardDistributor mrd = MultiRewardDistributor(
                addresses.getAddress("MRD_PROXY")
            );

            for (uint256 i = 0; i < emissionConfig.length; i++) {
                EmissionConfiguration memory config = emissionConfig[i];

                _pushAction(
                    address(mrd),
                    abi.encodeWithSignature(
                        "_addEmissionConfig(address,address,address,uint256,uint256,uint256)",
                        addresses.getAddress(config.mToken),
                        addresses.getAddress(config.owner),
                        addresses.getAddress(config.emissionToken),
                        config.supplyEmissionPerSec,
                        config.borrowEmissionsPerSec,
                        config.endTime
                    ),
                    "Add emission config for MToken market in MultiRewardDistributor"
                );
            }
        }
    }

    function _saveMTokens(uint256 chainId) internal {
        string memory empty = "";
        string memory envPath = vm.envOr("MTOKENS_PATH", empty);

        if (abi.encodePacked(envPath).length == 0) {
            return;
        }

        string memory encodedJson = vm.readFile(envPath);

        string memory chain = string.concat(".", vm.toString(chainId));

        if (vm.keyExistsJson(encodedJson, chain)) {
            bytes memory parsedJson = vm.parseJson(encodedJson, chain);

            MTokenConfiguration[] memory _mTokens = abi.decode(
                parsedJson,
                (MTokenConfiguration[])
            );

            for (uint256 i = 0; i < _mTokens.length; i++) {
                mTokens[chainId].push(_mTokens[i]);
            }
        }
    }

    function _saveEmissionConfigurations(uint256 chainId) internal {
        string memory encodedJson = vm.readFile(
            vm.envString("EMISSION_CONFIGURATIONS_PATH")
        );

        string memory chain = string.concat(".", vm.toString(chainId));
        if (vm.keyExistsJson(encodedJson, chain)) {
            bytes memory parsedJson = vm.parseJson(encodedJson, chain);

            EmissionConfiguration[] memory emissionConfig = abi.decode(
                parsedJson,
                (EmissionConfiguration[])
            );

            for (uint256 i = 0; i < emissionConfig.length; i++) {
                emissionConfigurations[chainId].push(emissionConfig[i]);
            }
        }
    }

    /// helper function to validate supply and borrow caps
    function _validateCaps(
        Addresses addresses,
        MTokenConfiguration memory config
    ) internal view {
        {
            if (config.supplyCap != 0 || config.borrowCap != 0) {
                uint8 decimals = IERC20(
                    addresses.getAddress(config.tokenAddressName)
                ).decimals();

                /// override defaults to false, dev can set to true to override these checks

                if (
                    config.supplyCap != 0 &&
                    !vm.envOr("OVERRIDE_SUPPLY_CAP", false)
                ) {
                    /// strip off all the decimals
                    uint256 adjustedSupplyCap = config.supplyCap /
                        (10 ** decimals);
                    require(
                        adjustedSupplyCap < 120_000_000,
                        "supply cap suspiciously high, if this is the right supply cap, set OVERRIDE_SUPPLY_CAP environment variable to true"
                    );
                }

                if (
                    config.borrowCap != 0 &&
                    !vm.envOr("OVERRIDE_BORROW_CAP", false)
                ) {
                    uint256 adjustedBorrowCap = config.borrowCap /
                        (10 ** decimals);
                    require(
                        adjustedBorrowCap < 120_000_000,
                        "borrow cap suspiciously high, if this is the right borrow cap, set OVERRIDE_BORROW_CAP environment variable to true"
                    );
                }
            }
        }
    }

    function beforeSimulationHook(Addresses addresses) public override {
        uint256 forkBefore = vm.activeFork();
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            vm.selectFork(chainId.toForkId());

            for (uint256 j = 0; j < mTokens[chainId].length; j++) {
                MTokenConfiguration memory config = mTokens[chainId][j];

                address admin;
                if (vm.activeFork() == MOONBEAM_FORK_ID) {
                    admin = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");
                } else {
                    admin = addresses.getAddress("TEMPORAL_GOVERNOR");
                }

                deal(
                    addresses.getAddress(config.tokenAddressName),
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    config.initialMintAmount
                );
            }
        }

        if (vm.activeFork() != forkBefore) {
            vm.selectFork(forkBefore);
        }
    }
}
