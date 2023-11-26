// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

interface UniswapV2PairInterface {
    function getReserves() external view returns (uint112, uint112,uint112);
    function token0() external view returns (address);
}
