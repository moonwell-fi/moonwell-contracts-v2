//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, ETHEREUM_FORK_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";

interface IStakedWellMoonbeam {
    function initializeV2() external;
}

/// @title MIP-X45: Upgrade StakedWell contracts on Base, OP, and Moonbeam; Deploy to Ethereum
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
contract mipx45 is HybridProposal {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-X45";

    /// @notice Before-state snapshots for storage preservation checks
    struct StkWellSnapshot {
        address stakedToken;
        address rewardToken;
        uint256 cooldownSeconds;
        uint256 unstakeWindow;
        address rewardsVault;
        address emissionManager;
        uint256 totalSupply;
        uint128 emissionsPerSecond;
        uint256 stakeTimestamp;
    }

    StkWellSnapshot public moonbeamBefore;
    StkWellSnapshot public baseBefore;
    StkWellSnapshot public optimismBefore;

    address public moonbeamStakedWellBefore;

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
            vm.readFile("./proposals/mips/mip-x45/x45.md")
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
        if (DO_RUN) simulate(addresses, deployerAddress);
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
                "MIP-X45: failed to deploy STK_GOVTOKEN_IMPL_V2"
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
                "MIP-X45: failed to deploy STK_GOVTOKEN_IMPL_V2"
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
                "MIP-X45: failed to deploy STK_GOVTOKEN_IMPL_V2"
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

    /// @notice Snapshot stkWELL storage state on the current fork
    function _snapshotStkWell(
        address proxy
    ) internal view returns (StkWellSnapshot memory) {
        IStakedWell stkWell = IStakedWell(proxy);
        (uint128 emissionsPerSecond, , ) = stkWell.assets(proxy);
        return
            StkWellSnapshot({
                stakedToken: address(stkWell.STAKED_TOKEN()),
                rewardToken: address(stkWell.REWARD_TOKEN()),
                cooldownSeconds: stkWell.COOLDOWN_SECONDS(),
                unstakeWindow: stkWell.UNSTAKE_WINDOW(),
                rewardsVault: address(stkWell.REWARDS_VAULT()),
                emissionManager: stkWell.EMISSION_MANAGER(),
                totalSupply: stkWell.totalSupply(),
                emissionsPerSecond: emissionsPerSecond,
                stakeTimestamp: 0
            });
    }

    /// @notice Stake tokens before the proposal executes to simulate existing stakers
    function beforeSimulationHook(Addresses addresses) public override {
        address testUser = address(0xBEEF);
        uint256 stakeAmount = 1_000 * 1e18;

        // Stake then snapshot on Moonbeam
        vm.selectFork(primaryForkId());
        _stakeTokens(
            addresses.getAddress("STK_GOVTOKEN_PROXY"),
            testUser,
            stakeAmount
        );
        moonbeamBefore = _snapshotStkWell(
            addresses.getAddress("STK_GOVTOKEN_PROXY")
        );
        moonbeamBefore.stakeTimestamp = block.timestamp;
        moonbeamStakedWellBefore = address(
            MultichainGovernor(
                payable(addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"))
            ).stkWell()
        );

        // Stake then snapshot on Base
        vm.selectFork(BASE_FORK_ID);
        _stakeTokens(
            addresses.getAddress("STK_GOVTOKEN_PROXY"),
            testUser,
            stakeAmount
        );
        baseBefore = _snapshotStkWell(
            addresses.getAddress("STK_GOVTOKEN_PROXY")
        );
        baseBefore.stakeTimestamp = block.timestamp;

        // Stake then snapshot on Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        _stakeTokens(
            addresses.getAddress("STK_GOVTOKEN_PROXY"),
            testUser,
            stakeAmount
        );
        optimismBefore = _snapshotStkWell(
            addresses.getAddress("STK_GOVTOKEN_PROXY")
        );
        optimismBefore.stakeTimestamp = block.timestamp;

        // Switch back to primary fork
        vm.selectFork(primaryForkId());
    }

    /// @notice Deal tokens and stake for a user on the current fork
    function _stakeTokens(
        address stkWellProxy,
        address user,
        uint256 amount
    ) internal {
        IStakedWell stkWell = IStakedWell(stkWellProxy);
        address stakedToken = address(stkWell.STAKED_TOKEN());

        uint256 balanceBefore = stkWell.balanceOf(user);

        deal(stakedToken, user, amount);

        vm.startPrank(user);
        IERC20(stakedToken).approve(stkWellProxy, amount);
        stkWell.stake(user, amount);
        vm.stopPrank();

        assertEq(
            stkWell.balanceOf(user),
            balanceBefore + amount,
            "beforeSimulationHook: stake failed"
        );
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

        // Validate Ethereum deployment.
        // Earlier proposal simulations (e.g. RewardsDistribution template) may call vm.makePersistent on the
        // WORMHOLE_BRIDGE_ADAPTER_PROXY, which shares the same address across Moonbeam and Ethereum.
        // This corrupts fork state with Moonbeam data.
        vm.revokePersistent(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        uint256 freshEthFork = vm.createFork("ethereum");
        vm.selectFork(freshEthFork);
        _validateEthereumDeployment(addresses);

        // Switch back to Moonbeam
        vm.selectFork(primaryForkId());
    }

    function _validateMoonbeamUpgrade(Addresses addresses) internal {
        address proxy = addresses.getAddress("STK_GOVTOKEN_PROXY");

        // Validate proxy points to new implementation
        assertEq(
            _getProxyImplementation(
                addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
                proxy
            ),
            addresses.getAddress("STK_GOVTOKEN_IMPL_V2"),
            "Moonbeam stkWELL implementation not upgraded"
        );

        // Validate initializeV2 was called by checking defaultSnapshotTimestamp
        _assertInitializeV2Called(proxy);

        // Validate storage preservation after upgrade
        _assertStoragePreserved(proxy, moonbeamBefore, "Moonbeam");

        // Validate MultichainGovernor state after setNewStakedWell
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");
        _validateGovernorState(governor, proxy, moonbeamStakedWellBefore);

        // Sanity check: stake and unstake works after upgrade
        _validateStakeAndUnstake(proxy, "Moonbeam");

        // Validate initializeV2() cannot be called again (reinitializer guard)
        vm.expectRevert();
        IStakedWellMoonbeam(proxy).initializeV2();

        // Validate initialize() cannot be called again (already initialized)
        vm.expectRevert();
        IStakedWell(proxy).initialize(
            address(0),
            address(0),
            0,
            0,
            address(0),
            address(0),
            0,
            address(0)
        );

        // End-to-end: verify MultichainGovernor.getVotes includes stkWELL contribution
        _validateGovernorGetVotes(proxy, governor);
    }

    /// @notice Validate initializeV2 was called on the Moonbeam stkWELL proxy
    function _assertInitializeV2Called(address proxy) internal view {
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
    }

    /// @notice Validate MultichainGovernor state after setNewStakedWell
    function _validateGovernorState(
        address governor,
        address expectedStkWell,
        address expectedStkWellBefore
    ) internal view {
        // Validate useTimestamps is true
        (bool timestampSuccess, bytes memory timestampData) = governor
            .staticcall(abi.encodeWithSignature("useTimestamps()"));
        require(timestampSuccess, "Failed to read useTimestamps");
        assertTrue(
            abi.decode(timestampData, (bool)),
            "MultichainGovernor useTimestamps not enabled"
        );

        // Validate stkWell address
        (bool stkWellSuccess, bytes memory stkWellData) = governor.staticcall(
            abi.encodeWithSignature("stkWell()")
        );
        require(stkWellSuccess, "Failed to read stkWell");
        assertEq(
            abi.decode(stkWellData, (address)),
            expectedStkWell,
            "MultichainGovernor stkWell address incorrect"
        );
        assertEq(
            abi.decode(stkWellData, (address)),
            expectedStkWellBefore,
            "MultichainGovernor stkWell address changed after setNewStakedWell"
        );

        // Validate governance parameters are unchanged after setNewStakedWell
        (bool thresholdSuccess, bytes memory thresholdData) = governor
            .staticcall(abi.encodeWithSignature("proposalThreshold()"));
        require(thresholdSuccess, "Failed to read proposalThreshold");
        assertGt(
            abi.decode(thresholdData, (uint256)),
            0,
            "MultichainGovernor proposalThreshold should be > 0"
        );

        (bool quorumSuccess, bytes memory quorumData) = governor.staticcall(
            abi.encodeWithSignature("quorum()")
        );
        require(quorumSuccess, "Failed to read quorum");
        assertGt(
            abi.decode(quorumData, (uint256)),
            0,
            "MultichainGovernor quorum should be > 0"
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

        // Validate storage preservation after upgrade
        _assertStoragePreserved(proxy, baseBefore, "Base");

        // Validate configureAssets is removed in V2
        _assertConfigureAssetsRemoved(proxy, "Base");

        // Validate initializeV2() does not exist on Base stkWELL
        vm.expectRevert();
        IStakedWellMoonbeam(proxy).initializeV2();

        // Sanity check: stake and unstake works after upgrade
        _validateStakeAndUnstake(proxy, "Base");
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

        // Validate storage preservation after upgrade
        _assertStoragePreserved(proxy, optimismBefore, "Optimism");

        // Validate configureAssets is removed in V2
        _assertConfigureAssetsRemoved(proxy, "Optimism");

        // Validate initializeV2() does not exist on Optimism stkWELL
        vm.expectRevert();
        IStakedWellMoonbeam(proxy).initializeV2();

        // Sanity check: stake and unstake works after upgrade
        _validateStakeAndUnstake(proxy, "Optimism");
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

    /// @notice Assert that stkWELL storage-backed getters are preserved after upgrade
    function _assertStoragePreserved(
        address proxy,
        StkWellSnapshot memory before,
        string memory chainName
    ) internal view {
        IStakedWell stkWell = IStakedWell(proxy);
        assertEq(
            address(stkWell.STAKED_TOKEN()),
            before.stakedToken,
            string.concat(chainName, ": STAKED_TOKEN changed after upgrade")
        );
        assertEq(
            address(stkWell.REWARD_TOKEN()),
            before.rewardToken,
            string.concat(chainName, ": REWARD_TOKEN changed after upgrade")
        );
        assertEq(
            stkWell.COOLDOWN_SECONDS(),
            before.cooldownSeconds,
            string.concat(chainName, ": COOLDOWN_SECONDS changed after upgrade")
        );
        assertEq(
            stkWell.UNSTAKE_WINDOW(),
            before.unstakeWindow,
            string.concat(chainName, ": UNSTAKE_WINDOW changed after upgrade")
        );
        assertEq(
            address(stkWell.REWARDS_VAULT()),
            before.rewardsVault,
            string.concat(chainName, ": REWARDS_VAULT changed after upgrade")
        );
        assertEq(
            stkWell.EMISSION_MANAGER(),
            before.emissionManager,
            string.concat(chainName, ": EMISSION_MANAGER changed after upgrade")
        );
        assertEq(
            stkWell.totalSupply(),
            before.totalSupply,
            string.concat(chainName, ": totalSupply changed after upgrade")
        );
        (uint128 emissionsAfter, , ) = stkWell.assets(proxy);
        assertEq(
            emissionsAfter,
            before.emissionsPerSecond,
            string.concat(
                chainName,
                ": emissionsPerSecond changed after upgrade"
            )
        );
    }

    /// @notice Validate Ethereum xWELL and stkWELL deployment
    /// @dev Adapted from xwellDeployBase validation logic
    /// @param addresses The addresses contract
    function _validateEthereumDeployment(Addresses addresses) private view {
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

        // Validate xWELL ownership
        address deployer = addresses.getAddress("MOONWELL_DEPLOYER");
        assertEq(
            xWELL(xwellProxy).owner(),
            deployer,
            "Ethereum: xWELL owner should be MOONWELL_DEPLOYER"
        );

        assertEq(
            xWELL(xwellProxy).pendingOwner(),
            address(0),
            "Ethereum: xWELL pending owner should be address(0)"
        );

        // Validate WormholeBridgeAdapter ownership
        assertEq(
            WormholeBridgeAdapter(wormholeAdapter).owner(),
            deployer,
            "Ethereum: WormholeBridgeAdapter owner should be MOONWELL_DEPLOYER"
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

        // Validate stkWELL proxy has a non-zero implementation
        address stkWellImpl = ProxyAdmin(proxyAdmin).getProxyImplementation(
            ITransparentUpgradeableProxy(stkWellProxy)
        );
        assertTrue(
            stkWellImpl != address(0),
            "Ethereum: stkWELL proxy must have non-zero implementation"
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

        // Validate EcosystemReserve fundsAdmin is the EcosystemReserveController
        address ecosystemReserveController = addresses.getAddress(
            "ECOSYSTEM_RESERVE_CONTROLLER"
        );
        (
            bool fundsAdminSuccess,
            bytes memory fundsAdminData
        ) = ecosystemReserveProxy.staticcall(
                abi.encodeWithSignature("getFundsAdmin()")
            );
        require(fundsAdminSuccess, "Failed to read getFundsAdmin");
        address fundsAdmin = abi.decode(fundsAdminData, (address));
        assertEq(
            fundsAdmin,
            ecosystemReserveController,
            "Ethereum: EcosystemReserve fundsAdmin should be EcosystemReserveController"
        );

        // Validate WormholeBridgeAdapter trusted senders for all source chains
        assertTrue(
            WormholeBridgeAdapter(wormholeAdapter).isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    MOONBEAM_CHAIN_ID
                )
            ),
            "Ethereum: Moonbeam wormhole adapter not trusted"
        );
        assertTrue(
            WormholeBridgeAdapter(wormholeAdapter).isTrustedSender(
                BASE_WORMHOLE_CHAIN_ID,
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    BASE_CHAIN_ID
                )
            ),
            "Ethereum: Base wormhole adapter not trusted"
        );
        assertTrue(
            WormholeBridgeAdapter(wormholeAdapter).isTrustedSender(
                OPTIMISM_WORMHOLE_CHAIN_ID,
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    OPTIMISM_CHAIN_ID
                )
            ),
            "Ethereum: Optimism wormhole adapter not trusted"
        );
    }

    /// @notice Validate that MultichainGovernor.getVotes includes stkWELL contribution end-to-end
    function _validateGovernorGetVotes(
        address stkWellProxy,
        address governor
    ) internal {
        uint256 snapshot = vm.snapshot();

        address testUser = address(0xBEEF);
        IStakedWell stkWell = IStakedWell(stkWellProxy);

        vm.warp(block.timestamp + 2);
        vm.roll(block.number + 1);

        uint256 queryTimestamp = block.timestamp - 1;
        uint256 queryBlock = block.number - 1;

        uint256 stkWellVotes = stkWell.getPriorVotes(testUser, queryTimestamp);
        assertGt(
            stkWellVotes,
            0,
            "Moonbeam: stkWELL votes should be > 0 for test staker"
        );

        (bool success, bytes memory data) = governor.staticcall(
            abi.encodeWithSignature(
                "getVotes(address,uint256,uint256)",
                testUser,
                queryTimestamp,
                queryBlock
            )
        );
        require(success, "Failed to call MultichainGovernor.getVotes");
        uint256 govVotes = abi.decode(data, (uint256));
        assertGe(
            govVotes,
            stkWellVotes,
            "Moonbeam: MultichainGovernor.getVotes should include stkWELL contribution"
        );

        vm.revertTo(snapshot);
    }

    /// @notice Assert that configureAssets is no longer callable after upgrade
    function _assertConfigureAssetsRemoved(
        address proxy,
        string memory chainName
    ) internal {
        uint128[] memory emissionsPerSecond = new uint128[](0);
        uint256[] memory totalStakeCeilings = new uint256[](0);
        address[] memory underlyingAssets = new address[](0);
        (bool success, ) = proxy.call(
            abi.encodeWithSignature(
                "configureAssets(uint128[],uint256[],address[])",
                emissionsPerSecond,
                totalStakeCeilings,
                underlyingAssets
            )
        );
        assertFalse(
            success,
            string.concat(
                chainName,
                ": configureAssets should be removed in V2"
            )
        );
    }

    /// @notice Validate that a pre-existing staker can still withdraw and has voting power after the upgrade
    /// @dev The test user staked in beforeSimulationHook before the proposal executed. This verifies the upgrade
    /// didn't break functionality for existing stakers.
    function _validateStakeAndUnstake(
        address stkWellProxy,
        string memory chainName
    ) internal {
        uint256 snapshot = vm.snapshot(); // so that the time warp and state changes don't persist

        IStakedWell stkWell = IStakedWell(stkWellProxy);
        uint256 cooldownSeconds = stkWell.COOLDOWN_SECONDS();

        address testUser = address(0xBEEF);
        uint256 stakedBalance = stkWell.balanceOf(testUser);

        // Verify the user still has their staked balance after the upgrade
        assertGt(
            stakedBalance,
            0,
            string.concat(
                chainName,
                ": staker balance should be > 0 after upgrade"
            )
        );

        // Verify voting power is preserved after upgrade.
        // Need to warp forward 1 second so the query timestamp is in the past (getPriorVotes requires this).
        // On Moonbeam (V2 upgrade), the Snapshot struct gains a new `timestamp` field. Pre-upgrade V1
        // snapshots have timestamp=0, which _getSnapshotTimestamp maps to defaultSnapshotTimestamp
        // (set during initializeV2). So we must query at block.timestamp (after the upgrade), not at
        // the original stakeTimestamp which predates defaultSnapshotTimestamp.
        // On Base/OP (V1 to V1), the stakeTimestamp works directly.
        vm.warp(block.timestamp + 1);
        uint256 queryTimestamp = block.timestamp - 1;
        uint256 votes = stkWell.getPriorVotes(testUser, queryTimestamp);
        assertEq(
            votes,
            stakedBalance,
            string.concat(
                chainName,
                ": voting power should equal staked balance after upgrade"
            )
        );

        // Initiate cooldown, warp past it, and redeem
        vm.prank(testUser);
        stkWell.cooldown();

        vm.warp(block.timestamp + cooldownSeconds + 1);

        vm.prank(testUser);
        stkWell.redeem(testUser, stakedBalance);

        // Verify balance is 0 after unstake
        assertEq(
            stkWell.balanceOf(testUser),
            0,
            string.concat(
                chainName,
                ": stkWELL balance should be 0 after unstake"
            )
        );

        vm.revertTo(snapshot);
    }
}
