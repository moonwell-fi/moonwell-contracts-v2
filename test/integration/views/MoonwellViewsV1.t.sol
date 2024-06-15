pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MoonwellViewsV1} from "@protocol/views/MoonwellViewsV1.sol";
import {MToken} from "@protocol/MToken.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";

contract MoonwellViewsV1Test is Test, PostProposalCheck {
    MoonwellViewsV1 public viewsContract;

    address public user = 0xd7854FC91f16a58D67EC3644981160B6ca9C41B8;
    address public proxyAdmin = address(1337);

    address public comptroller;
    address public tokenSaleDistributor;
    address public safetyModule;
    address public governanceToken;
    address public nativeMarket;
    address public governanceTokenLP;

    mapping(address => uint) public userTotalRewards;
    address[] public userRewardTokens;

    function setUp() public override {
        super.setUp();

        comptroller = addresses.getAddress("UNITROLLER");
        tokenSaleDistributor = addresses.getAddress("TOKENSALE");
        safetyModule = addresses.getAddress("STKGOVTOKEN");
        governanceToken = addresses.getAddress("GOVTOKEN");
        nativeMarket = addresses.getAddress("MNATIVE");
        governanceTokenLP = addresses.getAddress("GOVTOKEN_LP");

        viewsContract = new MoonwellViewsV1();

        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address)",
            comptroller,
            tokenSaleDistributor,
            safetyModule,
            governanceToken,
            nativeMarket,
            governanceTokenLP
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(viewsContract),
            proxyAdmin,
            initdata
        );

        /// wire proxy up
        viewsContract = MoonwellViewsV1(address(proxy));
        vm.rollFork(4717310);
    }

    function testComptrollerIsSet() public view {
        address _addy = address(viewsContract.comptroller());
        assertEq(_addy, comptroller);
    }

    function testMarketsSize() public view {
        MoonwellViewsV1.Market memory _market = viewsContract.getMarketInfo(
            MToken(0x091608f4e4a15335145be0A279483C0f8E4c7955)
        );

        assertEq(_market.isListed, true);
    }

    function testUserVotingPower() public view {
        MoonwellViewsV1.UserVotes memory _votes = viewsContract
            .getUserVotingPower(user);

        assertEq(
            _votes.stakingVotes.votingPower +
                _votes.tokenVotes.votingPower +
                _votes.claimsVotes.votingPower,
            5000001 * 1e18
        );
    }

    function testUserStakingInfo() public view {
        MoonwellViewsV1.UserStakingInfo memory _stakingInfo = viewsContract
            .getUserStakingInfo(user);

        assertEq(_stakingInfo.pendingRewards, 29708560610101962);
        assertEq(_stakingInfo.totalStaked, 1000000000000000000);
    }

    function testUserRewards() public {
        MoonwellViewsV1.Rewards[] memory _rewards = viewsContract
            .getUserRewards(user);

        for (uint index = 0; index < _rewards.length; index++) {
            bool exists = userTotalRewards[_rewards[index].rewardToken] > 0;
            userTotalRewards[_rewards[index].rewardToken] =
                userTotalRewards[_rewards[index].rewardToken] +
                (_rewards[index].supplyRewardsAmount +
                    _rewards[index].borrowRewardsAmount);

            if (!exists) {
                userRewardTokens.push(_rewards[index].rewardToken);
            }
        }
        assertEq(
            userTotalRewards[0x511aB53F793683763E5a8829738301368a2411E3],
            11526274217013010874
        );
        assertEq(
            userTotalRewards[0x0000000000000000000000000000000000000000],
            575610171267701893
        );
    }
}
