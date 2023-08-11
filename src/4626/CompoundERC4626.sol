// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {LibCompound} from "@protocol/4626/LibCompound.sol";
import {Comptroller as IComptroller} from "@protocol/Comptroller.sol";

/// @title CompoundERC4626
/// @author zefram.eth
/// @notice ERC4626 wrapper for Moonwell Finance
contract CompoundERC4626 is ERC4626 {
    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using LibCompound for MErc20;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event ClaimRewards(uint256 amount, address token);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Thrown when a call to Compound returned an error.
    /// @param errorCode The error code returned by Compound
    error CompoundERC4626__CompoundError(uint256 errorCode);

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint256 internal constant NO_ERROR = 0;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The WELL token contract
    ERC20 public immutable well;

    /// @notice The Moonwell mToken contract
    MErc20 public immutable mToken;

    /// @notice The address that will receive the liquidity mining rewards (if any)
    address public immutable rewardRecipient;

    /// @notice The Compound comptroller contract
    IComptroller public immutable comptroller;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        ERC20 asset_,
        ERC20 well_,
        MErc20 mToken_,
        address rewardRecipient_,
        IComptroller comptroller_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        well = well_;
        mToken = mToken_;
        comptroller = comptroller_;
        rewardRecipient = rewardRecipient_;
    }

    /// -----------------------------------------------------------------------
    /// Compound liquidity mining
    /// -----------------------------------------------------------------------

    /// @notice Claims liquidity mining rewards from Compound and sends it to rewardRecipient
    function claimRewards() public {
        address[] memory holders = new address[](1);
        holders[0] = address(this);

        MToken[] memory mTokens = new MToken[](1);
        mTokens[0] = MToken(address(mToken));

        comptroller.claimReward(holders, mTokens, false, true);

        uint256 amount = well.balanceOf(address(this));
        well.safeTransfer(rewardRecipient, amount);

        emit ClaimRewards(amount, address(well));
    }

    /// @notice Claims liquidity mining rewards from Compound and sends it to rewardRecipient
    function sweepRewards(address[] memory tokens) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            ERC20 token = ERC20(tokens[i]);
            uint256 amount = token.balanceOf(address(this));
            token.safeTransfer(rewardRecipient, amount);
            emit ClaimRewards(amount, address(token));
        }
    }

    /// @notice Claims liquidity mining rewards from Compound and sends it to
    /// rewardRecipient for all tokens
    /// @param tokens The tokens to sweep
    function claimAndSweep(address[] memory tokens) external {
        claimRewards();
        sweepRewards(tokens);
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function totalAssets() public view virtual override returns (uint256) {
        return mToken.viewUnderlyingBalanceOf(address(this));
    }

    function beforeWithdraw(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Withdraw assets from Compound
        /// -----------------------------------------------------------------------

        uint256 errorCode = mToken.redeemUnderlying(assets);
        if (errorCode != NO_ERROR) {
            revert CompoundERC4626__CompoundError(errorCode);
        }
    }

    function afterDeposit(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Deposit assets into Compound
        /// -----------------------------------------------------------------------

        // approve to mToken
        asset.safeApprove(address(mToken), assets);

        // deposit into mToken
        uint256 errorCode = mToken.mint(assets);
        if (errorCode != NO_ERROR) {
            revert CompoundERC4626__CompoundError(errorCode);
        }
    }

    function maxDeposit(address) public view override returns (uint256) {
        return maxMint(address(0));
    }

    function maxMint(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(address(mToken))) {
            return 0;
        }

        uint256 borrowCap = comptroller.borrowCaps(address(mToken));
        if (borrowCap != 0) {
            uint256 totalBorrows = mToken.totalBorrows();
            return borrowCap - totalBorrows;
        }

        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 cash = mToken.getCash();
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 cash = mToken.getCash();
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    /// -----------------------------------------------------------------------
    /// ERC20 metadata generation
    /// -----------------------------------------------------------------------

    function _vaultName(
        ERC20 asset_
    ) internal view virtual returns (string memory vaultName) {
        vaultName = string.concat("ERC4626-Wrapped Moonwell ", asset_.symbol());
    }

    function _vaultSymbol(
        ERC20 asset_
    ) internal view virtual returns (string memory vaultSymbol) {
        vaultSymbol = string.concat("wm", asset_.symbol());
    }
}
