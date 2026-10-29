// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@utils/ChainIds.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {ActionType, ProposalAction} from "@proposals/proposalTypes/IProposal.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";

interface IActionSource {
    function getActionsByType(
        ActionType actionType
    ) external view returns (ProposalAction[] memory);
}

/// @notice Every address a pending proposal calls or passes as an argument
/// must be in chains/<id>.json, or be registered by the proposal's own
/// deploy step (that output is pasted into the json after execution). MOO-586.
contract ProposalAddressRegistryIntegrationTest is PostProposalCheck {
    using ChainIds for uint256;

    /// @dev A calldata word with the upper 12 bytes zero and a value of at
    /// least 2^128 is treated as an address: no amount reaches 2^128, and only
    /// vanity addresses with 8+ leading zero nibbles are missed.
    uint256 internal constant ADDRESS_FLOOR = 1 << 128;

    mapping(uint256 chainId => mapping(address addr => bool)) internal known;

    function setUp() public override {
        super.setUp();

        uint256[4] memory chainIds = [
            MOONBEAM_CHAIN_ID,
            BASE_CHAIN_ID,
            OPTIMISM_CHAIN_ID,
            ETHEREUM_CHAIN_ID
        ];
        for (uint256 i = 0; i < chainIds.length; i++) {
            _loadRegistry(chainIds[i]);
        }

        (
            ,
            uint256[] memory recordedChains,
            address[] memory recorded
        ) = addresses.getRecordedAddresses();
        for (uint256 i = 0; i < recorded.length; i++) {
            known[recordedChains[i]][recorded[i]] = true;
        }
    }

    function testPendingProposalsOnlyTouchRegisteredAddresses() public {
        uint256 scanned;
        for (uint256 p = 0; p < proposals.length; p++) {
            IActionSource source = IActionSource(address(proposals[p]));
            for (uint256 t = 0; t <= uint256(ActionType.Ethereum); t++) {
                ProposalAction[] memory acts;
                try source.getActionsByType(ActionType(t)) returns (
                    ProposalAction[] memory result
                ) {
                    acts = result;
                } catch {
                    continue;
                }

                scanned += acts.length;
                uint256 chainId = _chainIdOf(ActionType(t));
                (address stray, uint256 index) = _firstUnregistered(
                    acts,
                    chainId
                );
                assertEq(
                    stray,
                    address(0),
                    string.concat(
                        proposals[p].name(),
                        " action ",
                        vm.toString(index),
                        " touches an address missing from chains/",
                        vm.toString(chainId),
                        ".json"
                    )
                );
            }
        }
        assertGt(scanned, 0, "no pending action scanned");
    }

    function testRegisteredTargetAndArgumentPass() public view {
        address unitroller = addresses.getAddress("UNITROLLER", BASE_CHAIN_ID);
        address guardian = addresses.getAddress(
            "PAUSE_GUARDIAN",
            BASE_CHAIN_ID
        );
        ProposalAction[] memory acts = _single(
            unitroller,
            abi.encodeWithSignature("_setPauseGuardian(address)", guardian)
        );

        (address stray, ) = _firstUnregistered(acts, BASE_CHAIN_ID);
        assertEq(stray, address(0), "registered call flagged");
    }

    function testUnregisteredTargetIsFlagged() public view {
        address target = 0x00000000000000000000000000000000DeaDBeef;
        ProposalAction[] memory acts = _single(target, "");

        (address stray, ) = _firstUnregistered(acts, BASE_CHAIN_ID);
        assertEq(stray, target, "stray target not flagged");
    }

    function testUnregisteredArgumentIsFlagged() public view {
        address unitroller = addresses.getAddress("UNITROLLER", BASE_CHAIN_ID);
        address stranger = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;
        ProposalAction[] memory acts = _single(
            unitroller,
            abi.encodeWithSignature("_setPauseGuardian(address)", stranger)
        );

        (address stray, ) = _firstUnregistered(acts, BASE_CHAIN_ID);
        assertEq(stray, stranger, "stray argument not flagged");
    }

    function testAmountWordsAreNotAddresses() public view {
        address unitroller = addresses.getAddress("UNITROLLER", BASE_CHAIN_ID);
        ProposalAction[] memory acts = _single(
            unitroller,
            abi.encodeWithSignature(
                "f(uint256,uint256,bytes32)",
                1e27,
                type(uint128).max,
                keccak256("merkle root")
            )
        );

        (address stray, ) = _firstUnregistered(acts, BASE_CHAIN_ID);
        assertEq(stray, address(0), "non-address word flagged");
    }

    /// @notice the first target or address-shaped calldata word not in the
    /// registry for `chainId`, and the index of the action holding it
    function _firstUnregistered(
        ProposalAction[] memory acts,
        uint256 chainId
    ) internal view returns (address, uint256) {
        for (uint256 i = 0; i < acts.length; i++) {
            if (!known[chainId][acts[i].target]) {
                return (acts[i].target, i);
            }

            bytes memory data = acts[i].data;
            for (uint256 off = 4; off + 32 <= data.length; off += 32) {
                uint256 word;
                assembly {
                    word := mload(add(add(data, 32), off))
                }
                if (word < ADDRESS_FLOOR || word >> 160 != 0) continue;

                address candidate = address(uint160(word));
                if (!known[chainId][candidate]) {
                    return (candidate, i);
                }
            }
        }
        return (address(0), 0);
    }

    /// @dev names come from the json; values from the live registry so that
    /// changeAddress() calls made by a pending proposal are honored
    function _loadRegistry(uint256 chainId) internal {
        string memory data = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/chains/",
                vm.toString(chainId),
                ".json"
            )
        );
        Addresses.SavedAddresses[] memory saved = abi.decode(
            vm.parseJson(data),
            (Addresses.SavedAddresses[])
        );
        for (uint256 i = 0; i < saved.length; i++) {
            known[chainId][saved[i].addr] = true;
            known[chainId][addresses.getAddress(saved[i].name, chainId)] = true;
        }
    }

    function _chainIdOf(ActionType t) internal pure returns (uint256) {
        if (t == ActionType.Moonbeam) return MOONBEAM_CHAIN_ID;
        if (t == ActionType.Base) return BASE_CHAIN_ID;
        if (t == ActionType.Optimism) return OPTIMISM_CHAIN_ID;
        return ETHEREUM_CHAIN_ID;
    }

    function _single(
        address target,
        bytes memory data
    ) internal pure returns (ProposalAction[] memory acts) {
        acts = new ProposalAction[](1);
        acts[0] = ProposalAction(target, 0, data, "", ActionType.Base);
    }
}
