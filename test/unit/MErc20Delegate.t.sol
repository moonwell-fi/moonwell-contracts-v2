pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MToken} from "@protocol/core/MToken.sol";
import {SigUtils} from "@test/helper/SigUtils.sol";
import {FaucetTokenWithPermit} from "@test/helper/FaucetToken.sol";
import {Comptroller} from "@protocol/core/Comptroller.sol";
import {MErc20Delegate} from "@protocol/core/MErc20Delegate.sol";
import {MErc20Delegator} from "@protocol/core/MErc20Delegator.sol";
import {MErc20Immutable} from "@protocol/core/MErc20Immutable.sol";
import {SimplePriceOracle} from "@test/helper/SimplePriceOracle.sol";
import {InterestRateModel} from "@protocol/core/IRModels/InterestRateModel.sol";
import {WhitePaperInterestRateModel} from "@protocol/core/IRModels/WhitePaperInterestRateModel.sol";
import {ComptrollerErrorReporter} from "@protocol/core/ErrorReporter.sol";
import {MultiRewardDistributor} from "@protocol/core/MultiRewardDistributor/MultiRewardDistributor.sol";

interface InstrumentedExternalEvents {
    event PricePosted(address asset, uint previousPriceMantissa, uint requestedPriceMantissa, uint newPriceMantissa);
    event NewCollateralFactor(MToken mToken, uint oldCollateralFactorMantissa, uint newCollateralFactorMantissa);
    event Transfer(address indexed from, address indexed to, uint amount);
    event Mint(address minter, uint mintAmount, uint mintTokens);
    event Approval(address indexed owner, address indexed spender, uint amount);
}

contract MErc20DelegateUnitTest is Test, InstrumentedExternalEvents, ComptrollerErrorReporter {
    Comptroller comptroller;
    SimplePriceOracle oracle;
    FaucetTokenWithPermit faucetToken;
    MToken mToken;
    MErc20Delegator mErc20Delegator;
    MErc20Delegate mTokenImpl;
    InterestRateModel irModel;
    MultiRewardDistributor distributor;
    SigUtils sigUtils;

    function setUp() public {
        comptroller = new Comptroller();
        oracle = new SimplePriceOracle();
        faucetToken = new FaucetTokenWithPermit(1e18, "Testing", 18, "TEST");
        irModel = new WhitePaperInterestRateModel(0.1e18, 0.45e18);

        mTokenImpl = new MErc20Delegate();

        mErc20Delegator = new MErc20Delegator(
            address(faucetToken),
            comptroller,
            irModel,
            1e18, // Exchange rate is 1:1 for tests
            "Test mToken",
            "mTEST",
            8,
            payable(address(this)),
            address(mTokenImpl),
            ""
        );

        mToken = MToken(address(mErc20Delegator));

        distributor = new MultiRewardDistributor();
        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address)",
            address(comptroller),
            address(this)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(distributor),
            address(this),
            initdata
        );
        /// wire proxy up
        distributor = MultiRewardDistributor(address(proxy));

        sigUtils = new SigUtils(faucetToken.DOMAIN_SEPARATOR());

        comptroller._setRewardDistributor(distributor);
        comptroller._setPriceOracle(oracle);
        comptroller._supportMarket(mToken);
        oracle.setUnderlyingPrice(mToken, 1e18);
    }

    function testDelegatorMintWithPermit() public {
        uint userPK = 0xA11CE;
        address user = vm.addr(userPK);

        faucetToken.allocateTo(user, 1e18);

        // Make sure our user has some tokens, but not mTokens
        assertEq(faucetToken.balanceOf(user), 1e18);
        assertEq(mToken.balanceOf(user), 0);

        uint deadline = 1 minutes;
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: user,
            spender: address(mToken),
            value: 1e18,
            nonce: 0,
            deadline: deadline
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPK, digest);

        // Ensure an Approval event was emitted as expected
        vm.expectEmit(true, true, true, true, address(faucetToken));
        emit Approval(user, address(mToken), 1e18);

        // Ensure an Mint event was emitted as expected
        vm.expectEmit(true, true, true, true, address(mToken));
        emit Mint(user, 1e18, 1e18);

        // Ensure an Transfer event was emitted as expected
        vm.expectEmit(true, true, true, true, address(mToken));
        emit Transfer(address(mToken), user, 1e18);

        // Go mint as a user with permit
        vm.prank(user);
        mErc20Delegator.mintWithPermit(1e18, deadline, v, r, s);

        // Make sure our ending state was as expected
        assertEq(faucetToken.balanceOf(user), 0);
        assertEq(mToken.balanceOf(user), 1e18);
    }
}