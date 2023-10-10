// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {Recovery} from "@protocol/Recovery.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {RecoveryDeploy} from "@test/utils/RecoveryDeploy.sol";

contract RecoveryDeploymentLiveSystemBaseTest is Configs, RecoveryDeploy {
    /// @notice addresses contract
    Addresses addresses;

    /// @notice RecoveryDeploy instance
    Recovery recover;

    /// @notice foundation multisig address
    address foundationMultisig;

    function setUp() public {
        vm.deal(deployer, 1);
        vm.startPrank(deployer);

        /// deployer is owner of recovery contract
        recover = mainnetDeployAndVerify(deployer);

        vm.stopPrank();

        addresses = new Addresses();
        foundationMultisig = addresses.getAddress("FOUNDATION_MULTISIG");
    }

    function testVerifyDeploy() public {
        verifyDeploy(recover);
    }

    function testPullFunds() public {
        uint256 recoveryBalance = address(recover).balance;
        uint256 multisigStartingBalance = foundationMultisig.balance;

        vm.prank(deployer);
        recover.sendAllEth(payable(foundationMultisig));

        assertEq(vm.getNonce(deployer), 1902, "incorrect nonce");
        assertEq(
            recoveryBalance,
            foundationMultisig.balance - multisigStartingBalance,
            "recovery balance not given to foundation multisig"
        );
        assertEq(address(recover).balance, 0, "recovery balance not 0");
    }
}
