pragma solidity 0.8.19;

interface IMultichainProposal {
    /// fork ID for base
    function baseForkId() external view returns (uint256);

    /// fork ID for moonbeam
    function moonbeamForkId() external view returns (uint256);

    /// set fork ID's for base and moonbeam
    function setForkIds(uint256 baseForkId, uint256 moonbeamForkId) external;
}
