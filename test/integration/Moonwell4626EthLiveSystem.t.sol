// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {WETH9} from "@protocol/router/IWETH.sol";
import {MarketBase} from "@test/utils/MarketBase.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {MoonwellERC4626} from "@protocol/4626/MoonwellERC4626.sol";
import {deploy4626Router} from "@protocol/4626/4626FactoryDeploy.sol";
import {ERC4626EthRouter} from "@protocol/router/ERC4626EthRouter.sol";
import {Malicious4626Minter} from "@test/mock/Malicious4626Minter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MoonwellERC4626Eth} from "@protocol/4626/MoonwellERC4626Eth.sol";

contract Moonwell4626EthLiveSystemBaseTest is Configs {
    Comptroller comptroller;
    Addresses addresses;
    WETH9 weth;
    MoonwellERC4626Eth ethVault;
    MoonwellERC4626 vault;
    ERC4626EthRouter router;
    MarketBase public marketBase;

    function setUp() public {
        addresses = new Addresses();

        router = deploy4626Router(addresses);

        ethVault = new MoonwellERC4626Eth(
            ERC20(addresses.getAddress("WETH")),
            MErc20(addresses.getAddress("MOONWELL_WETH")),
            address(this),
            Comptroller(addresses.getAddress("UNITROLLER"))
        );

        vault = new MoonwellERC4626(
            ERC20(addresses.getAddress("cbETH")),
            MErc20(addresses.getAddress("MOONWELL_cbETH")),
            address(this),
            Comptroller(addresses.getAddress("UNITROLLER"))
        );

        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        marketBase = new MarketBase(comptroller);
        weth = WETH9(addresses.getAddress("WETH"));
    }

    function testSetup() public view {
        assertEq(
            address(router.weth()),
            addresses.getAddress("WETH"),
            "incorrect WETH address"
        );
        assertEq(
            address(ethVault.asset()),
            addresses.getAddress("WETH"),
            "incorrect underlying asset"
        );
        assertEq(
            address(ethVault.mToken()),
            addresses.getAddress("MOONWELL_WETH"),
            "incorrect mToken"
        );
        assertEq(
            address(ethVault.rewardRecipient()),
            address(this),
            "incorrect reward recipient"
        );
        assertEq(
            address(ethVault.comptroller()),
            addresses.getAddress("UNITROLLER"),
            "incorrect moontroller"
        );
        assertEq(ethVault.totalSupply(), 0, "incorrect totalSupply");

        assertEq(
            address(vault.asset()),
            addresses.getAddress("cbETH"),
            "incorrect underlying asset"
        );
        assertEq(
            address(vault.mToken()),
            addresses.getAddress("MOONWELL_cbETH"),
            "incorrect mToken"
        );
        assertEq(
            address(vault.rewardRecipient()),
            address(this),
            "incorrect reward recipient"
        );
        assertEq(
            address(vault.comptroller()),
            addresses.getAddress("UNITROLLER"),
            "incorrect moontroller"
        );
        assertEq(vault.totalSupply(), 0, "incorrect totalSupply");
    }

    function testCreateMoonwellERC4626EthVaultFailsUnderlyingMismatch() public {
        ERC20 asset = ERC20(addresses.getAddress("cbETH"));
        MErc20 mToken = MErc20(addresses.getAddress("MOONWELL_WETH"));

        vm.expectRevert("ASSET_MISMATCH");
        new MoonwellERC4626Eth(asset, mToken, address(this), comptroller);
    }

    function testMintmWeth4626SharesUsingRouter(uint256 amount) public {
        amount = _bound(
            amount,
            1_000e18,
            marketBase.getMaxSupplyAmount(
                MToken(addresses.getAddress("MOONWELL_WETH"))
            )
        );

        _innerMintTest(amount);
    }

    function testMintExcessWethRefunded() public {
        uint256 amount = 1_000e18;
        uint256 startingTotalSupply = ethVault.totalSupply();
        vm.deal(address(this), amount * 2);

        uint256 shares = ethVault.convertToShares(amount);
        router.mint{value: amount * 2}(ethVault, address(this), shares, amount);

        assertEq(
            ethVault.balanceOf(address(this)),
            shares,
            "incorrect eth 4626 share balance"
        );
        assertEq(
            ethVault.totalSupply() - startingTotalSupply,
            shares,
            "incorrect eth 4626 total supply"
        );
        assertEq(weth.balanceOf(address(this)), amount, "not enough refunded");
        assertEq(
            weth.allowance(
                address(router),
                addresses.getAddress("MOONWELL_WETH")
            ),
            0,
            "allowance not zero after minting through router"
        );
        assertEq(
            address(router).balance,
            0,
            "router balance not zero after minting through router"
        );
    }

    function testDepositExcessWethRefunded() public {
        uint256 amount = 1_000e18;
        uint256 startingTotalSupply = ethVault.totalSupply();
        vm.deal(address(this), amount * 2);

        uint256 shares = ethVault.convertToShares(amount);
        uint256 amt2x = amount * 2;
        router.deposit{value: amt2x}(ethVault, address(this), shares, amount);

        assertEq(
            ethVault.balanceOf(address(this)),
            shares,
            "incorrect eth 4626 share balance"
        );
        assertEq(
            ethVault.totalSupply() - startingTotalSupply,
            shares,
            "incorrect eth 4626 total supply"
        );
        assertEq(weth.balanceOf(address(this)), amount, "not enough refunded");
        assertEq(weth.balanceOf(address(router)), 0, "router weth balance");
        assertEq(
            weth.allowance(
                address(router),
                addresses.getAddress("MOONWELL_WETH")
            ),
            0,
            "allowance not zero after minting through router"
        );
        assertEq(
            address(router).balance,
            0,
            "router balance not zero after minting through router"
        );
    }

    function testWithdrawEthFromEth4626Vault(uint256 amount) public {
        amount = _bound(amount, 1e18, 1_000e18);

        _innerMintTest(amount);

        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 100);

        uint256 shares = ethVault.previewWithdraw(amount);
        uint256 startingBalance = address(this).balance;
        uint256 startingTotalSupply = ethVault.totalSupply();

        ethVault.withdraw(amount, address(this), address(this));

        assertEq(
            address(this).balance - startingBalance,
            amount,
            "incorrect amount out"
        );
        assertEq(
            ethVault.totalSupply(),
            startingTotalSupply - shares,
            "incorrect total supply"
        );
    }

    function testRedeemEthFromEth4626Vault(uint256 amount) public {
        amount = _bound(amount, 1e18, 1_000e18);

        _innerMintTest(amount);

        vm.roll(block.number + 1000);
        vm.warp(block.timestamp + 10000);

        ethVault.redeem(
            ethVault.balanceOf(address(this)),
            address(this),
            address(this)
        );

        assertGt(address(this).balance, amount, "incorrect amount out");
        assertEq(ethVault.totalSupply(), 0, "incorrect total supply");
    }

    function testMintcbEth4626Shares(uint256 amount) public {
        uint256 maxSupplyAmount = marketBase.getMaxSupplyAmount(
            MToken(addresses.getAddress("MOONWELL_cbETH"))
        );
        maxSupplyAmount = maxSupplyAmount > 1.0000001e18
            ? maxSupplyAmount - 1e18
            : maxSupplyAmount;

        amount = _bound(amount, 1, maxSupplyAmount);

        deal(addresses.getAddress("cbETH"), address(this), amount);
        ERC20(addresses.getAddress("cbETH")).approve(address(vault), amount);

        uint256 shares = vault.convertToShares(amount);
        uint256 amountIn = vault.mint(shares, address(this));

        assertTrue(amountIn <= amount, "incorrect amount in");
        assertEq(
            vault.balanceOf(address(this)),
            shares,
            "incorrect 4626 share balance"
        );
        assertEq(vault.totalSupply(), shares, "incorrect 4626 total supply");
    }

    function testMintRouterMaxAmountInLtMaxFails(uint256 amount) public {
        amount = _bound(
            0,
            10 * 1e18,
            marketBase.getMaxSupplyAmount(
                MToken(addresses.getAddress("MOONWELL_WETH"))
            )
        );
        vm.deal(address(this), amount);

        uint256 shares = ethVault.convertToShares(amount);

        vm.expectRevert("MINT_FAILED");
        router.mint{value: amount}(ethVault, address(this), shares, amount - 2);
    }

    function testDepositSharesAmountOutLtMinFails(uint256 amount) public {
        amount = _bound(
            0,
            10 * 1e18,
            marketBase.getMaxSupplyAmount(
                MToken(addresses.getAddress("MOONWELL_WETH"))
            )
        );
        vm.deal(address(this), amount);

        uint256 shares = ethVault.convertToShares(amount);

        vm.expectRevert("DEPOSIT_FAILED");
        router.deposit{value: amount}(
            ethVault,
            address(this),
            amount,
            shares + 1
        );
    }

    function testDepositSharesAmountOutSucceeds(uint256 amount) public {
        amount = _bound(
            0,
            10 * 1e18,
            marketBase.getMaxSupplyAmount(
                MToken(addresses.getAddress("MOONWELL_WETH"))
            )
        );
        uint256 startingTotalSupply = ethVault.totalSupply();

        vm.deal(address(this), amount);

        uint256 shares = ethVault.convertToShares(amount);

        router.deposit{value: amount}(ethVault, address(this), amount, shares);

        /// eth balance
        assertEq(
            address(this).balance,
            0,
            "incorrect balance after depositing shares"
        );
        assertEq(
            address(router).balance,
            0,
            "router balance not zero after minting through router"
        );

        /// vault balance / total supply
        assertEq(
            ethVault.balanceOf(address(this)),
            shares,
            "incorrect eth 4626 share balance"
        );
        assertEq(
            ethVault.totalSupply() - startingTotalSupply,
            shares,
            "incorrect eth 4626 total supply"
        );
        assertEq(
            weth.allowance(
                address(router),
                addresses.getAddress("MOONWELL_WETH")
            ),
            0,
            "allowance not zero after minting through router"
        );

        /// weth balance
        assertEq(weth.balanceOf(address(router)), 0, "router weth balance");
    }

    function testMintFailsNoValue() public {
        vm.expectRevert("ZERO_ETH");
        router.mint{value: 0}(ethVault, address(this), 1, 0);
    }

    function testDepositFailsNoValue() public {
        vm.expectRevert("ZERO_ETH");
        router.deposit{value: 0}(ethVault, address(this), 1, 0);
    }

    function testReentrancyDepositFails() public {
        uint256 amount = 1_000e18;

        _innerMintTest(amount);

        Malicious4626Minter minter = new Malicious4626Minter(0);

        ethVault.transfer(address(minter), ethVault.balanceOf(address(this)));

        vm.expectRevert("ETH_TRANSFER_FAILED");
        minter.startAttack(address(ethVault));
    }

    function testReentrancyMintFails() public {
        uint256 amount = 1_000e18;

        _innerMintTest(amount);

        Malicious4626Minter minter = new Malicious4626Minter(1);

        ethVault.transfer(address(minter), ethVault.balanceOf(address(this)));

        vm.expectRevert("ETH_TRANSFER_FAILED");
        minter.startAttack(address(ethVault));
    }

    function testReentrancyWithdrawFails() public {
        uint256 amount = 1_000e18;

        _innerMintTest(amount);

        Malicious4626Minter minter = new Malicious4626Minter(2);

        ethVault.transfer(address(minter), ethVault.balanceOf(address(this)));

        vm.expectRevert("ETH_TRANSFER_FAILED");
        minter.startAttack(address(ethVault));
    }

    function testReentrancyRedeemFails() public {
        uint256 amount = 1_000e18;

        _innerMintTest(amount);

        Malicious4626Minter minter = new Malicious4626Minter(3);

        ethVault.transfer(address(minter), ethVault.balanceOf(address(this)));

        vm.expectRevert("ETH_TRANSFER_FAILED");
        minter.startAttack(address(ethVault));
    }

    function _innerMintTest(uint256 amount) private {
        uint256 startingTotalSupply = ethVault.totalSupply();
        vm.deal(address(this), amount);

        uint256 shares = ethVault.convertToShares(amount);
        router.mint{value: amount}(ethVault, address(this), shares, amount);

        assertEq(
            ethVault.balanceOf(address(this)),
            shares,
            "incorrect eth 4626 share balance"
        );
        assertEq(
            ethVault.totalSupply() - startingTotalSupply,
            shares,
            "incorrect eth 4626 total supply"
        );
        assertEq(
            weth.allowance(
                address(router),
                addresses.getAddress("MOONWELL_WETH")
            ),
            0,
            "allowance not zero after minting through router"
        );

        /// eth balance
        assertEq(
            address(this).balance,
            0,
            "incorrect balance after depositing shares"
        );
        assertEq(
            address(router).balance,
            0,
            "router balance not zero after minting through router"
        );

        /// weth balance
        assertEq(weth.balanceOf(address(router)), 0, "router weth balance");
    }

    receive() external payable {}
}
