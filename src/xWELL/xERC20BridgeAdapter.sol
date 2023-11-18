pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IXERC20} from "@protocol/xWELL/interfaces/IXERC20.sol";

/// @notice Abstract xERC20 Adapter Contract
abstract contract xERC20BridgeAdapter is Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice address of the xERC20 token
    IXERC20 public xERC20;

    /// @notice nonce of failed bridge transactions
    uint256 public nonce;

    /// @notice information on a failed bridge transaction
    /// can be used to replay the transaction and recover xERC20
    struct Error {
        uint256 chainId;
        address user;
        uint256 amount;
    }

    /// @notice mapping of error events for retry.
    mapping(uint256 => Error) public errors;

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ------------------------ Events ------------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice emitted when tokens are bridged out
    /// @param dstChainId destination chain id to send tokens to
    /// @param bridgeUser user who bridged out tokens
    /// @param tokenReceiver address to receive tokens on destination chain
    /// @param amount of tokens bridged out
    event BridgedOut(
        uint256 indexed dstChainId,
        address indexed bridgeUser,
        address indexed tokenReceiver,
        uint256 amount
    );

    /// @notice emitted when tokens are bridged in
    /// @param srcChainId source chain id tokens were bridged from
    /// @param tokenReceiver address to receive tokens on destination chain
    /// @param amount of tokens bridged in
    event BridgedIn(
        uint256 indexed srcChainId,
        address indexed tokenReceiver,
        uint256 amount
    );

    /// @notice emitted when a bridge error occurs
    /// @param errorId id of the error
    /// @param user user who bridged out tokens
    /// @param amount of tokens bridged out
    /// @param timestamp of the error
    event BridgeError(
        uint256 indexed errorId,
        address indexed user,
        uint256 amount,
        uint256 indexed timestamp
    );

    /// @notice ensure logic contract is unusable
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the bridge
    /// @param newxerc20 xERC20 token address
    /// @param newOwner contract owner address
    function initialize(
        address newxerc20,
        address newOwner
    ) public virtual initializer {
        __Ownable_init();
        xERC20 = IXERC20(newxerc20);
        _transferOwnership(newOwner);
    }

    /// @notice Bridge Out Funds
    /// @param dstChainId Destination chain id
    /// @param amount Amount of BIFI to bridge out
    /// @param to Address to receive funds on destination chain
    function bridge(
        uint256 dstChainId,
        uint256 amount,
        address to
    ) external payable virtual {
        _bridgeOut(msg.sender, dstChainId, amount, to);

        emit BridgedOut(dstChainId, msg.sender, to, amount);
    }

    /// @notice Bridge out funds from the chain from the given user
    /// by burning their tokens. The bridge out function must call
    /// this function in the overridden bridge out function.
    /// @param user to bridge out funds from
    /// @param amount of xERC20 tokens to bridge out
    function _burnTokens(address user, uint256 amount) internal {
        xERC20.burn(user, amount);
    }

    /// @notice Bridge in funds from the chain from the given user
    /// by minting tokens to the user
    /// @param chainId chain id funds are bridged from
    /// @param user to bridge in funds to
    /// @param amount of xERC20 tokens to bridge in
    function _bridgeIn(
        uint256 chainId,
        address user,
        uint256 amount
    ) internal virtual {
        try xERC20.mint(user, amount) {
            emit BridgedIn(chainId, user, amount);
        } catch {
            uint256 _nonce = nonce++;
            errors[_nonce] = Error(chainId, user, amount);

            emit BridgeError(_nonce, user, amount, block.timestamp);
        }
    }

    /// @notice Retry a failed bridge in
    /// @param errorId Id of error to retry
    function retry(uint256 errorId) external {
        Error memory userError = errors[errorId];
        delete errors[errorId];

        require(
            userError.user != address(0),
            "AxelarBridgeAdapter: no error found"
        );

        _bridgeIn(userError.chainId, userError.user, userError.amount);
    }

    /// @notice Estimate bridge cost
    /// @param dstChainId Destination chain id
    /// @param amount Amount of BIFI to bridge out
    /// @param to Address to receive funds on destination chain
    function bridgeCost(
        uint256 dstChainId,
        uint256 amount,
        address to
    ) external view virtual returns (uint256 gasCost);

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
    ) internal virtual;
}
