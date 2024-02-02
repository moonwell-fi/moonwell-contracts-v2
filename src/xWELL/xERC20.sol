pragma solidity 0.8.19;

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {IXERC20} from "@protocol/xWELL/interfaces/IXERC20.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";

abstract contract xERC20 is IXERC20, MintLimits {
    using SafeCast for uint256;

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
    function mint(address user, uint256 amount) public virtual {
        /// first deplete buffer for the minter if not at max
        _depleteBuffer(msg.sender, amount);

        _mint(user, amount);
    }

    /// @notice Burns tokens for a user
    /// @dev Can only be called by a minter
    /// @param user The address of the user who needs tokens burned
    /// @param amount The amount of tokens being burned
    function burn(address user, uint256 amount) public virtual {
        /// first replenish buffer for the minter if not at max
        /// unauthorized sender reverts
        _replenishBuffer(msg.sender, amount);

        /// deplete bridge's allowance
        _spendAllowance(user, msg.sender, amount);

        /// burn user's tokens
        _burn(user, amount);
    }

    //// ------------------------------------------------------------
    //// ------------------------------------------------------------
    //// ------------- Internal Override Functions ------------------
    //// ------------------------------------------------------------
    //// ------------------------------------------------------------

    /// @notice mint hook to ensure that max supply is never exceeded
    function _mint(address, uint256) internal virtual {
        /// mint tokens

        require(totalSupply() <= maxSupply(), "xERC20: max supply exceeded");
    }

    /// @notice maximum supply is 5 billion tokens if all WELL holders migrate to xWELL
    function maxSupply() public pure virtual returns (uint256);

    /// @notice total supply of tokens for this contract
    function totalSupply() public view virtual returns (uint256);

    /// @notice the maximum amount of time the token can be paused for
    function maxPauseDuration() public pure virtual returns (uint256);

    /// @notice burn tokens from a user
    function _burn(address user, uint256 amount) internal virtual;

    /// @notice spend allowance from a user
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual;
}
