pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {CrossChainProposal} from "@protocol/proposals/proposalTypes/CrossChainProposal.sol";

///    Reuse Cross Chain Proposal contract for readability and to avoid
/// code duplication around generation of governance calldata.

/// Environment variables:
///    PROPOSAL_DESCRIPTION: path to proposal description file
///    PROPOSAL: path to proposal JSON file
contract CrossChainJSONProposal is CrossChainProposal {
    Addresses addresses;

    function setUp() public {
        addresses = new Addresses();
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(vm.envString("PROPOSAL_DESCRIPTION"))
        );
        _setProposalDescription(proposalDescription);
    }

    function deploy(Addresses, address) public virtual override {}

    /// 1. run buildCalldata.ts using ffi
    /// 2. copy the temporal gov calldata and use it to build the proposal
    /// 3. simulate the proposal being executed by the temporal governor
    /// 3.5 simulate proposing on moonbeam, voting for the proposal, and executing the proposal
    /// ensure the proposal succeeded by ensuring event emission in the Wormhole Core contract on Moonbeam
    /// 4. run proposal validation steps

    function afterDeploy(Addresses, address) public virtual override {}

    function afterDeploySetup(Addresses) public virtual override {}

    function build(Addresses) public virtual override {
        string[] memory commands = new string[](3);

        /// note to future self, ffi absolutely flips out if you try to set env vars
        commands[0] = "npx";
        commands[1] = "ts-node";
        commands[2] = "typescript/buildCalldata.ts";

        bytes memory result = vm.ffi(commands);

        console.log("result: ");
        emit log_bytes(result);

        (
            address temporalGov,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = abi.decode(result, (address, address[], uint256[], bytes[]));

        require(temporalGov != address(0), "temporal gov invalid");
        require(
            targets.length == values.length,
            "arity mismatch in generated calldata 1"
        );
        require(
            calldatas.length == values.length,
            "arity mismatch in generated calldata 2"
        );

        console.log("temporal governor: %s\n", temporalGov);

        for (uint256 i = 0; i < values.length; i++) {
            // console.log("%d).\ntarget: ", i, targets[i]);
            // console.log("values: ", values[i]);
            // console.log("payload: ");
            // emit log_bytes(calldatas[i]);

            require(values[i] == 0, "value must be 0 for cross chain proposal");

            _pushCrossChainAction(targets[i], calldatas[i], "");
        }

        bytes memory temporalGovCalldata = getTemporalGovCalldata(
            temporalGov,
            targets,
            values,
            calldatas
        );

        bytes memory artemisCalldata = getArtemisGovernorCalldata(
            temporalGov,
            addresses.getAddress("WORMHOLE_CORE", moonBeamChainId), /// get wormhole core address on moonbeam
            temporalGovCalldata
        );

        /// confirmed that the calldata matches solidity generated calldata
        console.log("artemis gov calldata: ");
        emit log_bytes(artemisCalldata);
    }

    function teardown(Addresses, address) public virtual override {}

    function validate(Addresses, address) public virtual override {}
}
