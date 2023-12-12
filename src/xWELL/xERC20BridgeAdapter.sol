pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IXERC20} from "@protocol/xWELL/interfaces/IXERC20.sol";

/// @notice Abstract Upgradeable xERC20 Adapter Contract
abstract contract xERC20BridgeAdapter is Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice address of the xERC20 token
    IXERC20 public xERC20;

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

    /// @notice ensure logic contract is unusable
    constructor() {
        _disableInitializers();
    }

    /// @notice Bridge Out Funds to an external chain
    /// @param dstChainId Destination chain id
    /// @param amount Amount of xERC20 to bridge out
    /// @param to Address to receive funds on destination chain
    function bridge(
        uint256 dstChainId,
        uint256 amount,
        address to
    ) external payable virtual {
        _bridgeOut(msg.sender, dstChainId, amount, to);

        emit BridgedOut(dstChainId, msg.sender, to, amount);
    }

    /// @notice set the xERC20 token
    /// @param newxerc20 address of the xERC20 token
    function _setxERC20(address newxerc20) internal {
        xERC20 = IXERC20(newxerc20);
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
        xERC20.mint(user, amount);

        emit BridgedIn(chainId, user, amount);
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
    ) internal virtual;
}
