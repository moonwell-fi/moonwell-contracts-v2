pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MoonwellStakingViews} from "@protocol/views/MoonwellStakingViews.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// @notice Forks Ethereum mainnet and verifies the decoupled staking views
/// contract resolves real stkWELL state without needing a Comptroller.
contract MoonwellStakingViewsEthereumTest is Test {
    Addresses public addresses;
    MoonwellStakingViews public views_;

    function setUp() public {
        vm.createSelectFork(vm.envOr("ETH_RPC_URL", string("ethereum")));
        addresses = new Addresses();

        MoonwellStakingViews impl = new MoonwellStakingViews();
        ProxyAdmin proxyAdmin = new ProxyAdmin();

        bytes memory initdata = abi.encodeWithSelector(
            MoonwellStakingViews.initialize.selector,
            addresses.getAddress("STK_GOVTOKEN_PROXY", block.chainid)
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            initdata
        );

        views_ = MoonwellStakingViews(address(proxy));
    }

    function testSafetyModuleWired() public view {
        assertEq(
            address(views_.safetyModule()),
            addresses.getAddress("STK_GOVTOKEN_PROXY", block.chainid)
        );
    }

    function testGetStakingInfo() public view {
        MoonwellStakingViews.StakingInfo memory info = views_.getStakingInfo();

        // The Ethereum safety module is live and configured: COOLDOWN_SECONDS
        // and UNSTAKE_WINDOW are non-zero, and totalSupply is non-zero
        // because users have staked. These are weak invariants — they would
        // trip if the proxy were pointed at an uninitialized contract.
        assertGt(info.cooldown, 0, "COOLDOWN_SECONDS must be set");
        assertGt(info.unstakeWindow, 0, "UNSTAKE_WINDOW must be set");
        assertGt(info.totalSupply, 0, "stkWELL must have stakers");
    }
}
