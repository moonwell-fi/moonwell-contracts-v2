pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MoonwellERC4626} from "@protocol/4626/MoonwellERC4626.sol";
import {MoonwellERC4626Eth} from "@protocol/4626/MoonwellERC4626Eth.sol";
import {Comptroller as IMoontroller} from "@protocol/Comptroller.sol";

contract Factory4626 {
    /// ------------------------------------------------
    /// ------------------------------------------------
    /// ------------------ IMMUTABLES ------------------
    /// ------------------------------------------------
    /// ------------------------------------------------

    /// @notice The Moonwell moontroller contract
    IMoontroller public immutable moontroller;

    /// @notice The WETH9 contract
    address public immutable weth;

    /// @notice event emitted when a new 4626 vault is deployed
    /// @param asset underlying the vault
    /// @param mToken the mToken contract
    /// @param rewardRecipient the address to receive rewards
    /// @param deployed the address of the deployed contract
    event DeployedMoonwellERC4626(
        address indexed asset,
        address indexed mToken,
        address indexed rewardRecipient,
        address deployed
    );

    /// @param _moontroller The Moonwell comptroller contract
    /// @param _weth The WETH9 contract
    constructor(IMoontroller _moontroller, address _weth) {
        moontroller = _moontroller;
        weth = _weth;
    }

    /// @notice Deploy a CompoundERC4626 vault
    /// @param mToken The corresponding Moonwell mToken
    /// @param rewardRecipient The address to receive rewards
    function deployMoonwellERC4626(
        address mToken,
        address rewardRecipient
    ) external returns (address vault) {
        address asset = MErc20(mToken).underlying();

        require(rewardRecipient != address(0), "INVALID_RECIPIENT");
        require(asset != weth, "INVALID_ASSET");

        vault = address(
            new MoonwellERC4626(
                ERC20(asset),
                MErc20(mToken),
                rewardRecipient,
                moontroller
            )
        );

        emit DeployedMoonwellERC4626(asset, mToken, rewardRecipient, vault);
    }
}
