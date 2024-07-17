// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin-contracts/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MToken} from "@protocol/MToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MTokenInterface} from "@protocol/MTokenInterfaces.sol";
import {ExponentialNoError} from "@protocol/ExponentialNoError.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";

/**
    @title A multi-asset distributor that tracks mTokens supply/borrows
    @author Octavius - octavius@moonwell.fi

    This contract integrates with the Moonwell Comptroller and manages all reward disbursal and index
    calculations both for the global market indices as well as individual user indices on those markets.
    It is largely the same logic that compound uses, just generalized (meaning that transfers will not
    fail if things can't be sent out, but the excess is accrued on the books to be sent later).

    Each market has an array of configs, each with a unique emission token owned by a specific team/user.
    That owner can adjust supply and borrow emissions, end times, and

    This emitter also supports native assets, but keep in mind that things get complicated with multiple
    owners managing a native asset emitter - one owner can drain the contract by increasing their own

    Delegates admin control to the comptroller's admin (no internal admin controls).

    There is a hard rule that each market should only have 1 config with a specific emission token.

    Emission configs are non-removable because they hold the supplier/borrower indices and that would
    cause rewards to not be disbursed properly when a config is removed.

    There is a pause guardian in this contract that can immediately stop all token emissions. Accruals
    still happen but no tokens will be sent out when the circuit breaker is popped. Much like the pause
    guardians on the Comptroller, only the comptroller's admin can actually unpause things.
*/

contract MultiRewardDistributor is
    Pausable,
    ReentrancyGuard,
    Initializable,
    MultiRewardDistributorCommon,
    ExponentialNoError
{
    using SafeERC20 for IERC20;

    /// @notice The main data storage for this contract, holds a mapping of mToken to array
    //          of market configs
    mapping(address => MarketEmissionConfig[]) public marketConfigs;

    function getUserConfig(
        address mToken,
        address user,
        address emissionToken
    ) public returns (uint256 borrowerIndice, uint256 rewardsAccrued) {
        MarketEmissionConfig
            storage emissionConfig = fetchConfigByEmissionToken(
                MToken(mToken),
                emissionToken
            );

        // borrower indice
        borrowerIndice = emissionConfig.borrowerIndices[emissionToken];
        rewardsAccrued = emissionConfig.borrowerRewardsAccrued[emissionToken];
    }

    /// @notice Comptroller this distributor is bound to
    Comptroller public comptroller; /// we can't make this immutable because we are using proxies

    /// @notice The pause guardian for this contract
    address public pauseGuardian;

    /// @notice The initialIndexConstant, used to initialize indexes, and taken from the Comptroller
    uint224 public constant initialIndexConstant = 1e36;

    /// @notice The emission cap dictates an upper limit for reward speed emission speed configs
    /// @dev By default, is set to 100 1e18 token emissions / sec to avoid unbounded
    ///  computation/multiplication overflows
    uint256 public emissionCap;

    // Some structs we can't move to the interface
    struct CurrentMarketData {
        uint256 totalMTokens;
        uint256 totalBorrows;
        Exp marketBorrowIndex;
    }

    struct CalculatedData {
        CurrentMarketData marketData;
        MTokenData mTokenInfo;
    }

    /// construct the logic contract and initialize so that the initialize function is uncallable
    /// from the implementation and only callable from the proxy
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _comptroller,
        address _pauseGuardian
    ) external initializer {
        // Sanity check the params
        require(
            _comptroller != address(0),
            "Comptroller can't be the 0 address!"
        );
        require(
            _pauseGuardian != address(0),
            "Pause Guardian can't be the 0 address!"
        );

        comptroller = Comptroller(payable(_comptroller));

        require(
            comptroller.isComptroller(),
            "Can't bind to something that's not a comptroller!"
        );

        pauseGuardian = _pauseGuardian;
        emissionCap = 100e18;
    }

    /*
    ====================================================================================================
     ACL Modifiers

     all modifiers allow for the admin to call in to take actions within this contract, the idea being that
     the timelock can act like an owner of the config to set parameters, and act like the comptroller to
     kick the reward index updates, and act like a pause guardian to pause things.
    ====================================================================================================
    */

    /// @notice Only allow the comptroller's admin to take an action, usually the timelock
    modifier onlyComptrollersAdmin() {
        require(
            msg.sender == address(comptroller.admin()),
            "Only the comptroller's administrator can do this!"
        );
        _;
    }

    /// @notice Only allow the comptroller OR the comptroller's admin to take an action
    modifier onlyComptrollerOrAdmin() {
        require(
            msg.sender == address(comptroller) ||
                msg.sender == comptroller.admin(),
            "Only the comptroller or comptroller admin can call this function"
        );
        _;
    }

    /// @notice Only allow the emission config owner OR the comptroller's admin to take an action
    modifier onlyEmissionConfigOwnerOrAdmin(
        MToken _mToken,
        address emissionToken
    ) {
        MarketEmissionConfig
            storage emissionConfig = fetchConfigByEmissionToken(
                _mToken,
                emissionToken
            );
        require(
            msg.sender == emissionConfig.config.owner ||
                msg.sender == comptroller.admin(),
            "Only the config owner or comptroller admin can call this function"
        );
        _;
    }

    /// @notice Only allow the pause guardian OR the comptroller's admin to take an action
    modifier onlyPauseGuardianOrAdmin() {
        require(
            msg.sender == pauseGuardian || msg.sender == comptroller.admin(),
            "Only the pause guardian or comptroller admin can call this function"
        );
        _;
    }

    /*
    ====================================================================================================
     External/publicly accessible API

     The main public API for the contract, generally focused on getting a user's outstanding rewards or
     pulling down specific configs. Users should call `claimRewards` on the comptroller as usual to recv
     their rewards.
    ====================================================================================================
    */

    /**
     * @notice Get the current owner of a config
     * @param _mToken The market to get a config for
     * @param _emissionToken The reward token address
     */
    function getCurrentOwner(
        MToken _mToken,
        address _emissionToken
    ) external view returns (address) {
        MarketEmissionConfig
            storage emissionConfig = fetchConfigByEmissionToken(
                _mToken,
                _emissionToken
            );
        return emissionConfig.config.owner;
    }

    /// @notice A view to enumerate all configs for a given market, does not include index data
    function getAllMarketConfigs(
        MToken _mToken
    ) external view returns (MarketConfig[] memory) {
        MarketEmissionConfig[] storage configs = marketConfigs[
            address(_mToken)
        ];

        MarketConfig[] memory outputMarketConfigs = new MarketConfig[](
            configs.length
        );

        // Pop out the MarketConfigs to return them
        for (uint256 index = 0; index < configs.length; index++) {
            MarketEmissionConfig storage emissionConfig = configs[index];
            outputMarketConfigs[index] = emissionConfig.config;
        }

        return outputMarketConfigs;
    }

    /// @notice A view to get a config for a specific market/emission token pair
    function getConfigForMarket(
        MToken _mToken,
        address _emissionToken
    ) external view returns (MarketConfig memory) {
        MarketEmissionConfig
            storage emissionConfig = fetchConfigByEmissionToken(
                _mToken,
                _emissionToken
            );
        return emissionConfig.config;
    }

    /// @notice A view to enumerate a user's rewards across all markets and all emission tokens
    function getOutstandingRewardsForUser(
        address _user
    ) external view returns (RewardWithMToken[] memory) {
        MToken[] memory markets = comptroller.getAllMarkets();

        RewardWithMToken[] memory outputData = new RewardWithMToken[](
            markets.length
        );

        for (uint256 index = 0; index < markets.length; index++) {
            RewardInfo[] memory rewardInfo = getOutstandingRewardsForUser(
                markets[index],
                _user
            );

            outputData[index] = RewardWithMToken(
                address(markets[index]),
                rewardInfo
            );
        }

        return outputData;
    }

    /// @notice A view to enumerate a user's rewards across a specified market and all emission tokens for that market
    function getOutstandingRewardsForUser(
        MToken _mToken,
        address _user
    ) public view returns (RewardInfo[] memory) {
        // Global config for this mToken
        MarketEmissionConfig[] storage configs = marketConfigs[
            address(_mToken)
        ];

        // Output var
        RewardInfo[] memory outputRewardData = new RewardInfo[](configs.length);

        // Code golf to avoid too many local vars :rolling-eyes:
        CalculatedData memory calcData = CalculatedData({
            marketData: CurrentMarketData({
                totalMTokens: _mToken.totalSupply(),
                totalBorrows: _mToken.totalBorrows(),
                marketBorrowIndex: Exp({mantissa: _mToken.borrowIndex()})
            }),
            mTokenInfo: MTokenData({
                mTokenBalance: _mToken.balanceOf(_user),
                borrowBalanceStored: _mToken.borrowBalanceStored(_user)
            })
        });

        for (uint256 index = 0; index < configs.length; index++) {
            MarketEmissionConfig storage emissionConfig = configs[index];

            // Calculate our new global supply index
            IndexUpdate memory supplyUpdate = calculateNewIndex(
                emissionConfig.config.supplyEmissionsPerSec,
                emissionConfig.config.supplyGlobalTimestamp,
                emissionConfig.config.supplyGlobalIndex,
                emissionConfig.config.endTime,
                calcData.marketData.totalMTokens
            );

            console.log(
                "MRD total borrow: %s",
                calcData.marketData.totalBorrows
            );
            console.log(
                "MRD market borrow index: %s",
                calcData.marketData.marketBorrowIndex.mantissa
            );

            // Calculate our new global borrow index
            IndexUpdate memory borrowUpdate = calculateNewIndex(
                emissionConfig.config.borrowEmissionsPerSec,
                emissionConfig.config.borrowGlobalTimestamp,
                emissionConfig.config.borrowGlobalIndex,
                emissionConfig.config.endTime,
                div_(
                    calcData.marketData.totalBorrows,
                    calcData.marketData.marketBorrowIndex
                )
            );

            // Calculate outstanding supplier side rewards
            uint256 supplierRewardsAccrued = calculateSupplyRewardsForUser(
                emissionConfig,
                supplyUpdate.newIndex,
                calcData.mTokenInfo.mTokenBalance,
                _user
            );

            uint256 borrowerRewardsAccrued = calculateBorrowRewardsForUser(
                emissionConfig,
                borrowUpdate.newIndex,
                calcData.marketData.marketBorrowIndex,
                calcData.mTokenInfo,
                _user
            );

            outputRewardData[index] = RewardInfo({
                emissionToken: emissionConfig.config.emissionToken,
                totalAmount: borrowerRewardsAccrued + supplierRewardsAccrued,
                supplySide: supplierRewardsAccrued,
                borrowSide: borrowerRewardsAccrued
            });
        }

        return outputRewardData;
    }

    /// @notice A view to get the current emission caps
    function getCurrentEmissionCap() external view returns (uint256) {
        return emissionCap;
    }

    /// @notice view to get the cached global supply index for an mToken and emission index
    /// @param mToken The market to get a config for
    /// @param index The index of the config to get
    function getGlobalSupplyIndex(
        address mToken,
        uint256 index
    ) public view returns (uint256) {
        MarketEmissionConfig storage emissionConfig = marketConfigs[mToken][
            index
        ];

        // Set the new values in storage
        return emissionConfig.config.supplyGlobalIndex;
    }

    /// @notice view to get the cached global borrow index for an mToken and emission index
    /// @param mToken The market to get a config for
    /// @param index The index of the config to get
    function getGlobalBorrowIndex(
        address mToken,
        uint256 index
    ) public view returns (uint256) {
        MarketEmissionConfig storage emissionConfig = marketConfigs[mToken][
            index
        ];

        // Set the new values in storage
        return emissionConfig.config.borrowGlobalIndex;
    }

    /*
    ====================================================================================================
     Administrative API

     Should be only callable by the comptroller's admin (usually the timelock), this is the only way
     to add new configurations to the markets. There's also a rescue assets function that will sweep
     tokens out of this contract and to the timelock, the thought being that rescuing accidentally sent
     funds or sweeping existing tokens to a new distributor is possible.
    ====================================================================================================
    */

    /**
     * @notice Add a new emission configuration for a specific market
     * @dev Emission config must not already exist for the specified market (unique to the emission token)
     */
    function _addEmissionConfig(
        MToken _mToken,
        address _owner,
        address _emissionToken,
        uint256 _supplyEmissionPerSec,
        uint256 _borrowEmissionsPerSec,
        uint256 _endTime
    ) external onlyComptrollersAdmin {
        // Ensure market is listed in the comptroller before accepting a config for it (should always be checked
        // in the comptroller first, but never hurts to codify that assertion/requirement here.
        (bool tokenIsListed, ) = comptroller.markets(address(_mToken));
        require(
            tokenIsListed,
            "The market requested to be added is un-listed!"
        );

        // Sanity check emission speeds are below emissionCap
        require(
            _supplyEmissionPerSec < emissionCap,
            "Cannot set a supply reward speed higher than the emission cap!"
        );
        require(
            _borrowEmissionsPerSec < emissionCap,
            "Cannot set a borrow reward speed higher than the emission cap!"
        );

        // Sanity check end time is some time in the future
        require(
            _endTime > block.timestamp + 1,
            "The _endTime parameter must be in the future!"
        );

        MarketEmissionConfig[] storage configs = marketConfigs[
            address(_mToken)
        ];

        // Sanity check to ensure that the emission token doesn't already exist in a config
        for (uint256 index = 0; index < configs.length; index++) {
            MarketEmissionConfig storage mTokenConfig = configs[index];
            require(
                mTokenConfig.config.emissionToken != _emissionToken,
                "Emission token already listed!"
            );
        }

        // Things look good, create a config
        MarketConfig memory config = MarketConfig({
            // Set the owner of the reward distributor config
            owner: _owner,
            // Set the emission token address
            emissionToken: _emissionToken,
            // Set the time that the emission campaign should end at
            endTime: _endTime,
            // Initialize the global supply
            supplyGlobalTimestamp: safe32(
                block.timestamp,
                "block timestamp exceeds 32 bits"
            ),
            supplyGlobalIndex: initialIndexConstant,
            // Initialize the global borrow index + timestamp
            borrowGlobalTimestamp: safe32(
                block.timestamp,
                "block timestamp exceeds 32 bits"
            ),
            borrowGlobalIndex: initialIndexConstant,
            // Set supply and reward borrow speeds
            supplyEmissionsPerSec: _supplyEmissionPerSec,
            borrowEmissionsPerSec: _borrowEmissionsPerSec
        });

        emit NewConfigCreated(
            _mToken,
            _owner,
            _emissionToken,
            _supplyEmissionPerSec,
            _borrowEmissionsPerSec,
            _endTime
        );

        // Go push in our new config
        MarketEmissionConfig storage newConfig = configs.push();
        newConfig.config = config;
    }

    /**
     * @notice Sweep ERC-20 tokens from the comptroller to the admin
     * @param _tokenAddress The address of the token to transfer
     * @param _amount The amount of tokens to sweep, uint256.max means everything
     */
    function _rescueFunds(
        address _tokenAddress,
        uint256 _amount
    ) external onlyComptrollersAdmin {
        IERC20 token = IERC20(_tokenAddress);
        // Similar to mTokens, if this is uint256.max that means "transfer everything"
        if (_amount == type(uint256).max) {
            token.safeTransfer(
                comptroller.admin(),
                token.balanceOf(address(this))
            );
        } else {
            token.safeTransfer(comptroller.admin(), _amount);
        }

        emit FundsRescued(_tokenAddress, _amount);
    }

    /**
     * @notice Sets a new pause guardian, callable by the CURRENT pause guardian or comptroller's admin
     * @param _newPauseGuardian The new pause guardian
     */
    function _setPauseGuardian(
        address _newPauseGuardian
    ) external onlyPauseGuardianOrAdmin {
        require(
            _newPauseGuardian != address(0),
            "Pause Guardian can't be the 0 address!"
        );

        address currentPauseGuardian = pauseGuardian;

        pauseGuardian = _newPauseGuardian;

        emit NewPauseGuardian(currentPauseGuardian, _newPauseGuardian);
    }

    /**
     * @notice Sets a new emission cap for supply/borrow speeds
     * @param _newEmissionCap The new emission cap
     */
    function _setEmissionCap(
        uint256 _newEmissionCap
    ) external onlyComptrollersAdmin {
        uint256 oldEmissionCap = emissionCap;

        emissionCap = _newEmissionCap;

        emit NewEmissionCap(oldEmissionCap, _newEmissionCap);
    }

    /*
    ====================================================================================================
     Comptroller specific API

     This is the main integration points with the Moonwell Comptroller. Within the `allowMint`/`allowBorrow`/etc
     hooks, the comptroller will reach out to kick the global index update (updateMarketIndex) as well as update
     the supplier's/borrower's token specific distribution indices for that market
    ====================================================================================================
    */

    /**
     * @notice Updates the supply indices for a given market
     * @param _mToken The market to update
     */
    function updateMarketSupplyIndex(
        MToken _mToken
    ) external onlyComptrollerOrAdmin {
        updateMarketSupplyIndexInternal(_mToken);
    }

    /**
     * @notice Calculate the deltas in indices between this user's index and the global supplier index for all configs,
     *         and accrue any owed emissions to their supplierRewardsAccrued for this market's configs
     * @param _mToken The market to update
     * @param _supplier The supplier whose index will be updated
     * @param _sendTokens Whether to send tokens as part of calculating owed rewards
     */
    function disburseSupplierRewards(
        MToken _mToken,
        address _supplier,
        bool _sendTokens
    ) external onlyComptrollerOrAdmin {
        disburseSupplierRewardsInternal(_mToken, _supplier, _sendTokens);
    }

    /**
     * @notice Combine the above 2 functions into one that will update the global and user supplier indexes and
     *         disburse rewards
     * @param _mToken The market to update
     * @param _supplier The supplier whose index will be updated
     * @param _sendTokens Whether to send tokens as part of calculating owed rewards
     */
    function updateMarketSupplyIndexAndDisburseSupplierRewards(
        MToken _mToken,
        address _supplier,
        bool _sendTokens
    ) external onlyComptrollerOrAdmin {
        updateMarketSupplyIndexInternal(_mToken);
        disburseSupplierRewardsInternal(_mToken, _supplier, _sendTokens);
    }

    /**
     * @notice Updates the borrow indices for a given market
     * @param _mToken The market to update
     */
    function updateMarketBorrowIndex(
        MToken _mToken
    ) external onlyComptrollerOrAdmin {
        updateMarketBorrowIndexInternal(_mToken);
    }

    /**
     * @notice Calculate the deltas in indices between this user's index and the global borrower index for all configs,
     *         and accrue any owed emissions to their borrowerRewardsAccrued for this market's configs
     * @param _mToken The market to update
     * @param _borrower The borrower whose index will be updated
     * @param _sendTokens Whether to send tokens as part of calculating owed rewards
     */
    function disburseBorrowerRewards(
        MToken _mToken,
        address _borrower,
        bool _sendTokens
    ) external onlyComptrollerOrAdmin {
        disburseBorrowerRewardsInternal(_mToken, _borrower, _sendTokens);
    }

    /**
     * @notice Combine the above 2 functions into one that will update the global and user borrower indexes and
     *         disburse rewards
     * @param _mToken The market to update
     * @param _borrower The borrower whose index will be updated
     * @param _sendTokens Whether to send tokens as part of calculating owed rewards
     */
    function updateMarketBorrowIndexAndDisburseBorrowerRewards(
        MToken _mToken,
        address _borrower,
        bool _sendTokens
    ) external onlyComptrollerOrAdmin {
        updateMarketBorrowIndexInternal(_mToken);
        disburseBorrowerRewardsInternal(_mToken, _borrower, _sendTokens);
    }

    /*
    ====================================================================================================
     Pause Guardian API

     The pause guardian tooling is responsible for toggling on and off actual reward emissions. Things
     will still be accrued as normal, but the `sendRewards` function will simply not attempt to transfer
     any tokens out.

     Similarly to the pause guardians in the Comptroller, when the pause guardian pops this circuit
     breaker, only the comptroller's admin is able to unpause things and get tokens emitting again.
    ====================================================================================================
     */

    /// @notice Pauses reward sending *but not accrual*
    function _pauseRewards() external onlyPauseGuardianOrAdmin {
        _pause();

        emit RewardsPaused();
    }

    /// @notice Unpauses and allows reward sending once again
    function _unpauseRewards() external onlyComptrollersAdmin {
        _unpause();

        emit RewardsUnpaused();
    }

    /*
    ====================================================================================================
     Configuration Owner API

     This is a set of APIs for external parties/emission config owners to update their configs. They're
     able to transfer ownership, update emission speeds, and update the end time for a campaign. Worth
     noting, if the endTime is hit, no more rewards will be accrued, BUT you can call `_updateEndTime`
     to extend the specified campaign - if the campaign has ended already, then rewards will start
     accruing from the time of reactivation.
    ====================================================================================================
     */

    /**
     * @notice Update the supply emissions for a given mToken + emission token pair.
     * @param _mToken The market to change a config for
     * @param _emissionToken The underlying reward token address
     * @param _newSupplySpeed The supply side emission speed denoted in the underlying emission token's decimals
     */
    function _updateSupplySpeed(
        MToken _mToken,
        address _emissionToken,
        uint256 _newSupplySpeed
    ) external onlyEmissionConfigOwnerOrAdmin(_mToken, _emissionToken) {
        MarketEmissionConfig
            storage emissionConfig = fetchConfigByEmissionToken(
                _mToken,
                _emissionToken
            );

        uint256 currentSupplySpeed = emissionConfig
            .config
            .supplyEmissionsPerSec;

        require(
            _newSupplySpeed != currentSupplySpeed,
            "Can't set new supply emissions to be equal to current!"
        );
        require(
            _newSupplySpeed < emissionCap,
            "Cannot set a supply reward speed higher than the emission cap!"
        );

        // Make sure we update our indices before setting the new speed
        updateMarketSupplyIndexInternal(_mToken);

        // Update supply speed
        emissionConfig.config.supplyEmissionsPerSec = _newSupplySpeed;

        emit NewSupplyRewardSpeed(
            _mToken,
            _emissionToken,
            currentSupplySpeed,
            _newSupplySpeed
        );
    }

    /**
     * @notice Update the borrow emissions for a given mToken + emission token pair.
     * @param _mToken The market to change a config for
     * @param _emissionToken The underlying reward token address
     * @param _newBorrowSpeed The borrow side emission speed denoted in the underlying emission token's decimals
     */
    function _updateBorrowSpeed(
        MToken _mToken,
        address _emissionToken,
        uint256 _newBorrowSpeed
    ) external onlyEmissionConfigOwnerOrAdmin(_mToken, _emissionToken) {
        MarketEmissionConfig
            storage emissionConfig = fetchConfigByEmissionToken(
                _mToken,
                _emissionToken
            );

        uint256 currentBorrowSpeed = emissionConfig
            .config
            .borrowEmissionsPerSec;

        require(
            _newBorrowSpeed != currentBorrowSpeed,
            "Can't set new borrow emissions to be equal to current!"
        );
        require(
            _newBorrowSpeed < emissionCap,
            "Cannot set a borrow reward speed higher than the emission cap!"
        );

        // Make sure we update our indices before setting the new speed
        updateMarketBorrowIndexInternal(_mToken);

        // Update borrow speed
        emissionConfig.config.borrowEmissionsPerSec = _newBorrowSpeed;

        emit NewBorrowRewardSpeed(
            _mToken,
            _emissionToken,
            currentBorrowSpeed,
            _newBorrowSpeed
        );
    }

    /**
     * @notice Update the owner of a config
     * @param _mToken The market to change a config for
     * @param _emissionToken The underlying reward token address
     * @param _newOwner The new owner for this config
     */
    function _updateOwner(
        MToken _mToken,
        address _emissionToken,
        address _newOwner
    ) external onlyEmissionConfigOwnerOrAdmin(_mToken, _emissionToken) {
        MarketEmissionConfig
            storage emissionConfig = fetchConfigByEmissionToken(
                _mToken,
                _emissionToken
            );

        address currentOwner = emissionConfig.config.owner;

        emissionConfig.config.owner = _newOwner;
        emit NewEmissionConfigOwner(
            _mToken,
            _emissionToken,
            currentOwner,
            _newOwner
        );
    }

    /**
     * @notice Update the end time for an emission campaign, must be in the future
     * @param _mToken The market to change a config for
     * @param _emissionToken The underlying reward token address
     * @param _newEndTime The new desired end time
     */
    function _updateEndTime(
        MToken _mToken,
        address _emissionToken,
        uint256 _newEndTime
    ) external onlyEmissionConfigOwnerOrAdmin(_mToken, _emissionToken) {
        MarketEmissionConfig
            storage emissionConfig = fetchConfigByEmissionToken(
                _mToken,
                _emissionToken
            );

        uint256 currentEndTime = emissionConfig.config.endTime;

        // Must be older than our existing end time AND the current block
        require(
            _newEndTime > currentEndTime,
            "_newEndTime MUST be > currentEndTime"
        );
        require(
            _newEndTime > block.timestamp,
            "_newEndTime MUST be > block.timestamp"
        );

        // Update both global indices before setting the new end time. If rewards are off this just updates the
        // global block timestamp to the current second
        updateMarketBorrowIndexInternal(_mToken);
        updateMarketSupplyIndexInternal(_mToken);

        emissionConfig.config.endTime = _newEndTime;
        emit NewRewardEndTime(
            _mToken,
            _emissionToken,
            currentEndTime,
            _newEndTime
        );
    }

    /*
    ====================================================================================================
     Internal functions

     Internal functions used by other parts of this contract, views first then mutation functions
    ====================================================================================================
    */

    /**
     * @notice An internal view to calculate the total owed supplier rewards for a given supplier address
     * @param _emissionConfig The emission config to read index data from
     * @param _globalSupplyIndex The global supply index for a market
     * @param _supplierTokens The amount of this market's mTokens owned by a user
     * @param _supplier The address of the supplier
     */
    function calculateSupplyRewardsForUser(
        MarketEmissionConfig storage _emissionConfig,
        uint224 _globalSupplyIndex,
        uint256 _supplierTokens,
        address _supplier
    ) internal view returns (uint256) {
        uint256 userSupplyIndex = _emissionConfig.supplierIndices[_supplier];

        // If our user's index isn't set yet, set to the current global supply index
        if (
            userSupplyIndex == 0 && _globalSupplyIndex >= initialIndexConstant
        ) {
            userSupplyIndex = initialIndexConstant; //_globalSupplyIndex;
        }

        // Calculate change in the cumulative sum of the reward per cToken accrued
        Double memory deltaIndex = Double({
            mantissa: sub_(_globalSupplyIndex, userSupplyIndex)
        });

        // Calculate reward accrued: cTokenAmount * accruedPerCToken
        uint256 supplierDelta = mul_(_supplierTokens, deltaIndex);

        return
            add_(
                _emissionConfig.supplierRewardsAccrued[_supplier],
                supplierDelta
            );
    }

    /**
     * @notice An internal view to calculate the total owed borrower rewards for a given borrower address
     * @param _emissionConfig The emission config to read index data from
     * @param _globalBorrowIndex The global borrow index for a market
     * @param _marketBorrowIndex The mToken's borrowIndex
     * @param _mTokenData A struct holding a borrower's
     * @param _borrower The address of the supplier mToken balance and borrowed balance
     */
    function calculateBorrowRewardsForUser(
        MarketEmissionConfig storage _emissionConfig,
        uint224 _globalBorrowIndex,
        Exp memory _marketBorrowIndex,
        MTokenData memory _mTokenData,
        address _borrower
    ) internal view returns (uint256) {
        uint256 userBorrowIndex = _emissionConfig.borrowerIndices[_borrower];

        // If our user's index isn't set yet, set to the current global borrow index
        if (
            userBorrowIndex == 0 && _globalBorrowIndex >= initialIndexConstant
        ) {
            userBorrowIndex = initialIndexConstant; //userBorrowIndex = _globalBorrowIndex;
        }

        console.log("MRD userBorrowIndex %s", userBorrowIndex);
        // Calculate change in the cumulative sum of the reward per cToken accrued
        Double memory deltaIndex = Double({
            mantissa: sub_(_globalBorrowIndex, userBorrowIndex)
        });

        console.log("MRD deltaIndex %s", deltaIndex.mantissa);

        uint borrowerAmount = div_(
            _mTokenData.borrowBalanceStored,
            _marketBorrowIndex
        );

        console.log("MRD borrowerAmount %s", borrowerAmount);

        // Calculate reward accrued: mTokenAmount * accruedPerMToken
        uint borrowerDelta = mul_(borrowerAmount, deltaIndex);

        console.log("MRD borrowerDelta %s", borrowerDelta);

        return
            add_(
                _emissionConfig.borrowerRewardsAccrued[_borrower],
                borrowerDelta
            );
    }

    /**
     * @notice An internal view to calculate the global reward indices while taking into account emissions end times.
     * @dev Denominator here is whatever fractional denominator is used to calculate the index. On the supply side
     *      it's simply mToken.totalSupply(), while on the borrow side it's (mToken.totalBorrows() / mToken.borrowIndex())
     * @param _emissionsPerSecond The configured emissions per second for this index
     * @param _currentTimestamp The current index timestamp
     * @param _currentIndex The current index
     * @param _rewardEndTime The end time for this reward config
     * @param _denominator The denominator used in the calculation (supply side == mToken.totalSupply,
     *        borrow side is (mToken.totalBorrows() / mToken.borrowIndex()).
     */
    function calculateNewIndex(
        uint256 _emissionsPerSecond,
        uint32 _currentTimestamp,
        uint224 _currentIndex,
        uint256 _rewardEndTime,
        uint256 _denominator
    ) internal view returns (IndexUpdate memory) {
        uint32 blockTimestamp = safe32(
            block.timestamp,
            "block timestamp exceeds 32 bits"
        );
        uint256 deltaTimestamps = sub_(
            blockTimestamp,
            uint256(_currentTimestamp)
        );

        console.log("blockTimestamp");
        console.log("rewardEndTime", _rewardEndTime);

        // If our current block timestamp is newer than our emission end time, we need to halt
        // reward emissions by stinting the growth of the global index, but importantly not
        // the global timestamp. Should not be gte because the equivalent case makes a
        // 0 deltaTimestamp which doesn't accrue the last bit of rewards properly.
        if (blockTimestamp > _rewardEndTime) {
            // If our current index timestamp is less than our end time it means this
            // is the first time the endTime threshold has been breached, and we have
            // some left over rewards to accrue, so clamp deltaTimestamps to the whatever
            // window of rewards still remains.
            if (_currentTimestamp < _rewardEndTime) {
                deltaTimestamps = sub_(_rewardEndTime, _currentTimestamp);
            } else {
                // Otherwise just set deltaTimestamps to 0 to ensure that we short circuit
                // in the next step
                deltaTimestamps = 0;
            }
        }

        // Short circuit to update the timestamp but *not* the index if there's nothing
        // to calculate
        if (deltaTimestamps == 0 || _emissionsPerSecond == 0) {
            return
                IndexUpdate({
                    newIndex: _currentIndex,
                    newTimestamp: blockTimestamp
                });
        }

        // At this point we know we have to calculate a new index, so do so
        uint256 tokenAccrued = mul_(deltaTimestamps, _emissionsPerSecond);

        console.log(
            "MRD calculateNewIndex: emisisonsPerSecond",
            _emissionsPerSecond
        );
        console.log("MRD calculateNewIndex tokenAccrued", tokenAccrued);

        console.log("_denomintaor", _denominator);
        Double memory ratio = _denominator > 0
            ? fraction(tokenAccrued, _denominator)
            : Double({mantissa: 0});
        console.log("MRD calculateNewIndex totalBorrowed", _denominator);

        console.log("MRD calculateNewIndex updateIndex", ratio.mantissa);

        uint224 newIndex = safe224(
            add_(Double({mantissa: _currentIndex}), ratio).mantissa,
            "new index exceeds 224 bits"
        );

        console.log("current index", _currentIndex);

        console.log("MRD calculateNewIndex: new index", newIndex);

        return IndexUpdate({newIndex: newIndex, newTimestamp: blockTimestamp});
    }

    /**
     * @notice An internal view to find a config for a given market given a specific emission token
     * @dev Reverts if the mtoken + emission token combo could not be found.
     * @param _mToken The market to fetch a config for
     * @param _emissionToken The emission token to fetch a config for
     */
    function fetchConfigByEmissionToken(
        MToken _mToken,
        address _emissionToken
    ) internal view returns (MarketEmissionConfig storage) {
        MarketEmissionConfig[] storage configs = marketConfigs[
            address(_mToken)
        ];
        for (uint256 index = 0; index < configs.length; index++) {
            MarketEmissionConfig storage emissionConfig = configs[index];
            if (emissionConfig.config.emissionToken == _emissionToken) {
                return emissionConfig;
            }
        }

        revert("Unable to find emission token in mToken configs");
    }

    //
    // Internal mutable functions
    //

    /**
     * @notice An internal function to update the global supply index for a given mToken
     * @param _mToken The market to update the global supply index for
     */
    function updateMarketSupplyIndexInternal(MToken _mToken) internal {
        MarketEmissionConfig[] storage configs = marketConfigs[
            address(_mToken)
        ];

        uint256 totalMTokens = MTokenInterface(_mToken).totalSupply();

        // Iterate over all market configs and update their indexes + timestamps
        for (uint256 index = 0; index < configs.length; index++) {
            MarketEmissionConfig storage emissionConfig = configs[index];

            // Go calculate our new values
            IndexUpdate memory supplyUpdate = calculateNewIndex(
                emissionConfig.config.supplyEmissionsPerSec,
                emissionConfig.config.supplyGlobalTimestamp,
                emissionConfig.config.supplyGlobalIndex,
                emissionConfig.config.endTime,
                totalMTokens
            );

            // Set the new values in storage
            emissionConfig.config.supplyGlobalIndex = supplyUpdate.newIndex;
            emissionConfig.config.supplyGlobalTimestamp = supplyUpdate
                .newTimestamp;
            emit GlobalSupplyIndexUpdated(
                _mToken,
                emissionConfig.config.emissionToken,
                supplyUpdate.newIndex,
                supplyUpdate.newTimestamp
            );
        }
    }

    /**
     * @notice An internal function to disburse rewards for the supplier side of a a specific mToken
     * @dev will only send tokens when _sendTokens == true, otherwise just accrue rewards
     * @param _mToken The market to update the global supply index for
     * @param _supplier The supplier to disburse rewards for
     * @param _sendTokens Whether to actually send tokens instead of just accruing
     */
    function disburseSupplierRewardsInternal(
        MToken _mToken,
        address _supplier,
        bool _sendTokens
    ) internal {
        MarketEmissionConfig[] storage configs = marketConfigs[
            address(_mToken)
        ];

        uint256 supplierTokens = _mToken.balanceOf(_supplier);

        // Iterate over all market configs and update their indexes + timestamps
        for (uint256 index = 0; index < configs.length; index++) {
            MarketEmissionConfig storage emissionConfig = configs[index];

            uint256 totalRewardsOwed = calculateSupplyRewardsForUser(
                emissionConfig,
                emissionConfig.config.supplyGlobalIndex,
                supplierTokens,
                _supplier
            );

            // Update user's index to match global index
            emissionConfig.supplierIndices[_supplier] = emissionConfig
                .config
                .supplyGlobalIndex;
            // Update the user's total rewards owed
            emissionConfig.supplierRewardsAccrued[_supplier] = totalRewardsOwed;

            emit DisbursedSupplierRewards(
                _mToken,
                _supplier,
                emissionConfig.config.emissionToken,
                emissionConfig.supplierRewardsAccrued[_supplier]
            );

            // SendRewards will attempt to send only if it has enough emission tokens to do so,
            // and if it doesn't have enough it emits a InsufficientTokensToEmit event and returns
            // the rewards that couldn't be sent, which are the total of what a user is owed, so we
            // store it in supplierRewardsAccrued to make sure we don't lose rewards accrual if there's
            // not enough funds in the rewarder
            if (_sendTokens) {
                // Emit rewards for this token/pair
                uint256 unsendableRewards = sendReward(
                    payable(_supplier),
                    emissionConfig.supplierRewardsAccrued[_supplier],
                    emissionConfig.config.emissionToken
                );

                emissionConfig.supplierRewardsAccrued[
                    _supplier
                ] = unsendableRewards;
            }
        }
    }

    /**
     * @notice An internal function to update the global borrow index for a given mToken
     * @param _mToken The market to update the global borrow index for
     */
    function updateMarketBorrowIndexInternal(MToken _mToken) internal {
        MarketEmissionConfig[] storage configs = marketConfigs[
            address(_mToken)
        ];

        Exp memory marketBorrowIndex = Exp({
            mantissa: MToken(_mToken).borrowIndex()
        });
        uint256 totalBorrows = MToken(_mToken).totalBorrows();

        // Iterate over all market configs and update their indexes + timestamps
        for (uint256 index = 0; index < configs.length; index++) {
            MarketEmissionConfig storage emissionConfig = configs[index];

            // Go calculate our new borrow index
            IndexUpdate memory borrowIndexUpdate = calculateNewIndex(
                emissionConfig.config.borrowEmissionsPerSec,
                emissionConfig.config.borrowGlobalTimestamp,
                emissionConfig.config.borrowGlobalIndex,
                emissionConfig.config.endTime,
                div_(totalBorrows, marketBorrowIndex)
            );

            // Set the new values in storage
            emissionConfig.config.borrowGlobalIndex = borrowIndexUpdate
                .newIndex;
            emissionConfig.config.borrowGlobalTimestamp = borrowIndexUpdate
                .newTimestamp;

            // Emit an update
            emit GlobalBorrowIndexUpdated(
                _mToken,
                emissionConfig.config.emissionToken,
                emissionConfig.config.borrowGlobalIndex,
                emissionConfig.config.borrowGlobalTimestamp
            );
        }
    }

    /**
     * @notice An internal function to disburse rewards for the borrower side of a a specific mToken
     * @dev will only send tokens when _sendTokens == true, otherwise just accrue rewards
     * @param _mToken The market to update the global borrow index for
     * @param _borrower The borrower to disburse rewards for
     * @param _sendTokens Whether to actually send tokens instead of just accruing
     */
    function disburseBorrowerRewardsInternal(
        MToken _mToken,
        address _borrower,
        bool _sendTokens
    ) internal {
        MarketEmissionConfig[] storage configs = marketConfigs[
            address(_mToken)
        ];

        Exp memory marketBorrowIndex = Exp({mantissa: _mToken.borrowIndex()});
        MTokenData memory mTokenData = MTokenData({
            mTokenBalance: _mToken.balanceOf(_borrower),
            borrowBalanceStored: _mToken.borrowBalanceStored(_borrower)
        });

        // Iterate over all market configs and update their indexes + timestamps
        for (uint256 index = 0; index < configs.length; index++) {
            MarketEmissionConfig storage emissionConfig = configs[index];

            // Go calculate the total outstanding rewards for this user
            uint256 owedRewards = calculateBorrowRewardsForUser(
                emissionConfig,
                emissionConfig.config.borrowGlobalIndex,
                marketBorrowIndex,
                mTokenData,
                _borrower
            );

            // Update user's index to global index
            emissionConfig.borrowerIndices[_borrower] = emissionConfig
                .config
                .borrowGlobalIndex;

            // Update the accrued borrow side rewards for this user
            emissionConfig.borrowerRewardsAccrued[_borrower] = owedRewards;

            emit DisbursedBorrowerRewards(
                _mToken,
                _borrower,
                emissionConfig.config.emissionToken,
                emissionConfig.borrowerRewardsAccrued[_borrower]
            );

            // If we are instructed to send out rewards, do so and update the borrowerRewardsAccrued to
            // 0 if it was successful, or to `pendingRewards` if there was insufficient balance to send
            if (_sendTokens) {
                // Emit rewards for this token/pair
                uint256 pendingRewards = sendReward(
                    payable(_borrower),
                    emissionConfig.borrowerRewardsAccrued[_borrower],
                    emissionConfig.config.emissionToken
                );

                emissionConfig.borrowerRewardsAccrued[
                    _borrower
                ] = pendingRewards;
            }
        }
    }

    /**
     * @notice An internal function to send rewards to a user
     * @dev Non-reentrant and returns the amount of tokens that were successfully sent
     * @param _user The user address to send tokens to
     * @param _amount The amount of tokens to send
     * @param _rewardToken The reward token to send
     */
    function sendReward(
        address payable _user,
        uint256 _amount,
        address _rewardToken
    ) internal nonReentrant returns (uint256) {
        // Short circuit if we don't have anything to send out
        if (_amount == 0) {
            return _amount;
        }

        // If pause guardian is active, bypass all token transfers, but still accrue to local tally
        if (paused()) {
            return _amount;
        }

        IERC20 token = IERC20(_rewardToken);

        // Get the distributor's current balance
        uint256 currentTokenHoldings = token.balanceOf(address(this));

        // Only transfer out if we have enough of a balance to cover it (otherwise just accrue without sending)
        if (_amount > 0 && _amount <= currentTokenHoldings) {
            // Ensure we use SafeERC20 to revert even if the reward token isn't ERC20 compliant
            token.safeTransfer(_user, _amount);
            return 0;
        } else {
            // If we've hit here it means we weren't able to emit the reward and we should emit an event
            // instead of failing.
            emit InsufficientTokensToEmit(_user, _rewardToken, _amount);

            // By default, return the same amount as what's left over to send, we accrue reward but don't send them out
            return _amount;
        }
    }
}
