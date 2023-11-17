pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@test/helper/BaseTest.t.sol";

/// TODO:
///    - failing add limits
///    - failing remove limits
///    - pause specific tests

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
            new MintLimits.RateLimitMidPointInfo[](0), /// empty array as it will fail anyway
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

    /// ACL

    function testGrantGuardianNonOwnerReverts() public {
        testPendingOwnerAccepts();
        vm.expectRevert("Ownable: caller is not the owner");
        xwellProxy.grantPauseGuardian(address(0));
    }

    function testSetBufferCapLimitsNonOwnerReverts() public {
        testPendingOwnerAccepts();
        vm.expectRevert("Ownable: caller is not the owner");
        xwellProxy.setLimits(address(0), 0, 0);
    }

    function testSetBufferCapNonOwnerReverts() public {
        testPendingOwnerAccepts();
        vm.expectRevert("Ownable: caller is not the owner");
        xwellProxy.setBufferCap(address(0), 0);
    }

    function testSetRateLimitPerSecondNonOwnerReverts() public {
        testPendingOwnerAccepts();
        vm.expectRevert("Ownable: caller is not the owner");
        xwellProxy.setRateLimitPerSecond(address(0), 0);
    }

    function testAddBridgeNonOwnerReverts() public {
        testPendingOwnerAccepts();
        vm.expectRevert("Ownable: caller is not the owner");
        xwellProxy.addBridge(
            MintLimits.RateLimitMidPointInfo({
                bridge: address(0),
                rateLimitPerSecond: 0,
                bufferCap: 0
            })
        );
    }

    function testAddBridgesNonOwnerReverts() public {
        testPendingOwnerAccepts();
        vm.expectRevert("Ownable: caller is not the owner");
        xwellProxy.addBridges(new MintLimits.RateLimitMidPointInfo[](0));
    }

    function testRemoveBridgeNonOwnerReverts() public {
        testPendingOwnerAccepts();
        vm.expectRevert("Ownable: caller is not the owner");
        xwellProxy.removeBridge(address(0));
    }

    function testRemoveBridgesNonOwnerReverts() public {
        testPendingOwnerAccepts();
        vm.expectRevert("Ownable: caller is not the owner");
        xwellProxy.removeBridges(new address[](0));
    }

    function testGrantGuardianOwnerSucceeds(address newPauseGuardian) public {
        xwellProxy.grantPauseGuardian(newPauseGuardian);
        assertEq(
            xwellProxy.pauseGuardian(),
            newPauseGuardian,
            "incorrect pause guardian"
        );
    }

    function testSetBufferCapLimitsOwnerSucceeds(uint112 bufferCap) public {
        bufferCap = uint112(_bound(bufferCap, 1, type(uint112).max));

        xwellProxy.setLimits(address(xerc20Lockbox), bufferCap, 0);
        assertEq(
            xwellProxy.bufferCap(address(xerc20Lockbox)),
            bufferCap,
            "incorrect buffer cap"
        );
    }

    function testSetBufferCapOwnerSucceeds(uint112 bufferCap) public {
        bufferCap = uint112(_bound(bufferCap, 1, type(uint112).max));

        xwellProxy.setBufferCap(address(xerc20Lockbox), bufferCap);
        assertEq(
            xwellProxy.bufferCap(address(xerc20Lockbox)),
            bufferCap,
            "incorrect buffer cap"
        );
    }

    function testSetRateLimitPerSecondOwnerSucceeds(
        uint128 newRateLimitPerSecond
    ) public {
        newRateLimitPerSecond = uint128(
            _bound(
                newRateLimitPerSecond,
                1,
                xwellProxy.MAX_RATE_LIMIT_PER_SECOND()
            )
        );
        xwellProxy.setRateLimitPerSecond(
            address(xerc20Lockbox),
            newRateLimitPerSecond
        );

        assertEq(
            xwellProxy.rateLimitPerSecond(address(xerc20Lockbox)),
            newRateLimitPerSecond,
            "incorrect rate limit per second"
        );
    }

    /// add a new bridge and rate limit
    function testAddNewBridgeOwnerSucceeds(
        address bridge,
        uint128 newRateLimitPerSecond,
        uint112 newBufferCap
    ) public {
        xwellProxy.removeBridge(address(xerc20Lockbox));

        newRateLimitPerSecond = uint128(
            _bound(
                newRateLimitPerSecond,
                1,
                xwellProxy.MAX_RATE_LIMIT_PER_SECOND()
            )
        );
        newBufferCap = uint112(_bound(newBufferCap, 1, type(uint112).max));

        MintLimits.RateLimitMidPointInfo memory newBridge = MintLimits
            .RateLimitMidPointInfo({
                bridge: bridge,
                bufferCap: newBufferCap,
                rateLimitPerSecond: newRateLimitPerSecond
            });

        xwellProxy.addBridge(newBridge);

        assertEq(
            xwellProxy.rateLimitPerSecond(bridge),
            newRateLimitPerSecond,
            "incorrect rate limit per second"
        );

        assertEq(
            xwellProxy.bufferCap(bridge),
            newBufferCap,
            "incorrect buffer cap"
        );
    }

    function testAddNewBridgeWithExistingLimitFails() public {
        address newBridge = address(0x1111777777);
        uint128 rateLimitPerSecond = 10_000 * 1e18;
        uint112 bufferCap = 20_000_000 * 1e18;

        testAddNewBridgeOwnerSucceeds(newBridge, rateLimitPerSecond, bufferCap);

        MintLimits.RateLimitMidPointInfo memory bridge = MintLimits
            .RateLimitMidPointInfo({
                bridge: newBridge,
                bufferCap: bufferCap,
                rateLimitPerSecond: rateLimitPerSecond
            });

        vm.expectRevert("MintLimits: rate limit already exists");
        xwellProxy.addBridge(bridge);
    }

    function testAddNewBridgeOverMaxRateLimitPerSecondFails() public {
        address newBridge = address(0x1111777777);
        uint112 bufferCap = 20_000_000 * 1e18;

        MintLimits.RateLimitMidPointInfo memory bridge = MintLimits
            .RateLimitMidPointInfo({
                bridge: newBridge,
                bufferCap: bufferCap,
                rateLimitPerSecond: uint128(
                    xwellProxy.MAX_RATE_LIMIT_PER_SECOND() + 1
                )
            });

        vm.expectRevert("MintLimits: rateLimitPerSecond too high");
        xwellProxy.addBridge(bridge);
    }

    function testAddNewBridgeInvalidAddressFails() public {
        address newBridge = address(0);
        uint128 rateLimitPerSecond = 10_000 * 1e18;
        uint112 bufferCap = 20_000_000 * 1e18;

        MintLimits.RateLimitMidPointInfo memory bridge = MintLimits
            .RateLimitMidPointInfo({
                bridge: newBridge,
                bufferCap: bufferCap,
                rateLimitPerSecond: rateLimitPerSecond
            });

        vm.expectRevert("MintLimits: invalid bridge address");
        xwellProxy.addBridge(bridge);
    }

    function testAddNewBridgeBufferCapZeroFails() public {
        uint112 bufferCap = 0;
        address newBridge = address(100);
        uint128 rateLimitPerSecond = 10_000 * 1e18;

        MintLimits.RateLimitMidPointInfo memory bridge = MintLimits
            .RateLimitMidPointInfo({
                bridge: newBridge,
                bufferCap: bufferCap,
                rateLimitPerSecond: rateLimitPerSecond
            });

        vm.expectRevert("MintLimits: bufferCap cannot be 0");
        xwellProxy.addBridge(bridge);
    }

    function testSetRateLimitOnNonExistentBridgeFails(
        uint128 newRateLimitPerSecond
    ) public {
        newRateLimitPerSecond = uint128(
            _bound(
                newRateLimitPerSecond,
                1,
                xwellProxy.MAX_RATE_LIMIT_PER_SECOND()
            )
        );

        vm.expectRevert("MintLimits: non-existent rate limit");
        xwellProxy.setRateLimitPerSecond(address(0), newRateLimitPerSecond);
    }

    function testSetBufferCapOnNonExistentBridgeFails(
        uint112 newBufferCap
    ) public {
        newBufferCap = uint112(_bound(newBufferCap, 1, type(uint112).max));
        vm.expectRevert("MintLimits: non-existent rate limit");
        xwellProxy.setBufferCap(address(0), newBufferCap);
    }
}
