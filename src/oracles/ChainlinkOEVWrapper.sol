// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {MErc20Storage, MTokenInterface, MErc20Interface} from "../MTokenInterfaces.sol";
import {EIP20Interface} from "../EIP20Interface.sol";
import {IChainlinkOracle} from "../interfaces/IChainlinkOracle.sol";
import {IOEVWrapperFeed} from "./IOEVWrapperFeed.sol";

/**
 * @title ChainlinkOEVWrapper
 * @notice A wrapper for Chainlink price feeds that allows early updates for liquidation
 * @dev This contract implements the AggregatorV3Interface and adds OEV (Oracle Extractable Value) functionality
 */
contract ChainlinkOEVWrapper is
    Ownable,
    AggregatorV3Interface,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    /// @notice The maximum basis points for the fee multiplier
    uint16 public constant MAX_BPS = 10000;

    /// @notice Price mantissa decimals (used by ChainlinkOracle)
    uint8 private constant PRICE_MANTISSA_DECIMALS = 18;

    /// @notice The ChainlinkOracle contract
    IChainlinkOracle public immutable chainlinkOracle;

    /// @notice The Chainlink price feed this proxy forwards to
    AggregatorV3Interface public priceFeed;

    /// @notice The address that will receive the OEV fees
    address public feeRecipient;

    /// @notice The fee multiplier (in bps) for the OEV fees, to be paid to the liquidator
    uint16 public liquidatorFeeBps;

    /// @notice The last cached round id
    uint256 public cachedRoundId;

    /// @notice The max round delay
    uint256 public maxRoundDelay;

    /// @notice The max decrements
    uint256 public maxDecrements;

    /// @notice Emitted when the fee recipient is changed
    event FeeRecipientChanged(address oldFeeRecipient, address newFeeRecipient);

    /// @notice Emitted when the fee multiplier is changed
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

    /// @notice Emitted when the price is updated early and liquidated
    event PriceUpdatedEarlyAndLiquidated(
        address indexed borrower,
        uint256 repayAmount,
        address mTokenCollateral,
        address mTokenLoan,
        uint256 protocolFee,
        uint256 liquidatorFee
    );

    /// @notice Emitted when tokens are recovered from the contract
    event TokenRecovered(
        address indexed tokenAddress,
        address indexed to,
        uint256 amount
    );

    /**
     * @notice Contract constructor
     * @param _priceFeed Address of the Chainlink price feed to forward calls to
     * @param _owner Address that will own this contract
     * @param _liquidatorFeeBps The liquidator fee BPS for the OEV fees
     * @param _maxRoundDelay The max round delay
     * @param _maxDecrements The max decrements
     */
    constructor(
        address _priceFeed,
        address _owner,
        address _chainlinkOracle,
        address _feeRecipient,
        uint16 _liquidatorFeeBps,
        uint256 _maxRoundDelay,
        uint256 _maxDecrements
    ) {
        require(
            _priceFeed != address(0),
            "ChainlinkOEVWrapper: price feed cannot be zero address"
        );
        require(
            _owner != address(0),
            "ChainlinkOEVWrapper: owner cannot be zero address"
        );
        require(
            _liquidatorFeeBps <= MAX_BPS,
            "ChainlinkOEVWrapper: liquidator fee cannot be greater than MAX_BPS"
        );
        require(
            _maxRoundDelay > 0,
            "ChainlinkOEVWrapper: max round delay cannot be zero"
        );
        require(
            _maxDecrements > 0,
            "ChainlinkOEVWrapper: max decrements cannot be zero"
        );
        require(
            _chainlinkOracle != address(0),
            "ChainlinkOEVWrapper: chainlink oracle cannot be zero address"
        );
        require(
            _feeRecipient != address(0),
            "ChainlinkOEVWrapper: fee recipient cannot be zero address"
        );

        priceFeed = AggregatorV3Interface(_priceFeed);
        liquidatorFeeBps = _liquidatorFeeBps;
        cachedRoundId = priceFeed.latestRound();
        maxRoundDelay = _maxRoundDelay;
        maxDecrements = _maxDecrements;
        chainlinkOracle = IChainlinkOracle(_chainlinkOracle);
        feeRecipient = _feeRecipient;

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
     * @notice Sets the liquidator fee BPS for OEV fees
     * @param _liquidatorFeeBps The new liquidator fee in basis points (must be <= MAX_BPS)
     */
    function setLiquidatorFeeBps(uint16 _liquidatorFeeBps) external onlyOwner {
        require(
            _liquidatorFeeBps <= MAX_BPS,
            "ChainlinkOEVWrapper: liquidator fee cannot be greater than MAX_BPS"
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
            "ChainlinkOEVWrapper: max round delay cannot be zero"
        );
        uint256 oldMaxRoundDelay = maxRoundDelay;
        maxRoundDelay = _maxRoundDelay;
        emit MaxRoundDelayChanged(oldMaxRoundDelay, _maxRoundDelay);
    }

    /**
     * @notice Sets the max number of decrements to search previous rounds
     * @param _maxDecrements The new max decrements (must be > 0)
     */
    function setMaxDecrements(uint256 _maxDecrements) external onlyOwner {
        require(
            _maxDecrements > 0,
            "ChainlinkOEVWrapper: max decrements cannot be zero"
        );
        uint256 oldMaxDecrements = maxDecrements;
        maxDecrements = _maxDecrements;
        emit MaxDecrementsChanged(oldMaxDecrements, _maxDecrements);
    }

    /**
     * @notice Sets the fee recipient address
     * @param _feeRecipient The new fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(
            _feeRecipient != address(0),
            "ChainlinkOEVWrapper: fee recipient cannot be zero address"
        );

        address oldFeeRecipient = feeRecipient;
        feeRecipient = _feeRecipient;

        emit FeeRecipientChanged(oldFeeRecipient, _feeRecipient);
    }

    /**
     * @notice Recovers ERC20 tokens accidentally sent to this contract
     * @dev Only callable by the user who owns this strategy
     * @param tokenAddress The address of the token to recover
     * @param to The address to send the tokens to
     * @param amount The amount of tokens to recover
     */
    function recoverERC20(
        address tokenAddress,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(to != address(0), "Cannot send to zero address");
        require(amount > 0, "Amount must be greater than 0");

        IERC20(tokenAddress).safeTransfer(to, amount);

        emit TokenRecovered(tokenAddress, to, amount);
    }

    /**
     * @notice Recovers ETH accidentally sent to this contract
     * @dev Only callable by the user who owns this strategy
     * @param to The address to send the ETH to
     */
    function recoverETH(address payable to) external onlyOwner {
        require(to != address(0), "Cannot send to zero address");

        uint256 balance = address(this).balance;
        require(balance > 0, "Empty balance");

        (bool success, ) = to.call{value: balance}("");
        require(success, "Transfer failed");

        emit TokenRecovered(address(0), to, balance);
    }

    /**
     * @notice Allows the contract to receive ETH (needed for mWETH redemption which unwraps to ETH)
     */
    receive() external payable {}

    /**
     * @notice Updates the cached round ID to allow early access to the latest price and executes a liquidation
     * @dev This function collects a fee from the caller, updates the cached price, and performs the liquidation
     * @param borrower The address of the borrower to liquidate
     * @param repayAmount The amount to repay on behalf of the borrower
     * @param mTokenCollateral The mToken market for the collateral token
     * @param mTokenLoan The mToken market for the loan token, against which to liquidate
     */
    function updatePriceEarlyAndLiquidate(
        address borrower,
        uint256 repayAmount,
        address mTokenCollateral,
        address mTokenLoan
    ) external nonReentrant {
        // ensure the repay amount is greater than zero
        require(
            repayAmount > 0,
            "ChainlinkOEVWrapper: repay amount cannot be zero"
        );

        // ensure the borrower is not the zero address
        require(
            borrower != address(0),
            "ChainlinkOEVWrapper: borrower cannot be zero address"
        );

        // ensure the mToken is not the zero address
        require(
            mTokenCollateral != address(0),
            "ChainlinkOEVWrapper: mToken collateral cannot be zero address"
        );

        // ensure the mToken loan is not the zero address
        require(
            mTokenLoan != address(0),
            "ChainlinkOEVWrapper: mToken loan cannot be zero address"
        );

        // get the loan underlying token (the token being repaid)
        EIP20Interface underlyingLoan = EIP20Interface(
            MErc20Storage(mTokenLoan).underlying()
        );

        // get the collateral underlying token (the token being seized)
        EIP20Interface underlyingCollateral = EIP20Interface(
            MErc20Storage(mTokenCollateral).underlying()
        );

        MTokenInterface mTokenCollateralInterface = MTokenInterface(
            mTokenCollateral
        );

        require(
            address(chainlinkOracle.getFeed(underlyingCollateral.symbol())) ==
                address(this),
            "ChainlinkOEVWrapper: chainlink oracle feed does not match"
        );

        // transfer the loan token (to repay the borrow) from the liquidator to this contract
        IERC20(address(underlyingLoan)).safeTransferFrom(
            msg.sender,
            address(this),
            repayAmount
        );

        // get the latest round data and update cached round id
        int256 collateralAnswer;
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

        // execute liquidation
        uint256 collateralSeized = _executeLiquidation(
            borrower,
            repayAmount,
            mTokenCollateralInterface,
            mTokenLoan,
            underlyingLoan
        );

        require(
            collateralSeized > 0,
            "ChainlinkOEVWrapper: collateral seized cannot be zero"
        );

        // Calculate the split of collateral between liquidator and protocol
        (
            uint256 liquidatorFee,
            uint256 protocolFee
        ) = _calculateCollateralSplit(
                repayAmount,
                collateralAnswer,
                collateralSeized,
                underlyingLoan,
                mTokenCollateral,
                underlyingCollateral
            );

        // transfer the liquidator's payment (repayment + bonus) to the liquidator
        bool liquidatorSuccess = mTokenCollateralInterface.transfer(
            msg.sender,
            liquidatorFee
        );
        require(
            liquidatorSuccess,
            "ChainlinkOEVWrapper: liquidator fee transfer failed"
        );

        // transfer the remainder to the fee recipient
        bool protocolSuccess = mTokenCollateralInterface.transfer(
            feeRecipient,
            protocolFee
        );
        require(
            protocolSuccess,
            "ChainlinkOEVWrapper: protocol fee transfer failed"
        );

        emit PriceUpdatedEarlyAndLiquidated(
            borrower,
            repayAmount,
            mTokenCollateral,
            mTokenLoan,
            protocolFee,
            liquidatorFee
        );
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

    /// @notice Calculate the fully adjusted collateral token price
    /// @dev Scales Chainlink feed decimals to 18, then adjusts for token decimals
    /// @param collateralAnswer The raw price from Chainlink
    /// @param underlyingCollateral The collateral token interface
    /// @return The price scaled to 1e18 and adjusted for token decimals
    function _getCollateralTokenPrice(
        int256 collateralAnswer,
        EIP20Interface underlyingCollateral
    ) internal view returns (uint256) {
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

    /// @notice Execute liquidation
    /// @param borrower The address of the borrower to liquidate
    /// @param repayAmount The amount to repay on behalf of the borrower
    /// @param mTokenCollateral The mToken market for the collateral token
    /// @param _mTokenLoan The mToken market for the loan token
    /// @param underlyingLoan The underlying loan token interface
    /// @return collateralSeized The amount of mToken collateral seized
    function _executeLiquidation(
        address borrower,
        uint256 repayAmount,
        MTokenInterface mTokenCollateral,
        address _mTokenLoan,
        EIP20Interface underlyingLoan
    ) internal returns (uint256 collateralSeized) {
        uint256 mTokenCollateralBalanceBefore = mTokenCollateral.balanceOf(
            address(this)
        );
        // HAL-05: forceApprove tolerates non-standard ERC20s (USDT-class,
        // void-return approve) where the bare `approve` would silently fail.
        IERC20(address(underlyingLoan)).forceApprove(_mTokenLoan, repayAmount);
        require(
            MErc20Interface(_mTokenLoan).liquidateBorrow(
                borrower,
                repayAmount,
                mTokenCollateral
            ) == 0,
            "ChainlinkOEVWrapper: liquidation failed"
        );

        collateralSeized =
            mTokenCollateral.balanceOf(address(this)) -
            mTokenCollateralBalanceBefore;
    }

    /// @notice Resolve a feed registered in ChainlinkOracle down to its raw
    ///         Chainlink aggregator, single-hop.
    /// @dev If the registry feed is itself an OEV wrapper (exposes priceFeed()),
    ///      returns the inner aggregator. Otherwise returns the input unchanged.
    ///      Deliberately single-hop to avoid recursion and match the registry
    ///      invariant that entries are raw or a single level of wrapping.
    function _resolveRawFeed(
        AggregatorV3Interface registryFeed
    ) internal view returns (AggregatorV3Interface) {
        try IOEVWrapperFeed(address(registryFeed)).priceFeed() returns (
            AggregatorV3Interface inner
        ) {
            if (address(inner) != address(0)) {
                return inner;
            }
        } catch {
            // registry feed is a raw aggregator (no priceFeed() selector);
            // fall through and return the input.
        }
        return registryFeed;
    }

    /// @notice Get the loan token price from the raw underlying Chainlink feed.
    /// @dev Single-hop dereferences any OEV wrapper registered under the loan
    ///      token's symbol in ChainlinkOracle, so the split math reads from a
    ///      raw Chainlink aggregator. Mirrors the collateral side's freshness
    ///      guarantee (which reads from the wrapper's own `priceFeed` directly,
    ///      a raw aggregator by deployment convention).
    /// @param underlyingLoan The underlying loan token interface
    /// @return The price scaled to 1e18 and adjusted for token decimals
    function _getLoanTokenPrice(
        EIP20Interface underlyingLoan
    ) internal view returns (uint256) {
        AggregatorV3Interface registryFeed = chainlinkOracle.getFeed(
            underlyingLoan.symbol()
        );
        // Defense-in-depth: if the registry was misconfigured to point at an
        // EOA, the call inside _resolveRawFeed would revert with the
        // non-actionable "call to non-contract address" message (Solidity's
        // try/catch does not catch this revert in 0.8.19). Reject upfront
        // with a clear message. We re-check after resolve in case the
        // registry returns a wrapper whose inner priceFeed() points at an EOA.
        require(
            address(registryFeed).code.length > 0,
            "ChainlinkOEVWrapper: loan feed has no code"
        );
        AggregatorV3Interface loanFeed = _resolveRawFeed(registryFeed);
        require(
            address(loanFeed).code.length > 0,
            "ChainlinkOEVWrapper: loan feed has no code"
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

        // Scale feed decimals to 18 using the resolved feed's decimals.
        uint8 feedDecimals = loanFeed.decimals();
        uint256 loanPricePerUnit = uint256(loanAnswer);
        if (feedDecimals < 18) {
            loanPricePerUnit = loanPricePerUnit * (10 ** (18 - feedDecimals));
        } else if (feedDecimals > 18) {
            loanPricePerUnit = loanPricePerUnit / (10 ** (feedDecimals - 18));
        }

        // Adjust for token decimals (same logic as ChainlinkOracle).
        uint8 tokenDecimals = underlyingLoan.decimals();
        if (tokenDecimals < 18) {
            return loanPricePerUnit * (10 ** (18 - tokenDecimals));
        } else if (tokenDecimals > 18) {
            return loanPricePerUnit / (10 ** (tokenDecimals - 18));
        }
        return loanPricePerUnit;
    }

    /// @notice Calculate the split of seized collateral between liquidator and fee recipient
    /// @param repayAmount The amount of loan tokens being repaid
    /// @param collateralSeized The amount of collateral tokens seized (in mToken units)
    /// @param underlyingLoan The underlying loan token interface
    /// @param mTokenCollateral The mToken for the collateral
    /// @param underlyingCollateral The underlying collateral token interface
    /// @return liquidatorFee The amount of collateral to send to the liquidator (repayment + bonus) in mToken units
    /// @return protocolFee The amount of collateral to send to the fee recipient (remainder) in mToken units
    function _calculateCollateralSplit(
        uint256 repayAmount,
        int256 collateralAnswer,
        uint256 collateralSeized,
        EIP20Interface underlyingLoan,
        address mTokenCollateral,
        EIP20Interface underlyingCollateral
    ) internal view returns (uint256 liquidatorFee, uint256 protocolFee) {
        uint256 loanPrice = _getLoanTokenPrice(underlyingLoan);
        uint256 collateralPrice = _getCollateralTokenPrice(
            collateralAnswer,
            underlyingCollateral
        );

        // Convert seized mTokens to underlying amount, and accrue interest
        uint256 exchangeRate = MTokenInterface(mTokenCollateral)
            .exchangeRateStored();
        uint256 underlyingAmount = (collateralSeized * exchangeRate) / 1e18;

        uint256 usdNormalizer = 10 ** PRICE_MANTISSA_DECIMALS; // 1e18
        uint256 repayUSD = (repayAmount * loanPrice) / usdNormalizer;
        uint256 collateralUSD = (underlyingAmount * collateralPrice) /
            usdNormalizer;

        // If collateral is worth less than repayment, liquidator gets all collateral
        if (collateralUSD <= repayUSD) {
            liquidatorFee = collateralSeized;
            protocolFee = 0;
            return (liquidatorFee, protocolFee);
        }

        // Liquidator gets the repayment amount + bonus (remainder * liquidatorFeeBps)
        uint256 liquidatorUSD = repayUSD +
            ((collateralUSD - repayUSD) * uint256(liquidatorFeeBps)) /
            MAX_BPS;

        // Convert liquidator USD to underlying, then to mToken units
        uint256 liquidatorUnderlyingAmount = (liquidatorUSD * usdNormalizer) /
            collateralPrice;
        liquidatorFee = (liquidatorUnderlyingAmount * 1e18) / exchangeRate;

        protocolFee = collateralSeized - liquidatorFee;
    }
}
