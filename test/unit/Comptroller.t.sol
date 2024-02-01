pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MToken} from "@protocol/MToken.sol";
import {SigUtils} from "@test/helper/SigUtils.sol";
import {FaucetTokenWithPermit} from "@test/helper/FaucetToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Immutable} from "@test/mock/MErc20Immutable.sol";
import {SimplePriceOracle} from "@test/helper/SimplePriceOracle.sol";
import {InterestRateModel} from "@protocol/IRModels/InterestRateModel.sol";
import {MultiRewardDistributor} from "@protocol/MultiRewardDistributor/MultiRewardDistributor.sol";
import {ComptrollerErrorReporter} from "@protocol/ErrorReporter.sol";
import {WhitePaperInterestRateModel} from "@protocol/IRModels/WhitePaperInterestRateModel.sol";

interface InstrumentedExternalEvents {
    event PricePosted(
        address asset,
        uint previousPriceMantissa,
        uint requestedPriceMantissa,
        uint newPriceMantissa
    );
    event NewCollateralFactor(
        MToken mToken,
        uint oldCollateralFactorMantissa,
        uint newCollateralFactorMantissa
    );
    event Transfer(address indexed from, address indexed to, uint amount);
    event Mint(address minter, uint mintAmount, uint mintTokens);
    event Approval(address indexed owner, address indexed spender, uint amount);
}

contract ComptrollerUnitTest is
    Test,
    InstrumentedExternalEvents,
    ComptrollerErrorReporter
{
    Comptroller comptroller;
    SimplePriceOracle oracle;
    FaucetTokenWithPermit faucetToken;
    MErc20Immutable mToken;
    InterestRateModel irModel;
    SigUtils sigUtils;
    MultiRewardDistributor distributor;
    address public constant proxyAdmin = address(1337);

    function setUp() public {
        comptroller = new Comptroller();
        oracle = new SimplePriceOracle();
        faucetToken = new FaucetTokenWithPermit(1e18, "Testing", 18, "TEST");
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

        distributor = new MultiRewardDistributor();
        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address)",
            address(comptroller),
            address(this)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(distributor),
            address(proxyAdmin),
            initdata
        );
        /// wire proxy up
        distributor = MultiRewardDistributor(address(proxy));

        comptroller._setRewardDistributor(distributor);
        comptroller._setPriceOracle(oracle);
        comptroller._supportMarket(mToken);
        oracle.setUnderlyingPrice(mToken, 1e18);
        sigUtils = new SigUtils(faucetToken.DOMAIN_SEPARATOR());
    }

    function testWiring() public {
        // Ensure things are wired correctly
        assertEq(comptroller.admin(), address(this));
        assertEq(oracle.admin(), address(this));
        assertEq(address(comptroller.oracle()), address(oracle));

        // Ensure we have 1 TEST token
        assertEq(faucetToken.balanceOf(address(this)), 1e18);

        // Ensure our market is listed
        (bool isListed, ) = comptroller.markets(address(mToken));
        assertTrue(isListed);

        // 1 TEST === $1
        vm.expectEmit(true, true, true, true);
        emit PricePosted(mToken.underlying(), 1e18, 2e18, 2e18);
        oracle.setUnderlyingPrice(mToken, 2e18);

        assertEq(oracle.getUnderlyingPrice(mToken), 2e18);
    }

    function testSettingCF(uint cfToSet) public {
        // Ensure our market is listed
        (, uint originalCF) = comptroller.markets(address(mToken));
        assertEq(originalCF, 0);

        assertEq(oracle.getUnderlyingPrice(mToken), 1e18);

        // If we set a CF > 90% things fail, so check that
        if (cfToSet > 0.9e18) {
            vm.expectEmit(true, true, true, true, address(comptroller));
            emit Failure(
                uint(Error.INVALID_COLLATERAL_FACTOR),
                uint(FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION),
                0
            );
            comptroller._setCollateralFactor(mToken, cfToSet);
        } else {
            vm.expectEmit(true, true, true, true, address(comptroller));
            emit NewCollateralFactor(mToken, originalCF, cfToSet);

            uint setCollateralResult = comptroller._setCollateralFactor(
                mToken,
                cfToSet
            );
            assertEq(setCollateralResult, 0);

            (, uint collateralFactorUpdated) = comptroller.markets(
                address(mToken)
            );
            assertEq(collateralFactorUpdated, cfToSet);
        }
    }

    function testRewards() public {
        assertEq(oracle.getUnderlyingPrice(mToken), 1e18);

        comptroller._setCollateralFactor(mToken, 0.5e18);

        (, uint cf) = comptroller.markets(address(mToken));
        assertEq(cf, 0.5e18);

        faucetToken.approve(address(mToken), 1e18);
        mToken.mint(1e18);

        assertEq(faucetToken.balanceOf(address(this)), 0);

        uint time = 1678430000;
        vm.warp(time);

        distributor._addEmissionConfig(
            mToken,
            address(this),
            address(faucetToken),
            0.5e18,
            0,
            time + 86400
        );
        faucetToken.allocateTo(address(distributor), 100000e18);
        comptroller.claimReward();

        vm.warp(time + 10);

        comptroller.claimReward();

        // Make sure we got 10 * 0.5 == 5 tokens
        assertEq(faucetToken.balanceOf(address(this)), 5e18);

        // Make sure claiming twice in the same block doesn't do anything
        comptroller.claimReward();
        assertEq(faucetToken.balanceOf(address(this)), 5e18);
    }
}
