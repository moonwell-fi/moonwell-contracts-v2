//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";
import "@protocol/utils/ChainIds.sol";
import "@protocol/utils/String.sol";

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {MToken} from "@protocol/MToken.sol";
import {OPTIMISM_CHAIN_ID} from "@utils/ChainIds.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";
import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
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
    using SafeCast for *;
    using String for string;
    using stdJson for string;
    using ChainIds for uint256;
    using ProposalActions for *;
    using stdStorage for StdStorage;

    struct MToken {
        uint256 borrowCap;
        uint256 collateralFactor;
        uint256 initialMintAmount;
        IRParams jrm;
        string market;
        string name;
        string priceFeed;
        uint256 reserveFactor;
        uint256 seizeShare;
        uint256 supplyCap;
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

    function _saveMTokens(
        Addresses addresses,
        string memory encodedJson,
        uint256 chainId
    ) internal {
        string memory chain = string.concat(".", vm.toString(chainId));

        bytes memory parsedJson = vm.parseJson(encodedJson, chain);

        MTokens[] memory mTokens = abi.decode(parsedJson, (MTokens[]));

        for (uint256 i = 0; i < mTokens.length; i++) {
            mTokens[chainId].push(mTokens[i]);
        }
    }
}
