pragma solidity 0.8.19;

import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@forge-std/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";

/// @notice splitter contract to divy up tokens between two addresses
contract FeeSplitter {
    using SafeERC20 for IERC20;

    /// ------------------------------------------------
    /// ------------------ IMMUTABLES ------------------
    /// ------------------------------------------------

    /// @notice the percentage of tokens given to address A
    uint256 public immutable splitA;

    /// @notice the percentage of tokens given to address B
    uint256 public immutable splitB;

    /// @notice the address given split of splitB
    address public immutable b;

    /// @notice reference to the mToken where reserves will be added
    address public immutable mToken;

    /// @notice reference to the MetaMorpho Vault
    address public immutable metaMorphoVault;

    /// @notice the token to split
    IERC20 public immutable token;

    /// ------------------------------------------------
    /// ------------------- CONSTANT -------------------
    /// ------------------------------------------------

    /// @notice the total basis points of the split
    uint256 public constant SPLIT_TOTAL = 10_000;

    /// ------------------------------------------------
    /// --------------------- EVENT --------------------
    /// ------------------------------------------------

    /// @notice event emitted when tokens are split
    /// @param amountA the amount of tokens given to address A
    /// @param amountB the amount of tokens given to address B
    event TokensSplit(uint256 amountA, uint256 amountB);

    /// @param _b the address to give splitB to
    /// @param _splitA the percentage in basis points of tokens to give to
    /// address A
    /// @param _metaMorphoVault the address of the MetaMorpho Vault
    /// @param _mToken the address of the mToken
    constructor(
        address _b,
        uint256 _splitA,
        address _metaMorphoVault,
        address _mToken
    ) {
        b = _b;
        splitA = _splitA;
        splitB = SPLIT_TOTAL - _splitA;
        metaMorphoVault = _metaMorphoVault;
        mToken = _mToken;

        token = IERC20(MErc20(_mToken).underlying());
        address asset = IERC4626(_metaMorphoVault).asset();

        require(asset == address(token), "FeeSplitter: asset mismatch");
    }

    /// @notice permissionless function, callable by anyone
    /// splits MetaMorpho Vault tokens between two addresses
    /// If there is not enough liquidity to redeem A's portion, this function
    /// will fail
    function split() public {
        /// split 4626 vault tokens between two addresses, first get amount
        uint256 amount = IERC20(metaMorphoVault).balanceOf(address(this));

        /// leftovers will stay in the contract, no need to worry about dust
        uint256 amountA = (amount * splitA) / SPLIT_TOTAL;
        uint256 amountB = (amount * splitB) / SPLIT_TOTAL;

        /// send 4626 vault tokens to receiver b
        IERC20(metaMorphoVault).safeTransfer(b, amountB);

        /// 1. get amount to withdraw from MetaMorpho Vault
        /// accept that there is some slippage when withdrawing shares
        uint256 withdrawableAssets = IERC4626(metaMorphoVault).previewRedeem(
            amountA
        );

        /// 2. call withdraw on MetaMorpho Vault
        IERC4626(metaMorphoVault).withdraw(
            withdrawableAssets,
            address(this),
            address(this)
        );

        /// 3. call approve on underlying token to approve mToken to spend
        /// withdrawableAssets amount
        token.safeApprove(mToken, withdrawableAssets);

        /// 4. call addReserves on the mToken
        require(
            MErc20(mToken)._addReserves(withdrawableAssets) == 0,
            "FeeSplitter: add reserves failure"
        );

        emit TokensSplit(amountA, amountB);
    }
}
