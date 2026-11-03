//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ActionType} from "@proposals/proposalTypes/IProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {BASE_FORK_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID} from "@utils/ChainIds.sol";
import {MToken} from "@protocol/MToken.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {MarketUpdateV2Template} from "@proposals/templates/MarketUpdateV2.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title MIP-X75: Anthias Labs Risk Parameter Recommendations (10/27/26)
/// @notice x75.json market updates, plus a fixed $0.01 MAMO price on Base
///         because Chainlink is deprecating the MAMO / USD feed.
contract mipx75 is MarketUpdateV2Template {
    /// @notice $0.01, stored raw; MAMO has 18 decimals so no rescaling
    uint256 public constant MAMO_PRICE = 0.01e18;

    function name() external pure override returns (string memory) {
        return "MIP-X75";
    }

    function build(Addresses addresses) public override {
        super.build(addresses);

        vm.selectFork(BASE_FORK_ID);

        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setUnderlyingPrice(address,uint256)",
                addresses.getAddress("MOONWELL_MAMO"),
                MAMO_PRICE
            ),
            "Set fixed $0.01 price for MAMO on Base",
            ActionType.Base
        );
    }

    function validate(Addresses addresses, address deployer) public override {
        super.validate(addresses, deployer);

        vm.selectFork(BASE_FORK_ID);

        address mMamo = addresses.getAddress("MOONWELL_MAMO");
        assertEq(
            IERC20(MErc20(mMamo).underlying()).decimals(),
            18,
            "MAMO decimals"
        );
        assertEq(
            ChainlinkOracle(addresses.getAddress("CHAINLINK_ORACLE"))
                .getUnderlyingPrice(MToken(mMamo)),
            MAMO_PRICE,
            "MAMO price not fixed"
        );
    }

    function expectedPriceChanges(
        Addresses addresses
    ) public view override returns (address[] memory changes) {
        changes = new address[](1);
        changes[0] = addresses.getAddress("MOONWELL_MAMO", BASE_CHAIN_ID);
    }

    function expectedMarketStateChanges(
        Addresses addresses
    ) public view override returns (MarketStateChange[] memory changes) {
        uint256[2] memory chains = [BASE_CHAIN_ID, OPTIMISM_CHAIN_ID];
        changes = new MarketStateChange[](
            marketUpdates[BASE_CHAIN_ID].length +
                marketUpdates[OPTIMISM_CHAIN_ID].length
        );

        uint256 n;
        for (uint256 c = 0; c < chains.length; c++) {
            MarketUpdate[] storage updates = marketUpdates[chains[c]];
            for (uint256 i = 0; i < updates.length; i++) {
                changes[n++] = MarketStateChange({
                    chainId: chains[c],
                    target: addresses.getAddress(updates[i].market, chains[c]),
                    riskParameters: true,
                    accounting: false
                });
            }
        }
    }
}
