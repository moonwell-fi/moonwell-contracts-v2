pragma solidity 0.8.19;

/// @notice contract to recover funds sent to an address that can be a smart contract
contract Recovery {
    /// @notice address that owns this contract. Non-Transferrable
    address public immutable owner;

    /// @notice modifier, makes functions callable only by the owner
    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /// @param _owner address that owns this contract.
    constructor(address _owner) {
        owner = _owner;
    }

    /// @notice send all ether this contract owns to receiver
    /// @param to recipient of ether
    function sendAllEth(address payable to) external onlyOwner {
        uint256 ethBalance = address(this).balance;

        (bool success, ) = to.call{value: ethBalance}("");

        require(success, "Recovery: underlying call reverted");
    }

    /// @notice struct to pack calldata and targets for an emergency action
    struct Call {
        /// @notice target address to call
        address target;
        /// @notice amount of eth to send with the call
        uint256 value;
        /// @notice payload to send to target
        bytes callData;
    }

    /// @notice due to inflexibility of current smart contracts,
    /// add this ability to be able to execute arbitrary calldata
    /// against arbitrary addresses.
    /// callable only by owner
    function emergencyAction(
        Call[] calldata calls
    ) external payable onlyOwner returns (bytes[] memory returnData) {
        returnData = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            address payable target = payable(calls[i].target);
            uint256 value = calls[i].value;
            bytes calldata callData = calls[i].callData;

            (bool success, bytes memory returned) = target.call{value: value}(
                callData
            );
            require(success, "Recovery: underlying call reverted");
            returnData[i] = returned;
        }
    }
}
