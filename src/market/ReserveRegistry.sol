pragma solidity =0.8.19;

contract ReserveRegistry {
    /// @notice maps the mToken to the automation module address to receive assets
    mapping(address => address) public mTokenToAutomationModule;
}
