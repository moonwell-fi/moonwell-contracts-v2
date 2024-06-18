pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";

/// Performs the following actions which hand off direct or pending ownership
/// of the contracts from the Multichain Governor to the Artemis Timelock contract:
///    1. calls executeBreakGlass on the governor, which:
///      a. calls set trusted sender on temporal governor through wormhole core
///      b. calls set pending admin of all mTokens on moonbeam
///      c. sets the admin of chainlink oracle on moonbeam
///      d. sets the emissions manager for staked well
///      e. sets the owner of the moonbeam proxy admin
///      f. sets the owner of the xwell token
contract BreakGlass is Script, HybridProposal {
    string public constant override name = "BREAK_GLASS";

    struct Calls {
        address target;
        bytes call;
    }

    /// @notice whitelisted calldata for the break glass guardian
    bytes[] public approvedCalldata;

    /// @notice address of the temporal governor
    address[] public temporalGovernanceTargets;

    /// @notice whitelisted calldata for the temporal governor
    bytes[] public temporalGovernanceCalldata;

    /// @notice trusted senders for the temporal governor
    ITemporalGovernor.TrustedSender[] public temporalGovernanceTrustedSenders;

    function primaryForkId() public view override returns (ProposalType) {
        return ProposalType.Moonbeam;
    }

    function run() public override {
        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        /// ensure script runs on moonbeam
        vm.selectFork(primaryForkId());

        buildCalldata(addresses);
        bytes memory data = getCalldata(addresses);
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");

        console.log("Break Glass Calldata");
        console.logBytes(data);

        vm.prank(addresses.getAddress("BREAK_GLASS_GUARDIAN"));
        (bool success, bytes memory errorMessage) = governor.call{value: 0}(
            data
        );

        require(success, string(errorMessage));
    }

    function buildCalldata(Addresses addresses) public {
        address artemisTimelock = addresses.getAddress("MOONBEAM_TIMELOCK");
        address temporalGovernor = addresses.getAddress(
            "TEMPORAL_GOVERNOR",
            sendingChainIdToReceivingChainId[block.chainid]
        );

        /// add temporal governor to list
        temporalGovernanceTargets.push(temporalGovernor);

        temporalGovernanceTrustedSenders.push(
            ITemporalGovernor.TrustedSender({
                chainId: moonBeamWormholeChainId, /// this chainId is 16 (moonBeamWormholeChainId) regardless of testnet or mainnet
                addr: artemisTimelock /// this timelock on this chain
            })
        );

        /// new break glass guardian call for adding artemis as an owner of the Temporal Governor

        /// roll back trusted senders to artemis timelock
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
                200
            )
        );

        /// old break glass guardian calls from Artemis Governor

        approvedCalldata.push(
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                artemisTimelock
            )
        );

        /// for chainlink oracle
        approvedCalldata.push(
            abi.encodeWithSignature("setAdmin(address)", artemisTimelock)
        );

        /// for stkWELL
        approvedCalldata.push(
            abi.encodeWithSignature(
                "setEmissionsManager(address)",
                artemisTimelock
            )
        );

        /// for stkWELL
        approvedCalldata.push(
            abi.encodeWithSignature("changeAdmin(address)", artemisTimelock)
        );

        approvedCalldata.push(
            abi.encodeWithSignature(
                "transferOwnership(address)",
                artemisTimelock
            )
        );
    }

    function getCalldata(
        Addresses addresses
    ) public view override returns (bytes memory) {
        Calls[] memory calls = new Calls[](17);

        calls[0] = Calls({
            target: addresses.getAddress("mxcUSDC"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[1] = Calls({
            target: addresses.getAddress("mUSDCwh"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[2] = Calls({
            target: addresses.getAddress("mFRAX"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[3] = Calls({
            target: addresses.getAddress("mxcUSDT"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[4] = Calls({
            target: addresses.getAddress("mxcDOT"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[5] = Calls({
            target: addresses.getAddress("MNATIVE"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[6] = Calls({
            target: addresses.getAddress("MOONWELL_mUSDC"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[7] = Calls({
            target: addresses.getAddress("DEPRECATED_MOONWELL_mETH"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[8] = Calls({
            target: addresses.getAddress("MOONWELL_mBUSD"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[9] = Calls({
            target: addresses.getAddress("DEPRECATED_MOONWELL_mWBTC"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[10] = Calls({
            target: addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER"),
            call: approvedCalldata[5] /// transferOwnership
        });

        calls[11] = Calls({
            target: addresses.getAddress("UNITROLLER"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[12] = Calls({
            target: addresses.getAddress("STK_GOVTOKEN"),
            call: approvedCalldata[3] /// setEmissionsManager
        });

        calls[13] = Calls({
            target: addresses.getAddress("CHAINLINK_ORACLE"),
            call: approvedCalldata[2] /// setAdmin
        });

        calls[14] = Calls({
            target: addresses.getAddress("xWELL_PROXY"),
            call: approvedCalldata[5] /// transferOwnership
        });

        calls[15] = Calls({
            target: addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            call: approvedCalldata[5] /// transferOwnership
        });

        calls[16] = Calls({
            target: addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            call: approvedCalldata[5] /// transferOwnership
        });

        calls[17] = Calls({
            target: addresses.getAddress("MOONWELL_mWBTC"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        address[] memory targets = new address[](calls.length);
        bytes[] memory callDatas = new bytes[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            targets[i] = calls[i].target;
            callDatas[i] = calls[i].call;
        }

        return
            abi.encodeWithSignature(
                "executeBreakGlass(address[],bytes[])",
                targets,
                callDatas
            );
    }

    function validate(Addresses addresses, address) public view override {}
}
