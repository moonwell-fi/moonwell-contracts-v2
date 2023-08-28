// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {LibCompound} from "@protocol/4626/LibCompound.sol";
import {Comptroller as IComptroller} from "@protocol/Comptroller.sol";
import {MultiRewardDistributor, MultiRewardDistributorCommon} from "@protocol/MultiRewardDistributor/MultiRewardDistributor.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CompoundERC4626
/// @author zefram.eth
/// @notice ERC4626 wrapper for Moonwell Finance
contract CompoundERC4626 is ERC4626, Ownable {
    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using LibCompound for MErc20;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event ClaimRewards(uint256 amount, address token);
    event RewardHandlerUpdate(address newRewardHandler);

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
    uint256 internal constant MAX_INT = 2**256 - 1;


    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The Moonwell mToken contract
    MErc20 public immutable mToken;

    /// @notice The address that will handle the liquidity mining rewards (if any)
    address public rewardHandler;

    /// @notice The Compound comptroller contract
    IComptroller public immutable comptroller;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        address owner,
        ERC20 asset_,
        MErc20 mToken_,
        IComptroller comptroller_,
        address rewardHandler_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        _transferOwnership(owner);
        mToken = mToken_;
        comptroller = comptroller_;
        rewardHandler = rewardHandler_;
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 admin
    /// -----------------------------------------------------------------------
    
    /// @notice Ideally, revoke any allowances before updating reward handler
    function setRewardHandler(address rewardHandler_) onlyOwner {
        rewardHandler = rewardHandler_
        emit RewardHandlerUpdate(rewardHandler);
    }

    function revokeRewardHandlerAllowances(address[] calldata tokens) onlyOwner {
        require(rewardHandler != address(0), "No reward handler set")

        unchecked {
            for (uint256 i = 0; i < tokens.length; i++) {
                ERC20 token = ERC20(tokens[i]);
                token.approve(rewardHandler, 0); // revoke allowances
            }
        }
    }

    function enableRewardHandlerAllowances(address[] calldata tokens) onlyOwner {
        require(rewardHandler != address(0), "No reward handler set")
        unchecked {
            for (uint256 i = 0; i < tokens.length; i++) {
                require(
                    tokens[i] != address(mToken),
                    "CompoundERC4626: cannot give allowance for mToken"
                );
                ERC20 token = ERC20(tokens[i]);
                token.approve(rewardHandler, MAX_INT); // infinite allowance
            }
        }
    }

    function enableRewardHandlerAllowancesFromMRD() onlyOwner {
        require(rewardHandler != address(0), "No reward handler set")

        MultiRewardDistributor mrd = comptroller.rewardDistributor();
        require(address(mrd) != address(0), "No MRD set")

        MultiRewardDistributorCommon.MarketConfig[] memory configs = mrd
            .getAllMarketConfigs(MToken(address(mToken)));

        unchecked {
            for (uint256 i = 0; i < configs.length; i++) {
                require(
                    tokens[i] != address(mToken),
                    "CompoundERC4626: cannot give allowance for mToken"
                );
                ERC20 token = ERC20(configs[i].emissionToken);
                token.approve(rewardHandler, MAX_INT); // infinite allowance
            }
        }
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

    /// @notice maximum amount of underlying tokens that can be deposited into the underlying protocol
    function maxDeposit(address) public view override returns (uint256) {
        return maxMint(address(0));
    }

    /// @notice Returns the maximum amount of tokens that can be supplied
    /// no way for this function to ever revert unless comptroller or mToken is broken
    /// @dev accrue interest must be called before this function is called, otherwise
    /// an outdated value will be fetched, and the returned value will be incorrect
    /// (greater than actual amount available to be minted will be returned)
    function maxMint(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(address(mToken))) {
            return 0;
        }

        uint256 supplyCap = comptroller.supplyCaps(address(mToken));
        if (supplyCap != 0) {
            uint256 currentExchangeRate = mToken.viewExchangeRate();
            uint256 _totalSupply = MToken(address(mToken)).totalSupply();
            uint256 totalSupplies = (_totalSupply * currentExchangeRate) / 1e18; /// exchange rate is scaled up by 1e18, so needs to be divided off to get accurate total supply

            // uint256 totalCash = MToken(address(mToken)).getCash();
            // uint256 totalBorrows = MToken(address(mToken)).totalBorrows();
            // uint256 totalReserves = MToken(address(mToken)).totalReserves();

            // // (Pseudocode) totalSupplies = totalCash + totalBorrows - totalReserves
            // uint256 totalSupplies = (totalCash + totalBorrows) - totalReserves;

            // supply cap is      3
            // total supplies is  1
            /// no room for additional supplies

            // supply cap is      3
            // total supplies is  0
            /// room for 1 additional supplies

            // supply cap is      4
            // total supplies is  1
            /// room for 1 additional supplies

            /// total supplies could exceed supply cap as interest accrues, need to handle this edge case
            /// going to subtract 2 from supply cap to account for rounding errors
            if (totalSupplies + 2 >= supplyCap) {
                return 0;
            }

            return supplyCap - totalSupplies - 2;
        }

        return type(uint256).max;
    }

    /// @notice maximum amount of underlying tokens that can be withdrawn
    /// @param owner The address that owns the shares
    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 cash = mToken.getCash();
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    /// @notice maximum amount of shares that can be withdrawn
    /// @param owner The address that owns the shares
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
