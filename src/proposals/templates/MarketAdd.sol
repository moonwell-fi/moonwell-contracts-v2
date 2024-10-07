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
import {JumpRateModel, InterestRateModel} from "@protocol/irm/JumpRateModel.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {ComptrollerInterfaceV1} from "@protocol/views/ComptrollerInterfaceV1.sol";
import {IMultiRewardDistributor} from "@protocol/rewards/IMultiRewardDistributor.sol";
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

    struct MToken {
        string addressesString;
        uint256 borrowCap;
        uint256 collateralFactor;
        uint256 initialMintAmount;
        JRMParams jrm;
        string name;
        string priceFeed;
        uint256 reserveFactor;
        uint256 seizeShare;
        uint256 supplyCap;
        string symbol;
        string token;
    }

    uint256 startTimeStamp;

    mapping(uint256 chainid => MToken[]) mTokens;

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
        MToken[] memory _mTokens = mTokens[chainId];
        unchecked {
            for (uint256 i = 0; i < _mTokens.length; i++) {
                MToken memory config = _mTokens[i];
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
                        (ERC20(addresses.getAddress(config.token)).decimals() +
                            8)) * 2;

                    MErc20Delegator mToken = new MErc20Delegator(
                        addresses.getAddress(config.token),
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

    function _saveMTokens(
        Addresses addresses,
        string memory encodedJson,
        uint256 chainId
    ) internal {
        string memory chain = string.concat(".", vm.toString(chainId));

        bytes memory parsedJson = vm.parseJson(encodedJson, chain);

        MToken[] memory _mTokens = abi.decode(parsedJson, (MToken[]));

        for (uint256 i = 0; i < _mTokens.length; i++) {
            mTokens[chainId].push(_mTokens[i]);
        }
    }
}
