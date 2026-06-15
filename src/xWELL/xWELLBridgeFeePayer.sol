// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";

/// @notice Bridges xWELL through the WormholeBridgeAdapter while paying the
/// Wormhole Executor fee from this contract's own pre-funded ETH balance.
///
/// Why this exists: the adapter's on-chain-quoted path requires
/// `msg.value == bridgeCost(dstChainId)` exactly, but governance proposal
/// action values are frozen at propose time while execution happens days
/// later — the gas-priced quote will have drifted, so a direct
/// governor -> adapter bridge action is effectively guaranteed to revert.
/// Routing through this contract lets the proposal action carry zero value:
/// the quote is read and paid in the same transaction it executes in, so it
/// can never drift. (Long-term fix is relaxing the adapter's exact-match
/// requirement; this contract unblocks governance bridging until then.)
///
/// Roles:
/// - `caller` (the governor) is the only address allowed to bridge, so the
///   public cannot drain the fee balance with dust bridges.
/// - `sweeper` (ops) can recover the ETH balance.
/// Anyone can top up the fee balance by sending ETH.
contract xWELLBridgeFeePayer {
    using SafeERC20 for ERC20;

    /// @notice the xWELL token
    ERC20 public immutable xwell;

    /// @notice wormhole bridge adapter proxy
    WormholeBridgeAdapter public immutable wormholeBridge;

    /// @notice the only address allowed to bridge (the governor)
    address public immutable caller;

    /// @notice address allowed to sweep the ETH fee balance (ops)
    address public immutable sweeper;

    /// @param to address receiving xWELL on the destination chain
    /// @param destWormholeChainId wormhole chain id bridged to
    /// @param amount amount of xWELL bridged
    /// @param fee executor fee paid from this contract's balance
    event BridgeOutSuccess(
        address indexed to,
        uint16 indexed destWormholeChainId,
        uint256 amount,
        uint256 fee
    );

    /// @param to address receiving the swept ETH
    /// @param amount ETH swept
    event Swept(address indexed to, uint256 amount);

    constructor(
        address _xwell,
        address _wormholeBridge,
        address _caller,
        address _sweeper
    ) {
        xwell = ERC20(_xwell);
        wormholeBridge = WormholeBridgeAdapter(_wormholeBridge);
        caller = _caller;
        sweeper = _sweeper;
    }

    /// @notice accept ETH top-ups of the fee balance from anyone
    receive() external payable {}

    /// @notice current executor fee for a destination chain
    /// @param wormholeChainId wormhole chain id to bridge to
    function bridgeCost(
        uint16 wormholeChainId
    ) external view returns (uint256) {
        return wormholeBridge.bridgeCost(wormholeChainId);
    }

    /// @notice pull `amount` xWELL from the caller and bridge it to `to` on
    /// the destination chain, paying the live-quoted executor fee from this
    /// contract's ETH balance. Caller must have approved this contract.
    /// @param to address to receive the xWELL on the destination chain
    /// @param amount amount of xWELL to bridge
    /// @param wormholeChainId wormhole chain id to bridge to
    function bridgeToRecipient(
        address to,
        uint256 amount,
        uint16 wormholeChainId
    ) external {
        require(msg.sender == caller, "FeePayer: only caller");

        // quoted in the same transaction the adapter re-quotes in, so the
        // adapter's msg.value == bridgeCost() exact-match always holds
        uint256 cost = wormholeBridge.bridgeCost(wormholeChainId);
        require(cost > 0, "FeePayer: quote unavailable");
        require(
            address(this).balance >= cost,
            "FeePayer: insufficient fee balance"
        );

        xwell.safeTransferFrom(msg.sender, address(this), amount);

        // the adapter burns xWELL from its caller, which requires approval
        xwell.approve(address(wormholeBridge), amount);

        wormholeBridge.bridge{value: cost}(
            uint256(wormholeChainId),
            amount,
            to
        );

        emit BridgeOutSuccess(to, wormholeChainId, amount, cost);
    }

    /// @notice recover the ETH fee balance to `to`
    function sweep(address to) external {
        require(msg.sender == sweeper, "FeePayer: only sweeper");

        uint256 amount = address(this).balance;
        (bool success, ) = to.call{value: amount}("");
        require(success, "FeePayer: sweep failed");

        emit Swept(to, amount);
    }

    /// @notice recover accidentally-sent tokens to `to`
    /// @param token the token to sweep
    /// @param to address receiving the full token balance
    function sweepToken(address token, address to) external {
        require(msg.sender == sweeper, "FeePayer: only sweeper");

        uint256 amount = ERC20(token).balanceOf(address(this));
        ERC20(token).safeTransfer(to, amount);

        emit Swept(to, amount);
    }
}
