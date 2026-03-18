//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MarketAddV2} from "@proposals/templates/MarketAddV2.sol";
import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {OEVProtocolFeeRedeemer} from "@protocol/OEVProtocolFeeRedeemer.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import "@protocol/utils/ChainIds.sol";

/// @title MIP-B59: Add VVV Market to Moonwell on Base
/// @notice Deploys the OEV wrapper for VVV and adds the market with OEV-enabled pricing
contract mipb59 is MarketAddV2 {
    using ChainIds for uint256;
    using stdStorage for StdStorage;

    uint16 public constant FEE_MULTIPLIER = 3000;
    uint256 public constant MAX_ROUND_DELAY = 10;
    uint256 public constant MAX_DECREMENTS = 10;

    string public constant OEV_WRAPPER_NAME = "CHAINLINK_VVV_USD_OEV_WRAPPER";

    /// @notice Raw Chainlink price saved before simulation for comparison with wrapper
    int256 public rawChainlinkPrice;

    function afterDeploy(
        Addresses addresses,
        address deployer
    ) public override {
        uint256 forkBefore = vm.activeFork();
        vm.selectFork(BASE_FORK_ID);

        /// Deploy OEV wrapper for VVV feed on Base
        if (!addresses.isAddressSet(OEV_WRAPPER_NAME)) {
            vm.startBroadcast(deployer);

            ChainlinkOEVWrapper wrapper = new ChainlinkOEVWrapper(
                addresses.getAddress("CHAINLINK_VVV_USD"),
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                addresses.getAddress("CHAINLINK_ORACLE"),
                addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
                FEE_MULTIPLIER,
                MAX_ROUND_DELAY,
                MAX_DECREMENTS
            );

            vm.stopBroadcast();
            addresses.addAddress(OEV_WRAPPER_NAME, address(wrapper));
        }

        if (vm.activeFork() != forkBefore) {
            vm.selectFork(forkBefore);
        }
    }

    function build(Addresses addresses) public override {
        /// Build market add actions via parent (uses OEV wrapper as price feed)
        super.build(addresses);

        /// Whitelist mVVV on the OEV fee redeemer
        vm.selectFork(BASE_FORK_ID);
        address feeRedeemer = addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER");
        address mToken = addresses.getAddress("MOONWELL_VVV");

        _pushAction(
            feeRedeemer,
            abi.encodeWithSignature(
                "whitelistMarket(address,bool)",
                mToken,
                true
            ),
            "Whitelist mVVV on OEV fee redeemer"
        );
    }

    function validate(Addresses addresses, address deployer) public override {
        /// Validate market add via parent
        super.validate(addresses, deployer);

        vm.selectFork(BASE_FORK_ID);

        /// Validate OEV wrapper deployment and configuration
        ChainlinkOEVWrapper wrapper = ChainlinkOEVWrapper(
            payable(addresses.getAddress(OEV_WRAPPER_NAME))
        );

        assertEq(
            address(wrapper.priceFeed()),
            addresses.getAddress("CHAINLINK_VVV_USD"),
            "OEV wrapper priceFeed mismatch"
        );
        assertEq(
            wrapper.liquidatorFeeBps(),
            FEE_MULTIPLIER,
            "OEV wrapper fee mismatch"
        );
        assertEq(
            wrapper.feeRecipient(),
            addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"),
            "OEV wrapper feeRecipient mismatch"
        );
        assertEq(
            address(wrapper.chainlinkOracle()),
            addresses.getAddress("CHAINLINK_ORACLE"),
            "OEV wrapper chainlinkOracle mismatch"
        );
        assertEq(
            wrapper.owner(),
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            "OEV wrapper owner mismatch"
        );
        assertEq(
            wrapper.maxRoundDelay(),
            MAX_ROUND_DELAY,
            "OEV wrapper maxRoundDelay mismatch"
        );
        assertEq(
            wrapper.maxDecrements(),
            MAX_DECREMENTS,
            "OEV wrapper maxDecrements mismatch"
        );
        assertGt(
            wrapper.cachedRoundId(),
            0,
            "OEV wrapper cachedRoundId should be > 0"
        );

        /// Validate OEV wrapper returns the same price as the raw Chainlink feed
        (, int256 wrapperPrice, , , ) = wrapper.latestRoundData();
        assertEq(
            wrapperPrice,
            rawChainlinkPrice,
            "OEV wrapper price does not match raw Chainlink feed price"
        );

        /// Validate mVVV is whitelisted on the fee redeemer
        OEVProtocolFeeRedeemer feeRedeemer = OEVProtocolFeeRedeemer(
            payable(addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"))
        );
        assertTrue(
            feeRedeemer.whitelistedMarkets(
                addresses.getAddress("MOONWELL_VVV")
            ),
            "mVVV not whitelisted on OEV fee redeemer"
        );
    }

    function beforeSimulationHook(Addresses addresses) public override {
        uint256 forkBefore = vm.activeFork();
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            vm.selectFork(chainId.toForkId());

            for (uint256 j = 0; j < mTokens[chainId].length; j++) {
                MTokenConfiguration memory config = mTokens[chainId][j];

                /// Use stdstore instead of deal() for Solmate ERC20 compatibility.
                /// VVV uses Solmate's ERC20 which has a different storage layout
                /// than OpenZeppelin's, causing deal() to set the wrong slot.
                stdstore
                    .target(addresses.getAddress(config.tokenAddressName))
                    .sig("balanceOf(address)")
                    .with_key(addresses.getAddress("TEMPORAL_GOVERNOR"))
                    .checked_write(config.initialMintAmount);
            }
        }

        /// Save raw Chainlink VVV/USD price before simulation for later comparison
        vm.selectFork(BASE_FORK_ID);
        (, rawChainlinkPrice, , , ) = AggregatorV3Interface(
            addresses.getAddress("CHAINLINK_VVV_USD")
        ).latestRoundData();
        require(
            rawChainlinkPrice > 0,
            "Raw Chainlink VVV/USD price must be positive"
        );

        if (vm.activeFork() != forkBefore) {
            vm.selectFork(forkBefore);
        }
    }
}
