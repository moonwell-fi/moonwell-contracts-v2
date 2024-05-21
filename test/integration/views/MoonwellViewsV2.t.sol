pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MoonwellViewsV2} from "@protocol/views/MoonwellViewsV2.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";

contract MoonwellViewsV2Test is Test, PostProposalCheck {
    MoonwellViewsV2 public viewsContract;

    address public user = 0xd7854FC91f16a58D67EC3644981160B6ca9C41B8;
    address public proxyAdmin = address(1337);

    address public comptroller;
    address public tokenSaleDistributor;
    address public safetyModule;
    address public governanceToken;
    address public nativeMarket;
    address public governanceTokenLP;

    function setUp() public override {
        super.setUp();

        comptroller = addresses.getAddress("UNITROLLER");
        tokenSaleDistributor = addresses.getAddress("TOKENSALE");
        safetyModule = addresses.getAddress("STKGOVTOKEN");
        governanceToken = addresses.getAddress("GOVTOKEN");
        nativeMarket = addresses.getAddress("MNATIVE");
        governanceTokenLP = addresses.getAddress("GOVTOKEN_LP");

        viewsContract = new MoonwellViewsV2();

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
        viewsContract = MoonwellViewsV2(address(proxy));
        vm.rollFork(5349000);
    }

    function testComptrollerIsSet() public {
        address _addy = address(viewsContract.comptroller());
        assertEq(_addy, comptroller);
    }

    function testMarketsSize() public {
        MoonwellViewsV2.Market[] memory _markets = viewsContract
            .getAllMarketsInfo();
        assertEq(_markets.length, 5);
    }

    function testUserBalances() public {
        MoonwellViewsV2.Balances[] memory _balances = viewsContract
            .getUserBalances(user);
        assertEq(_balances.length, 11);
    }

    function testUserRewards() public {
        MoonwellViewsV2.Rewards[] memory _rewards = viewsContract
            .getUserRewards(user);

        assertEq(_rewards.length, 2);
    }
}
