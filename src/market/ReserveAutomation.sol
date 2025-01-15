pragma solidity =0.8.19;

import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MErc20} from "@protocol/MErc20.sol";

import {ERC20Mover} from "@protocol/market/ERC20Mover.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {RateLimitCommonLibrary} from "@zelt/src/lib/RateLimitCommonLibrary.sol";
import {RateLimit, RateLimitedLibrary} from "@zelt/src/lib/RateLimitedLibrary.sol";

/// @notice Contract that automates the sale of reserves for WELL tokens
/// @dev Uses Chainlink price feeds to determine exchange rates and implements a discount mechanism
contract ReserveAutomation is ERC20Mover {
    using RateLimitCommonLibrary for RateLimit;
    using RateLimitedLibrary for RateLimit;
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice period of time the sale is open for
    uint256 public constant SALE_WINDOW = 14 days;

    /// @notice the value to scale values
    uint256 public constant SCALAR = 1e18;

    /// @notice the maximum amount of time to wait for the auction to start
    uint256 public constant MAXIMUM_AUCTION_DELAY = 7 days;

    /// ------------------------------------------------------------
    /// ------------------------------------------------------------
    /// --------------------- Mutable Variables --------------------
    /// ------------------------------------------------------------
    /// ------------------------------------------------------------

    /// @notice address of the guardian who can cancel auctions
    address public guardian;

    /// @notice address of the mToken market to add reserves back to
    address public immutable mTokenMarket;

    /// @notice maximum discount in percentage terms scaled to 1e18
    /// must be less than 1 (1e18) as no discounts over or equal to 100% are allowed
    uint256 public maxDiscount;

    /// @notice the duration the discount is applied over
    uint256 public discountApplicationPeriod;

    /// @notice how long to wait since the last bid time until the discount
    /// is applied to the price
    uint256 public nonDiscountPeriod;

    /// @notice the address to send the proceeds of the sale to
    address public recipientAddress;

    /// ------------------------------------------------------------
    /// ------------------------------------------------------------
    /// ------------- Dynamically Calculated Variables -------------
    /// ------------------------------------------------------------
    /// ------------------------------------------------------------

    /// @notice the time the last bid was made
    uint256 public lastBidTime;

    /// @notice the start time of the sale period
    uint256 public saleStartTime;

    /// @notice set to the contract balance when a sale is initiated
    uint256 public periodSaleAmount;

    /// @notice the rate limit on the reserve sale, how many units can be sold per second
    RateLimit private _saleRateLimit;

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
        /// @notice maximum discount allowed for the sale
        uint256 maxDiscount;
        /// @notice period over which the discount is applied
        uint256 discountApplicationPeriod;
        /// @notice period before discount starts applying
        uint256 nonDiscountPeriod;
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
    event SaleInitiated(uint256 saleStartTime, uint256 periodSaleAmount);

    /// @notice emitted when the maximum discount is updated
    /// @param previousMaxDiscount the previous maximum discount value
    /// @param newMaxDiscount the new maximum discount value
    event MaxDiscountUpdate(
        uint256 previousMaxDiscount,
        uint256 newMaxDiscount
    );

    /// @notice emitted when the non discount period is updated
    /// @param previousNonDiscountPeriod the previous non-discount period
    /// @param newNonDiscountPeriod the new non-discount period
    event NonDiscountPeriodUpdate(
        uint256 previousNonDiscountPeriod,
        uint256 newNonDiscountPeriod
    );

    /// @notice emitted when the decay window is updated
    /// @param previousDecayWindow the previous decay window duration
    /// @param newDecayWindow the new decay window duration
    event DecayWindowUpdate(
        uint256 previousDecayWindow,
        uint256 newDecayWindow
    );

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
        maxDiscount = params.maxDiscount;
        discountApplicationPeriod = params.discountApplicationPeriod;
        nonDiscountPeriod = params.nonDiscountPeriod;
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

    /// @notice Returns the current buffer amount available for sales
    /// @return The amount of action used before hitting limit
    /// @dev replenishes at rateLimitPerSecond per second up to bufferCap
    function buffer() public view returns (uint256) {
        return _saleRateLimit.buffer();
    }

    /// @notice Returns the maximum buffer capacity
    /// @return The cap of the buffer
    function bufferCap() public view returns (uint256) {
        return _saleRateLimit.bufferCap;
    }

    /// @notice Returns the rate at which the buffer replenishes
    /// @return The amount the buffer replenishes per second
    function rateLimitPerSecond() public view returns (uint256) {
        return _saleRateLimit.rateLimitPerSecond;
    }

    /// @notice Calculates the current discount rate for reserve purchases
    /// @return The current discount as a percentage scaled to 1e18, returns 0 if no discount is applied
    /// @dev Does not apply discount if sale is not active
    function currentDiscount() public view returns (uint256) {
        if (
            saleStartTime == 0 ||
            block.timestamp < saleStartTime ||
            block.timestamp > saleStartTime + SALE_WINDOW
        ) {
            return 0;
        }

        if (block.timestamp - lastBidTime < nonDiscountPeriod) {
            return 0;
        }

        /// should never revert because discount window is active, which means that
        ///   block.timestamp >= lastBidTime - nonDiscountPeriod
        uint256 discountDecayTime = block.timestamp -
            lastBidTime -
            nonDiscountPeriod;

        /// you should never be able to get a discount greater than the max discount
        if (discountDecayTime >= discountApplicationPeriod) {
            return maxDiscount;
        }

        /// return the discount as a percentage of the max discount
        return (maxDiscount * discountDecayTime) / discountApplicationPeriod;
    }

    /// @notice Calculates the amount of WELL needed to purchase a given amount of reserves
    /// @param amountReserveAssetIn The amount of reserves to purchase
    /// @return amountWellOut The amount of WELL needed to purchase the given amount of reserves
    /// @dev Uses Chainlink price feeds and applies current discount if applicable
    function getAmountWellOut(
        uint256 amountReserveAssetIn
    ) public view returns (uint256 amountWellOut) {
        /// get the current WELL price in USD
        uint256 normalizedWellPrice;
        {
            (int256 wellPrice, uint8 wellDecimals) = getPriceAndDecimals(
                wellChainlinkFeed
            );
            normalizedWellPrice = scalePrice(wellPrice, wellDecimals, 18)
                .toUint256();
        }

        /// get the current reserve asset price in USD
        uint256 normalizedReservePrice;
        {
            (int256 reservePrice, uint8 reserveDecimals) = getPriceAndDecimals(
                reserveChainlinkFeed
            );
            normalizedReservePrice = scalePrice(
                reservePrice,
                reserveDecimals,
                18
            ).toUint256();
        }

        /// if we are in the discount period, apply the discount to the reserve asset price
        ///    reserve asset price = reserve asset price * (1 - discount)
        {
            uint256 discount = currentDiscount();
            if (discount > 0) {
                normalizedReservePrice =
                    (normalizedReservePrice * (SCALAR - discount)) /
                    SCALAR;
            }
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
        /// get the current WELL price in USD

        uint256 normalizedWellPrice;
        {
            (int256 wellPrice, uint8 wellDecimals) = getPriceAndDecimals(
                wellChainlinkFeed
            );
            normalizedWellPrice = scalePrice(wellPrice, wellDecimals, 18)
                .toUint256();
        }

        /// get the current reserve asset price in USD
        uint256 normalizedReservePrice;
        {
            (int256 reservePrice, uint8 reserveDecimals) = getPriceAndDecimals(
                reserveChainlinkFeed
            );
            normalizedReservePrice = scalePrice(
                reservePrice,
                reserveDecimals,
                18
            ).toUint256();
        }

        /// multiply the amount of WELL by WELL price in USD, result is still scaled up by 18
        uint256 wellAmountUSD = amountWellIn * normalizedWellPrice;

        /// if we are in the discount period, apply the discount to the reserve asset price
        ///    reserve asset price = reserve asset price * (1 - discount)
        {
            uint256 discount = currentDiscount();
            if (discount > 0) {
                normalizedReservePrice =
                    (normalizedReservePrice * (SCALAR - discount)) /
                    SCALAR;
            }
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

    /// @notice Sets the maximum discount that can be applied during sales
    /// @param newMaxDiscount The new maximum discount value (must be less than 1e18)
    function setMaxDiscount(uint256 newMaxDiscount) external onlyOwner {
        require(
            newMaxDiscount < SCALAR,
            "ReserveAutomationModule: max discount must be less than 1"
        );
        uint256 previousMaxDiscount = maxDiscount;
        maxDiscount = newMaxDiscount;

        emit MaxDiscountUpdate(previousMaxDiscount, newMaxDiscount);
    }

    /// @notice Sets the period before discounts start applying
    /// @param newNonDiscountPeriod The new non-discount period duration
    function setNonDiscountPeriod(
        uint256 newNonDiscountPeriod
    ) external onlyOwner {
        uint256 previousNonDiscountPeriod = nonDiscountPeriod;
        nonDiscountPeriod = newNonDiscountPeriod;

        emit NonDiscountPeriodUpdate(
            previousNonDiscountPeriod,
            newNonDiscountPeriod
        );
    }

    /// @notice Sets the window over which the discount decays
    /// @param decayWindow The new decay window duration
    function setDiscountApplicationPeriod(
        uint256 decayWindow
    ) external onlyOwner {
        uint256 previousDecayWindow = discountApplicationPeriod;
        discountApplicationPeriod = decayWindow;

        emit DecayWindowUpdate(previousDecayWindow, decayWindow);
    }

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

    /// @notice Cancels an auction that has been initiated but not yet started
    /// @dev Only callable by guardian, and only when auction is in waiting period
    /// After cancelling, the guardian's role is revoked
    function cancelAuction() external {
        require(
            msg.sender == guardian,
            "ReserveAutomationModule: only guardian"
        );

        uint256 amount = periodSaleAmount;

        saleStartTime = 0;
        periodSaleAmount = 0;
        lastBidTime = 0;
        _saleRateLimit.bufferStored = 0;
        _saleRateLimit.bufferCap = 0;
        _saleRateLimit.rateLimitPerSecond = 0;

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
    /// @dev Applies current discount and updates rate limiting buffer
    /// The discount mechanism is designed with the following considerations:
    /// 1. For purchases greater than a full period's rate limit, lastBidTime is set to current time
    /// 2. For smaller purchases, lastBidTime increases proportionally to amount purchased
    /// 3. While there's a theoretical edge case where users could maintain discounts with repeated
    ///    partial purchases, this is mitigated by:
    ///    - Gas costs making small frequent purchases unprofitable
    ///    - MEV bots naturally arbitraging when discounts become profitable
    ///    - Market competition driving efficient price discovery
    function getReserves(
        uint256 amountWellIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        /// check that the sale is active
        require(
            saleStartTime > 0 &&
                block.timestamp >= saleStartTime &&
                block.timestamp < saleStartTime + SALE_WINDOW,
            "ReserveAutomationModule: sale not active"
        );

        require(amountWellIn != 0, "ReserveAutomationModule: amount in is 0");

        amountOut = getAmountReservesOut(amountWellIn);
        uint256 currBuffer = buffer();

        /// check that the amount of reserves is less than or equal to the buffer
        require(
            amountOut <= currBuffer,
            "ReserveAutomationModule: amount bought exceeds buffer"
        );

        /// check that the amount of reserves is less than the total amount of reserves
        require(
            amountOut >= minAmountOut,
            "ReserveAutomationModule: not enough out"
        );

        uint256 discount = currentDiscount();

        /// deplete the buffer by the amount of reserves being sold
        _saleRateLimit.depleteBuffer(amountOut);

        /// desired behavior:
        ///     lastBidTime increases to the current timestamp based on the %
        ///     of the buffer that was used

        /// if the amount of reserves is greater than or equal to buffer from a single sale period,
        /// then we can set lastBidTime to the current timestamp
        if (
            amountOut >=
            (nonDiscountPeriod + discountApplicationPeriod) *
                rateLimitPerSecond()
        ) {
            lastBidTime = block.timestamp;
        } else {
            /// never allow lastBidTime increase based on a period longer than the maximum time difference
            uint256 maxTimeDiff = nonDiscountPeriod + discountApplicationPeriod;
            uint256 actualTimeDiff = block.timestamp - lastBidTime;
            uint256 effectiveTimeDiff = actualTimeDiff > maxTimeDiff
                ? maxTimeDiff
                : actualTimeDiff;

            lastBidTime += ((effectiveTimeDiff * amountOut) / currBuffer);
        }

        /// transfer the WELL tokens from the user to the recipient contract address
        IERC20(wellToken).safeTransferFrom(
            msg.sender,
            recipientAddress,
            amountWellIn
        );

        /// transfer the reserves from the contract to the user
        IERC20(reserveAsset).safeTransfer(msg.sender, amountOut);

        emit ReservesPurchased(msg.sender, amountWellIn, amountOut, discount);
    }

    /// @notice Initiates a new sale of reserves
    /// @param delay The time to wait before starting the sale
    /// @dev Can only be called if there are no active sales and there are reserves available
    function initiateSale(uint256 delay) external onlyOwner {
        require(
            saleStartTime == 0 || block.timestamp > saleStartTime + SALE_WINDOW,
            "ReserveAutomationModule: sale already active"
        );
        periodSaleAmount = IERC20(reserveAsset).balanceOf(address(this));
        require(
            periodSaleAmount > 0,
            "ReserveAutomationModule: no reserves to sell"
        );
        require(
            delay <= MAXIMUM_AUCTION_DELAY,
            "ReserveAutomationModule: delay exceeds max"
        );

        saleStartTime = block.timestamp + delay;

        /// set the last bid time to the current time so that the discount is
        /// not immediately applied
        lastBidTime = block.timestamp + delay;

        /// since we use safecast, we are assuming we never sell more than
        /// 2^128 - 1 tokens. We think this is a safe assumption due to the
        /// token prices and decimals of assets we are working with

        /// set the buffer cap to the total amount of reserves
        _saleRateLimit.setBufferCap(periodSaleAmount.toUint128());
        /// set the rate limit to the amount of reserves that can be sold per second
        _saleRateLimit.setRateLimitPerSecond(
            (periodSaleAmount / SALE_WINDOW).toUint128()
        );
        /// set the buffer to 0 so that it can replenish over time
        _saleRateLimit.bufferStored = 0;

        emit SaleInitiated(saleStartTime, periodSaleAmount);
    }
}
