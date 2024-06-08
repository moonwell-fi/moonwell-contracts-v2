pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {FeeSplitter as Splitter} from "@protocol/morpho/FeeSplitter.sol";

contract FeeSplitter is Script, Test {
    /// @notice addresses contract
    Addresses addresses;

    constructor() {
        addresses = new Addresses();
    }

    function run() public returns (Splitter splitter) {
        /// user must specify environment variables for the following addresses:
        /// - EXTERNAL_REWARD_RECIPIENT - address name in Addresses.json
        /// - SPLIT_A - uint256 percent of funds going to A in basis points
        /// - MORPHO_VAULT - address name in Addresses.json of vault fee
        /// splitter is for
        /// - MTOKEN - the address name in Addresses.json of mToken to add
        /// reserves to
        splitter = new Splitter(
            addresses.getAddress(vm.envString("EXTERNAL_REWARD_RECIPIENT")),
            vm.envUint("SPLIT_A"),
            addresses.getAddress(vm.envString("MORPHO_VAULT")),
            addresses.getAddress(vm.envString("MTOKEN"))
        );
    }
}
