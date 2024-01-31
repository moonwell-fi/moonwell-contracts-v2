pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/Governance/MultichainGovernor/Constants.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MultichainBaseTest} from "@test/helper/MultichainBaseTest.t.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {IMultichainGovernor, MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";

contract MultichainGovernanceFuzzing is MultichainBaseTest {
    // @notice max vote amount use for fuzzing, well total supply
    uint256 public totalSupply = 5_000_000_000 * 1e18;

    /// Voting on MultichainGovernor
    function testVotingGovernorMultipleUsersVoting(
        uint256 voteAmount,
        uint8 voters
    ) public returns (uint256 proposalId) {
        vm.assume(voters > 0);
        // vote amount * voters must be less than total supply
        uint256 maxVoteAmount = totalSupply / voters;
        voteAmount = bound(voteAmount, 1e18, maxVoteAmount);

        address[] memory users = new address[](voters);
        for (uint256 i = 0; i < voters; i++) {
            // random pick of token to delegate, can be well, xwell or stkwell
            uint256 random = i % 3;
            address tokenToVote;
            tokenToVote = address(xwell);

            if (random == 0) {
                tokenToVote = address(well);
            } else if (random == 1) {
                tokenToVote = address(xwell);
            } else {
                tokenToVote = address(stkWell);
            }

            address user = address(uint160(i + 1));
            users[i] = user;

            _delegateVoteAmountForUser(tokenToVote, user, voteAmount);
        }

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // check vote amount for users
        for (uint256 i = 0; i < voters; i++) {
            assertEq(
                governor.getVotes(
                    users[i],
                    block.timestamp - 1,
                    block.number - 1
                ),
                voteAmount,
                "incorrect vote amount"
            );
        }

        proposalId = _createProposalUpdateThreshold();

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        for (uint256 i = 0; i < voters; i++) {
            address user = users[i];
            vm.prank(user);
            governor.castVote(proposalId, Constants.VOTE_VALUE_YES);
            (bool hasVoted, , ) = governor.getReceipt(proposalId, user);
            assertTrue(hasVoted, "user did not vote");
        }

        (
            uint256 totalVotes,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 votesAbstain
        ) = governor.proposalVotes(proposalId);

        assertEq(votesFor, voteAmount * voters, "votes for incorrect");
        assertEq(votesAgainst, 0, "votes against incorrect");
        assertEq(votesAbstain, 0, "abstain votes incorrect");
        assertEq(votesFor, totalVotes, "total votes incorrect");
    }

    /// Voting on MultichainGovernor with different vote amounts per user
    function testVotingGovernorMultipleUsersVotingVaryingVoutAmount(
        uint8 voters
    ) public returns (uint256 proposalId) {
        vm.assume(voters > 0);

        address[] memory users = new address[](voters);
        uint256[] memory voteAmounts = new uint256[](voters);
        uint256 totalVoteAmount = 0;
        uint256 maxVoteAmount = totalSupply / voters;

        for (uint256 i = 0; i < voters; i++) {
            // Assigning a random vote amount for each user, ensuring it's at least 1e18
            uint256 voteAmount = (uint256(
                uint160(uint256(keccak256(abi.encode(i, block.timestamp))))
            ) * 1e18) % maxVoteAmount;

            voteAmounts[i] = voteAmount;
            totalVoteAmount += voteAmount;

            // Ensure the total vote amount does not exceed total supply
            require(
                totalVoteAmount <= totalSupply,
                "Total vote amount exceeds total supply"
            );

            // random pick of token to delegate
            uint256 random = i % 3;
            address tokenToVote = random == 0
                ? address(well)
                : random == 1
                    ? address(xwell)
                    : address(stkWell);

            address user = address(uint160(i + 1));
            users[i] = user;

            _delegateVoteAmountForUser(tokenToVote, user, voteAmount);
        }

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // Check vote amount for users
        for (uint256 i = 0; i < voters; i++) {
            assertEq(
                governor.getVotes(
                    users[i],
                    block.timestamp - 1,
                    block.number - 1
                ),
                voteAmounts[i],
                "Incorrect vote amount for user"
            );
        }

        proposalId = _createProposalUpdateThreshold();

        vm.warp(block.timestamp + 1);
        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "Incorrect state, not active"
        );

        for (uint256 i = 0; i < voters; i++) {
            address user = users[i];
            vm.prank(user);
            governor.castVote(proposalId, Constants.VOTE_VALUE_YES);
            (bool hasVoted, , ) = governor.getReceipt(proposalId, user);
            assertTrue(hasVoted, "User did not vote");
        }

        // Checking the vote counts
        (uint256 totalVotes, uint256 votesFor, , ) = governor.proposalVotes(
            proposalId
        );

        assertEq(votesFor, totalVoteAmount, "Votes for incorrect");
        assertEq(totalVotes, totalVoteAmount, "Total votes incorrect");
    }

    /// Voting on MultichainGovernor
    function testVotingVoteCollectionMultipleUsersVoting(
        uint256 voteAmount,
        uint8 voters
    ) public returns (uint256 proposalId) {
        vm.assume(voters > 0);
        // vote amount * voters must be less than total supply
        uint256 maxVoteAmount = totalSupply / voters;
        voteAmount = bound(voteAmount, 1e18, maxVoteAmount);

        address[] memory users = new address[](voters);
        for (uint256 i = 0; i < voters; i++) {
            // random pick of token to delegate, can be well, xwell or stkwell
            uint256 random = i % 3;
            address tokenToVote;
            tokenToVote = address(xwell);

            if (random == 0) {
                tokenToVote = address(well);
            } else if (random == 1) {
                tokenToVote = address(xwell);
            } else {
                tokenToVote = address(stkWell);
            }

            address user = address(uint160(i + 1));
            users[i] = user;

            _delegateVoteAmountForUser(tokenToVote, user, voteAmount);
        }

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // check vote amount for users
        for (uint256 i = 0; i < voters; i++) {
            assertEq(
                voteCollection.getVotes(users[i], block.timestamp - 1),
                voteAmount,
                "incorrect vote amount"
            );
        }

        proposalId = _createProposalUpdateThreshold();

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        for (uint256 i = 0; i < voters; i++) {
            address user = users[i];
            vm.prank(user);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);
            (bool hasVoted, , ) = voteCollection.getReceipt(proposalId, user);
            assertTrue(hasVoted, "user did not vote");
        }

        (
            uint256 totalVotes,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 votesAbstain
        ) = voteCollection.proposalVotes(proposalId);

        assertEq(votesFor, voteAmount * voters, "votes for incorrect");
        assertEq(votesAgainst, 0, "votes against incorrect");
        assertEq(votesAbstain, 0, "abstain votes incorrect");
        assertEq(votesFor, totalVotes, "total votes incorrect");
    }

    /// Voting on MultichainGovernor with different vote amounts per user
    function testVotingVoteCollectionMultipleUsersVotingVaryingVoutAmount(
        uint8 voters
    ) public returns (uint256 proposalId) {
        vm.assume(voters > 0);

        address[] memory users = new address[](voters);
        uint256[] memory voteAmounts = new uint256[](voters);
        uint256 totalVoteAmount = 0;
        uint256 maxVoteAmount = totalSupply / voters;

        for (uint256 i = 0; i < voters; i++) {
            // Assigning a random vote amount for each user, ensuring it's at least 1e18
            uint256 voteAmount = (uint256(
                uint160(uint256(keccak256(abi.encode(i, block.timestamp))))
            ) * 1e18) % maxVoteAmount;

            voteAmounts[i] = voteAmount;
            totalVoteAmount += voteAmount;

            // Ensure the total vote amount does not exceed total supply
            require(
                totalVoteAmount <= totalSupply,
                "Total vote amount exceeds total supply"
            );

            // random pick of token to delegate
            uint256 random = i % 3;
            address tokenToVote = random == 0
                ? address(xwell)
                : address(stkWell);
            address user = address(uint160(i + 1));
            users[i] = user;

            _delegateVoteAmountForUser(tokenToVote, user, voteAmount);
        }

        vm.warp(block.timestamp + 1);

        // Check vote amount for users
        for (uint256 i = 0; i < voters; i++) {
            assertEq(
                voteCollection.getVotes(users[i], block.timestamp - 1),
                voteAmounts[i],
                "Incorrect vote amount for user"
            );
        }

        proposalId = _createProposalUpdateThreshold();

        vm.warp(block.timestamp + 1);
        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "Incorrect state, not active"
        );

        for (uint256 i = 0; i < voters; i++) {
            address user = users[i];
            vm.prank(user);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);
            (bool hasVoted, , ) = voteCollection.getReceipt(proposalId, user);
            assertTrue(hasVoted, "User did not vote");
        }

        // Checking the vote counts
        (uint256 totalVotes, uint256 votesFor, , ) = voteCollection
            .proposalVotes(proposalId);

        assertEq(votesFor, totalVoteAmount, "Votes for incorrect");
        assertEq(totalVotes, totalVoteAmount, "Total votes incorrect");
    }

    // token can be xWELL, WELL or stkWELL
    function _delegateVoteAmountForUser(
        address token,
        address user,
        uint256 voteAmount
    ) internal {
        if (token != address(stkWell)) {
            deal(token, user, voteAmount);

            // users xWell interface but this can also be well
            vm.prank(user);
            xWELL(token).delegate(user);
        } else {
            deal(address(xwell), user, voteAmount);
            vm.startPrank(user);
            xwell.approve(address(stkWell), voteAmount);
            stkWell.stake(user, voteAmount);
            vm.stopPrank();
        }
    }
}
