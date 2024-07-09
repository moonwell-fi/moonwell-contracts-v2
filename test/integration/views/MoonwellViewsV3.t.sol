pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MoonwellViewsV3} from "@protocol/views/MoonwellViewsV3.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";

contract MoonwellViewsV3Test is Test, PostProposalCheck {
    MoonwellViewsV3 public viewsContract;

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
        tokenSaleDistributor = address(0);
        safetyModule = address(0);
        governanceToken = addresses.getAddress("xWELL_PROXY");
        nativeMarket = address(0);
        governanceTokenLP = address(0);

        viewsContract = new MoonwellViewsV3();

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
            address(viewsContract), proxyAdmin, initdata
        );

        /// wire proxy up
        viewsContract = MoonwellViewsV3(address(proxy));
        vm.rollFork(6900000);
    }

    function testComptrollerIsSet() public view {
        address _addy = address(viewsContract.comptroller());
        assertEq(_addy, comptroller);
    }

    function testMarketsSize() public view {
        MoonwellViewsV3.Market[] memory _markets =
            viewsContract.getAllMarketsInfo();
        assertEq(_markets.length, 3);
    }

    function testUserRewards() public view {
        MoonwellViewsV3.Rewards[] memory _rewards =
            viewsContract.getUserRewards(user);
        assertEq(_rewards.length, 0);
    }

    function testProtocolInfo() public view {
        MoonwellViewsV3.ProtocolInfo memory _protocolInfo =
            viewsContract.getProtocolInfo();
        assertEq(_protocolInfo.transferPaused, false);
    }
}
