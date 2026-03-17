// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";
import "@protocol/utils/ChainIds.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Address} from "@utils/Address.sol";
import {ChainIds} from "@utils/ChainIds.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {XERC20Lockbox} from "@protocol/xWELL/XERC20Lockbox.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {MOONBEAM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {VaaHelper} from "@test/helper/VaaHelper.sol";
import {ICoreBridge} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {toUniversalAddress} from "wormhole-sdk/Utils.sol";
import {SequenceReplayProtectionLib} from "wormhole-sdk/libraries/ReplayProtection.sol";

contract xWellIntegrationTest is Test {
    using ChainIds for uint256;
    using Address for address;

    /// @notice all addresses
    Addresses public addresses;

    /// @notice logic contract, not initializable
    xWELL public xwell;

    /// @notice wormhole bridge adapter contract
    WormholeBridgeAdapter public wormholeAdapter;

    /// @notice user address for testing
    address user = address(0x123);

    /// @notice amount of well to mint
    uint256 public constant startingWellAmount = 100_000 * 1e18;

    /// @notice sequence counter for VAA construction
    uint64 public vaaSequence;

    function setUp() public {
        addresses = new Addresses();

        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
        wormholeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        // Set up the core bridge with a devnet guardian so we can sign VAAs
        VaaHelper.setUpGuardianOverride(wormholeAdapter.coreBridge());
    }

    function testReinitializeFails() public {
        vm.expectRevert("Initializable: contract is already initialized");
        xwell.initialize(
            "WELL",
            "WELL",
            address(1),
            new MintLimits.RateLimitMidPointInfo[](0),
            0,
            address(0)
        );

        vm.expectRevert();
        wormholeAdapter.initialize(
            address(1),
            address(1),
            new uint16[](0),
            new address[](0)
        );
    }

    function testSetup() public view {
        address externalChainAddress = wormholeAdapter.targetAddress(
            MOONBEAM_WORMHOLE_CHAIN_ID
        );
        assertEq(
            externalChainAddress,
            address(wormholeAdapter),
            "incorrect target address config"
        );
        bytes32[] memory externalAddresses = wormholeAdapter.allTrustedSenders(
            MOONBEAM_WORMHOLE_CHAIN_ID
        );
        assertEq(externalAddresses.length, 1, "incorrect trusted senders");
        assertEq(
            externalAddresses[0],
            address(wormholeAdapter).toBytes(),
            "incorrect actual trusted senders"
        );
        assertTrue(
            wormholeAdapter.isTrustedSender(
                uint16(MOONBEAM_WORMHOLE_CHAIN_ID),
                address(wormholeAdapter)
            ),
            "self on moonbeam not trusted sender"
        );
    }

    function testBridgeInSuccess(uint256 mintAmount) public returns (uint256) {
        mintAmount = _bound(
            mintAmount,
            1,
            xwell.buffer(address(wormholeAdapter))
        );

        uint256 startingXWellBalance = xwell.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));

        uint16 dstWormholeChainId = wormholeAdapter.wormholeChainId();

        // New payload format: (destinationChainId, to, amount)
        bytes memory payload = abi.encode(dstWormholeChainId, user, mintAmount);

        // Emitter is the adapter on Moonbeam (trusted sender)
        uint16 emitterChainId = MOONBEAM_WORMHOLE_CHAIN_ID;
        address emitterAddress = address(wormholeAdapter);

        // Craft a signed VAA using the devnet guardian key
        bytes memory vaa = VaaHelper.craftVaa(
            wormholeAdapter.coreBridge(),
            emitterChainId,
            emitterAddress,
            vaaSequence++,
            payload
        );

        // Anyone can submit the VAA
        wormholeAdapter.executeVAAv1(vaa);

        uint256 endingXWellBalance = xwell.balanceOf(user);
        uint256 endingXWellTotalSupply = xwell.totalSupply();
        uint256 endingBuffer = xwell.buffer(address(wormholeAdapter));

        assertEq(
            endingXWellBalance,
            startingXWellBalance + mintAmount,
            "user xWELL balance incorrect"
        );
        assertEq(
            endingXWellTotalSupply,
            startingXWellTotalSupply + mintAmount,
            "total xWELL supply incorrect"
        );
        assertEq(endingBuffer, startingBuffer - mintAmount, "buffer incorrect");

        return mintAmount;
    }
}
