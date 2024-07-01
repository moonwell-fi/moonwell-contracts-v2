//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID} from "@utils/ChainIds.sol";

/*
DO_DEPLOY=true DO_AFTER_DEPLOY=true DO_PRE_BUILD_MOCK=true DO_BUILD=true \
DO_RUN=true DO_VALIDATE=true forge script src/proposals/mips/mip-o01/mip-o01.sol:mipo01 \
 -vvv
*/
contract mipo01 is Configs, HybridProposal {
    string public constant override name = "MIP-O01";

    /// @notice whitelisted calldata for the break glass guardian
    bytes[] public approvedCalldata;

    /// @notice whitelisted calldata for the temporal governor
    bytes[] public temporalGovernanceCalldata;

    /// @notice address of the temporal governor
    address[] public temporalGovernanceTargets;

    /// @notice trusted senders for the temporal governor
    ITemporalGovernor.TrustedSender[] public temporalGovernanceTrustedSenders;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-o01/MIP-O01.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function deploy(Addresses, address) public override {}

    function afterDeploy(Addresses, address) public override {}

    function preBuildMock(Addresses) public override {}

    function teardown(Addresses, address) public override {}

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        if (approvedCalldata.length == 0) {
            _buildCalldata(addresses);
        }

        /// accept admin of MOONWELL_mWBTC to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
            abi.encodeWithSignature(
                "updateApprovedCalldata(bytes,bool)",
                approvedCalldata,
                true
            ),
            "Whitelist break glass calldata to add the Artemis Timelock as a trusted sender in the Temporal Governor on Optimism",
            MOONBEAM_FORK_ID
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            baseActions.length == 0,
            "MIP-O01: should have no base actions"
        );

        require(
            moonbeamActions.length == 1,
            "MIP-O01: should have 1 moonbeam actions"
        );

        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public override {
        if (approvedCalldata.length == 0) {
            _buildCalldata(addresses);
        }

        bytes memory whitelistedCalldata = approvedCalldata[0];

        MultichainGovernor governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        );

        assertTrue(
            governor.whitelistedCalldatas(whitelistedCalldata),
            "multichain governor should have whitelisted break glass guardian calldata"
        );
    }

    function _buildCalldata(Addresses addresses) internal {
        address artemisTimelock = addresses.getAddress("MOONBEAM_TIMELOCK");
        /// get temporal governor on Optimism
        address temporalGovernor = addresses.getAddress(
            "TEMPORAL_GOVERNOR",
            block.chainid == MOONBEAM_CHAIN_ID
                ? OPTIMISM_CHAIN_ID
                : OPTIMISM_SEPOLIA_CHAIN_ID
        );

        temporalGovernanceTargets.push(temporalGovernor);

        temporalGovernanceTrustedSenders.push(
            ITemporalGovernor.TrustedSender({
                chainId: MOONBEAM_WORMHOLE_CHAIN_ID, /// this chainId is 16 (MOONBEAM_WORMHOLE_CHAIN_ID) regardless of testnet or mainnet
                addr: artemisTimelock /// the timelock on moonbeam
            })
        );

        /// roll back trusted senders to the artemis timelock
        /// in reality this just adds the artemis timelock as a trusted sender
        /// a second proposal is needed to revoke the Multichain Governor as a trusted sender
        temporalGovernanceCalldata.push(
            abi.encodeWithSignature(
                "setTrustedSenders((uint16,address)[])",
                temporalGovernanceTrustedSenders
            )
        );

        approvedCalldata.push(
            abi.encodeWithSignature(
                "publishMessage(uint32,bytes,uint8)",
                /// arbitrary nonce
                1000,
                abi.encode(
                    /// target is temporal governor, this passes intended recipient check
                    temporalGovernanceTargets[0],
                    /// sets temporal governor target to itself
                    temporalGovernanceTargets,
                    /// sets values to array filled with 0 values
                    new uint256[](1),
                    /// sets calldata to a call to the setTrustedSenders((uint16,address)[])
                    /// function with artemis timelock as the address and moonbeam wormhole
                    /// chain id as the chain id
                    temporalGovernanceCalldata
                ),
                /// consistency level ignored as Moonbeam has instant finality
                200
            )
        );
    }
}
