//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";
import "@protocol/utils/ChainIds.sol";
import "@protocol/utils/String.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {MToken} from "@protocol/MToken.sol";
import {OPTIMISM_CHAIN_ID} from "@utils/ChainIds.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {Comptroller, ComptrollerInterface} from "@protocol/Comptroller.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {ComptrollerInterfaceV1} from "@protocol/views/ComptrollerInterfaceV1.sol";
import {JumpRateModel, InterestRateModel} from "@protocol/irm/JumpRateModel.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(vm.envString("DESCRIPTION_PATH"))
        );

        _setProposalDescription(proposalDescription);
    }

    function name() external pure override returns (string memory) {
        return "MIP Market Add";
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function run(
        Addresses addresses,
        address
    ) public virtual override mockHook(addresses) {
        super.run(addresses, address(0));
    }

    function initProposal(Addresses addresses) public override {
        string memory encodedJson = vm.readFile(vm.envString("MTOKENS_PATH"));

        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            _saveMTokens(addresses, encodedJson, chainId);
            _saveEmissionConfigurations(addresses, chainId);
        }
    }

    function deploy(Addresses addresses, address deployer) public override {
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            _deployToChain(addresses, deployer, chainId);
        }
    }

    function validate(Addresses addresses, address) public override {}

    function _deployToChain(
        Addresses addresses,
        address deployer,
        uint256 chainId
    ) internal {
        MTokenConfiguration[] memory _mTokens = mTokens[chainId];
        unchecked {
            for (uint256 i = 0; i < _mTokens.length; i++) {
                MTokenConfiguration memory config = _mTokens[i];
                //   _validateCaps(addresses, config);

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
                    JumpRateModel irModel = new JumpRateModel(
                        config.jrm.baseRatePerYear,
                        config.jrm.multiplierPerYear,
                        config.jrm.jumpMultiplierPerYear,
                        config.jrm.kink
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
                        ComptrollerInterface(
                            addresses.getAddress("UNITROLLER")
                        ),
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

                    addresses.addAddress(
                        config.addressesString,
                        address(mToken)
                    );
                }
            }
        }
    }

    function _buildToChain(Addresses addresses, uint256 chainId) internal {
        vm.selectFork(chainId.toForkId());
        MTokenConfiguration[] memory _mTokens = mTokens[chainId];

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

        unchecked {
            for (uint256 i = 0; i < _mTokens.length; i++) {
                MTokenConfiguration memory config = _mTokens[i];

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

        MultiRewardDistributor mrd = MultiRewardDistributor(
            addresses.getAddress("MRD_PROXY")
        );

        unchecked {
            for (uint256 i = 0; i < emissionConfig.length; i++) {
                EmissionConfiguration memory config = emissionConfig[i];

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

    function _saveMTokens(
        Addresses addresses,
        string memory encodedJson,
        uint256 chainId
    ) internal {
        string memory chain = string.concat(".", vm.toString(chainId));

        bytes memory parsedJson = vm.parseJson(encodedJson, chain);

        MTokenConfiguration[] memory _mTokens = abi.decode(
            parsedJson,
            (MTokenConfiguration[])
        );

        for (uint256 i = 0; i < _mTokens.length; i++) {
            mTokens[chainId].push(_mTokens[i]);
        }
    }

    function _saveEmissionConfigurations(
        Addresses addresses,
        uint256 chainId
    ) internal {
        string memory encodedJson = vm.readFile(
            vm.envString("EMISSION_CONFIGURATIONS_PATH")
        );

        string memory chain = string.concat(".", vm.toString(chainId));

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
