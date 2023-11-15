pragma solidity 0.8.19;

import {ERC20VotesUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {Time} from "@openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/types/Time.sol";

import {IXERC20} from "@protocol/xWELL/interfaces/IXERC20.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";

contract xWELL is IXERC20, ERC20VotesUpgradeable, MintLimits {
    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// -------------------- clock override --------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice override clock from VotesUpgradeable to use timestamp instead of block number
    function clock() public view override returns (uint48) {
        return Time.timestamp();
    }

    /**
     * @dev Machine-readable description of the clock as specified in EIP-6372.
     * https://eips.ethereum.org/EIPS/eip-6372
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view override returns (string memory) {
        // Check that the clock was not modified
        if (clock() != Time.timestamp()) {
            revert ERC6372InconsistentClock();
        }

        return "mode=timestamp";
    }

    /**
     * @notice Returns the max limit of a minter
     *
     * @param _minter The minter we are viewing the limits of
     *  @return _limit The limit the minter has
     */
    function mintingMaxLimitOf(
        address _minter
    ) external view returns (uint256 _limit) {
        return bufferCap(_minter);
    }

    /**
     * @notice Returns the max limit of a bridge
     *
     * @param _bridge the bridge we are viewing the limits of
     * @return _limit The limit the bridge has
     */
    function burningMaxLimitOf(
        address _bridge
    ) external view returns (uint256 _limit) {
        return bufferCap(_bridge);
    }

    /**
     * @notice Returns the current limit of a minter
     *
     * @param _minter The minter we are viewing the limits of
     * @return _limit The limit the minter has
     */
    function mintingCurrentLimitOf(
        address _minter
    ) external view returns (uint256 _limit) {
        return buffer(_minter);
    }

    /**
     * @notice Returns the current limit of a bridge
     *
     * @param _bridge the bridge we are viewing the limits of
     * @return _limit The limit the bridge has
     */
    function burningCurrentLimitOf(
        address _bridge
    ) external view returns (uint256 _limit) {
        /// buffer <= bufferCap, so this can never revert, just return 0
        return bufferCap(_minter) - buffer(_minter);
    }

    /**
     * @notice Mints tokens for a user
     * @dev Can only be called by a minter
     * @param _user The address of the user who needs tokens minted
     * @param _amount The amount of tokens being minted
     */
    function mint(address _user, uint256 _amount) external {
        /// first deplete buffer for the minter if not at max
        if (bufferCap(msg.sender) != type(uint112).max) {
            _depleteBuffer(msg.sender, _amount);
        }

        _mint(_user, _amount);
    }

    /**
     * @notice Burns tokens for a user
     * @dev Can only be called by a minter
     * @param _user The address of the user who needs tokens burned
     * @param _amount The amount of tokens being burned
     */

    function burn(address _user, uint256 _amount) external {
        /// first replenish buffer for the minter if not at max
        if (bufferCap(msg.sender) != type(uint112).max) {
            _replenishBuffer(msg.sender, _amount);
        }

        _burn(user, _amount);
    }
}
