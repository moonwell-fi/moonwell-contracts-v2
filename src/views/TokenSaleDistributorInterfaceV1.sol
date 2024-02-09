// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

interface TokenSaleDistributorInterfaceV1 {
    function getPriorVotes(
        address account,
        uint blockNumber
    ) external view returns (uint);

    function totalAllocated(address recipient) external view returns (uint);

    function totalClaimed(address recipient) external view returns (uint);

    function delegates(address recipient) external view returns (address);

    function delegate(address delegatee) external;

    function balanceOf(address account) external view returns (uint);
}
