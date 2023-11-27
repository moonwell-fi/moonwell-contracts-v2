pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@test/helper/BaseTest.t.sol";

/// TODO:
///    - failing add limits
///    - failing remove limits
///    - test voting power

contract xWELLUnitTest is BaseTest {
    function testSetup() public {
        assertTrue(xwellProxy.DOMAIN_SEPARATOR() != bytes32(0), "domain separator not set");
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = xwellProxy.eip712Domain();
        assertEq(fields, hex"0f", "incorrect fields");
        assertEq(version, "1", "incorrect version");
        assertEq(chainId, block.chainid, "incorrect chain id");
        assertEq(salt, bytes32(0), "incorrect salt");
        assertEq(verifyingContract, address(xwellProxy), "incorrect verifying contract");
        assertEq(name, xwellName, "incorrect name from eip712Domain()");
        assertEq(xwellProxy.name(), xwellName, "incorrect name");
        assertEq(xwellProxy.symbol(), xwellSymbol, "incorrect symbol");
        assertEq(xwellProxy.totalSupply(), 0, "incorrect total supply");
        assertEq(xwellProxy.owner(), address(this), "incorrect owner");
        assertEq(xwellProxy.pendingOwner(), owner, "incorrect pending owner");
        assertEq(
            xwellProxy.CLOCK_MODE(),
            "mode=timestamp",
            "incorrect pending owner"
        );
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
            xwellProxy.bufferCap(address(xerc20Lockbox)),
            xwellProxy.mintingMaxLimitOf(address(xerc20Lockbox)),
            "incorrect lockbox mintingMaxLimitOf"
        );
        assertEq(
            xwellProxy.bufferCap(address(xerc20Lockbox)),
            xwellProxy.burningMaxLimitOf(address(xerc20Lockbox)),
            "incorrect lockbox burningMaxLimitOf"
        );
        assertEq(
            xwellProxy.buffer(address(xerc20Lockbox)),
            type(uint112).max / 2,
            "incorrect lockbox buffer"
        );
        assertEq(
            xwellProxy.buffer(address(xerc20Lockbox)),
            xwellProxy.mintingCurrentLimitOf(address(xerc20Lockbox)),
            "incorrect lockbox mintingCurrentLimitOf"
        );
        assertEq(
            xwellProxy.bufferCap(address(xerc20Lockbox)) -
                xwellProxy.buffer(address(xerc20Lockbox)),
            xwellProxy.burningCurrentLimitOf(address(xerc20Lockbox)),
            "incorrect lockbox burningCurrentLimitOf"
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

        vm.expectRevert("xERC20: cannot transfer to token contract");
        xwellProxy.transfer(address(xwellProxy), 1);
    }

    function testMintOverMaxSupplyFails() public {
        uint256 maxSupply = xwellProxy.MAX_SUPPLY();

        vm.prank(address(xerc20Lockbox));
        vm.expectRevert("xERC20: max supply exceeded");
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

    function testSetPauseDurationNonOwnerReverts() public {
        testPendingOwnerAccepts();
        vm.expectRevert("Ownable: caller is not the owner");
        xwellProxy.setPauseDuration(0);
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

    function testUpdatePauseDurationSucceeds() public {
        uint128 newDuration = 8 days;
        xwellProxy.setPauseDuration(newDuration);
        assertEq(
            xwellProxy.pauseDuration(),
            newDuration,
            "incorrect pause duration"
        );
    }

    function testUpdatePauseDurationGtMaxPauseDurationFails() public {
        uint128 newDuration = uint128(xwellProxy.MAX_PAUSE_DURATION() + 1);
        vm.expectRevert("xWELL: pause duration too long");

        xwellProxy.setPauseDuration(newDuration);
    }

    function testSetBufferCapOwnerSucceeds(uint112 bufferCap) public {
        bufferCap = uint112(
            _bound(
                bufferCap,
                xwellProxy.MIN_BUFFER_CAP() + 1,
                type(uint112).max
            )
        );

        xwellProxy.setBufferCap(address(xerc20Lockbox), bufferCap);
        assertEq(
            xwellProxy.bufferCap(address(xerc20Lockbox)),
            bufferCap,
            "incorrect buffer cap"
        );
    }

    function testSetBufferCapZeroFails() public {
        uint112 bufferCap = 0;

        vm.expectRevert("MintLimits: bufferCap cannot be 0");
        xwellProxy.setBufferCap(address(xerc20Lockbox), bufferCap);
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

        /// bound input so bridge is not zero address
        bridge = address(
            uint160(_bound(uint256(uint160(bridge)), 1, type(uint160).max))
        );

        newRateLimitPerSecond = uint128(
            _bound(
                newRateLimitPerSecond,
                1,
                xwellProxy.MAX_RATE_LIMIT_PER_SECOND()
            )
        );
        newBufferCap = uint112(
            _bound(
                newBufferCap,
                xwellProxy.MIN_BUFFER_CAP() + 1,
                type(uint112).max
            )
        );

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

    /// add a new bridge and rate limit
    function testAddNewBridgesOwnerSucceeds(
        address bridge,
        uint128 newRateLimitPerSecond,
        uint112 newBufferCap
    ) public {
        xwellProxy.removeBridge(address(xerc20Lockbox));
        xwellProxy.removeBridge(address(wormholeBridgeAdapterProxy));

        newRateLimitPerSecond = uint128(
            _bound(
                newRateLimitPerSecond,
                1,
                xwellProxy.MAX_RATE_LIMIT_PER_SECOND()
            )
        );
        newBufferCap = uint112(
            _bound(
                newBufferCap,
                xwellProxy.MIN_BUFFER_CAP() + 1,
                type(uint112).max
            )
        );

        MintLimits.RateLimitMidPointInfo[]
            memory newBridge = new MintLimits.RateLimitMidPointInfo[](1);

        newBridge[0].bridge = bridge;
        newBridge[0].bufferCap = newBufferCap;
        newBridge[0].rateLimitPerSecond = newRateLimitPerSecond;

        xwellProxy.addBridges(newBridge);

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
        uint128 rateLimitPerSecond = uint128(
            xwellProxy.MAX_RATE_LIMIT_PER_SECOND()
        );
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

    function testAddNewBridgeWithBufferBelowMinFails() public {
        address newBridge = address(0x1111777777);
        uint128 rateLimitPerSecond = uint128(
            xwellProxy.MAX_RATE_LIMIT_PER_SECOND()
        );
        uint112 bufferCap = xwellProxy.MIN_BUFFER_CAP();

        MintLimits.RateLimitMidPointInfo memory bridge = MintLimits
            .RateLimitMidPointInfo({
                bridge: newBridge,
                bufferCap: bufferCap,
                rateLimitPerSecond: rateLimitPerSecond
            });

        vm.expectRevert("MintLimits: buffer cap below min");
        xwellProxy.addBridge(bridge);
    }

    function testSetBridgeBufferBelowMinFails() public {
        address newBridge = address(0x1111777777);
        uint128 rateLimitPerSecond = uint128(
            xwellProxy.MAX_RATE_LIMIT_PER_SECOND()
        );
        uint112 bufferCap = xwellProxy.MIN_BUFFER_CAP();
        testAddNewBridgeOwnerSucceeds(
            newBridge,
            rateLimitPerSecond,
            bufferCap + 1
        );

        vm.expectRevert("MintLimits: buffer cap below min");
        xwellProxy.setBufferCap(newBridge, bufferCap);
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

    function testSetExistingBridgeOverMaxRateLimitPerSecondFails() public {
        uint128 maxRateLimitPerSecond = uint128(
            xwellProxy.MAX_RATE_LIMIT_PER_SECOND()
        );

        vm.expectRevert("MintLimits: rateLimitPerSecond too high");
        xwellProxy.setRateLimitPerSecond(
            address(xerc20Lockbox),
            maxRateLimitPerSecond + 1
        );
    }

    function testAddNewBridgeInvalidAddressFails() public {
        address newBridge = address(0);
        uint128 rateLimitPerSecond = uint128(
            xwellProxy.MAX_RATE_LIMIT_PER_SECOND()
        );
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

        vm.expectRevert("MintLimits: buffer cap below min");
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

    function testRemoveBridgeOwnerSucceeds() public {
        xwellProxy.removeBridge(address(xerc20Lockbox));

        assertEq(
            xwellProxy.bufferCap(address(xerc20Lockbox)),
            0,
            "incorrect buffer cap"
        );
        assertEq(
            xwellProxy.rateLimitPerSecond(address(xerc20Lockbox)),
            0,
            "incorrect rate limit per second"
        );
        assertEq(
            xwellProxy.buffer(address(xerc20Lockbox)),
            0,
            "incorrect buffer"
        );
    }

    function testCannotRemoveNonExistentBridge() public {
        vm.expectRevert("MintLimits: cannot remove non-existent rate limit");
        xwellProxy.removeBridge(address(0));
    }

    function testCannotRemoveNonExistentBridges() public {
        vm.expectRevert("MintLimits: cannot remove non-existent rate limit");
        xwellProxy.removeBridges(new address[](2));
    }

    function testRemoveBridgesOwnerSucceeds() public {
        /// todo add more bridges here
        address[] memory bridges = new address[](1);
        bridges[0] = address(10000);

        testAddNewBridgeOwnerSucceeds(
            bridges[0],
            10_000e18,
            xwellProxy.minBufferCap() + 1
        );

        xwellProxy.removeBridges(bridges);

        for (uint256 i = 0; i < bridges.length; i++) {
            assertEq(
                xwellProxy.bufferCap(bridges[i]),
                0,
                "incorrect buffer cap"
            );
            assertEq(
                xwellProxy.rateLimitPerSecond(bridges[i]),
                0,
                "incorrect rate limit per second"
            );
            assertEq(xwellProxy.buffer(bridges[i]), 0, "incorrect buffer");
        }
    }

    function testDepleteBufferBridgeSucceeds() public {
        address bridge = address(0xeeeee);
        uint128 rateLimitPerSecond = uint128(
            xwellProxy.MAX_RATE_LIMIT_PER_SECOND()
        );
        uint112 bufferCap = 20_000_000 * 1e18;

        testAddNewBridgeOwnerSucceeds(bridge, rateLimitPerSecond, bufferCap);

        uint256 amount = 100_000 * 1e18;

        vm.prank(bridge);
        xwellProxy.mint(address(this), amount);

        xwellProxy.approve(bridge, amount);

        uint256 buffer = xwellProxy.buffer(bridge);
        uint256 userStartingBalance = xwellProxy.balanceOf(address(this));
        uint256 startingTotalSupply = xwellProxy.totalSupply();

        vm.prank(bridge);
        xwellProxy.burn(address(this), amount);

        assertEq(
            xwellProxy.buffer(bridge),
            buffer + amount,
            "incorrect buffer amount"
        );
        assertEq(
            xwellProxy.balanceOf(address(this)),
            userStartingBalance - amount,
            "incorrect user balance"
        );
        assertEq(
            xwellProxy.allowance(address(this), bridge),
            0,
            "incorrect allowance"
        );
        assertEq(
            startingTotalSupply - xwellProxy.totalSupply(),
            amount,
            "incorrect total supply"
        );
    }

    function testReplenishBufferBridgeSucceeds() public {
        address bridge = address(0xeeeee);
        uint128 rateLimitPerSecond = uint128(
            xwellProxy.MAX_RATE_LIMIT_PER_SECOND()
        );
        uint112 bufferCap = 20_000_000 * 1e18;

        testAddNewBridgeOwnerSucceeds(bridge, rateLimitPerSecond, bufferCap);

        uint256 amount = 100_000 * 1e18;

        uint256 buffer = xwellProxy.buffer(bridge);
        uint256 userStartingBalance = xwellProxy.balanceOf(address(this));
        uint256 startingTotalSupply = xwellProxy.totalSupply();

        vm.prank(bridge);
        xwellProxy.mint(address(this), amount);

        assertEq(
            xwellProxy.buffer(bridge),
            buffer - amount,
            "incorrect buffer amount"
        );
        assertEq(
            xwellProxy.totalSupply() - startingTotalSupply,
            amount,
            "incorrect total supply"
        );
        assertEq(
            xwellProxy.balanceOf(address(this)) - userStartingBalance,
            amount,
            "incorrect user balance"
        );
    }

    function testReplenishBufferBridgeByZeroFails() public {
        address bridge = address(0xeeeee);
        uint128 rateLimitPerSecond = uint128(
            xwellProxy.MAX_RATE_LIMIT_PER_SECOND()
        );
        uint112 bufferCap = 20_000_000 * 1e18;

        testAddNewBridgeOwnerSucceeds(bridge, rateLimitPerSecond, bufferCap);

        vm.prank(bridge);
        vm.expectRevert("MintLimits: deplete amount cannot be 0");
        xwellProxy.mint(address(this), 0);
    }

    function testDepleteBufferBridgeByZeroFails() public {
        address bridge = address(0xeeeee);
        uint128 rateLimitPerSecond = uint128(
            xwellProxy.MAX_RATE_LIMIT_PER_SECOND()
        );
        uint112 bufferCap = 20_000_000 * 1e18;

        testAddNewBridgeOwnerSucceeds(bridge, rateLimitPerSecond, bufferCap);

        vm.prank(bridge);
        vm.expectRevert("MintLimits: replenish amount cannot be 0");
        xwellProxy.burn(address(this), 0);
    }

    function testMintFailsWhenPaused() public {
        vm.prank(pauseGuardian);
        xwellProxy.pause();
        assertTrue(xwellProxy.paused());

        vm.prank(address(xerc20Lockbox));
        vm.expectRevert("Pausable: paused");
        xwellProxy.mint(address(xerc20Lockbox), 1);
    }

    function testMintSucceedsAfterPauseDuration() public {
        testMintFailsWhenPaused();

        vm.warp(xwellProxy.pauseDuration() + block.timestamp + 1);

        assertFalse(xwellProxy.paused());
        testLockboxCanMint(0); /// let function choose amount to mint at random        
    }

    function testBurnFailsWhenPaused() public {
        vm.prank(pauseGuardian);
        xwellProxy.pause();
        assertTrue(xwellProxy.paused());

        vm.prank(address(xerc20Lockbox));
        vm.expectRevert("Pausable: paused");
        xwellProxy.burn(address(xerc20Lockbox), 1);
    }

    function tesBurnSucceedsAfterPauseDuration() public {
        testBurnFailsWhenPaused();

        vm.warp(xwellProxy.pauseDuration() + block.timestamp + 1);

        assertFalse(xwellProxy.paused());

        /// mint, then burn after pause is up
        testLockBoxCanBurn(0); /// let function choose amount to burn at random
    }
}
