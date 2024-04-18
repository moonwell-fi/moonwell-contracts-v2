// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "@forge-std/Test.sol";

import {ERC20Votes} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {MToken} from "@protocol/MToken.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {Constants} from "@protocol/governance/multichain/Constants.sol";
import {CreateCode} from "@proposals/utils/CreateCode.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {IStakedWellUplift} from "@protocol/stkWell/IStakedWellUplift.sol";
import {MockVoteCollection} from "@test/mock/MockVoteCollection.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {MockMultichainGovernor} from "@test/mock/MockMultichainGovernor.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {TestMultichainProposals} from "@protocol/proposals/TestMultichainProposals.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {ITemporalGovernor, TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {IEcosystemReserveUplift, IEcosystemReserveControllerUplift} from "@protocol/stkWell/IEcosystemReserveUplift.sol";
import {TokenSaleDistributorInterfaceV1} from "@protocol/views/TokenSaleDistributorInterfaceV1.sol";

import {mipm23c} from "@proposals/mips/mip-m23/mip-m23c.sol";

import {ITimelock as Timelock} from "@protocol/interfaces/ITimelock.sol";

/// @notice run this on a chainforked moonbeam node.
/// then switch over to base network to generate the calldata,
/// then switch back to moonbeam to run the test with the generated calldata

/*
if the tests fail, try setting the environment variables as follows:

export DO_DEPLOY=true
export DO_AFTER_DEPLOY=true
export DO_AFTER_DEPLOY_SETUP=true
export DO_BUILD=true
export DO_RUN=true
export DO_TEARDOWN=true
export DO_VALIDATE=true

*/
contract MultichainProposalTest is
    Test,
    ChainIds,
    CreateCode,
    TestMultichainProposals
{
    MultichainVoteCollection public voteCollection;
    MultichainGovernor public governor;
    IWormhole public wormhole;
    Timelock public timelock;
    ERC20Votes public well;
    xWELL public xwell;
    IStakedWell public stakedWellMoonbeam;
    IStakedWell public stakedWellBase;
    TokenSaleDistributorInterfaceV1 public distributor;

    event ProposalCreated(
        uint256 proposalId,
        uint256 votingStartTime,
        uint256 votingEndTime,
        uint256 votingCollectionEndTime
    );

    event LogMessagePublished(
        address indexed sender,
        uint64 sequence,
        uint32 nonce,
        bytes payload,
        uint8 consistencyLevel
    );

    event VotesEmitted(
        uint256 proposalId,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes
    );

    address public constant voter = address(100_000_000);

    mipm23c public proposalC;

    TemporalGovernor public temporalGov;

    WormholeRelayerAdapter public wormholeRelayerAdapterMoonbeam;

    WormholeRelayerAdapter wormholeRelayerAdapterBase;

    string public constant DEFAULT_BASE_RPC_URL = "https://mainnet.base.org";

    /// @notice fork ID for base
    uint256 public baseForkId =
        vm.createFork(vm.envOr("BASE_RPC_URL", DEFAULT_BASE_RPC_URL));

    string public constant DEFAULT_MOONBEAM_RPC_URL =
        "https://rpc.api.moonbeam.network";

    /// @notice fork ID for moonbeam
    uint256 public moonbeamForkId =
        vm.createFork(vm.envOr("MOONBEAM_RPC_URL", DEFAULT_MOONBEAM_RPC_URL));

    function setUp() public override {
        super.setUp();

        vm.selectFork(moonbeamForkId);

        proposalC = new mipm23c();
        proposalC.buildCalldata(addresses);

        /// load proposals up into the TestMultichainProposal contract
        _initialize(new address[](0));

        runProposals(false, true, true, true, true, true, true, true);

        voteCollection = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY", baseChainId)
        );
        wormhole = IWormhole(
            addresses.getAddress("WORMHOLE_CORE_MOONBEAM", moonBeamChainId)
        );

        well = ERC20Votes(addresses.getAddress("WELL", moonBeamChainId));
        xwell = xWELL(addresses.getAddress("xWELL_PROXY", moonBeamChainId));
        // make xwell persistent so votes are valid on both chains
        vm.makePersistent(address(xwell));

        stakedWellMoonbeam = IStakedWell(
            addresses.getAddress("stkWELL_PROXY", moonBeamChainId)
        );

        distributor = TokenSaleDistributorInterfaceV1(
            addresses.getAddress(
                "TOKEN_SALE_DISTRIBUTOR_PROXY",
                moonBeamChainId
            )
        );

        timelock = Timelock(
            addresses.getAddress("MOONBEAM_TIMELOCK", moonBeamChainId)
        );
        governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY", moonBeamChainId)
        );

        // make governor persistent so we can call receiveWormholeMessage on
        // governor from base
        vm.makePersistent(address(governor));
        {
            vm.selectFork(moonbeamForkId);

            wormholeRelayerAdapterMoonbeam = new WormholeRelayerAdapter();

            vm.store(
                address(governor),
                keccak256(abi.encodePacked(uint256(103))),
                bytes32(
                    uint256(uint160(address(wormholeRelayerAdapterMoonbeam)))
                )
            );

            vm.makePersistent(address(wormholeRelayerAdapterMoonbeam));
        }

        {
            vm.selectFork(baseForkId);

            assertEq(
                address(voteCollection.wormholeRelayer()),
                addresses.getAddress("WORMHOLE_BRIDGE_RELAYER"),
                "incorrect wormhole relayer"
            );

            wormholeRelayerAdapterBase = new WormholeRelayerAdapter();

            uint256 oldGasLimit = voteCollection.gasLimit();
            // encode gasLimit and relayer address since is stored in a single slot
            // relayer is first due to how evm pack values into a single storage
            bytes32 encodedData = bytes32(
                (uint256(uint160(address(wormholeRelayerAdapterBase))) << 96) |
                    uint256(oldGasLimit)
            );

            vm.store(address(voteCollection), bytes32(uint256(0)), encodedData);

            vm.makePersistent(address(wormholeRelayerAdapterBase));

            assertEq(
                address(voteCollection.wormholeRelayer()),
                address(wormholeRelayerAdapterBase),
                "incorrect wormhole relayer"
            );
            assertEq(
                voteCollection.gasLimit(),
                oldGasLimit,
                "incorrect gas limit vote collection"
            );

            stakedWellBase = IStakedWell(addresses.getAddress("stkWELL_PROXY"));
        }
    }

    function testSetup() public {
        vm.selectFork(baseForkId);
        voteCollection = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        );

        assertEq(
            voteCollection.gasLimit(),
            Constants.MIN_GAS_LIMIT,
            "incorrect gas limit vote collection"
        );
        assertEq(
            address(voteCollection.xWell()),
            addresses.getAddress("xWELL_PROXY"),
            "incorrect xWELL contract"
        );
        assertEq(
            address(voteCollection.stkWell()),
            addresses.getAddress("stkWELL_PROXY"),
            "incorrect xWELL contract"
        );

        temporalGov = TemporalGovernor(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );
        /// artemis timelock does not start off as trusted sender
        assertFalse(
            temporalGov.isTrustedSender(
                moonBeamWormholeChainId,
                addresses.getAddress(
                    "MOONBEAM_TIMELOCK",
                    sendingChainIdToReceivingChainId[block.chainid]
                )
            ),
            "artemis timelock should not be trusted sender"
        );
        assertTrue(
            temporalGov.isTrustedSender(
                moonBeamWormholeChainId,
                addresses.getAddress(
                    "MULTICHAIN_GOVERNOR_PROXY",
                    sendingChainIdToReceivingChainId[block.chainid]
                )
            ),
            "multichain governor should be trusted sender"
        );

        assertEq(
            temporalGov.allTrustedSenders(moonBeamWormholeChainId).length,
            1,
            "incorrect amount of trusted senders post proposal"
        );
    }

    function testNoBaseWormholeCoreAddressInProposal() public {
        address wormholeBase = addresses.getAddress(
            "WORMHOLE_CORE_BASE",
            baseChainId
        );
        vm.selectFork(moonbeamForkId);
        uint256[] memory proposals = governor.liveProposals();
        for (uint256 i = 0; i < proposals.length; i++) {
            if (proposals[i] == 4) {
                continue;
            }

            (address[] memory targets, , ) = governor.getProposalData(
                proposals[i]
            );

            for (uint256 j = 0; j < targets.length; j++) {
                require(
                    targets[j] != wormholeBase,
                    "targeted wormhole core base address on moonbeam"
                );
            }
        }
    }

    function testGetAllMarketConfigs() public {
        MultiRewardDistributor mrd = MultiRewardDistributor(
            addresses.getAddress("MRD_PROXY")
        );

        assertEq(
            mrd
                .getAllMarketConfigs(
                    MToken(addresses.getAddress("MOONWELL_DAI"))
                )
                .length,
            3,
            "incorrect reward token length"
        );
        assertEq(
            mrd
                .getAllMarketConfigs(
                    MToken(addresses.getAddress("MOONWELL_USDBC"))
                )
                .length,
            3,
            "incorrect reward token length"
        );
        assertEq(
            mrd
                .getAllMarketConfigs(
                    MToken(addresses.getAddress("MOONWELL_USDC"))
                )
                .length,
            3,
            "incorrect reward token length"
        );
        assertEq(
            mrd
                .getAllMarketConfigs(
                    MToken(addresses.getAddress("MOONWELL_WETH"))
                )
                .length,
            3,
            "incorrect reward token length"
        );
        assertEq(
            mrd
                .getAllMarketConfigs(
                    MToken(addresses.getAddress("MOONWELL_cbETH"))
                )
                .length,
            3,
            "incorrect reward token length"
        );
        assertEq(
            mrd
                .getAllMarketConfigs(
                    MToken(addresses.getAddress("MOONWELL_wstETH"))
                )
                .length,
            3,
            "incorrect reward token length"
        );
        assertEq(
            mrd
                .getAllMarketConfigs(
                    MToken(addresses.getAddress("MOONWELL_rETH"))
                )
                .length,
            3,
            "incorrect reward token length"
        );
    }

    function testInitializeVoteCollectionFails() public {
        vm.selectFork(baseForkId);
        voteCollection = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        );
        /// test impl and logic contract initialization
        vm.expectRevert("Initializable: contract is already initialized");
        voteCollection.initialize(
            address(0),
            address(0),
            address(0),
            address(0),
            uint16(0),
            address(0)
        );

        voteCollection = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_IMPL")
        );
        vm.expectRevert("Initializable: contract is already initialized");
        voteCollection.initialize(
            address(0),
            address(0),
            address(0),
            address(0),
            uint16(0),
            address(0)
        );
    }

    function testInitializeMultichainGovernorFails() public {
        vm.selectFork(moonbeamForkId);
        /// test impl and logic contract initialization
        MultichainGovernor.InitializeData memory initializeData;
        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );
        bytes[] memory whitelistedCalldata = new bytes[](0);

        vm.expectRevert("Initializable: contract is already initialized");
        MultichainGovernor(address(governor)).initialize(
            initializeData,
            trustedSenders,
            whitelistedCalldata
        );

        governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_IMPL")
        );
        vm.expectRevert("Initializable: contract is already initialized");
        governor.initialize(
            initializeData,
            trustedSenders,
            whitelistedCalldata
        );
    }

    function testInitializeEcosystemReserveFails() public {
        vm.selectFork(baseForkId);

        IEcosystemReserveControllerUplift ecosystemReserveController = IEcosystemReserveControllerUplift(
                addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER")
            );
        address ownerAddress = ecosystemReserveController.owner();

        vm.prank(ownerAddress);
        vm.expectRevert("ECOSYSTEM_RESERVE has been initialized");
        ecosystemReserveController.setEcosystemReserve(address(0));

        IEcosystemReserveUplift ecosystemReserve = IEcosystemReserveUplift(
            addresses.getAddress("ECOSYSTEM_RESERVE_PROXY")
        );

        vm.expectRevert("Initializable: contract is already initialized");
        ecosystemReserve.initialize(address(1));

        ecosystemReserve = IEcosystemReserveUplift(
            addresses.getAddress("ECOSYSTEM_RESERVE_IMPL")
        );
        vm.expectRevert("Initializable: contract is already initialized");
        ecosystemReserve.initialize(address(1));
    }

    function testRetrieveGasPriceMoonbeamSucceeds() public {
        vm.selectFork(moonbeamForkId);

        uint256 gasCost = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        ).bridgeCost(baseWormholeChainId);

        assertTrue(gasCost != 0, "gas cost is 0 bridgeCost");

        gasCost = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        ).bridgeCostAll();

        assertTrue(gasCost != 0, "gas cost is 0 gas cost all");
    }

    function testRetrieveGasPriceBaseSucceeds() public {
        vm.selectFork(baseForkId);

        uint256 gasCost = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        ).bridgeCost(baseWormholeChainId);

        assertTrue(gasCost != 0, "gas cost is 0 bridgeCost");

        gasCost = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        ).bridgeCostAll();

        assertTrue(gasCost != 0, "gas cost is 0 gas cost all");
    }

    function testProposeOnMoonbeamWellSucceeds() public {
        vm.selectFork(moonbeamForkId);

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            40_000_000 * 1e18
        );

        uint256 startingProposalId = governor.proposalCount();
        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(proposalId, startingProposalId + 1, "incorrect proposal id");
        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        _assertProposalCreated(proposalId, address(this));

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        /// vote yes on proposal
        governor.castVote(proposalId, 0);

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, address(this));
            assertTrue(hasVoted, "has voted incorrect");
            assertEq(voteValue, 0, "vote value incorrect");
            assertEq(votes, governor.getCurrentVotes(address(this)), "votes");

            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(
                totalVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect total votes"
            );
            assertEq(
                forVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect for votes"
            );
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }
        {
            (
                ,
                ,
                ,
                ,
                uint256 crossChainVoteCollectionEndTimestamp,
                ,
                ,
                ,

            ) = governor.proposalInformation(proposalId);

            vm.warp(crossChainVoteCollectionEndTimestamp - 1);

            assertEq(
                uint256(governor.state(proposalId)),
                1,
                "not in xchain vote collection period"
            );

            vm.warp(crossChainVoteCollectionEndTimestamp);
            assertEq(
                uint256(governor.state(proposalId)),
                1,
                "not in xchain vote collection period at end"
            );

            vm.warp(block.timestamp + 1);
            assertEq(
                uint256(governor.state(proposalId)),
                4,
                "not in succeeded at end"
            );
        }

        {
            governor.execute(proposalId);

            assertEq(
                address(governor).balance,
                0,
                "incorrect governor balance"
            );
            assertEq(
                governor.proposalThreshold(),
                40_000_000 * 1e18,
                "incorrect new proposal threshold"
            );
            assertEq(uint256(governor.state(proposalId)), 5, "not in executed");
        }
    }

    function testVotingOnMoonbeamAllTokens() public {
        vm.selectFork(moonbeamForkId);

        // mint 1/4 of the amount for each token
        uint256 mintAmount = governor.quorum() / 4;

        address user = address(1);

        {
            address[] memory recipients = new address[](1);
            recipients[0] = user;

            bool[] memory isLinear = new bool[](1);
            isLinear[0] = true;

            uint[] memory epochs = new uint[](1);
            epochs[0] = 1;

            uint[] memory vestingDurations = new uint[](1);
            vestingDurations[0] = 1;

            uint[] memory cliffs = new uint[](1);
            cliffs[0] = 0;

            uint[] memory cliffPercentages = new uint[](1);
            cliffPercentages[0] = 0;

            uint[] memory amounts = new uint[](1);
            amounts[0] = mintAmount;

            // prank as admin
            vm.prank(address(distributor.admin()));
            distributor.setAllocations(
                recipients,
                isLinear,
                epochs,
                vestingDurations,
                cliffs,
                cliffPercentages,
                amounts
            );
        }

        vm.startPrank(user);

        distributor.delegate(user);

        deal(address(well), user, mintAmount);
        well.approve(address(stakedWellMoonbeam), mintAmount);
        stakedWellMoonbeam.stake(user, mintAmount);

        deal(address(well), user, mintAmount);
        deal(address(well), user, mintAmount);
        well.delegate(user);

        deal(address(xwell), user, mintAmount);
        xwell.delegate(user);

        vm.stopPrank();

        // mint threshold for proposer
        deal(address(well), address(this), governor.proposalThreshold());
        well.delegate(address(this));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        uint256 proposalId;

        {
            address[] memory targets = new address[](1);
            uint256[] memory values = new uint256[](1);
            bytes[] memory calldatas = new bytes[](1);
            string
                memory description = "Proposal MIP-M00 - Update Proposal Threshold";

            targets[0] = address(governor);
            values[0] = 0;
            calldatas[0] = abi.encodeWithSignature(
                "updateProposalThreshold(uint256)",
                40_000_000 * 1e18
            );

            uint256 startingProposalId = governor.proposalCount();
            uint256 bridgeCost = governor.bridgeCostAll();
            vm.deal(address(this), bridgeCost);

            proposalId = governor.propose{value: bridgeCost}(
                targets,
                values,
                calldatas,
                description
            );

            assertEq(
                proposalId,
                startingProposalId + 1,
                "incorrect proposal id"
            );
            assertEq(
                uint256(governor.state(proposalId)),
                0,
                "incorrect proposal state"
            );

            // assertTrue(
            //     governor.userHasProposal(proposalId, address(this)),
            //     "user has proposal"
            // );
            // assertTrue(
            //     governor.proposalValid(proposalId),
            //     "user does not have proposal"
            // );
        }

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        uint256 totalMintAmount = governor.quorum();

        assertEq(
            governor.getCurrentVotes(user),
            totalMintAmount,
            "incorrect current votes"
        );

        /// vote yes on proposal
        vm.prank(user);
        governor.castVote(proposalId, 0);

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, user);
            assertTrue(hasVoted, "has voted incorrect");
            assertEq(voteValue, 0, "vote value incorrect");
            assertEq(votes, totalMintAmount, "votes");

            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(
                totalVotes,
                governor.getCurrentVotes(user),
                "incorrect total votes"
            );
            assertEq(
                forVotes,
                governor.getCurrentVotes(user),
                "incorrect for votes"
            );
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }
        {
            (
                ,
                ,
                ,
                ,
                uint256 crossChainVoteCollectionEndTimestamp,
                ,
                ,
                ,

            ) = governor.proposalInformation(proposalId);

            vm.warp(crossChainVoteCollectionEndTimestamp - 1);

            assertEq(
                uint256(governor.state(proposalId)),
                1,
                "not in xchain vote collection period"
            );

            vm.warp(crossChainVoteCollectionEndTimestamp);
            assertEq(
                uint256(governor.state(proposalId)),
                1,
                "not in xchain vote collection period at end"
            );

            vm.warp(block.timestamp + 1);
            assertEq(
                uint256(governor.state(proposalId)),
                4,
                "not in succeeded at end"
            );
        }

        {
            governor.execute(proposalId);

            assertEq(
                address(governor).balance,
                0,
                "incorrect governor balance"
            );
            assertEq(
                governor.proposalThreshold(),
                40_000_000 * 1e18,
                "incorrect new proposal threshold"
            );
            assertEq(uint256(governor.state(proposalId)), 5, "not in executed");
        }
    }

    function testProposeOnMoonbeamDefeat() public {
        vm.selectFork(moonbeamForkId);

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 startingProposalId = governor.proposalCount();
        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(proposalId, startingProposalId + 1, "incorrect proposal id");
        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        _assertProposalCreated(proposalId, address(this));

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        /// vote yes on proposal
        governor.castVote(proposalId, 1);

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, address(this));
            assertTrue(hasVoted, "has voted incorrect");
            assertEq(voteValue, 1, "vote value incorrect");
            assertEq(votes, governor.getCurrentVotes(address(this)), "votes");

            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(
                totalVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect total votes"
            );
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(
                againstVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect against votes"
            );
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }
        {
            (
                ,
                ,
                ,
                ,
                uint256 crossChainVoteCollectionEndTimestamp,
                ,
                ,
                ,

            ) = governor.proposalInformation(proposalId);

            vm.warp(crossChainVoteCollectionEndTimestamp - 1);

            assertEq(
                uint256(governor.state(proposalId)),
                1,
                "not in xchain vote collection period"
            );

            vm.warp(crossChainVoteCollectionEndTimestamp);
            assertEq(
                uint256(governor.state(proposalId)),
                1,
                "not in xchain vote collection period at end"
            );

            vm.warp(block.timestamp + 1);
            assertEq(
                uint256(governor.state(proposalId)),
                3,
                "not in succeeded at end"
            );
        }

        {
            vm.expectRevert(
                "MultichainGovernor: proposal can only be executed if it is Succeeded"
            );
            governor.execute(proposalId);

            assertEq(
                address(governor).balance,
                0,
                "incorrect governor balance"
            );
        }
    }

    function testProposeMoonbeamCancel() public {
        vm.selectFork(moonbeamForkId);

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 startingProposalId = governor.proposalCount();
        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(proposalId, startingProposalId + 1, "incorrect proposal id");
        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        _assertProposalCreated(proposalId, address(this));

        governor.cancel(proposalId);

        assertEq(
            uint256(governor.state(proposalId)),
            2,
            "not in canceled state"
        );
    }

    function testVotingOnBasestkWellSucceeds() public {
        vm.selectFork(moonbeamForkId);

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        _assertProposalCreated(proposalId, address(this));

        uint256 xwellMintAmount;
        {
            uint256 startTimestamp = block.timestamp;
            uint256 endTimestamp = startTimestamp + governor.votingPeriod();
            bytes memory payload = abi.encode(
                proposalId,
                startTimestamp - 1,
                startTimestamp,
                endTimestamp,
                endTimestamp + governor.crossChainVoteCollectionPeriod()
            );

            vm.selectFork(baseForkId);

            vm.warp(startTimestamp - 5);
            xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
            xwellMintAmount = xwell.buffer(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            );

            vm.prank(addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"));
            xwell.mint(address(this), xwellMintAmount);
            xwell.approve(address(stakedWellBase), xwellMintAmount);
            stakedWellBase.stake(address(this), xwellMintAmount);

            vm.warp(block.timestamp + 10);

            uint256 gasCost = wormholeRelayerAdapterBase.nativePriceQuote();

            vm.deal(address(governor), gasCost);
            vm.prank(address(governor));
            wormholeRelayerAdapterBase.sendPayloadToEvm{value: gasCost}(
                30,
                address(voteCollection),
                payload,
                0,
                0
            );
        }

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        /// vote yes on proposal
        voteCollection.castVote(proposalId, 0);

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(totalVotes, xwellMintAmount, "incorrect total votes");
            assertEq(forVotes, xwellMintAmount, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }
    }

    function testVotingOnBasexWellSucceeds()
        public
        returns (uint256 proposalId)
    {
        vm.selectFork(moonbeamForkId);

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        _assertProposalCreated(proposalId, address(this));

        uint256 xwellMintAmount;
        {
            uint256 startTimestamp = block.timestamp;
            uint256 endTimestamp = startTimestamp + governor.votingPeriod();
            bytes memory payload = abi.encode(
                proposalId,
                startTimestamp - 1,
                startTimestamp,
                endTimestamp,
                endTimestamp + governor.crossChainVoteCollectionPeriod()
            );

            vm.selectFork(baseForkId);

            vm.warp(startTimestamp - 5);
            xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
            xwellMintAmount = xwell.buffer(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            );

            vm.prank(addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"));
            xwell.mint(address(this), xwellMintAmount);

            xwell.delegate(address(this));

            vm.warp(block.timestamp + 10);

            uint256 gasCost = wormholeRelayerAdapterBase.nativePriceQuote();

            vm.deal(address(governor), gasCost);
            vm.prank(address(governor));
            wormholeRelayerAdapterBase.sendPayloadToEvm{value: gasCost}(
                30,
                address(voteCollection),
                payload,
                0,
                0
            );
        }

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        /// vote yes on proposal
        voteCollection.castVote(proposalId, 0);

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(totalVotes, xwellMintAmount, "incorrect total votes");
            assertEq(forVotes, xwellMintAmount, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }
    }

    function testVotingOnBasexWellPostVotingPeriodFails() public {
        vm.selectFork(moonbeamForkId);

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        _assertProposalCreated(proposalId, address(this));

        uint256 xwellMintAmount;
        {
            uint256 startTimestamp = block.timestamp;
            uint256 endTimestamp = startTimestamp + governor.votingPeriod();
            bytes memory payload = abi.encode(
                proposalId,
                startTimestamp - 1,
                startTimestamp,
                endTimestamp,
                endTimestamp + governor.crossChainVoteCollectionPeriod()
            );

            vm.selectFork(baseForkId);

            vm.warp(startTimestamp);
            xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
            xwellMintAmount = xwell.buffer(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            );

            vm.prank(addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"));
            xwell.mint(address(this), xwellMintAmount);
            xwell.delegate(address(this));

            vm.warp(block.timestamp + 10);

            uint256 gasCost = wormholeRelayerAdapterBase.nativePriceQuote();

            vm.deal(address(governor), gasCost);
            vm.prank(address(governor));
            wormholeRelayerAdapterBase.sendPayloadToEvm{value: gasCost}(
                30,
                address(voteCollection),
                payload,
                0,
                0
            );

            vm.warp(endTimestamp + 1);
        }

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        vm.expectRevert("MultichainVoteCollection: Voting has ended");
        /// vote yes on proposal
        voteCollection.castVote(proposalId, 0);

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }
    }

    function testRebroadcatingVotesMultipleTimesVotePeriodMultichainGovernorSucceeds()
        public
    {
        /// propose, then rebroadcast
        vm.selectFork(moonbeamForkId);

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);
        uint256 startingProposalId = governor.proposalCount();

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(proposalId, startingProposalId + 1, "incorrect proposal id");
        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        _assertProposalCreated(proposalId, address(this));

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        /// vote yes on proposal
        governor.castVote(proposalId, 0);

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, address(this));
            assertTrue(hasVoted, "has voted incorrect");
            assertEq(voteValue, 0, "vote value incorrect");
            assertEq(votes, governor.getCurrentVotes(address(this)), "votes");

            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(
                totalVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect total votes"
            );
            assertEq(
                forVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect for votes"
            );
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        vm.deal(address(this), bridgeCost * 3);
        governor.rebroadcastProposal{value: bridgeCost}(proposalId);
        governor.rebroadcastProposal{value: bridgeCost}(proposalId);
        governor.rebroadcastProposal{value: bridgeCost}(proposalId);

        assertEq(address(this).balance, 0, "balance not 0 after broadcasting");
        assertEq(
            address(governor).balance,
            0,
            "balance not 0 after broadcasting"
        );
    }

    function testEmittingVotesMultipleTimesVoteCollectionPeriodSucceeds()
        public
    {
        uint256 proposalId = testVotingOnBasexWellSucceeds();

        vm.selectFork(baseForkId);

        (
            ,
            ,
            ,
            uint256 crossChainVoteCollectionEndTimestamp,
            ,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes
        ) = voteCollection.proposalInformation(proposalId);

        vm.warp(crossChainVoteCollectionEndTimestamp);

        uint256 bridgeCost = voteCollection.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        vm.expectEmit(true, true, true, true, address(voteCollection));
        emit VotesEmitted(proposalId, forVotes, againstVotes, abstainVotes);

        voteCollection.emitVotes{value: bridgeCost}(proposalId);

        vm.deal(address(this), bridgeCost);

        vm.expectEmit(true, true, true, true, address(voteCollection));
        emit VotesEmitted(proposalId, forVotes, againstVotes, abstainVotes);

        voteCollection.emitVotes{value: bridgeCost}(proposalId);
    }

    function testReceiveProposalFromRelayersSucceeds() public {
        vm.selectFork(moonbeamForkId);

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        _assertProposalCreated(proposalId, address(this));

        {
            uint256 startTimestamp = block.timestamp;
            uint256 endTimestamp = startTimestamp + governor.votingPeriod();
            uint256 crossChainPeriod = endTimestamp +
                governor.crossChainVoteCollectionPeriod();
            bytes memory payload = abi.encode(
                proposalId,
                startTimestamp - 1,
                startTimestamp,
                endTimestamp,
                crossChainPeriod
            );

            vm.selectFork(baseForkId);

            uint256 gasCost = wormholeRelayerAdapterBase.nativePriceQuote();

            vm.deal(address(governor), gasCost);

            vm.expectEmit(true, true, true, true, address(voteCollection));
            emit ProposalCreated(
                proposalId,
                startTimestamp,
                endTimestamp,
                crossChainPeriod
            );

            vm.prank(address(governor));
            wormholeRelayerAdapterBase.sendPayloadToEvm{value: gasCost}(
                30,
                address(voteCollection),
                payload,
                0,
                0
            );

            (
                uint256 voteSnapshotTimestamp,
                uint256 votingStartTime,
                uint256 votingEndTime,
                uint256 crossChainVoteCollectionEndTimestamp,
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = voteCollection.proposalInformation(proposalId);

            assertEq(
                voteSnapshotTimestamp,
                startTimestamp - 1,
                "incorrect snapshot"
            );
            assertEq(
                votingStartTime,
                startTimestamp,
                "incorrect voting start time"
            );
            assertEq(votingEndTime, endTimestamp, "incorrect voting end time");
            assertEq(
                crossChainVoteCollectionEndTimestamp,
                crossChainPeriod,
                "incorrect cross chain vote collection end time"
            );

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }
    }

    function testReceiveSameProposalFromRelayersTwiceFails() public {
        vm.selectFork(moonbeamForkId);

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        _assertProposalCreated(proposalId, address(this));

        {
            uint256 startTimestamp = block.timestamp;
            uint256 endTimestamp = startTimestamp + governor.votingPeriod();
            uint256 crossChainPeriod = endTimestamp +
                governor.crossChainVoteCollectionPeriod();
            bytes memory payload = abi.encode(
                proposalId,
                startTimestamp - 1,
                startTimestamp,
                endTimestamp,
                crossChainPeriod
            );

            vm.selectFork(baseForkId);

            uint256 gasCost = wormholeRelayerAdapterBase.nativePriceQuote();

            vm.deal(address(governor), gasCost);

            vm.expectEmit(true, true, true, true, address(voteCollection));
            emit ProposalCreated(
                proposalId,
                startTimestamp,
                endTimestamp,
                crossChainPeriod
            );

            vm.prank(address(governor));
            wormholeRelayerAdapterBase.sendPayloadToEvm{value: gasCost}(
                30,
                address(voteCollection),
                payload,
                0,
                0
            );

            (
                uint256 voteSnapshotTimestamp,
                uint256 votingStartTime,
                uint256 votingEndTime,
                uint256 crossChainVoteCollectionEndTimestamp,
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = voteCollection.proposalInformation(proposalId);

            assertEq(
                voteSnapshotTimestamp,
                startTimestamp - 1,
                "incorrect snapshot"
            );
            assertEq(
                votingStartTime,
                startTimestamp,
                "incorrect voting start time"
            );
            assertEq(votingEndTime, endTimestamp, "incorrect voting end time");
            assertEq(
                crossChainVoteCollectionEndTimestamp,
                crossChainPeriod,
                "incorrect cross chain vote collection end time"
            );

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");

            vm.deal(address(governor), gasCost);

            vm.expectRevert(
                "MultichainVoteCollection: proposal already exists"
            );
            vm.prank(address(governor));
            wormholeRelayerAdapterBase.sendPayloadToEvm{value: gasCost}(
                30,
                address(voteCollection),
                payload,
                0,
                0
            );
        }
    }

    function testEmittingVotesPostVoteCollectionPeriodFails() public {
        uint256 proposalId = testVotingOnBasexWellSucceeds();

        vm.selectFork(baseForkId);

        (
            ,
            ,
            ,
            uint256 crossChainVoteCollectionEndTimestamp,
            ,
            ,
            ,

        ) = voteCollection.proposalInformation(proposalId);

        vm.warp(crossChainVoteCollectionEndTimestamp + 1);
        vm.expectRevert(
            "MultichainVoteCollection: Voting collection phase has ended"
        );
        voteCollection.emitVotes(proposalId);
    }

    /// upgrading contract logic

    function testUpgradeMultichainGovernorThroughGovProposal() public {
        vm.selectFork(moonbeamForkId);

        MockMultichainGovernor newGovernor = new MockMultichainGovernor();

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = addresses.getAddress("MOONBEAM_PROXY_ADMIN");
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "upgrade(address,address)",
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
            address(newGovernor)
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);
        uint256 startingProposalId = governor.proposalCount();

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(proposalId, startingProposalId + 1, "incorrect proposal id");
        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        _assertProposalCreated(proposalId, address(this));

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        /// vote yes on proposal
        governor.castVote(proposalId, 0);

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, address(this));
            assertTrue(hasVoted, "has voted incorrect");
            assertEq(voteValue, 0, "vote value incorrect");
            assertEq(votes, governor.getCurrentVotes(address(this)), "votes");

            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(
                totalVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect total votes"
            );
            assertEq(
                forVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect for votes"
            );
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }
        {
            (
                ,
                ,
                ,
                ,
                uint256 crossChainVoteCollectionEndTimestamp,
                ,
                ,
                ,

            ) = governor.proposalInformation(proposalId);

            vm.warp(crossChainVoteCollectionEndTimestamp - 1);

            assertEq(
                uint256(governor.state(proposalId)),
                1,
                "not in xchain vote collection period"
            );

            vm.warp(crossChainVoteCollectionEndTimestamp);
            assertEq(
                uint256(governor.state(proposalId)),
                1,
                "not in xchain vote collection period at end"
            );

            vm.warp(block.timestamp + 1);
            assertEq(
                uint256(governor.state(proposalId)),
                4,
                "not in succeeded at end"
            );
        }

        {
            governor.execute(proposalId);

            assertEq(
                address(governor).balance,
                0,
                "incorrect governor balance"
            );
            assertEq(uint256(governor.state(proposalId)), 5, "not in executed");
            assertEq(
                MockMultichainGovernor(address(governor)).newFeature(),
                1,
                "incorrectly upgraded"
            );

            validateProxy(
                vm,
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                address(newGovernor),
                addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
                "moonbeam new logic contract for multichain governor"
            );
        }
    }

    /// this requires a new mock relayer contract
    function testUpgradeMultichainVoteCollection() public {
        vm.selectFork(baseForkId);

        MockVoteCollection newVoteCollection = new MockVoteCollection();

        address proxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        ProxyAdmin(proxyAdmin).upgrade(
            ITransparentUpgradeableProxy(address(voteCollection)),
            address(newVoteCollection)
        );

        validateProxy(
            vm,
            addresses.getAddress("VOTE_COLLECTION_PROXY"),
            address(newVoteCollection),
            addresses.getAddress("MRD_PROXY_ADMIN"),
            "vote collection validation"
        );
    }

    function testBreakGlassGuardianSucceedsSettingPendingAdminAndOwners()
        public
    {
        {
            vm.selectFork(baseForkId);
            temporalGov = TemporalGovernor(
                addresses.getAddress("TEMPORAL_GOVERNOR")
            );
            /// artemis timelock does not start off as trusted sender
            assertFalse(
                temporalGov.isTrustedSender(
                    uint16(moonBeamWormholeChainId),
                    addresses.getAddress(
                        "MOONBEAM_TIMELOCK",
                        sendingChainIdToReceivingChainId[block.chainid]
                    )
                ),
                "artemis timelock should not be trusted sender"
            );
        }

        vm.selectFork(moonbeamForkId);
        address artemisTimelockAddress = addresses.getAddress(
            "MOONBEAM_TIMELOCK"
        );

        /// calldata to transfer system ownership back to artemis timelock
        bytes memory transferOwnershipCalldata = abi.encodeWithSignature(
            "transferOwnership(address)",
            artemisTimelockAddress
        );
        bytes memory changeAdminCalldata = abi.encodeWithSignature(
            "setAdmin(address)",
            artemisTimelockAddress
        );
        bytes memory setEmissionsManagerCalldata = abi.encodeWithSignature(
            "setEmissionsManager(address)",
            artemisTimelockAddress
        );
        bytes memory _setPendingAdminCalldata = abi.encodeWithSignature(
            "_setPendingAdmin(address)",
            artemisTimelockAddress
        );

        /// skip wormhole for now, circle back to that later and make array size 18

        /// targets
        address[] memory targets = new address[](19);
        bytes[] memory calldatas = new bytes[](19);

        targets[0] = addresses.getAddress("WORMHOLE_CORE_MOONBEAM");
        calldatas[0] = proposalC.approvedCalldata(0);

        targets[1] = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");
        calldatas[1] = transferOwnershipCalldata;

        targets[2] = addresses.getAddress("MOONBEAM_PROXY_ADMIN");
        calldatas[2] = transferOwnershipCalldata;

        targets[3] = addresses.getAddress("xWELL_PROXY");
        calldatas[3] = transferOwnershipCalldata;

        targets[4] = addresses.getAddress("CHAINLINK_ORACLE");
        calldatas[4] = changeAdminCalldata;

        targets[5] = addresses.getAddress("stkWELL_PROXY");
        calldatas[5] = setEmissionsManagerCalldata;

        targets[6] = addresses.getAddress("UNITROLLER");
        calldatas[6] = _setPendingAdminCalldata;

        targets[7] = addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER");
        calldatas[7] = transferOwnershipCalldata;

        targets[8] = addresses.getAddress("MOONWELL_mwBTC");
        calldatas[8] = _setPendingAdminCalldata;

        targets[9] = addresses.getAddress("MOONWELL_mBUSD");
        calldatas[9] = _setPendingAdminCalldata;

        targets[10] = addresses.getAddress("MOONWELL_mETH");
        calldatas[10] = _setPendingAdminCalldata;

        targets[11] = addresses.getAddress("MOONWELL_mUSDC");
        calldatas[11] = _setPendingAdminCalldata;

        targets[12] = addresses.getAddress("mGLIMMER");
        calldatas[12] = _setPendingAdminCalldata;

        targets[13] = addresses.getAddress("mxcDOT");
        calldatas[13] = _setPendingAdminCalldata;

        targets[14] = addresses.getAddress("mxcUSDT");
        calldatas[14] = _setPendingAdminCalldata;

        targets[15] = addresses.getAddress("mFRAX");
        calldatas[15] = _setPendingAdminCalldata;

        targets[16] = addresses.getAddress("mUSDCwh");
        calldatas[16] = _setPendingAdminCalldata;

        targets[17] = addresses.getAddress("mxcUSDC");
        calldatas[17] = _setPendingAdminCalldata;

        targets[18] = addresses.getAddress("mETHwh");
        calldatas[18] = _setPendingAdminCalldata;

        bytes[] memory temporalGovCalldatas = new bytes[](1);
        bytes memory temporalGovExecData;
        {
            address temporalGovAddress = addresses.getAddress(
                "TEMPORAL_GOVERNOR",
                baseChainId
            );
            address wormholeCore = addresses.getAddress(
                "WORMHOLE_CORE_MOONBEAM"
            );
            uint64 nextSequence = IWormhole(wormholeCore).nextSequence(
                address(governor)
            );
            address[] memory temporalGovTargets = new address[](1);
            temporalGovTargets[0] = temporalGovAddress;

            temporalGovCalldatas[0] = proposalC.temporalGovernanceCalldata(0);

            temporalGovExecData = abi.encode(
                temporalGovAddress,
                temporalGovTargets,
                new uint256[](1), /// 0 value
                temporalGovCalldatas
            );

            vm.prank(addresses.getAddress("BREAK_GLASS_GUARDIAN"));
            vm.expectEmit(true, true, true, true, wormholeCore);
            emit LogMessagePublished(
                address(governor),
                nextSequence,
                1000, /// nonce is hardcoded to 1000 in mip-m18c.sol
                temporalGovExecData,
                200 /// consistency level is hardcoded at 200 in mip-m18c.sol
            );
        }
        governor.executeBreakGlass(targets, calldatas);

        assertEq(
            IStakedWellUplift(addresses.getAddress("stkWELL_PROXY"))
                .EMISSION_MANAGER(),
            artemisTimelockAddress,
            "stkWELL EMISSIONS MANAGER"
        );
        assertEq(
            Ownable(addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER"))
                .owner(),
            artemisTimelockAddress,
            "ecosystem reserve controller owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ).pendingOwner(),
            artemisTimelockAddress,
            "WORMHOLE_BRIDGE_ADAPTER_PROXY pending owner incorrect"
        );
        /// governor still owns, pending is artemis timelock
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ).owner(),
            address(governor),
            "WORMHOLE_BRIDGE_ADAPTER_PROXY owner incorrect"
        );
        assertEq(
            Ownable(addresses.getAddress("MOONBEAM_PROXY_ADMIN")).owner(),
            artemisTimelockAddress,
            "MOONBEAM_PROXY_ADMIN owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(addresses.getAddress("xWELL_PROXY"))
                .owner(),
            address(governor),
            "xWELL_PROXY owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(addresses.getAddress("xWELL_PROXY"))
                .pendingOwner(),
            artemisTimelockAddress,
            "xWELL_PROXY pending owner incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mETHwh")).pendingAdmin(),
            artemisTimelockAddress,
            "mETHwh pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mETHwh")).admin(),
            address(governor),
            "mETHwh admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcUSDC")).pendingAdmin(),
            artemisTimelockAddress,
            "mxcUSDC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mxcUSDC")).admin(),
            address(governor),
            "mxcUSDC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mUSDCwh")).pendingAdmin(),
            artemisTimelockAddress,
            "mUSDCwh pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mUSDCwh")).admin(),
            address(governor),
            "mUSDCwh admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mFRAX")).pendingAdmin(),
            artemisTimelockAddress,
            "mFRAX pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mFRAX")).admin(),
            address(governor),
            "mFRAX admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcUSDT")).pendingAdmin(),
            artemisTimelockAddress,
            "mxcUSDT pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mxcUSDT")).admin(),
            address(governor),
            "mxcUSDT admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcDOT")).pendingAdmin(),
            artemisTimelockAddress,
            "mxcDOT pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mxcDOT")).admin(),
            address(governor),
            "mxcDOT admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mGLIMMER")).pendingAdmin(),
            artemisTimelockAddress,
            "mGLIMMER pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mGLIMMER")).admin(),
            address(governor),
            "mGLIMMER admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mUSDC")).pendingAdmin(),
            artemisTimelockAddress,
            "MOONWELL_mUSDC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mUSDC")).admin(),
            address(governor),
            "MOONWELL_mUSDC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mBUSD")).pendingAdmin(),
            artemisTimelockAddress,
            "MOONWELL_mBUSD pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mBUSD")).admin(),
            address(governor),
            "MOONWELL_mBUSD admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mwBTC")).pendingAdmin(),
            artemisTimelockAddress,
            "MOONWELL_mwBTC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mwBTC")).admin(),
            address(governor),
            "MOONWELL_mwBTC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mETH")).pendingAdmin(),
            artemisTimelockAddress,
            "MOONWELL_mETH pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mETH")).admin(),
            address(governor),
            "MOONWELL_mETH admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("UNITROLLER")).pendingAdmin(),
            artemisTimelockAddress,
            "UNITROLLER pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("UNITROLLER")).admin(),
            address(governor),
            "UNITROLLER admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("CHAINLINK_ORACLE")).admin(),
            artemisTimelockAddress,
            "Chainlink oracle admin incorrect"
        );

        assertEq(
            governor.breakGlassGuardian(),
            address(0),
            "break glass guardian not revoked"
        );

        /// Base simulation, LFG!

        vm.selectFork(baseForkId);
        temporalGov = TemporalGovernor(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );
        vm.startPrank(address(temporalGov));

        {
            (bool success, ) = address(temporalGov).call(
                temporalGovCalldatas[0]
            );
            require(success, "temporal gov call failed");
        }

        vm.stopPrank();

        assertTrue(
            temporalGov.isTrustedSender(
                uint16(moonBeamWormholeChainId),
                artemisTimelockAddress
            ),
            "artemis timelock not added as a trusted sender"
        );
    }

    /// staking

    /// - assert assets in ecosystem reserve deplete when rewards are claimed

    function testStakestkWellBaseSucceedsAndReceiveRewards() public {
        vm.selectFork(baseForkId);

        /// prank as the wormhole bridge adapter contract
        ///
        uint256 mintAmount = 1_000_000 * 1e18;
        IStakedWellUplift stkwell = IStakedWellUplift(
            addresses.getAddress("stkWELL_PROXY")
        );
        assertGt(
            stkwell.DISTRIBUTION_END(),
            block.timestamp,
            "distribution end incorrect"
        );
        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));

        {
            (
                uint128 emissionsPerSecond,
                uint128 lastUpdateTimestamp,
                uint256 index
            ) = stkwell.assets(address(stkwell));

            assertGe(
                lastUpdateTimestamp,
                1711250225,
                "lastUpdateTimestamp decreased"
            );
            assertGe(emissionsPerSecond, 0, "emissions per second");
            assertGe(index, 0, "rewards index");
        }

        vm.startPrank(stkwell.EMISSION_MANAGER());
        /// distribute 1e18 xWELL per second
        stkwell.configureAsset(1e18, address(stkwell));
        vm.stopPrank();

        vm.warp(block.timestamp + 1);

        vm.startPrank(addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"));
        xwell.mint(address(this), mintAmount);
        xwell.mint(addresses.getAddress("ECOSYSTEM_RESERVE_PROXY"), mintAmount);
        vm.stopPrank();

        uint256 prestkBalance = stkwell.balanceOf(address(this));
        uint256 prexwellBalance = xwell.balanceOf(address(this));
        uint256 preSTKWellTotalSupply = stkwell.totalSupply();

        xwell.approve(address(stkwell), mintAmount);
        stkwell.stake(address(this), mintAmount);

        assertEq(preSTKWellTotalSupply + mintAmount, stkwell.totalSupply());
        assertEq(
            stkwell.balanceOf(address(this)),
            prestkBalance + mintAmount,
            "incorrect stkWELL balance"
        );
        assertEq(
            xwell.balanceOf(address(this)),
            prexwellBalance - mintAmount,
            "incorrect xWELL balance"
        );

        {
            (
                uint128 emissionsPerSecond,
                uint128 lastUpdateTimestamp,
                uint256 index
            ) = stkwell.assets(address(stkwell));

            assertEq(1e18, emissionsPerSecond, "emissions per second");
            assertGt(index, 1, "rewards per second");
            assertEq(
                block.timestamp,
                lastUpdateTimestamp,
                "last update timestamp"
            );
        }

        vm.warp(block.timestamp + 10 days);

        assertEq(
            stkwell.balanceOf(address(this)),
            mintAmount,
            "incorrect stkWELL balance"
        );
        assertEq(xwell.balanceOf(address(this)), 0, "incorrect xWELL balance");

        uint256 userxWellBalance = xwell.balanceOf(address(this));
        stkwell.claimRewards(address(this), type(uint256).max);

        uint256 userRewards = 10 days * 1e18;

        assertLt(
            xwell.balanceOf(address(this)),
            userxWellBalance + userRewards,
            "incorrect xWELL balance after claiming rewards, rewards too high"
        );

        {
            (
                uint128 emissionsPerSecond,
                uint128 lastUpdateTimestamp,

            ) = stkwell.assets(address(stkwell));

            assertEq(1e18, emissionsPerSecond, "emissions per second");
            assertEq(
                block.timestamp,
                lastUpdateTimestamp,
                "last update timestamp"
            );
        }
    }

    function testStakestkWellBaseSucceedsAndReceiveRewardsThreeUsers() public {
        vm.selectFork(baseForkId);

        address userOne = address(1);
        address userTwo = address(2);
        address userThree = address(3);

        uint256 userOneAmount = 1_000_000 * 1e18;
        uint256 userTwoAmount = 2_000_000 * 1e18;
        uint256 userThreeAmount = 3_000_000 * 1e18;

        /// prank as the wormhole bridge adapter contract
        ///
        uint256 mintAmount = 1_000_000 * 1e18;
        IStakedWellUplift stkwell = IStakedWellUplift(
            addresses.getAddress("stkWELL_PROXY")
        );
        assertGt(
            stkwell.DISTRIBUTION_END(),
            block.timestamp,
            "distribution end incorrect"
        );
        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));

        {
            (
                uint128 emissionsPerSecond,
                uint128 lastUpdateTimestamp,
                uint256 index
            ) = stkwell.assets(address(stkwell));

            assertGe(
                lastUpdateTimestamp,
                1711250225,
                "lastUpdateTimestamp decreased"
            );
            assertGe(emissionsPerSecond, 0, "emissions per second");
            assertGe(index, 0, "rewards index");
        }

        vm.startPrank(stkwell.EMISSION_MANAGER());
        /// distribute 1e18 xWELL per second
        stkwell.configureAsset(1e18, address(stkwell));
        vm.stopPrank();

        vm.warp(block.timestamp + 1);

        vm.startPrank(addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"));
        xwell.mint(userOne, userOneAmount);
        xwell.mint(userTwo, userTwoAmount);
        xwell.mint(userThree, userThreeAmount);
        xwell.mint(addresses.getAddress("ECOSYSTEM_RESERVE_PROXY"), mintAmount);
        vm.stopPrank();

        {
            uint256 prestkBalance = stkwell.balanceOf(userOne);
            uint256 prexwellBalance = xwell.balanceOf(userOne);
            uint256 preSTKWellTotalSupply = stkwell.totalSupply();

            vm.startPrank(userOne);
            xwell.approve(address(stkwell), userOneAmount);
            stkwell.stake(userOne, userOneAmount);
            vm.stopPrank();

            assertEq(
                preSTKWellTotalSupply + userOneAmount,
                stkwell.totalSupply()
            );
            assertEq(
                stkwell.balanceOf(userOne),
                prestkBalance + userOneAmount,
                "incorrect stkWELL balance"
            );
            assertEq(
                xwell.balanceOf(userOne),
                prexwellBalance - userOneAmount,
                "incorrect xWELL balance"
            );
        }
        {
            uint256 prestkBalance = stkwell.balanceOf(userTwo);
            uint256 prexwellBalance = xwell.balanceOf(userTwo);
            uint256 preSTKWellTotalSupply = stkwell.totalSupply();

            vm.startPrank(userTwo);
            xwell.approve(address(stkwell), userTwoAmount);
            stkwell.stake(userTwo, userTwoAmount);
            vm.stopPrank();

            assertEq(
                preSTKWellTotalSupply + userTwoAmount,
                stkwell.totalSupply()
            );
            assertEq(
                stkwell.balanceOf(userTwo),
                prestkBalance + userTwoAmount,
                "incorrect stkWELL balance"
            );
            assertEq(
                xwell.balanceOf(userTwo),
                prexwellBalance - userTwoAmount,
                "incorrect xWELL balance"
            );
        }
        {
            uint256 prestkBalance = stkwell.balanceOf(userThree);
            uint256 prexwellBalance = xwell.balanceOf(userThree);
            uint256 preSTKWellTotalSupply = stkwell.totalSupply();

            vm.startPrank(userThree);
            xwell.approve(address(stkwell), userThreeAmount);
            stkwell.stake(userThree, userThreeAmount);
            vm.stopPrank();

            assertEq(
                preSTKWellTotalSupply + userThreeAmount,
                stkwell.totalSupply()
            );
            assertEq(
                stkwell.balanceOf(userThree),
                prestkBalance + userThreeAmount,
                "incorrect stkWELL balance"
            );
            assertEq(
                xwell.balanceOf(userThree),
                prexwellBalance - userThreeAmount,
                "incorrect xWELL balance"
            );
        }

        {
            (
                uint128 emissionsPerSecond,
                uint128 lastUpdateTimestamp,
                uint256 index
            ) = stkwell.assets(address(stkwell));

            assertEq(1e18, emissionsPerSecond, "emissions per second");
            assertGt(index, 1, "rewards per second");
            assertEq(
                block.timestamp,
                lastUpdateTimestamp,
                "last update timestamp"
            );
        }

        vm.warp(block.timestamp + 10 days);

        assertGt(
            (10 days * 1e18) / 6,
            stkwell.getTotalRewardsBalance(userOne),
            "user one rewards balance incorrect"
        );
        assertGt(
            (10 days * 1e18) / 3,
            stkwell.getTotalRewardsBalance(userTwo),
            "user two rewards balance incorrect"
        );
        assertGt(
            (10 days * 1e18) / 2,
            stkwell.getTotalRewardsBalance(userThree),
            "user three rewards balance incorrect"
        );

        uint256 startingxWELLAmount = xwell.balanceOf(
            addresses.getAddress("ECOSYSTEM_RESERVE_PROXY")
        );
        {
            uint256 startingUserxWellBalance = xwell.balanceOf(userOne);

            vm.prank(userOne);
            stkwell.claimRewards(userOne, type(uint256).max);

            assertGt(
                startingUserxWellBalance + ((10 days * 1e18) / 6),
                xwell.balanceOf(userOne),
                "incorrect xWELL balance after claiming rewards"
            );
        }

        {
            uint256 startingUserxWellBalance = xwell.balanceOf(userTwo);

            vm.prank(userTwo);
            stkwell.claimRewards(userTwo, type(uint256).max);

            assertGt(
                startingUserxWellBalance + ((10 days * 1e18) / 3),
                xwell.balanceOf(userTwo),
                "incorrect xWELL balance after claiming rewards"
            );
        }

        {
            uint256 startingUserxWellBalance = xwell.balanceOf(userThree);

            vm.prank(userThree);
            stkwell.claimRewards(userThree, type(uint256).max);

            assertGt(
                startingUserxWellBalance + ((10 days * 1e18) / 2),
                xwell.balanceOf(userThree),
                "incorrect xWELL balance after claiming rewards"
            );
        }

        /// starting balance greater than ending balance
        assertGt(
            startingxWELLAmount,
            xwell.balanceOf(addresses.getAddress("ECOSYSTEM_RESERVE_PROXY")),
            "did not deplete ecosystem reserve"
        );
    }

    function _assertProposalCreated(
        uint256 proposalid,
        address proposer
    ) private view {
        uint256[] memory liveProposals = governor.liveProposals();
        bool proposalFound = false;

        for (uint256 i = 0; i < liveProposals.length; i++) {
            if (liveProposals[i] == proposalid) {
                proposalFound = true;
                break;
            }
        }

        require(proposalFound, "proposal not created");

        uint256[] memory currentUserLiveProposals = governor
            .getUserLiveProposals(proposer);
        bool userProposalFound = false;

        for (uint256 i = 0; i < currentUserLiveProposals.length; i++) {
            if (currentUserLiveProposals[i] == proposalid) {
                userProposalFound = true;
                break;
            }
        }
        require(userProposalFound, "proposal not created");
    }

    function testGrantGuardianRoleAfterPause() public {
        vm.selectFork(moonbeamForkId);

        address pauseGuardian = addresses.getAddress(
            "MOONBEAM_PAUSE_GUARDIAN_MULTISIG"
        );

        vm.prank(pauseGuardian);
        governor.pause();

        assertTrue(governor.paused(), "governor not paused");

        vm.prank(pauseGuardian);
        governor.unpause();

        assertFalse(governor.paused(), "governor paused");
        assertEq(governor.pauseGuardian(), address(0), "guardian not kicked");

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Proposal MIP-M00 - Set guardian role";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "grantPauseGuardian(address)",
            pauseGuardian
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        /// vote yes on proposal
        governor.castVote(proposalId, 0);

        (
            ,
            ,
            ,
            ,
            uint256 crossChainVoteCollectionEndTimestamp,
            ,
            ,
            ,

        ) = governor.proposalInformation(proposalId);

        vm.warp(crossChainVoteCollectionEndTimestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            4,
            "incorrect proposal state"
        );

        governor.execute(proposalId);

        assertEq(governor.pauseGuardian(), pauseGuardian, "guardian not set");

        assertEq(
            uint256(governor.state(proposalId)),
            5,
            "incorrect proposal state"
        );
    }
}
