pragma solidity 0.8.19;

import {xERC20BridgeAdapter} from "@protocol/xWELL/xERC20BridgeAdapter.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IXERC20} from "@protocol/xWELL/interfaces/IXERC20.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {IWormholeReceiver} from "@protocol/wormhole/IWormholeReceiver.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";

/// @notice Wormhole xERC20 Token Bridge adapter
/// TODO change this model to trusted sender addresses, and explicitly rather than implicitly check.
contract WormholeBridgeAdapter is
    IWormholeReceiver,
    xERC20BridgeAdapter,
    WormholeTrustedSender
{
    using SafeCast for uint256;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------------ SINGLE STORAGE SLOT ------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @dev packing these variables into a single slot saves a
    /// COLD SLOAD on bridge out operations.

    /// TODO investigate and ensure this is accurate. If it can be lower, move lower.
    /// @notice gas limit for wormhole relayer, changeable incase gas prices change on external network
    uint96 public gasLimit = 300_000;

    /// @notice address of the wormhole relayer cannot be changed by owner
    /// because the relayer contract is a proxy
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

    /// @notice Initialize the Wormhole bridge
    /// @param newxerc20 xERC20 token address
    /// @param newOwner contract owner address
    /// @param wormholeRelayerAddress address of the wormhole relayer
    /// @param targetChain chain id of the target chain to address for bridging
    function initialize(
        address newxerc20,
        address newOwner,
        address wormholeRelayerAddress,
        uint16 targetChain
    ) public initializer {
        __Ownable_init();
        _transferOwnership(newOwner);
        _setxERC20(newxerc20);

        wormholeRelayer = IWormholeRelayer(wormholeRelayerAddress);

        /// initialize contract to trust this exact same address on an external chain
        /// @dev the external chain contracts MUST HAVE THE SAME ADDRESS on the external chain
        targetAddress[targetChain] = address(this);
        _addTrustedSender(address(this), targetChain);
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

    /// @notice Estimate bridge cost to bridge out to a destination chain
    /// backwards compatible with the xERC20BridgeAdapter getter interface
    /// @param dstChainId Destination chain id
    /// all other params are ignored
    function bridgeCost(
        uint256 dstChainId,
        uint256,
        address
    ) public view override returns (uint256) {
        return bridgeCost(dstChainId.toUint16());
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// -------------------- Bridge In/Out ---------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice Bridge Out Funds to an external chain.
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
        uint256 cost = bridgeCost(targetChainId);
        require(msg.value == cost, "WormholeBridge: cost not equal to quote");
        require(
            targetAddress[targetChainId] != address(0),
            "WormholeBridge: invalid target chain"
        );

        /// user must burn xERC20 tokens first
        _burnTokens(user, amount);

        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChainId,
            targetAddress[targetChainId],
            abi.encode(to, amount), // payload
            0, /// no receiver value allowed, only message passing
            gasLimit
        );

        emit TokensSent(targetChainId, to, amount);
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

        // Parse the payload and do the corresponding actions!
        (address to, uint256 amount) = abi.decode(payload, (address, uint256));

        /// mint tokens and emit events
        _bridgeIn(sourceChain, to, amount);
    }
}
