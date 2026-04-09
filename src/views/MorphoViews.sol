// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MToken} from "@protocol/MToken.sol";
import {IMorpho, IIrm, IOracle, MarketParams as MorphoMarketParams, Market as MorphoMarket, Id, Position as MorphoPosition} from "@protocol/views/MorphoBlueInterface.sol";
import {IMetaMorpho} from "@protocol/views/MetaMorphoInterface.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";

/**
 * @title Moonwell Morpho Views Contract
 * @author Moonwell
 */
contract MorphoViews is Initializable {
    uint256 constant WAD = 1e18;
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;
    uint256 internal constant POSITION_SLOT = 2;
    uint256 internal constant SUPPLY_SHARES_OFFSET = 0;
    uint256 internal constant BORROW_SHARES_AND_COLLATERAL_OFFSET = 1;

    struct UserMarketBalance {
        Id marketId;
        address collateralToken;
        uint collateralAssets;
        address loanToken;
        uint loanAssets;
        uint loanShares;
    }

    struct MorphoBlueMarket {
        Id marketId;
        address collateralToken;
        string collateralName;
        string collateralSymbol;
        uint collateralDecimals;
        uint collateralPrice;
        address loanToken;
        string loanName;
        string loanSymbol;
        uint loanDecimals;
        uint loanPrice;
        uint totalSupplyAssets;
        uint totalBorrowAssets;
        uint totalLiquidity;
        uint lltv;
        uint supplyApy;
        uint borrowApy;
        uint fee;
        address oracle;
        uint256 oraclePrice;
        address irm;
    }

    struct MorphoVaultMarketsInfo {
        Id marketId;
        address marketCollateral;
        string marketCollateralName;
        string marketCollateralSymbol;
        uint marketLiquidity;
        uint marketLltv;
        uint marketApy;
        uint vaultAllocation;
        uint vaultSupplied;
    }

    struct MorphoVault {
        address vault;
        uint totalSupply;
        uint totalAssets;
        uint underlyingPrice;
        uint fee;
        uint timelock;
        MorphoVaultMarketsInfo[] markets;
    }

    Comptroller public comptroller;
    IMorpho public morpho;

    /// construct the logic contract and initialize so that the initialize function is uncallable
    /// from the implementation and only callable from the proxy
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _comptroller,
        address _morpho
    ) external initializer {
        // Sanity check the params
        require(
            _comptroller != address(0),
            "Comptroller cant be the 0 address!"
        );

        comptroller = Comptroller(payable(_comptroller));

        require(
            comptroller.isComptroller(),
            "Cant bind to something thats not a comptroller!"
        );

        morpho = IMorpho(_morpho);
    }

    /// @dev Returns (`x` * `y`) / `WAD` rounded down.
    function wMulDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD);
    }

    /// @dev Returns (`x` * `WAD`) / `y` rounded down.
    function wDivDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y);
    }

    /// @dev Returns (`x` * `WAD`) / `y` rounded up.
    function wDivUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, WAD, y);
    }

    /// @dev Returns (`x` * `y`) / `d` rounded down.
    function mulDivDown(
        uint256 x,
        uint256 y,
        uint256 d
    ) internal pure returns (uint256) {
        return (x * y) / d;
    }

    /// @dev Returns (`x` * `y`) / `d` rounded up.
    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 d
    ) internal pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }

    /// @dev Returns the sum of the first three non-zero terms of a Taylor expansion of e^(nx) - 1, to approximate a
    /// continuous compound interest rate.
    function wTaylorCompounded(
        uint256 x,
        uint256 n
    ) internal pure returns (uint256) {
        uint256 firstTerm = x * n;
        uint256 secondTerm = mulDivDown(firstTerm, firstTerm, 2 * WAD);
        uint256 thirdTerm = mulDivDown(secondTerm, firstTerm, 3 * WAD);

        return firstTerm + secondTerm + thirdTerm;
    }

    /// @dev Returns `x` safely cast to uint128.
    function toUint128(uint256 x) internal pure returns (uint128) {
        require(x <= type(uint128).max, "MAX_UINT128_EXCEEDED");
        return uint128(x);
    }

    /// @dev Calculates the value of `shares` quoted in assets, rounding up.
    function toAssetsUp(
        uint256 shares,
        uint256 totalAssets,
        uint256 totalShares
    ) internal pure returns (uint256) {
        return
            mulDivUp(
                shares,
                totalAssets + VIRTUAL_ASSETS,
                totalShares + VIRTUAL_SHARES
            );
    }

    /// @dev Calculates the value of `assets` quoted in shares, rounding down.
    function toSharesDown(
        uint256 assets,
        uint256 totalAssets,
        uint256 totalShares
    ) internal pure returns (uint256) {
        return
            mulDivDown(
                assets,
                totalShares + VIRTUAL_SHARES,
                totalAssets + VIRTUAL_ASSETS
            );
    }

    /// @dev Calculates the value of `shares` quoted in assets, rounding down.
    function toAssetsDown(
        uint256 shares,
        uint256 totalAssets,
        uint256 totalShares
    ) internal pure returns (uint256) {
        return
            mulDivDown(
                shares,
                totalAssets + VIRTUAL_ASSETS,
                totalShares + VIRTUAL_SHARES
            );
    }

    /// @notice Returns the expected market balances of a market after having accrued interest.
    /// @return The expected total supply assets.
    /// @return The expected total supply shares.
    /// @return The expected total borrow assets.
    /// @return The expected total borrow shares.
    function expectedMarketBalances(
        MorphoMarket memory market,
        MorphoMarketParams memory marketParams
    ) internal view returns (uint256, uint256, uint256, uint256) {
        uint256 elapsed = block.timestamp - market.lastUpdate;

        // Skipped if elapsed == 0 or totalBorrowAssets == 0 because interest would be null, or if irm == address(0).
        if (
            elapsed != 0 &&
            market.totalBorrowAssets != 0 &&
            marketParams.irm != address(0)
        ) {
            uint256 borrowRate = IIrm(marketParams.irm).borrowRateView(
                marketParams,
                market
            );
            uint256 interest = wMulDown(
                market.totalBorrowAssets,
                wTaylorCompounded(borrowRate, elapsed)
            );
            market.totalBorrowAssets += toUint128(interest);
            market.totalSupplyAssets += toUint128(interest);

            if (market.fee != 0) {
                uint256 feeAmount = wMulDown(interest, market.fee);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact
                // that total supply is already updated.
                uint256 feeShares = toSharesDown(
                    feeAmount,
                    market.totalSupplyAssets - feeAmount,
                    market.totalSupplyShares
                );
                market.totalSupplyShares += toUint128(feeShares);
            }
        }

        return (
            market.totalSupplyAssets,
            market.totalSupplyShares,
            market.totalBorrowAssets,
            market.totalBorrowShares
        );
    }

    function morphoBlueBorrowAPY(
        MorphoMarketParams memory marketParams,
        MorphoMarket memory market
    ) public view returns (uint256 borrowApy) {
        if (marketParams.irm != address(0)) {
            borrowApy = wTaylorCompounded(
                IIrm(marketParams.irm).borrowRateView(marketParams, market),
                365 days
            );
        }
    }

    function morphoBlueSupplyAPY(
        MorphoMarketParams memory marketParams,
        MorphoMarket memory market
    ) public view returns (uint256 supplyApy) {
        (
            uint256 totalSupplyAssets,
            ,
            uint256 totalBorrowAssets,

        ) = expectedMarketBalances(market, marketParams);

        if (marketParams.irm != address(0)) {
            uint256 utilization = totalBorrowAssets == 0
                ? 0
                : wDivUp(totalBorrowAssets, totalSupplyAssets);
            supplyApy = wMulDown(
                wMulDown(
                    morphoBlueBorrowAPY(marketParams, market),
                    1 ether - market.fee
                ),
                utilization
            );
        }
    }

    function getChainlinkPrice(
        AggregatorV3Interface feed
    ) internal view returns (uint256) {
        (, int256 answer, , uint256 updatedAt, ) = AggregatorV3Interface(feed)
            .latestRoundData();
        require(answer > 0, "Chainlink price cannot be lower than 0");
        require(updatedAt != 0, "Round is in incompleted state");

        // Chainlink USD-denominated feeds store answers at 8 decimals
        uint256 decimalDelta = feed.decimals() > 18 ? 0 : 18 - feed.decimals();
        // Ensure that we don't multiply the result by 0
        if (decimalDelta > 0) {
            return uint256(answer) * (10 ** decimalDelta);
        } else {
            return uint256(answer);
        }
    }

    /// @notice A view to get a specific market info
    function getVaultMarketInfo(
        Id _marketId,
        IMorpho _morpho,
        IMetaMorpho _vault
    ) external view returns (MorphoVaultMarketsInfo memory) {
        MorphoVaultMarketsInfo memory _market;

        MorphoMarketParams memory _marketParams = _morpho.idToMarketParams(
            _marketId
        );

        MorphoMarket memory _marketState = _morpho.market(_marketId);

        MorphoPosition memory _position = _morpho.position(
            _marketId,
            address(_vault)
        );

        (
            uint totalSupplyAssets,
            uint totalSupplyShares,
            uint totalBorrowAssets,

        ) = expectedMarketBalances(_marketState, _marketParams);

        if (
            totalSupplyAssets != 0 && address(_marketParams.irm) != address(0)
        ) {
            uint256 borrowRate = IIrm(_marketParams.irm).borrowRateView(
                _marketParams,
                _marketState
            );

            uint borrowAPY = wTaylorCompounded(borrowRate, (3600 * 24 * 365));

            uint utilization = wDivUp(totalBorrowAssets, totalSupplyAssets);

            _market.marketApy = wMulDown(
                wMulDown(borrowAPY, WAD - _marketState.fee),
                utilization
            );
        }

        uint supplyAssetsUser = toAssetsDown(
            _position.supplyShares,
            totalSupplyAssets,
            totalSupplyShares
        );

        _market.marketCollateral = _marketParams.collateralToken;
        if (_market.marketCollateral != address(0)) {
            _market.marketCollateralName = MToken(_marketParams.collateralToken)
                .name();
            _market.marketCollateralSymbol = MToken(
                _marketParams.collateralToken
            ).symbol();
        }
        _market.marketId = _marketId;
        _market.marketLiquidity = (_marketParams.lltv > 0 &&
            totalSupplyAssets > totalBorrowAssets)
            ? totalSupplyAssets - totalBorrowAssets
            : 0;
        _market.marketLltv = _marketParams.lltv;
        _market.vaultSupplied = supplyAssetsUser;

        return _market;
    }

    /// @notice A view to get a specific market info
    function getVaultInfo(
        IMetaMorpho _vault
    ) external view returns (MorphoVault memory) {
        MorphoVault memory _result;

        AggregatorV3Interface priceFeed = ChainlinkOracle(
            address(comptroller.oracle())
        ).getFeed(MToken(_vault.asset()).symbol());

        if (address(priceFeed) != address(0)) {
            _result.underlyingPrice = getChainlinkPrice(priceFeed);
        }

        _result.fee = _vault.fee();
        _result.timelock = _vault.timelock();
        _result.totalAssets = _vault.totalAssets();
        _result.totalSupply = _vault.totalSupply();
        _result.vault = address(_vault);

        _result.markets = new MorphoVaultMarketsInfo[](
            _vault.withdrawQueueLength()
        );

        for (uint index = 0; index < _result.markets.length; index++) {
            Id _marketId = _vault.withdrawQueue(index);
            _result.markets[index] = this.getVaultMarketInfo(
                _marketId,
                _vault.MORPHO(),
                _vault
            );
        }

        return _result;
    }

    /// @notice A view to return vaults config
    function getVaultsInfo(
        address[] calldata morphoVaults
    ) external view returns (MorphoVault[] memory) {
        MorphoVault[] memory _result = new MorphoVault[](morphoVaults.length);

        for (uint256 index = 0; index < morphoVaults.length; index++) {
            _result[index] = this.getVaultInfo(
                IMetaMorpho(morphoVaults[index])
            );
        }

        return _result;
    }

    /// @notice A view to get a specific market info
    function getMorphoBlueMarketInfo(
        Id _marketId
    ) external view returns (MorphoBlueMarket memory) {
        MorphoBlueMarket memory _result;

        MorphoMarketParams memory _marketParams = morpho.idToMarketParams(
            _marketId
        );

        MorphoMarket memory _marketState = morpho.market(_marketId);

        _result.marketId = _marketId;
        _result.loanToken = _marketParams.loanToken;

        _result.collateralToken = _marketParams.collateralToken;
        _result.loanToken = _marketParams.loanToken;

        if (_result.collateralToken != address(0)) {
            _result.collateralSymbol = MToken(_result.collateralToken).symbol();
            _result.collateralName = MToken(_result.collateralToken).name();
            _result.collateralDecimals = MToken(_result.collateralToken)
                .decimals();

            AggregatorV3Interface priceFeed = ChainlinkOracle(
                address(comptroller.oracle())
            ).getFeed(_result.collateralSymbol);

            if (address(priceFeed) != address(0)) {
                _result.collateralPrice = getChainlinkPrice(priceFeed);
            }
        }

        if (_result.loanToken != address(0)) {
            _result.loanSymbol = MToken(_result.loanToken).symbol();
            _result.loanName = MToken(_result.loanToken).name();
            _result.loanDecimals = MToken(_result.loanToken).decimals();

            AggregatorV3Interface priceFeed = ChainlinkOracle(
                address(comptroller.oracle())
            ).getFeed(_result.loanSymbol);

            if (address(priceFeed) != address(0)) {
                _result.loanPrice = getChainlinkPrice(priceFeed);
            }
        }

        _result.borrowApy = this.morphoBlueBorrowAPY(
            _marketParams,
            _marketState
        );

        _result.supplyApy = this.morphoBlueSupplyAPY(
            _marketParams,
            _marketState
        );

        (
            uint256 totalSupplyAssets,
            ,
            uint256 totalBorrowAssets,

        ) = expectedMarketBalances(_marketState, _marketParams);

        _result.totalSupplyAssets = totalSupplyAssets;
        _result.totalBorrowAssets = totalBorrowAssets;

        _result.totalLiquidity = totalSupplyAssets > totalBorrowAssets
            ? totalSupplyAssets - totalBorrowAssets
            : 0;

        _result.fee = _marketState.fee;
        _result.irm = _marketParams.irm;
        _result.lltv = _marketParams.lltv;
        _result.oracle = _marketParams.oracle;

        if (_result.oracle != address(0)) {
            _result.oraclePrice = IOracle(_result.oracle).price();
        }

        return _result;
    }

    /// @notice A view to enumerate all market configs
    function getMorphoBlueMarketsInfo(
        Id[] calldata _marketIds
    ) external view returns (MorphoBlueMarket[] memory) {
        MorphoBlueMarket[] memory _result = new MorphoBlueMarket[](
            _marketIds.length
        );

        for (uint256 index = 0; index < _marketIds.length; index++) {
            _result[index] = this.getMorphoBlueMarketInfo(_marketIds[index]);
        }

        return _result;
    }

    function _array(bytes32 x) private pure returns (bytes32[] memory) {
        bytes32[] memory res = new bytes32[](1);
        res[0] = x;
        return res;
    }

    function positionSupplySharesSlot(
        Id id,
        address user
    ) internal pure returns (bytes32) {
        return
            bytes32(
                uint256(
                    keccak256(
                        abi.encode(
                            user,
                            keccak256(abi.encode(id, POSITION_SLOT))
                        )
                    )
                ) + SUPPLY_SHARES_OFFSET
            );
    }

    function positionBorrowSharesAndCollateralSlot(
        Id id,
        address user
    ) internal pure returns (bytes32) {
        return
            bytes32(
                uint256(
                    keccak256(
                        abi.encode(
                            user,
                            keccak256(abi.encode(id, POSITION_SLOT))
                        )
                    )
                ) + BORROW_SHARES_AND_COLLATERAL_OFFSET
            );
    }

    function supplyShares(Id id, address user) internal view returns (uint256) {
        bytes32[] memory slot = _array(positionSupplySharesSlot(id, user));
        return uint256(morpho.extSloads(slot)[0]);
    }

    function borrowShares(Id id, address user) internal view returns (uint256) {
        bytes32[] memory slot = _array(
            positionBorrowSharesAndCollateralSlot(id, user)
        );
        return uint128(uint256(morpho.extSloads(slot)[0]));
    }

    function collateral(Id id, address user) internal view returns (uint256) {
        bytes32[] memory slot = _array(
            positionBorrowSharesAndCollateralSlot(id, user)
        );
        return uint256(morpho.extSloads(slot)[0] >> 128);
    }

    function expectedBorrowBalance(
        Id id,
        MorphoMarketParams memory marketParams,
        MorphoMarket memory market,
        address user
    ) internal view returns (uint256, uint256) {
        uint256 _borrowShares = borrowShares(id, user);
        (
            ,
            ,
            uint256 totalBorrowAssets,
            uint256 totalBorrowShares
        ) = expectedMarketBalances(market, marketParams);

        return (
            _borrowShares,
            toAssetsUp(_borrowShares, totalBorrowAssets, totalBorrowShares)
        );
    }

    /// @notice A view to get a specific market info
    function getMorphoBlueUserBalance(
        Id _marketId,
        address user
    ) external view returns (UserMarketBalance memory) {
        UserMarketBalance memory _result;

        MorphoMarketParams memory _marketParams = morpho.idToMarketParams(
            _marketId
        );

        MorphoMarket memory _marketState = morpho.market(_marketId);

        _result.marketId = _marketId;
        _result.collateralToken = _marketParams.collateralToken;
        _result.collateralAssets = collateral(_marketId, user);

        (uint256 loanShares, uint256 loanAssets) = expectedBorrowBalance(
            _marketId,
            _marketParams,
            _marketState,
            user
        );

        _result.loanToken = _marketParams.loanToken;
        _result.loanShares = loanShares;
        _result.loanAssets = loanAssets;

        return _result;
    }

    /// @notice A view to enumerate all market configs
    function getMorphoBlueUserBalances(
        Id[] calldata _marketIds,
        address user
    ) external view returns (UserMarketBalance[] memory) {
        UserMarketBalance[] memory _result = new UserMarketBalance[](
            _marketIds.length
        );

        for (uint256 index = 0; index < _marketIds.length; index++) {
            _result[index] = this.getMorphoBlueUserBalance(
                _marketIds[index],
                user
            );
        }

        return _result;
    }
}
