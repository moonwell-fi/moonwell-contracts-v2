// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

/// Chainlink Data Streams v10 (Tokenized-asset) report, ABI order. The
/// collateral USD price is the "Theoretical Price" = `price * currentMultiplier`
/// (continuity-preserving across corporate actions, per Chainlink docs).
struct ReportV10 {
    bytes32 feedId;
    uint32 validFromTimestamp;
    uint32 observationsTimestamp;
    uint192 nativeFee;
    uint192 linkFee;
    uint32 expiresAt;
    uint64 lastUpdateTimestamp;
    int192 price; // underlying equity consensus mid price
    uint32 marketStatus; // 0 Unknown, 1 Closed, 2 Open
    int192 currentMultiplier; // shares per tokenized asset (1e18 ratio)
    int192 newMultiplier;
    uint32 activationDateTime;
    int192 tokenizedPrice;
}

struct DSAsset {
    address assetAddress;
    uint256 amount;
}

interface IVerifierProxy {
    function verify(
        bytes calldata payload,
        bytes calldata parameterPayload
    ) external payable returns (bytes memory verifierResponse);

    function s_feeManager() external view returns (address);
}

interface IDSFeeManager {
    function getFeeAndReward(
        address subscriber,
        bytes memory report,
        address quoteAddress
    ) external returns (DSAsset memory, DSAsset memory, uint256);

    function i_linkAddress() external view returns (address);

    function i_rewardManager() external view returns (address);
}

/// Caches the latest verified Chainlink Data Streams v10 price behind
/// `AggregatorV3Interface` so a `view` consumer (the Credit Marketplace's
/// `PriceLib.valueToUsd1e18`) can read a pull-based feed.
///
/// Data Streams are pull-based: a DON-signed report is fetched off-chain and
/// `verify()`-ed on-chain. A permissioned keeper pushes verified reports via
/// `verifyAndUpdate`; the cached value is exposed through the AggregatorV3
/// facade. `decimals()` is set at construction (Data Streams price scale is
/// per-stream — 8 or 18) and the stored answer is the Theoretical Price
/// (`price * currentMultiplier / 1e18`), which carries the `price` scale.
///
/// Operational SLA (off-chain, not enforced here): the keeper must push a fresh
/// report at least once per the consumer's configured staleness window, while
/// `marketStatus == Open`.
contract DataStreamsAggregatorAdapter is AggregatorV3Interface {
    using SafeERC20 for IERC20;

    error OnlyOwner();
    error OnlyKeeper();
    error ZeroAddress();
    error AlreadyBootstrapped();
    error NotInitialized();
    error WrongFeed(bytes32 got, bytes32 expected);
    error ReportExpired(uint32 expiresAt);
    error StaleReport(uint32 incomingObsTs, uint64 storedObsTs);
    error MarketClosed(uint32 marketStatus);
    error InvalidPrice(int192 price);
    error InvalidMultiplier(int192 multiplier);

    event PriceUpdated(
        int256 answer,
        uint32 observationsTimestamp,
        uint80 roundId
    );
    event Bootstrapped(int256 answer);
    event KeeperUpdated(address indexed previous, address indexed updated);
    event OwnerUpdated(address indexed previous, address indexed updated);

    /// Data Streams v10 `currentMultiplier` is a 1e18 fixed-point ratio.
    int256 internal constant MULTIPLIER_SCALE = 1e18;
    /// v10 `marketStatus`: 0 Unknown, 1 Closed, 2 Open.
    uint32 internal constant MARKET_STATUS_OPEN = 2;

    IVerifierProxy public immutable verifierProxy;
    bytes32 public immutable feedId;
    uint8 private immutable i_decimals;

    address public owner;
    address public keeper;

    int256 private _answer;
    uint256 private _lastUpdatedAt;
    uint64 private _latestObservationsTs;
    uint80 private _roundId;
    bool private _initialized;

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyKeeper() {
        if (msg.sender != keeper) revert OnlyKeeper();
        _;
    }

    constructor(
        IVerifierProxy _verifierProxy,
        bytes32 _feedId,
        uint8 _decimals,
        address _owner,
        address _keeper
    ) {
        if (address(_verifierProxy) == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        if (_keeper == address(0)) revert ZeroAddress();
        verifierProxy = _verifierProxy;
        feedId = _feedId;
        i_decimals = _decimals;
        owner = _owner;
        keeper = _keeper;
    }

    // ─── keeper / owner write paths ──────────────────────────────────────

    /// Verify a DON-signed v10 report and cache its Theoretical Price.
    /// `fullReport` is the full Streams Direct payload (decodes as
    /// `(bytes32[3], bytes, …)`). Permissioned to the keeper.
    function verifyAndUpdate(bytes calldata fullReport) external onlyKeeper {
        (, bytes memory reportData) = abi.decode(fullReport, (bytes32[3], bytes));
        bytes memory params = _feeParams(reportData);

        bytes memory verified = verifierProxy.verify(fullReport, params);
        ReportV10 memory r = abi.decode(verified, (ReportV10));

        // Pin the exact feed: feedId encodes the schema version (0x000a => v10),
        // so this also guarantees the decode matched the right schema.
        if (r.feedId != feedId) revert WrongFeed(r.feedId, feedId);
        if (r.expiresAt < block.timestamp) revert ReportExpired(r.expiresAt);
        if (r.observationsTimestamp <= _latestObservationsTs) {
            revert StaleReport(r.observationsTimestamp, _latestObservationsTs);
        }
        if (r.marketStatus != MARKET_STATUS_OPEN) {
            revert MarketClosed(r.marketStatus);
        }
        if (r.price <= 0) revert InvalidPrice(r.price);
        if (r.currentMultiplier <= 0) {
            revert InvalidMultiplier(r.currentMultiplier);
        }

        // Theoretical Price = price * currentMultiplier (continuity-preserving
        // across corporate actions). currentMultiplier is a 1e18 ratio, so the
        // result carries the stream's `price` decimals (== this adapter's
        // `decimals()`).
        int256 theoretical = (int256(r.price) * int256(r.currentMultiplier)) /
            MULTIPLIER_SCALE;

        _answer = theoretical;
        _latestObservationsTs = r.observationsTimestamp;
        _lastUpdatedAt = r.observationsTimestamp;
        _roundId += 1;
        _initialized = true;
        emit PriceUpdated(theoretical, r.observationsTimestamp, _roundId);
    }

    /// One-shot owner seed so `whitelistCollateralToken`'s `_probeFeed`
    /// (answer > 0 + fresh) passes before the first real report. Leaves
    /// `_latestObservationsTs = 0` so the first `verifyAndUpdate` overwrites it.
    function bootstrap(int256 seedAnswer) external onlyOwner {
        if (_initialized) revert AlreadyBootstrapped();
        if (seedAnswer <= 0) revert InvalidPrice(int192(seedAnswer));
        _answer = seedAnswer;
        _lastUpdatedAt = block.timestamp;
        _roundId += 1;
        _initialized = true;
        emit Bootstrapped(seedAnswer);
    }

    /// Data Streams fee handling: `s_feeManager() == address(0)` means
    /// off-chain billing (empty parameterPayload); otherwise quote the fee and
    /// pre-approve the reward manager to pull it (LINK must be funded).
    function _feeParams(
        bytes memory reportData
    ) private returns (bytes memory) {
        address fm = verifierProxy.s_feeManager();
        if (fm == address(0)) return bytes("");
        IDSFeeManager feeManager = IDSFeeManager(fm);
        address feeToken = feeManager.i_linkAddress();
        (DSAsset memory fee, , ) = feeManager.getFeeAndReward(
            address(this),
            reportData,
            feeToken
        );
        IERC20(feeToken).safeIncreaseAllowance(
            feeManager.i_rewardManager(),
            fee.amount
        );
        return abi.encode(feeToken);
    }

    // ─── ops ─────────────────────────────────────────────────────────────

    function setKeeper(address newKeeper) external onlyOwner {
        if (newKeeper == address(0)) revert ZeroAddress();
        emit KeeperUpdated(keeper, newKeeper);
        keeper = newKeeper;
    }

    function setOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnerUpdated(owner, newOwner);
        owner = newOwner;
    }

    function rescueErc20(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner, amount);
    }

    // ─── AggregatorV3Interface facade ─────────────────────────────────────

    function decimals() external view override returns (uint8) {
        return i_decimals;
    }

    function description() external pure override returns (string memory) {
        return "Chainlink Data Streams v10 (Tokenized-asset) cached adapter";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function latestRound() external view override returns (uint256) {
        return _roundId;
    }

    function getRoundData(
        uint80 _round
    )
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        if (_round != _roundId) revert NotInitialized();
        return _latestRound();
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return _latestRound();
    }

    function _latestRound()
        private
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        if (!_initialized) revert NotInitialized();
        return (_roundId, _answer, _lastUpdatedAt, _lastUpdatedAt, _roundId);
    }
}
