pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@test/helper/BaseTest.t.sol";

contract xWELLUnitTest is BaseTest {
    function testSetup() public {
        assertEq(xwellProxy.name(), xwellName, "incorrect name");
        assertEq(xwellProxy.symbol(), xwellSymbol, "incorrect symbol");
        assertEq(xwellProxy.totalSupply(), 0, "incorrect total supply");
        assertEq(xwellProxy.owner(), address(this), "incorrect owner");
        assertEq(xwellProxy.pendingOwner(), owner, "incorrect pending owner");
        assertEq(
            xwellProxy.MAX_SUPPLY(),
            5_000_000_000 * 1e18,
            "incorrect pending owner"
        );
        assertEq(
            xwellProxy.bufferCap(address(xerc20Lockbox)),
            type(uint112).max,
            "incorrect lockbox buffer cap"
        );
        assertEq(
            xwellProxy.buffer(address(xerc20Lockbox)),
            type(uint112).max / 2,
            "incorrect lockbox buffer cap"
        );
        assertEq(
            xwellProxy.rateLimitPerSecond(address(xerc20Lockbox)),
            0,
            "incorrect lockbox rate limit per second"
        );

        /// PROXY OWNERSHIP

        /// proxy admin starts off as this address
        assertEq(
            proxyAdmin.getProxyAdmin(
                ITransparentUpgradeableProxy(address(xwellProxy))
            ),
            address(proxyAdmin),
            "incorrect proxy admin"
        );

        /// PAUSING
        assertEq(
            xwellProxy.pauseGuardian(),
            pauseGuardian,
            "incorrect pause guardian"
        );
        assertEq(xwellProxy.pauseStartTime(), 0, "incorrect pause start time");
        assertEq(
            xwellProxy.pauseDuration(),
            pauseDuration,
            "incorrect pause duration"
        );
        assertFalse(xwellProxy.paused(), "incorrectly paused");
        assertFalse(xwellProxy.pauseUsed(), "pause should not be used");
    }

    function testPendingOwnerAccepts() public {
        vm.prank(owner);
        xwellProxy.acceptOwnership();

        assertEq(xwellProxy.owner(), owner, "incorrect owner");
        assertEq(
            xwellProxy.pendingOwner(),
            address(0),
            "incorrect pending owner"
        );
    }

    function testInitializeLogicContractFails() public {
        vm.expectRevert("Initializable: contract is already initialized");
        xwellLogic.initialize(
            xwellName,
            xwellSymbol,
            owner,
            new RateLimitMidPointInfo[](0), /// empty array as it will fail anyway
            pauseDuration,
            pauseGuardian
        );
    }

    function testTransferToTokenContractFails() public {
        testLockboxCanMint(1);

        vm.expectRevert("xWELL: cannot transfer to token contract");
        xwellProxy.transfer(address(xwellProxy), 1);
    }

    function testMintOverMaxSupplyFails() public {
        uint256 maxSupply = xwellProxy.MAX_SUPPLY();

        vm.prank(address(xerc20Lockbox));
        vm.expectRevert("xWELL: max supply exceeded");
        xwellProxy.mint(address(xerc20Lockbox), maxSupply + 1);
    }

    function testLockboxCanMint(uint112 mintAmount) public {
        mintAmount = uint112(_bound(mintAmount, 1, xwellProxy.MAX_SUPPLY()));

        _lockboxCanMint(mintAmount);
    }

    function testLockboxCanMintTo(address to, uint112 mintAmount) public {
        /// cannot transfer to the proxy contract
        to = to == address(xwellProxy)
            ? address(this)
            : address(103131212121482329);

        mintAmount = uint112(_bound(mintAmount, 1, xwellProxy.MAX_SUPPLY()));

        _lockboxCanMintTo(to, mintAmount);
    }

    function testLockboxCanMintBurnTo(uint112 mintAmount) public {
        address to = address(this);

        mintAmount = uint112(_bound(mintAmount, 1, xwellProxy.MAX_SUPPLY()));

        _lockboxCanMintTo(to, mintAmount);
        _lockboxCanBurnTo(to, mintAmount);
    }

    function testLockBoxCanBurn(uint112 burnAmount) public {
        burnAmount = uint112(_bound(burnAmount, 1, xwellProxy.MAX_SUPPLY()));

        testLockboxCanMint(burnAmount);
        _lockboxCanBurn(burnAmount);
    }

    function testLockBoxCanMintBurn(uint112 mintAmount) public {
        mintAmount = uint112(_bound(mintAmount, 1, xwellProxy.MAX_SUPPLY()));

        _lockboxCanMint(mintAmount);
        _lockboxCanBurn(mintAmount);

        assertEq(xwellProxy.totalSupply(), 0, "incorrect total supply");
    }

    function _lockboxCanBurn(uint112 burnAmount) private {
        uint256 startingTotalSupply = xwellProxy.totalSupply();
        uint256 startingWellBalance = well.balanceOf(address(this));
        uint256 startingXwellBalance = xwellProxy.balanceOf(address(this));

        xwellProxy.approve(address(xerc20Lockbox), burnAmount);
        xerc20Lockbox.withdraw(burnAmount);

        uint256 endingTotalSupply = xwellProxy.totalSupply();
        uint256 endingWellBalance = well.balanceOf(address(this));
        uint256 endingXwellBalance = xwellProxy.balanceOf(address(this));

        assertEq(
            startingTotalSupply - endingTotalSupply,
            burnAmount,
            "incorrect burn amount to totalSupply"
        );
        assertEq(
            endingWellBalance - startingWellBalance,
            burnAmount,
            "incorrect burn amount to well balance"
        );
        assertEq(
            startingXwellBalance - endingXwellBalance,
            burnAmount,
            "incorrect burn amount to xwell balance"
        );
    }

    function _lockboxCanBurnTo(address to, uint112 burnAmount) private {
        uint256 startingTotalSupply = xwellProxy.totalSupply();
        uint256 startingWellBalance = well.balanceOf(to);
        uint256 startingXwellBalance = xwellProxy.balanceOf(address(this));

        xwellProxy.approve(address(xerc20Lockbox), burnAmount);
        xerc20Lockbox.withdrawTo(to, burnAmount);

        uint256 endingTotalSupply = xwellProxy.totalSupply();
        uint256 endingWellBalance = well.balanceOf(to);
        uint256 endingXwellBalance = xwellProxy.balanceOf(address(this));

        assertEq(
            startingTotalSupply - endingTotalSupply,
            burnAmount,
            "incorrect burn amount to totalSupply"
        );
        assertEq(
            endingWellBalance - startingWellBalance,
            burnAmount,
            "incorrect burn amount to well balance"
        );
        assertEq(
            startingXwellBalance - endingXwellBalance,
            burnAmount,
            "incorrect burn amount to xwell balance"
        );
    }

    function _lockboxCanMint(uint112 mintAmount) private {
        well.mint(address(this), mintAmount);
        well.approve(address(xerc20Lockbox), mintAmount);

        uint256 startingTotalSupply = xwellProxy.totalSupply();
        uint256 startingWellBalance = well.balanceOf(address(this));
        uint256 startingXwellBalance = xwellProxy.balanceOf(address(this));

        xerc20Lockbox.deposit(mintAmount);

        uint256 endingTotalSupply = xwellProxy.totalSupply();
        uint256 endingWellBalance = well.balanceOf(address(this));
        uint256 endingXwellBalance = xwellProxy.balanceOf(address(this));

        assertEq(
            endingTotalSupply - startingTotalSupply,
            mintAmount,
            "incorrect mint amount to totalSupply"
        );
        assertEq(
            startingWellBalance - endingWellBalance,
            mintAmount,
            "incorrect mint amount to well balance"
        );
        assertEq(
            endingXwellBalance - startingXwellBalance,
            mintAmount,
            "incorrect mint amount to xwell balance"
        );
    }

    function _lockboxCanMintTo(address to, uint112 mintAmount) private {
        well.mint(address(this), mintAmount);
        well.approve(address(xerc20Lockbox), mintAmount);

        uint256 startingTotalSupply = xwellProxy.totalSupply();
        uint256 startingWellBalance = well.balanceOf(address(this));
        uint256 startingXwellBalance = xwellProxy.balanceOf(to);

        xerc20Lockbox.depositTo(to, mintAmount);

        uint256 endingTotalSupply = xwellProxy.totalSupply();
        uint256 endingWellBalance = well.balanceOf(address(this));
        uint256 endingXwellBalance = xwellProxy.balanceOf(to);

        assertEq(
            endingTotalSupply - startingTotalSupply,
            mintAmount,
            "incorrect mint amount to totalSupply"
        );
        assertEq(
            startingWellBalance - endingWellBalance,
            mintAmount,
            "incorrect mint amount to well balance"
        );
        assertEq(
            endingXwellBalance - startingXwellBalance,
            mintAmount,
            "incorrect mint amount to xwell balance"
        );
    }
}
