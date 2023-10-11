pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {Recovery} from "@protocol/Recovery.sol";
import {Addresses} from "@proposals/Addresses.sol";

contract RecoveryDeploy is Test {
    /// @notice base mainnet address to deploy to
    address public constant recoveryAddress =
        0x3b995646420BcfE8395bA9F44251415126f7BD7A;

    /// @notice base mainnet address to deploy from
    address public constant deployer =
        0xc191A4db4E05e478778eDB6a201cb7F13A257C23;

    /// @notice deploy a new recovery contract
    /// returns freshly deployed contract
    function deploy(address owner) public returns (Recovery) {
        Recovery recovery = new Recovery(owner);

        return recovery;
    }

    /// @notice deploy after 1901 tx's sending 0 value to address 0
    function mainnetDeploy(address owner) public returns (Recovery) {
        /// 1901 tx's to get to the right nonce
        for (uint256 i = 0; i < 1901; i++) {
            deploy(owner);
            // (bool success, ) = address(0).call{value: 1}(""); /// add 1 wei on to make tx actually send in foundry
            // success;
            vm.getNonce(owner);
        }

        Recovery recover = deploy(owner);
        vm.getNonce(owner);

        return recover;
    }

    /// @notice deploy after 1901 tx's sending 0 value to address 0
    function mainnetDeployScript(address owner) public returns (Recovery) {
        /// 1901 tx's to get to the right nonce
        for (uint256 i = 0; i < 1901; i++) {
            (bool success, ) = address(owner).call{value: 1}("");
            success;
            console.log(vm.getNonce(owner));
        }

        Recovery recover = deploy(owner);
        vm.getNonce(owner);

        return recover;
    }

    /// @notice deploy, then verify the address is correct
    function mainnetDeployAndVerify(address owner) public returns (Recovery) {
        Recovery recover = mainnetDeploy(owner);
        require(verifyDeploy(recover), "incorrect deploy address");

        return recover;
    }

    /// @notice deploy, then verify the address is correct
    function mainnetDeployAndVerifyScript(address owner) public returns (Recovery) {
        Recovery recover = mainnetDeployScript(owner);
        require(verifyDeploy(recover), "incorrect deploy address");

        return recover;
    }

    /// @notice verify contract is correctly deployed
    function verifyDeploy(Recovery recovery) public pure returns (bool) {
        return address(recovery) == recoveryAddress;
    }
}
