pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@test/helper/BaseTest.t.sol";

import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {MockTimestampGovernor} from "@test/mock/MockTimestampGovernor.sol";

/// test the xWELL vote functionality on the xWELLProxy contract
contract xWELLVoteUnitTest is BaseTest {
    MockTimestampGovernor public governor;
    Timelock public timelock;
    uint256 constant delay = 1 days;
    uint256 constant guardianSunset = 730 days;

    function setUp() public override {
        super.setUp();
        timelock = new Timelock(address(this), delay);
        governor = new MockTimestampGovernor(
            address(timelock),
            address(xwellProxy),
            address(0),
            address(0),
            address(0),
            guardianSunset
        );

        vm.warp(block.timestamp + 1000000);
    }

    function testFetchVotesCurrentTimestampFails() public {
        vm.expectRevert("ERC20Votes: future lookup");
        xwellProxy.getPastVotes(address(this), block.timestamp);
    }

    function testFetchVotesFutureTimestampFails() public {
        vm.expectRevert("ERC20Votes: future lookup");
        xwellProxy.getPastVotes(address(this), block.timestamp + 1);
    }

    function testTransferRemovesDelegation() public {
        uint112 mintAmount = 100_000 * 1e18;
        _lockboxCanMint(mintAmount);

        uint256 delegateTime = block.timestamp;
        xwellProxy.delegate(address(this));

        assertEq(
            xwellProxy.delegates(address(this)),
            address(this),
            "Incorrect delegate"
        );

        vm.warp(block.timestamp + 1); /// avoid future lookup error

        assertEq(
            xwellProxy.getPastVotes(address(this), delegateTime),
            mintAmount,
            "Incorrect past votes"
        );

        xwellProxy.transfer(address(1), xwellProxy.balanceOf(address(this)));
        vm.warp(block.timestamp + 1); /// avoid future lookup error

        assertEq(
            xwellProxy.getPastVotes(address(this), block.timestamp - 1),
            0,
            "Incorrect past votes"
        );

        assertEq(
            xwellProxy.delegates(address(this)),
            address(this),
            "Incorrect delegate"
        );
        assertEq(
            xwellProxy.balanceOf(address(this)),
            0,
            "Incorrect balance this"
        );
        assertEq(
            xwellProxy.balanceOf(address(1)),
            mintAmount,
            "Incorrect balance 1"
        );
    }

    function testSelfDelegatesSuccess() public {
        uint112 mintAmount = 100_000 * 1e18;
        _lockboxCanMint(mintAmount);

        assertEq(
            xwellProxy.getPastVotes(address(this), block.timestamp - 1),
            0,
            "Incorrect vote count before delegation"
        );

        uint256 delegateTime = block.timestamp;
        xwellProxy.delegate(address(this));

        assertEq(
            xwellProxy.delegates(address(this)),
            address(this),
            "Incorrect delegate"
        );

        vm.warp(block.timestamp + 1); /// avoid future lookup error

        assertEq(
            xwellProxy.getPastVotes(address(this), delegateTime - 1),
            0,
            "Incorrect vote count after delegation at delegate time - 1"
        );
        assertEq(
            xwellProxy.getPastVotes(address(this), delegateTime),
            mintAmount,
            "Incorrect past votes"
        );

        vm.warp(block.timestamp + 1000000);
        assertEq(
            xwellProxy.getPastVotes(address(this), delegateTime + 1),
            mintAmount,
            "Incorrect past votes"
        );
    }

    function testProposeSucceedsWithSelfDelegation() public {
        uint112 quorum = uint112(governor.quorumVotes());

        _lockboxCanMint(quorum);

        xwellProxy.delegate(address(this));

        assertEq(
            xwellProxy.delegates(address(this)),
            address(this),
            "Incorrect delegate"
        );

        vm.warp(block.timestamp + 1); /// avoid future lookup error

        vm.prank(address(timelock));
        timelock.setPendingAdmin(address(governor));

        vm.prank(address(governor));
        timelock.acceptAdmin();

        uint256 newDelay = 15 days;

        address[] memory targets = new address[](1);
        targets[0] = address(timelock);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setDelay(uint256)", newDelay);

        uint256 proposalId = governor.propose(
            targets,
            values,
            new string[](1),
            calldatas,
            "Accept timelock admin"
        );

        governor.castVote(proposalId, 0);

        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        governor.queue(proposalId);
        vm.warp(block.timestamp + delay + 1);

        governor.execute(proposalId);

        assertEq(
            timelock.delay(),
            newDelay,
            "Timelock delay not set correctly"
        );
        assertEq(
            timelock.admin(),
            address(governor),
            "Timelock admin not set correctly"
        );

        assertEq(
            timelock.pendingAdmin(),
            address(0),
            "Timelock pending admin not set correctly"
        );
    }

    function testDelegateReceivesAdditionalVotesAfterMint() public {
        uint112 quorum = uint112(governor.quorumVotes());

        _lockboxCanMint(quorum);

        uint256 delegateTime = block.timestamp;
        xwellProxy.delegate(address(this));

        vm.warp(block.timestamp + 1); /// avoid future lookup error

        assertEq(
            xwellProxy.getPastVotes(address(this), delegateTime),
            quorum,
            "Incorrect past votes"
        );
        assertEq(
            xwellProxy.getVotes(address(this)),
            quorum,
            "Incorrect current votes"
        );

        uint256 additionalMint = 100_000 * 1e18;

        _lockboxCanMint(uint112(additionalMint));

        assertEq(
            xwellProxy.getVotes(address(this)),
            xwellProxy.balanceOf(address(this)),
            "Incorrect current votes"
        );

        vm.warp(block.timestamp + 1); /// avoid future lookup error

        delegateTime++;

        assertEq(
            xwellProxy.getPastVotes(address(this), delegateTime),
            quorum + additionalMint,
            "Incorrect past votes"
        );
        assertEq(
            xwellProxy.getPastVotes(address(this), delegateTime),
            xwellProxy.balanceOf(address(this)),
            "Incorrect past votes when compared to balance"
        );
    }
}
