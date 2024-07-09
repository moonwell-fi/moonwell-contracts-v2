pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*
 to simulate:
  base:
    forge script script/GetTimestamp.s.sol:GetTimestamp \
     \ -vvvvv --rpc-url base --with-gas-price 500000

  moonbeam:
     forge script script/GetTimestamp.s.sol:GetTimestamp \
     \ -vvvvv --rpc-url moonbeam --with-gas-price 500000

  to run:
    forge script script/GetTimestamp.s.sol:GetTimestamp \
     \ -vvvvv --rpc-url base --with-gas-price 500000 --broadcast
*/
contract GetTimestamp is Script, Test {
    function run() public view {
        console.log("block timestamp: ", block.timestamp);
    }
}
