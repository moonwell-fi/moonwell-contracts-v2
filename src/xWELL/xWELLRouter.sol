pragma solidity 0.8.19;

import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {XERC20Lockbox} from "@protocol/xWELL/XERC20Lockbox.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";

/// @notice xWELL Router Contract that allows users to bridge their WELL to xWELL on the base chain
/// this reduces the amount of transactions needed from 4 to 2 to turn WELL into xWELL
/// 1. approve the lockbox to spend WELL
/// 2. call the bridgeToBase function
/// This contract is permissionless and ungoverned.
/// If WELL is sent to it, it will be lost
/// If xWELL is sent to it, it will be able to be used by the next user that converts WELL to xWELL
contract xWELLRouter {
    using SafeERC20 for ERC20;

    /// @notice the xWELL token
    xWELL public immutable xwell;

    /// @notice standard WELL token
    ERC20 public immutable well;

    /// @notice xWELL lockbox to convert well to xwell
    XERC20Lockbox public immutable lockbox;

    /// @notice wormhole bridge adapter proxy
    WormholeBridgeAdapter public wormholeBridge;

    /// @notice the chain id of the base chain
    uint16 public constant baseWormholeChainId = 30;

    /// @notice event emitted when WELL is bridged to xWELL via the base chain
    event BridgeOutSuccess(address indexed to, uint256 amount);

    /// @notice initialize the xWELL router
    /// @param _xwell the xWELL token
    /// @param _well the standard WELL token
    /// @param _lockbox the xWELL lockbox
    /// @param _wormholeBridge the wormhole bridge adapter proxy
    constructor(
        address _xwell,
        address _well,
        address _lockbox,
        address _wormholeBridge
    ) {
        xwell = xWELL(_xwell);
        well = ERC20(_well);
        lockbox = XERC20Lockbox(_lockbox);
        wormholeBridge = WormholeBridgeAdapter(_wormholeBridge);
    }

    /// @notice returns the cost to mint tokens on the base chain in GLMR
    function bridgeCost() external view returns (uint256) {
        return wormholeBridge.bridgeCost(baseWormholeChainId);
    }
    
    /// @notice bridge WELL to xWELL on the base chain
    /// receiver address to receive the xWELL is msg.sender
    /// @param amount amount of WELL to bridge
    function bridgeToBase(uint256 amount) external payable {
        _bridgeToBase(msg.sender, amount);
    }

    /// @notice bridge WELL to xWELL on the base chain
    /// @param to address to receive the xWELL
    /// @param amount amount of WELL to bridge
    function bridgeToBase(address to, uint256 amount) external payable {
        _bridgeToBase(to, amount);
    }

    /// @notice helper function to bridge WELL to xWELL on the base chain
    /// @param to address to receive the xWELL
    /// @param amount amount of WELL to bridge
    function _bridgeToBase(address to, uint256 amount) private {
        /// transfer WELL to this contract from the sender
        well.safeTransferFrom(msg.sender, address(this), amount);

        /// approve the lockbox to spend the WELL
        well.approve(address(lockbox), amount);

        /// deposit the WELL into the lockbox, which credits the lockbox with the xWELL
        lockbox.deposit(amount);

        /// get the amount of xWELL credited to the lockbox
        uint256 xwellAmount = xwell.balanceOf(address(this));

        /// approve the wormhole bridge to spend the xWELL
        xwell.approve(address(wormholeBridge), xwellAmount);

        /// bridge the xWELL to the base chain
        wormholeBridge.bridge{value: msg.value}(
            baseWormholeChainId,
            xwellAmount,
            to
        );

        emit BridgeOutSuccess(to, amount);
    }
}
