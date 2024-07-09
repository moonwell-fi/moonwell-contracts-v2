pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*
 to simulate:
 DEPLOYER_ADDRESS=0x...
  base:
    DEPLOYER_ADDRESS=0x... forge script script/GetNonce.s.sol:GetNonce \
     \ -vvvvv --rpc-url base --with-gas-price 500000

  moonbeam:
     DEPLOYER_ADDRESS=0x... forge script script/GetNonce.s.sol:GetNonce \
     \ -vvvvv --rpc-url moonbeam --with-gas-price 500000

  to run:
    DEPLOYER_ADDRESS=0x... forge script script/GetNonce.s.sol:GetNonce \
     \ -vvvvv --rpc-url base --with-gas-price 500000 --broadcast
*/
contract GetNonce is Script, Test {
    /// @notice addresses contract
    Addresses addresses;

    /// @notice deployer address
    address public immutable deployerAddress;

    constructor() {
        deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");

        addresses = new Addresses();
    }

    function run() public view {
        console.log("deployerAddress: ", deployerAddress);
        console.log("account nonce: ", vm.getNonce(deployerAddress));
    }
}
