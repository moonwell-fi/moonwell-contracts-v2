//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {Unitroller} from "@protocol/Unitroller.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {MIPProposal} from "@proposals/MIPProposal.s.sol";
import {PriceOracle} from "@protocol/oracles/PriceOracle.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {JumpRateModel, InterestRateModel} from "@protocol/irm/JumpRateModel.sol";
import {Comptroller, ComptrollerInterface} from "@protocol/Comptroller.sol";

/// @notice This lists all new markets provided in `mainnetMTokens.json`
/// This is a template of a MIP proposal that can be used to add new mTokens
/// @dev be sure to include all necessary underlying and price feed addresses
/// in the Addresses.sol contract for the network the MTokens are being deployed on.
contract mip0x is Proposal, CrossChainProposal, Configs {
    /// @notice the name of the proposal
    string public constant name = "MIP Market Creation";

    /// @notice all MTokens have 8 decimals
    uint8 public constant mTokenDecimals = 8;

    /// @notice list of all mTokens that were added to the market with this proposal
    MToken[] public mTokens;

    /// @notice supply caps of all mTokens that were added to the market with this proposal
    uint256[] public supplyCaps;

    /// @notice borrow caps of all mTokens that were added to the market with this proposal
    uint256[] public borrowCaps;

    struct CTokenAddresses {
        address mTokenImpl;
        address irModel;
        address unitroller;
    }

    constructor() {
        /// for example, should be set to
        /// LISTING_PATH="./src/proposals/mips/examples/mip-market-listing/MarketListingDescription.md"
        string memory descriptionPath = vm.envString("LISTING_PATH");
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(descriptionPath)
        );

        _setProposalDescription(proposalDescription);

        delete cTokenConfigurations[block.chainid]; /// wipe existing mToken Configs.sol
        delete emissions[block.chainid]; /// wipe existing reward loaded in Configs.sol

        {
            string memory mtokensPath = vm.envString("MTOKENS_PATH");
            /// MTOKENS_PATH="./src/proposals/mips/examples/mip-market-listing/MTokens.json"
            string memory fileContents = vm.readFile(mtokensPath);
            bytes memory rawJson = vm.parseJson(fileContents);

            CTokenConfiguration[] memory decodedJson = abi.decode(
                rawJson,
                (CTokenConfiguration[])
            );

            for (uint256 i = 0; i < decodedJson.length; i++) {
                require(
                    decodedJson[i].collateralFactor <= 0.95e18,
                    "collateral factor absurdly high, are you sure you want to proceed?"
                );

                /// possible to set supply caps and not borrow caps,
                /// but not set borrow caps and not set supply caps
                if (decodedJson[i].supplyCap != 0) {
                    require(
                        decodedJson[i].supplyCap > decodedJson[i].borrowCap,
                        "borrow cap gte supply cap, are you sure you want to proceed?"
                    );
                } else if (decodedJson[i].borrowCap != 0) {
                    revert("borrow cap must be set with a supply cap");
                }

                cTokenConfigurations[block.chainid].push(decodedJson[i]);
            }
        }

        {
            string memory mtokensPath = vm.envString("EMISSION_PATH");
            /// EMISSION_PATH="./src/proposals/mips/examples/mip-market-listing/RewardStreams.json"
            string memory fileContents = vm.readFile(mtokensPath);
            bytes memory rawJson = vm.parseJson(fileContents);
            EmissionConfig[] memory decodedEmissions = abi.decode(
                rawJson,
                (EmissionConfig[])
            );

            for (uint256 i = 0; i < decodedEmissions.length; i++) {
                emissions[block.chainid].push(decodedEmissions[i]);
            }
        }

        console.log("\n\n------------ LOAD STATS ------------");
        console.log(
            "Loaded %d MToken configs",
            cTokenConfigurations[block.chainid].length
        );
        console.log(
            "Loaded %d reward configs",
            emissions[block.chainid].length
        );
        console.log("\n\n");
    }

    /// @notice no contracts are deployed in this proposal
    function deploy(Addresses addresses, address deployer) public override {
        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);

        uint256 cTokenConfigsLength = cTokenConfigs.length;

        //// create all of the CTokens according to the configuration in Config.sol
        unchecked {
            for (uint256 i = 0; i < cTokenConfigsLength; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];

                /// ----- Jump Rate IRM -------
                {
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
                        address(irModel),
                        true
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
                    address(mToken),
                    true
                );
            }
        }
    }

    function afterDeploy(Addresses addresses, address) public override {
        address governor = addresses.getAddress("TEMPORAL_GOVERNOR");
        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);

        unchecked {
            for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];
                supplyCaps.push(config.supplyCap);
                borrowCaps.push(config.borrowCap);

                /// get the mToken
                mTokens.push(
                    MToken(addresses.getAddress(config.addressesString))
                );

                mTokens[i]._setReserveFactor(config.reserveFactor);
                mTokens[i]._setProtocolSeizeShare(config.seizeShare);
                mTokens[i]._setPendingAdmin(payable(governor)); /// set governor as pending admin of the mToken
            }
        }
    }

    function afterDeploySetup(Addresses addresses) public override {
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

    /// ------------ MTOKEN MARKET ACTIVIATION BUILD ------------

    function build(Addresses addresses) public override {
        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);
        address unitrollerAddress = addresses.getAddress("UNITROLLER");
        address chainlinkOracleAddress = addresses.getAddress(
            "CHAINLINK_ORACLE"
        );

        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setMarketSupplyCaps(address[],uint256[])",
                mTokens,
                supplyCaps
            ),
            "Set supply caps MToken market"
        );

        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setMarketBorrowCaps(address[],uint256[])",
                mTokens,
                borrowCaps
            ),
            "Set borrow caps MToken market"
        );

        unchecked {
            for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];

                address cTokenAddress = addresses.getAddress(
                    config.addressesString
                );

                _pushCrossChainAction(
                    chainlinkOracleAddress,
                    abi.encodeWithSignature(
                        "setFeed(string,address)",
                        ERC20(addresses.getAddress(config.tokenAddressName))
                            .symbol(),
                        addresses.getAddress(config.priceFeedName)
                    ),
                    "Set price feed for underlying address in MToken market"
                );

                _pushCrossChainAction(
                    unitrollerAddress,
                    abi.encodeWithSignature(
                        "_supportMarket(address)",
                        addresses.getAddress(config.addressesString)
                    ),
                    "Support MToken market in comptroller"
                );

                /// temporal governor accepts admin of mToken
                _pushCrossChainAction(
                    cTokenAddress,
                    abi.encodeWithSignature("_acceptAdmin()"),
                    "Temporal governor accepts admin on mToken"
                );

                /// Approvals
                _pushCrossChainAction(
                    addresses.getAddress(config.tokenAddressName),
                    abi.encodeWithSignature(
                        "approve(address,uint256)",
                        cTokenAddress,
                        config.initialMintAmount
                    ),
                    "Approve underlying token to be spent by market"
                );

                /// Initialize markets
                _pushCrossChainAction(
                    cTokenAddress,
                    abi.encodeWithSignature(
                        "mint(uint256)",
                        config.initialMintAmount
                    ),
                    "Initialize token market to prevent exploit"
                );

                _pushCrossChainAction(
                    cTokenAddress,
                    abi.encodeWithSignature(
                        "transfer(address,uint256)",
                        address(0),
                        1
                    ),
                    "Send 1 wei to address 0 to prevent a state where market has 0 mToken"
                );

                _pushCrossChainAction(
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

        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            block.chainid
        );
        MultiRewardDistributor mrd = MultiRewardDistributor(
            addresses.getAddress("MRD_PROXY")
        );

        unchecked {
            for (uint256 i = 0; i < emissionConfig.length; i++) {
                EmissionConfig memory config = emissionConfig[i];

                _pushCrossChainAction(
                    address(mrd),
                    abi.encodeWithSignature(
                        "_addEmissionConfig(address,address,address,uint256,uint256,uint256)",
                        MToken(addresses.getAddress(config.mToken)),
                        addresses.getAddress(config.owner),
                        config.emissionToken,
                        config.supplyEmissionPerSec,
                        config.borrowEmissionsPerSec,
                        config.endTime
                    ),
                    "Add emission config for MToken market in MultiRewardDistributor"
                );
            }
        }
    }

    function run(
        Addresses addresses,
        address
    ) public override(CrossChainProposal, MIPProposal) {
        printCalldata(addresses);
        _simulateCrossChainActions(addresses.getAddress("TEMPORAL_GOVERNOR"));
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);
        address governor = addresses.getAddress("TEMPORAL_GOVERNOR");
        Comptroller comptroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );

        unchecked {
            for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];

                /// TODO validate borrow cap is always lte 90% of supply cap
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
                    )
                ); /// minting allowed by guardian
                assertFalse(
                    comptroller.borrowGuardianPaused(
                        addresses.getAddress(config.addressesString)
                    )
                ); /// borrowing allowed by guardian
                assertEq(borrowCap, config.borrowCap);
                assertEq(supplyCap, config.supplyCap);

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
                assertEq(mToken.reserveFactorMantissa(), config.reserveFactor);

                /// assert initial mToken balances are correct
                assertTrue(mToken.balanceOf(address(governor)) > 0); /// governor has some
                assertEq(mToken.balanceOf(address(0)), 1); /// address 0 has 1 wei of assets

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
                            config.emissionToken
                        );

                    assertEq(
                        marketConfig.owner,
                        addresses.getAddress(config.owner)
                    );
                    assertEq(marketConfig.emissionToken, config.emissionToken);
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
    }
}
