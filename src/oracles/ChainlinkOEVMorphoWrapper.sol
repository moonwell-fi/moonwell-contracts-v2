// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./AggregatorV3Interface.sol";
import {EIP20Interface} from "../EIP20Interface.sol";
import {IMorphoBlue} from "../morpho/IMorphoBlue.sol";
import {MarketParams} from "../morpho/IMetaMorpho.sol";
import {IMorphoChainlinkOracleV2} from "../morpho/IMorphoChainlinkOracleV2.sol";
import {IChainlinkOracle} from "../interfaces/IChainlinkOracle.sol";

/**
 * @title ChainlinkOEVMorphoWrapper
 * @notice A wrapper for Chainlink price feeds that allows early updates for liquidation
 * @dev This contract implements the AggregatorV3Interface and adds OEV (Oracle Extractable Value) functionality
 */
contract ChainlinkOEVMorphoWrapper is
    Initializable,
    OwnableUpgradeable,
    AggregatorV3Interface
{
    using SafeERC20 for IERC20;

    /// @notice The maximum basis points for the fee multiplier
    uint16 public constant MAX_BPS = 10000;

    /// @notice Price mantissa decimals (used by ChainlinkOracle)
    uint8 private constant PRICE_MANTISSA_DECIMALS = 18;

    /// @notice The Chainlink price feed this proxy forwards to
    AggregatorV3Interface public priceFeed;

    /// @notice The ChainlinkOracle contract.
    /// @dev Vestigial after the loan-feed source moved to
    ///      MorphoChainlinkOracleV2.QUOTE_FEED_1. Storage slot retained for
    ///      layout compatibility with prior implementations.
    IChainlinkOracle public chainlinkOracle;

    /// @notice The Morpho Blue contract address
    IMorphoBlue public morphoBlue;

    /// @notice The address that will receive the OEV fees
    address public feeRecipient;

    /// @notice The fee multiplier (in bps) for the OEV fees, to be paid to the liquidator
    uint16 public liquidatorFeeBps;

    /// @notice The last cached round id
    uint256 public cachedRoundId;

    /// @notice The max round delay (seconds)
    uint256 public maxRoundDelay;

    /// @notice The max decrements
    uint256 public maxDecrements;

    /// @notice Whether a Morpho market id is approved for early price updates and liquidations
    /// @dev Market id is `keccak256(abi.encode(MarketParams))` — the canonical Morpho Blue id
    mapping(bytes32 => bool) public approvedMarkets;

    /// @notice Manual reentrancy guard status. 0 = uninitialized / not entered,
    ///         1 = not entered (post first call), 2 = entered.
    /// @dev Implemented inline rather than via `ReentrancyGuardUpgradeable`
    ///      to avoid shifting all existing storage slots — inheriting that
    ///      parent would prepend 50 slots and break the upgradeable layout.
    uint256 private _reentrancyStatus;

    /// @notice Storage gap for future-proofing upgradeable storage layout.
    /// @dev Shrunk 50 → 49 (approvedMarkets) → 48 (_reentrancyStatus).
    uint256[48] private __gap;

    /// @notice Emitted when the fee recipient is changed
    event FeeRecipientChanged(address oldFeeRecipient, address newFeeRecipient);

    /// @notice Emitted when the liquidator fee bps is changed
    event LiquidatorFeeBpsChanged(
        uint16 oldLiquidatorFeeBps,
        uint16 newLiquidatorFeeBps
    );

    /// @notice Emitted when the max round delay is changed
    event MaxRoundDelayChanged(
        uint256 oldMaxRoundDelay,
        uint256 newMaxRoundDelay
    );

    /// @notice Emitted when the max decrements is changed
    event MaxDecrementsChanged(
        uint256 oldMaxDecrements,
        uint256 newMaxDecrements
    );

    /// @notice Emitted when a Morpho market is approved or unapproved for early liquidation
    event MarketApproved(bytes32 indexed id, bool approved);

    /// @notice Emitted when the price is updated early and liquidated
    event PriceUpdatedEarlyAndLiquidated(
        address indexed borrower,
        uint256 seizedAssets,
        uint256 repaidAssets,
        uint256 protocolFee,
        uint256 liquidatorFee
    );

    /// @notice Inline reentrancy guard. See `_reentrancyStatus` for the
    ///         rationale on avoiding `ReentrancyGuardUpgradeable` inheritance.
    modifier nonReentrant() {
        require(
            _reentrancyStatus != 2,
            "ChainlinkOEVMorphoWrapper: reentrant call"
        );
        _reentrancyStatus = 2;
        _;
        _reentrancyStatus = 1;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the proxy with a price feed address
     * @param _priceFeed Address of the Chainlink price feed to forward calls to
     * @param _owner Address that will own this contract
     * @param _morphoBlue Address of the Morpho Blue contract
     * @param _chainlinkOracle Address of the Chainlink oracle contract
     * @param _feeRecipient Address that will receive the OEV fees
     * @param _liquidatorFeeBps The liquidator fee in basis points
     * @param _maxRoundDelay The max round delay
     * @param _maxDecrements The max decrements
     * @custom:oz-upgrades-validate-as-initializer
     */
    function initializeV2(
        address _priceFeed,
        address _owner,
        address _morphoBlue,
        address _chainlinkOracle,
        address _feeRecipient,
        uint16 _liquidatorFeeBps,
        uint256 _maxRoundDelay,
        uint256 _maxDecrements
    ) public reinitializer(2) {
        require(
            _priceFeed != address(0),
            "ChainlinkOEVMorphoWrapper: price feed cannot be zero address"
        );
        require(
            _owner != address(0),
            "ChainlinkOEVMorphoWrapper: owner cannot be zero address"
        );
        require(
            _morphoBlue != address(0),
            "ChainlinkOEVMorphoWrapper: morpho blue cannot be zero address"
        );
        require(
            _chainlinkOracle != address(0),
            "ChainlinkOEVMorphoWrapper: chainlink oracle cannot be zero address"
        );
        require(
            _feeRecipient != address(0),
            "ChainlinkOEVMorphoWrapper: fee recipient cannot be zero address"
        );
        require(
            _liquidatorFeeBps <= MAX_BPS,
            "ChainlinkOEVMorphoWrapper: liquidatorFeeBps cannot be greater than MAX_BPS"
        );
        require(
            _maxRoundDelay > 0,
            "ChainlinkOEVMorphoWrapper: max round delay cannot be zero"
        );
        require(
            _maxDecrements > 0,
            "ChainlinkOEVMorphoWrapper: max decrements cannot be zero"
        );
        __Ownable_init();

        priceFeed = AggregatorV3Interface(_priceFeed);
        morphoBlue = IMorphoBlue(_morphoBlue);
        chainlinkOracle = IChainlinkOracle(_chainlinkOracle);
        feeRecipient = _feeRecipient;
        liquidatorFeeBps = _liquidatorFeeBps;
        cachedRoundId = priceFeed.latestRound();
        maxRoundDelay = _maxRoundDelay;
        maxDecrements = _maxDecrements;

        _transferOwnership(_owner);
    }

    /**
     * @notice Returns the number of decimals in the price feed
     * @return The number of decimals
     */
    function decimals() external view override returns (uint8) {
        return priceFeed.decimals();
    }

    /**
     * @notice Returns a description of the price feed
     * @return The description string
     */
    function description() external view override returns (string memory) {
        return priceFeed.description();
    }

    /**
     * @notice Returns the version number of the price feed
     * @return The version number
     */
    function version() external view override returns (uint256) {
        return priceFeed.version();
    }

    /**
     * @notice Returns data for a specific round
     * @param _roundId The round ID to retrieve data for
     * @return roundId The round ID
     * @return answer The price reported in this round
     * @return startedAt The timestamp when the round started
     * @return updatedAt The timestamp when the round was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = priceFeed
            .getRoundData(_roundId);
        _validateRoundData(roundId, answer, updatedAt, answeredInRound);
    }

    /**
     * @notice Returns data from the latest round, with OEV protection mechanism
     * @dev If the latest round hasn't been paid for (via updatePriceEarlyAndLiquidate) and is recent,
     *      this function will return data from a previous round instead
     * @return roundId The round ID
     * @return answer The latest price
     * @return startedAt The timestamp when the round started
     * @return updatedAt The timestamp when the round was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = priceFeed
            .latestRoundData();

        // The default behavior is to delay the price update unless someone has paid for the current round.
        // If the current round is not too old (maxRoundDelay seconds) and hasn't been paid for,
        // attempt to find the most recent valid round by checking previous rounds
        if (
            roundId != cachedRoundId &&
            block.timestamp < updatedAt + maxRoundDelay
        ) {
            // start from the previous round
            uint256 currentRoundId = roundId - 1;

            for (uint256 i = 0; i < maxDecrements && currentRoundId > 0; i++) {
                try priceFeed.getRoundData(uint80(currentRoundId)) returns (
                    uint80 r,
                    int256 a,
                    uint256 s,
                    uint256 u,
                    uint80 ar
                ) {
                    // previous round data found, update the round data
                    roundId = r;
                    answer = a;
                    startedAt = s;
                    updatedAt = u;
                    answeredInRound = ar;
                    break;
                } catch {
                    // previous round data not found, continue to the next decrement
                    currentRoundId--;
                }
            }
        }
        _validateRoundData(roundId, answer, updatedAt, answeredInRound);
    }

    /**
     * @notice Returns the latest round ID
     * @dev Falls back to extracting round ID from latestRoundData if latestRound() is not supported
     * @return The latest round ID
     */
    function latestRound() external view override returns (uint256) {
        try priceFeed.latestRound() returns (uint256 round) {
            return round;
        } catch {
            // Fallback: extract round ID from latestRoundData
            (uint80 roundId, , , , ) = priceFeed.latestRoundData();
            return uint256(roundId);
        }
    }

    /**
     * @notice Sets the fee recipient address
     * @param _feeRecipient The new fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(
            _feeRecipient != address(0),
            "ChainlinkOEVMorphoWrapper: fee recipient cannot be zero address"
        );

        address oldFeeRecipient = feeRecipient;
        feeRecipient = _feeRecipient;

        emit FeeRecipientChanged(oldFeeRecipient, _feeRecipient);
    }

    /**
     * @notice Sets the liquidator fee in basis points
     * @param _liquidatorFeeBps The new liquidator fee in basis points (must be <= MAX_BPS)
     */
    function setLiquidatorFeeBps(uint16 _liquidatorFeeBps) external onlyOwner {
        require(
            _liquidatorFeeBps <= MAX_BPS,
            "ChainlinkOEVMorphoWrapper: liquidatorFeeBps cannot be greater than MAX_BPS"
        );
        uint16 oldLiquidatorFeeBps = liquidatorFeeBps;
        liquidatorFeeBps = _liquidatorFeeBps;
        emit LiquidatorFeeBpsChanged(oldLiquidatorFeeBps, _liquidatorFeeBps);
    }

    /**
     * @notice Sets the max round delay in seconds
     * @param _maxRoundDelay The new max round delay (must be > 0)
     */
    function setMaxRoundDelay(uint256 _maxRoundDelay) external onlyOwner {
        require(
            _maxRoundDelay > 0,
            "ChainlinkOEVMorphoWrapper: max round delay cannot be zero"
        );
        uint256 oldMaxRoundDelay = maxRoundDelay;
        maxRoundDelay = _maxRoundDelay;
        emit MaxRoundDelayChanged(oldMaxRoundDelay, _maxRoundDelay);
    }

    /**
     * @notice Approve or unapprove a Morpho market for early price updates and liquidation
     * @dev Only approved markets may advance `cachedRoundId` via `updatePriceEarlyAndLiquidate`.
     *      This prevents an attacker from spinning up a permissionless dust market with this
     *      wrapper as base feed and using it to unlock the fresh price for free.
     * @param id The canonical Morpho Blue market id (`keccak256(abi.encode(MarketParams))`)
     * @param approved Whether the market is approved
     */
    function setApprovedMarket(bytes32 id, bool approved) external onlyOwner {
        require(
            approvedMarkets[id] != approved,
            "ChainlinkOEVMorphoWrapper: market approval unchanged"
        );
        approvedMarkets[id] = approved;
        emit MarketApproved(id, approved);
    }

    /**
     * @notice Sets the max number of decrements to search previous rounds
     * @param _maxDecrements The new max decrements (must be > 0)
     */
    function setMaxDecrements(uint256 _maxDecrements) external onlyOwner {
        require(
            _maxDecrements > 0,
            "ChainlinkOEVMorphoWrapper: max decrements cannot be zero"
        );
        uint256 oldMaxDecrements = maxDecrements;
        maxDecrements = _maxDecrements;
        emit MaxDecrementsChanged(oldMaxDecrements, _maxDecrements);
    }

    /// @notice Validate the round data from Chainlink
    /// @param roundId The round ID to validate
    /// @param answer The price to validate
    /// @param updatedAt The timestamp when the round was updated
    /// @param answeredInRound The round ID in which the answer was computed
    function _validateRoundData(
        uint80 roundId,
        int256 answer,
        uint256 updatedAt,
        uint80 answeredInRound
    ) internal pure {
        require(answer > 0, "Chainlink price cannot be lower or equal to 0");
        require(updatedAt != 0, "Round is in incompleted state");
        require(answeredInRound >= roundId, "Stale price");
    }

    /**
     * @notice Updates the cached round ID to allow early access to the latest price and executes a liquidation
     * @dev This function collects a fee from the caller, updates the cached price, and performs the liquidation on Morpho Blue
     * @dev The actual repayment amount is calculated by Morpho based on seizedAssets, oracle price, and liquidation incentive
     * @param marketParams The Morpho market parameters identifying the market
     * @param borrower The address of the borrower to liquidate
     * @param seizedAssets The amount of collateral assets to seize from the borrower
     * @param maxRepayAmount The maximum amount of loan tokens the liquidator is willing to repay (slippage protection)
     */
    function updatePriceEarlyAndLiquidate(
        MarketParams memory marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 maxRepayAmount
    ) external nonReentrant {
        // ensure the borrower is not the zero address
        require(
            borrower != address(0),
            "ChainlinkOEVMorphoWrapper: borrower cannot be zero address"
        );

        // ensure the seized assets is greater than zero
        require(
            seizedAssets > 0,
            "ChainlinkOEVMorphoWrapper: seized assets cannot be zero"
        );

        // ensure max repay amount is greater than zero
        require(
            maxRepayAmount > 0,
            "ChainlinkOEVMorphoWrapper: max repay amount cannot be zero"
        );

        // gate: only approved markets may advance cachedRoundId. Without this an attacker
        // could create a permissionless Morpho market + oracle pointing at this wrapper,
        // self-liquidate a dust position, unlock the fresh price for shared consumers, and
        // then liquidate real positions through Morpho Blue's native `liquidate()` at zero
        // OEV cost. (C4 #195)
        require(
            approvedMarkets[keccak256(abi.encode(marketParams))],
            "ChainlinkOEVMorphoWrapper: market not approved"
        );

        require(
            address(
                IMorphoChainlinkOracleV2(marketParams.oracle).BASE_FEED_1()
            ) == address(this),
            "ChainlinkOEVMorphoWrapper: oracle must be the same as the base feed 1"
        );

        // get the latest round data and update cached round id
        int256 collateralAnswer;
        // snapshot so the fresh-round unlock is scoped to this nested liquidation, not persisted globally.
        uint256 previousCachedRoundId = cachedRoundId;
        {
            (
                uint80 roundId,
                int256 answer,
                ,
                uint256 updatedAt,
                uint80 answeredInRound
            ) = priceFeed.latestRoundData();

            // validate the round data
            _validateRoundData(roundId, answer, updatedAt, answeredInRound);

            // update the cached round id
            cachedRoundId = roundId;
            collateralAnswer = answer;
        }

        // Execute liquidation
        uint256 actualSeizedAssets;
        uint256 actualRepaidAssets;
        {
            EIP20Interface loanToken = EIP20Interface(marketParams.loanToken);

            // Morpho will pull the actual amount needed, and we'll return any excess
            IERC20(address(loanToken)).safeTransferFrom(
                msg.sender,
                address(this),
                maxRepayAmount
            );

            IERC20(address(loanToken)).forceApprove(
                address(morphoBlue),
                maxRepayAmount
            );
            (actualSeizedAssets, actualRepaidAssets) = morphoBlue.liquidate(
                marketParams,
                borrower,
                seizedAssets,
                0,
                ""
            );
            // restore before the refund below (which yields control to the loan token), so the fresh round is not globally unlocked.
            cachedRoundId = previousCachedRoundId;
            // HAL-08: zero out the residual allowance so a future caller can't
            // skip a fresh approval for the leftover (maxRepay - actualRepaid).
            IERC20(address(loanToken)).forceApprove(address(morphoBlue), 0);

            require(
                actualRepaidAssets <= maxRepayAmount,
                "ChainlinkOEVMorphoWrapper: repaid amount exceeds maximum"
            );

            // HAL-03: return excess via safeTransfer so void-return tokens
            // (e.g. USDT-class) on permissionless Morpho markets don't brick
            // the refund path.
            uint256 excessLoanTokens = maxRepayAmount - actualRepaidAssets;
            if (excessLoanTokens > 0) {
                IERC20(address(loanToken)).safeTransfer(
                    msg.sender,
                    excessLoanTokens
                );
            }
        }

        // Calculate the split of collateral between liquidator and protocol
        (
            uint256 liquidatorFee,
            uint256 protocolFee
        ) = _calculateCollateralSplit(
                actualRepaidAssets,
                collateralAnswer,
                actualSeizedAssets,
                marketParams
            );

        // HAL-03/05: use safeTransfer for collateral distribution too, so
        // void-return tokens (e.g. USDT-class) joining a permissionless
        // Morpho market as collateral don't brick the fee-split path.
        IERC20(marketParams.collateralToken).safeTransfer(
            msg.sender,
            liquidatorFee
        );
        IERC20(marketParams.collateralToken).safeTransfer(
            feeRecipient,
            protocolFee
        );

        emit PriceUpdatedEarlyAndLiquidated(
            borrower,
            actualSeizedAssets,
            actualRepaidAssets,
            protocolFee,
            liquidatorFee
        );
    }

    /// @notice Get the loan token price from the Morpho market's per-market
    ///         oracle, sourced directly from QUOTE_FEED_1.
    /// @dev By Morpho's convention, QUOTE_FEED_1 is the raw Chainlink
    ///      aggregator for the quote (loan) asset of the market — it is not
    ///      OEV-wrapped, so no dereferencing is needed. Reads it directly,
    ///      runs full Chainlink staleness validation via _validateRoundData,
    ///      and scales to 1e18 with loan-token decimal adjustment.
    /// @param marketParams The Morpho market parameters (loanToken + oracle)
    /// @return The price scaled to 1e18 and adjusted for loan token decimals
    function _getLoanTokenPrice(
        MarketParams memory marketParams
    ) internal view returns (uint256) {
        AggregatorV3Interface loanFeed = IMorphoChainlinkOracleV2(
            marketParams.oracle
        ).QUOTE_FEED_1();
        require(
            address(loanFeed) != address(0),
            "ChainlinkOEVMorphoWrapper: loan feed not set"
        );
        require(
            address(
                IMorphoChainlinkOracleV2(marketParams.oracle).QUOTE_FEED_2()
            ) == address(0),
            "ChainlinkOEVMorphoWrapper: chained quote feeds unsupported"
        );
        require(
            address(
                IMorphoChainlinkOracleV2(marketParams.oracle).BASE_FEED_2()
            ) == address(0),
            "ChainlinkOEVMorphoWrapper: chained base feeds unsupported"
        );

        int256 loanAnswer;
        {
            (
                uint80 roundId,
                int256 answer,
                ,
                uint256 updatedAt,
                uint80 answeredInRound
            ) = loanFeed.latestRoundData();

            _validateRoundData(roundId, answer, updatedAt, answeredInRound);

            loanAnswer = answer;
        }

        uint8 feedDecimals = loanFeed.decimals();
        uint256 loanPricePerUnit = uint256(loanAnswer);
        if (feedDecimals < 18) {
            loanPricePerUnit = loanPricePerUnit * (10 ** (18 - feedDecimals));
        } else if (feedDecimals > 18) {
            loanPricePerUnit = loanPricePerUnit / (10 ** (feedDecimals - 18));
        }

        uint8 tokenDecimals = EIP20Interface(marketParams.loanToken).decimals();
        if (tokenDecimals < 18) {
            return loanPricePerUnit * (10 ** (18 - tokenDecimals));
        } else if (tokenDecimals > 18) {
            return loanPricePerUnit / (10 ** (tokenDecimals - 18));
        }
        return loanPricePerUnit;
    }

    /// @notice Calculate the fully adjusted collateral token price
    /// @dev Scales Chainlink feed decimals to 18, then adjusts for token decimals
    /// @param collateralAnswer The raw price from Chainlink
    /// @param underlyingCollateral The collateral token interface
    /// @return The price scaled to 1e18 and adjusted for token decimals
    function _getCollateralTokenPrice(
        int256 collateralAnswer,
        EIP20Interface underlyingCollateral
    ) private view returns (uint256) {
        uint8 feedDecimals = priceFeed.decimals();
        uint256 collateralPricePerUnit = uint256(collateralAnswer);

        // Scale price feed decimals to 18
        if (feedDecimals < 18) {
            collateralPricePerUnit =
                collateralPricePerUnit *
                (10 ** (18 - feedDecimals));
        } else if (feedDecimals > 18) {
            collateralPricePerUnit =
                collateralPricePerUnit /
                (10 ** (feedDecimals - 18));
        }

        // Adjust for token decimals
        uint8 tokenDecimals = underlyingCollateral.decimals();
        if (tokenDecimals < 18) {
            return collateralPricePerUnit * (10 ** (18 - tokenDecimals));
        } else if (tokenDecimals > 18) {
            return collateralPricePerUnit / (10 ** (tokenDecimals - 18));
        }
        return collateralPricePerUnit;
    }

    /// @notice Calculate the split of seized collateral between liquidator and fee recipient
    /// @param repayAmount The amount of loan tokens being repaid
    /// @param collateralAnswer The raw price from Chainlink for the collateral
    /// @param collateralReceived The amount of collateral tokens seized
    /// @param marketParams The Morpho market parameters
    /// @return liquidatorFee The amount of collateral to send to the liquidator (repayment + bonus)
    /// @return protocolFee The amount of collateral to send to the fee recipient (remainder)
    function _calculateCollateralSplit(
        uint256 repayAmount,
        int256 collateralAnswer,
        uint256 collateralReceived,
        MarketParams memory marketParams
    ) internal view returns (uint256 liquidatorFee, uint256 protocolFee) {
        uint256 loanTokenPrice = _getLoanTokenPrice(marketParams);
        uint256 collateralTokenPrice = _getCollateralTokenPrice(
            collateralAnswer,
            EIP20Interface(marketParams.collateralToken)
        );

        uint256 usdNormalizer = 10 ** PRICE_MANTISSA_DECIMALS; // 1e18
        uint256 repayUSD = (repayAmount * loanTokenPrice) / usdNormalizer;
        uint256 collateralUSD = (collateralReceived * collateralTokenPrice) /
            usdNormalizer;

        // If collateral is worth less than repayment, liquidator gets all collateral
        if (collateralUSD <= repayUSD) {
            liquidatorFee = collateralReceived;
            protocolFee = 0;
            return (liquidatorFee, protocolFee);
        }

        // Liquidator gets the repayment amount + bonus (remainder * liquidatorFeeBps)
        uint256 liquidatorUSD = repayUSD +
            ((collateralUSD - repayUSD) * uint256(liquidatorFeeBps)) /
            MAX_BPS;

        // Convert back to collateral token amount
        liquidatorFee = (liquidatorUSD * usdNormalizer) / collateralTokenPrice;

        protocolFee = collateralReceived - liquidatorFee;
    }
}
