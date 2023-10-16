pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MoonwellViewsV2} from "@protocol/views/MoonwellViewsV2.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract MoonwellViewsV2Test is Test {
   MoonwellViewsV2 public viewsContract;

    address public constant proxyAdmin = address(1337);
    
    address public constant comptroller =
        0xfBb21d0380beE3312B33c4353c8936a0F13EF26C;

    function setUp() public {
        viewsContract = new MoonwellViewsV2();

         bytes memory initdata = abi.encodeWithSignature(
            "initialize(address)",
            address(comptroller)
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
        MoonwellViewsV2.Market[] memory _markets = viewsContract.getAllMarketsInfo();

        console.log("markets length %s", _markets.length);
        assertEq(_markets.length, 5);
    }
}
