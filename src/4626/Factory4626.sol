pragma solidity 0.8.19;

import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MoonwellERC4626} from "@protocol/4626/MoonwellERC4626.sol";
import {Comptroller as IMoontroller} from "@protocol/Comptroller.sol";

contract Factory4626 {
    using SafeERC20 for *;

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

    /// @notice Deploy a MoonwellERC4626 vault
    /// @param mToken The corresponding mToken
    /// @param rewardRecipient The address to receive rewards
    function deployMoonwellERC4626(
        address mToken,
        address rewardRecipient
    ) external returns (address vault) {
        address asset = MErc20(mToken).underlying();
        /// parameter checks
        require(rewardRecipient != address(0), "INVALID_RECIPIENT");
        require(asset != weth, "INVALID_ASSET");

        /// create the vault contract
        vault = address(
            new MoonwellERC4626(
                ERC20(asset),
                MErc20(mToken),
                rewardRecipient,
                moontroller
            )
        );

        /// handle initial mints to the vault to prevent front-running
        /// and share price manipulation

        uint256 initialMintAmount = 10 ** ((ERC20(asset).decimals() * 2) / 3);

        IERC20(asset).safeTransferFrom(
            msg.sender,
            address(this),
            initialMintAmount
        );

        IERC20(asset).safeApprove(vault, initialMintAmount);

        require(
            MoonwellERC4626(vault).deposit(initialMintAmount, address(0)) > 0,
            "deposit failed"
        );

        emit DeployedMoonwellERC4626(asset, mToken, rewardRecipient, vault);
    }
}
