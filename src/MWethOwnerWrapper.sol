// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {WETH9} from "@protocol/router/IWETH.sol";
import {MTokenInterface} from "@protocol/MTokenInterfaces.sol";
import {MErc20Interface} from "@protocol/MTokenInterfaces.sol";
import {MDelegatorInterface} from "@protocol/MTokenInterfaces.sol";
import {InterestRateModel} from "@protocol/irm/InterestRateModel.sol";
import {ComptrollerInterface} from "@protocol/ComptrollerInterface.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

/// @notice admin hooks added to MErc20Delegate by MIP-X71
interface IMErc20DelegateInternalCash {
    function _sweepExcessCash() external;

    function _syncCashDown() external;
}

/**
 * @title MWethOwnerWrapper
 * @notice A wrapper contract that acts as the admin for the WETH market,
 * enabling it to receive native ETH through the WETH unwrapping process.
 * This solves the issue where TEMPORAL_GOVERNOR cannot reliably receive ETH
 * during proposal execution when reducing WETH market reserves.
 *
 * @dev This contract:
 * - Automatically wraps any received ETH into WETH
 * - Delegates all admin functions to the underlying WETH market
 * - Is owned by TEMPORAL_GOVERNOR for governance control
 * - Allows extracting tokens (primarily WETH) after reserve reductions
 */
contract MWethOwnerWrapper is Initializable, OwnableUpgradeable {
    /// @notice The WETH market this wrapper administers
    MTokenInterface public mToken;

    /// @notice The WETH token contract
    WETH9 public weth;

    /// @notice Emitted when ETH is received and wrapped to WETH
    event EthWrapped(uint256 amount);

    /// @notice Emitted when tokens are withdrawn from the wrapper
    event TokenWithdrawn(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the wrapper contract
     * @param _mToken Address of the WETH market to administer
     * @param _weth Address of the WETH token contract
     * @param _owner Address that will own this contract (should be TEMPORAL_GOVERNOR)
     */
    function initialize(
        address _mToken,
        address _weth,
        address _owner
    ) public initializer {
        require(
            _mToken != address(0),
            "MWethOwnerWrapper: mToken cannot be zero address"
        );
        require(
            _weth != address(0),
            "MWethOwnerWrapper: weth cannot be zero address"
        );
        require(
            _owner != address(0),
            "MWethOwnerWrapper: owner cannot be zero address"
        );

        __Ownable_init();

        mToken = MTokenInterface(_mToken);
        weth = WETH9(_weth);
        _transferOwnership(_owner);
    }

    /**
     * @notice Fallback function to receive ETH and automatically wrap it to WETH
     * @dev This is critical for receiving ETH from the WETH unwrapper during reserve reductions
     */
    receive() external payable {
        if (msg.value > 0) {
            weth.deposit{value: msg.value}();
            emit EthWrapped(msg.value);
        }
    }

    // ========================================
    // Admin Functions - Delegate to MToken
    // ========================================

    /**
     * @notice Reduce reserves of the WETH market
     * @dev The reduced reserves will be sent to this wrapper as ETH, then auto-wrapped to WETH
     * @param reduceAmount The amount of reserves to reduce
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _reduceReserves(
        uint256 reduceAmount
    ) external onlyOwner returns (uint) {
        return mToken._reduceReserves(reduceAmount);
    }

    /**
     * @notice Set pending admin of the WETH market
     * @param newPendingAdmin The new pending admin address
     * @return uint 0=success, otherwise a failure
     */
    function _setPendingAdmin(
        address payable newPendingAdmin
    ) external onlyOwner returns (uint) {
        return mToken._setPendingAdmin(newPendingAdmin);
    }

    /**
     * @notice Accept admin role for the WETH market
     * @dev Call this after the market's current admin has called _setPendingAdmin
     * @return uint 0=success, otherwise a failure
     */
    function _acceptAdmin() external onlyOwner returns (uint) {
        return mToken._acceptAdmin();
    }

    /**
     * @notice Set the comptroller for the WETH market
     * @param newComptroller The new comptroller address
     * @return uint 0=success, otherwise a failure
     */
    function _setComptroller(
        ComptrollerInterface newComptroller
    ) external onlyOwner returns (uint) {
        return mToken._setComptroller(newComptroller);
    }

    /**
     * @notice Set the reserve factor for the WETH market
     * @param newReserveFactorMantissa The new reserve factor (scaled by 1e18)
     * @return uint 0=success, otherwise a failure
     */
    function _setReserveFactor(
        uint256 newReserveFactorMantissa
    ) external onlyOwner returns (uint) {
        return mToken._setReserveFactor(newReserveFactorMantissa);
    }

    /**
     * @notice Set the interest rate model for the WETH market
     * @param newInterestRateModel The new interest rate model address
     * @return uint 0=success, otherwise a failure
     */
    function _setInterestRateModel(
        InterestRateModel newInterestRateModel
    ) external onlyOwner returns (uint) {
        return mToken._setInterestRateModel(newInterestRateModel);
    }

    /**
     * @notice Set the protocol seize share for the WETH market
     * @param newProtocolSeizeShareMantissa The new protocol seize share (scaled by 1e18)
     * @return uint 0=success, otherwise a failure
     */
    function _setProtocolSeizeShare(
        uint256 newProtocolSeizeShareMantissa
    ) external onlyOwner returns (uint) {
        return mToken._setProtocolSeizeShare(newProtocolSeizeShareMantissa);
    }

    /**
     * @notice Add reserves to the WETH market
     * @param addAmount The amount of reserves to add
     * @return uint 0=success, otherwise a failure
     */
    function _addReserves(uint256 addAmount) external onlyOwner returns (uint) {
        // First approve the mToken to spend WETH from this wrapper
        require(
            weth.approve(address(mToken), addAmount),
            "MWethOwnerWrapper: WETH approval failed"
        );
        return MErc20Interface(address(mToken))._addReserves(addAmount);
    }

    /**
     * @notice Point the WETH market at a new implementation
     * @param implementation_ The new implementation address
     * @param allowResign Whether to call _resignImplementation on the old implementation
     * @param becomeImplementationData Data passed to _becomeImplementation
     */
    function _setImplementation(
        address implementation_,
        bool allowResign,
        bytes calldata becomeImplementationData
    ) external onlyOwner {
        MDelegatorInterface(address(mToken))._setImplementation(
            implementation_,
            allowResign,
            becomeImplementationData
        );
    }

    /**
     * @notice Sweep WETH held by the market above its internalCash to this wrapper
     * @dev Swept WETH lands here and is extracted with withdrawToken
     */
    function _sweepExcessCash() external onlyOwner {
        IMErc20DelegateInternalCash(address(mToken))._sweepExcessCash();
    }

    /**
     * @notice Lower the WETH market's internalCash to its WETH balance after a
     *         loss outside the market; never raises it
     */
    function _syncCashDown() external onlyOwner {
        IMErc20DelegateInternalCash(address(mToken))._syncCashDown();
    }

    // ========================================
    // Token Management Functions
    // ========================================

    /**
     * @notice Withdraw ERC20 tokens from this wrapper
     * @dev Primarily used to extract WETH after reserve reductions
     * @param token The token address to withdraw
     * @param to The recipient address
     * @param amount The amount to withdraw
     */
    function withdrawToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(
            to != address(0),
            "MWethOwnerWrapper: cannot withdraw to zero address"
        );
        require(
            amount > 0,
            "MWethOwnerWrapper: amount must be greater than zero"
        );

        require(
            WETH9(token).transfer(to, amount),
            "MWethOwnerWrapper: token transfer failed"
        );

        emit TokenWithdrawn(token, to, amount);
    }

    /**
     * @notice Get the balance of a token held by this wrapper
     * @param token The token address to query
     * @return The balance of the token
     */
    function getTokenBalance(address token) external view returns (uint256) {
        return WETH9(token).balanceOf(address(this));
    }
}
