pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/governance/multichainGovernor/Constants.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MultichainBaseTest} from "@test/helper/MultichainBaseTest.t.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichainGovernor/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@protocol/governance/multichainGovernor/MultichainGovernorDeploy.sol";
import {IMultichainGovernor, MultichainGovernor} from "@protocol/governance/multichainGovernor/MultichainGovernor.sol";
import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";

contract MultichainGovernanceFuzzing is MultichainBaseTest {
    using EnumerableSet for EnumerableSet.AddressSet;

    // @notice max vote amount use for fuzzing, well total supply
    uint256 public totalSupply = 5_000_000_000 * 1e18;

    /// Voting on MultichainGovernor
    function testVotingGovernorMultipleUsersVoting(
        uint256 voteAmount,
        uint8 voters
    ) public returns (uint256 proposalId) {
        voters = uint8(bound(voters, 1, type(uint8).max));
        // vote amount * voters must be less than total supply
        uint256 maxVoteAmount = totalSupply / voters;
        voteAmount = bound(voteAmount, 1e18, maxVoteAmount);

        address[] memory users = new address[](voters);
        for (uint256 i = 0; i < voters; i++) {
            // random pick of token to delegate, can be well, xwell or stkwell
            uint256 random = i % 3;
            address tokenToVote;

            if (random == 0) {
                tokenToVote = address(well);
            } else if (random == 1) {
                tokenToVote = address(xwell);
            } else {
                tokenToVote = address(stkWellMoonbeam);
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

        proposalId = _createProposalUpdateThreshold(address(this));

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

        _assertGovernanceBalance();
    }

    /// Voting on MultichainGovernor with different vote amounts per user
    function testVotingGovernorMultipleUsersVotingVaryingVoutAmount(
        uint8 voters
    ) public returns (uint256 proposalId) {
        voters = uint8(bound(voters, 1, type(uint8).max));
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
                    : address(stkWellMoonbeam);

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

        proposalId = _createProposalUpdateThreshold(address(this));

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

        _assertGovernanceBalance();
    }

    /// Voting on MultichainGovernor
    function testVotingVoteCollectionMultipleUsersVoting(
        uint256 voteAmount,
        uint8 voters
    ) public returns (uint256 proposalId) {
        voters = uint8(bound(voters, 1, type(uint8).max));
        // vote amount * voters must be less than total supply
        uint256 maxVoteAmount = totalSupply / voters;
        voteAmount = bound(voteAmount, 1e18, maxVoteAmount);

        address[] memory users = new address[](voters);
        for (uint256 i = 0; i < voters; i++) {
            // random pick of token to delegate, can be well, xwell or stkwell
            uint256 random = i % 2;
            address tokenToVote = random == 0
                ? address(xwell)
                : address(stkWellBase);

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

        proposalId = _createProposalUpdateThreshold(address(this));

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

        _assertGovernanceBalance();
    }

    /// Voting on MultichainGovernor with different vote amounts per user
    function testVotingVoteCollectionMultipleUsersVotingVaryingVoutAmount(
        uint8 voters
    ) public returns (uint256 proposalId) {
        voters = uint8(bound(voters, 1, type(uint8).max));

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
            uint256 random = i % 2;
            address tokenToVote = random == 0
                ? address(xwell)
                : address(stkWellBase);
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

        proposalId = _createProposalUpdateThreshold(address(this));

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

        _assertGovernanceBalance();
    }

    struct FuzzingInput {
        uint160 user;
        uint256 wellAmount;
        uint256 xwellAmount;
        uint256 stkwellAmount;
        uint256 vestingWellAmount;
        uint8 voteValue;
    }

    // array of users enumerable
    EnumerableSet.AddressSet internal usersSetGovernor;

    function testGovernorVotingMultipleUsersMultipleTokensDifferentVoteValues(
        FuzzingInput[] memory inputs
    ) public {
        // array of vote amounts
        uint256[] memory voteAmounts = new uint256[](inputs.length);
        // array of vote values
        uint8[] memory voteValues = new uint8[](inputs.length);

        // staked well and xwell uses xwell balance
        uint256 totalXWellRemaining = xwell.totalSupply();
        // well and distributor uses well balance
        uint256 totalWellRemaining = well.totalSupply();

        for (uint256 i = 0; i < inputs.length; i++) {
            FuzzingInput memory input = inputs[i];

            input.voteValue = uint8(bound(input.voteValue, 0, 2));

            address userAddress = address(
                uint160(bound(uint256(input.user), 1, type(uint160).max))
            );
            // make sure user is unique
            if (usersSetGovernor.contains(userAddress)) {
                continue;
            }

            // if total xwell remaining is greater than 0, then we can have a
            // range of 1 to total xwell remaining
            input.xwellAmount = bound(
                input.xwellAmount,
                totalXWellRemaining > 0 ? 1 : 0,
                totalXWellRemaining > 0 ? totalXWellRemaining : 0
            );
            // reduce total xwell remaining
            totalXWellRemaining -= input.xwellAmount;

            // if total xwell remaining is greater than 0, then we can have a
            // range of 1 to total xwell remaining
            input.stkwellAmount = bound(
                input.stkwellAmount,
                totalXWellRemaining > 0 ? 1 : 0,
                totalXWellRemaining > 0 ? totalXWellRemaining : 0
            );
            totalXWellRemaining -= input.stkwellAmount;

            // if total well remaining is greater than 0, then we can have a
            // range of 1 to total well remaining
            input.wellAmount = bound(
                input.wellAmount,
                totalWellRemaining > 0 ? 1 : 0,
                totalWellRemaining > 0 ? totalWellRemaining : 0
            );
            totalWellRemaining -= input.wellAmount;

            // if total well remaining is greater than 0, then we can have a
            // range of 1 to total well remaining
            input.vestingWellAmount = bound(
                input.vestingWellAmount,
                totalWellRemaining > 0 ? 1 : 0,
                totalWellRemaining > 0 ? totalWellRemaining : 0
            );
            totalWellRemaining -= input.vestingWellAmount;

            uint256 totalVoteAmount = input.wellAmount +
                input.xwellAmount +
                input.stkwellAmount +
                input.vestingWellAmount;

            // only add to arrays if total vote amount is greater than 0
            if (totalVoteAmount == 0) {
                continue;
            } else {
                usersSetGovernor.add(userAddress);
                uint256 index = usersSetGovernor.length() - 1;
                voteAmounts[index] = totalVoteAmount;
                voteValues[index] = input.voteValue;
            }

            if (input.stkwellAmount > 0) {
                _delegateVoteAmountForUser(
                    address(stkWellMoonbeam),
                    userAddress,
                    input.stkwellAmount
                );
            }
            if (input.wellAmount > 0) {
                _delegateVoteAmountForUser(
                    address(well),
                    userAddress,
                    input.wellAmount
                );
            }
            if (input.xwellAmount > 0) {
                _delegateVoteAmountForUser(
                    address(xwell),
                    userAddress,
                    input.xwellAmount
                );
            }
            if (input.vestingWellAmount > 0) {
                _delegateVoteAmountForUser(
                    address(distributor),
                    userAddress,
                    input.vestingWellAmount
                );
            }

            // check user balance to ensure it's correct
            assertEq(
                xwell.balanceOf(userAddress),
                input.xwellAmount,
                "incorrect xwell balance"
            );

            assertEq(
                stkWellMoonbeam.balanceOf(userAddress),
                input.stkwellAmount,
                "incorrect stkwell balance"
            );

            assertEq(
                well.balanceOf(userAddress),
                input.wellAmount,
                "incorrect well balance"
            );
            assertEq(
                distributor.balanceOf(userAddress),
                input.vestingWellAmount,
                "incorrect distributor balance"
            );
        }

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        uint256 proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        uint256 totalVotes = 0;
        uint256 totalVotesFor = 0;
        uint256 totalVotesAgainst = 0;
        uint256 totalVotesAbstain = 0;

        // loop over users to vote
        for (uint256 i = 0; i < usersSetGovernor.length(); i++) {
            address user = usersSetGovernor.at(i);
            uint8 voteValue = voteValues[i];
            uint256 voteAmount = voteAmounts[i];

            if (voteValue == Constants.VOTE_VALUE_YES) {
                totalVotesFor += voteAmount;
            } else if (voteValue == Constants.VOTE_VALUE_NO) {
                totalVotesAgainst += voteAmount;
            } else {
                totalVotesAbstain += voteAmount;
            }
            totalVotes += voteAmount;

            vm.prank(user);
            governor.castVote(proposalId, voteValue);
            // get votes
            (bool hasVoted, uint8 value, uint256 votes) = governor.getReceipt(
                proposalId,
                user
            );
            assertTrue(hasVoted, "user did not vote");
            assertEq(votes, voteAmount, "incorrect vote amount");
            assertEq(voteValue, value, "incorrect vote value");
        }

        (
            uint256 totalVotesGovernor,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 votesAbstain
        ) = governor.proposalVotes(proposalId);

        assertEq(totalVotesFor, votesFor, "votes for incorrect");
        assertEq(votesAgainst, totalVotesAgainst, "votes against incorrect");
        assertEq(votesAbstain, totalVotesAbstain, "abstain votes incorrect");
        assertEq(totalVotes, totalVotesGovernor, "total votes incorrect");

        _assertGovernanceBalance();
    }

    struct FuzzingInputVoteCollection {
        uint160 user;
        uint256 xwellAmount;
        uint256 stkwellAmount;
        uint8 voteValue;
    }

    // array of users enumerable
    EnumerableSet.AddressSet internal usersSetVoteCollection;

    function testVoteCollectionVotingMultippleUsersMultipleTokensDifferentVoteValues(
        FuzzingInputVoteCollection[] memory inputs
    ) public {
        // array of vote amounts
        uint256[] memory voteAmounts = new uint256[](inputs.length);
        // array of vote values
        uint8[] memory voteValues = new uint8[](inputs.length);

        // staked well and xwell uses xwell balance
        uint256 totalXWellRemaining = xwell.totalSupply();

        for (uint256 i = 0; i < inputs.length; i++) {
            FuzzingInputVoteCollection memory input = inputs[i];

            input.voteValue = uint8(bound(input.voteValue, 0, 2));

            address userAddress = address(
                uint160(bound(uint256(input.user), 1, type(uint160).max))
            );
            // make sure user is unique
            if (usersSetVoteCollection.contains(userAddress)) {
                continue;
            }

            // if total xwell remaining is greater than 0, then we can have a
            // range of 1 to total xwell remaining
            input.xwellAmount = bound(
                input.xwellAmount,
                totalXWellRemaining > 0 ? 1 : 0,
                totalXWellRemaining > 0 ? totalXWellRemaining : 0
            );
            // reduce total xwell remaining
            totalXWellRemaining -= input.xwellAmount;

            // if total xwell remaining is greater than 0, then we can have a
            // range of 1 to total xwell remaining
            input.stkwellAmount = bound(
                input.stkwellAmount,
                totalXWellRemaining > 0 ? 1 : 0,
                totalXWellRemaining > 0 ? totalXWellRemaining : 0
            );
            totalXWellRemaining -= input.stkwellAmount;

            uint256 totalVoteAmount = input.xwellAmount + input.stkwellAmount;

            // only add to arrays if total vote amount is greater than 0
            if (totalVoteAmount == 0) {
                continue;
            } else {
                usersSetVoteCollection.add(userAddress);
                uint256 index = usersSetVoteCollection.length() - 1;
                voteAmounts[index] = totalVoteAmount;
                voteValues[index] = input.voteValue;
            }

            if (input.stkwellAmount > 0) {
                _delegateVoteAmountForUser(
                    address(stkWellBase),
                    userAddress,
                    input.stkwellAmount
                );
            }
            if (input.xwellAmount > 0) {
                _delegateVoteAmountForUser(
                    address(xwell),
                    userAddress,
                    input.xwellAmount
                );
            }
            // check user balance to ensure it's correct
            assertEq(
                xwell.balanceOf(userAddress),
                input.xwellAmount,
                "incorrect xwell balance"
            );

            assertEq(
                stkWellBase.balanceOf(userAddress),
                input.stkwellAmount,
                "incorrect stkwell balance"
            );
        }

        vm.warp(block.timestamp + 1);

        uint256 proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        uint256 totalVotes = 0;
        uint256 totalVotesFor = 0;
        uint256 totalVotesAgainst = 0;
        uint256 totalVotesAbstain = 0;

        // loop over users to vote
        for (uint256 i = 0; i < usersSetVoteCollection.length(); i++) {
            address user = usersSetVoteCollection.at(i);
            uint8 voteValue = voteValues[i];
            uint256 voteAmount = voteAmounts[i];

            if (voteValue == Constants.VOTE_VALUE_YES) {
                totalVotesFor += voteAmount;
            } else if (voteValue == Constants.VOTE_VALUE_NO) {
                totalVotesAgainst += voteAmount;
            } else {
                totalVotesAbstain += voteAmount;
            }
            totalVotes += voteAmount;

            vm.prank(user);
            voteCollection.castVote(proposalId, voteValue);
            // get votes
            (bool hasVoted, uint8 value, uint256 votes) = voteCollection
                .getReceipt(proposalId, user);
            assertTrue(hasVoted, "user did not vote");
            assertEq(votes, voteAmount, "incorrect vote amount");
            assertEq(voteValue, value, "incorrect vote value");
        }

        (
            uint256 totalVotesGovernor,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 votesAbstain
        ) = voteCollection.proposalVotes(proposalId);

        assertEq(totalVotesFor, votesFor, "votes for incorrect");
        assertEq(votesAgainst, totalVotesAgainst, "votes against incorrect");
        assertEq(votesAbstain, totalVotesAbstain, "abstain votes incorrect");
        assertEq(totalVotes, totalVotesGovernor, "total votes incorrect");

        _assertGovernanceBalance();
    }
}
