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
import {BASE_FORK_ID, BASE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";

/// @notice MIP-B61: rebuild the Base ETH-derivative composites on top of the
/// ETH/USD OEV wrapper that prices WETH, so both legs of a WETH/LST liquidation
/// read the same delayed round (MOO-1023).
contract mipb61 is HybridProposalV2, ChainlinkOracleConfigs {
    using ChainIds for uint256;

    string public constant override name = "MIP-B61";

    /// @notice composites rebuilt by this proposal are the ones based on this feed
    string public constant ETH_FEED = "CHAINLINK_ETH_USD";

    /// @notice OEV wrapper over ETH_FEED that prices WETH (deployed by MIP-X72)
    string public constant ETH_WRAPPER = "CHAINLINK_ETH_USD_OEV_WRAPPER";

    /// @notice archive suffix for the composites that read the raw ETH/USD feed
    string public constant DEPRECATED_SUFFIX = "_DEPRECATED_RAW_BASE";

    constructor() {
        _setProposalDescription(
            bytes(vm.readFile("./proposals/mips/mip-b61/b61.md"))
        );
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    /// @notice Proposal.run() without the top-level broadcast: deploy() opens
    /// its own after selecting the Base fork (same pattern as MIP-B60/X72).
    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

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

        address wrapper = addresses.getAddress(ETH_WRAPPER);
        address ethFeed = addresses.getAddress(ETH_FEED);
        require(
            address(ChainlinkOEVWrapper(payable(wrapper)).priceFeed()) ==
                ethFeed,
            "MIP-B61: ETH OEV wrapper does not wrap the standard ETH/USD feed"
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

            ChainlinkCompositeOracle old = ChainlinkCompositeOracle(
                addresses.getAddress(configs[i].compositeOracleName)
            );
            require(
                old.base() == ethFeed,
                string.concat(
                    "MIP-B61: unexpected base for ",
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

        vm.selectFork(primaryForkId());
    }

    /// @notice MIP-X72 must have executed: WETH has to be priced by the same
    /// wrapper the new composites read, otherwise the legs stay out of lockstep.
    function afterDeploy(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);

        assertEq(
            address(
                ChainlinkOracle(addresses.getAddress("CHAINLINK_ORACLE"))
                    .getFeed(ERC20(addresses.getAddress("WETH")).symbol())
            ),
            addresses.getAddress(ETH_WRAPPER),
            "MIP-B61: WETH is not priced by the ETH OEV wrapper (execute MIP-X72 first)"
        );

        vm.selectFork(primaryForkId());
    }

    function build(Addresses addresses) public override {
        vm.selectFork(BASE_FORK_ID);

        CompositeOracleConfig[] memory configs = _ethComposites();
        address chainlinkOracle = addresses.getAddress("CHAINLINK_ORACLE");

        for (uint256 i = 0; i < configs.length; i++) {
            string memory symbol = ERC20(
                addresses.getAddress(configs[i].symbol)
            ).symbol();

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
                    " feed at a composite oracle based on the ETH/USD OEV wrapper"
                )
            );
        }

        vm.selectFork(primaryForkId());
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);

        ChainlinkOracle oracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );
        address wrapper = addresses.getAddress(ETH_WRAPPER);
        address ethFeed = addresses.getAddress(ETH_FEED);

        assertEq(
            address(
                oracle.getFeed(ERC20(addresses.getAddress("WETH")).symbol())
            ),
            wrapper,
            "MIP-B61: WETH feed is not the ETH OEV wrapper"
        );

        CompositeOracleConfig[] memory configs = _ethComposites();
        for (uint256 i = 0; i < configs.length; i++) {
            string memory name_ = configs[i].compositeOracleName;
            ChainlinkCompositeOracle composite = ChainlinkCompositeOracle(
                addresses.getAddress(name_)
            );
            ChainlinkCompositeOracle old = ChainlinkCompositeOracle(
                addresses.getAddress(string.concat(name_, DEPRECATED_SUFFIX))
            );
            string memory symbol = ERC20(
                addresses.getAddress(configs[i].symbol)
            ).symbol();

            assertEq(
                address(oracle.getFeed(symbol)),
                address(composite),
                string.concat("MIP-B61: feed not repointed for ", symbol)
            );
            assertEq(
                composite.base(),
                wrapper,
                string.concat(
                    "MIP-B61: base is not the OEV wrapper for ",
                    name_
                )
            );
            assertEq(
                old.base(),
                ethFeed,
                string.concat("MIP-B61: archived base is not raw for ", name_)
            );
            assertEq(
                composite.multiplier(),
                old.multiplier(),
                string.concat("MIP-B61: multiplier drift for ", name_)
            );
            assertEq(
                composite.secondMultiplier(),
                old.secondMultiplier(),
                string.concat("MIP-B61: secondMultiplier drift for ", name_)
            );

            // at most one ETH/USD round apart, i.e. well under 1%
            (, int256 newAnswer, , , ) = composite.latestRoundData();
            (, int256 oldAnswer, , , ) = old.latestRoundData();
            assertApproxEqRel(
                uint256(newAnswer),
                uint256(oldAnswer),
                0.01e18,
                string.concat("MIP-B61: price drifted >1% for ", name_)
            );
        }

        vm.selectFork(primaryForkId());
    }

    /// @notice Base composites whose base leg is ETH/USD (cbETH, wstETH, rETH, weETH, wrsETH)
    function _ethComposites()
        internal
        view
        returns (CompositeOracleConfig[] memory ethConfigs)
    {
        CompositeOracleConfig[]
            memory configs = getCompositeOracleConfigurations(BASE_CHAIN_ID);

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
}
