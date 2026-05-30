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

/**
 * @title ChainlinkCompositeOEVWrapper
 * @notice A wrapper for composite Chainlink oracles (ChainlinkCompositeOracle, BoundedCompositeOracle)
 *         that adds OEV (Oracle Extractable Value) protection via base feed round tracking.
 * @dev Composite oracles don't have their own round IDs (they return roundId=0, updatedAt=block.timestamp).
 *      This wrapper tracks the base Chainlink feed's round ID (e.g., ETH/USD) as a proxy for new price
 *      information, and caches the composite price to implement the delay mechanism.
 *
 *      Delay mechanism:
 *      1. If base feed round == cached round -> return fresh composite price (no new information)
 *      2. If base feed has new round AND within maxRoundDelay -> return cached composite price (delayed)
 *      3. If base feed has new round AND beyond maxRoundDelay -> return fresh composite price (timeout)
 */
contract ChainlinkCompositeOEVWrapper is
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

    /// @notice The composite oracle to read prices from (ChainlinkCompositeOracle or BoundedCompositeOracle)
    AggregatorV3Interface public compositeOracle;

    /// @notice The base Chainlink price feed for round tracking (e.g., ETH/USD)
    AggregatorV3Interface public baseFeed;

    /// @notice The address that will receive the OEV fees
    address public feeRecipient;

    /// @notice The fee multiplier (in bps) for the OEV fees, to be paid to the liquidator
    uint16 public liquidatorFeeBps;

    /// @notice The last cached base feed round id
    uint256 public cachedBaseRoundId;

    /// @notice The cached composite price at the time of last cache update
    int256 public cachedCompositePrice;

    /// @notice The cached timestamp at the time of last cache update
    uint256 public cachedTimestamp;

    /// @notice The max round delay in seconds
    uint256 public maxRoundDelay;

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
     * @param _compositeOracle Address of the composite oracle to read prices from
     * @param _baseFeed Address of the base Chainlink feed for round tracking
     * @param _owner Address that will own this contract
     * @param _chainlinkOracle Address of the ChainlinkOracle contract
     * @param _feeRecipient Address that will receive the OEV fees
     * @param _liquidatorFeeBps The liquidator fee BPS for the OEV fees
     * @param _maxRoundDelay The max round delay in seconds
     */
    constructor(
        address _compositeOracle,
        address _baseFeed,
        address _owner,
        address _chainlinkOracle,
        address _feeRecipient,
        uint16 _liquidatorFeeBps,
        uint256 _maxRoundDelay
    ) {
        require(
            _compositeOracle != address(0),
            "ChainlinkCompositeOEVWrapper: composite oracle cannot be zero address"
        );
        require(
            _baseFeed != address(0),
            "ChainlinkCompositeOEVWrapper: base feed cannot be zero address"
        );
        require(
            _owner != address(0),
            "ChainlinkCompositeOEVWrapper: owner cannot be zero address"
        );
        require(
            _liquidatorFeeBps <= MAX_BPS,
            "ChainlinkCompositeOEVWrapper: liquidator fee cannot be greater than MAX_BPS"
        );
        require(
            _maxRoundDelay > 0,
            "ChainlinkCompositeOEVWrapper: max round delay cannot be zero"
        );
        require(
            _chainlinkOracle != address(0),
            "ChainlinkCompositeOEVWrapper: chainlink oracle cannot be zero address"
        );
        require(
            _feeRecipient != address(0),
            "ChainlinkCompositeOEVWrapper: fee recipient cannot be zero address"
        );

        compositeOracle = AggregatorV3Interface(_compositeOracle);
        baseFeed = AggregatorV3Interface(_baseFeed);
        liquidatorFeeBps = _liquidatorFeeBps;
        maxRoundDelay = _maxRoundDelay;
        chainlinkOracle = IChainlinkOracle(_chainlinkOracle);
        feeRecipient = _feeRecipient;

        // Initialize cache with current composite price and base feed round
        (
            ,
            int256 compositePrice,
            ,
            uint256 compositeUpdatedAt,

        ) = compositeOracle.latestRoundData();

        (uint80 initBaseRoundId, , , , ) = baseFeed.latestRoundData();

        cachedCompositePrice = compositePrice;
        cachedTimestamp = compositeUpdatedAt;
        cachedBaseRoundId = uint256(initBaseRoundId);

        _transferOwnership(_owner);
    }

    /**
     * @notice Returns the number of decimals in the composite oracle
     * @return The number of decimals
     */
    function decimals() external view override returns (uint8) {
        return compositeOracle.decimals();
    }

    /**
     * @notice Returns a description of this wrapper
     * @return The description string
     */
    function description() external pure override returns (string memory) {
        return "Chainlink Composite OEV Wrapper";
    }

    /**
     * @notice Returns the version number
     * @return The version number
     */
    function version() external pure override returns (uint256) {
        return 1;
    }

    /**
     * @notice Returns data for a specific round - NOT SUPPORTED for composite oracles
     * @dev Composite oracles don't have real round data, so this always reverts
     */
    function getRoundData(
        uint80
    )
        external
        pure
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        revert(
            "ChainlinkCompositeOEVWrapper: getRoundData not supported for composite oracles"
        );
    }

    /**
     * @notice Returns data from the latest round, with OEV protection mechanism
     * @dev Uses base feed round tracking to determine if the composite price should be delayed.
     *      - If base feed round matches cached round: return fresh composite price
     *      - If base feed has new round within maxRoundDelay: return cached composite price
     *      - If base feed has new round past maxRoundDelay: return fresh composite price
     * @return roundId Always 0 (composite oracles don't have rounds)
     * @return answer The composite price (either fresh or cached)
     * @return startedAt Always 0
     * @return updatedAt The timestamp (either current or cached)
     * @return answeredInRound Always 0
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
        // Get current base feed round
        (uint80 baseRoundId, , , uint256 baseUpdatedAt, ) = baseFeed
            .latestRoundData();

        // If base feed round matches cached round, no new price information -> return fresh composite price
        if (uint256(baseRoundId) == cachedBaseRoundId) {
            (, answer, , updatedAt, ) = compositeOracle.latestRoundData();
            require(
                answer > 0,
                "Chainlink price cannot be lower or equal to 0"
            );
            return (0, answer, 0, updatedAt, 0);
        }

        // Base feed has a new round. Check if within delay window.
        if (block.timestamp < baseUpdatedAt + maxRoundDelay) {
            // Within delay window -> return cached composite price
            answer = cachedCompositePrice;
            updatedAt = cachedTimestamp;
            require(
                answer > 0,
                "Chainlink price cannot be lower or equal to 0"
            );
            return (0, answer, 0, updatedAt, 0);
        }

        // Past delay window -> return fresh composite price (timeout)
        (, answer, , updatedAt, ) = compositeOracle.latestRoundData();
        require(answer > 0, "Chainlink price cannot be lower or equal to 0");
        return (0, answer, 0, updatedAt, 0);
    }

    /**
     * @notice Returns the latest round ID from the base feed
     * @return The latest round ID of the base feed
     */
    function latestRound() external view override returns (uint256) {
        return baseFeed.latestRound();
    }

    /**
     * @notice Sets the liquidator fee BPS for OEV fees
     * @param _liquidatorFeeBps The new liquidator fee in basis points (must be <= MAX_BPS)
     */
    function setLiquidatorFeeBps(uint16 _liquidatorFeeBps) external onlyOwner {
        require(
            _liquidatorFeeBps <= MAX_BPS,
            "ChainlinkCompositeOEVWrapper: liquidator fee cannot be greater than MAX_BPS"
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
            "ChainlinkCompositeOEVWrapper: max round delay cannot be zero"
        );
        uint256 oldMaxRoundDelay = maxRoundDelay;
        maxRoundDelay = _maxRoundDelay;
        emit MaxRoundDelayChanged(oldMaxRoundDelay, _maxRoundDelay);
    }

    /**
     * @notice Sets the fee recipient address
     * @param _feeRecipient The new fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(
            _feeRecipient != address(0),
            "ChainlinkCompositeOEVWrapper: fee recipient cannot be zero address"
        );

        address oldFeeRecipient = feeRecipient;
        feeRecipient = _feeRecipient;

        emit FeeRecipientChanged(oldFeeRecipient, _feeRecipient);
    }

    /**
     * @notice Recovers ERC20 tokens accidentally sent to this contract
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

    /// @notice Allows the contract to receive ETH (needed for mWETH redemption which unwraps to ETH)
    receive() external payable {}

    /**
     * @notice Updates the cached composite price and base round, then executes a liquidation
     * @param borrower The address of the borrower to liquidate
     * @param repayAmount The amount to repay on behalf of the borrower
     * @param mTokenCollateral The mToken market for the collateral token
     * @param mTokenLoan The mToken market for the loan token
     */
    function updatePriceEarlyAndLiquidate(
        address borrower,
        uint256 repayAmount,
        address mTokenCollateral,
        address mTokenLoan
    ) external nonReentrant {
        require(
            repayAmount > 0,
            "ChainlinkCompositeOEVWrapper: repay amount cannot be zero"
        );
        require(
            borrower != address(0),
            "ChainlinkCompositeOEVWrapper: borrower cannot be zero address"
        );
        require(
            mTokenCollateral != address(0),
            "ChainlinkCompositeOEVWrapper: mToken collateral cannot be zero address"
        );
        require(
            mTokenLoan != address(0),
            "ChainlinkCompositeOEVWrapper: mToken loan cannot be zero address"
        );

        // get the loan underlying token
        EIP20Interface underlyingLoan = EIP20Interface(
            MErc20Storage(mTokenLoan).underlying()
        );

        // get the collateral underlying token
        EIP20Interface underlyingCollateral = EIP20Interface(
            MErc20Storage(mTokenCollateral).underlying()
        );

        MTokenInterface mTokenCollateralInterface = MTokenInterface(
            mTokenCollateral
        );

        require(
            address(chainlinkOracle.getFeed(underlyingCollateral.symbol())) ==
                address(this),
            "ChainlinkCompositeOEVWrapper: chainlink oracle feed does not match"
        );

        // transfer the loan token from the liquidator to this contract
        IERC20(address(underlyingLoan)).safeTransferFrom(
            msg.sender,
            address(this),
            repayAmount
        );

        // Get fresh composite price and update cache
        int256 collateralAnswer;
        {
            (
                ,
                int256 freshCompositePrice,
                ,
                uint256 freshUpdatedAt,

            ) = compositeOracle.latestRoundData();

            require(
                freshCompositePrice > 0,
                "Chainlink price cannot be lower or equal to 0"
            );

            // Get base feed round atomically via latestRoundData
            (uint80 baseRoundId, , , , ) = baseFeed.latestRoundData();

            // Update cache with fresh composite price and current base round
            cachedCompositePrice = freshCompositePrice;
            cachedTimestamp = freshUpdatedAt;
            cachedBaseRoundId = uint256(baseRoundId);

            collateralAnswer = freshCompositePrice;
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
            "ChainlinkCompositeOEVWrapper: collateral seized cannot be zero"
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

        // transfer the liquidator's payment to the liquidator
        bool liquidatorSuccess = mTokenCollateralInterface.transfer(
            msg.sender,
            liquidatorFee
        );
        require(
            liquidatorSuccess,
            "ChainlinkCompositeOEVWrapper: liquidator fee transfer failed"
        );

        // transfer the remainder to the fee recipient
        bool protocolSuccess = mTokenCollateralInterface.transfer(
            feeRecipient,
            protocolFee
        );
        require(
            protocolSuccess,
            "ChainlinkCompositeOEVWrapper: protocol fee transfer failed"
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

    /// @notice Calculate the fully adjusted collateral token price
    /// @dev Scales composite oracle decimals to 18, then adjusts for token decimals
    /// @param collateralAnswer The raw price from the composite oracle
    /// @param underlyingCollateral The collateral token interface
    /// @return The price scaled to 1e18 and adjusted for token decimals
    function _getCollateralTokenPrice(
        int256 collateralAnswer,
        EIP20Interface underlyingCollateral
    ) internal view returns (uint256) {
        uint8 feedDecimals = compositeOracle.decimals();
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
        underlyingLoan.approve(_mTokenLoan, repayAmount);
        require(
            MErc20Interface(_mTokenLoan).liquidateBorrow(
                borrower,
                repayAmount,
                mTokenCollateral
            ) == 0,
            "ChainlinkCompositeOEVWrapper: liquidation failed"
        );

        collateralSeized =
            mTokenCollateral.balanceOf(address(this)) -
            mTokenCollateralBalanceBefore;
    }

    /// @notice Get the loan token price directly from the underlying Chainlink feed
    function _getLoanTokenPrice(
        EIP20Interface underlyingLoan
    ) internal view returns (uint256) {
        AggregatorV3Interface loanFeed = chainlinkOracle.getFeed(
            underlyingLoan.symbol()
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

        // Scale feed decimals to 18
        uint8 feedDecimals = loanFeed.decimals();
        uint256 loanPricePerUnit = uint256(loanAnswer);
        if (feedDecimals < 18) {
            loanPricePerUnit = loanPricePerUnit * (10 ** (18 - feedDecimals));
        } else if (feedDecimals > 18) {
            loanPricePerUnit = loanPricePerUnit / (10 ** (feedDecimals - 18));
        }

        // Adjust for token decimals
        uint8 tokenDecimals = underlyingLoan.decimals();
        if (tokenDecimals < 18) {
            return loanPricePerUnit * (10 ** (18 - tokenDecimals));
        } else if (tokenDecimals > 18) {
            return loanPricePerUnit / (10 ** (tokenDecimals - 18));
        }
        return loanPricePerUnit;
    }

    /// @notice Calculate the split of seized collateral between liquidator and fee recipient
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

        // Convert seized mTokens to underlying amount
        uint256 exchangeRate = MTokenInterface(mTokenCollateral)
            .exchangeRateStored();
        uint256 underlyingAmount = (collateralSeized * exchangeRate) / 1e18;

        uint256 usdNormalizer = 10 ** PRICE_MANTISSA_DECIMALS;
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

    /// @notice Validate the round data from Chainlink
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
}
