// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/console.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {HybridProposalV2} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {ChainlinkOracleConfigs} from "@proposals/ChainlinkOracleConfigs.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";
import {BASE_FORK_ID, OPTIMISM_FORK_ID, ETHEREUM_FORK_ID, BASE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";

/// @notice MIP-X74: rebuild the Base and Optimism ETH-derivative composites on
/// top of the ETH/USD OEV wrapper that prices WETH, so both legs of a WETH/LST
/// liquidation read the same delayed round (MOO-1023).
contract mipx74 is HybridProposalV2, ChainlinkOracleConfigs {
    using ChainIds for uint256;

    string public constant override name = "MIP-X74";

    /// @notice composites rebuilt by this proposal are the ones based on this feed
    string public constant ETH_FEED = "CHAINLINK_ETH_USD";

    /// @notice OEV wrapper over ETH_FEED that prices WETH (deployed by MIP-X72)
    string public constant ETH_WRAPPER = "CHAINLINK_ETH_USD_OEV_WRAPPER";

    /// @notice pre-V2 ETH wrapper; Optimism weETH still reads it
    string public constant LEGACY_ETH_WRAPPER =
        "CHAINLINK_ETH_USD_OEV_WRAPPER_DEPRECATED";

    /// @notice archive suffix for the replaced (live) composites
    string public constant DEPRECATED_SUFFIX = "_DEPRECATED_X74";

    constructor() {
        _setProposalDescription(
            bytes(vm.readFile("./proposals/mips/mip-x74/x74.md"))
        );
    }

    function primaryForkId() public pure override returns (uint256) {
        return ETHEREUM_FORK_ID;
    }

    /// @notice Proposal.run() without the top-level broadcast: each chain's
    /// deploy opens its own after selecting its fork (same pattern as MIP-X72).
    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        vm.selectFork(primaryForkId());

        setProposalDescriptionUri(_resolveProposalDescriptionUri(this.name()));

        initProposal(addresses);

        (, address deployerAddress, ) = vm.readCallers();

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);

        if (DO_BUILD) build(addresses);
        if (DO_RUN) simulate(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_VALIDATE) {
            validate(addresses, deployerAddress);
            console.log("Validation completed for proposal ", this.name());
        }
        if (DO_PRINT) {
            printProposalActionSteps();

            addresses.removeAllRestrictions();
            printCalldata(addresses);

            _printAddressesChanges(addresses);
        }
    }

    function deploy(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);
        _deployComposites(addresses);

        vm.selectFork(OPTIMISM_FORK_ID);
        _deployComposites(addresses);

        vm.selectFork(primaryForkId());
    }

    /// @notice MIP-X72 must have executed: WETH has to be priced by the same
    /// wrapper the new composites read, otherwise the legs stay out of lockstep.
    function afterDeploy(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);
        _assertWethOnWrapper(addresses);

        vm.selectFork(OPTIMISM_FORK_ID);
        _assertWethOnWrapper(addresses);

        vm.selectFork(primaryForkId());
    }

    function build(Addresses addresses) public override {
        vm.selectFork(BASE_FORK_ID);
        _buildSetFeeds(addresses);

        vm.selectFork(OPTIMISM_FORK_ID);
        _buildSetFeeds(addresses);

        vm.selectFork(primaryForkId());
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);
        _validateComposites(addresses);

        vm.selectFork(OPTIMISM_FORK_ID);
        _validateComposites(addresses);

        vm.selectFork(primaryForkId());
    }

    /// @notice Deploy a wrapper-based composite per ETH derivative on the active
    /// chain, mirroring the live feed's multipliers, and archive the live feed.
    function _deployComposites(Addresses addresses) internal {
        ChainlinkOracle oracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );
        address wrapper = addresses.getAddress(ETH_WRAPPER);
        address ethFeed = addresses.getAddress(ETH_FEED);
        require(
            address(ChainlinkOEVWrapper(payable(wrapper)).priceFeed()) ==
                ethFeed,
            "MIP-X74: ETH OEV wrapper does not wrap the standard ETH/USD feed"
        );

        CompositeOracleConfig[] memory configs = _ethComposites();

        vm.startBroadcast();
        for (uint256 i = 0; i < configs.length; i++) {
            string memory deprecatedName = string.concat(
                configs[i].compositeOracleName,
                DEPRECATED_SUFFIX
            );
            if (addresses.isAddressSet(deprecatedName)) {
                continue;
            }

            // the live feed, not the registry key: Optimism weETH is priced by a
            // composite registered under a different key
            ChainlinkCompositeOracle old = ChainlinkCompositeOracle(
                address(oracle.getFeed(_symbol(addresses, configs[i])))
            );
            require(
                _isReplaceableBase(addresses, old.base(), ethFeed),
                string.concat(
                    "MIP-X74: unexpected base for ",
                    configs[i].compositeOracleName
                )
            );

            ChainlinkCompositeOracle composite = new ChainlinkCompositeOracle(
                wrapper,
                old.multiplier(),
                old.secondMultiplier()
            );

            addresses.addAddress(deprecatedName, address(old));
            addresses.changeAddress(
                configs[i].compositeOracleName,
                address(composite),
                true
            );
        }
        vm.stopBroadcast();
    }

    function _assertWethOnWrapper(Addresses addresses) internal view {
        assertEq(
            address(
                ChainlinkOracle(addresses.getAddress("CHAINLINK_ORACLE"))
                    .getFeed(ERC20(addresses.getAddress("WETH")).symbol())
            ),
            addresses.getAddress(ETH_WRAPPER),
            "MIP-X74: WETH is not priced by the ETH OEV wrapper (execute MIP-X72 first)"
        );
    }

    function _buildSetFeeds(Addresses addresses) internal {
        CompositeOracleConfig[] memory configs = _ethComposites();
        address chainlinkOracle = addresses.getAddress("CHAINLINK_ORACLE");

        for (uint256 i = 0; i < configs.length; i++) {
            string memory symbol = _symbol(addresses, configs[i]);

            _pushAction(
                chainlinkOracle,
                abi.encodeWithSignature(
                    "setFeed(string,address)",
                    symbol,
                    addresses.getAddress(configs[i].compositeOracleName)
                ),
                string.concat(
                    "Repoint ",
                    symbol,
                    " feed on ",
                    _chainName(),
                    " at a composite oracle based on the ETH/USD OEV wrapper"
                )
            );
        }
    }

    function _validateComposites(Addresses addresses) internal view {
        ChainlinkOracle oracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );
        address wrapper = addresses.getAddress(ETH_WRAPPER);
        address ethFeed = addresses.getAddress(ETH_FEED);

        _assertWethOnWrapper(addresses);

        CompositeOracleConfig[] memory configs = _ethComposites();
        for (uint256 i = 0; i < configs.length; i++) {
            string memory name_ = configs[i].compositeOracleName;
            ChainlinkCompositeOracle composite = ChainlinkCompositeOracle(
                addresses.getAddress(name_)
            );
            ChainlinkCompositeOracle old = ChainlinkCompositeOracle(
                addresses.getAddress(string.concat(name_, DEPRECATED_SUFFIX))
            );
            string memory symbol = _symbol(addresses, configs[i]);

            assertEq(
                address(oracle.getFeed(symbol)),
                address(composite),
                string.concat("MIP-X74: feed not repointed for ", symbol)
            );
            assertEq(
                composite.base(),
                wrapper,
                string.concat(
                    "MIP-X74: base is not the OEV wrapper for ",
                    name_
                )
            );
            assertTrue(
                _isReplaceableBase(addresses, old.base(), ethFeed),
                string.concat("MIP-X74: unexpected archived base for ", name_)
            );
            assertEq(
                composite.multiplier(),
                old.multiplier(),
                string.concat("MIP-X74: multiplier drift for ", name_)
            );
            assertEq(
                composite.secondMultiplier(),
                old.secondMultiplier(),
                string.concat("MIP-X74: secondMultiplier drift for ", name_)
            );

            // at most one ETH/USD round apart, i.e. well under 1%
            (, int256 newAnswer, , , ) = composite.latestRoundData();
            (, int256 oldAnswer, , , ) = old.latestRoundData();
            assertApproxEqRel(
                uint256(newAnswer),
                uint256(oldAnswer),
                0.01e18,
                string.concat("MIP-X74: price drifted >1% for ", name_)
            );
        }
    }

    /// @notice a composite this proposal replaces reads ETH/USD raw, or through
    /// the pre-V2 ETH wrapper (separate cachedRoundId from WETH's wrapper)
    function _isReplaceableBase(
        Addresses addresses,
        address base,
        address ethFeed
    ) internal view returns (bool) {
        if (base == ethFeed) return true;
        return
            addresses.isAddressSet(LEGACY_ETH_WRAPPER) &&
            base == addresses.getAddress(LEGACY_ETH_WRAPPER);
    }

    /// @notice active chain's composites whose base leg is ETH/USD
    /// (cbETH, wstETH, rETH, weETH, wrsETH on both Base and Optimism)
    function _ethComposites()
        internal
        view
        returns (CompositeOracleConfig[] memory ethConfigs)
    {
        CompositeOracleConfig[]
            memory configs = getCompositeOracleConfigurations(block.chainid);

        uint256 count;
        for (uint256 i = 0; i < configs.length; i++) {
            if (_isEthBased(configs[i])) count++;
        }

        ethConfigs = new CompositeOracleConfig[](count);
        uint256 j;
        for (uint256 i = 0; i < configs.length; i++) {
            if (_isEthBased(configs[i])) ethConfigs[j++] = configs[i];
        }
    }

    function _isEthBased(
        CompositeOracleConfig memory config
    ) internal pure returns (bool) {
        return
            keccak256(bytes(config.baseFeedName)) == keccak256(bytes(ETH_FEED));
    }

    function _symbol(
        Addresses addresses,
        CompositeOracleConfig memory config
    ) internal view returns (string memory) {
        return ERC20(addresses.getAddress(config.symbol)).symbol();
    }

    function _chainName() internal view returns (string memory) {
        return block.chainid == BASE_CHAIN_ID ? "Base" : "Optimism";
    }
}
