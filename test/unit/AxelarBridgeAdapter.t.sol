pragma solidity 0.8.19;

import {AddressToString, StringToAddress} from "@protocol/xWELL/axelarInterfaces/AddressString.sol";

import "@test/helper/BaseTest.t.sol";

import {AxelarBridgeAdapter} from "@protocol/xWELL/AxelarBridgeAdapter.sol";
import {MockAxelarGatewayGasService} from "@test/mock/MockAxelarGatewayGasService.sol";

contract AxelarBridgeAdapterUnitTest is BaseTest {
    using StringToAddress for string;
    using AddressToString for address;

    /// @notice emitted when tokens are bridged out
    /// @param dstChainId destination chain id to send tokens to
    /// @param bridgeUser user who bridged out tokens
    /// @param tokenReceiver address to receive tokens on destination chain
    /// @param amount of tokens bridged out
    event BridgedOut(
        uint256 indexed dstChainId, address indexed bridgeUser, address indexed tokenReceiver, uint256 amount
    );

    /// @notice emitted when tokens are bridged in
    /// @param srcChainId source chain id tokens were bridged from
    /// @param tokenReceiver address to receive tokens on destination chain
    /// @param amount of tokens bridged in
    event BridgedIn(uint256 indexed srcChainId, address indexed tokenReceiver, uint256 amount);

    /// wormhole events

    /// @notice chain id of the target chain to address for bridging
    /// @param dstChainId source chain id tokens were bridged from
    /// @param tokenReceiver address to receive tokens on destination chain
    /// @param amount of tokens bridged in
    event TokensSent(uint16 indexed dstChainId, address indexed tokenReceiver, uint256 amount);

    /// @notice chain id of the target chain to address for bridging
    /// @param dstChainId destination chain id to send tokens to
    /// @param target address to send tokens to
    event TargetAddressUpdated(uint16 indexed dstChainId, address indexed target);

    /// @notice emitted when the gas limit changes on external chains
    /// @param oldGasLimit old gas limit
    /// @param newGasLimit new gas limit
    event GasLimitUpdated(uint96 oldGasLimit, uint96 newGasLimit);

    /// @notice address to send tokens to
    address to;

    /// @notice amount of tokens to mint
    uint256 amount;

    /// relayer gas cost
    uint256 public constant gasCost = 0.00001 * 1 ether;

    AxelarBridgeAdapter public adapter;

    MockAxelarGatewayGasService public gasService;

    AxelarBridgeAdapter.ChainConfig public chainConfig;

    AxelarBridgeAdapter.ChainIds public chainIds;

    string public constant axelarId = "axelar 30";

    function setUp() public override {
        super.setUp();

        chainConfig = AxelarBridgeAdapter.ChainConfig({adapter: address(this), axelarid: axelarId});

        chainIds = AxelarBridgeAdapter.ChainIds({chainid: block.chainid, axelarid: axelarId});

        (, address axelarBridgeAdapter) = deployAxelarBridgeAdapter(address(proxyAdmin));
        gasService = new MockAxelarGatewayGasService();
        vm.label(address(gasService), "gasService mock");

        adapter = AxelarBridgeAdapter(axelarBridgeAdapter);

        AxelarBridgeAdapter.ChainIds[] memory chainids = new AxelarBridgeAdapter.ChainIds[](1);
        chainids[0] = chainIds;

        AxelarBridgeAdapter.ChainConfig[] memory chainConfigs = new AxelarBridgeAdapter.ChainConfig[](1);
        chainConfigs[0] = chainConfig;

        initializeAxelarBridgeAdapter(
            address(adapter),
            address(xwellProxy),
            owner,
            address(gasService),
            address(gasService),
            chainids,
            chainConfigs
        );

        to = address(999999999999999);
        amount = 100 * 1e18;
    }

    function testSetup() public view {
        assertTrue(adapter.validChainId(block.chainid), "invalid chain id");
        assertTrue(adapter.validAxelarChainid(axelarId), "invalid axelar id");
        assertEq(adapter.owner(), owner, "invalid owner");
        assertEq(address(adapter.gasService()), address(gasService), "invalid gas service");
        assertEq(address(adapter.gateway()), address(gasService), "invalid gateway");
        assertTrue(adapter.isApproved(axelarId, address(this)), "trusted sender not set");
        assertEq(adapter.chainIdToAxelarId(block.chainid), axelarId, "incorrect mapping of chain id to axelar id");
        assertEq(adapter.axelarIdToChainId(axelarId), block.chainid, "incorrect mapping of axelar id to chain id");
        assertEq(address(xwellProxy), address(adapter.xERC20()), "incorrect xerc20 in bridge adapter");
    }

    function testReinitializeFails() public {
        vm.expectRevert("Initializable: contract is already initialized");
        initializeAxelarBridgeAdapter(
            address(adapter),
            address(xwellProxy),
            owner,
            address(gasService),
            address(gasService),
            new AxelarBridgeAdapter.ChainIds[](0),
            new AxelarBridgeAdapter.ChainConfig[](0)
        );
    }

    /// ACL Tests

    /// Failure tests
    function testAddChainIdsNonOwnerFails() public {
        vm.expectRevert("Ownable: caller is not the owner");
        adapter.addChainIds(new AxelarBridgeAdapter.ChainIds[](0));
    }

    function testRemoveChainIdsNonOwnerFails() public {
        vm.expectRevert("Ownable: caller is not the owner");
        adapter.removeChainIds(new AxelarBridgeAdapter.ChainIds[](0));
    }

    function testaddExternalChainSendersNonOwnerFails() public {
        vm.expectRevert("Ownable: caller is not the owner");
        adapter.addExternalChainSenders(new AxelarBridgeAdapter.ChainConfig[](0));
    }

    function testRemoveApprovedExternalChainSendersNonOwnerFails() public {
        vm.expectRevert("Ownable: caller is not the owner");
        adapter.removeExternalChainSenders(new AxelarBridgeAdapter.ChainConfig[](0));
    }

    /// Success tests

    function testAddChainIdsOwnerSucceeds() public {
        AxelarBridgeAdapter.ChainIds[] memory chainids = new AxelarBridgeAdapter.ChainIds[](1);

        uint256 newChainId = 999999999999999;
        string memory newAxelarId = "axelar 999999999999999";
        chainids[0].chainid = newChainId;
        chainids[0].axelarid = newAxelarId;

        vm.prank(owner);
        adapter.addChainIds(chainids);

        assertTrue(adapter.validChainId(newChainId), "invalid chain id");
        assertTrue(adapter.validAxelarChainid(newAxelarId), "invalid axelar id");
    }

    function testRemoveChainIdsOwnerSucceeds() public {
        testAddChainIdsOwnerSucceeds();

        AxelarBridgeAdapter.ChainIds[] memory chainids = new AxelarBridgeAdapter.ChainIds[](1);

        uint256 removedChainId = 999999999999999;
        string memory removedAxelarId = "axelar 999999999999999";
        chainids[0].chainid = removedChainId;
        chainids[0].axelarid = removedAxelarId;

        vm.prank(owner);
        adapter.removeChainIds(chainids);

        assertFalse(adapter.validChainId(removedChainId), "chain id not removed");
        assertFalse(adapter.validAxelarChainid(removedAxelarId), "axelar id not removed");
    }

    function testaddExternalChainSendersOwnerSucceeds() public {
        address newAdapter = address(999999999999999);

        AxelarBridgeAdapter.ChainConfig[] memory newChainConfigs = new AxelarBridgeAdapter.ChainConfig[](1);

        newChainConfigs[0].adapter = newAdapter;
        newChainConfigs[0].axelarid = axelarId;

        vm.prank(owner);
        adapter.addExternalChainSenders(newChainConfigs);

        assertTrue(adapter.isApproved(axelarId, newAdapter), "trusted sender not set");
    }

    function testRemoveApprovedExternalChainSendersOwnerSucceeds() public {
        testaddExternalChainSendersOwnerSucceeds();

        address newAdapter = address(999999999999999);

        AxelarBridgeAdapter.ChainConfig[] memory newChainConfigs = new AxelarBridgeAdapter.ChainConfig[](1);

        newChainConfigs[0].adapter = newAdapter;
        newChainConfigs[0].axelarid = axelarId;

        vm.prank(owner);
        adapter.removeExternalChainSenders(newChainConfigs);

        assertFalse(adapter.isApproved(axelarId, newAdapter), "trusted sender not un set");
    }

    /// test owner require statement failures

    function testAddChainIdsOwnerFailsPreexistingAdapterConfig() public {
        testaddExternalChainSendersOwnerSucceeds();
        address newAdapter = address(999999999999999);

        AxelarBridgeAdapter.ChainConfig[] memory newChainConfigs = new AxelarBridgeAdapter.ChainConfig[](1);

        newChainConfigs[0].adapter = newAdapter;
        newChainConfigs[0].axelarid = axelarId;

        vm.prank(owner);
        vm.expectRevert("AxelarBridge: config already approved");
        adapter.addExternalChainSenders(newChainConfigs);
    }

    function testAddChainIdsOwnerFailsNonExistingAxelarId() public {
        testaddExternalChainSendersOwnerSucceeds();

        AxelarBridgeAdapter.ChainConfig[] memory newChainConfigs = new AxelarBridgeAdapter.ChainConfig[](1);

        newChainConfigs[0].adapter = address(1000010);
        newChainConfigs[0].axelarid = "new axelar id that's invalid";

        vm.prank(owner);
        vm.expectRevert("AxelarBridge: invalid axelar id");
        adapter.addExternalChainSenders(newChainConfigs);
    }

    function testRemoveChainIdsOwnerFailsNonExistingAdaper() public {
        AxelarBridgeAdapter.ChainConfig[] memory newChainConfigs = new AxelarBridgeAdapter.ChainConfig[](1);

        /// axelar id does not matter as it is not validated, use non-approved adapter to cause revert
        newChainConfigs[0].adapter = address(1000010);

        vm.prank(owner);
        vm.expectRevert("AxelarBridge: config not already approved");
        adapter.removeExternalChainSenders(newChainConfigs);
    }

    function testAddChainIdsOwnerFailsPreexistingConfig() public {
        AxelarBridgeAdapter.ChainIds[] memory chainids = new AxelarBridgeAdapter.ChainIds[](1);
        chainids[0] = chainIds;

        vm.prank(owner);
        vm.expectRevert("AxelarBridge: existing chainId config");
        adapter.addChainIds(chainids);
    }

    function testAddChainIdsOwnerFailsPreexistingChainIdConfig() public {
        AxelarBridgeAdapter.ChainIds[] memory chainids = new AxelarBridgeAdapter.ChainIds[](1);
        chainids[0] = chainIds;
        chainids[0].chainid = 198138182811;
        /// new chainid, same axelarid

        vm.prank(owner);
        vm.expectRevert("AxelarBridge: existing axelarId config");
        adapter.addChainIds(chainids);
    }

    function testRemoveChainIdsOwnerFailsNoPreexistingConfig() public {
        AxelarBridgeAdapter.ChainIds[] memory chainids = new AxelarBridgeAdapter.ChainIds[](1);
        chainids[0].chainid = 10391821728172;

        vm.prank(owner);
        vm.expectRevert("AxelarBridge: non-existent chainid config");
        adapter.removeChainIds(chainids);
    }

    function testAddChainIdsOwnerFailsNoPreexistingAxelarIdConfig() public {
        AxelarBridgeAdapter.ChainIds[] memory chainids = new AxelarBridgeAdapter.ChainIds[](1);
        chainids[0] = chainIds;
        chainids[0].axelarid = "23892aa axelar";
        /// new axelarid, same chainid

        vm.prank(owner);
        vm.expectRevert("AxelarBridge: non-existent axelarId config");
        adapter.removeChainIds(chainids);
    }

    function testBridgeOutSuccess() public {
        _setupxERC20();

        uint256 bridgeAmount = 100 * 1e18;
        _lockboxCanMintTo(address(this), uint112(bridgeAmount));
        uint256 startingBalance = xwellProxy.balanceOf(address(this));

        xwellProxy.approve(address(adapter), bridgeAmount);
        adapter.bridge(block.chainid, bridgeAmount, address(this));

        uint256 endingBalance = xwellProxy.balanceOf(address(this));

        assertEq(startingBalance - endingBalance, bridgeAmount, "invalid xwell amount after bridge out");
    }

    function testBridgeOutFailsInvalidChainId() public {
        _setupxERC20();

        uint256 bridgeAmount = 100 * 1e18;
        _lockboxCanMintTo(address(this), uint112(bridgeAmount));

        vm.expectRevert("AxelarBridge: invalid chain id");
        adapter.bridge(block.chainid + 1, bridgeAmount, address(this));
    }

    function testBridgeInSuccess() public {
        _setupxERC20();

        uint256 bridgeAmount = 100 * 1e18;

        bytes memory payload = abi.encode(address(this), bridgeAmount);

        uint256 startingBalance = xwellProxy.balanceOf(address(this));

        adapter.execute(bytes32(bridgeAmount), axelarId, address(this).toString(), payload);

        uint256 endingBalance = xwellProxy.balanceOf(address(this));
        assertEq(endingBalance - startingBalance, bridgeAmount, "invalid xwell amount after bridge in");
    }

    function testBridgeInFailsInvalidContractGatewayCall() public {
        _setupxERC20();

        uint256 bridgeAmount = 100 * 1e18;

        bytes memory payload = abi.encode(address(this), bridgeAmount);

        gasService.setValidate(false);

        vm.expectRevert("AxelarBridgeAdapter: call not approved by gateway");
        adapter.execute(bytes32(bridgeAmount), axelarId, address(this).toString(), payload);
    }

    function testBridgeInFailsInvalidSender() public {
        _setupxERC20();

        uint256 bridgeAmount = 100 * 1e18;

        bytes memory payload = abi.encode(address(this), bridgeAmount);

        gasService.setValidate(false);

        vm.expectRevert("AxelarBridgeAdapter: sender not approved");
        adapter.execute(bytes32(bridgeAmount), axelarId, address(xwellProxy).toString(), payload);
    }

    function testBridgeInFailsInvalidSourceChain() public {
        _setupxERC20();

        uint256 bridgeAmount = 100 * 1e18;

        bytes memory payload = abi.encode(address(this), bridgeAmount);

        gasService.setValidate(false);

        vm.expectRevert("AxelarBridgeAdapter: invalid source chain");
        adapter.execute(bytes32(bridgeAmount), "made up axelar id", address(xwellProxy).toString(), payload);
    }

    function _setupxERC20() private {
        MintLimits.RateLimitMidPointInfo memory ratelimit = MintLimits.RateLimitMidPointInfo({
            bridge: address(adapter),
            bufferCap: 100_000_000 * 1e18,
            rateLimitPerSecond: 100 * 1e18
        });

        vm.prank(xwellProxy.owner());
        xwellProxy.addBridge(ratelimit);
    }
}
