//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, ETHEREUM_FORK_ID, ChainIds} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";

/// @title MIP-X44: Upgrade StakedWell contracts on Base, OP, and Moonbeam; Deploy to Ethereum
/// @author Moonwell Contributors
/// @notice Proposal to:
///         1. Upgrade stkWELL on Moonbeam to switch snapshot logic to use timestamps instead of block numbers
///         2. Upgrade stkWELL on Base/OP to remove faulty configureAssets function
///         3. Call setNewStakedWell on the MultichainGovernor on moonbeam with the same stkwell contract and toUseTimestamps=true
///         4. Validate xWELL and stkWELL deployment on Ethereum
///
/// @dev IMPORTANT: Ethereum deployment is handled separately via script/DeployXWellEthereum.s.sol
///      This is because multichain proposals cannot handle library linking for xWELL's Zelt libraries.
///      Before running this proposal, deploy to Ethereum using:
///        forge script script/DeployXWellEthereum.s.sol:DeployXWellEthereum --rpc-url ethereum --broadcast
contract mipx44 is HybridProposal {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-X44";

    /// @notice Constants for Ethereum xWELL deployment
    uint112 public constant ETH_XWELL_BUFFER_CAP = 100_000_000 * 1e18;
    uint128 public constant ETH_XWELL_RATE_LIMIT_PER_SECOND = 1158 * 1e18; // ~19m per day
    uint128 public constant ETH_XWELL_PAUSE_DURATION = 10 days;

    /// @notice Constants for Ethereum stkWELL deployment
    uint256 public constant ETH_STKWELL_COOLDOWN_SECONDS = 7 days;
    uint256 public constant ETH_STKWELL_UNSTAKE_WINDOW = 2 days;
    uint128 public constant ETH_STKWELL_DISTRIBUTION_DURATION = 1 days;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x44/x44.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        initProposal(addresses);

        (, address deployerAddress, ) = vm.readCallers();

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);

        if (DO_BUILD) build(addresses);
        if (DO_RUN) run(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_VALIDATE) {
            validate(addresses, deployerAddress);
            console.log("Validation completed for proposal ", this.name());
        }
        if (DO_PRINT) {
            printProposalActionSteps();

            addresses.removeAllRestrictions();
            printCalldata(addresses);

            _printAddressesChanges(addresses);
        }
    }

    function deploy(Addresses addresses, address) public override {
        // Moonbeam
        if (!addresses.isAddressSet("STK_GOVTOKEN_IMPL_V2")) {
            vm.startBroadcast();
            address implementation = deployCode(
                "artifacts/foundry/StakedWellMoonbeam.sol/StakedWellMoonbeam.json"
            );

            require(
                implementation != address(0),
                "MIP-X44: failed to deploy STK_GOVTOKEN_IMPL_V2"
            );

            // Save new implementation
            addresses.addAddress("STK_GOVTOKEN_IMPL_V2", implementation);
            vm.stopBroadcast();
        }

        // Base
        vm.selectFork(BASE_FORK_ID);
        if (!addresses.isAddressSet("STK_GOVTOKEN_IMPL_V2")) {
            vm.startBroadcast();
            address implementation = deployCode(
                "artifacts/foundry/StakedWell.sol/StakedWell.json"
            );

            require(
                implementation != address(0),
                "MIP-X44: failed to deploy STK_GOVTOKEN_IMPL_V2"
            );

            // Save new implementation
            addresses.addAddress("STK_GOVTOKEN_IMPL_V2", implementation);
            vm.stopBroadcast();
        }

        // OP
        vm.selectFork(OPTIMISM_FORK_ID);
        if (!addresses.isAddressSet("STK_GOVTOKEN_IMPL_V2")) {
            vm.startBroadcast();
            address implementation = deployCode(
                "artifacts/foundry/StakedWell.sol/StakedWell.json"
            );

            require(
                implementation != address(0),
                "MIP-X44: failed to deploy STK_GOVTOKEN_IMPL_V2"
            );

            // Save new implementation
            addresses.addAddress("STK_GOVTOKEN_IMPL_V2", implementation);
            vm.stopBroadcast();
        }

        // Ethereum - Verify xWELL and stkWELL are deployed
        // NOTE: Ethereum deployment is handled separately via script/DeployXWellEthereum.s.sol
        // This is because multichain proposals cannot handle library linking for xWELL's Zelt libraries.
        // Run the deployment script before executing this proposal:
        //   forge script script/DeployXWellEthereum.s.sol:DeployXWellEthereum --rpc-url ethereum --broadcast
        vm.selectFork(ETHEREUM_FORK_ID);
        require(
            addresses.isAddressSet("xWELL_PROXY"),
            "Ethereum xWELL must be deployed before running this proposal. Run script/DeployXWellEthereum.s.sol first."
        );
        require(
            addresses.isAddressSet("STK_GOVTOKEN_PROXY"),
            "Ethereum stkWELL must be deployed before running this proposal. Run script/DeployXWellEthereum.s.sol first."
        );
        require(
            addresses.isAddressSet("PROXY_ADMIN"),
            "Ethereum PROXY_ADMIN must be deployed before running this proposal. Run script/DeployXWellEthereum.s.sol first."
        );

        // Switch back to Moonbeam
        vm.selectFork(primaryForkId());
    }

    function build(Addresses addresses) public override {
        // Moonbeam: upgrade stkWELL proxy with initializeV2
        _pushAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                addresses.getAddress("STK_GOVTOKEN_PROXY"),
                addresses.getAddress("STK_GOVTOKEN_IMPL_V2"),
                abi.encodeWithSignature("initializeV2()")
            ),
            "Upgrade stkWELL on Moonbeam via upgradeAndCall (with initializeV2)"
        );

        // Moonbeam: call setNewStakedWell on MultichainGovernor to enable timestamp mode
        _pushAction(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
            abi.encodeWithSignature(
                "setNewStakedWell(address,bool)",
                addresses.getAddress("STK_GOVTOKEN_PROXY"),
                true // toUseTimestamps
            ),
            "Enable timestamp mode on MultichainGovernor for stkWELL"
        );

        // Base: upgrade stkWELL proxy (no initializeV2 needed)
        vm.selectFork(BASE_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("STK_GOVTOKEN_PROXY"),
                addresses.getAddress("STK_GOVTOKEN_IMPL_V2")
            ),
            "Upgrade stkWELL on Base"
        );

        // Optimism: upgrade stkWELL proxy (no initializeV2 needed)
        vm.selectFork(OPTIMISM_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("STK_GOVTOKEN_PROXY"),
                addresses.getAddress("STK_GOVTOKEN_IMPL_V2")
            ),
            "Upgrade stkWELL on Optimism"
        );

        // Switch back to Moonbeam
        vm.selectFork(primaryForkId());
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        // Validate Moonbeam
        vm.selectFork(primaryForkId());
        _validateMoonbeamUpgrade(addresses);

        // Validate Base
        vm.selectFork(BASE_FORK_ID);
        _validateBaseUpgrade(addresses);

        // Validate Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        _validateOptimismUpgrade(addresses);

        // Validate Ethereum deployment
        vm.selectFork(ETHEREUM_FORK_ID);
        _validateEthereumDeployment(addresses);

        // Switch back to Moonbeam
        vm.selectFork(primaryForkId());
    }

    function _validateMoonbeamUpgrade(Addresses addresses) internal {
        address proxyAdmin = addresses.getAddress("MOONBEAM_PROXY_ADMIN");
        address proxy = addresses.getAddress("STK_GOVTOKEN_PROXY");
        address expectedImpl = addresses.getAddress("STK_GOVTOKEN_IMPL_V2");

        // Validate proxy points to new implementation
        address actualImpl = _getProxyImplementation(proxyAdmin, proxy);
        assertEq(
            actualImpl,
            expectedImpl,
            "Moonbeam stkWELL implementation not upgraded"
        );

        // Validate initializeV2 was called by checking defaultSnapshotTimestamp
        (bool success, bytes memory data) = proxy.staticcall(
            abi.encodeWithSignature("defaultSnapshotTimestamp()")
        );
        require(success, "Failed to read defaultSnapshotTimestamp");
        uint256 defaultSnapshotTimestamp = abi.decode(data, (uint256));
        assertGt(
            defaultSnapshotTimestamp,
            0,
            "initializeV2 not called - defaultSnapshotTimestamp is 0"
        );

        // Validate MultichainGovernor useTimestamps is true
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");
        (bool timestampSuccess, bytes memory timestampData) = governor
            .staticcall(abi.encodeWithSignature("useTimestamps()"));
        require(timestampSuccess, "Failed to read useTimestamps");
        bool useTimestamps = abi.decode(timestampData, (bool));
        assertTrue(
            useTimestamps,
            "MultichainGovernor useTimestamps not enabled"
        );
    }

    function _validateBaseUpgrade(Addresses addresses) internal {
        address proxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");
        address proxy = addresses.getAddress("STK_GOVTOKEN_PROXY");
        address expectedImpl = addresses.getAddress("STK_GOVTOKEN_IMPL_V2");

        // Validate proxy points to new implementation
        address actualImpl = _getProxyImplementation(proxyAdmin, proxy);
        assertEq(
            actualImpl,
            expectedImpl,
            "Base stkWELL implementation not upgraded"
        );
    }

    function _validateOptimismUpgrade(Addresses addresses) internal {
        address proxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");
        address proxy = addresses.getAddress("STK_GOVTOKEN_PROXY");
        address expectedImpl = addresses.getAddress("STK_GOVTOKEN_IMPL_V2");

        // Validate proxy points to new implementation
        address actualImpl = _getProxyImplementation(proxyAdmin, proxy);
        assertEq(
            actualImpl,
            expectedImpl,
            "Optimism stkWELL implementation not upgraded"
        );
    }

    function _getProxyImplementation(
        address proxyAdmin,
        address proxy
    ) internal view returns (address) {
        (bool success, bytes memory data) = proxyAdmin.staticcall(
            abi.encodeWithSignature("getProxyImplementation(address)", proxy)
        );
        require(success, "Failed to get proxy implementation");
        return abi.decode(data, (address));
    }

    /// @notice Validate Ethereum xWELL and stkWELL deployment
    /// @dev Adapted from xwellDeployBase validation logic
    /// @param addresses The addresses contract
    function _validateEthereumDeployment(Addresses addresses) private {
        // Get addresses from Ethereum fork (current fork)
        address xwellProxy = addresses.getAddress("xWELL_PROXY");
        address wormholeAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        address proxyAdmin = addresses.getAddress("PROXY_ADMIN");
        address stkWellProxy = addresses.getAddress("STK_GOVTOKEN_PROXY");
        address ecosystemReserveProxy = addresses.getAddress(
            "ECOSYSTEM_RESERVE_PROXY"
        );

        assertEq(
            address(WormholeBridgeAdapter(wormholeAdapter).wormholeRelayer()),
            addresses.getAddress("WORMHOLE_BRIDGE_RELAYER_PROXY"),
            "Ethereum: wormhole bridge adapter relayer is incorrect"
        );

        assertEq(
            WormholeBridgeAdapter(wormholeAdapter).gasLimit(),
            300_000,
            "Ethereum: wormhole bridge adapter gas limit is incorrect"
        );

        assertEq(
            xWELL(xwellProxy).pendingOwner(),
            address(0),
            "Ethereum: xWELL pending owner should be address(0)"
        );

        // Validate pause duration
        assertEq(
            xWELL(xwellProxy).pauseDuration(),
            ETH_XWELL_PAUSE_DURATION,
            "Ethereum: pause duration is incorrect"
        );

        // Validate rate limits
        assertEq(
            xWELL(xwellProxy).rateLimitPerSecond(wormholeAdapter),
            ETH_XWELL_RATE_LIMIT_PER_SECOND,
            "Ethereum: rateLimitPerSecond is incorrect"
        );

        // Validate buffer cap
        assertEq(
            xWELL(xwellProxy).bufferCap(wormholeAdapter),
            ETH_XWELL_BUFFER_CAP,
            "Ethereum: bufferCap is incorrect"
        );

        // Validate proxy admin is admin of xWELL proxy
        assertEq(
            ProxyAdmin(proxyAdmin).getProxyAdmin(
                ITransparentUpgradeableProxy(xwellProxy)
            ),
            proxyAdmin,
            "Ethereum: ProxyAdmin is not admin of xWELL proxy"
        );

        // Validate proxy admin is admin of wormhole adapter proxy
        assertEq(
            ProxyAdmin(proxyAdmin).getProxyAdmin(
                ITransparentUpgradeableProxy(wormholeAdapter)
            ),
            proxyAdmin,
            "Ethereum: ProxyAdmin is not admin of wormhole adapter proxy"
        );

        // Validate stkWELL deployment
        assertEq(
            address(IStakedWell(stkWellProxy).STAKED_TOKEN()),
            xwellProxy,
            "Ethereum: stkWELL staked token should be xWELL"
        );

        assertEq(
            address(IStakedWell(stkWellProxy).REWARD_TOKEN()),
            xwellProxy,
            "Ethereum: stkWELL reward token should be xWELL"
        );

        assertEq(
            IStakedWell(stkWellProxy).COOLDOWN_SECONDS(),
            ETH_STKWELL_COOLDOWN_SECONDS,
            "Ethereum: stkWELL cooldown seconds is incorrect"
        );

        assertEq(
            IStakedWell(stkWellProxy).UNSTAKE_WINDOW(),
            ETH_STKWELL_UNSTAKE_WINDOW,
            "Ethereum: stkWELL unstake window is incorrect"
        );

        assertEq(
            address(IStakedWell(stkWellProxy).REWARDS_VAULT()),
            ecosystemReserveProxy,
            "Ethereum: stkWELL rewards vault should be ecosystem reserve"
        );

        assertEq(
            IStakedWell(stkWellProxy).EMISSION_MANAGER(),
            addresses.getAddress("MOONWELL_DEPLOYER"),
            "Ethereum: stkWELL emission manager should be MOONWELL_DEPLOYER"
        );

        // Validate proxy admin is admin of stkWELL proxy
        assertEq(
            ProxyAdmin(proxyAdmin).getProxyAdmin(
                ITransparentUpgradeableProxy(stkWellProxy)
            ),
            proxyAdmin,
            "Ethereum: ProxyAdmin is not admin of stkWELL proxy"
        );

        // Validate proxy admin is admin of ecosystem reserve proxy
        assertEq(
            ProxyAdmin(proxyAdmin).getProxyAdmin(
                ITransparentUpgradeableProxy(ecosystemReserveProxy)
            ),
            proxyAdmin,
            "Ethereum: ProxyAdmin is not admin of ecosystem reserve proxy"
        );
    }
}
