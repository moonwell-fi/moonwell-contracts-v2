pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MorphoViews} from "@protocol/views/MorphoViews.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IMorpho, IIrm, IOracle, MarketParams as MorphoMarketParams, Market as MorphoMarket, Id, Position as MorphoPosition} from "@protocol/views/MorphoBlueInterface.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import "forge-std/console.sol";

contract MorphoViewsTest is Test, PostProposalCheck {
    MorphoViews public viewsContract;

    address public user = 0xd7854FC91f16a58D67EC3644981160B6ca9C41B8;
    address public proxyAdmin = address(1337);

    address public comptroller;
    address morpho = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    function setUp() public override {
        super.setUp();

        comptroller = addresses.getAddress("UNITROLLER");
        viewsContract = new MorphoViews();

        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address)",
            comptroller,
            morpho
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(viewsContract),
            proxyAdmin,
            initdata
        );

        /// wire proxy up
        viewsContract = MorphoViews(address(proxy));
        vm.rollFork(16317213);
    }

    function testVaultsProtocolInfo() public {
        address[] memory morphoVaults = new address[](2);
        morphoVaults[0] = 0xa0E430870c4604CcfC7B38Ca7845B1FF653D0ff1;
        morphoVaults[1] = 0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca;

        MorphoViews.MorphoVault[] memory _vaultsInfo = viewsContract
            .getVaultsInfo(morphoVaults);

        for (uint index = 0; index < _vaultsInfo.length; index++) {
            MorphoViews.MorphoVault memory _vault = _vaultsInfo[index];
            console.log("Vault fee %s", _vault.fee);
            console.log("Vault timelock %s", _vault.timelock);
            console.log("Vault totalAssets %s", _vault.totalAssets);
            console.log("Vault totalSupply %s", _vault.totalSupply);
            console.log("Vault underlyingPrice %s", _vault.underlyingPrice);
            console.log("Vault markets %s", _vault.markets.length);

            for (uint y = 0; y < _vault.markets.length; y++) {
                MorphoViews.MorphoVaultMarketsInfo memory _market = _vault
                    .markets[index];
                console.log(
                    "  Market marketCollateral %s",
                    _market.marketCollateral
                );
                console.log(
                    "  Market marketCollateralName %s",
                    _market.marketCollateralName
                );
                console.log(
                    "  Market marketCollateralSymbol %s",
                    _market.marketCollateralSymbol
                );
                console.log("  Market apy %s", _market.marketApy);
                console.log(
                    "  Market marketLiquidity %s",
                    _market.marketLiquidity
                );
                console.log("  Market marketLltv %s", _market.marketLltv);
                console.log("  Market vaultSupplied %s", _market.vaultSupplied);
            }
        }

        assertEq(_vaultsInfo.length, 2);
    }

    function testMorphoMarketsInfo() public {
        Id[] memory markets = new Id[](1);
        markets[0] = Id.wrap(
            bytes32(
                0xdba352d93a64b17c71104cbddc6aef85cd432322a1446b5b65163cbbc615cd0c
            )
        );

        MorphoViews.MorphoBlueMarket[] memory _marketInfo = viewsContract
            .getMorphoBlueMarketsInfo(markets);

        for (uint index = 0; index < markets.length; index++) {
            MorphoViews.MorphoBlueMarket memory _market = _marketInfo[index];
            console.log(
                "Market marketId %s",
                string(abi.encodePacked(Id.unwrap(_market.marketId)))
            );

            console.log("Market collateralToken %s", _market.collateralToken);
            console.log("Market collateralName %s", _market.collateralName);
            console.log("Market collateralSymbol %s", _market.collateralSymbol);
            console.log("Market collateralPrice %s", _market.collateralPrice);

            console.log("Market loanToken %s", _market.loanToken);
            console.log("Market loanName %s", _market.loanName);
            console.log("Market loanSymbol %s", _market.loanSymbol);
            console.log("Market loanPrice %s", _market.loanPrice);

            console.log("Market fee %s", _market.fee);
            console.log("Market irm %s", _market.irm);
            console.log("Market lltv %s", _market.lltv);
            console.log("Market oracle %s", _market.oracle);
            console.log("Market oraclePrice %s", _market.oraclePrice);

            console.log(
                "Market totalSupplyAssets %s",
                _market.totalSupplyAssets
            );
            console.log(
                "Market totalBorrowAssets %s",
                _market.totalBorrowAssets
            );
            console.log("Market totalLiquidity %s", _market.totalLiquidity);
        }

        assertEq(_marketInfo.length, 1);
    }

    function testUserBalances() public {
        Id[] memory markets = new Id[](1);
        markets[0] = Id.wrap(
            bytes32(
                0xdba352d93a64b17c71104cbddc6aef85cd432322a1446b5b65163cbbc615cd0c
            )
        );

        MorphoViews.UserMarketBalance[] memory _balances = viewsContract
            .getMorphoBlueUserBalances(markets, user);

        for (uint index = 0; index < markets.length; index++) {
            MorphoViews.UserMarketBalance memory _balance = _balances[index];
            console.log(
                "User balances for marketId %s",
                string(abi.encodePacked(Id.unwrap(_balance.marketId)))
            );

            console.log("User collateralToken %s", _balance.collateralToken);
            console.log("User collateralAssets %s", _balance.collateralAssets);

            console.log("User loanToken %s", _balance.loanToken);
            console.log("User loanAssets %s", _balance.loanAssets);
            console.log("User loanShares %s", _balance.loanShares);
        }

        assertEq(_balances.length, 1);
    }
}
