// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract MockRedstoneMultiFeedAdapter {
    function getLastUpdateDetails(
        bytes32
    )
        public
        view
        virtual
        returns (
            uint256 lastDataTimestamp,
            uint256 lastBlockTimestamp,
            uint256 lastValue
        )
    {
        return (block.timestamp, block.timestamp, 100_000e8);
    }
}
