// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Vm} from "@forge-std/Vm.sol";
import {console} from "@forge-std/console.sol";

import {MToken} from "@protocol/MToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {PriceOracle} from "@protocol/oracles/PriceOracle.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// @notice Snapshots every listed market's oracle price before proposal
/// simulation and reports the markets whose price moved afterwards.
/// Guards against re-wiring a feed to the wrong unit: MIP-X43 priced cbETH at
/// the cbETH/ETH ratio (1.12) instead of USD (2,200) and nothing in CI noticed.
contract MarketPriceGuard {
    Vm internal constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Violation {
        uint256 chainId;
        address mToken;
        string symbol;
        uint256 priceBefore;
        uint256 priceAfter;
    }

    /// @notice max relative move allowed between snapshot and check, 1e18 = 100%.
    /// Fork prices are static; the slack only absorbs an OEV wrapper switching
    /// from the delayed round to the latest one across the governance warp.
    uint256 public constant MAX_DRIFT = 0.01e18;

    mapping(uint256 => address[]) internal _markets;
    mapping(uint256 => mapping(address => uint256)) internal _priceBefore;
    mapping(uint256 => uint256) internal _snapshotTimestamp;
    mapping(uint256 => bool) public snapshotTaken;

    /// @notice record the price of every listed market on `forkId`.
    /// Forks without a Comptroller, or whose RPC placeholder is empty, are skipped.
    function snapshot(Addresses addresses, uint256 forkId) external {
        vm.selectFork(forkId);
        delete _markets[forkId];
        snapshotTaken[forkId] = false;

        if (!addresses.isAddressSet("UNITROLLER")) {
            return;
        }

        Comptroller comptroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );
        // placeholder fork (RPC unavailable): typed calls revert in the caller, uncaught by try/catch
        if (address(comptroller).code.length == 0) {
            return;
        }
        MToken[] memory markets;
        try comptroller.getAllMarkets() returns (MToken[] memory m) {
            markets = m;
        } catch {
            return;
        }

        PriceOracle oracle = comptroller.oracle();
        _snapshotTimestamp[forkId] = block.timestamp;

        for (uint256 i = 0; i < markets.length; i++) {
            uint256 price = _readPrice(oracle, markets[i]);
            // unpriced markets (deprecated, external oracle unavailable on fork) are not guarded
            if (price == 0) {
                continue;
            }
            _markets[forkId].push(address(markets[i]));
            _priceBefore[forkId][address(markets[i])] = price;
        }

        snapshotTaken[forkId] = true;
    }

    /// @notice compare every snapshotted market against its current price.
    /// @param allowlist mTokens whose price is expected to change; never reported.
    function check(
        Addresses addresses,
        uint256 forkId,
        address[] memory allowlist
    ) external returns (Violation[] memory violations) {
        if (!snapshotTaken[forkId]) {
            return violations;
        }

        vm.selectFork(forkId);
        // re-read through the Comptroller so an oracle swap is checked too
        PriceOracle oracle = Comptroller(addresses.getAddress("UNITROLLER"))
            .oracle();

        address[] memory markets = _markets[forkId];
        Violation[] memory buffer = new Violation[](markets.length);
        uint256 count;

        for (uint256 i = 0; i < markets.length; i++) {
            if (_contains(allowlist, markets[i])) {
                continue;
            }

            uint256 before = _priceBefore[forkId][markets[i]];
            uint256 after_ = _readPrice(oracle, MToken(markets[i]));
            if (after_ == 0) {
                // oracles with a staleness bound revert after the governance
                // warp; re-read at the snapshot time to tell stale from broken
                uint256 now_ = block.timestamp;
                vm.warp(_snapshotTimestamp[forkId]);
                after_ = _readPrice(oracle, MToken(markets[i]));
                vm.warp(now_);
            }

            if (!_withinDrift(before, after_)) {
                buffer[count++] = Violation({
                    chainId: block.chainid,
                    mToken: markets[i],
                    symbol: MToken(markets[i]).symbol(),
                    priceBefore: before,
                    priceAfter: after_
                });
            }
        }

        violations = new Violation[](count);
        for (uint256 i = 0; i < count; i++) {
            violations[i] = buffer[i];
        }
    }

    /// @notice log every violation and return a one-line summary for require().
    function describe(
        Violation[] memory violations
    ) external view returns (string memory summary) {
        for (uint256 i = 0; i < violations.length; i++) {
            console.log(
                "MarketPriceGuard: %s on chain %s moved",
                violations[i].symbol,
                violations[i].chainId
            );
            console.log(
                "  before %s after %s",
                violations[i].priceBefore,
                violations[i].priceAfter
            );
        }
        if (violations.length == 0) {
            return "";
        }
        return
            string.concat(
                "MarketPriceGuard: ",
                vm.toString(violations.length),
                " market price(s) changed across proposal simulation, first: ",
                violations[0].symbol,
                " on chain ",
                vm.toString(violations[0].chainId),
                ". Declare intentional changes via Proposal.expectedPriceChanges()"
            );
    }

    function _readPrice(
        PriceOracle oracle,
        MToken mToken
    ) internal view returns (uint256) {
        try oracle.getUnderlyingPrice(mToken) returns (uint256 price) {
            return price;
        } catch {
            return 0;
        }
    }

    function _withinDrift(
        uint256 before,
        uint256 after_
    ) internal pure returns (bool) {
        if (after_ == 0) {
            return false;
        }
        uint256 diff = before > after_ ? before - after_ : after_ - before;
        return (diff * 1e18) / before <= MAX_DRIFT;
    }

    function _contains(
        address[] memory list,
        address item
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == item) {
                return true;
            }
        }
        return false;
    }
}
