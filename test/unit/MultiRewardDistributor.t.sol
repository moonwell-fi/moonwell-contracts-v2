pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@protocol/MultiRewardDistributor/MultiRewardDistributor.sol";
import {MToken} from "@protocol/MToken.sol";
import {FaucetToken, FaucetTokenWithPermit} from "@test/helper/FaucetToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Immutable} from "@test/mock/MErc20Immutable.sol";
import {InterestRateModel} from "@protocol/IRModels/InterestRateModel.sol";
import {SimplePriceOracle} from "@test/helper/SimplePriceOracle.sol";
import {WhitePaperInterestRateModel} from "@protocol/IRModels/WhitePaperInterestRateModel.sol";

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin-contracts/contracts/utils/Strings.sol";

contract Common is Test, MultiRewardDistributorCommon {
    Comptroller comptroller;
    SimplePriceOracle oracle;
    FaucetTokenWithPermit faucetToken;
    FaucetTokenWithPermit emissionToken;
    MErc20Immutable mToken;
    InterestRateModel irModel;
    address public constant proxyAdmin = address(1337);

    struct User {
        address addr;
        uint256 supplied;
        uint256 borrowed;
    }

    function setupEnvironment() internal {
        comptroller = new Comptroller();
        oracle = new SimplePriceOracle();
        faucetToken = new FaucetTokenWithPermit(0, "Testing", 18, "TEST");
        irModel = new WhitePaperInterestRateModel(0.1e18, 0.45e18);

        mToken = new MErc20Immutable(
            address(faucetToken),
            comptroller,
            irModel,
            1e18, // Exchange rate is 1:1 for tests
            "Test mToken",
            "mTEST",
            8,
            payable(address(this))
        );

        comptroller._setPriceOracle(oracle);
        comptroller._supportMarket(mToken);
        oracle.setUnderlyingPrice(mToken, 1e18);

        comptroller._setCollateralFactor(mToken, 0.5e18); // 50% CF

        emissionToken = new FaucetTokenWithPermit(
            0,
            "Emission Token",
            18,
            "EMIT"
        );
    }

    function assertInitialMarketState(
        MultiRewardDistributor distributor,
        uint256 endTime
    ) internal {
        MarketConfig memory config = distributor.marketConfigs(
            address(mToken),
            0
        );

        assertEq(MTokenInterface(mToken).totalSupply(), 0);

        assertEq(config.owner, address(this));
        assertEq(config.emissionToken, address(emissionToken));
        assertEq(config.endTime, endTime);
        assertEq(config.supplyGlobalIndex, distributor.initialIndexConstant());
        assertEq(config.supplyGlobalTimestamp, block.timestamp);
        assertEq(config.borrowGlobalIndex, 0);
        assertEq(config.borrowGlobalTimestamp, block.timestamp);
        assertEq(config.supplyEmissionsPerSec, 0.54321e18);
        assertEq(config.borrowEmissionsPerSec, 0.54321e18);
    }

    function createDistributorWithOddValuesAndConfig()
        internal
        returns (MultiRewardDistributor)
    {
        faucetToken.allocateTo(address(this), 1.2345e18);
        faucetToken.approve(address(mToken), 1.2345e18);

        MultiRewardDistributor distributor = new MultiRewardDistributor();
        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address)",
            address(comptroller),
            address(this)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(distributor),
            proxyAdmin,
            initdata
        );
        /// wire proxy up
        distributor = MultiRewardDistributor(address(proxy));

        uint256 endTime = block.timestamp + 1000;

        // Add config + send emission tokens
        emissionToken.allocateTo(address(distributor), 100e18);
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            0.54321e18,
            0.54321e18,
            endTime
        );

        return distributor;
    }

    function createDistributorWithRoundValuesAndConfig(
        uint256 tokensToMint,
        uint256 supplyEmissionsPerSecond,
        uint256 borrowEmissionsPerSecond
    ) internal returns (MultiRewardDistributor distributor) {
        faucetToken.allocateTo(address(this), tokensToMint);
        faucetToken.approve(address(mToken), tokensToMint);

        distributor = new MultiRewardDistributor();
        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address)",
            address(comptroller),
            address(this)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(distributor),
            proxyAdmin,
            initdata
        );
        /// wire proxy up
        distributor = MultiRewardDistributor(address(proxy));


        // 1 year of rewards
        uint256 endTime = block.timestamp + (60 * 60 * 24 * 365);

        // Add config + send emission tokens
        emissionToken.allocateTo(address(distributor), 100e18);
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            supplyEmissionsPerSecond,
            borrowEmissionsPerSecond,
            endTime
        );
    }

    function mint(address user, uint256 amountToSupply) public {
        faucetToken.allocateTo(address(user), amountToSupply);

        vm.prank(user);
        faucetToken.approve(address(mToken), amountToSupply);

        vm.prank(user);
        mToken.mint(amountToSupply);
    }

    function borrow(address user, uint256 amountToBorrow) public {
        vm.prank(user);
        mToken.borrow(amountToBorrow);
    }
}

contract MultiRewardBorrowSideDistributorUnitTest is
    Test,
    ExponentialNoError,
    Common
{
    function setUp() public {
        setupEnvironment();
    }

    function testBorrowerHappyPath() public {
        uint256 startTime = 1678340000;
        vm.warp(startTime);

        // Only incentivize borrowers
        MultiRewardDistributor distributor = createDistributorWithRoundValuesAndConfig(
                2e18, // Amount to give us
                1e18, // Supply side
                0.5e18 // Borrow side
            );
        emissionToken.allocateTo(address(distributor), 1000000e18);
        comptroller._setRewardDistributor(distributor);

        // Supply
        mToken.mint(2e18);

        // Enter markets
        address[] memory marketsToEnter = new address[](1);
        marketsToEnter[0] = address(mToken);
        comptroller.enterMarkets(marketsToEnter);

        assertEq(MTokenInterface(mToken).totalSupply(), 2e18);

        assertEq(faucetToken.balanceOf(address(this)), 0);

        mToken.borrow(1e18);

        // Make sure we actually borrowed 1 TEST token (50% of supplied collateral - right up to CF)
        assertEq(faucetToken.balanceOf(address(this)), 1e18);

        uint256 warpSeconds = 1;

        // fast forward 1 second
        vm.warp(block.timestamp + warpSeconds);

        comptroller.claimReward();

        // At this point we should have 600s of 1e18/s == 600e18 supply side emissions
        // and 600s of 0.5e18/s == 300e18 borrow side emissions, so 900e18 in total
        uint256 expectedEmissions1 = (warpSeconds * 0.5e18) +
            (warpSeconds * 1e18) -
            1; // -1 due to index rounding/resolution

        assertEq(emissionToken.balanceOf(address(this)), expectedEmissions1);

        warpSeconds = 1 days;
        // Wait another 24 hours
        vm.warp(block.timestamp + warpSeconds);

        comptroller.claimReward();

        // Make sure that we now have 86400 * 0.5e18 == 43,200 for supply side and 86400 * 1e18 tokens
        uint256 expectedEmissions2 = (warpSeconds * 0.5e18) +
            (warpSeconds * 1e18) -
            1; // -1 due to index rounding/resolution
        assertEq(
            emissionToken.balanceOf(address(this)),
            expectedEmissions2 + expectedEmissions1
        );
    }

    // Make sure that our events are emitted correctly
    function testBorrowEvents() public {
        uint256 startTime = 1678340000;
        vm.warp(startTime);

        MultiRewardDistributor distributor = createDistributorWithOddValuesAndConfig();

        mToken.mint(1.2345e18);
        mToken.borrow(0.5e18);

        vm.warp(startTime + 5);

        // 5 blocks @ 0.54321 tokens per second over a total of 1.2345 mTokens is
        // the total emissions per mToken, which is the root of the underlying index.
        Double memory delta1 = fraction(
            5 * 0.54321e18,
            div_(mToken.totalBorrows(), Exp({mantissa: mToken.borrowIndex()}))
        );

        // Expect a GlobalBorrowIndexUpdated event to be emitted
        vm.expectEmit(true, true, true, true);
        emit GlobalBorrowIndexUpdated(
            mToken,
            address(emissionToken),
            add_(distributor.initialIndexConstant(), delta1.mantissa),
            uint32(startTime + 5)
        );
        vm.prank(address(comptroller));
        distributor.updateMarketBorrowIndex(mToken);

        vm.warp(startTime + 10);

        Double memory delta2 = fraction(
            10 * 0.54321e18,
            div_(mToken.totalBorrows(), Exp({mantissa: mToken.borrowIndex()}))
        );

        // Make sure we emit the proper amount when updating supply index
        vm.expectEmit(true, true, true, true);
        emit GlobalBorrowIndexUpdated(
            mToken,
            address(emissionToken),
            add_(distributor.initialIndexConstant(), delta2.mantissa),
            uint32(startTime + 10)
        );
        vm.prank(address(comptroller));
        distributor.updateMarketBorrowIndex(mToken);
    }
}

contract MultiRewardSupplySideDistributorUnitTest is
    Test,
    ExponentialNoError,
    Common
{
    function setUp() public {
        setupEnvironment();
    }

    // Make sure that our events are emitted correctly
    function testEvents() public {
        uint256 startTime = 1678340000;
        vm.warp(startTime);

        MultiRewardDistributor distributor = createDistributorWithOddValuesAndConfig();

        mToken.mint(1.2345e18);

        vm.warp(startTime + 5);

        // 5 blocks @ 0.54321 tokens per second over a total of 1.2345 mTokens is
        // the total emissions per mToken, which is the root of the underlying index.
        Double memory delta1 = fraction(5 * 0.54321e18, 1.2345e18);

        // Expect a GlobalSupplyIndexUpdated event to be emitted
        vm.expectEmit(true, true, true, true);
        emit GlobalSupplyIndexUpdated(
            mToken,
            address(emissionToken),
            add_(distributor.initialIndexConstant(), delta1.mantissa),
            uint32(startTime + 5)
        );
        vm.prank(address(comptroller));
        distributor.updateMarketSupplyIndex(mToken);

        vm.warp(startTime + 10);

        Double memory delta2 = fraction(10 * 0.54321e18, 1.2345e18);

        // Make sure we emit the proper amount when updating supply index
        vm.expectEmit(true, true, true, true);
        emit GlobalSupplyIndexUpdated(
            mToken,
            address(emissionToken),
            add_(distributor.initialIndexConstant(), delta2.mantissa),
            uint32(startTime + 10)
        );
        vm.prank(address(comptroller));
        distributor.updateMarketSupplyIndex(mToken);
    }

    // Make sure that our rewards accrue correctly
    function testSupplyingBeforeRewardsPath() public {
        uint256 startTime = 1678340000;
        vm.warp(startTime);

        // Go supply to the market
        faucetToken.allocateTo(address(this), 2e18);
        faucetToken.approve(address(mToken), 2e18);
        mToken.mint(2e18);

        // THEN create the distributor and add a config
        MultiRewardDistributor distributor = createDistributorWithRoundValuesAndConfig(
                2e18,
                0.5e18,
                0.5e18
            );

        // Make sure we have an expected amt of mTokens issued
        assertEq(MTokenInterface(mToken).totalSupply(), 2e18);

        // Wait 10 blocks after depositing
        vm.warp(startTime + 10);

        // Update market supply index again after fast forwarding
        vm.prank(address(comptroller));
        distributor.updateMarketSupplyIndex(mToken);

        // Claim rewards
        vm.prank(address(comptroller));
        distributor.disburseSupplierRewards(mToken, address(this), true);

        // Make sure that we have (10 seconds * 0.5 tokens / sec) == 5 tokens disbursed to us
        assertEq(emissionToken.balanceOf(address(this)), 5e18);
    }

    function testSupplierHappyPath() public {
        uint256 startTime = 1678340000;
        vm.warp(startTime);

        MultiRewardDistributor distributor = createDistributorWithRoundValuesAndConfig(
                2e18,
                0.5e18,
                0.5e18
            );
        comptroller._setRewardDistributor(distributor);

        emissionToken.allocateTo(address(distributor), 10000e18);

        vm.warp(block.timestamp + 1);

        mToken.mint(2e18);
        assertEq(MTokenInterface(mToken).totalSupply(), 2e18);

        // Wait 12345 seconds after depositing
        vm.warp(block.timestamp + 12345);

        // Go claim
        comptroller.claimReward();

        // Make sure that we have (12345 seconds * 0.5 tokens / sec) == 6,172.5 tokens disbursed to us
        assertEq(emissionToken.balanceOf(address(this)), 6172.5e18);

        // Make sure claiming again doesn't do anything
        comptroller.claimReward();

        // Make sure that we still have the same amt
        assertEq(emissionToken.balanceOf(address(this)), 6172.5e18);
    }

    function testSupplierAndBorrowerHappyPath() public {
        uint256 startTime = 1678340000;
        vm.warp(startTime);

        MultiRewardDistributor distributor = createDistributorWithRoundValuesAndConfig(
                2e18,
                0.5e18,
                0.5e18
            );
        comptroller._setRewardDistributor(distributor);

        emissionToken.allocateTo(address(distributor), 10000e18);

        vm.warp(block.timestamp + 1);

        mToken.mint(2e18);
        assertEq(MTokenInterface(mToken).totalSupply(), 2e18);
        comptroller.claimReward();

        // Wait 12345 seconds after depositing
        vm.warp(block.timestamp + 12345);

        // Go claim
        comptroller.claimReward();

        // Make sure that we have (12345 seconds * 0.5 tokens / sec) == 6,172.5 tokens disbursed to us
        assertEq(emissionToken.balanceOf(address(this)), 6172.5e18);

        // Make sure claiming again doesn't do anything
        comptroller.claimReward();

        // Make sure that we still have the same amt
        assertEq(emissionToken.balanceOf(address(this)), 6172.5e18);
    }

    function testMultiRewardEmitterWithOddInputs() public {
        uint256 startTime = 1678340000;
        vm.warp(startTime);

        MultiRewardDistributor distributor = createDistributorWithOddValuesAndConfig();

        mToken.mint(1.2345e18);

        assertEq(MTokenInterface(mToken).totalSupply(), 1.2345e18);

        vm.warp(startTime + 5);

        // 5 blocks @ 0.54321 tokens per second over a total of 1.2345 mTokens is
        // the total emissions per mToken, which is the root of the underlying index.
        Double memory delta1 = fraction(5 * 0.54321e18, 1.2345e18);

        // Expect a GlobalSupplyIndexUpdated event to be emitted
        vm.expectEmit(true, true, true, true);
        emit GlobalSupplyIndexUpdated(
            mToken,
            address(emissionToken),
            add_(distributor.initialIndexConstant(), delta1.mantissa),
            uint32(startTime + 5)
        );

        vm.prank(address(comptroller));
        distributor.updateMarketSupplyIndex(mToken);

        vm.warp(startTime + 10);

        Double memory delta2 = fraction(10 * 0.54321e18, 1.2345e18);

        // Make sure we emit the proper amount when updating supply index
        vm.expectEmit(true, true, true, true);
        emit GlobalSupplyIndexUpdated(
            mToken,
            address(emissionToken),
            add_(distributor.initialIndexConstant(), delta2.mantissa),
            uint32(startTime + 10)
        );
        vm.prank(address(comptroller));
        distributor.updateMarketSupplyIndex(mToken);

        // Go disburse the amount
        Double memory delta3 = fraction(10 * 0.54321e18, 1.2345e18);
        uint256 supplierTokens = MTokenInterface(mToken).balanceOf(
            address(this)
        );
        uint256 expectedSupplierRewards = mul_(supplierTokens, delta3);

        // Emissions are (4400243013365735115431348724179829890 / 1e36) * (1234500000000000000 / 1e18) or 4.4002430134 * 1.2345 == 5.4321
        vm.prank(address(comptroller));
        distributor.disburseSupplierRewards(mToken, address(this), true);

        // Should have disbursed 10 emission tokens to us
        assertEq(
            emissionToken.balanceOf(address(this)),
            expectedSupplierRewards
        );
    }

    function testMultipleEmissionTokens() public {
        uint256 EMISSION_TOKEN_1 = 1e18;
        uint256 EMISSION_TOKEN_2 = 1e10;

        FaucetToken emissionToken2 = new FaucetTokenWithPermit(
            0,
            "Testing2",
            10,
            "TEST2"
        );

        uint256 startTime = 1678340000;
        vm.warp(startTime);

        MultiRewardDistributor distributor = new MultiRewardDistributor();
        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address)",
            address(comptroller),
            address(this)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(distributor),
            proxyAdmin,
            initdata
        );
        /// wire proxy up
        distributor = MultiRewardDistributor(address(proxy));


        emissionToken.allocateTo(address(distributor), EMISSION_TOKEN_1 * 100);

        // Use a 10 digit mantissa token
        emissionToken2.allocateTo(address(distributor), EMISSION_TOKEN_2 * 100);

        uint256 endTime = block.timestamp + 1000;

        // Emit 1 token per second
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            EMISSION_TOKEN_1,
            EMISSION_TOKEN_1,
            endTime
        );

        faucetToken.approve(address(mToken), EMISSION_TOKEN_1 * 10);
        faucetToken.allocateTo(address(this), EMISSION_TOKEN_1 * 10);
        mToken.mint(EMISSION_TOKEN_1 * 10);

        // Fast forward 10s, then add a new config
        vm.warp(startTime + 10);

        // Emit 1 token per second
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken2),
            EMISSION_TOKEN_2,
            EMISSION_TOKEN_2,
            endTime
        );

        // Fast forward 20s, then update rewards and check things out
        vm.warp(startTime + 20);

        // Update indexes and and claim rewards
        vm.prank(address(comptroller));
        distributor.updateMarketSupplyIndex(mToken);

        assertEq(emissionToken.balanceOf(address(this)), 0);
        assertEq(emissionToken2.balanceOf(address(this)), 0);

        vm.prank(address(comptroller));
        distributor.disburseSupplierRewards(mToken, address(this), true);

        // Ensure we got paid out in the tokens we expected, 20 timestamps worth of token 1 and 10 timestamps of token 2
        assertEq(emissionToken.balanceOf(address(this)), EMISSION_TOKEN_1 * 20); // 20 secs worth of accrual @ 1 token/sec == 20 tokens
        assertEq(
            emissionToken2.balanceOf(address(this)),
            EMISSION_TOKEN_2 * 10
        ); // 10 secs worth of accrual @ 1 token/sec == 10 tokens
    }

    function testOutstandingRewardCalcs() public {
        uint256 startTime = 1678340000;
        vm.warp(startTime);

        MultiRewardDistributor distributor = createDistributorWithOddValuesAndConfig();
        comptroller._setRewardDistributor(distributor);

        mToken.mint(1.2345e18);

        uint256 timeDelta1 = 10;
        vm.warp(startTime + timeDelta1);

        RewardWithMToken[] memory rewardInfo = distributor
            .getOutstandingRewardsForUser(address(this));

        assertEq(rewardInfo.length, 1);
        assertEq(rewardInfo[0].rewards.length, 1);
        assertEq(
            rewardInfo[0].rewards[0].emissionToken,
            address(emissionToken)
        );
        assertEq(
            rewardInfo[0].rewards[0].totalAmount,
            (0.54321e18 * timeDelta1) - 1
        );
        assertEq(
            rewardInfo[0].rewards[0].supplySide,
            (0.54321e18 * timeDelta1) - 1
        );
        assertEq(rewardInfo[0].rewards[0].borrowSide, 0);

        uint256 timeDelta2 = 20;
        vm.warp(startTime + timeDelta2);

        RewardInfo[] memory rewards = distributor.getOutstandingRewardsForUser(
            mToken,
            address(this)
        );

        assertEq(rewards.length, 1);
        assertEq(rewards[0].emissionToken, address(emissionToken));
        assertEq(rewards[0].totalAmount, (0.54321e18 * timeDelta2) - 1);
        assertEq(rewards[0].supplySide, (0.54321e18 * timeDelta2) - 1);
        assertEq(rewards[0].borrowSide, 0);
    }

    function testOutstandingRewardCalcsOneSecond() public {
        uint256 startTime = 1678340000;
        vm.warp(startTime);
        MultiRewardDistributor distributor = createDistributorWithOddValuesAndConfig();
        comptroller._setRewardDistributor(distributor);

        mToken.mint(1.2345e18);

        uint256 timeDelta1 = 100;
        vm.warp(block.timestamp + timeDelta1);

        RewardInfo[] memory rewardInfo = distributor
            .getOutstandingRewardsForUser(mToken, address(this));

        assertEq(rewardInfo[0].totalAmount, (0.54321e18 * timeDelta1) - 1);
        assertEq(rewardInfo[0].supplySide, (0.54321e18 * timeDelta1) - 1);
        assertEq(rewardInfo[0].borrowSide, 0);

        uint256 timeDelta2 = 200;
        vm.warp(block.timestamp + timeDelta2);

        rewardInfo = distributor.getOutstandingRewardsForUser(
            mToken,
            address(this)
        );

        assertEq(rewardInfo[0].borrowSide, 0);
        assertEq(
            rewardInfo[0].totalAmount,
            (0.54321e18 * (timeDelta1 + timeDelta2) - 1)
        );
        assertEq(
            rewardInfo[0].supplySide,
            (0.54321e18 * (timeDelta1 + timeDelta2) - 1)
        );
    }

    function testLotsOfEmissionTokens() public {
        uint256 startTime = 1678340000;
        vm.warp(startTime);

        MultiRewardDistributor distributor = new MultiRewardDistributor();
        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address)",
            address(comptroller),
            address(this)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(distributor),
            proxyAdmin,
            initdata
        );
        /// wire proxy up
        distributor = MultiRewardDistributor(address(proxy));

        comptroller._setRewardDistributor(distributor);

        uint256 ITERATION_COUNT = 10;

        FaucetToken[] memory emissionTokens = new FaucetToken[](
            ITERATION_COUNT
        );

        uint256 endTime = block.timestamp + 1000;
        for (uint256 i = 0; i < ITERATION_COUNT; i++) {
            FaucetToken multiEmissionToken = new FaucetTokenWithPermit(
                0,
                "Testing Token",
                10,
                string(abi.encodePacked("TEST", i))
            );

            distributor._addEmissionConfig(
                mToken,
                address(this),
                address(multiEmissionToken),
                1e18 * (i + 1),
                2e18 * (i + 1),
                endTime
            );

            multiEmissionToken.allocateTo(address(distributor), 100000e18);

            emissionTokens[i] = multiEmissionToken;
        }

        faucetToken.allocateTo(address(this), 10e18);
        faucetToken.approve(address(mToken), 10e18);
        mToken.mint(10e18);

        vm.warp(startTime + ITERATION_COUNT);

        // Currently 700,000+ gas to claim with nothing here
        comptroller.claimReward();

        for (uint256 i = 0; i < emissionTokens.length; i++) {
            assertEq(
                emissionTokens[i].balanceOf(address(this)),
                1e18 * ITERATION_COUNT * (i + 1)
            );   
        }
    }

    function testDifferentNumOfSuppliers() public {
        uint256 USERS = 10;
        address[10] memory users;

        MultiRewardDistributor distributor = new MultiRewardDistributor();
        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address)",
            address(comptroller),
            address(this)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(distributor),
            proxyAdmin,
            initdata
        );
        /// wire proxy up
        distributor = MultiRewardDistributor(address(proxy));

        comptroller._setRewardDistributor(distributor);

        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            1e18,
            0,
            block.timestamp + 1000
        );
        emissionToken.allocateTo(address(distributor), 100000e18);

        for (uint256 i = 0; i < USERS; i++) {
            address user = vm.addr(i + 1);

            // Everyone deposits 10 tokens
            faucetToken.allocateTo(address(user), (i + 1) * 1e18);

            vm.prank(user);
            faucetToken.approve(address(mToken), (i + 1) * 1e18);

            vm.prank(user);
            mToken.mint((i + 1) * 1e18);

            users[i] = user;
        }

        uint256 SLEEP_TIME = 123;
        vm.warp(block.timestamp + SLEEP_TIME);

        for (uint256 i = 0; i < USERS; i++) {
            // Get the total amount of deposits -  (n * (n + 1)) / 2
            uint256 total = (USERS * (USERS + 1)) / 2;

            // The user's ratible portion of the supply-side emissions, (# of tokens supplied) / (total tokens supplied)
            Double memory frac = fraction((i + 1) * 1e18, total * 1e18);
            // Multiply by the amount of seconds that have elapsed
            Double memory emissions = div_(mul_(frac, SLEEP_TIME), 1e18);

            // Claim rewards for this user
            vm.prank(users[i]);
            comptroller.claimReward();

            assertEq(emissionToken.balanceOf(users[i]), emissions.mantissa);
        }
    }
}

contract MultiRewardDistributorCommonUnitTest is Test, ExponentialNoError, Common {
    MultiRewardDistributor distributor;

    function setUp() public {
        setupEnvironment();
        distributor = new MultiRewardDistributor();
        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address)",
            address(comptroller),
            address(this)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(distributor),
            proxyAdmin,
            initdata
        );
        /// wire proxy up
        distributor = MultiRewardDistributor(address(proxy));

        comptroller._setRewardDistributor(distributor);
    }

    function testDoubleClaiming() public {
        faucetToken.allocateTo(address(this), 2e18);
        faucetToken.approve(address(mToken), 2e18);

        // Supply some tokens
        mToken.mint(2e18);
        mToken.borrow(0.5e18);

        // 10 min emission window
        uint256 endTime = block.timestamp + 600;

        // Add config + send emission tokens
        emissionToken.allocateTo(address(distributor), 1_000_000e18);
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            0.5e18,
            0.5e18,
            endTime
        );

        // Sleep for 1s, then make sure we only accrue 1 token (0.5 for borrow 0.5 for supply)
        vm.warp(block.timestamp + 100);
        assertEq(emissionToken.balanceOf(address(this)), 0);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 100e18);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 100e18);

        // Try to multi-claim right on the block that breaches the end time
        vm.warp(block.timestamp + 500);
        assertEq(emissionToken.balanceOf(address(this)), 100e18);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 600e18);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 600e18);
    }

    function testRewardsEndingTime() public {
        faucetToken.allocateTo(address(this), 2e18);
        faucetToken.approve(address(mToken), 2e18);

        // Supply some tokens
        mToken.mint(2e18);
        mToken.borrow(0.5e18);

        // 10 min emission window
        uint256 endTime = block.timestamp + 600;

        // Add config + send emission tokens
        emissionToken.allocateTo(address(distributor), 1_000_000e18);
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            0.5e18,
            0.5e18,
            endTime
        );

        // Sleep for 1s, then make sure we've accrued 100 TEST tokens
        vm.warp(block.timestamp + 1);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 1e18);

        // Sleep for 100s, then make sure we've accrued 100 TEST tokens
        vm.warp(block.timestamp + 99);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 100e18);

        vm.warp(block.timestamp + 499);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 599e18);

        vm.warp(block.timestamp + 1);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 600e18);

        // Sleep for 1s, then make sure we haven't accrued any new tokens
        vm.warp(block.timestamp + 1);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 600e18);

        // Sleep for another 100s, then make sure we haven't accrued any new tokens
        vm.warp(block.timestamp + 100);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 600e18);
    }

    function testEndTimeValidation() public {
        vm.expectRevert(bytes("The _endTime parameter must be in the future!"));

        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            0.5e18,
            0.5e18,
            block.timestamp - 1 // Make sure this is checked and fails
        );
    }

    function testRenewingRewards() public {
        faucetToken.allocateTo(address(this), 2e18);
        faucetToken.approve(address(mToken), 2e18);

        // Supply & borrow some tokens
        mToken.mint(2e18);
        mToken.borrow(0.5e18);

        // 10 min initial emission window
        uint256 endTime = block.timestamp + 600;

        // Add config + send emission tokens
        emissionToken.allocateTo(address(distributor), 1_000_000e18);
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            0.5e18,
            0.5e18,
            endTime
        );
        comptroller.claimReward();

        // Sleep for 500s, then make sure we've accrued 500 TEST tokens
        vm.warp(block.timestamp + 500);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 500e18);

        // Make sure we don't accrue additional rewards when breaching the endTime by a bit
        vm.warp(block.timestamp + 101);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 600e18);

        // Make sure we don't accrue anything
        vm.warp(block.timestamp + 100);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 600e18);

        // Turn on emissions for 100 more seconds
        distributor._updateEndTime(
            mToken,
            address(emissionToken),
            block.timestamp + 100
        );

        // Accrue some rewards and claim them
        vm.warp(block.timestamp + 50);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 650e18);

        // Accrue some rewards and claim them
        vm.warp(block.timestamp + 49);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 699e18);

        // Accrue some rewards and claim them
        vm.warp(block.timestamp + 1);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 700e18);

        // Ensure that we get the proper amount out, but no more
        vm.warp(block.timestamp + 1);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 700e18);
    }

    function testPauseGuardian() public {
        uint256 startTime = 1678340000;
        vm.warp(startTime);

        // Wire up a different distributor
        distributor = createDistributorWithRoundValuesAndConfig(
            2e18,
            0.5e18,
            0.5e18
        );
        comptroller._setRewardDistributor(distributor);

        vm.warp(block.timestamp + 10);

        // Supply some tokens
        mToken.mint(2e18);

        // Wait 10 seconds and claim, then make sure we've accrued 5 tokens (10 seconds * 0.5 tokens)
        vm.warp(block.timestamp + 10);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 5e18);

        // Pause emissions
        distributor._pauseRewards();

        // Fast forward again and try to claim again, asserting that our balances haven't changed
        vm.warp(block.timestamp + 10);
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 5e18);

        // Unpause guardian
        distributor._unpauseRewards();

        // Claim again, but this time make sure that we get our expected 5 tokens out
        comptroller.claimReward();
        assertEq(emissionToken.balanceOf(address(this)), 10e18);
    }

    // Calculates the ratible share of emissions this user should have received
    function expectedTotalEmissions(
        User memory user,
        uint256 totalSupplied,
        uint256 totalBorrows,
        uint256 SUPPLY_SPEED,
        uint256 BORROW_SPEED,
        uint256 TIME_DELTA
    ) public pure returns (uint256) {
        uint256 supplyRatio = fraction(user.supplied, totalSupplied).mantissa;
        uint256 supplySideEmissions = (SUPPLY_SPEED *
            TIME_DELTA *
            supplyRatio) / 1e36;
        
        uint256 borrowRatio = fraction(user.borrowed, totalBorrows).mantissa;
        uint256 borrowSideEmissions = (BORROW_SPEED *
            TIME_DELTA *
            borrowRatio) / 1e36;

        return borrowSideEmissions + supplySideEmissions;
    }

    // Go make sure that a pool of 10 users who supply and borrow at various
    // numbers actually get their expected ratable share of the rewards being
    // emitted over that timeframe.
    //
    // Also, fuzz the supply and borrow speeds to make sure things are accurate
    // to a 1e6 (0.0000000000001 of an 18 digit token)
    function testVariousSuppliersAndBorrowers(
        uint256 SUPPLY_SPEED,
        uint256 BORROW_SPEED
    ) public returns (User[10] memory) {
        // Ensure we don't generate test cases that will go above emission caps
        vm.assume(SUPPLY_SPEED < distributor.getCurrentEmissionCap());
        vm.assume(BORROW_SPEED < distributor.getCurrentEmissionCap());

        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            SUPPLY_SPEED,
            BORROW_SPEED,
            block.timestamp + (60 * 60 * 24 * 365) // 1 yr
        );
        emissionToken.allocateTo(address(distributor), type(uint256).max);

        User[10] memory users;

        // Supplies 1.5 TEST to the market, no borrowing
        users[0] = User(vm.addr(1), 1.5e18, 0);
        mint(users[0].addr, users[0].supplied);

        // Supplies 8.5 TEST to the market, no borrowing
        users[1] = User(vm.addr(2), 8.5e18, 0);
        mint(users[1].addr, users[1].supplied);

        // Supplies 30 TEST to the market, no borrowing
        users[2] = User(vm.addr(3), 30e18, 0);
        mint(users[2].addr, users[2].supplied);

        // Supplies 60 TEST to the market, no borrowing
        users[3] = User(vm.addr(4), 60e18, 0);
        mint(users[3].addr, users[3].supplied);

        // Supplies 100 TEST to the market, no borrowing
        users[4] = User(vm.addr(5), 100e18, 0);
        mint(users[4].addr, users[4].supplied);

        // Supplies 4 TEST to the market, borrows 1.5 TEST
        users[5] = User(vm.addr(6), 4e18, 1.25e18);
        mint(users[5].addr, users[5].supplied);
        borrow(users[5].addr, users[5].borrowed);

        // Supplies 8.5 TEST to the market, borrows 3.75 TEST
        users[6] = User(vm.addr(7), 8.5e18, 3.75e18);
        mint(users[6].addr, users[6].supplied);
        borrow(users[6].addr, users[6].borrowed);

        // Supplies 30 TEST to the market, borrows 10 TEST
        users[7] = User(vm.addr(8), 30e18, 10e18);
        mint(users[7].addr, users[7].supplied);
        borrow(users[7].addr, users[7].borrowed);

        // Supplies 60 TEST to the market, borrows 25 TEST
        users[8] = User(vm.addr(9), 60e18, 25e18);
        mint(users[8].addr, users[8].supplied);
        borrow(users[8].addr, users[8].borrowed);

        // Supplies 100 TEST to the market, borrows 40 TEST
        users[9] = User(vm.addr(10), 100e18, 40e18);
        mint(users[9].addr, users[9].supplied);
        borrow(users[9].addr, users[9].borrowed);

        // Wait 10 minutes
        uint256 TIME_DELTA = 600;
        vm.warp(block.timestamp + TIME_DELTA);

        // Tally up total supplied/borrowed
        uint256 totalSupplied = (mToken.totalSupply() *
            mToken.exchangeRateStored()) / 1e18;
        uint256 totalBorrows = mToken.totalBorrows();

        // Go calculate our expected emissions and ensure when we call claimReward() it's the
        // expected value within a margin of error
        for (uint256 i = 0; i < users.length; i++) {
            // Go claim rewards
            vm.prank(users[i].addr);
            comptroller.claimReward();

            // Ensure that we got an expected/ratable portion of the pool disbursed for every user's position
            uint256 expectedEmissions = expectedTotalEmissions(
                users[i],
                totalSupplied,
                totalBorrows,
                SUPPLY_SPEED,
                BORROW_SPEED,
                TIME_DELTA
            );

            uint256 actualEmissions = emissionToken.balanceOf(users[i].addr);
            uint256 delta;

            if (actualEmissions >= expectedEmissions) {
                delta = actualEmissions - expectedEmissions;
            } else {
                delta = expectedEmissions - actualEmissions;
            }

            // Go make sure our 2 calcs generally agree with eachother
            assertLe(
                delta,
                1e6 // Due to truncation our calcs might be off by a wei or two of rounding error. Make sure we're
                // within a variance band of 1e6 wei (0.0000000000001 of an 18 digit token)
            );
        }

        return users;
    }

    function testSupplyAddConfigEmissionCaps() public {
        uint256 currentEmissionCap = distributor.getCurrentEmissionCap();

        // Ensure that we fail to set a supply speed beyond the emission cap
        vm.expectRevert(
            "Cannot set a supply reward speed higher than the emission cap!"
        );
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            currentEmissionCap + 1,
            currentEmissionCap - 1,
            block.timestamp + (60 * 60 * 24 * 365) // 1 yr
        );
    }

    function testBorrowAddConfigEmissionCaps() public {
        uint256 currentEmissionCap = distributor.getCurrentEmissionCap();

        // Ensure that we fail to set a borrow speed beyond the emission cap
        vm.expectRevert(
            "Cannot set a borrow reward speed higher than the emission cap!"
        );
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            currentEmissionCap - 1,
            currentEmissionCap + 1,
            block.timestamp + (60 * 60 * 24 * 365) // 1 yr
        );
    }

    function testBothSupplyAndBorrowAddConfigEmissionCaps() public {
        uint256 currentEmissionCap = distributor.getCurrentEmissionCap();

        // Ensure that we fail to set a supply speed beyond the emission cap
        vm.expectRevert(
            "Cannot set a supply reward speed higher than the emission cap!"
        );
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            currentEmissionCap + 1,
            currentEmissionCap + 1,
            block.timestamp + (60 * 60 * 24 * 365) // 1 yr
        );
    }

    function testUpdateSupplyEmissionCaps() public {
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + (60 * 60 * 24 * 365) // 1 yr
        );

        uint256 currentEmissionCap = distributor.getCurrentEmissionCap();

        vm.expectRevert(
            "Cannot set a supply reward speed higher than the emission cap!"
        );
        distributor._updateSupplySpeed(
            mToken,
            address(emissionToken),
            currentEmissionCap + 1
        );
    }

    function testUpdateBorrowEmissionCaps() public {
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + (60 * 60 * 24 * 365) // 1 yr
        );

        uint256 currentEmissionCap = distributor.getCurrentEmissionCap();

        vm.expectRevert(
            "Cannot set a borrow reward speed higher than the emission cap!"
        );
        distributor._updateBorrowSpeed(
            mToken,
            address(emissionToken),
            currentEmissionCap + 1
        );
    }

    function testRescueFundsAdminSucceeds() public {
        uint256 mintAmount = 100e18;
        deal(address(emissionToken), address(distributor), mintAmount);

        distributor._rescueFunds(address(emissionToken), mintAmount);

        assertEq(emissionToken.balanceOf(address(this)), mintAmount);
        assertEq(emissionToken.balanceOf(address(distributor)), 0);
    }

    function testRescueFundsAdminSucceedsSendAll() public {
        uint256 mintAmount = 100e18;
        deal(address(emissionToken), address(distributor), mintAmount);

        distributor._rescueFunds(address(emissionToken), type(uint256).max);

        assertEq(emissionToken.balanceOf(address(this)), mintAmount);
        assertEq(emissionToken.balanceOf(address(distributor)), 0);
    }

    function testUserSupplierRewardsNotSentWhenContractUnderfunded() public {
        address holdingAddress = address(10_000_000);

        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            0.5e18,
            0.5e18,
            block.timestamp + (60 * 60 * 24 * 365) // 1 yr
        );
        emissionToken.allocateTo(address(distributor), type(uint256).max);

        faucetToken.allocateTo(address(this), 2e18);
        faucetToken.approve(address(mToken), 2e18);

        // Supply some tokens
        mToken.mint(2e18);

        uint256 timeDelta = 10;
        vm.warp(block.timestamp + timeDelta);

        assertEq(emissionToken.balanceOf(address(this)), 0);

        /// pull all the funds out of the contract
        uint256 emissionTokenBalance = emissionToken.balanceOf(
            address(distributor)
        );
        vm.prank(address(distributor));
        emissionToken.transfer(holdingAddress, emissionTokenBalance);

        RewardInfo[] memory rewardInfo = distributor
            .getOutstandingRewardsForUser(mToken, address(this));

        assertEq(rewardInfo[0].emissionToken, address(emissionToken));
        assertEq(rewardInfo[0].totalAmount, (0.5e18 * timeDelta));
        assertEq(rewardInfo[0].supplySide, (0.5e18 * timeDelta));
        assertEq(rewardInfo[0].borrowSide, 0);

        vm.expectEmit(true, false, false, true, address(distributor));
        emit InsufficientTokensToEmit(
            payable(address(this)),
            address(emissionToken),
            rewardInfo[0].totalAmount
        );

        comptroller.claimReward();

        rewardInfo = distributor.getOutstandingRewardsForUser(
            mToken,
            address(this)
        );

        assertEq(rewardInfo[0].supplySide, (0.5e18 * timeDelta)); /// no change in unpaid rewards
        assertEq(rewardInfo[0].totalAmount, (0.5e18 * timeDelta));
    }

    function testUserBorrowerRewardsNotSentWhenContractUnderfunded() public {
        address holdingAddress = address(10_000_000);

        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            0,
            0.5e18,
            block.timestamp + (60 * 60 * 24 * 365) // 1 yr
        );
        emissionToken.allocateTo(address(distributor), type(uint256).max);

        faucetToken.allocateTo(address(this), 2e18);
        faucetToken.approve(address(mToken), 2e18);

        // Supply some tokens
        mToken.mint(2e18);
        mToken.borrow(1e18);

        uint256 timeDelta = 10;
        vm.warp(block.timestamp + timeDelta);

        assertEq(emissionToken.balanceOf(address(this)), 0);

        /// pull all the funds out of the contract
        uint256 emissionTokenBalance = emissionToken.balanceOf(
            address(distributor)
        );
        vm.prank(address(distributor));
        emissionToken.transfer(holdingAddress, emissionTokenBalance);

        RewardInfo[] memory rewardInfo = distributor
            .getOutstandingRewardsForUser(mToken, address(this));

        assertEq(rewardInfo[0].emissionToken, address(emissionToken));
        assertEq(rewardInfo[0].totalAmount, (0.5e18 * timeDelta));
        assertEq(rewardInfo[0].borrowSide, (0.5e18 * timeDelta));
        assertEq(rewardInfo[0].supplySide, 0);

        vm.expectEmit(true, false, false, true, address(distributor));
        emit InsufficientTokensToEmit(
            payable(address(this)),
            address(emissionToken),
            rewardInfo[0].totalAmount
        );

        comptroller.claimReward();

        rewardInfo = distributor.getOutstandingRewardsForUser(
            mToken,
            address(this)
        );

        assertEq(rewardInfo[0].supplySide, 0);
        assertEq(rewardInfo[0].borrowSide, (0.5e18 * timeDelta)); /// no change in unpaid rewards
        assertEq(rewardInfo[0].totalAmount, (0.5e18 * timeDelta));
    }

    function testNoRoundingDownIssues() public {
        uint256 rewardsPerSecond = 0.0001e18;

        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            0,
            rewardsPerSecond,
            block.timestamp + (60 * 60 * 24 * 365) // 1 yr
        );
        emissionToken.allocateTo(address(distributor), type(uint256).max);

        faucetToken.allocateTo(address(this), 2e18);
        faucetToken.approve(address(mToken), 2e18);

        // Supply some tokens
        mToken.mint(2e18);
        mToken.borrow(1); /// borrow 1 wei

        uint256 timeDelta = 1; /// smallest unit of time
        vm.warp(block.timestamp + timeDelta);

        assertEq(emissionToken.balanceOf(address(this)), 0);

        RewardInfo[] memory rewardInfo = distributor
            .getOutstandingRewardsForUser(mToken, address(this));

        assertEq(rewardInfo[0].emissionToken, address(emissionToken));
        assertEq(rewardInfo[0].totalAmount, (rewardsPerSecond * timeDelta));
        assertEq(rewardInfo[0].borrowSide, (rewardsPerSecond * timeDelta));
        assertEq(rewardInfo[0].supplySide, 0);

        comptroller.claimReward();

        rewardInfo = distributor.getOutstandingRewardsForUser(
            mToken,
            address(this)
        );

        /// all rewards paid
        assertEq(rewardInfo[0].supplySide, 0);
        assertEq(rewardInfo[0].borrowSide, 0);
        assertEq(rewardInfo[0].totalAmount, 0);

        assertEq(
            emissionToken.balanceOf(address(this)),
            timeDelta * rewardsPerSecond
        );
    }

    function testBorrowRewardsFuzz(
        uint256 rewardsPerSecond,
        uint256 secondsToWarp
    ) public {
        rewardsPerSecond = _bound(rewardsPerSecond, 0.0001e18, 1e18);
        secondsToWarp = _bound(secondsToWarp, 1, 365 days); /// between 1 second and 365 days

        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            0,
            rewardsPerSecond,
            block.timestamp + (365 days) // 1 yr
        );
        emissionToken.allocateTo(address(distributor), type(uint256).max);

        faucetToken.allocateTo(address(this), 2e18);
        faucetToken.approve(address(mToken), 2e18);

        // Supply some tokens
        mToken.mint(2e18);
        mToken.borrow(1e18);

        vm.warp(block.timestamp + secondsToWarp);

        assertEq(emissionToken.balanceOf(address(this)), 0);

        RewardInfo[] memory rewardInfo = distributor
            .getOutstandingRewardsForUser(mToken, address(this));

        assertEq(rewardInfo[0].emissionToken, address(emissionToken));
        assertEq(rewardInfo[0].totalAmount, (rewardsPerSecond * secondsToWarp));
        assertEq(rewardInfo[0].borrowSide, (rewardsPerSecond * secondsToWarp));
        assertEq(rewardInfo[0].supplySide, 0);

        comptroller.claimReward();

        rewardInfo = distributor.getOutstandingRewardsForUser(
            mToken,
            address(this)
        );

        /// all rewards paid
        assertEq(rewardInfo[0].supplySide, 0);
        assertEq(rewardInfo[0].borrowSide, 0);
        assertEq(rewardInfo[0].totalAmount, 0);

        assertEq(
            emissionToken.balanceOf(address(this)),
            secondsToWarp * rewardsPerSecond
        );
    }

    function testSupplyRewardsFuzz(
        uint256 rewardsPerSecond,
        uint256 secondsToWarp
    ) public {
        rewardsPerSecond = _bound(rewardsPerSecond, 0.0001e18, 1e18);
        secondsToWarp = _bound(secondsToWarp, 1, 365 days);

        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            rewardsPerSecond,
            0,
            block.timestamp + (365 days) // 1 yr
        );
        emissionToken.allocateTo(address(distributor), type(uint256).max);

        faucetToken.allocateTo(address(this), 2e18);
        faucetToken.approve(address(mToken), 2e18);

        // Supply some tokens
        mToken.mint(2e18);

        vm.warp(block.timestamp + secondsToWarp);

        assertEq(emissionToken.balanceOf(address(this)), 0);

        RewardInfo[] memory rewardInfo = distributor
            .getOutstandingRewardsForUser(mToken, address(this));

        assertEq(rewardInfo[0].emissionToken, address(emissionToken));
        assertEq(rewardInfo[0].totalAmount, (rewardsPerSecond * secondsToWarp));
        assertEq(rewardInfo[0].supplySide, (rewardsPerSecond * secondsToWarp));
        assertEq(rewardInfo[0].borrowSide, 0);

        comptroller.claimReward();

        rewardInfo = distributor.getOutstandingRewardsForUser(
            mToken,
            address(this)
        );

        /// all rewards paid
        assertEq(rewardInfo[0].supplySide, 0);
        assertEq(rewardInfo[0].borrowSide, 0);
        assertEq(rewardInfo[0].totalAmount, 0);

        assertEq(
            emissionToken.balanceOf(address(this)),
            secondsToWarp * rewardsPerSecond
        );
    }

    function testBorrowSupplyRewardsFuzz(
        uint256 rewardsPerSecondBorrow,
        uint256 rewardsPerSecondSupply,
        uint256 secondsToWarp
    ) public {
        rewardsPerSecondBorrow = _bound(
            rewardsPerSecondBorrow,
            0.0001e18,
            1e18
        );
        rewardsPerSecondSupply = _bound(
            rewardsPerSecondSupply,
            0.0001e18,
            1e18
        );
        secondsToWarp = _bound(secondsToWarp, 1, 365 days);

        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            rewardsPerSecondSupply,
            rewardsPerSecondBorrow,
            block.timestamp + (365 days) // 1 yr
        );
        emissionToken.allocateTo(address(distributor), type(uint256).max);

        faucetToken.allocateTo(address(this), 2e18);
        faucetToken.approve(address(mToken), 2e18);

        // Supply some tokens
        mToken.mint(2e18);
        mToken.borrow(1);

        vm.warp(block.timestamp + secondsToWarp);

        assertEq(emissionToken.balanceOf(address(this)), 0);

        RewardInfo[] memory rewardInfo = distributor
            .getOutstandingRewardsForUser(mToken, address(this));

        assertEq(
            rewardInfo[0].totalAmount,
            (rewardsPerSecondBorrow * secondsToWarp) +
                (rewardsPerSecondSupply * secondsToWarp)
        );
        assertEq(
            rewardInfo[0].supplySide,
            (rewardsPerSecondSupply * secondsToWarp)
        );
        assertEq(
            rewardInfo[0].borrowSide,
            (rewardsPerSecondBorrow * secondsToWarp)
        );

        comptroller.claimReward();

        rewardInfo = distributor.getOutstandingRewardsForUser(
            mToken,
            address(this)
        );

        /// all rewards paid
        assertEq(rewardInfo[0].supplySide, 0);
        assertEq(rewardInfo[0].borrowSide, 0);
        assertEq(rewardInfo[0].totalAmount, 0);

        assertEq(
            emissionToken.balanceOf(address(this)),
            (rewardsPerSecondBorrow * secondsToWarp) +
                (rewardsPerSecondSupply * secondsToWarp)
        );
    }

    function testGlobalSupplyIndexProperlyUpdates() public {
        testVariousSuppliersAndBorrowers(1e18, 0);

        uint256 currSupplyIndex = distributor.getGlobalSupplyIndex(address(mToken), 0);

        assertTrue(currSupplyIndex > 1e36);
    }

    function testAccurateRewardAmountsSupply() public {
        uint256 supplySpeed = 1e18;
        uint256 startTime = block.timestamp;

        testVariousSuppliersAndBorrowers(supplySpeed, 0);

        uint256 rewardsSpent = type(uint256).max - emissionToken.balanceOf(address(distributor));
        uint256 endTime = block.timestamp;
        uint256 expectedRewards = (endTime - startTime) * supplySpeed;
        uint256 currSupplyIndex = distributor.getGlobalSupplyIndex(address(mToken), 0);
    
        assertTrue(currSupplyIndex > 1e36);

        assertApproxEqRel(
            rewardsSpent,
            expectedRewards,
            0.00001e18 /// 1 basis point of deviation allowed
        );
    }

    function testAddEmissionConfigUnlistedTokenFails() public {
        vm.expectRevert("The market requested to be added is un-listed!");

        distributor._addEmissionConfig(
            MToken(address(this)),
            address(this),
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + (60 * 60 * 24 * 365) // 1 yr
        );
    }

    function testAddEmissionTokenAlreadyListedFails() public {
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + (60 * 60 * 24 * 365) // 1 yr
        );

        vm.expectRevert("Emission token already listed!");
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + (60 * 60 * 24 * 365) // 1 yr
        );
    }

    function testSetPauseGuardianAddressZeroFails() public {
        vm.expectRevert("Pause Guardian can't be the 0 address!");
        distributor._setPauseGuardian(address(0));
    }

    function testSetPauseGuardianSucceeds() public {
        distributor._setPauseGuardian(address(1));
        assertEq(distributor.pauseGuardian(), address(1));
    }

    function testSetEmissionCapSucceeds() public {
        distributor._setEmissionCap(100);
        assertEq(distributor.emissionCap(), 100);
    }

    function testSetNewSupplyEmissionsToCurrentFails() public {
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + 365 days
        );

        vm.expectRevert(
            "Can't set new supply emissions to be equal to current!"
        );
        distributor._updateSupplySpeed(mToken, address(emissionToken), 1e18);
    }

    function testSetNewBorrowEmissionsToCurrentFails() public {
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + 365 days
        );

        vm.expectRevert(
            "Can't set new borrow emissions to be equal to current!"
        );
        distributor._updateBorrowSpeed(mToken, address(emissionToken), 1e18);
    }

    function testSetNewEndTimeLtOrEqualCurrentEndTimeFails() public {
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + 365 days
        );

        vm.expectRevert("_newEndTime MUST be > currentEndTime");
        distributor._updateEndTime(
            mToken,
            address(emissionToken),
            block.timestamp + 365 days
        );
    }

    function testSetNewEndTimeCurrentTimestampFails() public {
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + 365 days
        );

        vm.warp(block.timestamp + 366 days);
        vm.expectRevert("_newEndTime MUST be > block.timestamp");
        distributor._updateEndTime(
            mToken,
            address(emissionToken),
            block.timestamp
        );
    }

    function testSetNewEndTimePastFails() public {
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + 365 days
        );

        uint256 invalidStartTime = block.timestamp + 380 days;
        vm.warp(block.timestamp + 400 days); /// past end time now,

        vm.expectRevert("_newEndTime MUST be > block.timestamp");
        distributor._updateEndTime(
            mToken,
            address(emissionToken),
            invalidStartTime
        );
    }

    function testGetConfigForNonExistentMarketFails() public {
        vm.expectRevert("Unable to find emission token in mToken configs");
        distributor.getConfigForMarket(
            MToken(address(0)),
            address(emissionToken)
        );
    }

    function testSetNewSupplyEmissionsAdminSucceeds() public {
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + 365 days
        );

        distributor._updateSupplySpeed(mToken, address(emissionToken), 0.5e18);

        MarketConfig memory config = distributor.getConfigForMarket(
            mToken,
            address(emissionToken)
        );

        assertEq(config.owner, address(this));
        assertEq(config.emissionToken, address(emissionToken));
        assertEq(config.endTime, block.timestamp + 365 days);
        assertEq(config.supplyGlobalIndex, distributor.initialIndexConstant());
        assertEq(config.borrowGlobalIndex, distributor.initialIndexConstant());
        assertEq(config.supplyEmissionsPerSec, 0.5e18);
        assertEq(config.borrowEmissionsPerSec, 1e18);
    }

    function testSetNewBorrowEmissionsAdminSucceeds() public {
        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + 365 days
        );

        distributor._updateBorrowSpeed(mToken, address(emissionToken), 0.5e18);

        MarketConfig memory config = distributor.getConfigForMarket(
            mToken,
            address(emissionToken)
        );

        assertEq(config.owner, address(this));
        assertEq(config.emissionToken, address(emissionToken));
        assertEq(config.endTime, block.timestamp + 365 days);
        assertEq(config.supplyGlobalIndex, distributor.initialIndexConstant());
        assertEq(config.borrowGlobalIndex, distributor.initialIndexConstant());
        assertEq(config.borrowEmissionsPerSec, 0.5e18);
        assertEq(config.supplyEmissionsPerSec, 1e18);
    }

    function testUpdateOwnerConfigOwnerSucceeds() public {
        distributor._addEmissionConfig(
            mToken,
            address(1), /// address 1 is owner of this config
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + 365 days
        );

        MarketConfig memory config = distributor.getConfigForMarket(
            mToken,
            address(emissionToken)
        );

        assertEq(config.owner, address(1));
        vm.prank(address(1));
        distributor._updateOwner(mToken, address(emissionToken), address(this));

        config = distributor.getConfigForMarket(
            mToken,
            address(emissionToken)
        );

        assertEq(config.owner, address(this));
    }

    function testGetConfigForExistingMarketSucceeds() public {
        distributor._addEmissionConfig(
            mToken,
            address(1), /// address 1 is owner of this config
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + 365 days
        );

        MarketConfig memory config = distributor.getConfigForMarket(
            mToken,
            address(emissionToken)
        );

        assertEq(config.owner, address(1));
        assertEq(config.emissionToken, address(emissionToken));
        assertEq(config.endTime, block.timestamp + 365 days);
        assertEq(config.supplyGlobalIndex, distributor.initialIndexConstant());
        assertEq(config.borrowGlobalIndex, distributor.initialIndexConstant());
        assertEq(config.supplyEmissionsPerSec, 1e18);
        assertEq(config.borrowEmissionsPerSec, 1e18);
    }

    function testUpdateSupplySpeedNonConfigOwnerFails() public {
        distributor._addEmissionConfig(
            mToken,
            address(1), /// address 1 is owner of this config
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + 365 days
        );

        vm.prank(address(2));
        vm.expectRevert(
            "Only the config owner or comptroller admin can call this function"
        );
        distributor._updateSupplySpeed(mToken, address(emissionToken), 1e18);
    }

    function testUpdateBorrowSpeedNonConfigOwnerFails() public {
        distributor._addEmissionConfig(
            mToken,
            address(1), /// address 1 is owner of this config
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + 365 days
        );

        vm.prank(address(2));
        vm.expectRevert(
            "Only the config owner or comptroller admin can call this function"
        );
        distributor._updateBorrowSpeed(mToken, address(emissionToken), 1e18);
    }

    function testUpdateOwnerNonConfigOwnerFails() public {
        distributor._addEmissionConfig(
            mToken,
            address(1), /// address 1 is owner of this config
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + 365 days
        );

        vm.prank(address(2));
        vm.expectRevert(
            "Only the config owner or comptroller admin can call this function"
        );
        distributor._updateOwner(
            mToken,
            address(emissionToken),
            address(100) /// doesn't matter as it will not be set
        );
    }

    function testConfigAssertValues() public {
        distributor._addEmissionConfig(
            mToken,
            address(1), /// address 1 is owner of this config
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + 365 days
        );

        MultiRewardDistributorCommon.MarketConfig[]
            memory allConfigs = distributor.getAllMarketConfigs(mToken);

        assertEq(allConfigs.length, 1);
        assertEq(
            distributor.getCurrentOwner(mToken, address(emissionToken)),
            address(1)
        );
    }

    function testUpdateEndTimeConfigOwnerFails() public {
        distributor._addEmissionConfig(
            mToken,
            address(1), /// address 1 is owner of this config
            address(emissionToken),
            1e18,
            1e18,
            block.timestamp + 365 days
        );

        vm.prank(address(2));
        vm.expectRevert(
            "Only the config owner or comptroller admin can call this function"
        );
        distributor._updateEndTime(
            mToken,
            address(emissionToken),
            block.timestamp + 366 days
        );
    }
}
