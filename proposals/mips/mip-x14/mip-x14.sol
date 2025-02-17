//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@protocol/utils/ChainIds.sol";

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {ChainlinkFeedOEVWrapper} from "@protocol/oracles/ChainlinkFeedOEVWrapper.sol";
import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";
import {DeployChainlinkOEVWrapper} from "@script/DeployChainlinkOEVWrapper.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {OPTIMISM_FORK_ID, BASE_FORK_ID, OPTIMISM_CHAIN_ID, BASE_CHAIN_ID} from "@utils/ChainIds.sol";

contract mipx14 is HybridProposal, DeployChainlinkOEVWrapper {
    using ProposalActions for *;
    using ChainIds for uint256;

    function name() external pure override returns (string memory) {
        return "MIP-X14";
    }

    function primaryForkId() public pure override returns (uint256) {
        return OPTIMISM_FORK_ID;
    }

    struct OracleConfig {
        string oracleName;
        string tokenName;
        string marketName;
    }

    mapping(uint256 => OracleConfig[]) internal _oracleConfigs;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x14/x14.md")
        );
        _setProposalDescription(proposalDescription);

        // Initialize oracle configurations for Base
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_ETH_USD", "WETH", "MOONWELL_WETH")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_BTC_USD", "cbBTC", "MOONWELL_cbBTC")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_EURC_USD", "EURC", "MOONWELL_EURC")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_WELL_USD", "xWELL_PROXY", "MOONWELL_WELL")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_USDS_USD", "USDS", "MOONWELL_USDS")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_TBTC_USD", "TBTC", "MOONWELL_TBTC")
        );
        _oracleConfigs[BASE_CHAIN_ID].push(
            OracleConfig("CHAINLINK_VIRTUAL_USD", "VIRTUAL", "MOONWELL_VIRTUAL")
        );

        // Initialize oracle configurations for Optimism
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_ETH_USD", "WETH", "MOONWELL_WETH")
        );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_USDC_USD", "USDC", "MOONWELL_USDC")
        );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_DAI_USD", "DAI", "MOONWELL_DAI")
        );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_USDT_USD", "USDT", "MOONWELL_USDT")
        );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_WBTC_USD", "WBTC", "MOONWELL_WBTC")
        );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_OP_USD", "OP", "MOONWELL_OP")
        );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_VELO_USD", "VELO", "MOONWELL_VELO")
        );
        _oracleConfigs[OPTIMISM_CHAIN_ID].push(
            OracleConfig("CHAINLINK_WELL_USD", "xWELL_PROXY", "MOONWELL_WELL")
        );
    }

    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        initProposal(addresses);

        (, address deployerAddress, ) = vm.readCallers();

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);

        if (DO_BUILD) build(addresses);
        if (DO_RUN) run(addresses, deployerAddress);
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
        // Deploy composite oracle for weETH on Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        vm.startBroadcast();

        // Only deploy if not already set
        ChainlinkCompositeOracle weethCompositeOracle = new ChainlinkCompositeOracle(
                addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER"),
                addresses.getAddress("CHAINLINK_WEETH_ORACLE"),
                address(0) // No second multiplier needed
            );

        addresses.changeAddress(
            "CHAINLINK_WEETH_ETH_COMPOSITE_ORACLE",
            address(weethCompositeOracle),
            OPTIMISM_CHAIN_ID,
            true
        );

        for (uint i = 0; i < _oracleConfigs[OPTIMISM_CHAIN_ID].length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(
                    _oracleConfigs[OPTIMISM_CHAIN_ID][i].oracleName,
                    "_OEV_WRAPPER"
                )
            );
            if (!addresses.isAddressSet(wrapperName)) {
                deployChainlinkOEVWrapper(
                    addresses,
                    _oracleConfigs[OPTIMISM_CHAIN_ID][i].oracleName
                );
            }
        }
        vm.stopBroadcast();

        // Deploy for Base
        vm.selectFork(BASE_FORK_ID);
        vm.startBroadcast();
        for (uint i = 0; i < _oracleConfigs[BASE_CHAIN_ID].length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(
                    _oracleConfigs[BASE_CHAIN_ID][i].oracleName,
                    "_OEV_WRAPPER"
                )
            );
            if (!addresses.isAddressSet(wrapperName)) {
                deployChainlinkOEVWrapper(
                    addresses,
                    _oracleConfigs[BASE_CHAIN_ID][i].oracleName
                );
            }
        }

        vm.stopBroadcast();
    }

    function build(Addresses addresses) public override {
        // Set the weETH composite oracle in the Chainlink oracle on Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setFeed(string,address)",
                "weETH",
                addresses.getAddress("CHAINLINK_WEETH_ETH_COMPOSITE_ORACLE")
            ),
            "Set composite price feed for weETH"
        );

        // Build for Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        for (uint i = 0; i < _oracleConfigs[OPTIMISM_CHAIN_ID].length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(
                    _oracleConfigs[OPTIMISM_CHAIN_ID][i].oracleName,
                    "_OEV_WRAPPER"
                )
            );
            _pushAction(
                addresses.getAddress("CHAINLINK_ORACLE"),
                abi.encodeWithSignature(
                    "setFeed(string,address)",
                    ERC20(
                        addresses.getAddress(
                            _oracleConfigs[OPTIMISM_CHAIN_ID][i].tokenName
                        )
                    ).symbol(),
                    addresses.getAddress(wrapperName)
                ),
                string(
                    abi.encodePacked(
                        "Set price feed for ",
                        _oracleConfigs[OPTIMISM_CHAIN_ID][i].tokenName
                    )
                )
            );
        }

        // Build for Base
        vm.selectFork(BASE_FORK_ID);
        for (uint i = 0; i < _oracleConfigs[BASE_CHAIN_ID].length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(
                    _oracleConfigs[BASE_CHAIN_ID][i].oracleName,
                    "_OEV_WRAPPER"
                )
            );
            _pushAction(
                addresses.getAddress("CHAINLINK_ORACLE"),
                abi.encodeWithSignature(
                    "setFeed(string,address)",
                    ERC20(
                        addresses.getAddress(
                            _oracleConfigs[BASE_CHAIN_ID][i].tokenName
                        )
                    ).symbol(),
                    addresses.getAddress(wrapperName)
                ),
                string(
                    abi.encodePacked(
                        "Set price feed for ",
                        _oracleConfigs[BASE_CHAIN_ID][i].tokenName
                    )
                )
            );
        }
    }

    function validate(Addresses addresses, address) public override {
        // Validate Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        _validateChain(addresses, OPTIMISM_CHAIN_ID);

        // Validate Base
        vm.selectFork(BASE_FORK_ID);
        _validateChain(addresses, BASE_CHAIN_ID);
    }

    function _validateChain(
        Addresses addresses,
        uint256 chainId
    ) internal view {
        // Validate composite oracle if on Optimism
        if (chainId == OPTIMISM_CHAIN_ID) {
            ChainlinkCompositeOracle compositeOracle = ChainlinkCompositeOracle(
                addresses.getAddress("CHAINLINK_WEETH_ETH_COMPOSITE_ORACLE")
            );

            // Validate composite oracle configuration
            assertEq(
                compositeOracle.base(),
                addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER"),
                "Wrong base oracle for weETH composite"
            );
            assertEq(
                compositeOracle.multiplier(),
                addresses.getAddress("CHAINLINK_WEETH_ORACLE"),
                "Wrong multiplier oracle for weETH composite"
            );
            assertEq(
                compositeOracle.secondMultiplier(),
                address(0),
                "Second multiplier should be zero for weETH composite"
            );

            // Validate price feed is working
            (, int256 price, , , ) = compositeOracle.latestRoundData();
            assertGt(
                uint256(price),
                0,
                "weETH composite oracle returned zero price"
            );
        }

        for (uint i = 0; i < _oracleConfigs[chainId].length; i++) {
            _validateWrapper(addresses, chainId, i);
        }
    }

    function _validateWrapper(
        Addresses addresses,
        uint256 chainId,
        uint256 index
    ) internal view {
        string memory wrapperName = string(
            abi.encodePacked(
                _oracleConfigs[chainId][index].oracleName,
                "_OEV_WRAPPER"
            )
        );
        ChainlinkFeedOEVWrapper wrapper = ChainlinkFeedOEVWrapper(
            addresses.getAddress(wrapperName)
        );
        string memory tokenName = _oracleConfigs[chainId][index].tokenName;

        _validateOwnership(addresses, wrapper, tokenName);
        _validateFeed(addresses, wrapper, chainId, index, tokenName);
        _validateMarket(addresses, wrapper, chainId, index, tokenName);
        _validateParameters(wrapper, tokenName);
        _validateInterface(wrapper, tokenName);
        _validateRoundData(wrapper, tokenName);
    }

    function _validateOwnership(
        Addresses addresses,
        ChainlinkFeedOEVWrapper wrapper,
        string memory tokenName
    ) internal view {
        address owner = Ownable(address(wrapper)).owner();
        assertEq(
            owner,
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            _errorMessage("owner", tokenName)
        );
    }

    function _validateFeed(
        Addresses addresses,
        ChainlinkFeedOEVWrapper wrapper,
        uint256 chainId,
        uint256 index,
        string memory tokenName
    ) internal view {
        assertEq(
            address(wrapper.originalFeed()),
            addresses.getAddress(_oracleConfigs[chainId][index].oracleName),
            _errorMessage("feed", tokenName)
        );
    }

    function _validateMarket(
        Addresses addresses,
        ChainlinkFeedOEVWrapper wrapper,
        uint256 chainId,
        uint256 index,
        string memory tokenName
    ) internal view {
        assertEq(
            address(wrapper.WETHMarket()),
            addresses.getAddress("MOONWELL_WETH"),
            _errorMessage("market", tokenName)
        );
    }

    function _validateParameters(
        ChainlinkFeedOEVWrapper wrapper,
        string memory tokenName
    ) internal view {
        assertEq(
            wrapper.feeMultiplier(),
            99,
            _errorMessage("fee multiplier", tokenName)
        );
    }

    function _validateInterface(
        ChainlinkFeedOEVWrapper wrapper,
        string memory tokenName
    ) internal view {
        assertEq(
            wrapper.decimals(),
            wrapper.originalFeed().decimals(),
            _errorMessage("decimals", tokenName)
        );
        assertEq(
            wrapper.description(),
            wrapper.originalFeed().description(),
            _errorMessage("description", tokenName)
        );
        assertEq(
            wrapper.version(),
            wrapper.originalFeed().version(),
            _errorMessage("version", tokenName)
        );
    }

    function _validateRoundData(
        ChainlinkFeedOEVWrapper wrapper,
        string memory tokenName
    ) internal view {
        _validateRoundDataValues(wrapper, tokenName);
        _validateCachedRound(wrapper, tokenName);
    }

    function _validateRoundDataValues(
        ChainlinkFeedOEVWrapper wrapper,
        string memory tokenName
    ) internal view {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;

        (roundId, answer, startedAt, updatedAt, answeredInRound) = wrapper
            .latestRoundData();

        uint80 expectedRoundId;
        int256 expectedAnswer;
        uint256 expectedStartedAt;
        uint256 expectedUpdatedAt;
        uint80 expectedAnsweredInRound;

        (
            expectedRoundId,
            expectedAnswer,
            expectedStartedAt,
            expectedUpdatedAt,
            expectedAnsweredInRound
        ) = wrapper.originalFeed().getRoundData(
            uint80(wrapper.originalFeed().latestRound())
        );

        assertEq(roundId, expectedRoundId, _errorMessage("roundId", tokenName));
        assertEq(answer, expectedAnswer, _errorMessage("answer", tokenName));
        assertEq(
            startedAt,
            expectedStartedAt,
            _errorMessage("startedAt", tokenName)
        );
        assertEq(
            updatedAt,
            expectedUpdatedAt,
            _errorMessage("updatedAt", tokenName)
        );
        assertEq(
            answeredInRound,
            expectedAnsweredInRound,
            _errorMessage("answeredInRound", tokenName)
        );
    }

    function _validateCachedRound(
        ChainlinkFeedOEVWrapper wrapper,
        string memory tokenName
    ) internal view {
        assertGt(
            wrapper.cachedRoundId(),
            0,
            _errorMessage("cachedRoundId", tokenName)
        );
    }

    function _errorMessage(
        string memory field,
        string memory tokenName
    ) internal pure returns (string memory) {
        return string(abi.encodePacked("Wrong ", field, " for ", tokenName));
    }
}
