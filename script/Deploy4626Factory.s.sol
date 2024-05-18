pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {deployFactory} from "@protocol/4626/4626FactoryDeploy.sol";

/// forge script script/Deploy4626Factory.s.sol:Deploy4626Factory --fork-url base -vvv
contract Deploy4626Factory is Script {
    /// @notice addresses contract
    Addresses addresses;

    /// @notice deployer private key
    uint256 private PRIVATE_KEY;

    constructor() {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "MOONWELL_DEPLOY_PK",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );

        addresses = new Addresses();
    }

    function run() public {
        vm.startBroadcast(PRIVATE_KEY);

        deployFactory(addresses);

        vm.stopBroadcast();
    }
}
