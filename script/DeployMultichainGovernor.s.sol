// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Well} from "@protocol/Governance/deprecated/Well.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {Constants} from "@protocol/Governance/MultichainGovernor/Constants.sol";
import {CreateCode} from "@proposals/utils/CreateCode.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {MoonwellArtemisGovernor} from "@protocol/Governance/deprecated/MoonwellArtemisGovernor.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script} from "@forge-std/Script.sol";

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
    CreateCode,
    MultichainGovernorDeploy
{
    MultichainVoteCollection public voteCollection;
    MoonwellArtemisGovernor public governor;
    IWormhole public wormhole;
    Timelock public timelock;
    Well public well;

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
        address proxyAdmin = address(new ProxyAdmin());
        // add moonbase proxy admin to addresses
        addresses.addAddress("MOONBEAM_PROXY_ADMIN", proxyAdmin);
        (
            address governorProxy,
            address governorImpl
        ) = deployMultichainGovernor(proxyAdmin);

        addresses.addAddress("MULTICHAIN_GOVERNOR_PROXY", governorProxy);
        addresses.addAddress("MULTICHAIN_GOVERNOR_IMPL", governorImpl);
    }
}
