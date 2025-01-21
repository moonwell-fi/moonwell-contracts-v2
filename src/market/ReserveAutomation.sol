pragma solidity =0.8.19;

import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {ERC20Mover} from "@protocol/market/ERC20Mover.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

/// @notice Contract that automates the sale of reserves for WELL tokens
/// @dev Uses Chainlink price feeds to determine exchange rates and implements a discount mechanism
contract ReserveAutomation is ERC20Mover {
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice the value to scale values
    uint256 public constant SCALAR = 1e18;

    /// @notice the maximum amount of time to wait for the auction to start
    uint256 public constant MAXIMUM_AUCTION_DELAY = 7 days;

    /// @notice address of the mToken market to add reserves back to
    address public immutable mTokenMarket;

    /// ------------------------------------------------------------
    /// ------------------------------------------------------------
    /// --------------------- Mutable Variables --------------------
    /// ------------------------------------------------------------
    /// ------------------------------------------------------------

    /// @notice period of time the sale is open for
    uint256 public saleWindow;

    /// @notice the period each mini auction within the larger sale lasts
    uint256 public miniAuctionPeriod;

    /// @notice maximum discount reached during a mini auction in percentage
    /// terms scaled to 1e18 must be less than 1 (1e18) as no discounts over or
    /// equal to 100% are allowed
    uint256 public maxDiscount;

    /// @notice the starting premium on the price of the reserve asset
    uint256 public startingPremium;

    /// @notice address of the guardian, can cancel auctions sending reserves
    /// back to the market
    address public guardian;

    /// @notice the address to send the proceeds of the sale to. Initially will
    /// be the ERC20Holding Deposit address that holds WELL.
    address public recipientAddress;

    /// ------------------------------------------------------------
    /// ------------------------------------------------------------
    /// ------------- Dynamically Calculated Variables -------------
    /// ------------------------------------------------------------
    /// ------------------------------------------------------------

    /// @notice the start time of the sale period
    uint256 public saleStartTime;

    /// @notice set to the contract balance when a sale is initiated
    uint256 public periodSaleAmount;

    struct CachedChainlinkPrices {
        int256 wellPrice;
        int256 reservePrice;
    }

    /// @notice mapping that stores the periodsale start time and corresponding
    /// cached chainlink price. Can only be cached once per period.
    mapping(uint256 periodSaleStartTime => CachedChainlinkPrices cachedChainlinkPrice)
        public startPeriodTimestampCachedChainlinkPrice;

    /// @notice mapping that stores the period start time and corresponding
    /// amount of reserves sold during that period
    mapping(uint256 periodSaleStartTime => uint256 amountSold)
        public periodStartSaleAmount;

    /// ------------------------------------------------------------
    /// ------------------------------------------------------------
    /// ------------------------ Immutables ------------------------
    /// ------------------------------------------------------------
    /// ------------------------------------------------------------

    /// @notice the decimals of the reserve asset
    uint8 public immutable reserveAssetDecimals;

    /// @notice address of the WELL token
    address public immutable wellToken;

    /// @notice address of the reserve asset
    address public immutable reserveAsset;

    /// @notice address of the Chainlink feed for the WELL token
    address public immutable wellChainlinkFeed;

    /// @notice address of the Chainlink feed for the reserve asset
    address public immutable reserveChainlinkFeed;

    /// ------------------------------------------------------------
    /// ------------------------------------------------------------
    /// ---------------------- Initialization -----------------------
    /// ------------------------------------------------------------
    /// ------------------------------------------------------------

    /// @notice struct of the parameters to initialize the contract
    struct InitParams {
        /// @notice address to receive sale proceeds
        address recipientAddress;
        /// @notice address of the WELL token
        address wellToken;
        /// @notice address of the reserve asset
        address reserveAsset;
        /// @notice address of the Chainlink feed for WELL
        address wellChainlinkFeed;
        /// @notice address of the Chainlink feed for reserve asset
        address reserveChainlinkFeed;
        /// @notice address of the contract owner
        address owner;
        /// @notice address of the market to add reserves back to
        address mTokenMarket;
        /// @notice address of the initial guardian
        address guardian;
    }

    /// ------------------------------------------------------------
    /// ------------------------------------------------------------
    /// -------------------------- Events --------------------------
    /// ------------------------------------------------------------
    /// ------------------------------------------------------------

    /// @notice emitted when reserves are purchased
    /// @param buyer address of the account purchasing reserves
    /// @param amountWellIn amount of WELL tokens used for purchase
    /// @param amountOut amount of reserve tokens received
    /// @param discount current discount rate applied to the purchase
    event ReservesPurchased(
        address indexed buyer,
        uint256 amountWellIn,
        uint256 amountOut,
        uint256 discount
    );

    /// @notice emitted when a sale is started
    /// @param saleStartTime timestamp when the sale begins
    /// @param periodSaleAmount total amount of reserves available for sale
    /// @param saleWindow the period of time the sale is open for
    /// @param miniAuctionPeriod the period of time each mini auction within the sale window lasts
    event SaleInitiated(
        uint256 saleStartTime,
        uint256 periodSaleAmount,
        uint256 saleWindow,
        uint256 miniAuctionPeriod
    );

    /// @notice emitted when the maximum discount is set
    /// @param newMaxDiscount the new maximum discount value
    event MaxDiscountSet(uint256 newMaxDiscount);

    /// @notice emitted when the recipient address is updated
    /// @param previousRecipient the previous recipient address
    /// @param newRecipient the new recipient address
    event RecipientAddressUpdate(
        address previousRecipient,
        address newRecipient
    );

    /// @notice emitted when the guardian is updated
    /// @param oldGuardian previous guardian address
    /// @param newGuardian new guardian address
    event GuardianUpdated(
        address indexed oldGuardian,
        address indexed newGuardian
    );

    /// @notice emitted when an auction is cancelled by the guardian
    /// @param guardian address of the guardian who cancelled
    /// @param amount amount of reserves returned to market
    event AuctionCancelled(address indexed guardian, uint256 amount);

    /// @notice Initializes the contract with the given parameters
    /// @param params struct containing initialization parameters
    constructor(InitParams memory params) ERC20Mover(params.owner) {
        recipientAddress = params.recipientAddress;
        wellToken = params.wellToken;
        reserveAsset = params.reserveAsset;
        wellChainlinkFeed = params.wellChainlinkFeed;
        reserveChainlinkFeed = params.reserveChainlinkFeed;
        reserveAssetDecimals = ERC20(params.reserveAsset).decimals();
        mTokenMarket = params.mTokenMarket;
        guardian = params.guardian;

        /// sanity check that reserve asset does not have more than 18 decimals
        require(
            reserveAssetDecimals <= 18,
            "ReserveAutomationModule: reserve asset has too many decimals"
        );
    }

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// -------------------- View Functions ------------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// periods are defined as mini auction periods
    /// if a mini auction is 10 seconds long as a simplified example, and the sale started at
    /// 11, then the first period would be 11 to 20, the second period would be 21 to 30, etc.
    /// this is because the start and end second are inclusive

    /// @notice Returns the start time of the current mini auction period
    /// @return startTime The timestamp when the current mini auction period started
    /// @dev Returns 0 if no sale is active or if the sale hasn't started yet
    /// @dev If the sale has ended, returns the start time of the last period
    function getCurrentPeriodStartTime()
        public
        view
        returns (uint256 startTime)
    {
        if (
            saleStartTime == 0 ||
            block.timestamp < saleStartTime ||
            block.timestamp > saleStartTime + saleWindow
        ) {
            return 0;
        }

        // Calculate how many complete periods have passed since sale start
        uint256 periodsPassed = (block.timestamp - saleStartTime) /
            miniAuctionPeriod;

        // Calculate the start time of the current period
        // Each period starts 1 second after the previous period ends
        return saleStartTime + (periodsPassed * miniAuctionPeriod);
    }

    /// @notice Returns the end time of the current mini auction period
    /// @return The timestamp when the current mini auction period ends
    /// @dev Returns 0 if no sale is active or if the sale hasn't started yet
    /// @dev Each period is exactly miniAuctionPeriod in length
    function getCurrentPeriodEndTime() public view returns (uint256) {
        uint256 startTime = getCurrentPeriodStartTime();
        if (startTime == 0) {
            return 0;
        }

        return startTime + miniAuctionPeriod - 1;
    }

    /// @notice gives the remaining amount of reserves for sale in the current
    /// period. If not in an active period, returns 0 as no tokens are
    /// available for sale
    function getCurrentPeriodRemainingReserves() public view returns (uint256) {
        uint256 startTime = getCurrentPeriodStartTime();
        if (startTime == 0) {
            return 0;
        }

        return periodSaleAmount - periodStartSaleAmount[startTime];
    }

    /// @notice Calculates the current discount or premium rate for reserve purchases
    /// @return The current discount as a percentage scaled to 1e18, returns
    /// 1e18 if no discount is applied
    /// @dev Does not apply discount or premium if the sale is not active
    function currentDiscount() public view returns (uint256) {
        if (
            saleStartTime == 0 ||
            block.timestamp < saleStartTime ||
            block.timestamp > saleStartTime + saleWindow
        ) {
            return SCALAR;
        }

        uint256 decayDelta = startingPremium - maxDiscount;
        uint256 periodStart = getCurrentPeriodStartTime();
        uint256 periodEnd = getCurrentPeriodEndTime();
        uint256 saleTimeRemaining = periodEnd - block.timestamp;

        /// calculate the current premium or discount at the current time based
        /// on the length you are into the current period
        return
            maxDiscount +
            (decayDelta * saleTimeRemaining) /
            (periodEnd - periodStart);
    }

    /// @notice Calculates the amount of WELL needed to purchase a given amount of reserves
    /// @param amountReserveAssetIn The amount of reserves to purchase
    /// @return amountWellOut The amount of WELL needed to purchase the given amount of reserves
    /// @dev Uses Chainlink price feeds and applies current discount if applicable
    function getAmountWellOut(
        uint256 amountReserveAssetIn
    ) public view returns (uint256 amountWellOut) {
        CachedChainlinkPrices memory cachedPrices = getCachedChainlinkPrices();

        // Get normalized prices for both tokens
        uint256 normalizedWellPrice = _getNormalizedPrice(
            wellChainlinkFeed,
            cachedPrices.wellPrice
        );
        uint256 normalizedReservePrice = _getNormalizedPrice(
            reserveChainlinkFeed,
            cachedPrices.reservePrice
        );

        /// apply the premium or discount to the reserve asset price
        ///    reserve asset price = reserve asset price * (1 - discount)
        {
            uint256 discount = currentDiscount();

            normalizedReservePrice =
                (normalizedReservePrice * discount) /
                SCALAR;
        }

        /// normalize decimals up to 18 if reserve asset has less than 18 decimals
        if (reserveAssetDecimals != 18) {
            amountReserveAssetIn =
                amountReserveAssetIn *
                (10 ** uint256(18 - reserveAssetDecimals));
        }

        /// calculate the reserve asset dollar value
        uint256 reserveAssetValue = amountReserveAssetIn *
            normalizedReservePrice;

        /// divide the reserve asset amount out by the WELL price in USD
        /// since both are scaled by 1e18, the result loses the scaling
        amountWellOut = reserveAssetValue / normalizedWellPrice;
    }

    /// @notice returns the amount of reserves that can be purchased at the
    /// current market price of the reserve asset with the given amount of WELL
    /// @param amountWellIn the amount of WELL tokens to purchase reserves with
    /// @return amountOut the amount of reserves that can be purchased with the given amount of WELL
    /// @dev this function does not revert if the amount of reserves is greater than the buffer
    function getAmountReservesOut(
        uint256 amountWellIn
    ) public view returns (uint256 amountOut) {
        CachedChainlinkPrices memory cachedPrices = getCachedChainlinkPrices();

        // Get normalized prices for both tokens
        uint256 normalizedWellPrice = _getNormalizedPrice(
            wellChainlinkFeed,
            cachedPrices.wellPrice
        );
        uint256 normalizedReservePrice = _getNormalizedPrice(
            reserveChainlinkFeed,
            cachedPrices.reservePrice
        );

        /// multiply the amount of WELL by WELL price in USD, result is still scaled up by 18
        uint256 wellAmountUSD = amountWellIn * normalizedWellPrice;

        /// if we are in the discount period, apply the discount to the reserve asset price
        ///    reserve asset price = reserve asset price * (1 - discount)
        {
            uint256 discount = currentDiscount();

            normalizedReservePrice =
                (normalizedReservePrice * discount) /
                SCALAR;
        }

        /// divide the amount of WELL in USD being sold by the reserve asset price in USD
        /// since both are scaled by 1e18, the result loses the scaling
        amountOut = wellAmountUSD / normalizedReservePrice;

        /// if the reserve asset has non 18 decimals, shrink down the amount of
        /// reserve asset received to the actual amount
        if (reserveAssetDecimals != 18) {
            amountOut = amountOut / (10 ** uint256(18 - reserveAssetDecimals));
        }
    }

    /// @notice helper function to get the cached chainlink prices for the current period
    /// @return the cached chainlink prices for the current period. Returns 0 if
    /// the prices have not been cached yet for the current period or if there is no active sale
    function getCachedChainlinkPrices()
        public
        view
        returns (CachedChainlinkPrices memory)
    {
        uint256 startTime = getCurrentPeriodStartTime();
        return startPeriodTimestampCachedChainlinkPrice[startTime];
    }

    /// @notice helper function to retrieve price from chainlink
    /// @param oracleAddress The address of the chainlink oracle
    /// returns the price and then the decimals of the given asset
    /// reverts if price is 0 or if the oracle data is invalid
    function getPriceAndDecimals(
        address oracleAddress
    ) public view returns (int256, uint8) {
        (
            uint80 roundId,
            int256 price,
            ,
            ,
            uint80 answeredInRound
        ) = AggregatorV3Interface(oracleAddress).latestRoundData();
        bool valid = price > 0 && answeredInRound >= roundId;
        require(valid, "ReserveAutomationModule: Oracle data is invalid");
        uint8 oracleDecimals = AggregatorV3Interface(oracleAddress).decimals();

        return (price, oracleDecimals); /// price always gt 0 at this point
    }

    /// @notice scale price up or down to the desired amount of decimals
    /// @param price The price to scale
    /// @param priceDecimals The amount of decimals the price has
    /// @param expectedDecimals The amount of decimals the price should have
    /// @return the scaled price
    function scalePrice(
        int256 price,
        uint8 priceDecimals,
        uint8 expectedDecimals
    ) public pure returns (int256) {
        if (priceDecimals < expectedDecimals) {
            return
                price *
                (10 ** uint256(expectedDecimals - priceDecimals)).toInt256();
        } else if (priceDecimals > expectedDecimals) {
            return
                price /
                (10 ** uint256(priceDecimals - expectedDecimals)).toInt256();
        }

        /// if priceDecimals == expectedDecimals, return price without any changes

        return price;
    }

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// --------------- Owner Mutative Functions -------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @notice Sets the address that receives the proceeds from sales
    /// @param recipient The new recipient address
    function setRecipientAddress(address recipient) external onlyOwner {
        address previousRecipient = recipientAddress;
        recipientAddress = recipient;

        emit RecipientAddressUpdate(previousRecipient, recipient);
    }

    /// @notice Sets a new guardian address
    /// @param newGuardian The address of the new guardian
    /// @dev Only callable by owner
    function setGuardian(address newGuardian) external onlyOwner {
        address oldGuardian = guardian;
        guardian = newGuardian;
        emit GuardianUpdated(oldGuardian, newGuardian);
    }

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// ---------------- Guardian Mutative Function ----------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @notice Cancels an auction at any time
    /// @dev Only callable by guardian
    function cancelAuction() external {
        require(
            msg.sender == guardian,
            "ReserveAutomationModule: only guardian"
        );

        uint256 amount = IERC20(reserveAsset).balanceOf(address(this));

        saleStartTime = 0;
        periodSaleAmount = 0;

        IERC20(reserveAsset).approve(mTokenMarket, amount);

        require(
            MErc20(mTokenMarket)._addReserves(amount) == 0,
            "ReserveAutomationModule: add reserves failure"
        );

        emit AuctionCancelled(guardian, amount);
    }

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// ------------------ Mutative Functions ----------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @notice Allows a user to purchase reserves in exchange for WELL tokens
    /// @param amountWellIn The amount of WELL tokens to spend
    /// @param minAmountOut The minimum amount of reserves to receive
    /// @return amountOut The amount of reserves received
    /// @dev Applies current discount/premium based on where the contract is in the auction period
    function getReserves(
        uint256 amountWellIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        /// CHECKS

        /// check that the sale is active
        require(
            saleStartTime > 0 &&
                block.timestamp >= saleStartTime &&
                block.timestamp < saleStartTime + saleWindow,
            "ReserveAutomationModule: sale not active"
        );

        require(amountWellIn != 0, "ReserveAutomationModule: amount in is 0");

        amountOut = getAmountReservesOut(amountWellIn);

        /// bound the sale amount by the amount of reserves remaining in the
        /// current period
        require(
            amountOut <= getCurrentPeriodRemainingReserves(),
            "ReserveAutomationModule: not enough reserves remaining"
        );

        /// check that the amount of reserves is less than the total amount of reserves
        require(
            amountOut >= minAmountOut,
            "ReserveAutomationModule: not enough out"
        );

        /// EFFECTS

        uint256 startTime = getCurrentPeriodStartTime();

        periodStartSaleAmount[startTime] += amountOut;

        /// cache the chainlink prices if they have not been cached for the
        /// current period
        if (
            startPeriodTimestampCachedChainlinkPrice[startTime].wellPrice == 0
        ) {
            (int256 wellPrice, ) = getPriceAndDecimals(wellChainlinkFeed);
            startPeriodTimestampCachedChainlinkPrice[startTime]
                .wellPrice = wellPrice;

            (int256 reservePrice, ) = getPriceAndDecimals(reserveChainlinkFeed);
            startPeriodTimestampCachedChainlinkPrice[startTime]
                .reservePrice = reservePrice;
        }

        /// INTERACTIONS

        /// transfer the WELL tokens from the user to the recipient contract address
        IERC20(wellToken).safeTransferFrom(
            msg.sender,
            recipientAddress,
            amountWellIn
        );

        /// transfer the reserves from the contract to the user
        IERC20(reserveAsset).safeTransfer(msg.sender, amountOut);

        emit ReservesPurchased(
            msg.sender,
            amountWellIn,
            amountOut,
            currentDiscount()
        );
    }

    /// @notice Initiates a new sale of reserves
    /// @param _delay The time to wait before starting the sale
    /// @param _auctionPeriod The period of time the sale is open for
    /// @param _miniAuctionPeriod The period of time each mini auction lasts
    /// @param _periodMaxDiscount The maximum discount reached during a mini auction
    /// @param _periodStartingPremium The starting premium on during a mini auction
    /// @dev Can only be called if there are no active sales and there are reserves available
    function initiateSale(
        uint256 _delay,
        uint256 _auctionPeriod,
        uint256 _miniAuctionPeriod,
        uint256 _periodMaxDiscount,
        uint256 _periodStartingPremium
    ) external onlyOwner {
        require(
            saleStartTime == 0 || block.timestamp > saleStartTime + saleWindow,
            "ReserveAutomationModule: sale already active"
        );
        /// each period sale is the total amount of reserves divided by the
        /// number of mini auctions
        periodSaleAmount =
            IERC20(reserveAsset).balanceOf(address(this)) /
            (_auctionPeriod / _miniAuctionPeriod);
        require(
            periodSaleAmount > 0,
            "ReserveAutomationModule: no reserves to sell"
        );
        require(
            _delay <= MAXIMUM_AUCTION_DELAY,
            "ReserveAutomationModule: delay exceeds max"
        );

        require(
            _periodMaxDiscount < SCALAR,
            "ReserveAutomationModule: ending discount must be less than 1"
        );
        require(
            _periodStartingPremium > SCALAR,
            "ReserveAutomationModule: starting premium must be greater than 1"
        );

        /// sanity check that the auction period is divisible by the mini
        /// auction period and that the auction period is greater than the
        /// mini auction period
        require(
            _auctionPeriod % _miniAuctionPeriod == 0,
            "ReserveAutomationModule: auction period not divisible by mini auction period"
        );
        require(
            _auctionPeriod / _miniAuctionPeriod > 1,
            "ReserveAutomationModule: auction period not greater than mini auction period"
        );

        maxDiscount = _periodMaxDiscount;
        startingPremium = _periodStartingPremium;

        saleStartTime = block.timestamp + _delay;
        saleWindow = _auctionPeriod;
        miniAuctionPeriod = _miniAuctionPeriod;

        emit MaxDiscountSet(maxDiscount);
        emit SaleInitiated(
            saleStartTime,
            periodSaleAmount,
            _auctionPeriod,
            _miniAuctionPeriod
        );
    }

    /// @notice helper function to get normalized price for a token, using cached price if available
    /// @param oracleAddress The address of the chainlink oracle for the token
    /// @param cachedPrice The cached price from the current period, if any
    /// @return normalizedPrice The normalized price with 18 decimals
    function _getNormalizedPrice(
        address oracleAddress,
        int256 cachedPrice
    ) private view returns (uint256 normalizedPrice) {
        (int256 price, uint8 decimals) = getPriceAndDecimals(oracleAddress);

        // Use cached price if available, otherwise use current price
        price = cachedPrice != 0 ? cachedPrice : price;

        // Scale price to 18 decimals and convert to uint256
        normalizedPrice = scalePrice(price, decimals, 18).toUint256();
    }
}
