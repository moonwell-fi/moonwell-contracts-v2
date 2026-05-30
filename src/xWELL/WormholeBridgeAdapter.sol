pragma solidity 0.8.19;

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {IExecutor, IExecutorQuoterRouter, IVaaV1Receiver} from "@protocol/wormhole/IExecutorQuoterRouter.sol";
import {xERC20BridgeAdapter} from "@protocol/xWELL/xERC20BridgeAdapter.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";

import {SequenceReplayProtectionLib} from "wormhole-sdk/libraries/ReplayProtection.sol";
import {RequestLib} from "wormhole-sdk/Executor/Request.sol";
import {RelayInstructionLib} from "wormhole-sdk/Executor/RelayInstruction.sol";
import {toUniversalAddress} from "wormhole-sdk/Utils.sol";

/// @notice Wormhole xERC20 Token Bridge adapter using the Executor framework
contract WormholeBridgeAdapter is
    IVaaV1Receiver,
    xERC20BridgeAdapter,
    WormholeTrustedSender
{
    using SafeCast for uint256;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ---------------------- CONSTANTS ------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice Wormhole consistency level for publishMessage.
    /// 1 = finalized: on Ethereum this means L1 finality (~15 min);
    ///                on Base/Optimism this means L2 safe head finality.
    uint8 public constant CONSISTENCY_LEVEL = 1;

    /// @notice Wormhole ChainId for Moonbeam, where quoter and quoter router are not available
    uint16 internal constant MOONBEAM_WORMHOLE_CHAIN_ID = 16;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------------ SINGLE STORAGE SLOT ------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @dev packing these variables into a single slot saves a
    /// COLD SLOAD on bridge out operations.

    /// @notice gas limit for executor, changeable incase gas prices change on external network
    uint96 public gasLimit = 300_000;

    /// @notice address of the wormhole relayer cannot be changed by owner
    /// because the relayer contract is a proxy and should never change its address
    /// @dev DEPRECATED
    IWormholeRelayer public wormholeRelayer;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ----------------------- MAPPINGS ------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice nonces that have already been processed
    /// @dev DEPRECATED — used by the old Wormhole standard relayer path.
    ///      Superseded by processedVAAHashes. Retained to preserve storage
    ///      layout for upgradeable proxies.
    mapping(bytes32 => bool) public processedNonces;

    /// @notice chain id of the target chain to address for bridging
    /// starts off mapped to itself, but can be changed by governance
    mapping(uint16 => address) public targetAddress;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------- V3 STORAGE (post-upgrade) -----------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice Wormhole core bridge for onchain VAA verification
    IWormhole public wormhole;

    /// @notice tracks processed VAA hashes to prevent replay
    /// @dev DEPRECATED
    mapping(bytes32 => bool) public processedVAAHashes;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------- V4 STORAGE (Executor framework) -----------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice address of the executor quoter router for onchain quoting and execution requests
    IExecutorQuoterRouter public executorQuoterRouter;

    /// @notice address of the quoter used for pricing execution
    address public quoterAddress;

    /// @notice Wormhole Executor for off-chain quote flow
    IExecutor public executor;

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
    /// ---------------------- INITIALIZE -----------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice Initialize the Wormhole bridge
    /// @param newxerc20 xERC20 token address
    /// @param newOwner contract owner address
    /// @param wormholeRelayerAddress address of the wormhole relayer
    /// @param targetChains chain id of the target chain to address for bridging
    /// @param targetAddresses addresses of the wormhole bridge adapters to
    /// bridge to on external chains
    function initialize(
        address newxerc20,
        address newOwner,
        address wormholeRelayerAddress,
        uint16[] memory targetChains,
        address[] memory targetAddresses
    ) public initializer {
        __Ownable_init();
        _transferOwnership(newOwner);
        _setxERC20(newxerc20);

        wormholeRelayer = IWormholeRelayer(wormholeRelayerAddress);

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

    /// @notice V3 upgrade: set the Wormhole core bridge address for direct
    ///         VAA verification, bypassing the deprecated standard relayer.
    /// @param _wormhole address of the Wormhole core bridge on this chain
    function initializeV3(address _wormhole) external reinitializer(3) {
        require(_wormhole != address(0), "WormholeBridgeAdapter: zero address");
        wormhole = IWormhole(_wormhole);
    }

    /// @notice V5 upgrade: migrate to Wormhole Executor framework
    /// @param _executorAddress Executor address for off-chain quote flow
    /// @param _executorQuoterRouterAddress Executor Quoter Router for onchain quoting (address(0) on Moonbeam)
    /// @param _quoterAddr onchain quoter address for pricing execution (address(0) on Moonbeam)
    function initializeV5(
        address _executorAddress,
        address _executorQuoterRouterAddress,
        address _quoterAddr
    ) external reinitializer(5) {
        require(
            _executorAddress != address(0) && address(wormhole) != address(0),
            "WormholeBridge: zero address"
        );

        /// Moonbeam has no onchain quoter; all other chains must set both
        if (wormhole.chainId() != MOONBEAM_WORMHOLE_CHAIN_ID) {
            require(
                _executorQuoterRouterAddress != address(0) &&
                    _quoterAddr != address(0),
                "WormholeBridge: zero quoter address"
            );
        }

        executor = IExecutor(_executorAddress);
        executorQuoterRouter = IExecutorQuoterRouter(
            _executorQuoterRouterAddress
        );
        quoterAddress = _quoterAddr;
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ---------------- Admin Only Functions ------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice set a gas limit for the executor on the external chain
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
    /// @dev Uses the Executor onchain quoter. Returns 0 if the quote fails.
    /// @param dstChainId Destination chain id
    function bridgeCost(
        uint16 dstChainId
    ) public view returns (uint256 gasCost) {
        if (address(executorQuoterRouter) == address(0)) {
            return 0;
        }

        bytes memory relayInstructions = RelayInstructionLib.encodeGas(
            uint128(gasLimit),
            0
        );
        bytes memory requestBytes = RequestLib.encodeVaaMultiSigRequest(
            wormhole.chainId(),
            toUniversalAddress(address(this)),
            0
        );
        bytes32 peerAddr = toUniversalAddress(targetAddress[dstChainId]);

        try
            executorQuoterRouter.quoteExecution(
                dstChainId,
                peerAddr,
                address(this),
                quoterAddress,
                requestBytes,
                relayInstructions
            )
        returns (uint256 executorFee) {
            gasCost = executorFee + wormhole.messageFee();
        } catch {
            gasCost = 0;
        }
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// -------------------- Bridge In/Out ---------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice Bridge out using an off-chain signed quote from the Executor.
    /// Burns xERC20 tokens, publishes a message via Wormhole Core Bridge, then
    /// requests execution via the Executor with the signed quote.
    /// @param user to send funds from, should be msg.sender in all cases
    /// @param targetChain Destination chain id
    /// @param amount Amount of xERC20 to bridge out
    /// @param to Address to receive funds on destination chain
    /// @param signedQuote Signed quote obtained off-chain from the executor API
    function _bridgeOut(
        address user,
        uint256 targetChain,
        uint256 amount,
        address to,
        bytes calldata signedQuote
    ) internal override {
        uint16 targetChainId = targetChain.toUint16();
        require(
            targetAddress[targetChainId] != address(0),
            "WormholeBridge: invalid target chain"
        );

        /// user must burn xERC20 tokens first
        _burnTokens(user, amount);

        bytes memory payload = abi.encode(to, amount, targetChainId);

        /// Step 1: Publish message via Core Bridge
        uint256 messageFee = wormhole.messageFee();
        uint64 sequence = wormhole.publishMessage{value: messageFee}(
            0, // nonce
            payload,
            CONSISTENCY_LEVEL
        );

        /// Step 2: Request execution via Executor with off-chain signed quote
        bytes memory requestBytes = RequestLib.encodeVaaMultiSigRequest(
            wormhole.chainId(),
            toUniversalAddress(address(this)),
            sequence
        );
        bytes memory relayInstructions = RelayInstructionLib.encodeGas(
            uint128(gasLimit),
            0
        );
        bytes32 peerAddr = toUniversalAddress(targetAddress[targetChainId]);

        executor.requestExecution{value: msg.value - messageFee}(
            targetChainId,
            peerAddr,
            msg.sender,
            signedQuote,
            requestBytes,
            relayInstructions
        );

        emit TokensSent(targetChainId, to, amount);
    }

    /// @notice Bridge Out Funds to an external chain using the Executor framework.
    /// Burns xERC20 tokens, publishes a message via Wormhole Core Bridge, then
    /// requests execution via the ExecutorQuoterRouter (onchain quoting).
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
        require(
            address(executorQuoterRouter) != address(0),
            "WormholeBridge: onchain quoting not available, use bridge with signedQuote"
        );
        uint16 targetChainId = targetChain.toUint16();
        uint256 cost = bridgeCost(targetChainId);
        require(msg.value == cost, "WormholeBridge: cost not equal to quote");
        require(
            targetAddress[targetChainId] != address(0),
            "WormholeBridge: invalid target chain"
        );

        /// user must burn xERC20 tokens first
        _burnTokens(user, amount);

        bytes memory payload = abi.encode(to, amount, targetChainId);

        /// Publish message via Core Bridge
        uint256 messageFee = wormhole.messageFee();
        uint64 sequence = wormhole.publishMessage{value: messageFee}(
            0, // nonce
            payload,
            CONSISTENCY_LEVEL
        );

        /// Request execution via Executor
        bytes memory requestBytes = RequestLib.encodeVaaMultiSigRequest(
            wormhole.chainId(),
            toUniversalAddress(address(this)),
            sequence
        );
        bytes memory relayInstructions = RelayInstructionLib.encodeGas(
            uint128(gasLimit),
            0
        );
        bytes32 peerAddr = toUniversalAddress(targetAddress[targetChainId]);

        executorQuoterRouter.requestExecution{value: cost - messageFee}(
            targetChainId,
            peerAddr,
            msg.sender,
            quoterAddress,
            requestBytes,
            relayInstructions
        );

        emit TokensSent(targetChainId, to, amount);
    }

    /// @notice Receive and execute a Wormhole VAA. Anyone can submit a valid VAA.
    /// The contract verifies the VAA via the Wormhole Core Bridge, checks that the
    /// emitter is a trusted sender, and applies sequence-based replay protection.
    /// @param encodedVaa the encoded VAA to process
    function executeVAAv1(bytes memory encodedVaa) external payable override {
        require(msg.value == 0, "WormholeBridge: no value allowed");

        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole
            .parseAndVerifyVM(encodedVaa);
        require(valid, reason);

        require(
            isTrustedSender(vm.emitterChainId, vm.emitterAddress),
            "WormholeBridge: sender not trusted"
        );

        /// Backward-compat: reject VAAs already processed via the old processVAA path
        require(
            !processedVAAHashes[vm.hash],
            "WormholeBridge: VAA already processed"
        );
        processedVAAHashes[vm.hash] = true;

        /// Bitmap-based replay protection (deterministic storage slots, no mapping needed)
        SequenceReplayProtectionLib.replayProtect(
            vm.emitterChainId,
            vm.emitterAddress,
            vm.sequence
        );

        /// Parse the payload and do the corresponding actions!
        (address to, uint256 amount, uint16 targetChainId) = abi.decode(
            vm.payload,
            (address, uint256, uint16)
        );

        require(
            targetChainId == wormhole.chainId(),
            "WormholeBridge: invalid target chain"
        );

        /// mint tokens and emit events
        _bridgeIn(vm.emitterChainId, to, amount);
    }

    /// @notice DEPRECATED - Old Standard Relayer receive function
    /// @dev Always reverts. Use executeVAAv1() instead.
    function receiveWormholeMessages(
        bytes memory,
        bytes[] memory,
        bytes32,
        uint16,
        bytes32
    ) external payable {
        revert("WormholeBridge: deprecated, use executeVAAv1");
    }
}
