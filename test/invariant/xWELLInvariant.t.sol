pragma solidity 0.8.19;

import {RateLimitMidPoint, RateLimitMidpointCommonLibrary} from "@zelt/src/lib/RateLimitMidpointCommonLibrary.sol";
import {RateLimitedMidpointLibrary} from "@zelt/src/lib/RateLimitedMidpointLibrary.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import "forge-std/Test.sol";

import "@test/helper/BaseTest.t.sol";

import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLOwnerHandler} from "@test/invariant/xWELLOwnerHandler.sol";

/// CommonBase, StdCheats, StdUtils
contract xWELLInvariant is BaseTest {
    using RateLimitedMidpointLibrary for RateLimitMidPoint;

    xWELLOwnerHandler handler;

    function setUp() public override {
        super.setUp();

        handler = new xWELLOwnerHandler(
            address(xwellProxy),
            address(well),
            address(xerc20Lockbox)
        );

        MintLimits.RateLimitMidPointInfo memory handlerRateLimits = MintLimits
            .RateLimitMidPointInfo({
                bufferCap: 50_000_000 * 1e18,
                rateLimitPerSecond: 100 * 1e18,
                bridge: address(handler)
            });

        vm.prank(owner);
        xwellProxy.addBridge(handlerRateLimits);

        for (uint160 i = 0; i < 50; i++) {
            address user = address(uint160(i + 100));

            /// give users both WELL and xWELL
            vm.prank(address(wormholeBridgeAdapterProxy));
            xwellProxy.mint(user, 1000 * 1e18);
            well.mint(user, 1000 * 1e18);
        }

        handler.sync();

        /// selectors:
        ///  - transfer
        ///  - transferFrom
        ///  - delegate
        ///  - undelegate
        ///  - depositTo
        ///  - withdrawTo
        ///  - mintToUser
        ///  - burnFromUser
        ///  - setBufferCap
        ///  - setRateLimitPerSecond
        ///  - warp

        bytes4[] memory selectors = new bytes4[](11);

        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.transferFrom.selector;
        selectors[2] = handler.delegate.selector;
        selectors[3] = handler.undelegate.selector;
        selectors[4] = handler.depositTo.selector;
        selectors[5] = handler.withdrawTo.selector;
        selectors[6] = handler.mintToUser.selector;
        selectors[7] = handler.burnFromUser.selector;
        selectors[8] = handler.setBufferCap.selector;
        selectors[9] = handler.setRateLimitPerSecond.selector;
        selectors[10] = handler.warp.selector;

        // Set fuzzer to only call the handler
        targetContract(address(handler));

        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
    }

    function invariant_totalSupplySumOfBalances() public {
        uint256 sumOfBalances;
        uint256 totalSupply = xwellProxy.totalSupply();

        address[] memory users = handler.getUsers();
        for (uint256 i = 0; i < users.length; i++) {
            sumOfBalances += xwellProxy.balanceOf(users[i]);
        }

        assertEq(totalSupply, sumOfBalances, "total supply != sum of balances");
    }

    function invariant_handlerBalancesCorrect() public {
        address[] memory users = handler.getUsers();

        for (uint256 i = 0; i < users.length; i++) {
            assertEq(
                xwellProxy.balanceOf(users[i]),
                handler.userBalances(users[i]),
                "handlers balances incorrect"
            );
        }
    }

    function invariant_sumOfDelegatesBalancesEqualsVotes() public {
        address[] memory users = handler.getUsers();
        for (uint256 i = 0; i < users.length; i++) {
            address[] memory delegators = handler.getUserDelegators(users[i]);
            uint256 sumOfDelegatesBalances;
            for (uint256 j = 0; j < delegators.length; j++) {
                sumOfDelegatesBalances += xwellProxy.balanceOf(delegators[j]);
            }

            assertEq(
                sumOfDelegatesBalances,
                xwellProxy.getVotes(users[i]),
                "incorrect votes count"
            );
        }
    }

    function invariant_totalSupplyLteMaxSupply() public {
        assertTrue(
            xwellProxy.totalSupply() <= xwellProxy.maxSupply(),
            "total supply gt max supply"
        );
    }

    function invariant_bufferStoredLteBufferCap() public {
        {
            (, uint112 bufferCap, , uint112 bufferStored, ) = xwellProxy
                .rateLimits(address(handler));

            assertTrue(
                bufferStored <= bufferCap,
                "handler buffer stored gt buffer cap"
            );
        }
        {
            (, uint112 bufferCap, , uint112 bufferStored, ) = xwellProxy
                .rateLimits(address(xerc20Lockbox));

            assertTrue(
                bufferStored <= bufferCap,
                "lockbox buffer stored gt buffer cap"
            );
        }
    }

    function invariant_bufferLteBufferCap() public {
        {
            (, uint112 bufferCap, , , ) = xwellProxy
                .rateLimits(address(handler));

            assertTrue(
                xwellProxy.buffer(address(handler)) <= bufferCap,
                "handler buffer gt buffer cap"
            );
        }
        {
            (, uint112 bufferCap, , , ) = xwellProxy
                .rateLimits(address(xerc20Lockbox));

            assertTrue(
                xwellProxy.buffer(address(xerc20Lockbox)) <= bufferCap,
                "xerc20Lockbox buffer gt buffer cap"
            );
        }
    }

    function invariant_rateLimitPerSecondLteRLPSMax() public {
        {
            (uint128 rateLimitPerSecond, , , , ) = xwellProxy.rateLimits(
                address(handler)
            );

            assertTrue(
                rateLimitPerSecond <= xwellProxy.maxRateLimitPerSecond(),
                "handler rate limit per second gt max rate limit per second"
            );
        }
        {
            (uint128 rateLimitPerSecond, , , , ) = xwellProxy.rateLimits(
                address(xerc20Lockbox)
            );

            assertTrue(
                rateLimitPerSecond <= xwellProxy.maxRateLimitPerSecond(),
                "xerc20Lockbox rate limit per second gt max rate limit per second"
            );
        }
    }

    function invariant_totalSupplyMirrorCorrect() public {
        assertEq(
            handler.totalSupply(),
            xwellProxy.totalSupply(),
            "total supply mirror incorrect"
        );
    }
}
