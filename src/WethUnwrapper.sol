// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {WETH9} from "@protocol/router/IWETH.sol";

contract WethUnwrapper {
    /// @notice the mToken address
    address public constant mToken = 0x628ff693426583D9a7FB391E54366292F509D457;

    /// @notice reference to the WETH contract
    address public immutable weth;

    /// @notice construct a new WethUnwrapper
    /// @param _weth the WETH contract address
    constructor(address _weth) {
        weth = _weth;
    }

    /// @notice transfer ETH underlying to the recipient
    /// first unwrap the WETH into raw ETH, then transfer
    /// @param to the recipient address
    /// @param amount the amount of ETH to transfer
    function send(address payable to, uint256 amount) external {
        require(msg.sender == mToken, "only mToken can call send");

        WETH9(weth).withdraw(amount);
        (bool success, bytes memory returndata) = to.call{value: amount}("");

        if (!success) {
            if (returndata.length == 0) revert();
            assembly {
                revert(add(32, returndata), mload(returndata))
            }
        }
    }

    receive() external payable {}
}
