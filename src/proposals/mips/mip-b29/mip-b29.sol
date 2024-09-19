//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {EIP20Interface} from "@protocol/EIP20Interface.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {JumpRateModel, InterestRateModel} from "@protocol/irm/JumpRateModel.sol";
import {Comptroller, ComptrollerInterface} from "@protocol/Comptroller.sol";

/// @notice This lists all new markets provided in `MTokens.json`
/// This is a template of a MIP proposal that can be used to add new mTokens
/// @dev be sure to include all necessary underlying and price feed addresses
/// in the Addresses.sol contract for the network the MTokens are being deployed on.
contract mipb29 is HybridProposal, Configs {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice the name of the proposal
    string public constant override name = "MIP-B29";

    /// @notice all MTokens have 8 decimals
    uint8 public constant mTokenDecimals = 8;

    /// @notice list of all mTokens that were added to the market with this proposal
    EnumerableSet.AddressSet private mTokens;

    /// @notice supply caps of all mTokens that were added to the market with this proposal
    uint256[] public supplyCaps;

    /// @notice borrow caps of all mTokens that were added to the market with this proposal
    uint256[] public borrowCaps;

    struct CTokenAddresses {
        address mTokenImpl;
        address irModel;
        address unitroller;
    }

    string constant descriptionPath = "./src/proposals/mips/mip-b29/MIP-B29.md";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(descriptionPath)
        );

        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function deploy(Addresses addresses, address deployer) public override {
        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);

        if (cTokenConfigs.length == 0) {
            _setMTokenConfiguration(
                "./src/proposals/mips/mip-b29/MTokens.json"
            );
            _setEmissionConfiguration(
                "./src/proposals/mips/mip-b29/RewardStreams.json"
            );

            cTokenConfigs = getCTokenConfigurations(block.chainid);
        }

        //// create all of the CTokens according to the configuration in Config.sol
        unchecked {
            for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];

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

                /// ---------- MToken ----------
                if (!addresses.isAddressSet(config.addressesString)) {
                    /// stack isn't too deep
                    CTokenAddresses memory addr = CTokenAddresses({
                        mTokenImpl: addresses.getAddress(
                            "MTOKEN_IMPLEMENTATION"
                        ),
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
                        address(mToken)
                    );
                }
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

                /// get the mToken
                mTokens.add(addresses.getAddress(config.addressesString));

                _validateCaps(addresses, config); /// validate supply and borrow caps

                if (
                    MToken(mTokens.at(i)).reserveFactorMantissa() !=
                    config.reserveFactor &&
                    MToken(mTokens.at(i)).protocolSeizeShareMantissa() !=
                    config.seizeShare
                ) {
                    MToken(mTokens.at(i))._setReserveFactor(
                        config.reserveFactor
                    );
                    MToken(mTokens.at(i))._setProtocolSeizeShare(
                        config.seizeShare
                    );
                    MToken(mTokens.at(i))._setPendingAdmin(payable(governor)); /// set governor as pending admin of the mToken
                }
            }
        }
    }

    function preBuildMock(Addresses addresses) public override {
        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);

        if (cTokenConfigs.length == 0) {
            _setMTokenConfiguration(
                "./src/proposals/mips/mip-b29/MTokens.json"
            );
            _setEmissionConfiguration(
                "./src/proposals/mips/mip-b29/RewardStreams.json"
            );

            cTokenConfigs = getCTokenConfigurations(block.chainid);
        }

        for (uint256 i = 0; i < cTokenConfigs.length; i++) {
            Configs.CTokenConfiguration memory config = cTokenConfigs[i];

            deal(
                addresses.getAddress(config.tokenAddressName),
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                config.initialMintAmount
            );
        }
    }

    /// ------------ MTOKEN MARKET ACTIVIATION BUILD ------------

    function build(Addresses addresses) public override {
        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);

        if (cTokenConfigs.length == 0) {
            _setMTokenConfiguration(
                "./src/proposals/mips/mip-b29/MTokens.json"
            );
            _setEmissionConfiguration(
                "./src/proposals/mips/mip-b29/RewardStreams.json"
            );

            cTokenConfigs = getCTokenConfigurations(block.chainid);
        }

        for (uint256 i = 0; i < cTokenConfigs.length; i++) {
            Configs.CTokenConfiguration memory config = cTokenConfigs[i];

            supplyCaps.push(config.supplyCap);
            borrowCaps.push(config.borrowCap);

            mTokens.add(addresses.getAddress(config.addressesString));
        }

        address unitrollerAddress = addresses.getAddress("UNITROLLER");
        address chainlinkOracleAddress = addresses.getAddress(
            "CHAINLINK_ORACLE"
        );

        _pushAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setMarketSupplyCaps(address[],uint256[])",
                mTokens.values(),
                supplyCaps
            ),
            "Set supply caps MToken market"
        );

        _pushAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setMarketBorrowCaps(address[],uint256[])",
                mTokens.values(),
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

                _pushAction(
                    chainlinkOracleAddress,
                    abi.encodeWithSignature(
                        "setFeed(string,address)",
                        ERC20(addresses.getAddress(config.tokenAddressName))
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

                _pushAction(
                    addresses.getAddress("MARKET_ADD_CHECKER"),
                    abi.encodeWithSignature(
                        "checkMarketAdd(address)",
                        cTokenAddress
                    ),
                    "Check the market has been correctly initialized and collateral token minted"
                );

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

        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            block.chainid
        );
        MultiRewardDistributor mrd = MultiRewardDistributor(
            addresses.getAddress("MRD_PROXY")
        );

        unchecked {
            for (uint256 i = 0; i < emissionConfig.length; i++) {
                EmissionConfig memory config = emissionConfig[i];

                require(
                    addresses.getAddress(config.emissionToken).code.length > 0,
                    "emission token must have bytecode"
                );
                require(
                    addresses.isAddressContract(config.emissionToken),
                    "emission token not a contract check 2"
                );
                require(
                    addresses.isAddressSet(config.emissionToken),
                    "emission token not set"
                );

                _pushAction(
                    address(mrd),
                    abi.encodeWithSignature(
                        "_addEmissionConfig(address,address,address,uint256,uint256,uint256)",
                        MToken(addresses.getAddress(config.mToken)),
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
    }

    /// helper function to validate supply and borrow caps
    function _validateCaps(
        Addresses addresses,
        Configs.CTokenConfiguration memory config
    ) private view {
        {
            if (config.supplyCap != 0 || config.borrowCap != 0) {
                uint8 decimals = EIP20Interface(
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
}
