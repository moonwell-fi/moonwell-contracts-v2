pragma solidity 0.8.19;

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {ICoreBridge, CoreBridgeVM} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {IExecutor, IVaaV1Receiver, IExecutorQuoterRouter} from "@protocol/wormhole/IExecutorCompat.sol";
import {SequenceReplayProtectionLib} from "wormhole-sdk/libraries/ReplayProtection.sol";
import {RequestLib} from "wormhole-sdk/Executor/Request.sol";
import {RelayInstructionLib} from "wormhole-sdk/Executor/RelayInstruction.sol";
import {toUniversalAddress, fromUniversalAddress} from "wormhole-sdk/Utils.sol";

import {xERC20BridgeAdapter} from "@protocol/xWELL/xERC20BridgeAdapter.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";

/// @notice Wormhole xERC20 Token Bridge adapter using the Executor pattern.
/// Supports both off-chain and on-chain quoting for bridge operations.
contract WormholeBridgeAdapter is
    IVaaV1Receiver,
    xERC20BridgeAdapter,
    WormholeTrustedSender
{
    using SafeCast for uint256;

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
    uint96 public gasLimit = 300_000;

    /// @dev dead storage - previously held the wormhole relayer address.
    address private __deprecated_wormholeRelayer;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ----------------------- MAPPINGS ------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @dev dead storage - previously held processed nonces.
    /// Now using SequenceReplayProtectionLib.
    mapping(bytes32 => bool) public processedNonces;

    /// @notice chain id of the target chain to address for bridging
    /// starts off mapped to itself, but can be changed by governance
    mapping(uint16 => address) public targetAddress;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------------------ EVENTS -------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice chain id of the target chain to address for bridging
    /// @param dstChainId source chain id tokens were bridged from
    /// @param tokenReceiver address to receive tokens on destination chain
    /// @param amount of tokens bridged in
    event TokensSent(
        uint16 indexed dstChainId,
        address indexed tokenReceiver,
        uint256 amount
    );

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
    /// ---------------------- INITIALIZE -----------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice Initialize the Wormhole bridge
    /// @param newxerc20 xERC20 token address
    /// @param newOwner contract owner address
    /// @param targetChains chain id of the target chain to address for bridging
    /// @param targetAddresses addresses of the wormhole bridge adapters to
    /// bridge to on external chains
    function initialize(
        address newxerc20,
        address newOwner,
        uint16[] memory targetChains,
        address[] memory targetAddresses
    ) public initializer {
        __Ownable_init();
        _transferOwnership(newOwner);
        _setxERC20(newxerc20);

        /// initialize contract to trust this exact same address on an external chain
        /// @dev the external chain contracts MUST HAVE THE SAME ADDRESS on the external chain
        require(
            targetChains.length == targetAddresses.length,
            "WormholeBridge: array length mismatch"
        );
        for (uint256 i = 0; i < targetChains.length; i++) {
            targetAddress[targetChains[i]] = targetAddresses[i];
            _addTrustedSender(targetAddresses[i], targetChains[i]);
        }

        gasLimit = 300_000; /// @dev default starting gas limit for relayer
    }

    /// @notice needed on Ethereum as the owner was previously set as the proxy admin
    function initializeV2(address newOwner) external reinitializer(2) {
        require(
            newOwner != address(0),
            "WormholeBridgeAdapter: new owner cannot be zero address"
        );
        _transferOwnership(newOwner);
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ---------------- Admin Only Functions ------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice set a gas limit for the relayer on the external chain
    /// should only be called if there is a change in gas prices on the external chain
    /// @param newGasLimit new gas limit to set
    function setGasLimit(uint96 newGasLimit) external onlyOwner {
        uint96 oldGasLimit = gasLimit;
        gasLimit = newGasLimit;

        emit GasLimitUpdated(oldGasLimit, newGasLimit);
    }

    /// @notice remove trusted senders from external chains
    /// @param _trustedSenders array of trusted senders to remove
    function removeTrustedSenders(
        WormholeTrustedSender.TrustedSender[] memory _trustedSenders
    ) external onlyOwner {
        _removeTrustedSenders(_trustedSenders);
    }

    /// @notice add trusted senders from external chains
    /// @param _trustedSenders array of trusted senders to add
    function addTrustedSenders(
        WormholeTrustedSender.TrustedSender[] memory _trustedSenders
    ) external onlyOwner {
        _addTrustedSenders(_trustedSenders);
    }

    /// @notice add map of target addresses for external chains
    /// @dev there is no check here to ensure there isn't an existing configuration
    /// ensure the proper add or remove is being called when using this function
    /// @param _chainConfig array of chainids to addresses to add
    function setTargetAddresses(
        WormholeTrustedSender.TrustedSender[] memory _chainConfig
    ) external onlyOwner {
        for (uint256 i = 0; i < _chainConfig.length; i++) {
            targetAddress[_chainConfig[i].chainId] = _chainConfig[i].addr;

            emit TargetAddressUpdated(
                _chainConfig[i].chainId,
                _chainConfig[i].addr
            );
        }
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ---------------- View Only Functions -------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice Estimate bridge cost to bridge out to a destination chain
    /// using on-chain quoting. Returns 0 if the quoter is not available.
    /// @param dstChainId Destination chain id
    function bridgeCost(
        uint16 dstChainId
    ) public view returns (uint256 gasCost) {
        if (address(executorQuoterRouter) == address(0)) {
            return 0;
        }

        address target = targetAddress[dstChainId];
        if (target == address(0)) {
            return 0;
        }

        bytes memory requestBytes = RequestLib.encodeVaaMultiSigRequest(
            wormholeChainId,
            toUniversalAddress(address(this)),
            0
        );
        bytes memory relayInstructions = RelayInstructionLib.encodeGas(
            uint128(gasLimit),
            0
        );

        try
            executorQuoterRouter.quoteExecution(
                dstChainId,
                toUniversalAddress(target),
                address(this),
                address(0),
                requestBytes,
                relayInstructions
            )
        returns (uint256 cost) {
            gasCost = cost + coreBridge.messageFee();
        } catch {
            gasCost = 0;
        }
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// -------------------- Bridge In/Out ---------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice Bridge Out Funds to an external chain using an off-chain signed quote.
    /// Callable by the users to bridge out their funds to an external chain.
    /// If a user sends tokens to the token contract on the external chain,
    /// that call will revert, and the tokens will be lost permanently.
    /// @param user to send funds from, should be msg.sender in all cases
    /// @param targetChain Destination chain id
    /// @param amount Amount of xERC20 to bridge out
    /// @param to Address to receive funds on destination chain
    function _bridgeOut(
        address user,
        uint256 targetChain,
        uint256 amount,
        address to
    ) internal override {
        uint16 targetChainId = targetChain.toUint16();
        address target = targetAddress[targetChainId];
        require(
            target != address(0),
            "WormholeBridge: invalid target chain"
        );

        /// user must burn xERC20 tokens first
        _burnTokens(user, amount);

        uint256 messageFee = coreBridge.messageFee();

        /// encode payload with destination chain for cross-chain replay protection
        bytes memory payload = abi.encode(targetChainId, to, amount);

        uint64 sequence = coreBridge.publishMessage{value: messageFee}(
            0,
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
            0
        );

        uint256 executorFee = msg.value - messageFee;

        /// Use on-chain quoting if available, otherwise the caller must
        /// have provided enough msg.value for the off-chain executor fee
        if (address(executorQuoterRouter) != address(0)) {
            executorQuoterRouter.requestExecution{value: executorFee}(
                targetChainId,
                toUniversalAddress(target),
                msg.sender,
                address(0), /// default quoter
                requestBytes,
                relayInstructions
            );
        } else {
            /// Off-chain quoting: the caller must provide a signed quote
            /// via the bridge() function's signedQuote parameter.
            /// For now, send the full remaining value to the executor.
            /// The executor will refund any overpayment.
            revert("WormholeBridge: off-chain quote required, use bridgeWithQuote");
        }

        emit TokensSent(targetChainId, to, amount);
    }

    /// @notice Bridge Out Funds to an external chain using an off-chain signed quote.
    /// @param targetChain Destination chain id
    /// @param amount Amount of xERC20 to bridge out
    /// @param to Address to receive funds on destination chain
    /// @param signedQuote Signed off-chain quote from a relay provider
    function bridgeWithQuote(
        uint256 targetChain,
        uint256 amount,
        address to,
        bytes calldata signedQuote
    ) external payable {
        uint16 targetChainId = targetChain.toUint16();
        address target = targetAddress[targetChainId];
        require(
            target != address(0),
            "WormholeBridge: invalid target chain"
        );

        /// user must burn xERC20 tokens first
        _burnTokens(msg.sender, amount);

        uint256 messageFee = coreBridge.messageFee();

        bytes memory payload = abi.encode(targetChainId, to, amount);

        uint64 sequence = coreBridge.publishMessage{value: messageFee}(
            0,
            payload,
            200
        );

        bytes memory requestBytes = RequestLib.encodeVaaMultiSigRequest(
            wormholeChainId,
            toUniversalAddress(address(this)),
            sequence
        );

        bytes memory relayInstructions = RelayInstructionLib.encodeGas(
            uint128(gasLimit),
            0
        );

        uint256 executorFee = msg.value - messageFee;
        executor.requestExecution{value: executorFee}(
            targetChainId,
            toUniversalAddress(target),
            msg.sender, /// refund address
            signedQuote,
            requestBytes,
            relayInstructions
        );

        emit TokensSent(targetChainId, to, amount);
    }

    /// @notice Receive and process a VAA from the Wormhole Executor.
    /// Verifies the VAA via Core Bridge, checks trusted sender,
    /// prevents replay, then mints tokens.
    /// @param multiSigVaa The signed VAA bytes
    function executeVAAv1(bytes memory multiSigVaa) external payable override {
        require(msg.value == 0, "WormholeBridge: no value allowed");

        (
            CoreBridgeVM memory vm,
            bool valid,
            string memory reason
        ) = coreBridge.parseAndVerifyVM(multiSigVaa);

        require(valid, reason);

        /// verify trusted sender
        require(
            isTrustedSender(vm.emitterChainId, vm.emitterAddress),
            "WormholeBridge: sender not trusted"
        );

        /// sequence-based replay protection
        SequenceReplayProtectionLib.replayProtect(
            vm.emitterChainId,
            vm.emitterAddress,
            vm.sequence
        );

        /// decode payload and verify destination chain
        (uint16 destinationChainId, address to, uint256 amount) = abi.decode(
            vm.payload,
            (uint16, address, uint256)
        );

        require(
            destinationChainId == wormholeChainId,
            "WormholeBridge: destination chain mismatch"
        );

        /// mint tokens and emit events
        _bridgeIn(vm.emitterChainId, to, amount);
    }
}
