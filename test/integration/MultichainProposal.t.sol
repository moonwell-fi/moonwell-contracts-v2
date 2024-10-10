// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC20Votes} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import "@forge-std/Test.sol";

import "@protocol/utils/ChainIds.sol";
import "@utils/ChainIds.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {MToken} from "@protocol/MToken.sol";
import {mipx01} from "@proposals/mips/mip-x01/mip-x01.sol";
import {mipm23c} from "@proposals/mips/mip-m23/mip-m23c.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {Constants} from "@protocol/governance/multichain/Constants.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {IStakedWellUplift} from "@protocol/stkWell/IStakedWellUplift.sol";
import {MockVoteCollection} from "@test/mock/MockVoteCollection.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {ITimelock as Timelock} from "@protocol/interfaces/ITimelock.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {MockMultichainGovernor} from "@test/mock/MockMultichainGovernor.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {TokenSaleDistributorInterfaceV1} from "@protocol/views/TokenSaleDistributorInterfaceV1.sol";
import {ITemporalGovernor, TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {IEcosystemReserveUplift, IEcosystemReserveControllerUplift} from "@protocol/stkWell/IEcosystemReserveUplift.sol";

/// @notice run this on a chainforked moonbeam node.
/// then switch over to base network to generate the calldata,
/// then switch back to moonbeam to run the test with the generated calldata

/*
if the tests fail, try setting the environment variables as follows:

export DO_DEPLOY=true
export DO_AFTER_DEPLOY=true
export DO_PRE_BUILD_MOCK=true
export DO_BUILD=true
export DO_RUN=true
export DO_TEARDOWN=true
export DO_VALIDATE=true

*/
contract MultichainProposalTest is PostProposalCheck {
    using ChainIds for uint256;

    MultichainVoteCollection public voteCollection;
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

    event VotesEmitted(
        uint256 proposalId,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes
    );

    event MockWormholeRelayerError(string reason);

    address public constant voter = address(100_000_000);

    mipm23c public proposalC;

    TemporalGovernor public temporalGov;

    WormholeRelayerAdapter public wormholeRelayerAdapter;

    /// @notice new xWELL buffer cap
    uint256 public constant XWELL_BUFFER_CAP = 100_000_000 * 1e18;

    /// @notice new xWELL rate limit per second
    uint128 public constant XWELL_RATE_LIMIT_PER_SECOND = 1158 * 1e18;

    function setUp() public override {
        vm.makePersistent(address(this));

        MOONBEAM_FORK_ID.createForksAndSelect();

        uint256 startTimestamp = block.timestamp;

        vm.warp(startTimestamp);
        {
            addresses = new Addresses();
            vm.makePersistent(address(addresses));

            xwell = xWELL(addresses.getAddress("xWELL_PROXY"));

            {
                vm.selectFork(BASE_FORK_ID);
                vm.warp(startTimestamp);

                stakedWellBase = IStakedWell(
                    addresses.getAddress("STK_GOVTOKEN_PROXY")
                );

                vm.selectFork(MOONBEAM_FORK_ID);
            }
        }

        super.setUp();

        proposalC = new mipm23c();
        proposalC.buildCalldata(addresses);

        voteCollection = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY", BASE_CHAIN_ID)
        );
        vm.makePersistent(address(voteCollection));

        addresses.addRestriction(block.chainid.toMoonbeamChainId());
        wormhole = IWormhole(
            addresses.getAddress("WORMHOLE_CORE", MOONBEAM_CHAIN_ID)
        );

        well = ERC20Votes(addresses.getAddress("GOVTOKEN", MOONBEAM_CHAIN_ID));

        stakedWellMoonbeam = IStakedWell(
            addresses.getAddress("STK_GOVTOKEN_PROXY", MOONBEAM_CHAIN_ID)
        );

        distributor = TokenSaleDistributorInterfaceV1(
            addresses.getAddress(
                "TOKEN_SALE_DISTRIBUTOR_PROXY",
                MOONBEAM_CHAIN_ID
            )
        );

        timelock = Timelock(
            addresses.getAddress("MOONBEAM_TIMELOCK", MOONBEAM_CHAIN_ID)
        );
        governor = MultichainGovernor(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"))
        );
        vm.makePersistent(address(governor));

        addresses.removeRestriction();

        {
            vm.selectFork(MOONBEAM_FORK_ID);

            /// ----------------------------------------------------------
            /// ---------------- Wormhole Relayer Etching ----------------
            /// ----------------------------------------------------------

            /// mock relayer so we can simulate bridging well
            wormholeRelayerAdapter = new WormholeRelayerAdapter();
            vm.makePersistent(address(wormholeRelayerAdapter));
            vm.label(address(wormholeRelayerAdapter), "MockWormholeRelayer");

            /// we need to set this so that the relayer mock knows that for the next sendPayloadToEvm
            /// call it must switch forks
            wormholeRelayerAdapter.setIsMultichainTest(true);
            wormholeRelayerAdapter.setSenderChainId(MOONBEAM_WORMHOLE_CHAIN_ID);

            // set mock as the wormholeRelayer address on bridge adapter
            WormholeBridgeAdapter wormholeBridgeAdapter = WormholeBridgeAdapter(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            );

            uint256 gasLimit = wormholeBridgeAdapter.gasLimit();

            // encode gasLimit and relayer address since is stored in a single slot
            // relayer is first due to how evm pack values into a single storage
            bytes32 encodedData = bytes32(
                (uint256(uint160(address(wormholeRelayerAdapter))) << 96) |
                    uint256(gasLimit)
            );

            vm.selectFork(BASE_FORK_ID);

            /// stores the wormhole mock address in the wormholeRelayer variable
            vm.store(address(voteCollection), bytes32(0), encodedData);

            vm.selectFork(OPTIMISM_FORK_ID);
            vm.warp(startTimestamp);

            address voteCollectionOptimism = addresses.getAddress(
                "VOTE_COLLECTION_PROXY"
            );

            /// stores the wormhole mock address in the wormholeRelayer variable
            vm.store(voteCollectionOptimism, bytes32(0), encodedData);

            vm.selectFork(MOONBEAM_FORK_ID);

            /// stores the wormhole mock address in the wormholeRelayer variable
            vm.store(
                address(governor),
                bytes32(uint256(103)),
                bytes32(uint256(uint160(address(wormholeRelayerAdapter))))
            );
            /// ----------------------------------------------------------
            /// ----------------------------------------------------------
            /// ----------------------------------------------------------
        }
    }

    function testSetup() public {
        vm.selectFork(BASE_FORK_ID);
        voteCollection = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        );

        assertEq(
            address(voteCollection.xWell()),
            addresses.getAddress("xWELL_PROXY"),
            "incorrect xWELL contract"
        );
        assertEq(
            address(voteCollection.stkWell()),
            addresses.getAddress("STK_GOVTOKEN_PROXY"),
            "incorrect xWELL contract"
        );

        temporalGov = TemporalGovernor(
            payable(addresses.getAddress("TEMPORAL_GOVERNOR"))
        );
        /// artemis timelock does not start off as trusted sender
        assertFalse(
            temporalGov.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                addresses.getAddress(
                    "MOONBEAM_TIMELOCK",
                    block.chainid.toMoonbeamChainId()
                )
            ),
            "artemis timelock should not be trusted sender"
        );
        assertTrue(
            temporalGov.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                addresses.getAddress(
                    "MULTICHAIN_GOVERNOR_PROXY",
                    block.chainid.toMoonbeamChainId()
                )
            ),
            "multichain governor should be trusted sender"
        );

        assertEq(
            temporalGov.allTrustedSenders(MOONBEAM_WORMHOLE_CHAIN_ID).length,
            1,
            "incorrect amount of trusted senders post proposal"
        );
    }

    function testxWELLPostProposal() public {
        {
            vm.selectFork(BASE_FORK_ID);

            xWELL baseWell = xWELL(addresses.getAddress("xWELL_PROXY"));

            assertEq(
                xwell.bufferCap(
                    addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
                ),
                XWELL_BUFFER_CAP,
                "XWELL_BUFFER_CAP incorrectly set on Base"
            );
            assertEq(
                xwell.rateLimitPerSecond(
                    addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
                ),
                XWELL_RATE_LIMIT_PER_SECOND,
                "XWELL_RATE_LIMIT_PER_SECOND incorrectly set on Base"
            );
            assertEq(
                baseWell.name(),
                "WELL",
                "name should not change post proposal"
            );
            assertEq(
                baseWell.symbol(),
                "WELL",
                "name should not change post proposal"
            );
        }
        {
            vm.selectFork(MOONBEAM_FORK_ID);
            xwell = xWELL(addresses.getAddress("xWELL_PROXY"));

            assertEq(
                xwell.bufferCap(
                    addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
                ),
                XWELL_BUFFER_CAP,
                "XWELL_BUFFER_CAP incorrectly set on Moonbeam"
            );
            assertEq(
                xwell.rateLimitPerSecond(
                    addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
                ),
                XWELL_RATE_LIMIT_PER_SECOND,
                "XWELL_RATE_LIMIT_PER_SECOND incorrectly set on Moonbeam"
            );
            assertEq(
                xwell.name(),
                "WELL",
                "name should not change post proposal"
            );
            assertEq(
                xwell.symbol(),
                "WELL",
                "name should not change post proposal"
            );
        }
        {
            vm.selectFork(OPTIMISM_FORK_ID);
            xwell = xWELL(addresses.getAddress("xWELL_PROXY"));

            assertEq(
                xwell.bufferCap(
                    addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
                ),
                XWELL_BUFFER_CAP,
                "XWELL_BUFFER_CAP incorrectly set on Optimism"
            );
            assertEq(
                xwell.rateLimitPerSecond(
                    addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
                ),
                XWELL_RATE_LIMIT_PER_SECOND,
                "XWELL_RATE_LIMIT_PER_SECOND incorrectly set on Optimism"
            );
        }
    }

    function _ownerUnpauseTest() private {
        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));

        vm.prank(xwell.pauseGuardian());
        xwell.pause();
        assertTrue(xwell.paused(), "xwell should be paused");

        vm.prank(xwell.owner());
        xwell.ownerUnpause();
        assertFalse(
            xwell.paused(),
            "xwell should be unpaused post ownerUnpause"
        );
    }

    function testPausexWELLUnpauseAsOwner() public {
        vm.selectFork(MOONBEAM_FORK_ID);
        _ownerUnpauseTest();

        vm.selectFork(BASE_FORK_ID);
        _ownerUnpauseTest();

        vm.selectFork(OPTIMISM_FORK_ID);
        _ownerUnpauseTest();
    }

    function testNoBaseWormholeCoreAddressInProposal() public {
        address wormholeBase = addresses.getAddress(
            "WORMHOLE_CORE",
            BASE_CHAIN_ID
        );
        vm.selectFork(MOONBEAM_FORK_ID);
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
        vm.selectFork(BASE_FORK_ID);

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
        vm.selectFork(BASE_FORK_ID);
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
        vm.selectFork(MOONBEAM_FORK_ID);
        /// test impl and logic contract initialization
        MultichainGovernor.InitializeData memory initializeData;
        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );
        bytes[] memory whitelistedCalldata = new bytes[](0);

        vm.expectRevert("Initializable: contract is already initialized");
        governor.initialize(
            initializeData,
            trustedSenders,
            whitelistedCalldata
        );

        governor = MultichainGovernor(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_IMPL"))
        );
        vm.expectRevert("Initializable: contract is already initialized");
        governor.initialize(
            initializeData,
            trustedSenders,
            whitelistedCalldata
        );
    }

    function testInitializeEcosystemReserveFails() public {
        vm.selectFork(BASE_FORK_ID);

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
        vm.selectFork(MOONBEAM_FORK_ID);
        wormholeRelayerAdapter.setSenderChainId(BASE_WORMHOLE_CHAIN_ID);

        uint256 gasCost = MultichainGovernor(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"))
        ).bridgeCost(BASE_WORMHOLE_CHAIN_ID);

        assertTrue(gasCost != 0, "gas cost is 0 bridgeCost");

        gasCost = MultichainGovernor(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"))
        ).bridgeCostAll();

        assertTrue(gasCost != 0, "gas cost is 0 gas cost all");
    }

    function testRetrieveGasPriceBaseSucceeds() public {
        vm.selectFork(BASE_FORK_ID);

        wormholeRelayerAdapter.setSenderChainId(BASE_WORMHOLE_CHAIN_ID);

        uint256 gasCost = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        ).bridgeCost(BASE_WORMHOLE_CHAIN_ID);

        assertTrue(gasCost != 0, "gas cost is 0 bridgeCost");

        gasCost = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        ).bridgeCostAll();

        assertTrue(gasCost != 0, "gas cost is 0 gas cost all");
    }

    function testProposeOnMoonbeamWellSucceeds() public {
        vm.selectFork(MOONBEAM_FORK_ID);

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

        uint256 startingGovernorBalance = address(governor).balance;

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
                startingGovernorBalance,
                "incorrect governor balance, should not change"
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
        vm.selectFork(MOONBEAM_FORK_ID);
        wormholeRelayerAdapter.setIsMultichainTest(false);

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
        uint256 startingGovernorBalance = address(governor).balance;

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
                startingGovernorBalance,
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
        vm.selectFork(MOONBEAM_FORK_ID);

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

        uint256 startingProposalId = governor.proposalCount();
        uint256 bridgeCost = governor.bridgeCostAll();

        vm.deal(address(this), bridgeCost);
        uint256 startingGovernorBalance = address(governor).balance;

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
                startingGovernorBalance,
                "incorrect governor balance"
            );
        }
    }

    function testProposeMoonbeamExcessRefund() public {
        vm.selectFork(MOONBEAM_FORK_ID);

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
        vm.deal(address(this), bridgeCost * 100);

        governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(
            address(this).balance,
            bridgeCost * 99,
            "bridge cost not refunded"
        );
    }

    function testProposeMoonbeamCancel() public {
        vm.selectFork(MOONBEAM_FORK_ID);

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
        vm.selectFork(MOONBEAM_FORK_ID);

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);
        uint256 timestamp = block.timestamp + 1;

        vm.warp(timestamp);

        vm.selectFork(BASE_FORK_ID);

        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
        uint256 xwellMintAmount = xwell.buffer(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        vm.prank(addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"));
        xwell.mint(address(this), xwellMintAmount);
        xwell.approve(address(stakedWellBase), xwellMintAmount);

        stakedWellBase.stake(address(this), xwellMintAmount);

        vm.warp(timestamp);

        vm.selectFork(MOONBEAM_FORK_ID);

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

        wormholeRelayerAdapter.setSenderChainId(MOONBEAM_WORMHOLE_CHAIN_ID);

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

        vm.selectFork(BASE_FORK_ID);

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

        console.log("block.timestamp", block.timestamp);

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
        vm.selectFork(MOONBEAM_FORK_ID);

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);

        uint256 timestamp = block.timestamp + 1;
        vm.warp(timestamp);

        // make sure all chain have the same block timestamp
        vm.selectFork(BASE_FORK_ID);
        vm.warp(timestamp);

        vm.selectFork(MOONBEAM_FORK_ID);

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

        bytes32 encodedData = bytes32(
            uint256(uint160(address(wormholeRelayerAdapter)))
        );

        /// stores the wormhole mock address in the wormholeRelayer variable
        vm.store(address(governor), bytes32(uint256(103)), encodedData);

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

            vm.selectFork(BASE_FORK_ID);
            vm.warp(startTimestamp - 5);
            xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
            xwellMintAmount = xwell.buffer(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            );

            vm.prank(addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"));
            xwell.mint(address(this), xwellMintAmount);

            xwell.delegate(address(this));

            vm.warp(endTimestamp - 5);
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
        vm.selectFork(MOONBEAM_FORK_ID);

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

        wormholeRelayerAdapter.setSenderChainId(MOONBEAM_WORMHOLE_CHAIN_ID);
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

            vm.selectFork(BASE_FORK_ID);

            vm.warp(startTimestamp);
            xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
            xwellMintAmount = xwell.buffer(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            );

            vm.prank(addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"));
            xwell.mint(address(this), xwellMintAmount);
            xwell.delegate(address(this));

            vm.warp(endTimestamp + 5);
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

    function testRebroadcatingProposalMultipleTimesVotePeriodMultichainGovernorSucceeds()
        public
    {
        /// propose, then rebroadcast
        vm.selectFork(MOONBEAM_FORK_ID);

        wormholeRelayerAdapter.setSilenceFailure(true);

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
        uint256 startingProposalId = governor.proposalCount();
        uint256 startingGovernorBalance = address(governor).balance;

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
            startingGovernorBalance,
            "balance not 0 after broadcasting"
        );
    }

    function testEmittingVotesExcessValueRefunded() public {
        uint256 proposalId = testVotingOnBasexWellSucceeds();

        vm.selectFork(BASE_FORK_ID);

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
        vm.deal(address(this), bridgeCost * 100);

        wormholeRelayerAdapter.setSenderChainId(BASE_WORMHOLE_CHAIN_ID);

        vm.expectEmit(true, true, true, true, address(voteCollection));
        emit VotesEmitted(proposalId, forVotes, againstVotes, abstainVotes);

        voteCollection.emitVotes{value: bridgeCost * 100}(proposalId);

        assertEq(
            address(this).balance,
            bridgeCost * 99,
            "excess value not refunded multichain vote collection"
        );
    }

    function testEmittingVotesMultipleTimesVoteCollectionPeriodSucceeds()
        public
    {
        uint256 proposalId = testVotingOnBasexWellSucceeds();

        vm.selectFork(BASE_FORK_ID);

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

        wormholeRelayerAdapter.setSenderChainId(BASE_WORMHOLE_CHAIN_ID);
        wormholeRelayerAdapter.setSilenceFailure(true);

        vm.selectFork(MOONBEAM_FORK_ID);
        vm.warp(crossChainVoteCollectionEndTimestamp - 1);

        vm.selectFork(BASE_FORK_ID);

        vm.expectEmit(true, true, true, true, address(voteCollection));
        emit VotesEmitted(proposalId, forVotes, againstVotes, abstainVotes);

        voteCollection.emitVotes{value: bridgeCost}(proposalId);

        vm.deal(address(this), bridgeCost);

        vm.expectEmit(true, true, true, true, address(voteCollection));
        emit VotesEmitted(proposalId, forVotes, againstVotes, abstainVotes);

        voteCollection.emitVotes{value: bridgeCost}(proposalId);
    }

    function testReceiveProposalFromRelayersSucceeds() public {
        vm.selectFork(MOONBEAM_FORK_ID);

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

            vm.selectFork(BASE_FORK_ID);

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
        vm.selectFork(MOONBEAM_FORK_ID);

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

            vm.selectFork(BASE_FORK_ID);

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

            vm.selectFork(MOONBEAM_FORK_ID);

            uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

            wormholeRelayerAdapter.setSilenceFailure(true);

            vm.deal(address(governor), gasCost);
            vm.expectEmit();
            emit MockWormholeRelayerError(
                "MultichainVoteCollection: proposal already exists"
            );

            vm.prank(address(governor));
            wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
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

        vm.selectFork(BASE_FORK_ID);

        (
            ,
            ,
            ,
            uint256 crossChainVoteCollectionEndTimestamp,
            ,
            ,
            ,

        ) = voteCollection.proposalInformation(proposalId);

        wormholeRelayerAdapter.setSenderChainId(BASE_WORMHOLE_CHAIN_ID);

        vm.warp(crossChainVoteCollectionEndTimestamp + 1);
        vm.expectRevert(
            "MultichainVoteCollection: Voting collection phase has ended"
        );
        voteCollection.emitVotes(proposalId);
    }

    /// upgrading contract logic

    function testUpgradeMultichainGovernorThroughGovProposal() public {
        vm.selectFork(MOONBEAM_FORK_ID);
        wormholeRelayerAdapter.setIsMultichainTest(false);

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
        uint256 startingGovernorBalance = address(governor).balance;

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
                startingGovernorBalance,
                "incorrect governor balance"
            );
            assertEq(uint256(governor.state(proposalId)), 5, "not in executed");
            assertEq(
                MockMultichainGovernor(payable(governor)).newFeature(),
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
        vm.selectFork(BASE_FORK_ID);

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
            vm.selectFork(BASE_FORK_ID);
            temporalGov = TemporalGovernor(
                payable(addresses.getAddress("TEMPORAL_GOVERNOR"))
            );
            /// artemis timelock does not start off as trusted sender
            assertFalse(
                temporalGov.isTrustedSender(
                    uint16(MOONBEAM_WORMHOLE_CHAIN_ID),
                    addresses.getAddress(
                        "MOONBEAM_TIMELOCK",
                        block.chainid.toMoonbeamChainId()
                    )
                ),
                "artemis timelock should not be trusted sender"
            );
        }

        vm.selectFork(MOONBEAM_FORK_ID);
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
        address[] memory targets = new address[](20);
        bytes[] memory calldatas = new bytes[](20);

        targets[0] = addresses.getAddress("WORMHOLE_CORE");
        calldatas[0] = proposalC.approvedCalldata(0);

        targets[1] = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");
        calldatas[1] = transferOwnershipCalldata;

        targets[2] = addresses.getAddress("MOONBEAM_PROXY_ADMIN");
        calldatas[2] = transferOwnershipCalldata;

        targets[3] = addresses.getAddress("xWELL_PROXY");
        calldatas[3] = transferOwnershipCalldata;

        targets[4] = addresses.getAddress("CHAINLINK_ORACLE");
        calldatas[4] = changeAdminCalldata;

        targets[5] = addresses.getAddress("STK_GOVTOKEN_PROXY");
        calldatas[5] = setEmissionsManagerCalldata;

        targets[6] = addresses.getAddress("UNITROLLER");
        calldatas[6] = _setPendingAdminCalldata;

        targets[7] = addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER");
        calldatas[7] = transferOwnershipCalldata;

        targets[8] = addresses.getAddress("DEPRECATED_MOONWELL_mWBTC");
        calldatas[8] = _setPendingAdminCalldata;

        targets[9] = addresses.getAddress("MOONWELL_mBUSD");
        calldatas[9] = _setPendingAdminCalldata;

        targets[10] = addresses.getAddress("DEPRECATED_MOONWELL_mETH");
        calldatas[10] = _setPendingAdminCalldata;

        targets[11] = addresses.getAddress("MOONWELL_mUSDC");
        calldatas[11] = _setPendingAdminCalldata;

        targets[12] = addresses.getAddress("MNATIVE");
        calldatas[12] = _setPendingAdminCalldata;

        targets[13] = addresses.getAddress("mxcDOT");
        calldatas[13] = _setPendingAdminCalldata;

        targets[14] = addresses.getAddress("mxcUSDT");
        calldatas[14] = _setPendingAdminCalldata;

        targets[15] = addresses.getAddress("mFRAX");
        calldatas[15] = _setPendingAdminCalldata;

        targets[16] = addresses.getAddress("mUSDCwh");
        calldatas[16] = _setPendingAdminCalldata;

        targets[17] = addresses.getAddress("MOONWELL_mWBTC");
        calldatas[17] = _setPendingAdminCalldata;

        targets[18] = addresses.getAddress("mxcUSDC");
        calldatas[18] = _setPendingAdminCalldata;

        targets[19] = addresses.getAddress("MOONWELL_mETH");
        calldatas[19] = _setPendingAdminCalldata;

        bytes[] memory temporalGovCalldatas = new bytes[](1);
        bytes memory temporalGovExecData;
        {
            address temporalGovAddress = addresses.getAddress(
                "TEMPORAL_GOVERNOR",
                BASE_CHAIN_ID
            );
            address wormholeCore = addresses.getAddress("WORMHOLE_CORE");
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
            IStakedWellUplift(addresses.getAddress("STK_GOVTOKEN_PROXY"))
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
            Timelock(addresses.getAddress("MNATIVE")).pendingAdmin(),
            artemisTimelockAddress,
            "MNATIVE pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MNATIVE")).admin(),
            address(governor),
            "MNATIVE admin incorrect"
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
            Timelock(addresses.getAddress("DEPRECATED_MOONWELL_mWBTC"))
                .pendingAdmin(),
            artemisTimelockAddress,
            "DEPRECATED_MOONWELL_mWBTC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("DEPRECATED_MOONWELL_mWBTC")).admin(),
            address(governor),
            "DEPRECATED_MOONWELL_mWBTC admin incorrect"
        );

        /// only test this condition if MIP-M32 passes
        if (
            Timelock(addresses.getAddress("MOONWELL_mWBTC")).pendingAdmin() ==
            address(0)
        ) {
            assertEq(
                Timelock(addresses.getAddress("MOONWELL_mWBTC")).pendingAdmin(),
                artemisTimelockAddress,
                "MOONWELL_mWBTC pending admin incorrect"
            );
            assertEq(
                Timelock(addresses.getAddress("MOONWELL_mWBTC")).admin(),
                address(governor),
                "MOONWELL_mWBTC admin incorrect"
            );
        }

        assertEq(
            Timelock(addresses.getAddress("DEPRECATED_MOONWELL_mETH"))
                .pendingAdmin(),
            artemisTimelockAddress,
            "DEPRECATED_MOONWELL_mETH pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("DEPRECATED_MOONWELL_mETH")).admin(),
            address(governor),
            "DEPRECATED_MOONWELL_mETH admin incorrect"
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

        vm.selectFork(BASE_FORK_ID);
        temporalGov = TemporalGovernor(
            payable(addresses.getAddress("TEMPORAL_GOVERNOR"))
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
                uint16(MOONBEAM_WORMHOLE_CHAIN_ID),
                artemisTimelockAddress
            ),
            "artemis timelock not added as a trusted sender"
        );
    }

    /// staking

    /// - assert assets in ecosystem reserve deplete when rewards are claimed

    function testStakestkWellBaseSucceedsAndReceiveRewards() public {
        vm.selectFork(BASE_FORK_ID);

        /// prank as the wormhole bridge adapter contract
        ///
        uint256 mintAmount = 1_000_000 * 1e18;
        IStakedWellUplift stkwell = IStakedWellUplift(
            addresses.getAddress("STK_GOVTOKEN_PROXY")
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
        vm.selectFork(BASE_FORK_ID);

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
            addresses.getAddress("STK_GOVTOKEN_PROXY")
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
        vm.selectFork(MOONBEAM_FORK_ID);

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

        vm.selectFork(MOONBEAM_FORK_ID);

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

    receive() external payable {}
}
