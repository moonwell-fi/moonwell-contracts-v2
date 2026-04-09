pragma solidity 0.8.19;

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {IWormholeReceiver} from "@protocol/wormhole/IWormholeReceiver.sol";
import {xERC20BridgeAdapter} from "@protocol/xWELL/xERC20BridgeAdapter.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";

/// @notice Wormhole xERC20 Token Bridge adapter
contract WormholeBridgeAdapter is
    IWormholeReceiver,
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

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------------ SINGLE STORAGE SLOT ------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @dev packing these variables into a single slot saves a
    /// COLD SLOAD on bridge out operations.

    /// @notice gas limit for wormhole relayer, changeable incase gas prices change on external network
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

    /// @notice Wormhole core bridge for on-chain VAA verification
    IWormhole public wormhole;

    /// @notice tracks processed VAA hashes to prevent replay
    mapping(bytes32 => bool) public processedVAAHashes;

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

    /// @notice Estimate bridge cost to bridge out to a destination chain.
    ///         Returns the Wormhole core messageFee (currently 0 on all chains).
    ///         The deprecated relayer quoter is no longer called since V3 uses
    ///         direct publishMessage via Wormhole core.
    function bridgeCost(uint16) public view returns (uint256) {
        return wormhole.messageFee();
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// -------------------- Bridge In/Out ---------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice Bridge Out Funds to an external chain.
    /// Callable by the users to bridge out their funds to an external chain.
    /// Publishes a direct application VAA via Wormhole core bridge so that
    /// guardians sign with this contract as emitter. The VAA can then be
    /// relayed permissionlessly via processVAA() on the destination chain.
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
        require(
            targetAddress[targetChainId] != address(0),
            "WormholeBridgeAdapter: invalid target chain"
        );

        uint256 cost = bridgeCost(targetChainId);
        require(
            msg.value == cost,
            "WormholeBridgeAdapter: cost not equal to quote"
        );

        /// user must burn xERC20 tokens first
        _burnTokens(user, amount);

        /// Publish a direct application VAA via Wormhole core bridge.
        wormhole.publishMessage{value: cost}(
            0,
            abi.encode(to, amount, targetChainId),
            CONSISTENCY_LEVEL
        );

        emit TokensSent(targetChainId, to, amount);
    }

    /// @notice Process a guardian-signed VAA to complete a bridge-in transfer.
    ///         Callable by anyone (permissionless). The VAA must be signed by
    ///         the Wormhole guardian quorum. The emitter must be a trusted sender
    ///         (the WormholeBridgeAdapter on the source chain).
    /// @param signedVAA The full guardian-signed VAA bytes
    function processVAA(bytes calldata signedVAA) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole
            .parseAndVerifyVM(signedVAA);

        require(valid, reason);
        require(
            isTrustedSender(vm.emitterChainId, vm.emitterAddress),
            "WormholeBridgeAdapter: untrusted emitter"
        );

        require(
            !processedVAAHashes[vm.hash],
            "WormholeBridgeAdapter: VAA already processed"
        );
        processedVAAHashes[vm.hash] = true;

        (address to, uint256 amount, uint16 targetChainId) = abi.decode(
            vm.payload,
            (address, uint256, uint16)
        );
        require(
            targetChainId == wormhole.chainId(),
            "WormholeBridgeAdapter: invalid target chain"
        );
        _bridgeIn(vm.emitterChainId, to, amount);
    }

    /// @notice legacy relayer entry point — deprecated
    /// @dev kept to satisfy the IWormholeReceiver interface
    function receiveWormholeMessages(
        bytes memory, // payload
        bytes[] memory, // additionalVaas
        bytes32, // senderAddress
        uint16, // sourceChain
        bytes32 // nonce
    ) external payable override {
        require(
            address(wormhole) == address(0),
            "WormholeBridgeAdapter: relayer disabled"
        );
    }
}
