pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {XERC20Lockbox} from "@protocol/xWELL/XERC20Lockbox.sol";

contract BaseTest is xWELLDeploy, Test {
    /// @notice addresses contract, stores all addresses
    Addresses public addresses;

    /// @notice lockbox contract
    XERC20Lockbox public xerc20Lockbox;

    /// @notice original token contract
    MockERC20 public well;

    /// @notice logic contract, not initializable
    xWELL public xwellLogic;

    /// @notice proxy admin contract
    ProxyAdmin public proxyAdmin;

    /// @notice proxy contract, stores all state
    xWELL public xwellProxy;

    /// @notice name of the token
    string public xwellName = "Cross Chain WELL";

    /// @notice symbol of the token
    string public xwellSymbol = "xWELL";

    /// @notice owner of the token
    address public owner = address(100_000_000);

    /// @notice pause guardian of the token
    address public pauseGuardian = address(1111111111);

    /// @notice duration of the pause
    uint128 public pauseDuration = 10 days;

    function setUp() public {
        addresses = new Addresses();
        if (addresses.getAddress("WELL") == address(0)) {
            well = new MockERC20();
            addresses.addAddress("WELL", address(well));
        } else {
            well = MockERC20(addresses.getAddress("WELL"));
        }

        (
            address xwellLogicAddress,
            address xwellProxyAddress,
            address proxyAdminAddress,
            address lockboxAddress
        ) = deployXWellAndLockBox(
                addresses,
                xwellName,
                xwellSymbol,
                owner,
                new MintLimits.RateLimitMidPointInfo[](0),
                pauseDuration,
                pauseGuardian
            );

        xwellProxy = xWELL(xwellProxyAddress);
        xwellLogic = xWELL(xwellLogicAddress);
        proxyAdmin = ProxyAdmin(proxyAdminAddress);
        xerc20Lockbox = XERC20Lockbox(lockboxAddress);

        vm.label(xwellLogicAddress, "xWELL Logic");
        vm.label(xwellProxyAddress, "xWELL Proxy");
        vm.label(proxyAdminAddress, "Proxy Admin");
        vm.label(lockboxAddress, "Lockbox");
        vm.label(pauseGuardian, "Pause Guardian");
        vm.label(owner, "Owner");
    }
}
