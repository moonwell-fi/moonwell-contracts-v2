pragma solidity =0.8.19;

import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {ERC20Mover} from "@protocol/market/ERC20Mover.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {RateLimitCommonLibrary} from "@zelt/src/lib/RateLimitCommonLibrary.sol";
import {RateLimit, RateLimitedLibrary} from "@zelt/src/lib/RateLimitedLibrary.sol";

contract ReserveAutomation is ERC20Mover {
    using RateLimitCommonLibrary for RateLimit;
    using RateLimitedLibrary for RateLimit;
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice period of time the sale is open for
    uint256 public constant SALE_WINDOW = 14 days;

    /// @notice the value to scale values
    uint256 public constant SCALAR = 1e18;

    /// ------------------------------------------------------------
    /// ------------------------------------------------------------
    /// --------------------- Mutable Variables --------------------
    /// ------------------------------------------------------------
    /// ------------------------------------------------------------

    /// @notice maximum discount in percentage terms scaled to 1e18
    /// must be less than 1 (1e18) as no discounts over or equal to 100% are allowed
    uint256 public maxDiscount;

    /// @notice the duration the discount decays over
    uint256 public discountDecayPeriod;

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

    /// @notice the end time of the sale period
    uint256 public saleEndTime;

    /// @notice set to the contract balance when a sale is initiated
    uint256 public periodSaleAmount;

    /// @notice the rate limit on the reserve sale, how many units can be sold
    /// per second
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
        uint256 maxDiscount;
        uint256 discountDecayPeriod;
        uint256 nonDiscountPeriod;
        address recipientAddress;
        address wellToken;
        address reserveAsset;
        address wellChainlinkFeed;
        address reserveChainlinkFeed;
    }

    /// ------------------------------------------------------------
    /// ------------------------------------------------------------
    /// -------------------------- Events --------------------------
    /// ------------------------------------------------------------
    /// ------------------------------------------------------------

    /// @notice emitted when reserves are purchased
    event ReservesPurchased(
        address indexed buyer,
        uint256 amountWellIn,
        uint256 amountOut,
        uint256 discount
    );

    /// @notice emitted when a sale is started
    event SaleInitiated(uint256 saleEndTime, uint256 periodSaleAmount);

    /// @notice emitted when the maximum discount is updated
    event MaxDiscountUpdate(
        uint256 previousMaxDiscount,
        uint256 newMaxDiscount
    );

    /// @notice emitted when the non discount period is updated
    event NonDiscountPeriodUpdate(
        uint256 previousNonDiscountPeriod,
        uint256 newNonDiscountPeriod
    );

    /// @notice emitted when the decay window is updated
    event DecayWindowUpdate(
        uint256 previousDecayWindow,
        uint256 newDecayWindow
    );

    /// @notice emitted when the recipient address is updated
    event RecipientAddressUpdate(
        address previousRecipient,
        address newRecipient
    );

    /// @notice it is assumed that all params passed to the constructor are correct
    /// this will happen by checking the state variables in the deployed contract
    /// @param params the parameters to initialize the contract with
    /// @param _owner the owner of the contract
    constructor(InitParams memory params, address _owner) ERC20Mover(_owner) {
        maxDiscount = params.maxDiscount;
        discountDecayPeriod = params.discountDecayPeriod;
        nonDiscountPeriod = params.nonDiscountPeriod;
        recipientAddress = params.recipientAddress;
        wellToken = params.wellToken;
        reserveAsset = params.reserveAsset;
        wellChainlinkFeed = params.wellChainlinkFeed;
        reserveChainlinkFeed = params.reserveChainlinkFeed;
        reserveAssetDecimals = ERC20(params.reserveAsset).decimals();

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

    /// @notice the amount of action used before hitting limit
    /// @dev replenishes at rateLimitPerSecond per second up to bufferCap
    function buffer() public view returns (uint256) {
        return _saleRateLimit.buffer();
    }

    /// @notice the cap of the buffer
    function bufferCap() public view returns (uint256) {
        return _saleRateLimit.bufferCap;
    }

    /// @notice the amount the buffer replenishes towards the midpoint per second
    function rateLimitPerSecond() public view returns (uint256) {
        return _saleRateLimit.rateLimitPerSecond;
    }

    /// @return the current discount. returns 0 if no discount is applied
    function currentDiscount() public view returns (uint256) {
        if (saleEndTime == 0 || block.timestamp > saleEndTime) {
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
        if (discountDecayTime >= discountDecayPeriod) {
            return maxDiscount;
        }

        /// return the discount as a percentage of the max discount
        return (maxDiscount * discountDecayTime) / discountDecayPeriod;
    }

    /// @notice calculates the amount of WELL needed to purchase a given amount of reserves
    /// @param amountReserveAssetOut the amount of reserves to purchase
    /// @return amountWellIn the amount of WELL needed to purchase the given amount of reserves
    function getAmountWellIn(
        uint256 amountReserveAssetOut
    ) public view returns (uint256 amountWellIn) {
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
            amountReserveAssetOut =
                amountReserveAssetOut *
                (10 ** uint256(18 - reserveAssetDecimals));
        }

        /// calculate the reserve asset dollar value
        uint256 reserveAssetValue = amountReserveAssetOut *
            normalizedReservePrice;

        /// divide the reserve asset amount out by the WELL price in USD
        /// since both are scaled by 1e18, the result loses the scaling
        amountWellIn = reserveAssetValue / normalizedWellPrice;
    }

    /// @notice returns the amount of reserves that can be purchased at the
    /// current market price of the reserve asset with the given amount of WELL
    /// @param amountWellIn the amount of WELL tokens to purchase reserves with
    /// @return amountOut the amount of reserves that can be purchased with the given amount of WELL
    /// @dev this function does not revert if the amount of reserves is greater than the buffer
    function getAmountOut(
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

    /// @notice sets the maximum discount applied in percentage terms during the discount window
    function setMaxDiscount(uint256 newMaxDiscount) external onlyOwner {
        require(
            newMaxDiscount < 1e18,
            "ReserveAutomationModule: max discount must be less than 1"
        );
        uint256 previousMaxDiscount = maxDiscount;
        maxDiscount = newMaxDiscount;

        emit MaxDiscountUpdate(previousMaxDiscount, newMaxDiscount);
    }

    /// @notice sets the non discount period
    /// @param newNonDiscountPeriod the new non discount period
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

    /// @notice sets the decay window for the discount
    /// @param decayWindow the new decay window
    function setDecayWindow(uint256 decayWindow) external onlyOwner {
        uint256 previousDecayWindow = discountDecayPeriod;
        discountDecayPeriod = decayWindow;

        emit DecayWindowUpdate(previousDecayWindow, decayWindow);
    }

    /// @notice sets the recipient address for the sale proceeds
    function setRecipientAddress(address recipient) external onlyOwner {
        address previousRecipient = recipientAddress;
        recipientAddress = recipient;

        emit RecipientAddressUpdate(previousRecipient, recipient);
    }

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// ------------------ Mutative Functions ----------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @notice allows a user to purchase reserves in exchange for WELL tokens
    /// @param amountWellIn the amount of WELL tokens to purchase reserves with
    /// @param minAmountOut the minimum amount of reserves to receive
    /// @return amountOut the amount of reserves received
    function getReserves(
        uint256 amountWellIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        /// check that the sale is active
        require(
            saleEndTime > 0 && block.timestamp < saleEndTime,
            "ReserveAutomationModule: sale not active"
        );

        /// check that the amount of reserves is greater than 0
        require(
            periodSaleAmount > 0,
            "ReserveAutomationModule: no reserves to sell"
        );

        amountOut = getAmountOut(amountWellIn);

        /// check that the amount of reserves is less than the buffer
        require(
            amountOut <= buffer(),
            "ReserveAutomationModule: amount bought exceeds buffer"
        );

        /// check that the amount of reserves is less than the total amount of reserves
        require(
            minAmountOut >= amountOut,
            "ReserveAutomationModule: not enough out"
        );

        uint256 discount = currentDiscount();

        /// deplete the buffer by the amount of reserves being sold
        _saleRateLimit.depleteBuffer(amountOut);

        lastBidTime = block.timestamp;

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

    /// @notice starts the sale of reserves
    /// @dev can only be called if
    ///  - there are no active sales
    ///  - the balance of the reserve asset is greater than 0
    function initiateSale() external {
        require(
            saleEndTime == 0 || saleEndTime + SALE_WINDOW < block.timestamp,
            "ReserveAutomationModule: sale already active"
        );
        periodSaleAmount = IERC20(reserveAsset).balanceOf(address(this));
        require(
            periodSaleAmount > 0,
            "ReserveAutomationModule: no reserves to sell"
        );

        saleEndTime = block.timestamp + SALE_WINDOW;

        /// set the last bid time to the current time so that the discount is
        /// not immediately applied
        lastBidTime = block.timestamp;

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

        emit SaleInitiated(saleEndTime, periodSaleAmount);
    }
}
