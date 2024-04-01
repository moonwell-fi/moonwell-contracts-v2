pragma solidity 0.8.19;

import {xERC20BridgeAdapter} from "@protocol/xWELL/xERC20BridgeAdapter.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAxelarGateway} from "@protocol/xWELL/axelarInterfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "@protocol/xWELL/axelarInterfaces/IAxelarGasService.sol";
import {AddressToString, StringToAddress} from "@protocol/xWELL/axelarInterfaces/AddressString.sol";

/// @notice Axelar Token Bridge adapter for XERC20 tokens
/// @dev the access control model for this contract is to deploy
/// the same exact contract on separate chains, otherwise this does not work.
contract AxelarBridgeAdapter is xERC20BridgeAdapter {
    using SafeERC20 for IERC20;
    using StringToAddress for string;
    using AddressToString for address;

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// ------------------- State Variables ------------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @notice reference to the axelar gateway contract
    IAxelarGateway public gateway;

    /// @notice reference to the axelar gas service contract
    IAxelarGasService public gasService;

    /// @notice chainid to axelar id mapping
    mapping(uint256 => string) public chainIdToAxelarId;

    /// @notice axelar id to chainid mapping
    mapping(string => uint256) public axelarIdToChainId;

    /// @notice whether or not a given address on a given chain is approved
    /// to mint tokens on this chain.
    mapping(string => mapping(address => bool)) public isApproved;

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// ----------------------- Structs ----------------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @notice configuration from chainid to axelarid and vice versa
    struct ChainIds {
        /// @notice native chain id
        uint256 chainid;
        /// @notice corresponding axelar chain id
        string axelarid;
    }

    /// @notice configuration for a trusted bridge contract on an external chain
    struct ChainConfig {
        /// @notice bridge on external chain
        address adapter;
        /// @notice axelar id of external chain
        string axelarid;
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ------------------------ Events ------------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice emitted when a new chain id is set
    /// @param chainId native chain id
    /// @param axelarId axelar chain id
    event AxelarIdSet(uint256 indexed chainId, string indexed axelarId);

    /// @notice emitted when a new chain id is set
    /// @param bridge address approved
    /// @param axelarId axelar chain id
    /// @param approval whether or not the bridge address is approved
    event AxelarBridgeApprovalUpdated(
        address indexed bridge,
        string indexed axelarId,
        bool approval
    );

    /// @notice emitted when a new sender approval is updated
    /// @param bridge adapter address approved
    /// @param axelarId axelar chain id
    /// @param approval whether or not the bridge adapter address is approved
    event SenderApprovalUpdated(
        address indexed bridge,
        string indexed axelarId,
        bool approval
    );

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ---------------------- Initialize ----------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice Initialize the bridge
    /// @param newxerc20 xERC20 token address
    /// @param newOwner contract owner address
    function initialize(
        address newxerc20,
        address newOwner,
        address axelarGateway,
        address axelarGasService,
        ChainIds[] memory chainIds,
        ChainConfig[] memory configs
    ) public initializer {
        /// transfer ownership
        _transferOwnership(newOwner);

        /// set token
        _setxERC20(newxerc20);

        gateway = IAxelarGateway(axelarGateway);
        gasService = IAxelarGasService(axelarGasService);

        for (uint256 i; i < chainIds.length; ++i) {
            _addChainId(chainIds[i]);
        }

        for (uint256 i = 0; i < configs.length; i++) {
            _addExternalSender(configs[i]);
        }
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ------------------ View Only Functions -----------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice return whether the axelar chain id is valid and configured in this contract
    function validAxelarChainid(
        string memory axelarid
    ) public view returns (bool) {
        return axelarIdToChainId[axelarid] != 0;
    }

    /// @notice return whether the chain id is valid and configured in this contract
    function validChainId(uint256 chainid) public view returns (bool) {
        return bytes(chainIdToAxelarId[chainid]).length != 0;
    }

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// --------------------- Admin Functions ----------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @notice add a new group of chain ids to the mapping.
    /// callable only by the owner
    /// @param chainIds the chain ids to add
    function addChainIds(ChainIds[] calldata chainIds) external onlyOwner {
        unchecked {
            for (uint256 i; i < chainIds.length; ++i) {
                _addChainId(chainIds[i]);
            }
        }
    }

    /// @notice remove a group of chain ids from the mapping.
    /// callable only by the owner
    /// @param chainIds the chain ids to remove
    function removeChainIds(ChainIds[] calldata chainIds) external onlyOwner {
        unchecked {
            for (uint256 i; i < chainIds.length; ++i) {
                _removeChainId(chainIds[i]);
            }
        }
    }

    /// @notice add approved external bridge address on a different chain
    /// @param configs of bridges and chainids to add
    function addExternalChainSenders(
        ChainConfig[] memory configs
    ) external onlyOwner {
        unchecked {
            for (uint256 i = 0; i < configs.length; i++) {
                _addExternalSender(configs[i]);
            }
        }
    }

    /// @notice remove bridge addresses as trusted senders from a different chain
    /// @param configs of bridges and chainids to remove
    function removeExternalChainSenders(
        ChainConfig[] memory configs
    ) external onlyOwner {
        unchecked {
            for (uint256 i = 0; i < configs.length; i++) {
                _removeExternalSender(configs[i]);
            }
        }
    }

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// -------------- Internal Helper Functions -------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @notice helper function to add a new trusted sender.
    /// the axelar chainid must be currently valid, and
    /// the adapter address must not already be approved.
    /// @param config the config to add
    function _addExternalSender(ChainConfig memory config) private {
        require(
            !isApproved[config.axelarid][config.adapter],
            "AxelarBridge: config already approved"
        );
        require(
            /// valid axelarId
            validAxelarChainid(config.axelarid),
            "AxelarBridge: invalid axelar id"
        );

        isApproved[config.axelarid][config.adapter] = true;

        emit SenderApprovalUpdated(config.adapter, config.axelarid, true);
    }

    /// @notice can only remove when the config is already approved.
    /// state of the axelarid does not matter as an axelar id could be removed
    /// and external senders still need to be cleaned up from that config.
    /// @param config the config to remove
    function _removeExternalSender(ChainConfig memory config) private {
        require(
            isApproved[config.axelarid][config.adapter],
            "AxelarBridge: config not already approved"
        );

        isApproved[config.axelarid][config.adapter] = false;

        emit SenderApprovalUpdated(config.adapter, config.axelarid, false);
    }

    /// @notice helper function to add a new chain id to the mapping.
    /// @param chainids the chain id configuration to add
    function _addChainId(ChainIds memory chainids) private {
        require(
            !validChainId(chainids.chainid),
            "AxelarBridge: existing chainId config"
        );
        require(
            !validAxelarChainid(chainids.axelarid),
            "AxelarBridge: existing axelarId config"
        );

        chainIdToAxelarId[chainids.chainid] = chainids.axelarid;
        axelarIdToChainId[chainids.axelarid] = chainids.chainid;

        emit AxelarIdSet(chainids.chainid, chainids.axelarid);
    }

    /// @notice helper function to add a new chain id to the mapping.
    /// @param chainids the chain id configuration to add
    function _removeChainId(ChainIds memory chainids) private {
        require(
            validChainId(chainids.chainid),
            "AxelarBridge: non-existent chainid config"
        );
        require(
            validAxelarChainid(chainids.axelarid),
            "AxelarBridge: non-existent axelarId config"
        );

        delete chainIdToAxelarId[chainids.chainid];
        delete axelarIdToChainId[chainids.axelarid];

        emit AxelarIdSet(chainids.chainid, chainids.axelarid);
    }

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// ------------- Internal Override Functions ------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @notice bridge tokens from this chain to the dstChain
    /// @param user address burning tokens and funding the cross chain call
    /// @param dstChainId destination chain id
    /// @param amount amount of tokens to bridge
    /// @param to address to receive tokens on the destination chain
    function _bridgeOut(
        address user,
        uint256 dstChainId,
        uint256 amount,
        address to
    ) internal override {
        require(
            bytes(chainIdToAxelarId[dstChainId]).length != 0,
            "AxelarBridge: invalid chain id"
        );

        _burnTokens(user, amount);

        // Send message to receiving bridge to mint tokens to user.
        bytes memory payload = abi.encode(to, amount);

        /// pay for the transaction on the destination chain.
        gasService.payNativeGasForContractCall{value: msg.value}(
            address(this),
            chainIdToAxelarId[dstChainId],
            address(this).toString(),
            payload,
            user
        );

        // Send message to receiving bridge to mint tokens to user.
        gateway.callContract(
            chainIdToAxelarId[dstChainId],
            address(this).toString(),
            payload
        );

        emit BridgedOut(dstChainId, user, to, amount);
    }

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// -------------------- Mint Function -------------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @notice execute a bridge in using the axelar gateway
    /// @param commandId the command id
    /// @param sourceChain the source chain
    /// @param sourceAddress the sending address on the source chain
    /// @param payload the payload that contains the recipient address and the token amount
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external {
        require(
            axelarIdToChainId[sourceChain] != 0,
            "AxelarBridgeAdapter: invalid source chain"
        );
        require(
            isApproved[sourceChain][sourceAddress.toAddress()],
            "AxelarBridgeAdapter: sender not approved"
        );

        bytes32 payloadHash = keccak256(payload);

        require(
            gateway.validateContractCall(
                commandId,
                sourceChain,
                sourceAddress,
                payloadHash
            ),
            "AxelarBridgeAdapter: call not approved by gateway"
        );

        (address user, uint256 amount) = abi.decode(
            payload,
            (address, uint256)
        );

        _bridgeIn(axelarIdToChainId[sourceChain], user, amount);
    }
}
