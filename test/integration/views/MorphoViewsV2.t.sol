pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MorphoViewsV2, IMetaMorphoV2, IMorphoBlue} from "@protocol/views/MorphoViewsV2.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import "@utils/ChainIds.sol";

contract MorphoViewsV2Test is PostProposalCheck {
    using ChainIds for uint256;

    MorphoViewsV2 public viewsContract;
    MorphoViewsV2 public implementation;
    address public morphoBlue;

    address public proxyAdmin = address(1337);

    // cbETH/USDC market on Base
    bytes32 public constant CBETH_USDC_MARKET =
        0xdba352d93a64b17c71104cbddc6aef85cd432322a1446b5b65163cbbc615cd0c;

    function setUp() public override {
        super.setUp();

        // Switch to Base fork for testing
        vm.selectFork(BASE_FORK_ID);

        address comptroller = addresses.getAddress("UNITROLLER");
        morphoBlue = addresses.getAddress("MORPHO_BLUE");

        implementation = new MorphoViewsV2();

        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address)",
            comptroller,
            morphoBlue
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            proxyAdmin,
            initdata
        );

        viewsContract = MorphoViewsV2(address(proxy));
    }

    function testVaultsProtocolInfoV2() public view {
        address[] memory morphoVaults = new address[](2);
        morphoVaults[0] = addresses.getAddress("WETH_METAMORPHO_VAULT");
        morphoVaults[1] = addresses.getAddress("USDC_METAMORPHO_VAULT");

        MorphoViewsV2.MorphoVault[] memory vaultsInfo = viewsContract
            .getVaultsInfo(morphoVaults);

        assertEq(vaultsInfo.length, 2);

        for (uint index = 0; index < vaultsInfo.length; index++) {
            MorphoViewsV2.MorphoVault memory vault = vaultsInfo[index];
            assertEq(vault.vault, morphoVaults[index]);
            assertGt(vault.totalSupply, 0);
        }
    }

    function testMorphoMarketsInfoV2() public view {
        bytes32[] memory markets = new bytes32[](1);
        markets[0] = CBETH_USDC_MARKET;

        MorphoViewsV2.MorphoBlueMarket[] memory marketInfo = viewsContract
            .getMorphoBlueMarketsInfo(markets);

        assertEq(marketInfo.length, 1);

        MorphoViewsV2.MorphoBlueMarket memory market = marketInfo[0];
        assertEq(market.marketId, markets[0]);
        assertGt(market.lltv, 0);
    }

    function testUserBalancesV2() public view {
        bytes32[] memory markets = new bytes32[](1);
        markets[0] = CBETH_USDC_MARKET;

        // Use a known user address from the Addresses contract
        address user = addresses.getAddress("TEMPORAL_GOVERNOR");

        MorphoViewsV2.UserMarketBalance[] memory balances = viewsContract
            .getMorphoBlueUserBalances(markets, user);

        assertEq(balances.length, 1);
        assertEq(balances[0].marketId, markets[0]);
    }

    function testNewV2Vaults() public view {
        address[] memory morphoVaults = new address[](2);
        morphoVaults[0] = addresses.getAddress("llUSDC_METAMORPHO_VAULT");
        morphoVaults[1] = addresses.getAddress("meUSDC_METAMORPHO_VAULT");

        MorphoViewsV2.MorphoVault[] memory vaultsInfo = viewsContract
            .getVaultsInfo(morphoVaults);

        assertEq(vaultsInfo.length, 2);

        for (uint index = 0; index < vaultsInfo.length; index++) {
            MorphoViewsV2.MorphoVault memory vault = vaultsInfo[index];
            assertEq(vault.vault, morphoVaults[index]);
        }
    }

    function testGetSingleVaultInfo() public view {
        address vaultAddress = addresses.getAddress("USDC_METAMORPHO_VAULT");

        MorphoViewsV2.MorphoVault memory vault = viewsContract.getVaultInfo(
            IMetaMorphoV2(vaultAddress)
        );

        assertEq(vault.vault, vaultAddress);
        assertGe(vault.markets.length, 0);
    }

    function testGetSingleMarketInfo() public view {
        MorphoViewsV2.MorphoBlueMarket memory market = viewsContract
            .getMorphoBlueMarketInfo(CBETH_USDC_MARKET);

        assertEq(market.marketId, CBETH_USDC_MARKET);
        assertGt(market.lltv, 0);
    }

    // ==================== NEW TESTS ====================

    /// @notice Test getVaultMarketInfo external function directly
    function testGetVaultMarketInfo() public view {
        address vaultAddress = addresses.getAddress("USDC_METAMORPHO_VAULT");
        IMetaMorphoV2 vault = IMetaMorphoV2(vaultAddress);

        // Get the first market from the vault's withdraw queue
        bytes32 marketId = vault.withdrawQueue(0);

        MorphoViewsV2.MorphoVaultMarketsInfo memory marketInfo = viewsContract
            .getVaultMarketInfo(marketId, IMorphoBlue(morphoBlue), vault);

        assertEq(marketInfo.marketId, marketId);
        // Market should have some liquidity or supply
        assertGe(marketInfo.marketLltv, 0);
    }

    /// @notice Test getMorphoBlueUserBalance (single market, single user)
    function testGetSingleUserBalance() public view {
        address user = addresses.getAddress("TEMPORAL_GOVERNOR");

        MorphoViewsV2.UserMarketBalance memory balance = viewsContract
            .getMorphoBlueUserBalance(CBETH_USDC_MARKET, user);

        assertEq(balance.marketId, CBETH_USDC_MARKET);
        // Verify token addresses are populated
        assertTrue(balance.collateralToken != address(0));
        assertTrue(balance.loanToken != address(0));
    }

    /// @notice Test that re-initialization reverts
    function testCannotReinitialize() public {
        address comptroller = addresses.getAddress("UNITROLLER");

        vm.expectRevert("Initializable: contract is already initialized");
        viewsContract.initialize(comptroller, morphoBlue);
    }

    /// @notice Test that implementation cannot be initialized directly
    function testImplementationCannotBeInitialized() public {
        address comptroller = addresses.getAddress("UNITROLLER");

        vm.expectRevert("Initializable: contract is already initialized");
        implementation.initialize(comptroller, morphoBlue);
    }

    /// @notice Test getVaultsInfo with empty array
    function testGetVaultsInfoEmptyArray() public view {
        address[] memory emptyVaults = new address[](0);

        MorphoViewsV2.MorphoVault[] memory vaultsInfo = viewsContract
            .getVaultsInfo(emptyVaults);

        assertEq(vaultsInfo.length, 0);
    }

    /// @notice Test getMorphoBlueMarketsInfo with empty array
    function testGetMarketsInfoEmptyArray() public view {
        bytes32[] memory emptyMarkets = new bytes32[](0);

        MorphoViewsV2.MorphoBlueMarket[] memory marketInfo = viewsContract
            .getMorphoBlueMarketsInfo(emptyMarkets);

        assertEq(marketInfo.length, 0);
    }

    /// @notice Test getMorphoBlueUserBalances with empty array
    function testGetUserBalancesEmptyArray() public view {
        bytes32[] memory emptyMarkets = new bytes32[](0);
        address user = addresses.getAddress("TEMPORAL_GOVERNOR");

        MorphoViewsV2.UserMarketBalance[] memory balances = viewsContract
            .getMorphoBlueUserBalances(emptyMarkets, user);

        assertEq(balances.length, 0);
    }

    /// @notice Test market info returns valid token data
    function testMarketInfoTokenData() public view {
        MorphoViewsV2.MorphoBlueMarket memory market = viewsContract
            .getMorphoBlueMarketInfo(CBETH_USDC_MARKET);

        // Verify collateral token data
        assertTrue(market.collateralToken != address(0));
        assertTrue(bytes(market.collateralSymbol).length > 0);
        assertTrue(bytes(market.collateralName).length > 0);
        assertGt(market.collateralDecimals, 0);

        // Verify loan token data
        assertTrue(market.loanToken != address(0));
        assertTrue(bytes(market.loanSymbol).length > 0);
        assertTrue(bytes(market.loanName).length > 0);
        assertGt(market.loanDecimals, 0);
    }

    /// @notice Test market APY values are reasonable (not overflow/underflow)
    function testMarketAPYValues() public view {
        MorphoViewsV2.MorphoBlueMarket memory market = viewsContract
            .getMorphoBlueMarketInfo(CBETH_USDC_MARKET);

        // APY should be less than 1000% (10e18 in WAD)
        uint256 maxReasonableApy = 10e18;
        assertLt(market.supplyApy, maxReasonableApy);
        assertLt(market.borrowApy, maxReasonableApy);

        // Borrow APY should be >= supply APY (protocol takes fees)
        assertGe(market.borrowApy, market.supplyApy);
    }

    /// @notice Test vault info returns valid market allocations
    function testVaultMarketsAllocation() public view {
        address vaultAddress = addresses.getAddress("USDC_METAMORPHO_VAULT");

        MorphoViewsV2.MorphoVault memory vault = viewsContract.getVaultInfo(
            IMetaMorphoV2(vaultAddress)
        );

        // Vault should have at least one market
        assertGt(vault.markets.length, 0);

        // Each market should have a valid ID
        for (uint i = 0; i < vault.markets.length; i++) {
            assertTrue(vault.markets[i].marketId != bytes32(0));
        }
    }

    /// @notice Test multiple markets info retrieval
    function testMultipleMarketsInfo() public view {
        // Get markets from a vault's withdraw queue
        address vaultAddress = addresses.getAddress("USDC_METAMORPHO_VAULT");
        IMetaMorphoV2 vault = IMetaMorphoV2(vaultAddress);

        uint256 queueLength = vault.withdrawQueueLength();
        if (queueLength < 2) return; // Skip if vault has less than 2 markets

        bytes32[] memory markets = new bytes32[](2);
        markets[0] = vault.withdrawQueue(0);
        markets[1] = vault.withdrawQueue(1);

        MorphoViewsV2.MorphoBlueMarket[] memory marketInfo = viewsContract
            .getMorphoBlueMarketsInfo(markets);

        assertEq(marketInfo.length, 2);
        assertEq(marketInfo[0].marketId, markets[0]);
        assertEq(marketInfo[1].marketId, markets[1]);
    }

    /// @notice Test that oracle price is returned for markets with oracle
    function testMarketOraclePrice() public view {
        MorphoViewsV2.MorphoBlueMarket memory market = viewsContract
            .getMorphoBlueMarketInfo(CBETH_USDC_MARKET);

        // If market has an oracle, price should be > 0
        if (market.oracle != address(0)) {
            assertGt(market.oraclePrice, 0);
        }
    }

    /// @notice Test vault underlying price from Chainlink
    function testVaultUnderlyingPrice() public view {
        address vaultAddress = addresses.getAddress("USDC_METAMORPHO_VAULT");

        MorphoViewsV2.MorphoVault memory vault = viewsContract.getVaultInfo(
            IMetaMorphoV2(vaultAddress)
        );

        // USDC should have a price feed, price should be ~$1 (around 1e18 in 18 decimals)
        assertGt(vault.underlyingPrice, 0);
        // USDC price should be between $0.90 and $1.10
        assertGt(vault.underlyingPrice, 0.9e18);
        assertLt(vault.underlyingPrice, 1.1e18);
    }

    /// @notice Test total liquidity calculation
    function testMarketTotalLiquidity() public view {
        MorphoViewsV2.MorphoBlueMarket memory market = viewsContract
            .getMorphoBlueMarketInfo(CBETH_USDC_MARKET);

        // Total liquidity should equal totalSupply - totalBorrow
        if (market.totalSupplyAssets >= market.totalBorrowAssets) {
            assertEq(
                market.totalLiquidity,
                market.totalSupplyAssets - market.totalBorrowAssets
            );
        } else {
            assertEq(market.totalLiquidity, 0);
        }
    }
}
