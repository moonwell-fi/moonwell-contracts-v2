pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MorphoVaultV2Views, IMorphoVaultV2} from "@protocol/views/MorphoVaultV2Views.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import "@utils/ChainIds.sol";

contract MorphoVaultV2ViewsTest is PostProposalCheck {
    using ChainIds for uint256;

    MorphoVaultV2Views public viewsContract;
    MorphoVaultV2Views public implementation;

    address public proxyAdmin = address(1337);

    // Addresses fetched from Addresses contract
    address public vaultV2meUSDC;
    address public metaMorphomeUSDC;

    function setUp() public override {
        super.setUp();

        // Switch to Base fork for testing
        vm.selectFork(BASE_FORK_ID);

        // Fetch addresses from Addresses contract
        vaultV2meUSDC = addresses.getAddress("MORPHO_meUSDC_VAULT_V2");
        metaMorphomeUSDC = addresses.getAddress("meUSDC_METAMORPHO_VAULT");

        address comptroller = addresses.getAddress("UNITROLLER");

        implementation = new MorphoVaultV2Views();

        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address)",
            comptroller
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            proxyAdmin,
            initdata
        );

        viewsContract = MorphoVaultV2Views(address(proxy));
    }

    // ==================== VAULT INFO TESTS ====================

    /// @notice Test getting single vault info
    function testGetVaultInfo() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        assertEq(info.vault, vaultV2meUSDC);
        assertEq(info.name, "Moonwell Ecosystem USDC");
        assertEq(info.symbol, "meUSDC");
        assertGt(info.totalAssets, 0);
        assertGt(info.totalSupply, 0);
        assertTrue(info.owner != address(0));
        assertTrue(info.curator != address(0));
        assertTrue(info.adapterRegistry != address(0));
    }

    /// @notice Test vault has adapters
    function testVaultHasAdapters() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        // meUSDC has at least 1 adapter
        assertGe(info.adapters.length, 1);

        // First adapter should have an address and real assets
        assertTrue(info.adapters[0].adapter != address(0));
        assertGt(info.adapters[0].realAssets, 0);
    }

    /// @notice Test adapter points to underlying MetaMorpho
    function testAdapterUnderlyingVault() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        // Adapter should point to MetaMorpho vault
        assertEq(info.adapters[0].underlyingVault, metaMorphomeUSDC);
        assertEq(
            info.adapters[0].underlyingVaultName,
            "Moonwell Ecosystem USDC Vault"
        );
        assertGt(info.adapters[0].underlyingVaultTotalAssets, 0);
    }

    /// @notice Test allocation percentage is calculated correctly
    function testAdapterAllocationPercentage() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        // With only 1 adapter, allocation should be ~100% (1e18)
        // Allow some small variance for rounding
        assertGt(info.adapters[0].allocationPercentage, 0.99e18);
        assertLe(info.adapters[0].allocationPercentage, 1e18);
    }

    /// @notice Test asset metadata is populated
    function testAssetMetadata() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        // USDC metadata
        assertEq(info.assetSymbol, "USDC");
        assertEq(info.assetDecimals, 6);
        assertTrue(bytes(info.assetName).length > 0);
    }

    /// @notice Test underlying price is fetched
    function testUnderlyingPrice() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        // USDC should be ~$1 (between $0.90 and $1.10)
        assertGt(info.underlyingPrice, 0.9e18);
        assertLt(info.underlyingPrice, 1.1e18);
    }

    // ==================== MULTIPLE VAULTS TESTS ====================

    /// @notice Test getting multiple vaults info
    function testGetVaultsInfo() public view {
        address[] memory vaults = new address[](1);
        vaults[0] = vaultV2meUSDC;

        MorphoVaultV2Views.VaultV2Info[] memory infos = viewsContract
            .getVaultsInfo(vaults);

        assertEq(infos.length, 1);
        assertEq(infos[0].vault, vaultV2meUSDC);
    }

    /// @notice Test empty array returns empty result
    function testGetVaultsInfoEmptyArray() public view {
        address[] memory emptyVaults = new address[](0);

        MorphoVaultV2Views.VaultV2Info[] memory infos = viewsContract
            .getVaultsInfo(emptyVaults);

        assertEq(infos.length, 0);
    }

    // ==================== USER BALANCE TESTS ====================

    /// @notice Test getting user balance
    function testGetUserBalance() public view {
        // Use a test address that likely has no balance
        address user = addresses.getAddress("TEMPORAL_GOVERNOR");

        MorphoVaultV2Views.UserVaultBalance memory balance = viewsContract
            .getUserBalance(vaultV2meUSDC, user);

        assertEq(balance.vault, vaultV2meUSDC);
        // Balance may be 0 for this user, that's fine
        assertEq(balance.shares >= 0, true);
    }

    /// @notice Test getting multiple user balances
    function testGetUserBalances() public view {
        address user = addresses.getAddress("TEMPORAL_GOVERNOR");

        address[] memory vaults = new address[](1);
        vaults[0] = vaultV2meUSDC;

        MorphoVaultV2Views.UserVaultBalance[] memory balances = viewsContract
            .getUserBalances(vaults, user);

        assertEq(balances.length, 1);
        assertEq(balances[0].vault, vaultV2meUSDC);
    }

    /// @notice Test user balance empty array
    function testGetUserBalancesEmptyArray() public view {
        address user = addresses.getAddress("TEMPORAL_GOVERNOR");
        address[] memory emptyVaults = new address[](0);

        MorphoVaultV2Views.UserVaultBalance[] memory balances = viewsContract
            .getUserBalances(emptyVaults, user);

        assertEq(balances.length, 0);
    }

    // ==================== ADAPTER INFO TESTS ====================

    /// @notice Test getting adapter underlying info directly
    function testGetAdapterUnderlyingInfo() public view {
        // Get the first adapter from the vault
        address adapter = IMorphoVaultV2(vaultV2meUSDC).adapters(0);

        (address vault, uint256 totalAssets, uint256 markets) = viewsContract
            .getAdapterUnderlyingInfo(adapter);

        assertEq(vault, metaMorphomeUSDC);
        assertGt(totalAssets, 0);
        assertGt(markets, 0); // MetaMorpho should have markets
    }

    // ==================== INITIALIZATION TESTS ====================

    /// @notice Test that re-initialization reverts
    function testCannotReinitialize() public {
        address comptroller = addresses.getAddress("UNITROLLER");

        vm.expectRevert("Initializable: contract is already initialized");
        viewsContract.initialize(comptroller);
    }

    /// @notice Test that implementation cannot be initialized directly
    function testImplementationCannotBeInitialized() public {
        address comptroller = addresses.getAddress("UNITROLLER");

        vm.expectRevert("Initializable: contract is already initialized");
        implementation.initialize(comptroller);
    }

    // ==================== DATA INTEGRITY TESTS ====================

    /// @notice Test that vault totalAssets matches adapter realAssets
    function testVaultAssetsMatchAdapterAssets() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        // Sum of all adapter realAssets should approximately equal vault totalAssets
        uint256 totalAdapterAssets = 0;
        for (uint256 i = 0; i < info.adapters.length; i++) {
            totalAdapterAssets += info.adapters[i].realAssets;
        }

        // Allow 0.1% variance for rounding
        uint256 variance = info.totalAssets / 1000;
        assertGe(totalAdapterAssets, info.totalAssets - variance);
        assertLe(totalAdapterAssets, info.totalAssets + variance);
    }

    /// @notice Test that convertToAssets works correctly for shares
    function testShareToAssetConversion() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        // If totalSupply > 0, convertToAssets should give reasonable value
        if (info.totalSupply > 0) {
            // 1 share should be worth some assets
            uint256 assetsPerShare = (info.totalAssets * 1e18) /
                info.totalSupply;
            assertGt(assetsPerShare, 0);
        }
    }

    // ==================== UNDERLYING VAULT DATA TESTS ====================

    /// @notice Test underlying vault fee is returned
    function testUnderlyingVaultFee() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        // Fee should be a valid percentage (0-100% = 0-1e18)
        // MetaMorpho fees are typically 0-15%
        assertLe(info.adapters[0].underlyingVaultFee, 0.15e18);
    }

    /// @notice Test underlying vault timelock is returned
    function testUnderlyingVaultTimelock() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        // Timelock can be 0 or any positive value
        // Just verify it doesn't revert
        assertTrue(info.adapters[0].underlyingVaultTimelock >= 0);
    }

    /// @notice Test underlying markets are returned
    function testUnderlyingMarketsExist() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        // MetaMorpho vault should have at least 1 underlying market
        assertGt(info.adapters[0].underlyingMarkets.length, 0);
    }

    /// @notice Test underlying market data is populated
    function testUnderlyingMarketData() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        // Get first market from first adapter
        MorphoVaultV2Views.UnderlyingMarketInfo memory market = info
            .adapters[0]
            .underlyingMarkets[0];

        // Market ID should be non-zero
        assertTrue(market.marketId != bytes32(0));

        // LLTV should be a valid percentage (typically 0-100% = 0-1e18)
        assertLe(market.marketLltv, 1e18);
    }

    /// @notice Test market collateral info is populated
    function testMarketCollateralInfo() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        // Get first market from first adapter
        MorphoVaultV2Views.UnderlyingMarketInfo memory market = info
            .adapters[0]
            .underlyingMarkets[0];

        // Collateral token should have a valid address (or be address(0) for idle market)
        // If collateral exists, it should have name and symbol
        if (market.collateralToken != address(0)) {
            assertTrue(bytes(market.collateralName).length > 0);
            assertTrue(bytes(market.collateralSymbol).length > 0);
        }
    }

    /// @notice Test market APYs are reasonable
    function testMarketApys() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        // Check all markets have reasonable APYs
        for (
            uint256 i = 0;
            i < info.adapters[0].underlyingMarkets.length;
            i++
        ) {
            MorphoVaultV2Views.UnderlyingMarketInfo memory market = info
                .adapters[0]
                .underlyingMarkets[i];

            // Supply APY should be less than 1000% (10e18)
            assertLt(market.marketSupplyApy, 10e18);

            // Borrow APY should be less than 1000% (10e18)
            assertLt(market.marketBorrowApy, 10e18);

            // Supply APY should be <= Borrow APY (suppliers earn less than borrowers pay)
            assertLe(market.marketSupplyApy, market.marketBorrowApy);
        }
    }

    /// @notice Test market liquidity is calculated
    function testMarketLiquidity() public view {
        MorphoVaultV2Views.VaultV2Info memory info = viewsContract.getVaultInfo(
            vaultV2meUSDC
        );

        // At least one market should have liquidity
        bool hasLiquidity = false;
        for (
            uint256 i = 0;
            i < info.adapters[0].underlyingMarkets.length;
            i++
        ) {
            if (info.adapters[0].underlyingMarkets[i].marketLiquidity > 0) {
                hasLiquidity = true;
                break;
            }
        }
        assertTrue(hasLiquidity, "At least one market should have liquidity");
    }
}
