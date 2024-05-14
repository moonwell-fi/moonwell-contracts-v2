// SPDX-License-Iden`fier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {Proxy} from "@external/Proxy.sol";
import {Configs} from "@proposals/Configs.sol";
import {ErrorsLib} from "@external/ErrorsLib.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {IMorphoBase, MarketParams} from "@interfaces/IMorpho.sol";
import {PendingAddress, IMetaMorpho, MarketAllocation} from "@external/MetaMorpho.sol";
import {IMorphoChainlinkOracleV2, IMorphoChainlinkOracleV2Factory} from "@interfaces/IMorphoChainlinkOracleV2Factory.sol";

/// for testing against mainnet
contract MorphoVaultEthMainnetTest is Configs {
    Addresses addresses;
    IMetaMorpho metaMorpho;
    IMetaMorpho usdcVault;
    address morpho;
    IERC20 usdc;
    address steth;
    ProxyAdmin proxyAdmin;

    uint256 public constant timelock = 2 days;

    /// @notice The length of the data used to compute the id of a market.
    /// @dev The length is 5 * 32 because `MarketParams` has 5 variables of 32 bytes each.
    uint256 internal constant MARKET_PARAMS_BYTES_LENGTH = 5 * 32;

    uint256 internal constant MIN_TIMELOCK = 1 days;

    error OwnableUnauthorizedAccount(address account);

    MarketParams[] internal allMarkets;

    function setUp() public {
        addresses = new Addresses();
        proxyAdmin = new ProxyAdmin();

        morpho = addresses.getAddress("MORPHO_BLUE");
        usdc = IERC20(addresses.getAddress("USDC"));
        steth = addresses.getAddress("stETH");
        metaMorpho = IMetaMorpho(
            addresses.getAddress("METAMORPHO_USDC_VAULT_MAINNET")
        );
        usdcVault = IMetaMorpho(
            address(
                new Proxy(
                    address(morpho),
                    address(metaMorpho),
                    address(proxyAdmin),
                    address(this),
                    timelock,
                    address(usdc),
                    "Moonwell USDC Vault",
                    "Moonwell-USDC"
                )
            )
        );
    }

    function testSetup() public {
        {
            PendingAddress memory pendingAddresses = usdcVault
                .pendingGuardian();
            assertEq(
                pendingAddresses.value,
                address(0),
                "pending guardian incorrect"
            );
            assertEq(
                pendingAddresses.validAt,
                0,
                "pending timestamp incorrect"
            );
        }

        assertEq(
            address(usdcVault.MORPHO()),
            addresses.getAddress("MORPHO_BLUE"),
            "morpho address incorrect"
        );

        assertEq(
            address(usdcVault.guardian()),
            address(0),
            "guardian incorrect"
        );
        assertEq(
            usdcVault.feeRecipient(),
            address(0),
            "fee recipient incorrect"
        );
        assertEq(
            usdcVault.skimRecipient(),
            address(0),
            "skim recipient incorrect"
        );

        assertEq(usdcVault.fee(), 0, "fee incorrect");
        assertEq(usdcVault.lastTotalAssets(), 0, "last total assets incorrect");
        assertEq(
            usdcVault.supplyQueueLength(),
            0,
            "supply queue length incorrect"
        );
        assertEq(
            usdcVault.withdrawQueueLength(),
            0,
            "withdraw queue length incorrect"
        );

        /// max mint and max deposit are set to 0 because there are no supply caps
        assertEq(usdcVault.maxMint(address(0)), 0, "max mint incorrect");
        assertEq(usdcVault.maxDeposit(address(0)), 0, "max deposit incorrect");
        assertEq(
            usdcVault.decimals(),
            metaMorpho.decimals(),
            "decimals incorrect"
        );

        assertEq(usdcVault.owner(), address(this), "owner incorrect");
        assertEq(usdcVault.timelock(), timelock, "timelock incorrect");
        assertEq(usdcVault.asset(), address(usdc), "asset incorrect");
        assertEq(usdcVault.totalSupply(), 0, "total supply incorrect");

        assertEq(usdcVault.symbol(), "Moonwell-USDC");
        assertEq(usdcVault.name(), "Moonwell USDC Vault");
    }

    function testOwnerActionsSucceedsOwner() public {
        address newCurator = address(0x1111111);
        address newAllocator = address(0xaaaaaaa);
        address newFeeRecipient = address(0xfffffff);
        address newSkimRecipient = address(0x44444444);

        usdcVault.setCurator(newCurator);
        usdcVault.setIsAllocator(newAllocator, true);
        usdcVault.setFeeRecipient(newFeeRecipient);
        usdcVault.setSkimRecipient(newSkimRecipient);

        assertEq(usdcVault.curator(), newCurator, "curator incorrect");
        assertEq(
            usdcVault.isAllocator(newAllocator),
            true,
            "allocator incorrect"
        );
        assertEq(
            usdcVault.feeRecipient(),
            newFeeRecipient,
            "fee recipient incorrect"
        );
        assertEq(
            usdcVault.skimRecipient(),
            newSkimRecipient,
            "skim recipient incorrect"
        );
    }

    function testOwnerActionsFailsNotOwner() public {
        address sender = address(0x12345678);

        address newCurator = address(0x1111111);
        address newAllocator = address(0xaaaaaaa);
        address newFeeRecipient = address(0xfffffff);
        address newSkimRecipient = address(0x44444444);

        vm.startPrank(sender);

        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                sender
            )
        );
        usdcVault.setCurator(newCurator);

        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                sender
            )
        );
        usdcVault.setIsAllocator(newAllocator, true);

        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                sender
            )
        );
        usdcVault.setFeeRecipient(newFeeRecipient);

        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                sender
            )
        );
        usdcVault.setSkimRecipient(newSkimRecipient);

        vm.stopPrank();
    }

    function testOracleStEthUsdc()
        public
        returns (IMorphoChainlinkOracleV2 oracle)
    {
        address zero = address(0);
        address stEthEthFeed = addresses.getAddress("stETH_ETH_ORACLE");
        address usdcEthFeed = addresses.getAddress("ETH_USDC_ORACLE");
        IMorphoChainlinkOracleV2Factory factory = IMorphoChainlinkOracleV2Factory(
                addresses.getAddress("MORPHO_ORACLE_FACTORY")
            );

        oracle = factory.createMorphoChainlinkOracleV2(
            zero,
            1,
            stEthEthFeed,
            zero,
            18,
            zero,
            1,
            usdcEthFeed,
            zero,
            6,
            bytes32(0)
        );
        (, int256 baseAnswer, , , ) = AggregatorV3Interface(stEthEthFeed)
            .latestRoundData();
        (, int256 quoteAnswer, , , ) = AggregatorV3Interface(usdcEthFeed)
            .latestRoundData();

        assertEq(
            oracle.price(),
            (uint256(baseAnswer) * 10 ** (36 + 18 + 6 - 18 - 18)) /
                uint256(quoteAnswer)
        );
    }

    /// steps to testing the vault:
    ///  1. ensure lending token and borrowing token exist
    ///  2. create the oracle feed using their factory
    ///  3. create the market using the oracle feed
    ///  4. create the vault using the created market
    ///  5. deposit some funds into the vault

    function testCreateMarketMorphoBlueSucceeds() public {
        address irm = addresses.getAddress("MORPHO_IRM_MAINNET");
        address loanToken = address(usdc);
        address collateralToken = addresses.getAddress("stETH");
        IMorphoChainlinkOracleV2 oracle = testOracleStEthUsdc();

        uint256 newSupplyCap = 1_000_000 * 1e6;

        ///    address loanToken;
        ///    address collateralToken;
        ///    address oracle;
        ///    address irm;
        ///    uint256 lltv;
        MarketParams memory marketParams;

        marketParams.irm = irm;
        marketParams.loanToken = loanToken;
        marketParams.collateralToken = collateralToken;
        marketParams.oracle = address(oracle);
        marketParams.lltv = 0.77e18;

        IMorphoBase(morpho).createMarket(marketParams);

        usdcVault.submitCap(marketParams, newSupplyCap);

        vm.warp(block.timestamp + timelock);

        usdcVault.acceptCap(marketParams);

        bytes32[] memory marketIds = new bytes32[](1);
        marketIds[0] = id(marketParams);

        usdcVault.setSupplyQueue(marketIds);

        assertEq(
            usdcVault.supplyQueueLength(),
            1,
            "supply queue length incorrect"
        );

        assertEq(
            usdcVault.maxMint(address(0)),
            newSupplyCap * (10 ** usdcVault.DECIMALS_OFFSET()),
            "max mint incorrect"
        );
        assertEq(
            usdcVault.maxDeposit(address(0)),
            newSupplyCap,
            "max deposit incorrect"
        );
    }

    /// test cannot skim

    function testSkimFailsRecipientNotSet() public {
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        usdcVault.skim(address(usdc));

        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        usdcVault.skim(address(usdc));
    }

    /// ACL tests for the vault

    /// Curator

    function testSubmitCapNonCuratorRoleFails(address caller) public {
        vm.assume(caller != usdcVault.owner() && caller != usdcVault.curator());

        MarketParams memory marketParams;

        vm.prank(caller);
        vm.expectRevert(ErrorsLib.NotCuratorRole.selector);
        usdcVault.submitCap(marketParams, 0); /// both params are ignored because ACL check fails
    }

    function testSubmitMarketRemovalNonCuratorRoleFails(address caller) public {
        vm.assume(caller != usdcVault.owner() && caller != usdcVault.curator());

        MarketParams memory marketParams;

        vm.prank(caller);
        vm.expectRevert(ErrorsLib.NotCuratorRole.selector);
        usdcVault.submitMarketRemoval(marketParams);
    }

    /// Allocator

    function testSetSupplyQueueFailsNonAllocator(address caller) public {
        vm.assume(
            !usdcVault.isAllocator(caller) &&
                caller != usdcVault.owner() &&
                caller != usdcVault.curator()
        );

        bytes32[] memory newSupplyQueue;
        MarketAllocation[] memory allocation;
        uint256[] memory withdrawQueueFromRanks;

        vm.prank(caller);
        vm.expectRevert(ErrorsLib.NotAllocatorRole.selector);
        usdcVault.setSupplyQueue(newSupplyQueue);

        vm.prank(caller);
        vm.expectRevert(ErrorsLib.NotAllocatorRole.selector);
        usdcVault.updateWithdrawQueue(withdrawQueueFromRanks);

        vm.prank(caller);
        vm.expectRevert(ErrorsLib.NotAllocatorRole.selector);
        usdcVault.reallocate(allocation);
    }

    /// Guardian

    function testRevokeShouldRevertNonGuardian(address caller) public {
        vm.assume(
            caller != usdcVault.owner() && caller != usdcVault.guardian()
        );

        vm.prank(caller);
        vm.expectRevert(ErrorsLib.NotGuardianRole.selector);
        usdcVault.revokePendingTimelock();

        vm.prank(caller);
        vm.expectRevert(ErrorsLib.NotGuardianRole.selector);
        usdcVault.revokePendingGuardian();
    }

    /// Curator or Guardian

    function testCuratorOrGuardianRevokeFailsNotCuratorOrGuardianRole(
        address caller,
        bytes32 marketId
    ) public {
        vm.assume(
            caller != usdcVault.owner() &&
                caller != usdcVault.curator() &&
                caller != usdcVault.guardian()
        );

        vm.prank(caller);
        vm.expectRevert(ErrorsLib.NotCuratorNorGuardianRole.selector);
        usdcVault.revokePendingCap(marketId);

        vm.prank(caller);
        vm.expectRevert(ErrorsLib.NotCuratorNorGuardianRole.selector);
        usdcVault.revokePendingMarketRemoval(marketId);
    }

    /// TODO add timelock tests

    function testAcceptTimelockTimelockNotElapsed(
        uint256 newTimelock,
        uint256 elapsed
    ) public {
        newTimelock = bound(newTimelock, MIN_TIMELOCK, timelock - 1);
        elapsed = bound(elapsed, 1, timelock - 1);

        usdcVault.submitTimelock(newTimelock);

        vm.warp(block.timestamp + elapsed);

        vm.expectRevert(ErrorsLib.TimelockNotElapsed.selector);
        usdcVault.acceptTimelock();
    }

    function testAcceptTimelockNoPendingValue() public {
        vm.expectRevert(ErrorsLib.NoPendingValue.selector);
        usdcVault.acceptTimelock();
    }

    /// TODO move to helper file

    /// @notice Returns the id of the market `marketParams`.
    function id(
        MarketParams memory marketParams
    ) internal pure returns (bytes32 marketParamsId) {
        assembly ("memory-safe") {
            marketParamsId := keccak256(
                marketParams,
                MARKET_PARAMS_BYTES_LENGTH
            )
        }
    }
}
