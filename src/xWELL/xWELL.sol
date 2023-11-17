pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {IXERC20} from "@protocol/xWELL/interfaces/IXERC20.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {ConfigurablePause} from "@protocol/xWELL/ConfigurablePause.sol";
import {ConfigurablePauseGuardian} from "@protocol/xWELL/ConfigurablePauseGuardian.sol";

/// @notice TODO set the lockbox address bufferCap to uint112 max in deployment script for Moonbeam
contract xWELL is
    IXERC20,
    MintLimits,
    ERC20VotesUpgradeable,
    Ownable2StepUpgradeable,
    ConfigurablePauseGuardian
{
    using SafeCast for uint256;

    /// @notice maximum supply is 5 billion tokens if all WELL holders migrate to xWELL
    uint256 public constant MAX_SUPPLY = 5_000_000_000 * 1e18;

    /// @notice logic contract cannot be initialized
    constructor() {
        _disableInitializers();
    }

    /// @dev on token's native chain, the lockbox must have its bufferCap set to uint112 max
    /// @notice initialize the xWELL token
    /// @param tokenName The name of the token
    /// @param tokenSymbol The symbol of the token
    /// @param tokenOwner The owner of the token, Temporal Governor on Base, Timelock on Moonbeam
    /// @param newRateLimits The rate limits for the token
    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        address tokenOwner,
        MintLimits.RateLimitMidPointInfo[] memory newRateLimits,
        uint128 newPauseDuration,
        address newPauseGuardian
    ) external initializer {
        __ERC20_init(tokenName, tokenSymbol);
        __Ownable_init();
        _addLimits(newRateLimits);

        /// pausing
        __Pausable_init(); /// not really needed, but seems like good form
        _grantGuardian(newPauseGuardian); /// set the pause guardian
        _updatePauseDuration(newPauseDuration);

        transferOwnership(tokenOwner);
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// -------------------- clock override --------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice override the clock in ERC20 Votes to use block timestamp
    /// now all checkpoints use unix timestamp instead of block number
    function clock() public view override returns (uint48) {
        /// do not safe cast, overflow will not happen for billions of years
        /// Given that the Unix Epoch started in 1970, adding these years to 1970 gives a theoretical year:
        /// 1970 + 8,923,292,862.77 ≈ Year 8,923,292,883,832
        return uint48(block.timestamp);
    }

    /// @dev Machine-readable description of the clock as specified in EIP-6372.
    /// https://eips.ethereum.org/EIPS/eip-6372
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view override returns (string memory) {
        // Check that the clock is correctly modified
        require(clock() == uint48(block.timestamp), "Incorrect clock");

        return "mode=timestamp";
    }

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// -------------------- View Functions ------------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @notice Returns the max limit of a minter
    /// @param minter The minter we are viewing the limits of
    /// @return limit The limit the minter has
    function mintingMaxLimitOf(
        address minter
    ) external view returns (uint256 limit) {
        return bufferCap(minter);
    }

    /// @notice Returns the max limit of a bridge
    /// @param bridge the bridge we are viewing the limits of
    /// @return limit The limit the bridge has
    function burningMaxLimitOf(
        address bridge
    ) external view returns (uint256 limit) {
        return bufferCap(bridge);
    }

    /// @notice Returns the current limit of a minter
    /// @param minter The minter we are viewing the limits of
    /// @return limit The limit the minter has
    function mintingCurrentLimitOf(
        address minter
    ) external view returns (uint256 limit) {
        return buffer(minter);
    }

    /// @notice Returns the current limit of a bridge
    /// @param bridge the bridge we are viewing the limits of
    /// @return limit The limit the bridge has
    function burningCurrentLimitOf(
        address bridge
    ) external view returns (uint256 limit) {
        /// buffer <= bufferCap, so this can never revert, just return 0
        return bufferCap(bridge) - buffer(bridge);
    }

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// --------------------- Bridge Functions ---------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @notice Mints tokens for a user
    /// @dev Can only be called by a minter
    /// @param user The address of the user who needs tokens minted
    /// @param amount The amount of tokens being minted
    function mint(address user, uint256 amount) external whenNotPaused {
        /// first deplete buffer for the minter if not at max
        if (bufferCap(msg.sender) != type(uint112).max) {
            _depleteBuffer(msg.sender, amount);
        }

        _mint(user, amount);
    }

    /// @notice Burns tokens for a user
    /// @dev Can only be called by a minter
    /// @param user The address of the user who needs tokens burned
    /// @param amount The amount of tokens being burned
    function burn(address user, uint256 amount) external whenNotPaused {
        /// first replenish buffer for the minter if not at max
        /// unauthorized sender reverts
        if (bufferCap(msg.sender) != type(uint112).max) {
            _replenishBuffer(msg.sender, amount);
        }

        /// deplete bridge's allowance
        _spendAllowance(user, msg.sender, amount);

        /// burn user's tokens
        _burn(user, amount);
    }

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// --------------------- Admin Functions ---------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @dev can only be called if the bridge already has a buffer cap
    /// @notice conform to the xERC20 setLimits interface
    /// @param bridge the bridge we are setting the limits of
    /// @param newBufferCap the new buffer cap, uint112 max for unlimited
    function setLimits(
        address bridge,
        uint256 newBufferCap,
        uint256
    ) external onlyOwner {
        setBufferCap(bridge, newBufferCap);
    }

    /// @dev can only be called if the bridge already has a buffer cap
    /// @notice conform to the xERC20 setLimits interface
    /// @param bridge the bridge we are setting the limits of
    /// @param newBufferCap the new buffer cap, uint112 max for unlimited
    function setBufferCap(
        address bridge,
        uint256 newBufferCap
    ) public onlyOwner {
        _setBufferCap(bridge, newBufferCap.toUint112());

        emit BridgeLimitsSet(newBufferCap, newBufferCap, bridge);
    }

    /// @dev can only be called if the bridge already has a buffer cap
    /// @notice set rate limit per second for a bridge
    /// @param bridge the bridge we are setting the limits of
    /// @param newRateLimitPerSecond the new rate limit per second
    function setRateLimitPerSecond(
        address bridge,
        uint128 newRateLimitPerSecond
    ) external onlyOwner {
        _setRateLimitPerSecond(bridge, newRateLimitPerSecond);
    }

    /// @notice grant new pause guardian
    /// @dev should only be called when unpaused, otherwise the
    /// contract can be paused again
    /// @param newPauseGuardian the new pause guardian
    function grantPauseGuardian(address newPauseGuardian) external onlyOwner {
        _grantGuardian(newPauseGuardian);
    }

    /// @notice add a new bridge to the currently active bridges
    /// @param newBridge the bridge to add
    function addBridge(
        RateLimitMidPointInfo memory newBridge
    ) external onlyOwner {
        _addLimit(newBridge);
    }

    /// @notice add new bridges to the currently active bridges
    /// @param newBridges the bridges to add
    function addBridges(
        RateLimitMidPointInfo[] memory newBridges
    ) external onlyOwner {
        _addLimits(newBridges);
    }

    /// @notice remove a bridge from the currently active bridges
    /// deleting its buffer stored, buffer cap, mid point and last
    /// buffer used time
    /// @param bridge the bridge to remove
    function removeBridge(address bridge) external onlyOwner {
        _removeLimit(bridge);
    }

    /// @notice remove a set of bridges from the currently active bridges
    /// deleting its buffer stored, buffer cap, mid point and last
    /// buffer used time
    /// @param bridges the bridges to remove
    function removeBridges(address[] memory bridges) external onlyOwner {
        _removeLimits(bridges);
    }

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// ------------- Internal Override Functions ------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @notice mint hook to ensure that max supply is never exceeded
    /// @param to the address to mint to
    /// @param amount the amount to mint
    function _mint(address to, uint256 amount) internal override {
        /// mint tokens
        super._mint(to, amount);

        require(totalSupply() <= MAX_SUPPLY, "xWELL: max supply exceeded");
    }

    /// @notice hook to stop users from transferring tokens to the xWELL contract
    /// @param from the address to transfer from
    /// @param to the address to transfer to
    /// @param amount the amount to transfer
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._beforeTokenTransfer(from, to, amount);

        require(
            to != address(this),
            "xWELL: cannot transfer to token contract"
        );
    }
}
