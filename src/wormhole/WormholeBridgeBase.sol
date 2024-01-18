pragma solidity 0.8.19;

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {IWormholeReceiver} from "@protocol/wormhole/IWormholeReceiver.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/// @notice Wormhole xERC20 Token Bridge adapter
abstract contract WormholeBridgeBase is
    IWormholeReceiver,
    WormholeTrustedSender
{
    // TODO do we need this?
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

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
    IWormholeRelayer public wormholeRelayer;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ----------------------- MAPPINGS ------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice nonces that have already been processed
    mapping(bytes32 => bool) public processedNonces;

    /// @notice chain id of the target chain to address for bridging
    /// starts off mapped to itself, but can be changed by governance
    mapping(uint16 => address) public targetAddress;

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- STATE VARIABLES -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

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

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ---------------------- INITIALIZE -----------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice Initialize the Wormhole bridge
    /// @param wormholeRelayerAddress address of the wormhole relayer
    /// @param trustedSenders array of trusted senders to add
    function _initialize(
        address wormholeRelayerAddress,
        TrustedSender[] memory trustedSenders
    ) internal {
        wormholeRelayer = IWormholeRelayer(wormholeRelayerAddress);
        
        _addTrustedSenders(trustedSenders);

        gasLimit = 300_000; /// @dev default starting gas limit for relayer 
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ---------------- Admin Only Functions ------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice set a gas limit for the relayer on the external chain
    /// should only be called if there is a change in gas prices on the external chain
    /// @param newGasLimit new gas limit to set
    function _setGasLimit(uint96 newGasLimit) internal  {
        uint96 oldGasLimit = gasLimit;
        gasLimit = newGasLimit;

        emit GasLimitUpdated(oldGasLimit, newGasLimit);
    }

    /// @notice add map of target addresses for external chains
    /// @dev there is no check here to ensure there isn't an existing configuration
    /// ensure the proper add or remove is being called when using this function
    /// @param _chainConfig array of chainids to addresses to add
    function _setTargetAddresses(
        TrustedSender[] memory _chainConfig
    ) internal {
        for (uint256 i = 0; i < _chainConfig.length; i++) {
            uint16 chainId = _chainConfig[i].chainId;
            targetAddress[chainId] = _chainConfig[i].addr;
            _targetChains.add(chainId);

            emit TargetAddressUpdated(
                                      chainId,
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
    /// @param dstChainId Destination chain id
    function bridgeCost(
        uint16 dstChainId
    ) public view returns (uint256 gasCost) {
        (gasCost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            dstChainId,
            0,
            gasLimit
        );
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// -------------------- Bridge In/Out ---------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice Bridge Out Funds to an external chain.
    /// @param targetChain Destination chain id
    /// @param payload Payload to send to the external chain
    function _bridgeOut(
        uint256 targetChain,
        bytes memory payload
    ) internal {
        uint16 targetChainId = targetChain.toUint16();
        uint256 cost = bridgeCost(targetChainId);
        require(msg.value == cost, "WormholeBridge: cost not equal to quote");
        require(
            targetAddress[targetChainId] != address(0),
            "WormholeBridge: invalid target chain"
        );

        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChainId,
            targetAddress[targetChainId],
            payload,
            0, /// no receiver value allowed, only message passing
            gasLimit
        );
    }

    /// @notice callable only by the wormhole relayer
    /// @param payload the payload of the message, contains the to and amount
    /// additional vaas, unused parameter
    /// @param senderAddress the address of the sender on the source chain, bytes32 encoded
    /// @param sourceChain the chain id of the source chain
    /// @param nonce the unique message ID
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory, // additionalVaas
        bytes32 senderAddress,
        uint16 sourceChain,
        bytes32 nonce
    ) external payable override {
        require(msg.value == 0, "WormholeBridge: no value allowed");
        require(
            msg.sender == address(wormholeRelayer),
            "WormholeBridge: only relayer allowed"
        );
        require(
            isTrustedSender(sourceChain, senderAddress),
            "WormholeBridge: sender not trusted"
        );
        require(
            !processedNonces[nonce],
            "WormholeBridge: message already processed"
        );

        processedNonces[nonce] = true;

        _bridgeIn(sourceChain, payload);
     }

    // @notice logic for bringing payload in from external chain
    // @dev must be overridden by implementation contract
    // @param sourceChain the chain id of the source chain
    // @param payload the payload of the message
    function _bridgeIn(uint16 sourceChain, bytes memory payload) internal virtual;
}
