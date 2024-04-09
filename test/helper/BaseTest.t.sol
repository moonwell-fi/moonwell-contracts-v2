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
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";

import {SigUtils} from "@test/helper/SigUtils.sol";

contract BaseTest is xWELLDeploy, Test {
    /// @notice addresses contract, stores all addresses
    Addresses public addresses;

    /// @notice reference to the wormhole bridge adapter
    WormholeBridgeAdapter public wormholeBridgeAdapter;

    /// @notice reference to the wormhole bridge adapter
    WormholeBridgeAdapter public wormholeBridgeAdapterProxy;

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

    /// @notice signature utils contract
    SigUtils public sigUtils;

    /// @notice name of the token
    string public xwellName = "WELL";

    /// @notice symbol of the token
    string public xwellSymbol = "WELL";

    /// @notice owner of the token
    address public owner = address(100_000_000);

    /// @notice pause guardian of the token
    address public pauseGuardian = address(1111111111);

    /// @notice wormhole relayer of the WormholeBridgeAdapter
    address public wormholeRelayer = address(2222222222);

    /// @notice duration of the pause
    uint128 public pauseDuration = 10 days;

    /// @notice external chain buffer cap
    uint112 public externalChainBufferCap = 100_000_000 * 1e18;

    /// @notice external chain rate limit per second
    uint112 public externalChainRateLimitPerSecond = 1_000 * 1e18;

    /// @notice wormhole chainid for base chain
    uint16 public chainId = 30;

    function setUp() public virtual {
        addresses = new Addresses();
        if (!addresses.isAddressSet("WELL")) {
            well = new MockERC20();
            addresses.addAddress("WELL", address(well), true);
        } else {
            well = MockERC20(addresses.getAddress("WELL"));
        }

        {
            (
                address xwellLogicAddress,
                address xwellProxyAddress,
                address proxyAdminAddress,
                address wormholeAdapterLogic,
                address wormholeAdapterProxy,
                address lockboxAddress
            ) = deployMoonbeamSystem(address(well), address(0));

            xwellProxy = xWELL(xwellProxyAddress);
            xwellLogic = xWELL(xwellLogicAddress);
            proxyAdmin = ProxyAdmin(proxyAdminAddress);
            xerc20Lockbox = XERC20Lockbox(lockboxAddress);
            wormholeBridgeAdapter = WormholeBridgeAdapter(wormholeAdapterLogic);
            wormholeBridgeAdapterProxy = WormholeBridgeAdapter(
                wormholeAdapterProxy
            );

            vm.label(xwellLogicAddress, "xWELL Logic");
            vm.label(xwellProxyAddress, "xWELL Proxy");
            vm.label(proxyAdminAddress, "Proxy Admin");
            vm.label(lockboxAddress, "Lockbox");
            vm.label(pauseGuardian, "Pause Guardian");
            vm.label(owner, "Owner");
            vm.label(pauseGuardian, "Pause Guardian");
            vm.label(address(wormholeAdapterLogic), "WormholeAdapterLogic");
            vm.label(
                address(wormholeBridgeAdapterProxy),
                "WormholeAdapterProxy"
            );
        }

        MintLimits.RateLimitMidPointInfo[]
            memory newRateLimits = new MintLimits.RateLimitMidPointInfo[](2);

        /// lock box limit
        newRateLimits[0].bufferCap = type(uint112).max;
        newRateLimits[0].bridge = address(xerc20Lockbox);
        newRateLimits[0].rateLimitPerSecond = 0;

        /// wormhole limit
        newRateLimits[1].bufferCap = externalChainBufferCap;
        newRateLimits[1].bridge = address(wormholeBridgeAdapterProxy);
        newRateLimits[1].rateLimitPerSecond = externalChainRateLimitPerSecond;

        /// give wormhole bridge adapter and lock box a rate limit
        initializeXWell(
            address(xwellProxy),
            xwellName,
            xwellSymbol,
            owner,
            newRateLimits,
            pauseDuration,
            pauseGuardian
        );

        initializeWormholeAdapter(
            address(wormholeBridgeAdapterProxy),
            address(xwellProxy),
            owner,
            wormholeRelayer,
            chainId
        );

        sigUtils = new SigUtils(xwellProxy.DOMAIN_SEPARATOR());
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ----------- Internal testing helper functions ----------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    function _lockboxCanBurn(uint112 burnAmount) internal {
        uint256 startingTotalSupply = xwellProxy.totalSupply();
        uint256 startingWellBalance = well.balanceOf(address(this));
        uint256 startingXwellBalance = xwellProxy.balanceOf(address(this));

        xwellProxy.approve(address(xerc20Lockbox), burnAmount);
        xerc20Lockbox.withdraw(burnAmount);

        uint256 endingTotalSupply = xwellProxy.totalSupply();
        uint256 endingWellBalance = well.balanceOf(address(this));
        uint256 endingXwellBalance = xwellProxy.balanceOf(address(this));

        assertEq(
            startingTotalSupply - endingTotalSupply,
            burnAmount,
            "incorrect burn amount to totalSupply"
        );
        assertEq(
            endingWellBalance - startingWellBalance,
            burnAmount,
            "incorrect burn amount to well balance"
        );
        assertEq(
            startingXwellBalance - endingXwellBalance,
            burnAmount,
            "incorrect burn amount to xwell balance"
        );
    }

    function _lockboxCanBurnTo(address to, uint112 burnAmount) internal {
        uint256 startingTotalSupply = xwellProxy.totalSupply();
        uint256 startingWellBalance = well.balanceOf(to);
        uint256 startingXwellBalance = xwellProxy.balanceOf(address(this));

        xwellProxy.approve(address(xerc20Lockbox), burnAmount);
        xerc20Lockbox.withdrawTo(to, burnAmount);

        uint256 endingTotalSupply = xwellProxy.totalSupply();
        uint256 endingWellBalance = well.balanceOf(to);
        uint256 endingXwellBalance = xwellProxy.balanceOf(address(this));

        assertEq(
            startingTotalSupply - endingTotalSupply,
            burnAmount,
            "incorrect burn amount to totalSupply"
        );
        assertEq(
            endingWellBalance - startingWellBalance,
            burnAmount,
            "incorrect burn amount to well balance"
        );
        assertEq(
            startingXwellBalance - endingXwellBalance,
            burnAmount,
            "incorrect burn amount to xwell balance"
        );
    }

    function _lockboxCanMint(uint112 mintAmount) internal {
        well.mint(address(this), mintAmount);
        well.approve(address(xerc20Lockbox), mintAmount);

        uint256 startingTotalSupply = xwellProxy.totalSupply();
        uint256 startingWellBalance = well.balanceOf(address(this));
        uint256 startingXwellBalance = xwellProxy.balanceOf(address(this));

        xerc20Lockbox.deposit(mintAmount);

        uint256 endingTotalSupply = xwellProxy.totalSupply();
        uint256 endingWellBalance = well.balanceOf(address(this));
        uint256 endingXwellBalance = xwellProxy.balanceOf(address(this));

        assertEq(
            endingTotalSupply - startingTotalSupply,
            mintAmount,
            "incorrect mint amount to totalSupply"
        );
        assertEq(
            startingWellBalance - endingWellBalance,
            mintAmount,
            "incorrect mint amount to well balance"
        );
        assertEq(
            endingXwellBalance - startingXwellBalance,
            mintAmount,
            "incorrect mint amount to xwell balance"
        );
    }

    function _lockboxCanMintTo(address to, uint112 mintAmount) internal {
        well.mint(address(this), mintAmount);
        well.approve(address(xerc20Lockbox), mintAmount);

        uint256 startingTotalSupply = xwellProxy.totalSupply();
        uint256 startingWellBalance = well.balanceOf(address(this));
        uint256 startingXwellBalance = xwellProxy.balanceOf(to);

        xerc20Lockbox.depositTo(to, mintAmount);

        uint256 endingTotalSupply = xwellProxy.totalSupply();
        uint256 endingWellBalance = well.balanceOf(address(this));
        uint256 endingXwellBalance = xwellProxy.balanceOf(to);

        assertEq(
            endingTotalSupply - startingTotalSupply,
            mintAmount,
            "incorrect mint amount to totalSupply"
        );
        assertEq(
            startingWellBalance - endingWellBalance,
            mintAmount,
            "incorrect mint amount to well balance"
        );
        assertEq(
            endingXwellBalance - startingXwellBalance,
            mintAmount,
            "incorrect mint amount to xwell balance"
        );
    }
}
