pragma solidity 0.8.19;

import {ICoreBridge, CoreBridgeVM} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {IExecutor, IVaaV1Receiver, IExecutorQuoterRouter} from "@protocol/wormhole/IExecutorCompat.sol";
import {SequenceReplayProtectionLib} from "wormhole-sdk/libraries/ReplayProtection.sol";
import {RequestLib} from "wormhole-sdk/Executor/Request.sol";
import {RelayInstructionLib} from "wormhole-sdk/Executor/RelayInstruction.sol";
import {toUniversalAddress, fromUniversalAddress} from "wormhole-sdk/Utils.sol";

import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/// @notice Wormhole Bridge Base Contract using the Executor pattern.
/// Sends messages to and receives messages from the same addresses on many
/// different chains. Replaces the deprecated Standard Relayer with the
/// Wormhole Executor, supporting both off-chain and on-chain quoting.
abstract contract WormholeBridgeBase is IVaaV1Receiver {
    using EnumerableSet for EnumerableSet.UintSet;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// -------------------- IMMUTABLES -------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice reference to the Wormhole Core Bridge contract
    ICoreBridge public immutable coreBridge;

    /// @notice this chain's wormhole chain id
    uint16 public immutable wormholeChainId;

    /// @notice reference to the Wormhole Executor contract (off-chain quoting)
    IExecutor public immutable executor;

    /// @notice reference to the Executor Quoter Router (on-chain quoting)
    IExecutorQuoterRouter public immutable executorQuoterRouter;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------------ SINGLE STORAGE SLOT ------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @dev Slot 0 layout preserved for proxy compatibility.
    /// Previously packed: uint96 gasLimit | IWormholeRelayer wormholeRelayer
    /// Now only gasLimit is used; the bottom 160 bits are dead storage.

    /// @notice gas limit for executor delivery, changeable in case gas prices
    /// change on external network
    uint96 public gasLimit;

    /// @dev dead storage - previously held the wormhole relayer address.
    /// Preserved to maintain storage layout for proxy upgrades.
    address private __deprecated_wormholeRelayer;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ----------------------- MAPPINGS ------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @dev dead storage - previously held processed nonces for replay protection.
    /// Now using SequenceReplayProtectionLib for bitmap-based replay protection.
    mapping(bytes32 => bool) public processedNonces;

    /// @notice chain id of the target chain to address for bridging
    /// starts off mapped to itself, but can be changed by governance
    mapping(uint16 chainId => address target) public targetAddress;

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- STATE VARIABLES -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice set of target chains to bridge out to
    /// @dev values are less or equal to 2^16 - 1, as add function takes uint16 as parameter
    /// should be impossible to ever have duplicate values in this set
    /// the reason being that the add function only adds if the value is not already in the set
    EnumerableSet.UintSet internal _targetChains;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------------------ EVENTS -------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice chain id of the target chain to address for bridging
    /// @param dstChainId destination chain id to send tokens to
    /// @param target address to send tokens to
    event TargetAddressUpdated(
        uint16 indexed dstChainId,
        address indexed target
    );

    /// @notice emitted when the gas limit changes on external chains
    /// @param oldGasLimit old gas limit
    /// @param newGasLimit new gas limit
    event GasLimitUpdated(uint96 oldGasLimit, uint96 newGasLimit);

    /// @notice emitted when a bridge out fails
    /// @param dstChainId destination chain id to send tokens to
    /// @param payload payload that failed to send
    /// @param refundAmount amount to refund
    event BridgeOutFailed(
        uint16 dstChainId,
        bytes payload,
        uint256 refundAmount
    );

    /// @notice event emitted when a bridge out succeeds
    /// @param dstWormholeChainId destination wormhole chain id to send tokens to
    /// @param cost cost of the bridge out
    /// @param dst destination address to send tokens to
    /// @param payload payload that was sent
    event BridgeOutSuccess(
        uint16 dstWormholeChainId,
        uint256 cost,
        address dst,
        bytes payload
    );

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ---------------------- CONSTRUCTOR ----------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @param _coreBridge address of the Wormhole Core Bridge
    /// @param _executor address of the Wormhole Executor (off-chain quoting)
    /// @param _executorQuoterRouter address of the Executor Quoter Router (on-chain quoting, address(0) if unavailable)
    constructor(
        address _coreBridge,
        address _executor,
        address _executorQuoterRouter
    ) {
        coreBridge = ICoreBridge(_coreBridge);
        wormholeChainId = ICoreBridge(_coreBridge).chainId();
        executor = IExecutor(_executor);
        executorQuoterRouter = IExecutorQuoterRouter(_executorQuoterRouter);
    }

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------------------ HELPERS ------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice set a gas limit for the relayer on the external chain
    /// should only be called if there is a change in gas prices on the external chain
    /// @param newGasLimit new gas limit to set
    function _setGasLimit(uint96 newGasLimit) internal {
        uint96 oldGasLimit = gasLimit;
        gasLimit = newGasLimit;

        emit GasLimitUpdated(oldGasLimit, newGasLimit);
    }

    /// @notice add map of target addresses for external chains
    /// @dev there is no check here to ensure there isn't an existing configuration
    /// ensure the proper add or remove is being called when using this function
    /// @param _chainConfig array of chainids to addresses to add
    function _addTargetAddresses(
        WormholeTrustedSender.TrustedSender[] memory _chainConfig
    ) internal {
        for (uint256 i = 0; i < _chainConfig.length; ) {
            _addTargetAddress(_chainConfig[i].chainId, _chainConfig[i].addr);

            unchecked {
                i++;
            }
        }
    }

    /// @notice add map of target addresses for external chains
    /// @param chainId chain id to add
    /// @param addr address to add
    function _addTargetAddress(uint16 chainId, address addr) internal {
        require(
            targetAddress[chainId] == address(0),
            "WormholeBridge: chain already added"
        );
        require(addr != address(0), "WormholeBridge: invalid target address");

        /// this code should be unreachable
        require(
            _targetChains.add(chainId),
            "WormholeBridge: chain already added to set"
        );

        targetAddress[chainId] = addr;

        emit TargetAddressUpdated(chainId, addr);
    }

    /// @notice remove map of target addresses for external chains
    /// @dev there is no check here to ensure there isn't an existing configuration
    /// ensure the proper add or remove is being called when using this function
    /// @param _chainConfig array of chainids to addresses to remove
    function _removeTargetAddresses(
        WormholeTrustedSender.TrustedSender[] memory _chainConfig
    ) internal {
        for (uint256 i = 0; i < _chainConfig.length; ) {
            uint16 chainId = _chainConfig[i].chainId;
            targetAddress[chainId] = address(0);
            require(
                _targetChains.remove(chainId),
                "WormholeBridge: chain not added"
            );

            emit TargetAddressUpdated(chainId, address(0));

            unchecked {
                i++;
            }
        }
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ---------------- View Only Functions -------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice returns all target wormhole chain ids for this contract instance
    function getAllTargetChains() external view returns (uint16[] memory) {
        uint256 chainsLength = _targetChains.length();
        uint16[] memory chains = new uint16[](chainsLength);

        for (uint256 i = 0; i < chainsLength; ) {
            chains[i] = uint16(_targetChains.at(i));
            unchecked {
                i++;
            }
        }

        return chains;
    }

    /// @notice returns the length of the target chains set
    function getAllTargetChainsLength() external view returns (uint256) {
        return _targetChains.length();
    }

    /// @notice Estimate bridge cost to bridge out to a destination chain
    /// using on-chain quoting. Returns 0 if the quoter is not available.
    /// @param dstWormholeChainId Destination chain id
    function bridgeCost(
        uint16 dstWormholeChainId
    ) public view returns (uint256 gasCost) {
        if (address(executorQuoterRouter) == address(0)) {
            return 0;
        }

        address target = targetAddress[dstWormholeChainId];
        if (target == address(0)) {
            return 0;
        }

        bytes memory requestBytes = RequestLib.encodeVaaMultiSigRequest(
            wormholeChainId,
            toUniversalAddress(address(this)),
            0 /// sequence is unknown at quote time, doesn't affect cost
        );
        bytes memory relayInstructions = RelayInstructionLib.encodeGas(
            uint128(gasLimit),
            0
        );

        try
            executorQuoterRouter.quoteExecution(
                dstWormholeChainId,
                toUniversalAddress(target),
                address(this),
                address(0), /// quoter address - use default
                requestBytes,
                relayInstructions
            )
        returns (uint256 cost) {
            gasCost = cost + coreBridge.messageFee();
        } catch {
            gasCost = 0;
        }
    }

    /// @notice Estimate bridge cost to bridge out to all chains
    function bridgeCostAll() public view returns (uint256) {
        uint256 totalCost = 0;

        uint256 chainsLength = _targetChains.length();
        for (uint256 i = 0; i < chainsLength; ) {
            totalCost += bridgeCost(uint16(_targetChains.at(i)));
            unchecked {
                i++;
            }
        }

        return totalCost;
    }

    /// @notice returns whether or not the address is in the trusted senders list for a given chain
    /// @param chainId The wormhole chain id to check
    /// @param addr The address to check (bytes32 universal address format)
    function isTrustedSender(
        uint16 chainId,
        bytes32 addr
    ) public view returns (bool) {
        return isTrustedSender(chainId, fromUniversalAddress(addr));
    }

    /// @notice returns whether or not the address is in the trusted senders list for a given chain
    /// @param chainId The wormhole chain id to check
    /// @param addr The address to check
    function isTrustedSender(
        uint16 chainId,
        address addr
    ) public view returns (bool) {
        return targetAddress[chainId] == addr;
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// -------------------- Bridge In/Out ---------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice Bridge Out Funds to all external chains using off-chain signed quotes.
    /// Quotes are obtained at execution time to avoid expiry during multisig signing.
    /// Overpayment is refunded to msg.sender.
    /// @param payload Payload to send to the external chains
    /// @param signedQuotes Array of signed quotes, one per target chain (in order)
    function _bridgeOutAll(
        bytes memory payload,
        bytes[] calldata signedQuotes
    ) internal {
        uint256 chainsLength = _targetChains.length();
        require(
            signedQuotes.length == chainsLength,
            "WormholeBridge: quotes length mismatch"
        );

        uint256 totalRefundAmount = msg.value;
        uint256 messageFee = coreBridge.messageFee();

        for (uint256 i = 0; i < chainsLength; ) {
            uint16 targetChain = uint16(_targetChains.at(i));
            address target = targetAddress[targetChain];

            try this._bridgeOutSingle{value: totalRefundAmount}(
                payload,
                targetChain,
                target,
                signedQuotes[i],
                messageFee
            ) returns (uint256 cost) {
                totalRefundAmount -= cost;
                emit BridgeOutSuccess(
                    targetChain,
                    cost,
                    target,
                    payload
                );
            } catch {
                emit BridgeOutFailed(targetChain, payload, 0);
            }

            unchecked {
                i++;
            }
        }

        if (totalRefundAmount != 0) {
            /// send bridge funds back to sender using call
            (bool success, ) = msg.sender.call{value: totalRefundAmount}("");
            require(success, "WormholeBridge: refund failed");
        }
    }

    /// @notice Bridge Out Funds to all external chains using on-chain quoting.
    /// @param payload Payload to send to the external chains
    /// @param quoterAddress Address of the on-chain quoter to use
    function _bridgeOutAllOnChain(
        bytes memory payload,
        address quoterAddress
    ) internal {
        require(
            address(executorQuoterRouter) != address(0),
            "WormholeBridge: on-chain quoter not available"
        );

        uint256 chainsLength = _targetChains.length();
        uint256 totalRefundAmount = msg.value;
        uint256 messageFee = coreBridge.messageFee();

        for (uint256 i = 0; i < chainsLength; ) {
            uint16 targetChain = uint16(_targetChains.at(i));
            address target = targetAddress[targetChain];

            try this._bridgeOutSingleOnChain{value: totalRefundAmount}(
                payload,
                targetChain,
                target,
                quoterAddress,
                messageFee
            ) returns (uint256 cost) {
                totalRefundAmount -= cost;
                emit BridgeOutSuccess(
                    targetChain,
                    cost,
                    target,
                    payload
                );
            } catch {
                emit BridgeOutFailed(targetChain, payload, 0);
            }

            unchecked {
                i++;
            }
        }

        if (totalRefundAmount != 0) {
            (bool success, ) = msg.sender.call{value: totalRefundAmount}("");
            require(success, "WormholeBridge: refund failed");
        }
    }

    /// @notice Internal helper to bridge out a single message with off-chain quote.
    /// External so it can be called with try/catch and value forwarding.
    /// @dev Must only be called by this contract.
    /// @return cost Total cost of this bridge out (message fee + executor fee)
    function _bridgeOutSingle(
        bytes memory payload,
        uint16 targetChain,
        address target,
        bytes calldata signedQuote,
        uint256 messageFee
    ) external payable returns (uint256 cost) {
        require(
            msg.sender == address(this),
            "WormholeBridge: only self"
        );

        uint64 sequence = coreBridge.publishMessage{value: messageFee}(
            0, /// nonce unused
            payload,
            200 /// finalized consistency level
        );

        bytes memory requestBytes = RequestLib.encodeVaaMultiSigRequest(
            wormholeChainId,
            toUniversalAddress(address(this)),
            sequence
        );

        bytes memory relayInstructions = RelayInstructionLib.encodeGas(
            uint128(gasLimit),
            0 /// no msg.value on destination
        );

        uint256 executorFee = msg.value - messageFee;
        executor.requestExecution{value: executorFee}(
            targetChain,
            toUniversalAddress(target),
            msg.sender, /// refund address
            signedQuote,
            requestBytes,
            relayInstructions
        );

        cost = messageFee + executorFee;
    }

    /// @notice Internal helper to bridge out a single message with on-chain quote.
    /// External so it can be called with try/catch and value forwarding.
    /// @dev Must only be called by this contract.
    /// @return cost Total cost of this bridge out (message fee + executor fee)
    function _bridgeOutSingleOnChain(
        bytes memory payload,
        uint16 targetChain,
        address target,
        address quoterAddress,
        uint256 messageFee
    ) external payable returns (uint256 cost) {
        require(
            msg.sender == address(this),
            "WormholeBridge: only self"
        );

        uint64 sequence = coreBridge.publishMessage{value: messageFee}(
            0,
            payload,
            200
        );

        bytes32 targetUniversal = toUniversalAddress(target);

        bytes memory requestBytes = RequestLib.encodeVaaMultiSigRequest(
            wormholeChainId,
            toUniversalAddress(address(this)),
            sequence
        );

        bytes memory relayInstructions = RelayInstructionLib.encodeGas(
            uint128(gasLimit),
            0
        );

        uint256 executorFee = executorQuoterRouter.quoteExecution(
            targetChain,
            targetUniversal,
            address(this),
            quoterAddress,
            requestBytes,
            relayInstructions
        );

        executorQuoterRouter.requestExecution{value: executorFee}(
            targetChain,
            targetUniversal,
            address(this), /// refund address
            quoterAddress,
            requestBytes,
            relayInstructions
        );

        cost = messageFee + executorFee;
    }

    /// @notice Receive and process a VAA from the Wormhole Executor.
    /// Verifies the VAA signatures via the Core Bridge, checks peer,
    /// prevents replay, then delegates to _bridgeIn.
    /// @param multiSigVaa The signed VAA bytes
    function executeVAAv1(bytes memory multiSigVaa) external payable override {
        require(msg.value == 0, "WormholeBridge: no value allowed");

        (
            CoreBridgeVM memory vm,
            bool valid,
            string memory reason
        ) = coreBridge.parseAndVerifyVM(multiSigVaa);

        require(valid, reason);

        /// verify the sender is a known peer
        require(
            targetAddress[vm.emitterChainId] != address(0) &&
                targetAddress[vm.emitterChainId] ==
                fromUniversalAddress(vm.emitterAddress),
            "WormholeBridge: sender not trusted"
        );

        /// sequence-based replay protection (bitmap, ~75% cheaper than mapping)
        SequenceReplayProtectionLib.replayProtect(
            vm.emitterChainId,
            vm.emitterAddress,
            vm.sequence
        );

        _bridgeIn(vm.emitterChainId, vm.payload);
    }

    /// @notice logic for bringing payload in from external chain
    /// @dev must be overridden by implementation contract
    /// @param sourceChain the chain id of the source chain
    /// @param payload the payload of the message
    function _bridgeIn(
        uint16 sourceChain,
        bytes memory payload
    ) internal virtual;

    /// @notice function to receive Ether for bridge operations
    receive() external payable virtual {}
}
