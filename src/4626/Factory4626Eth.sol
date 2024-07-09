pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {MoonwellERC4626Eth} from "@protocol/4626/MoonwellERC4626Eth.sol";
import {Comptroller as IMoontroller} from "@protocol/Comptroller.sol";
import {MErc20} from "@protocol/MErc20.sol";

contract Factory4626Eth {
    /// ------------------------------------------------
    /// ------------------------------------------------
    /// ------------------ IMMUTABLES ------------------
    /// ------------------------------------------------
    /// ------------------------------------------------

    /// @notice The Moonwell moontroller contract
    IMoontroller public immutable moontroller;

    /// @notice The WETH9 contract
    address public immutable weth;

    /// @notice The initial mint amount for a new vault
    uint256 public constant INITIAL_MINT_AMOUNT = 0.0001 ether;

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

    /// @notice Deploy a CompoundERC4626Eth vault
    /// @param mToken The corresponding Moonwell mToken,
    /// should be MOONWELL_WETH
    /// @param rewardRecipient The address to receive rewards
    function deployMoonwellERC4626Eth(address mToken, address rewardRecipient)
        external
        returns (address vault)
    {
        /// parameter checks
        require(rewardRecipient != address(0), "INVALID_RECIPIENT");
        require(MErc20(mToken).underlying() == weth, "INVALID_ASSET");

        /// create the vault contract
        vault = address(
            new MoonwellERC4626Eth(
                ERC20(weth), MErc20(mToken), rewardRecipient, moontroller
            )
        );

        /// handle initial mints to the vault to prevent front-running
        /// and share price manipulation

        require(
            ERC20(weth).transferFrom(
                msg.sender, address(this), INITIAL_MINT_AMOUNT
            ),
            "transferFrom failed"
        );

        require(
            ERC20(weth).approve(vault, INITIAL_MINT_AMOUNT), "approve failed"
        );

        require(
            MoonwellERC4626Eth(payable(vault)).deposit(
                INITIAL_MINT_AMOUNT, address(0)
            ) > 0,
            "deposit failed"
        );

        emit DeployedMoonwellERC4626(weth, mToken, rewardRecipient, vault);
    }
}
