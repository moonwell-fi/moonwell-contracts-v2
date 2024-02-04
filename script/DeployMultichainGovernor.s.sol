// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

/*
 to simulate:
     forge script script/DeployMultichainGovernor.s.sol:DeployMultichainGovernorScript \
     \ -vvvvv --rpc-url moonbase/moonbeam

 to run:
    forge script script/DelpoyMultichainGovernor.s.sol:DeployMultichainGovernorScript \
    \ -vvvvv --rpc-url moonbase/moonbeam --broadcast --etherscan-api-key moonbases/moonbeam --verify
*/
contract DeployMultichainGovernorScript is
    Script,
    ChainIds,
    MultichainGovernorDeploy
{
    /// @notice addresses contract
    Addresses addresses;

    /// @notice deployer private key
    uint256 private PRIVATE_KEY;

    constructor() {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = uint256(vm.envBytes32("ETH_PRIVATE_KEY"));

        addresses = new Addresses();
    }

    function run() public {
        // todo try/catch checking if address exist to make this compatible with
        // mainnet deploy
        address proxyAdmin = address(new ProxyAdmin());

        // add moonbase proxy admin to addresses
        addresses.addAddress("MOONBEAM_PROXY_ADMIN", proxyAdmin);
        (
            address governorProxy,
            address governorImpl
        ) = deployMultichainGovernor(proxyAdmin);

        addresses.addAddress("MULTICHAIN_GOVERNOR_PROXY", governorProxy);
        addresses.addAddress("MULTICHAIN_GOVERNOR_IMPL", governorImpl);

        printAddresses(addresses);
    }

    function printAddresses(Addresses addresses) private view {
        (
            string[] memory recordedNames,
            ,
            address[] memory recordedAddresses
        ) = addresses.getRecordedAddresses();
        for (uint256 j = 0; j < recordedNames.length; j++) {
            console.log('{\n        "addr": "%s", ', recordedAddresses[j]);
            console.log('        "chainId": %d,', block.chainid);
            console.log(
                '        "name": "%s"\n}%s',
                recordedNames[j],
                j < recordedNames.length - 1 ? "," : ""
            );
        }
    }
}
