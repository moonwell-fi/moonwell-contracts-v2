//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {MToken} from "@protocol/core/MToken.sol";
import {MErc20} from "@protocol/core/MErc20.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Proposal} from "@test/proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {Unitroller} from "@protocol/core/Unitroller.sol";
import {MErc20Delegate} from "@protocol/core/MErc20Delegate.sol";
import {MErc20Delegator} from "@protocol/core/MErc20Delegator.sol";
import {ChainlinkOracle} from "@protocol/core/Oracles/ChainlinkOracle.sol";
import {CrossChainProposal} from "@test/proposals/proposalTypes/CrossChainProposal.sol";
import {JumpRateModel, InterestRateModel} from "@protocol/core/IRModels/JumpRateModel.sol";
import {Comptroller, ComptrollerInterface} from "@protocol/core/Comptroller.sol";

/// @notice This MIP deploys and lists new MTokens for the protocol.
/// It reads in the configuration from Config.sol, which reads in the mainnetMTokens.json file and deploys the MTokens specified in that file.
/// @dev be sure to include all necessary underlying and price feed addresses in the Addresses.sol contract for the network
/// the MTokens are being deployed to.
contract mip02 is Proposal, CrossChainProposal, ChainIds, Configs {
    string public constant name = "MIP02";
    uint8 public constant mTokenDecimals = 8; /// all mTokens have 8 decimals

    constructor() {
        _setNonce(2);
    }

    struct CTokenAddresses {
        address mTokenImpl;
        address irModel;
        address unitroller;
    }

    /// @notice the deployer should have both USDC, WETH and any other assets that will be started as
    /// listed to be able to deploy on base. This allows the deployer to be able to initialize the
    /// markets with a balance to avoid exploits
    function deploy(Addresses addresses, address deployer) public {
        /// ------ MTOKENS -------

        {
            MErc20Delegate mTokenLogic = new MErc20Delegate();
            addresses.addAddress("MTOKEN_IMPLEMENTATION", address(mTokenLogic));
        }

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
    }

    function afterDeploy(Addresses addresses, address) public {
        address governor = addresses.getAddress("TEMPORAL_GOVERNOR");

        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);
        MToken[] memory mTokens = new MToken[](cTokenConfigs.length);
        uint256[] memory supplyCaps = new uint256[](cTokenConfigs.length);
        uint256[] memory borrowCaps = new uint256[](cTokenConfigs.length);

        //// set mint paused for all of the deployed MTokens
        unchecked {
            for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];
                supplyCaps[i] = config.supplyCap;
                borrowCaps[i] = config.borrowCap;

                /// get the mToken
                mTokens[i] = MToken(
                    addresses.getAddress(config.addressesString)
                );

                mTokens[i]._setReserveFactor(config.reserveFactor);
                mTokens[i]._setProtocolSeizeShare(config.seizeShare);
                mTokens[i]._setPendingAdmin(payable(governor)); /// set governor as pending admin of the mToken
            }
        }
    }

    function build(Addresses addresses) public {
        ChainlinkOracle oracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );

        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);
        uint256[] memory supplyCaps = new uint256[](cTokenConfigs.length);
        uint256[] memory borrowCaps = new uint256[](cTokenConfigs.length);
        MToken[] memory mTokens = new MToken[](cTokenConfigs.length);

        address unitrollerAddress = addresses.getAddress("UNITROLLER");

        /// set mint unpaused for all of the deployed MTokens
        unchecked {
            for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];

                supplyCaps[i] = config.supplyCap;
                borrowCaps[i] = config.borrowCap;

                address cTokenAddress = addresses.getAddress(
                    config.addressesString
                );
                mTokens[i] = MToken(cTokenAddress);

                _pushCrossChainAction(
                    address(oracle),
                    abi.encodeWithSignature(
                        "setFeed(string,uint256)",
                        ERC20(addresses.getAddress(config.tokenAddressName))
                            .symbol(),
                        addresses.getAddress(config.priceFeedName)
                    ),
                    "Temporal governor accepts admin on mToken"
                );

                _pushCrossChainAction(
                    unitrollerAddress,
                    abi.encodeWithSignature(
                        "_supportMarket(address)",
                        addresses.getAddress(config.addressesString)
                    ),
                    "Unpause MToken market"
                );

                /// ------------ MTOKEN MARKET ACTIVIATION ------------

                /// temporal governor accepts admin of mToken
                _pushCrossChainAction(
                    cTokenAddress,
                    abi.encodeWithSignature("_acceptAdmin()"),
                    "Temporal governor accepts admin on mToken"
                );

                _pushCrossChainAction(
                    unitrollerAddress,
                    abi.encodeWithSignature(
                        "_setMintPaused(address,bool)",
                        cTokenAddress,
                        false
                    ),
                    "Unpause MToken market"
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
                        cTokenAddress,
                        config.collateralFactor
                    ),
                    "Set collateral factor for the market"
                );
            }
        }

        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setMarketSupplyCaps(address[],uint256[])",
                mTokens,
                supplyCaps
            ),
            "Set market supply caps for each mToken"
        );

        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setMarketBorrowCaps(address[],uint256[])",
                mTokens,
                borrowCaps
            ),
            "Set market borrow caps for each mToken"
        );
    }

    function run(Addresses addresses, address) public {
        _simulateCrossChainActions(addresses.getAddress("TEMPORAL_GOVERNOR"));
    }

    function printCalldata(Addresses addresses) public {
        printActions(
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            addresses.getAddress("WORMHOLE_CORE")
        );
    }

    function teardown(Addresses addresses, address) public pure {}

    function validate(Addresses addresses, address) public {
        address governor = addresses.getAddress("TEMPORAL_GOVERNOR");

        {
            ChainlinkOracle oracle = ChainlinkOracle(
                addresses.getAddress("CHAINLINK_ORACLE")
            );

            assertEq(oracle.admin(), governor);
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

        {
            Comptroller comptroller = Comptroller(
                addresses.getAddress("UNITROLLER")
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
                    assertTrue(mToken.balanceOf(governor) > 0); /// governor has some
                    assertEq(mToken.balanceOf(address(0)), 1); /// address 0 has 1 wei of assets

                    /// assert cToken admin is the temporal governor
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
    }
}
