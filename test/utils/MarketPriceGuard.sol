// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Vm} from "@forge-std/Vm.sol";
import {console} from "@forge-std/console.sol";

import {MToken} from "@protocol/MToken.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {EIP20Interface} from "@protocol/EIP20Interface.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {PriceOracle} from "@protocol/oracles/PriceOracle.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Proposal} from "@proposals/Proposal.sol";

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
        string reason;
    }

    /// @notice max relative move allowed between snapshot and check, 1e18 = 100%.
    /// Fork prices are static; the slack only absorbs an OEV wrapper switching
    /// from the delayed round to the latest one across the governance warp.
    uint256 public constant MAX_DRIFT = 0.01e18;

    mapping(uint256 => address[]) internal _markets;
    mapping(uint256 => mapping(address => uint256)) internal _priceBefore;
    mapping(uint256 => mapping(address => bool)) internal _listedAtSnapshot;
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
            _listedAtSnapshot[forkId][address(markets[i])] = true;
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

    /// @notice compare every snapshotted market against its current price, and
    /// sanity-check markets listed after the snapshot (no baseline to compare).
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
        MToken[] memory listed = Comptroller(addresses.getAddress("UNITROLLER"))
            .getAllMarkets();
        Violation[] memory buffer = new Violation[](
            markets.length + listed.length
        );
        uint256 count;

        for (uint256 i = 0; i < markets.length; i++) {
            if (_contains(allowlist, markets[i])) {
                continue;
            }

            uint256 before = _priceBefore[forkId][markets[i]];
            uint256 after_ = _readPrice(oracle, MToken(markets[i]));
            if (!_withinDrift(before, after_)) {
                // round selection is time-dependent (OEV wrappers return the
                // delayed round while the latest is under maxRoundDelay old,
                // staleness bounds revert after the governance warp); re-read
                // at the snapshot time so only a real feed change is reported
                uint256 now_ = block.timestamp;
                vm.warp(_snapshotTimestamp[forkId]);
                uint256 atSnapshot = _readPrice(oracle, MToken(markets[i]));
                vm.warp(now_);
                if (_withinDrift(before, atSnapshot)) {
                    continue;
                }
                if (after_ == 0) {
                    after_ = atSnapshot;
                }
            }

            if (!_withinDrift(before, after_)) {
                buffer[count++] = Violation({
                    chainId: block.chainid,
                    mToken: markets[i],
                    symbol: MToken(markets[i]).symbol(),
                    priceBefore: before,
                    priceAfter: after_,
                    reason: "price moved"
                });
            }
        }

        for (uint256 i = 0; i < listed.length; i++) {
            address m = address(listed[i]);
            if (_listedAtSnapshot[forkId][m] || _contains(allowlist, m)) {
                continue;
            }
            (uint256 price, string memory problem) = _newMarketProblem(
                oracle,
                listed[i]
            );
            if (bytes(problem).length > 0) {
                buffer[count++] = Violation({
                    chainId: block.chainid,
                    mToken: m,
                    symbol: listed[i].symbol(),
                    priceBefore: 0,
                    priceAfter: price,
                    reason: problem
                });
            }
        }

        violations = new Violation[](count);
        for (uint256 i = 0; i < count; i++) {
            violations[i] = buffer[i];
        }
    }

    /// @notice a proposal's expectedPriceChanges(), resolved on its own primary
    /// fork. Raw staticcall: a MIP artifact compiled before the hook existed
    /// reverts with no data; fail closed (no declaration, no price may move).
    function declaredChanges(
        Addresses addresses,
        Proposal proposal
    ) external returns (address[] memory declared) {
        uint256 activeFork = vm.activeFork();
        try proposal.primaryForkId() returns (uint256 primaryFork) {
            vm.selectFork(primaryFork);
        } catch {
            return declared;
        }

        (bool ok, bytes memory ret) = address(proposal).staticcall(
            abi.encodeWithSelector(
                Proposal.expectedPriceChanges.selector,
                addresses
            )
        );
        if (ok && ret.length > 0) {
            declared = abi.decode(ret, (address[]));
        }

        vm.selectFork(activeFork);
    }

    /// @notice log every violation and return a one-line summary for require().
    function describe(
        Violation[] memory violations
    ) external view returns (string memory summary) {
        for (uint256 i = 0; i < violations.length; i++) {
            console.log(
                "MarketPriceGuard: %s on chain %s: %s",
                violations[i].symbol,
                violations[i].chainId,
                violations[i].reason
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

    /// @notice a new listing must be priced, and a Chainlink feed that names
    /// its pair must quote USD (MIP-X43 wired the cbETH / ETH ratio feed)
    function _newMarketProblem(
        PriceOracle oracle,
        MToken mToken
    ) internal view returns (uint256 price, string memory problem) {
        price = _readPrice(oracle, mToken);
        if (price == 0) {
            return (price, "new market is unpriced");
        }

        address underlying;
        try MErc20(address(mToken)).underlying() returns (address u) {
            underlying = u;
        } catch {
            return (price, "");
        }

        // a direct price override bypasses the feed
        (bool ok, bytes memory ret) = address(oracle).staticcall(
            abi.encodeWithSignature("assetPrices(address)", underlying)
        );
        if (ok && ret.length == 32 && abi.decode(ret, (uint256)) != 0) {
            return (price, "");
        }

        (ok, ret) = address(oracle).staticcall(
            abi.encodeWithSignature(
                "getFeed(string)",
                EIP20Interface(underlying).symbol()
            )
        );
        if (!ok || ret.length != 32) {
            return (price, "");
        }
        address feed = abi.decode(ret, (address));
        if (feed.code.length == 0) {
            return (price, "");
        }

        // composite oracles carry no pair in their description; unchecked
        (ok, ret) = feed.staticcall(abi.encodeWithSignature("description()"));
        if (!ok || ret.length == 0) {
            return (price, "");
        }
        string memory pair = abi.decode(ret, (string));
        if (
            bytes(pair).length > 0 &&
            vm.indexOf(pair, "/ USD") == type(uint256).max
        ) {
            problem = string.concat(
                "new market feed is not USD-quoted: ",
                pair
            );
        }
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
