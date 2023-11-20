pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MoonwellViewsV2} from "@protocol/views/MoonwellViewsV2.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract MoonwellViewsV2Test is Test {
    MoonwellViewsV2 public viewsContract;

    address public constant proxyAdmin = address(1337);

    address public constant comptroller =
        0xfBb21d0380beE3312B33c4353c8936a0F13EF26C;

    address public constant tokenSaleDistributor = address(0);

    address public constant safetyModule = address(0);

    address public constant governanceToken = address(0);

    address public constant user = 0xd7854FC91f16a58D67EC3644981160B6ca9C41B8;

    function setUp() public {
        viewsContract = new MoonwellViewsV2();

        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address,address,address)",
            address(comptroller),
            address(tokenSaleDistributor),
            address(safetyModule),
            address(governanceToken)
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

        console.log("markets length %s", _markets.length);
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
