pragma solidity 0.8.19;

interface IXERC20 {
    /**
     * @notice Emits when a limit is set
     *
     * @param bridge The address of the bridge we are setting the limit too
     * @param bufferCap The updated buffer cap for the bridge
     */
    event BridgeLimitsSet(address indexed bridge, uint256 bufferCap);

    /**
     * @notice Returns the max limit of a minter
     *
     * @param _minter The minter we are viewing the limits of
     *  @return _limit The limit the minter has
     */
    function mintingMaxLimitOf(address _minter) external view returns (uint256 _limit);

    /**
     * @notice Returns the max limit of a bridge
     *
     * @param _bridge the bridge we are viewing the limits of
     * @return _limit The limit the bridge has
     */
    function burningMaxLimitOf(address _bridge) external view returns (uint256 _limit);

    /**
     * @notice Returns the current limit of a minter
     *
     * @param _minter The minter we are viewing the limits of
     * @return _limit The limit the minter has
     */
    function mintingCurrentLimitOf(address _minter) external view returns (uint256 _limit);

    /**
     * @notice Returns the current limit of a bridge
     *
     * @param _bridge the bridge we are viewing the limits of
     * @return _limit The limit the bridge has
     */
    function burningCurrentLimitOf(address _bridge) external view returns (uint256 _limit);

    /**
     * @notice Mints tokens for a user
     * @dev Can only be called by a minter
     * @param _user The address of the user who needs tokens minted
     * @param _amount The amount of tokens being minted
     */
    function mint(address _user, uint256 _amount) external;

    /**
     * @notice Burns tokens for a user
     * @dev Can only be called by a minter
     * @param _user The address of the user who needs tokens burned
     * @param _amount The amount of tokens being burned
     */
    function burn(address _user, uint256 _amount) external;
}
