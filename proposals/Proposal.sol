// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";
import {Test} from "@forge-std/Test.sol";
import {stdJson} from "@forge-std/StdJson.sol";

import "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

abstract contract Proposal is Script, Test {
    using ChainIds for uint256;
    using stdJson for string;

    bool internal DEBUG;
    bool internal DO_DEPLOY;
    bool internal DO_AFTER_DEPLOY;
    bool internal DO_BUILD;
    bool internal DO_RUN;
    bool internal DO_TEARDOWN;
    bool internal DO_VALIDATE;
    bool internal DO_PRINT;

    modifier mockHook(Addresses addresses) {
        beforeSimulationHook(addresses);
        _;
        afterSimulationHook(addresses);
    }

    constructor() {
        DEBUG = vm.envOr("DEBUG", true);
        DO_DEPLOY = vm.envOr("DO_DEPLOY", true);
        DO_AFTER_DEPLOY = vm.envOr("DO_AFTER_DEPLOY", true);
        DO_BUILD = vm.envOr("DO_BUILD", true);
        DO_RUN = vm.envOr("DO_RUN", true);
        DO_TEARDOWN = vm.envOr("DO_TEARDOWN", true);
        DO_VALIDATE = vm.envOr("DO_VALIDATE", true);
        DO_PRINT = vm.envOr("DO_PRINT", true);
    }

    function run() public virtual {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        vm.selectFork(primaryForkId());

        // inject the optional IPFS description URI from mips.json so
        // forge-script runs (e.g. mip-e00 mainnet deploy) emit the pinned URI
        // in propose() calldata. ProposalMap.runProposal does the same for the
        // test path — both paths read from the same mips.json source of truth.
        setProposalDescriptionUri(_resolveProposalDescriptionUri(this.name()));

        initProposal(addresses);

        vm.startBroadcast();

        (, address deployerAddress, ) = vm.readCallers();

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);
        vm.stopBroadcast();

        if (DO_BUILD) build(addresses);
        if (DO_RUN) simulate(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_VALIDATE) {
            validate(addresses, deployerAddress);
        }
        if (DO_PRINT) {
            printProposalActionSteps();

            addresses.removeAllRestrictions();
            printCalldata(addresses);

            _printAddressesChanges(addresses);
        }
    }

    function primaryForkId() public virtual returns (uint256);

    function name() external view virtual returns (string memory);

    function deploy(Addresses, address) public virtual;

    function afterDeploy(Addresses, address) public virtual;

    function build(Addresses) public virtual;

    function simulate(Addresses, address) public virtual;

    function printCalldata(Addresses addresses) public virtual;

    function teardown(Addresses, address) public virtual;

    function validate(Addresses, address) public virtual;

    function printProposalActionSteps() public virtual;

    function beforeSimulationHook(Addresses) public virtual {}

    function afterSimulationHook(Addresses) public virtual {}

    /// @notice initialize the proposal after the proposal is created and the
    /// live fork is selected
    function initProposal(Addresses) public virtual {}

    /// @notice hex encoded description of the proposal (raw markdown)
    bytes public PROPOSAL_DESCRIPTION;

    /// @notice optional IPFS URI (e.g. ipfs://<cid>) pointing at the pinned
    /// proposal description. When set, it is used as the description argument to
    /// propose() (printed calldata and simulation) instead of the raw markdown.
    /// Populated off-chain (see ProposalMap) from the optional `descriptionUri`
    /// field in mips.json, and by run() via _resolveProposalDescriptionUri().
    string public PROPOSAL_DESCRIPTION_URI;

    /// @notice set the proposal's raw markdown description
    function _setProposalDescription(
        bytes memory newProposalDescription
    ) internal {
        PROPOSAL_DESCRIPTION = newProposalDescription;
    }

    /// @notice set the optional IPFS URI for the proposal description
    function setProposalDescriptionUri(string memory uri) public virtual {
        PROPOSAL_DESCRIPTION_URI = uri;
    }

    /// @notice description argument used in propose(): the pinned IPFS URI when
    /// available, otherwise the raw markdown (backwards compatible)
    function _proposeDescription() internal view returns (string memory) {
        return
            bytes(PROPOSAL_DESCRIPTION_URI).length > 0
                ? PROPOSAL_DESCRIPTION_URI
                : string(PROPOSAL_DESCRIPTION);
    }

    /// @dev Print recorded addresses
    function _printAddressesChanges(Addresses addresses) internal view {
        bytes
            memory printedAddress = hex"7b0A20202020202020202261646472223a2022257322";
        bytes
            memory printedName = hex"2020202020202020226e616d65223a20222573220A7d2573";
        bytes
            memory printedContract = hex"2020202020202020226973436f6e7472616374223a202573";

        (
            string[] memory recordedNames,
            uint256[] memory chainIds,
            address[] memory recordedAddresses
        ) = addresses.getRecordedAddresses();

        if (recordedNames.length > 0) {
            console.log(
                "\n------- Addresses added after running proposal -------"
            );

            uint256[4] memory chainIdsToCheck = [
                OPTIMISM_CHAIN_ID,
                BASE_CHAIN_ID,
                MOONBEAM_CHAIN_ID,
                ETHEREUM_CHAIN_ID
            ];

            for (uint256 i = 0; i < chainIdsToCheck.length; i++) {
                uint256 currentChainId = chainIdsToCheck[i];
                console.log(
                    string(
                        abi.encodePacked(
                            "\n----------- Addresses added for ",
                            currentChainId.chainIdToName(),
                            " -----------"
                        )
                    )
                );

                uint256 addressCount = 0;
                for (uint256 j = 0; j < recordedNames.length; j++) {
                    if (chainIds[j] == currentChainId) {
                        addressCount++;
                    }
                }

                uint256 printedCount = 0;
                for (uint256 j = 0; j < recordedNames.length; j++) {
                    if (chainIds[j] == currentChainId) {
                        console.log(
                            string(printedAddress),
                            recordedAddresses[j],
                            ","
                        );
                        console.log(string(printedContract), true, ",");
                        console.log(
                            string(printedName),
                            recordedNames[j],
                            printedCount < addressCount - 1 ? "," : ""
                        );
                        printedCount++;
                    }
                }
            }
        }

        (
            string[] memory changedNames,
            ,
            ,
            address[] memory changedAddresses
        ) = addresses.getChangedAddresses();

        if (changedNames.length > 0) {
            console.log(
                "\n------- Addresses changed after running proposal --------"
            );

            for (uint256 j = 0; j < changedNames.length; j++) {
                console.log(string(printedAddress), changedAddresses[j], ",");
                console.log(string(printedContract), true, ",");
                console.log(
                    string(printedName),
                    changedNames[j],
                    j < changedNames.length - 1 ? "," : ""
                );
            }
        }
    }

    /// @notice resolve the optional IPFS descriptionUri from mips.json by
    /// matching the artifact stem of each entry's `path` (e.g. "mipe00" from
    /// "mip-e00.sol/mipe00.json") against `proposalName` with '-' stripped and
    /// lowercased (e.g. "MIP-E00" -> "mipe00"). Returns "" when no entry
    /// matches or the matching entry has no `descriptionUri`, in which case
    /// HybridProposalV2._proposeDescription() falls back to raw markdown.
    function _resolveProposalDescriptionUri(
        string memory proposalName
    ) internal view returns (string memory) {
        string memory data = vm.readFile(
            string(
                abi.encodePacked(vm.projectRoot(), "/proposals/mips/mips.json")
            )
        );

        bytes32 targetHash = keccak256(_normalizeMipName(bytes(proposalName)));

        uint256 i = 0;
        while (
            vm.keyExistsJson(
                data,
                string.concat(".[", vm.toString(i), "].path")
            )
        ) {
            string memory path = data.readString(
                string.concat(".[", vm.toString(i), "].path")
            );
            if (keccak256(_artifactStem(bytes(path))) == targetHash) {
                string memory uriKey = string.concat(
                    ".[",
                    vm.toString(i),
                    "].descriptionUri"
                );
                if (vm.keyExistsJson(data, uriKey)) {
                    return data.readString(uriKey);
                }
                return "";
            }
            i++;
        }
        return "";
    }

    /// @notice "MIP-E00" -> "mipe00": strip '-' and lowercase ASCII A-Z
    function _normalizeMipName(
        bytes memory s
    ) private pure returns (bytes memory) {
        bytes memory tmp = new bytes(s.length);
        uint256 j = 0;
        for (uint256 i = 0; i < s.length; i++) {
            bytes1 c = s[i];
            if (c == 0x2D) continue; // '-'
            if (c >= 0x41 && c <= 0x5A) c = bytes1(uint8(c) + 32);
            tmp[j++] = c;
        }
        bytes memory out = new bytes(j);
        for (uint256 i = 0; i < j; i++) out[i] = tmp[i];
        return out;
    }

    /// @notice "mip-e00.sol/mipe00.json" -> "mipe00": take the segment after
    /// the last '/' and drop a trailing ".json" if present
    function _artifactStem(
        bytes memory path
    ) private pure returns (bytes memory) {
        uint256 start = 0;
        for (uint256 i = 0; i < path.length; i++) {
            if (path[i] == 0x2F) start = i + 1; // '/'
        }
        uint256 end = path.length;
        if (
            end >= start + 5 &&
            path[end - 5] == 0x2E && // '.'
            path[end - 4] == 0x6A && // 'j'
            path[end - 3] == 0x73 && // 's'
            path[end - 2] == 0x6F && // 'o'
            path[end - 1] == 0x6E //    'n'
        ) {
            end -= 5;
        }
        bytes memory stem = new bytes(end - start);
        for (uint256 i = 0; i < stem.length; i++) {
            stem[i] = path[start + i];
        }
        return stem;
    }
}
