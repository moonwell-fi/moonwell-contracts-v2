pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";

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
