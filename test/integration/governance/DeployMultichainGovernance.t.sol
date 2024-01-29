// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Well} from "@protocol/Governance/Well.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";

import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {Addresses} from "@proposals/Addresses.sol";

import "@forge-std/Test.sol";

contract DeployMultichainGovernanceTest {
    /// @notice addresses contract, stores all addresses
    Addresses public addresses;

    /// @notice well token contract
    Well public well;

    /// @notice xWELL token contract
    xWELL public xwell;

    /// @notice stkWell token contract
    IStakedWell public stkWell;

    /// @notice wormhole bridge adapter contract
    WormholeRelayerAdapter public wormholeAdapter;

    /// @notice user address for testing
    address user = address(0x123);

    /// @notice base wormhole chain id
    uint16 public constant wormholeBaseChainId = 30;

    /// @notice moonbeam wormhole chain id
    uint16 public constant wormholeMoonbeamChainId = 16;

    // @notice amount of each token to start with
    uint256 startingTokenAmount = 100_000 * 1e18;

    function setUp() public {
        addresses = new Addresses();

        well = ERC20(addresses.getAddress("WELL"));
        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
        // TODO add staked well to addresses.json
        stkWell = IStakedWell(addresses.getAddress("stkWELL_PROXY"));
        wormholeRelayer = (addresses.getAddress("WORMHOLE_RELAYER"));

        // User start only with well
        deal(address(well), user, startingTokenAmount);
    }
}
