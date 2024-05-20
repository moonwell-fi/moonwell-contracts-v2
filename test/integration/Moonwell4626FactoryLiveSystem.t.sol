// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import "@forge-std/Test.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {Factory4626} from "@protocol/4626/Factory4626.sol";
import {Factory4626Eth} from "@protocol/4626/Factory4626Eth.sol";
import {MoonwellERC4626} from "@protocol/4626/MoonwellERC4626.sol";
import {deployFactory, deployFactoryEth} from "@protocol/4626/4626FactoryDeploy.sol";

contract Moonwell4626FactoryLiveSystemBaseTest is Configs {
    /// @notice WETH9 contract
    WETH9 weth;

    /// @notice mToken address for ETH
    address mweth;

    /// @notice addresses contract
    Addresses addresses;

    /// @notice 4626 factory contract
    Factory4626 factory;

    /// @notice 4626 eth factory contract
    Factory4626Eth ethFactory;

    /// @notice moontroller contract
    Comptroller comptroller;

    /// @notice event emitted when a new 4626 vault is deployed
    /// @param asset underlying the vault
    /// @param mToken the mToken contract
    /// @param rewardRecipient the address to receive rewards
    /// @param deployed the address of the deployed contract
    event DeployedMoonwellERC4626(
        address indexed asset,
        address indexed mToken,
        address indexed rewardRecipient,
        address deployed
    );

    function setUp() public {
        addresses = new Addresses();

        mweth = addresses.getAddress("MOONWELL_WETH");
        factory = deployFactory(addresses);
        ethFactory = deployFactoryEth(addresses);

        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        weth = WETH9(addresses.getAddress("WETH"));
    }

    function testSetup() public {
        assertEq(
            factory.weth(),
            addresses.getAddress("WETH"),
            "incorrect WETH address"
        );
        assertEq(
            address(factory.moontroller()),
            addresses.getAddress("UNITROLLER"),
            "incorrect moontroller address"
        );
        assertEq(
            ethFactory.weth(),
            addresses.getAddress("WETH"),
            "incorrect WETH address"
        );
        assertEq(
            address(ethFactory.moontroller()),
            addresses.getAddress("UNITROLLER"),
            "incorrect moontroller address"
        );
    }

    /// Sad Paths

    function testDeployVaultNoRewardsRecipientFails() public {
        vm.expectRevert("INVALID_RECIPIENT");
        factory.deployMoonwellERC4626(mweth, address(0));

        vm.expectRevert("INVALID_RECIPIENT");
        ethFactory.deployMoonwellERC4626Eth(mweth, address(0));
    }

    function testDeployVaultAssetWethFails() public {
        vm.expectRevert("INVALID_ASSET");
        factory.deployMoonwellERC4626(mweth, address(1));
    }

    function testDeployVaultAssetNotWethFails() public {
        address mcbEth = addresses.getAddress("MOONWELL_cbETH");

        vm.expectRevert("INVALID_ASSET");
        ethFactory.deployMoonwellERC4626Eth(mcbEth, address(1));
    }

    function testDeploycbEthVaultFailsNotFunded() public {
        address cbEth = addresses.getAddress("MOONWELL_cbETH");
        address rewardRecipient = address(0xeeeeeeeeeeee);

        vm.expectRevert("ERC20: insufficient allowance");
        factory.deployMoonwellERC4626(cbEth, rewardRecipient);
    }

    function testDeployEthVaultFailsNotFunded() public {
        address mwEth = addresses.getAddress("MOONWELL_WETH");
        address rewardRecipient = address(0xeeeeeeeeeeee);

        vm.expectRevert();
        ethFactory.deployMoonwellERC4626Eth(mwEth, rewardRecipient);
    }

    /// Happy Paths

    function testDeployVaultSuccessFunded() public {
        address cbEth = addresses.getAddress("cbETH");
        address mcbEth = addresses.getAddress("MOONWELL_cbETH");
        address rewardRecipient = address(0xeeeeeeeeeeee);

        deal(cbEth, address(this), .01 ether);
        ERC20(cbEth).approve(address(factory), .01 ether);

        /// take a snapshot of the current state
        uint256 snapshotId = vm.snapshot();
        /// get the address of the deployed contract
        address vault = factory.deployMoonwellERC4626(mcbEth, rewardRecipient);
        /// now roll back snapshot to check the emitted event
        assertTrue(vm.revertTo(snapshotId), "rollback failed");

        vm.expectEmit(true, true, true, true, address(factory));
        emit DeployedMoonwellERC4626(cbEth, mcbEth, rewardRecipient, vault);

        vault = factory.deployMoonwellERC4626(mcbEth, rewardRecipient);

        assertEq(
            address(MoonwellERC4626(vault).asset()),
            addresses.getAddress("cbETH"),
            "incorrect asset address, should be cbEth"
        );
        assertEq(
            address(MoonwellERC4626(vault).mToken()),
            mcbEth,
            "incorrect mToken address"
        );
        assertEq(
            MoonwellERC4626(vault).rewardRecipient(),
            rewardRecipient,
            "incorrect rewardRecipient address"
        );
        assertEq(
            address(MoonwellERC4626(vault).comptroller()),
            address(comptroller),
            "incorrect moontroller address"
        );
        assertTrue(
            MoonwellERC4626(vault).totalSupply() > 0,
            "incorrect totalSupply"
        );
        assertEq(
            MoonwellERC4626(vault).totalSupply(),
            MoonwellERC4626(vault).balanceOf(address(0)),
            "incorrect balance of address(0)"
        );
    }

    function testDeployEthVaultSuccess() public {
        address mwEth = addresses.getAddress("MOONWELL_WETH");
        address rewardRecipient = address(0xeeeeeeeeeeee);

        deal(address(weth), address(this), .01 ether);
        weth.approve(address(ethFactory), .01 ether);

        /// take a snapshot of the current state
        uint256 snapshotId = vm.snapshot();
        /// get the address of the deployed contract
        address vault = ethFactory.deployMoonwellERC4626Eth(
            mwEth,
            rewardRecipient
        );
        /// now roll back snapshot to check the emitted event
        assertTrue(vm.revertTo(snapshotId), "rollback failed");

        vm.expectEmit(true, true, true, true, address(ethFactory));
        emit DeployedMoonwellERC4626(
            address(weth),
            mwEth,
            rewardRecipient,
            vault
        );

        vault = ethFactory.deployMoonwellERC4626Eth(mwEth, rewardRecipient);

        assertEq(
            address(MoonwellERC4626(vault).asset()),
            address(weth),
            "incorrect asset address, should be weth"
        );
        assertEq(
            address(MoonwellERC4626(vault).mToken()),
            mwEth,
            "incorrect mToken address"
        );
        assertEq(
            MoonwellERC4626(vault).rewardRecipient(),
            rewardRecipient,
            "incorrect rewardRecipient address"
        );
        assertEq(
            address(MoonwellERC4626(vault).comptroller()),
            address(comptroller),
            "incorrect moontroller address"
        );
        assertTrue(
            MoonwellERC4626(vault).totalSupply() > 0,
            "incorrect totalSupply"
        );
        assertEq(
            MoonwellERC4626(vault).totalSupply(),
            MoonwellERC4626(vault).balanceOf(address(0)),
            "incorrect balance of address(0)"
        );
    }
}
