pragma solidity 0.8.19;

import {xERC20BridgeAdapter} from "@protocol/xWELL/xERC20BridgeAdapter.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IAxelarGateway} from "@protocol/xWELL/axelar-interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "@protocol/xWELL/axelar-interfaces/IAxelarGasService.sol";
import {AddressToString, StringToAddress} from "@protocol/xWELL/axelar-interfaces/AddressString.sol";

import {IXERC20} from "@protocol/xWELL/interfaces/IXERC20.sol";

/// @notice Axelar Token Bridge adapter for XERC20 tokens
/// @dev the access control model for this contract is to deploy
/// the same exact contract on separate chains, otherwise this does not work.
/// TODO change this model to trusted sender addresses, and explicitly rather than implicitly check.
contract AxelarBridge is xERC20BridgeAdapter {
    using SafeERC20 for IERC20;
    using StringToAddress for string;
    using AddressToString for address;

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
    /// TODO add setter functions for this mappping
    mapping(string => mapping(address => bool)) public isApproved;

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ------------------------ Events ------------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice emitted when a new chain id is set
    /// @param chainId native chain id
    /// @param axelarId axelar chain id
    event AxelarIdSet(uint256 indexed chainId, string indexed axelarId);

    /// @notice Initialize the bridge
    /// @param newxerc20 xERC20 token address
    /// @param newOwner contract owner address
    function initialize(
        address newxerc20,
        address newOwner,
        address axelarGateway,
        address axelarGasService
    ) public initializer {
        super.initialize(newxerc20, newOwner);

        gateway = IAxelarGateway(axelarGateway);
        gasService = IAxelarGasService(axelarGasService);
    }

    /// @notice use the axelar sdk to fetch the estimated cost of bridging tokens
    /// https://docs.axelar.dev/dev/reference/pricing#callcontract-general-message-passing
    function bridgeCost(
        uint256,
        uint256,
        address
    ) external pure override returns (uint256 gasCost) {
        return 0;
    }

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
            abi.encode(chainIdToAxelarId[dstChainId]).length != 0,
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

    /// @notice configuration from chainid to axelarid and vice versa
    struct ChainIds {
        /// @notice native chain id
        uint256 chainid;
        /// @notice corresponding axelar chain id
        string axelarid;
    }

    /// @notice add a new group of chain ids to the mapping.
    /// callable only by the owner
    /// @param chainIds the chain ids to add
    function addChainIds(ChainIds[] calldata chainIds) external onlyOwner {
        for (uint256 i; i < chainIds.length; ++i) {
            _addChainId(chainIds[i]);
        }
    }

    /// @notice helper function to add a new chain id to the mapping.
    /// @param chainids the chain id configuration to add
    function _addChainId(ChainIds memory chainids) private {
        chainIdToAxelarId[chainids.chainid] = chainids.axelarid;
        axelarIdToChainId[chainids.axelarid] = chainids.chainid;

        emit AxelarIdSet(chainids.chainid, chainids.axelarid);
    }

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
