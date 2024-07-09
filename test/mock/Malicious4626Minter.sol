pragma solidity 0.8.19;

import {MoonwellERC4626Eth} from "@protocol/4626/MoonwellERC4626Eth.sol";

contract Malicious4626Minter {
    uint8 public immutable action;
    constructor(uint8 _action) {
        action = _action;
    }

    /// 1. redeem shares
    function startAttack(address target) public {
        MoonwellERC4626Eth vault = MoonwellERC4626Eth(payable(target));
        vault.redeem(
            vault.balanceOf(address(this)),
            address(this),
            address(this)
        );
    }

    /// 2. received eth gets sent to fallback
    /// 3. attempt reentrant callback to target
    receive() external payable {
        if (action == 1) {
            MoonwellERC4626Eth(payable(msg.sender)).deposit(0, address(this));
        } else if (action == 2) {
            MoonwellERC4626Eth(payable(msg.sender)).mint(0, address(this));
        } else if (action == 3) {
            MoonwellERC4626Eth(payable(msg.sender)).withdraw(
                1,
                address(this),
                address(this)
            );
        } else {
            MoonwellERC4626Eth(payable(msg.sender)).redeem(
                1,
                address(this),
                address(this)
            );
        }
    }
}
