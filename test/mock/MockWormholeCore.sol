// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";

contract MockWormholeCore {
    bool public validity = true;
    string public reasonString = "invalid things";
    bytes public payload;
    uint16 emitterChainId;
    bytes32 public emitterAddress;

    function setStorage(
        bool valid,
        uint16 _emitterChainId,
        bytes32 _emitterAddress,
        string memory _reason,
        bytes memory _payload
    ) external {
        validity = valid;
        reasonString = _reason;
        payload = _payload;
        emitterChainId = _emitterChainId;
        emitterAddress = _emitterAddress;
    }

    function parseAndVerifyVM(
        bytes calldata VAA
    )
        external
        view
        returns (IWormhole.VM memory vm, bool valid, string memory reason)
    {
        vm.hash = keccak256(VAA);
        vm.payload = payload;
        vm.emitterChainId = emitterChainId;
        vm.emitterAddress = emitterAddress;

        valid = validity;
        reason = reasonString;
    }
}
