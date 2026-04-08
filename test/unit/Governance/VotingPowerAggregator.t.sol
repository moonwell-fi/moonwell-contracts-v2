// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MockxWELL} from "@test/mock/MockxWELL.sol";
import {MockSnapshotSource} from "@test/mock/MockSnapshotSource.sol";
import {VotingPowerAggregator} from "@protocol/governance/multichain/VotingPowerAggregator.sol";
import {IVotingPowerAggregator} from "@protocol/governance/multichain/IVotingPowerAggregator.sol";

contract VotingPowerAggregatorUnitTest is Test {
    VotingPowerAggregator public votingPowerAggregator;
    VotingPowerAggregator public implementation;
    MockxWELL public xwell;
    MockSnapshotSource public source1;
    MockSnapshotSource public source2;
    MockSnapshotSource public source3;
    ProxyAdmin public proxyAdmin;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public nonOwner = address(0x3);

    event SnapshotSourceAdded(address source);
    event SnapshotSourceRemoved(address source);

    function setUp() public {
        // Deploy mock xWELL
        xwell = new MockxWELL();

        // Deploy mock snapshot sources
        source1 = new MockSnapshotSource();
        source2 = new MockSnapshotSource();
        source3 = new MockSnapshotSource();

        // Deploy proxy admin
        proxyAdmin = new ProxyAdmin();

        // Deploy implementation
        implementation = new VotingPowerAggregator();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            owner,
            address(xwell)
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );

        votingPowerAggregator = VotingPowerAggregator(address(proxy));
    }

    /// ========================================================================
    /// Initialization Tests
    /// ========================================================================

    function testInitializeSucceeds() public {
        // Deploy fresh contracts
        MockxWELL newXwell = new MockxWELL();
        VotingPowerAggregator newImplementation = new VotingPowerAggregator();

        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            user1,
            address(newXwell)
        );

        TransparentUpgradeableProxy newProxy = new TransparentUpgradeableProxy(
            address(newImplementation),
            address(proxyAdmin),
            initData
        );

        VotingPowerAggregator newAggregator = VotingPowerAggregator(
            address(newProxy)
        );

        assertEq(newAggregator.owner(), user1, "owner not set correctly");
        assertEq(
            address(newAggregator.xWell()),
            address(newXwell),
            "xWell not set correctly"
        );
    }

    function testInitializeWithZeroOwnerSucceeds() public {
        // OwnableUpgradeable allows zero address owner during initialization
        // This is different from Ownable2Step which has stricter checks
        VotingPowerAggregator newImplementation = new VotingPowerAggregator();

        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            address(0),
            address(xwell)
        );

        TransparentUpgradeableProxy newProxy = new TransparentUpgradeableProxy(
            address(newImplementation),
            address(proxyAdmin),
            initData
        );

        VotingPowerAggregator newAggregator = VotingPowerAggregator(
            address(newProxy)
        );

        assertEq(
            newAggregator.owner(),
            address(0),
            "owner should be zero address"
        );
    }

    function testCannotInitializeTwice() public {
        vm.expectRevert("Initializable: contract is already initialized");
        votingPowerAggregator.initialize(owner, address(xwell));
    }

    function testCannotInitializeImplementation() public {
        vm.expectRevert("Initializable: contract is already initialized");
        implementation.initialize(owner, address(xwell));
    }

    /// ========================================================================
    /// Snapshot Source Management Tests - Add
    /// ========================================================================

    function testAddSnapshotSourceAsOwnerSucceeds() public {
        assertFalse(
            votingPowerAggregator.isSnapshotSource(address(source1)),
            "source1 should not be snapshot source initially"
        );

        votingPowerAggregator.addSnapshotSource(address(source1));

        assertTrue(
            votingPowerAggregator.isSnapshotSource(address(source1)),
            "source1 should be snapshot source after adding"
        );
    }

    function testAddSnapshotSourceEmitsEvent() public {
        vm.expectEmit(true, true, true, true, address(votingPowerAggregator));
        emit SnapshotSourceAdded(address(source1));

        votingPowerAggregator.addSnapshotSource(address(source1));
    }

    function testAddMultipleSnapshotSourcesSucceeds() public {
        votingPowerAggregator.addSnapshotSource(address(source1));
        votingPowerAggregator.addSnapshotSource(address(source2));
        votingPowerAggregator.addSnapshotSource(address(source3));

        assertTrue(
            votingPowerAggregator.isSnapshotSource(address(source1)),
            "source1 should be added"
        );
        assertTrue(
            votingPowerAggregator.isSnapshotSource(address(source2)),
            "source2 should be added"
        );
        assertTrue(
            votingPowerAggregator.isSnapshotSource(address(source3)),
            "source3 should be added"
        );
    }

    function testAddSnapshotSourceAsNonOwnerFails() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        votingPowerAggregator.addSnapshotSource(address(source1));
    }

    function testAddDuplicateSnapshotSourceFails() public {
        votingPowerAggregator.addSnapshotSource(address(source1));

        vm.expectRevert(IVotingPowerAggregator.EnumerableSetError.selector);
        votingPowerAggregator.addSnapshotSource(address(source1));
    }

    function testAddXWellAsSnapshotSourceFails() public {
        vm.expectRevert(IVotingPowerAggregator.InvalidSource.selector);
        votingPowerAggregator.addSnapshotSource(address(xwell));
    }

    function testAddZeroAddressAsSnapshotSourceFails() public {
        vm.expectRevert(IVotingPowerAggregator.InvalidSource.selector);
        votingPowerAggregator.addSnapshotSource(address(0));
    }

    /// ========================================================================
    /// Snapshot Source Management Tests - Remove
    /// ========================================================================

    function testRemoveSnapshotSourceAsOwnerSucceeds() public {
        votingPowerAggregator.addSnapshotSource(address(source1));
        assertTrue(
            votingPowerAggregator.isSnapshotSource(address(source1)),
            "source1 should be added"
        );

        votingPowerAggregator.removeSnapshotSource(address(source1));

        assertFalse(
            votingPowerAggregator.isSnapshotSource(address(source1)),
            "source1 should be removed"
        );
    }

    function testRemoveSnapshotSourceEmitsEvent() public {
        votingPowerAggregator.addSnapshotSource(address(source1));

        vm.expectEmit(true, true, true, true, address(votingPowerAggregator));
        emit SnapshotSourceRemoved(address(source1));

        votingPowerAggregator.removeSnapshotSource(address(source1));
    }

    function testRemoveSnapshotSourceAsNonOwnerFails() public {
        votingPowerAggregator.addSnapshotSource(address(source1));

        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        votingPowerAggregator.removeSnapshotSource(address(source1));
    }

    function testRemoveNonExistentSnapshotSourceFails() public {
        vm.expectRevert(IVotingPowerAggregator.EnumerableSetError.selector);
        votingPowerAggregator.removeSnapshotSource(address(source1));
    }

    function testRemoveAllSnapshotSourcesSucceeds() public {
        votingPowerAggregator.addSnapshotSource(address(source1));
        votingPowerAggregator.addSnapshotSource(address(source2));

        votingPowerAggregator.removeSnapshotSource(address(source1));
        votingPowerAggregator.removeSnapshotSource(address(source2));

        assertFalse(
            votingPowerAggregator.isSnapshotSource(address(source1)),
            "source1 should be removed"
        );
        assertFalse(
            votingPowerAggregator.isSnapshotSource(address(source2)),
            "source2 should be removed"
        );
    }

    /// ========================================================================
    /// Voting Power Calculation Tests - getCurrentVotes
    /// ========================================================================

    function testGetCurrentVotesWithSingleSource() public {
        votingPowerAggregator.addSnapshotSource(address(source1));

        uint256 votingPower = 100_000 * 1e18;
        source1.setCurrentVotes(user1, votingPower);

        uint256 totalVotes = votingPowerAggregator.getCurrentVotes(user1);

        assertEq(
            totalVotes,
            votingPower,
            "total votes should equal source1 votes"
        );
    }

    function testGetCurrentVotesWithMultipleSources() public {
        votingPowerAggregator.addSnapshotSource(address(source1));
        votingPowerAggregator.addSnapshotSource(address(source2));
        votingPowerAggregator.addSnapshotSource(address(source3));

        uint256 votes1 = 100_000 * 1e18;
        uint256 votes2 = 50_000 * 1e18;
        uint256 votes3 = 25_000 * 1e18;

        source1.setCurrentVotes(user1, votes1);
        source2.setCurrentVotes(user1, votes2);
        source3.setCurrentVotes(user1, votes3);

        uint256 totalVotes = votingPowerAggregator.getCurrentVotes(user1);

        assertEq(
            totalVotes,
            votes1 + votes2 + votes3,
            "total votes should be sum of all sources"
        );
    }

    function testGetCurrentVotesWithZeroSources() public {
        uint256 xwellVotes = 75_000 * 1e18;
        xwell.setVotes(user1, xwellVotes);

        uint256 totalVotes = votingPowerAggregator.getCurrentVotes(user1);

        assertEq(
            totalVotes,
            xwellVotes,
            "total votes should equal only xWELL votes"
        );
    }

    function testGetCurrentVotesWithEmptyAccount() public {
        votingPowerAggregator.addSnapshotSource(address(source1));
        votingPowerAggregator.addSnapshotSource(address(source2));

        uint256 totalVotes = votingPowerAggregator.getCurrentVotes(user1);

        assertEq(totalVotes, 0, "total votes should be zero for empty account");
    }

    function testGetCurrentVotesIncludesXWell() public {
        votingPowerAggregator.addSnapshotSource(address(source1));

        uint256 sourceVotes = 100_000 * 1e18;
        uint256 xwellVotes = 50_000 * 1e18;

        source1.setCurrentVotes(user1, sourceVotes);
        xwell.setVotes(user1, xwellVotes);

        uint256 totalVotes = votingPowerAggregator.getCurrentVotes(user1);

        assertEq(
            totalVotes,
            sourceVotes + xwellVotes,
            "total votes should include xWELL votes"
        );
    }

    function testGetCurrentVotesWithOneSourceZeroBalance() public {
        votingPowerAggregator.addSnapshotSource(address(source1));
        votingPowerAggregator.addSnapshotSource(address(source2));

        uint256 votes1 = 100_000 * 1e18;
        uint256 votes2 = 0;

        source1.setCurrentVotes(user1, votes1);
        source2.setCurrentVotes(user1, votes2);

        uint256 totalVotes = votingPowerAggregator.getCurrentVotes(user1);

        assertEq(
            totalVotes,
            votes1,
            "total votes should only include non-zero source"
        );
    }

    function testGetCurrentVotesForMultipleUsers() public {
        votingPowerAggregator.addSnapshotSource(address(source1));

        uint256 user1Votes = 100_000 * 1e18;
        uint256 user2Votes = 200_000 * 1e18;

        source1.setCurrentVotes(user1, user1Votes);
        source1.setCurrentVotes(user2, user2Votes);

        assertEq(
            votingPowerAggregator.getCurrentVotes(user1),
            user1Votes,
            "user1 votes incorrect"
        );
        assertEq(
            votingPowerAggregator.getCurrentVotes(user2),
            user2Votes,
            "user2 votes incorrect"
        );
    }

    /// ========================================================================
    /// Voting Power Calculation Tests - getVotes (Historical)
    /// ========================================================================

    function testGetVotesWithHistoricalTimestamp() public {
        votingPowerAggregator.addSnapshotSource(address(source1));

        uint256 timestamp = 1000;
        uint256 votingPower = 100_000 * 1e18;

        source1.setPriorVotes(user1, timestamp, votingPower);

        uint256 totalVotes = votingPowerAggregator.getVotes(user1, timestamp);

        assertEq(
            totalVotes,
            votingPower,
            "historical votes should match source1"
        );
    }

    function testGetVotesWithMultipleSourcesHistorical() public {
        votingPowerAggregator.addSnapshotSource(address(source1));
        votingPowerAggregator.addSnapshotSource(address(source2));

        uint256 timestamp = 1000;
        uint256 votes1 = 100_000 * 1e18;
        uint256 votes2 = 50_000 * 1e18;

        source1.setPriorVotes(user1, timestamp, votes1);
        source2.setPriorVotes(user1, timestamp, votes2);

        uint256 totalVotes = votingPowerAggregator.getVotes(user1, timestamp);

        assertEq(
            totalVotes,
            votes1 + votes2,
            "historical votes should be sum of sources"
        );
    }

    function testGetVotesIncludesXWellHistorical() public {
        votingPowerAggregator.addSnapshotSource(address(source1));

        uint256 timestamp = 1000;
        uint256 sourceVotes = 100_000 * 1e18;
        uint256 xwellVotes = 50_000 * 1e18;

        source1.setPriorVotes(user1, timestamp, sourceVotes);
        xwell.setPastVotes(user1, timestamp, xwellVotes);

        uint256 totalVotes = votingPowerAggregator.getVotes(user1, timestamp);

        assertEq(
            totalVotes,
            sourceVotes + xwellVotes,
            "historical votes should include xWELL"
        );
    }

    function testGetVotesWithZeroSourcesOnlyXWell() public {
        uint256 timestamp = 1000;
        uint256 xwellVotes = 75_000 * 1e18;

        xwell.setPastVotes(user1, timestamp, xwellVotes);

        uint256 totalVotes = votingPowerAggregator.getVotes(user1, timestamp);

        assertEq(
            totalVotes,
            xwellVotes,
            "votes should only include xWELL when no sources"
        );
    }

    function testGetVotesWithEmptyAccountHistorical() public {
        votingPowerAggregator.addSnapshotSource(address(source1));

        uint256 timestamp = 1000;

        uint256 totalVotes = votingPowerAggregator.getVotes(user1, timestamp);

        assertEq(
            totalVotes,
            0,
            "votes should be zero for account with no history"
        );
    }

    /// ========================================================================
    /// Access Control & Ownership Tests
    /// ========================================================================

    function testOwnerCanTransferOwnership() public {
        votingPowerAggregator.transferOwnership(user1);

        assertEq(
            votingPowerAggregator.owner(),
            user1,
            "ownership should be transferred to user1"
        );
    }

    function testNonOwnerCannotTransferOwnership() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        votingPowerAggregator.transferOwnership(user1);
    }

    function testNewOwnerCanManageSources() public {
        // Transfer ownership
        votingPowerAggregator.transferOwnership(user1);

        // New owner should be able to add sources
        vm.prank(user1);
        votingPowerAggregator.addSnapshotSource(address(source1));

        assertTrue(
            votingPowerAggregator.isSnapshotSource(address(source1)),
            "new owner should be able to add sources"
        );

        // New owner should be able to remove sources
        vm.prank(user1);
        votingPowerAggregator.removeSnapshotSource(address(source1));

        assertFalse(
            votingPowerAggregator.isSnapshotSource(address(source1)),
            "new owner should be able to remove sources"
        );
    }

    function testOldOwnerCannotManageSourcesAfterTransfer() public {
        votingPowerAggregator.transferOwnership(user1);

        // Old owner should not be able to add sources
        vm.expectRevert("Ownable: caller is not the owner");
        votingPowerAggregator.addSnapshotSource(address(source1));
    }

    function testRenounceOwnership() public {
        votingPowerAggregator.renounceOwnership();

        assertEq(
            votingPowerAggregator.owner(),
            address(0),
            "owner should be zero address after renouncing"
        );

        // Should not be able to manage sources after renouncing
        vm.expectRevert("Ownable: caller is not the owner");
        votingPowerAggregator.addSnapshotSource(address(source1));
    }

    /// ========================================================================
    /// Edge Cases & Integration Tests
    /// ========================================================================

    function testIsSnapshotSourceReturnsFalseForNonSource() public view {
        assertFalse(
            votingPowerAggregator.isSnapshotSource(address(source1)),
            "should return false for non-source"
        );
        assertFalse(
            votingPowerAggregator.isSnapshotSource(address(0)),
            "should return false for zero address"
        );
        assertFalse(
            votingPowerAggregator.isSnapshotSource(user1),
            "should return false for random address"
        );
    }

    function testAddAndRemoveSourceMultipleTimes() public {
        // Add source1
        votingPowerAggregator.addSnapshotSource(address(source1));
        assertTrue(
            votingPowerAggregator.isSnapshotSource(address(source1)),
            "source1 should be added"
        );

        // Remove source1
        votingPowerAggregator.removeSnapshotSource(address(source1));
        assertFalse(
            votingPowerAggregator.isSnapshotSource(address(source1)),
            "source1 should be removed"
        );

        // Add source1 again
        votingPowerAggregator.addSnapshotSource(address(source1));
        assertTrue(
            votingPowerAggregator.isSnapshotSource(address(source1)),
            "source1 should be added again"
        );
    }

    function testRemovingAllSourcesLeavesOnlyXWellVotes() public {
        // Add multiple sources
        votingPowerAggregator.addSnapshotSource(address(source1));
        votingPowerAggregator.addSnapshotSource(address(source2));

        // Set voting power
        uint256 sourceVotes = 100_000 * 1e18;
        uint256 xwellVotes = 50_000 * 1e18;

        source1.setCurrentVotes(user1, sourceVotes);
        source2.setCurrentVotes(user1, sourceVotes);
        xwell.setVotes(user1, xwellVotes);

        // Verify total includes all sources
        uint256 totalBefore = votingPowerAggregator.getCurrentVotes(user1);
        assertEq(
            totalBefore,
            sourceVotes + sourceVotes + xwellVotes,
            "should include all sources"
        );

        // Remove all sources
        votingPowerAggregator.removeSnapshotSource(address(source1));
        votingPowerAggregator.removeSnapshotSource(address(source2));

        // Verify only xWELL votes remain
        uint256 totalAfter = votingPowerAggregator.getCurrentVotes(user1);
        assertEq(totalAfter, xwellVotes, "should only have xWELL votes");
    }

    function testWithManySnapshotSources() public {
        // Create and add 10 snapshot sources
        uint256 sourceCount = 10;
        MockSnapshotSource[] memory sources = new MockSnapshotSource[](
            sourceCount
        );

        for (uint256 i = 0; i < sourceCount; i++) {
            sources[i] = new MockSnapshotSource();
            votingPowerAggregator.addSnapshotSource(address(sources[i]));

            // Set votes for each source
            sources[i].setCurrentVotes(user1, 10_000 * 1e18);
        }

        // Verify all sources are added
        for (uint256 i = 0; i < sourceCount; i++) {
            assertTrue(
                votingPowerAggregator.isSnapshotSource(address(sources[i])),
                "all sources should be added"
            );
        }

        // Verify total voting power is aggregated correctly
        uint256 expectedTotal = 10_000 * 1e18 * sourceCount;
        uint256 actualTotal = votingPowerAggregator.getCurrentVotes(user1);

        assertEq(
            actualTotal,
            expectedTotal,
            "should aggregate votes from many sources"
        );
    }

    function testVotingPowerDoesNotChangeAfterRemovingSource() public {
        votingPowerAggregator.addSnapshotSource(address(source1));
        votingPowerAggregator.addSnapshotSource(address(source2));

        uint256 votes1 = 100_000 * 1e18;
        uint256 votes2 = 50_000 * 1e18;

        source1.setCurrentVotes(user1, votes1);
        source2.setCurrentVotes(user1, votes2);

        uint256 totalBefore = votingPowerAggregator.getCurrentVotes(user1);
        assertEq(totalBefore, votes1 + votes2, "initial total incorrect");

        // Remove source2
        votingPowerAggregator.removeSnapshotSource(address(source2));

        uint256 totalAfter = votingPowerAggregator.getCurrentVotes(user1);
        assertEq(totalAfter, votes1, "total should decrease by source2 votes");
    }

    function testGetVotesAndGetCurrentVotesConsistency() public {
        votingPowerAggregator.addSnapshotSource(address(source1));

        uint256 votes = 100_000 * 1e18;
        uint256 xwellVotesCurrent = 50_000 * 1e18;
        uint256 xwellVotesPast = 50_000 * 1e18;

        // Set current votes
        source1.setCurrentVotes(user1, votes);
        xwell.setVotes(user1, xwellVotesCurrent);

        // Set same votes for historical
        uint256 timestamp = 1000;
        source1.setPriorVotes(user1, timestamp, votes);
        xwell.setPastVotes(user1, timestamp, xwellVotesPast);

        uint256 currentVotes = votingPowerAggregator.getCurrentVotes(user1);
        uint256 historicalVotes = votingPowerAggregator.getVotes(
            user1,
            timestamp
        );

        assertEq(
            currentVotes,
            historicalVotes,
            "current and historical votes should match when set to same values"
        );
    }
}
