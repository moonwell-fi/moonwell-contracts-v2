pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/governance/multichain/Constants.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MultichainBaseTestV2} from "@test/helper/MultichainBaseTestV2.t.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@script/DeployMultichainGovernor.s.sol";
import {IMultichainGovernorV2, MultichainGovernorV2} from "@protocol/governance/multichain/MultichainGovernorV2.sol";
import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";

contract MultichainGovernanceFuzzingV2 is MultichainBaseTestV2 {
    using EnumerableSet for EnumerableSet.AddressSet;

    // @notice max vote amount use for fuzzing
    // Note: In setUp(), 5B xWELL is minted, but 2B is staked (1B in stkWellMoonbeam, 1B in stkWellBase)
    // This leaves 3B xWELL available for distribution
    // For WELL tokens, the full supply is available since nothing is pre-allocated
    uint256 public totalSupply = 5_000_000_000 * 1e18;
    uint256 public availableXWellSupply = 3_000_000_000 * 1e18; // 3B xWELL available after staking
    uint256 public availableWellSupply = type(uint256).max; // WELL has no pre-allocation

    /// Voting on MultichainGovernorV2
    function testVotingGovernorMultipleUsersVoting(
        uint256 voteAmount,
        uint8 voters
    ) public returns (uint256 proposalId) {
        voters = uint8(bound(voters, 1, type(uint8).max));

        // Simplified: just ensure we have reasonable values
        // Each user needs at least 1e18, and we need at least 1 voter
        voteAmount = bound(voteAmount, 1e18, availableXWellSupply / 2); // Be conservative, use half available supply

        uint256 totalXWellUsed = 0;
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

            // Check if we have enough xWELL for xwell-based tokens
            if (random != 0) {
                // xwell or stkwell
                // Check for sufficient xWELL without causing underflow
                // Short-circuit evaluation: first check prevents underflow in second check
                if (
                    totalXWellUsed >= availableXWellSupply ||
                    voteAmount > (availableXWellSupply - totalXWellUsed)
                ) {
                    // Not enough xWELL remaining, skip the rest
                    voters = uint8(i);
                    break;
                }
                totalXWellUsed += voteAmount;
            }

            address user = address(uint160(i + 1));

            // Skip protected contract addresses that cannot receive token transfers
            if (
                user == address(xwell) ||
                user == address(well) ||
                user == address(distributor) ||
                user == address(stkWellMoonbeam) ||
                user == address(stkWellBase) ||
                user == address(governor) ||
                user == address(voteCollection) ||
                user == address(votingPowerAggregator) ||
                user == proxyAdmin ||
                user == xwellProxyAdmin
            ) {
                // Skip this voter and reduce the count
                voters = uint8(i);
                break;
            }

            users[i] = user;

            _delegateVoteAmountForUser(tokenToVote, user, voteAmount);
        }

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // check vote amount for users - V2: use votingPowerAggregator
        for (uint256 i = 0; i < voters; i++) {
            assertEq(
                votingPowerAggregator.getVotes(users[i], block.timestamp - 1),
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

    /// Voting on MultichainGovernorV2 with different vote amounts per user
    function testVotingGovernorMultipleUsersVotingVaryingVoutAmount(
        uint8 voters
    ) public returns (uint256 proposalId) {
        voters = uint8(bound(voters, 1, type(uint8).max));
        address[] memory users = new address[](voters);
        uint256[] memory voteAmounts = new uint256[](voters);
        uint256 totalVoteAmount = 0;

        // Track xWELL and WELL usage separately since they both have limited supply
        uint256 totalXWellUsed = 0;
        uint256 totalWellUsed = 0;
        uint256 availableWellBalance = well.balanceOf(address(this));

        // Use conservative max to avoid running out
        uint256 maxVoteAmount = availableXWellSupply / 2;

        for (uint256 i = 0; i < voters; i++) {
            // random pick of token to delegate
            uint256 random = i % 3;
            address tokenToVote = random == 0
                ? address(well)
                : random == 1
                    ? address(xwell)
                    : address(stkWellMoonbeam);

            bool isXWellBased = random != 0; // xwell or stkwell
            bool isWellBased = random == 0; // well or distributor

            // Assigning a random vote amount for each user, ensuring it's at least 1e18
            uint256 voteAmount = (uint256(
                uint160(uint256(keccak256(abi.encode(i, block.timestamp))))
            ) * 1e18) % maxVoteAmount;

            // Ensure minimum vote amount
            if (voteAmount < 1e18) voteAmount = 1e18;

            // Ensure we don't exceed token supply
            if (isXWellBased) {
                // Check for sufficient xWELL without causing underflow
                if (
                    totalXWellUsed >= availableXWellSupply ||
                    voteAmount > (availableXWellSupply - totalXWellUsed)
                ) {
                    // Not enough xWELL, skip this user
                    voteAmounts[i] = 0;
                    users[i] = address(uint160(i + 1));
                    continue;
                }
                totalXWellUsed += voteAmount;
            } else if (isWellBased) {
                // Check for sufficient WELL
                if (
                    totalWellUsed >= availableWellBalance ||
                    voteAmount > (availableWellBalance - totalWellUsed)
                ) {
                    // Not enough WELL, skip this user
                    voteAmounts[i] = 0;
                    users[i] = address(uint160(i + 1));
                    continue;
                }
                totalWellUsed += voteAmount;
            }

            voteAmounts[i] = voteAmount;
            totalVoteAmount += voteAmount;

            address user = address(uint160(i + 1));

            // Skip protected contract addresses that cannot receive token transfers
            if (
                user == address(xwell) ||
                user == address(well) ||
                user == address(distributor) ||
                user == address(stkWellMoonbeam) ||
                user == address(stkWellBase) ||
                user == address(governor) ||
                user == address(voteCollection) ||
                user == address(votingPowerAggregator) ||
                user == proxyAdmin ||
                user == xwellProxyAdmin
            ) {
                // Mark this user as skipped
                voteAmounts[i] = 0;
                users[i] = user;
                totalVoteAmount -= voteAmount;
                continue;
            }

            users[i] = user;

            _delegateVoteAmountForUser(tokenToVote, user, voteAmount);
        }

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // Check vote amount for users - V2: use votingPowerAggregator
        for (uint256 i = 0; i < voters; i++) {
            // Skip users with 0 vote amount (those who were skipped due to insufficient xWELL)
            if (voteAmounts[i] == 0) continue;

            assertEq(
                votingPowerAggregator.getVotes(users[i], block.timestamp - 1),
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
            // Skip users with 0 vote amount
            if (voteAmounts[i] == 0) continue;

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

    /// Voting on MultichainGovernorV2
    function testVotingVoteCollectionMultipleUsersVoting(
        uint256 voteAmount,
        uint8 voters
    ) public returns (uint256 proposalId) {
        voters = uint8(bound(voters, 1, type(uint8).max));
        // vote amount * voters must be less than available xWELL supply
        // (both xwell and stkWellBase use xWELL tokens)
        // Be conservative and use half the available supply
        voteAmount = bound(voteAmount, 1e18, availableXWellSupply / 2);

        uint256 totalXWellUsed = 0;

        address[] memory users = new address[](voters);
        for (uint256 i = 0; i < voters; i++) {
            // random pick of token to delegate, can be well, xwell or stkwell
            uint256 random = i % 2;
            address tokenToVote = random == 0
                ? address(xwell)
                : address(stkWellBase);

            // Check for sufficient xWELL (both tokens use xWELL)
            if (
                totalXWellUsed >= availableXWellSupply ||
                voteAmount > (availableXWellSupply - totalXWellUsed)
            ) {
                // Not enough xWELL remaining, skip the rest
                voters = uint8(i);
                break;
            }
            totalXWellUsed += voteAmount;

            address user = address(uint160(i + 1));

            // Skip protected contract addresses that cannot receive token transfers
            if (
                user == address(xwell) ||
                user == address(well) ||
                user == address(distributor) ||
                user == address(stkWellMoonbeam) ||
                user == address(stkWellBase) ||
                user == address(governor) ||
                user == address(voteCollection) ||
                user == address(votingPowerAggregator) ||
                user == proxyAdmin ||
                user == xwellProxyAdmin
            ) {
                // Skip this voter and reduce the count
                voters = uint8(i);
                break;
            }

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

    /// Voting on MultichainGovernorV2 with different vote amounts per user
    function testVotingVoteCollectionMultipleUsersVotingVaryingVoutAmount(
        uint8 voters
    ) public returns (uint256 proposalId) {
        voters = uint8(bound(voters, 1, type(uint8).max));

        address[] memory users = new address[](voters);
        uint256[] memory voteAmounts = new uint256[](voters);
        uint256 totalVoteAmount = 0;
        uint256 totalXWellUsed = 0;

        // All voters use xWELL-based tokens (xwell or stkWellBase)
        // Be conservative to avoid running out
        uint256 maxVoteAmount = availableXWellSupply / 2;

        for (uint256 i = 0; i < voters; i++) {
            // Assigning a random vote amount for each user, ensuring it's at least 1e18
            uint256 voteAmount = (uint256(
                uint160(uint256(keccak256(abi.encode(i, block.timestamp))))
            ) * 1e18) % maxVoteAmount;

            // Ensure minimum vote amount
            if (voteAmount < 1e18) voteAmount = 1e18;

            // Check for sufficient xWELL
            if (
                totalXWellUsed >= availableXWellSupply ||
                voteAmount > (availableXWellSupply - totalXWellUsed)
            ) {
                // Not enough xWELL, skip this user
                voteAmounts[i] = 0;
                users[i] = address(uint160(i + 1));
                continue;
            }

            voteAmounts[i] = voteAmount;
            totalVoteAmount += voteAmount;
            totalXWellUsed += voteAmount;

            // random pick of token to delegate
            uint256 random = i % 2;
            address tokenToVote = random == 0
                ? address(xwell)
                : address(stkWellBase);
            address user = address(uint160(i + 1));

            // Skip protected contract addresses that cannot receive token transfers
            if (
                user == address(xwell) ||
                user == address(well) ||
                user == address(distributor) ||
                user == address(stkWellMoonbeam) ||
                user == address(stkWellBase) ||
                user == address(governor) ||
                user == address(voteCollection) ||
                user == address(votingPowerAggregator) ||
                user == proxyAdmin ||
                user == xwellProxyAdmin
            ) {
                // Mark this user as skipped
                voteAmounts[i] = 0;
                users[i] = user;
                totalVoteAmount -= voteAmount;
                totalXWellUsed -= voteAmount;
                continue;
            }

            users[i] = user;

            _delegateVoteAmountForUser(tokenToVote, user, voteAmount);
        }

        vm.warp(block.timestamp + 1);

        // Check vote amount for users
        for (uint256 i = 0; i < voters; i++) {
            // Skip users with 0 vote amount
            if (voteAmounts[i] == 0) continue;

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
            // Skip users with 0 vote amount
            if (voteAmounts[i] == 0) continue;

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
}
