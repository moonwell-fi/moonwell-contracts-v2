pragma solidity 0.8.19;

import {xERC20BridgeAdapter} from "@protocol/xWELL/xERC20BridgeAdapter.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IXERC20} from "@protocol/xWELL/interfaces/IXERC20.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {WormholeBridgeBase} from "@protocol/wormhole/WormholeBridgeBase.sol";

/// @notice Wormhole xERC20 Token Bridge adapter
contract WormholeBridgeAdapter is
    xERC20BridgeAdapter,
    WormholeBridgeBase
{
    using SafeCast for uint256;

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

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ---------------------- INITIALIZE -----------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

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
        // initialize WormholeBridgeBase
        _initialize(wormholeRelayerAddress, targetChain);
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
    function _bridgeTokenOut(
        address user,
        uint256 targetChain,
        uint256 amount,
        address to
    ) internal override {
        /// user must burn xERC20 tokens first
        _burnTokens(user, amount);

        // TODO check casting
        _bridgeOut(uint16(targetChain), abi.encode(to, amount));

        emit TokensSent(uint16(targetChain), to, amount);
    }

    /// @notice Bridge in funds from the chain to the given user
    /// by minting tokens to the user
    /// @param chainId chain id funds are bridged from
    /// @param payload payload to decode
    function _bridgeIn(
        uint16 chainId,
        bytes memory payload
        ) internal override {
        (address user, uint256 amount) = abi.decode(payload, (address, uint256));

        _bridgeTokenIn(chainId, amount, user);
    }

}
