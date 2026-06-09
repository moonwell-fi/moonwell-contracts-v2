// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IVerifierProxy, ReportV10} from "@protocol/oracles/DataStreamsAggregatorAdapter.sol";

/// Local/fork stub for the Chainlink Data Streams verifier proxy. Lets the
/// marketplace run end-to-end against a STATIC, settable COIN price without
/// Data Streams API credentials or a real DON-signed report — the one thing it
/// does NOT exercise is the DON signature check (Chainlink's, not ours).
///
/// `verify()` ignores its input and returns the stored v10 report. By default
/// it stamps `observationsTimestamp`/`expiresAt` from `block.timestamp`
/// (`marketStatus = Open`, `expiresAt = now + 1h`). Setters move the price /
/// market status / multiplier for demo scenarios (e.g. crash COIN to trigger
/// the default path). `setTimestamps` forces exact obs/expiry values so tests
/// can exercise the adapter's expiry + monotonic gates.
///
/// `s_feeManager()` returns `address(0)` → the adapter takes the off-chain
/// billing path (empty parameterPayload, no LINK), so no funding is needed.
contract MockDataStreamsVerifierV10 is IVerifierProxy {
    ReportV10 internal _report;

    bool internal _useStaticTimestamps;
    uint32 internal _staticObsTs;
    uint32 internal _staticExpiresAt;

    constructor(bytes32 _feedId, int192 _price, int192 _multiplier) {
        _report.feedId = _feedId;
        _report.price = _price;
        _report.currentMultiplier = _multiplier;
        _report.marketStatus = 2; // Open
    }

    function s_feeManager() external pure override returns (address) {
        return address(0);
    }

    function verify(
        bytes calldata,
        bytes calldata
    ) external payable override returns (bytes memory) {
        ReportV10 memory r = _report;
        if (_useStaticTimestamps) {
            r.observationsTimestamp = _staticObsTs;
            r.expiresAt = _staticExpiresAt;
            r.validFromTimestamp = _staticObsTs;
            r.lastUpdateTimestamp = _staticObsTs;
        } else {
            r.observationsTimestamp = uint32(block.timestamp);
            r.expiresAt = uint32(block.timestamp + 1 hours);
            r.validFromTimestamp = uint32(block.timestamp);
            r.lastUpdateTimestamp = uint64(block.timestamp);
        }
        return abi.encode(r);
    }

    // ─── demo / test knobs ────────────────────────────────────────────────

    function setPrice(int192 price) external {
        _report.price = price;
    }

    function setMultiplier(int192 multiplier) external {
        _report.currentMultiplier = multiplier;
    }

    function setMarketStatus(uint32 marketStatus) external {
        _report.marketStatus = marketStatus;
    }

    function setFeedId(bytes32 newFeedId) external {
        _report.feedId = newFeedId;
    }

    function setTokenizedPrice(int192 tokenizedPrice) external {
        _report.tokenizedPrice = tokenizedPrice;
    }

    /// Force exact obs/expiry timestamps (for the adapter's expiry + monotonic
    /// gate tests). `setBlockTimestamps()` reverts to block-derived stamps.
    function setTimestamps(uint32 obsTs, uint32 expiresAt) external {
        _useStaticTimestamps = true;
        _staticObsTs = obsTs;
        _staticExpiresAt = expiresAt;
    }

    function setBlockTimestamps() external {
        _useStaticTimestamps = false;
    }
}
