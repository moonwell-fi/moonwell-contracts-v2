//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ActionType} from "@proposals/proposalTypes/IProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {BASE_FORK_ID, BASE_CHAIN_ID, OPTIMISM_FORK_ID, OPTIMISM_CHAIN_ID} from "@utils/ChainIds.sol";
import {MToken} from "@protocol/MToken.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {MarketUpdateV2Template} from "@proposals/templates/MarketUpdateV2.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title MIP-X75: Anthias Labs Risk Parameter Recommendations (10/27/26)
/// @notice x75.json market updates, plus fixed prices for MAMO on Base
///         (Chainlink is deprecating the MAMO / USD feed) and VELO on OP.
contract mipx75 is MarketUpdateV2Template {
    /// @notice $0.01, stored raw; MAMO has 18 decimals so no rescaling
    uint256 public constant MAMO_PRICE = 0.01e18;

    /// @notice VELO / USD answer on 2026-11-04 (2599706 at 8 decimals); VELO has 18 decimals
    uint256 public constant VELO_PRICE = 0.02599706e18;

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

        vm.selectFork(OPTIMISM_FORK_ID);

        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setUnderlyingPrice(address,uint256)",
                addresses.getAddress("MOONWELL_VELO"),
                VELO_PRICE
            ),
            "Set fixed $0.02599706 price for VELO on OP Mainnet",
            ActionType.Optimism
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

        vm.selectFork(OPTIMISM_FORK_ID);

        address mVelo = addresses.getAddress("MOONWELL_VELO");
        assertEq(
            IERC20(MErc20(mVelo).underlying()).decimals(),
            18,
            "VELO decimals"
        );
        assertEq(
            ChainlinkOracle(addresses.getAddress("CHAINLINK_ORACLE"))
                .getUnderlyingPrice(MToken(mVelo)),
            VELO_PRICE,
            "VELO price not fixed"
        );
    }

    function expectedPriceChanges(
        Addresses addresses
    ) public view override returns (address[] memory changes) {
        changes = new address[](2);
        changes[0] = addresses.getAddress("MOONWELL_MAMO", BASE_CHAIN_ID);
        changes[1] = addresses.getAddress("MOONWELL_VELO", OPTIMISM_CHAIN_ID);
    }
}
