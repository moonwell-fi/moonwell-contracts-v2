pragma solidity 0.8.19;

import {WETH9} from "@protocol/router/IWETH.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Factory4626} from "@protocol/4626/Factory4626.sol";
import {Factory4626Eth} from "@protocol/4626/Factory4626Eth.sol";
import {ERC4626EthRouter} from "@protocol/router/ERC4626EthRouter.sol";
import {Comptroller as IComptroller} from "@protocol/Comptroller.sol";

function deployFactory(Addresses addresses) returns (Factory4626 factory) {
    factory = new Factory4626(
        IComptroller(addresses.getAddress("UNITROLLER")),
        addresses.getAddress("WETH")
    );
}

function deployFactoryEth(
    Addresses addresses
) returns (Factory4626Eth factory) {
    factory = new Factory4626Eth(
        IComptroller(addresses.getAddress("UNITROLLER")),
        addresses.getAddress("WETH")
    );
}

function deploy4626Router(
    Addresses addresses
) returns (ERC4626EthRouter router) {
    router = new ERC4626EthRouter(WETH9(addresses.getAddress("WETH")));
}
