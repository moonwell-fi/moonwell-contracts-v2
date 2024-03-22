pragma solidity 0.8.19;

import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";

contract BreakGlassCalldata is ChainIds {
    /// @notice address of the temporal governor
    address[] public temporalGovernanceTargets;

    /// @notice trusted senders for the temporal governor
    ITemporalGovernor.TrustedSender[] public temporalGovernanceTrustedSenders;

    /// @notice whitelisted calldata for the break glass guardian
    bytes[] public approvedCalldata;

    /// @notice whitelisted calldata for the temporal governor
    bytes[] public temporalGovernanceCalldata;

    struct Calls {
        address target;
        bytes call;
    }

    function buildWhitelistedCalldatas(
        Addresses addresses
    ) public returns (bytes memory) {
        require(
            temporalGovernanceTargets.length == 0,
            "calldata already set in mip-18-c"
        );
        require(
            temporalGovernanceTrustedSenders.length == 0,
            "temporal gov trusted sender already set in mip-18-c"
        );
        require(
            approvedCalldata.length == 0,
            "approved calldata already set in mip-18-c"
        );
        require(
            temporalGovernanceCalldata.length == 0,
            "temporal gov calldata already set in mip-18-c"
        );

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
            target: addresses.getAddress("mGLIMMER"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[6] = Calls({
            target: addresses.getAddress("MOONWELL_mUSDC"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[7] = Calls({
            target: addresses.getAddress("MOONWELL_mETH"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[8] = Calls({
            target: addresses.getAddress("MOONWELL_mBUSD"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[9] = Calls({
            target: addresses.getAddress("MOONWELL_mwBTC"),
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
            target: addresses.getAddress("stkWELL_PROXY"),
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
}
