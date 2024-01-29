// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IStakedToken} from "./IStakedToken.sol";
import {Initializable} from "./Initializable.sol";
import {ITransferHook} from "./ITransferHook.sol";
import {IEcosystemReserve} from "./IEcosystemReserve.sol";
import {ERC20WithSnapshot} from "./ERC20WithSnapshot.sol";
import {DistributionTypes} from "./DistributionTypes.sol";
import {DistributionManager} from "./DistributionManager.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";

/**
 * @title StakedToken
 * @notice Contract to stake MFAM token, tokenize the position and get rewards, inheriting from a distribution manager contract
 * @author Moonwell
 **/
contract StakedToken is
    IStakedToken,
    ERC20WithSnapshot,
    Initializable,
    DistributionManager,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    IERC20 public STAKED_TOKEN;
    IERC20 public REWARD_TOKEN;
    uint256 public COOLDOWN_SECONDS;

    /// @notice Seconds available to redeem once the cooldown period is fullfilled
    uint256 public UNSTAKE_WINDOW;

    /// @notice Address to pull from the rewards, needs to have approved this contract
    address public REWARDS_VAULT;

    mapping(address => uint256) public stakerRewardsToClaim;
    mapping(address => uint256) public stakersCooldowns;

    event Staked(
        address indexed from,
        address indexed onBehalfOf,
        uint256 amount
    );
    event Redeem(address indexed from, address indexed to, uint256 amount);

    event RewardsAccrued(address user, uint256 amount);
    event RewardsClaimed(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    event Cooldown(address indexed user);

    // TODO add this back once figuring out about upgreadable on ERC20WithSnapshot
    /// @notice logic contract cannot be initialized
    //    constructor() public {
    //        _disableInitializers();
    //    }

    function __StakedToken_init(
        IERC20 stakedToken,
        IERC20 rewardToken,
        uint256 cooldownSeconds,
        uint256 unstakeWindow,
        address rewardsVault,
        address emissionManager,
        uint128 distributionDuration,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address governance
    ) internal initializer {
        __ReentrancyGuard_init();
        __ERC20_init_unchained(name, symbol, decimals);
        __DistributionManager_init_unchained(
            emissionManager,
            distributionDuration
        );
        __StakedToken_init_unchained(
            stakedToken,
            rewardToken,
            cooldownSeconds,
            unstakeWindow,
            rewardsVault,
            governance
        );
    }

    function __StakedToken_init_unchained(
        IERC20 stakedToken,
        IERC20 rewardToken,
        uint256 cooldownSeconds,
        uint256 unstakeWindow,
        address rewardsVault,
        address governance
    ) internal {
        STAKED_TOKEN = stakedToken;
        REWARD_TOKEN = rewardToken;
        COOLDOWN_SECONDS = cooldownSeconds;
        UNSTAKE_WINDOW = unstakeWindow;
        REWARDS_VAULT = rewardsVault;
        _setGovernance(ITransferHook(governance));
    }

    function stake(
        address onBehalfOf,
        uint256 amount
    ) external override nonReentrant {
        require(amount != 0, "INVALID_ZERO_AMOUNT");
        require(onBehalfOf != address(0), "STAKE_ZERO_ADDRESS");
        uint256 balanceOfUser = balanceOf(onBehalfOf);

        uint256 accruedRewards = _updateUserAssetInternal(
            onBehalfOf,
            address(this),
            balanceOfUser,
            totalSupply()
        );
        if (accruedRewards != 0) {
            emit RewardsAccrued(onBehalfOf, accruedRewards);
            stakerRewardsToClaim[onBehalfOf] = stakerRewardsToClaim[onBehalfOf]
                .add(accruedRewards);
        }

        stakersCooldowns[onBehalfOf] = getNextCooldownTimestamp(
            0,
            amount,
            onBehalfOf,
            balanceOfUser
        );

        _mint(onBehalfOf, amount);
        IERC20(STAKED_TOKEN).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        emit Staked(msg.sender, onBehalfOf, amount);
    }

    /**
     * @dev Redeems staked tokens, and stop earning rewards
     * @param to Address to redeem to
     * @param amount Amount to redeem
     **/
    function redeem(address to, uint256 amount) external override nonReentrant {
        require(amount != 0, "INVALID_ZERO_AMOUNT");
        require(to != address(0), "REDEEM_ZERO_ADDRESS");
        //solium-disable-next-line
        uint256 cooldownStartTimestamp = stakersCooldowns[msg.sender];
        require(
            block.timestamp > cooldownStartTimestamp.add(COOLDOWN_SECONDS),
            "INSUFFICIENT_COOLDOWN"
        );
        require(
            block.timestamp.sub(cooldownStartTimestamp.add(COOLDOWN_SECONDS)) <=
                UNSTAKE_WINDOW,
            "UNSTAKE_WINDOW_FINISHED"
        );
        uint256 balanceOfMessageSender = balanceOf(msg.sender);

        uint256 amountToRedeem = (amount > balanceOfMessageSender)
            ? balanceOfMessageSender
            : amount;

        _updateCurrentUnclaimedRewards(
            msg.sender,
            balanceOfMessageSender,
            true
        );

        _burn(msg.sender, amountToRedeem);

        if (balanceOfMessageSender.sub(amountToRedeem) == 0) {
            stakersCooldowns[msg.sender] = 0;
        }

        IERC20(STAKED_TOKEN).safeTransfer(to, amountToRedeem);

        emit Redeem(msg.sender, to, amountToRedeem);
    }

    /**
     * @dev Activates the cooldown period to unstake
     * - It can't be called if the user is not staking
     **/
    function cooldown() external override {
        require(balanceOf(msg.sender) != 0, "INVALID_BALANCE_ON_COOLDOWN");
        //solium-disable-next-line
        stakersCooldowns[msg.sender] = block.timestamp;

        emit Cooldown(msg.sender);
    }

    /**
     * @dev Claims an `amount` of `REWARD_TOKEN` to the address `to`
     * @param to Address to stake for
     * @param amount Amount to stake
     **/
    function claimRewards(
        address to,
        uint256 amount
    ) external override nonReentrant {
        uint256 newTotalRewards = _updateCurrentUnclaimedRewards(
            msg.sender,
            balanceOf(msg.sender),
            false
        );
        uint256 amountToClaim = (amount == type(uint256).max)
            ? newTotalRewards
            : amount;

        stakerRewardsToClaim[msg.sender] = newTotalRewards.sub(
            amountToClaim,
            "INVALID_AMOUNT"
        );

        IERC20(REWARD_TOKEN).safeTransferFrom(REWARDS_VAULT, to, amountToClaim);

        emit RewardsClaimed(msg.sender, to, amountToClaim);
    }

    /**
     * @dev Internal ERC20 _transfer of the tokenized staked tokens
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param amount Amount to transfer
     **/
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        uint256 balanceOfFrom = balanceOf(from);
        // Sender
        _updateCurrentUnclaimedRewards(from, balanceOfFrom, true);

        // Recipient
        if (from != to) {
            uint256 balanceOfTo = balanceOf(to);
            _updateCurrentUnclaimedRewards(to, balanceOfTo, true);

            uint256 previousSenderCooldown = stakersCooldowns[from];
            stakersCooldowns[to] = getNextCooldownTimestamp(
                previousSenderCooldown,
                amount,
                to,
                balanceOfTo
            );
            // if cooldown was set and whole balance of sender was transferred - clear cooldown
            if (balanceOfFrom == amount && previousSenderCooldown != 0) {
                stakersCooldowns[from] = 0;
            }
        }

        super._transfer(from, to, amount);
    }

    /**
     * @dev Updates the user state related with his accrued rewards
     * @param user Address of the user
     * @param userBalance The current balance of the user
     * @param updateStorage Boolean flag used to update or not the stakerRewardsToClaim of the user
     * @return The unclaimed rewards that were added to the total accrued
     **/
    function _updateCurrentUnclaimedRewards(
        address user,
        uint256 userBalance,
        bool updateStorage
    ) internal returns (uint256) {
        uint256 accruedRewards = _updateUserAssetInternal(
            user,
            address(this),
            userBalance,
            totalSupply()
        );
        uint256 unclaimedRewards = stakerRewardsToClaim[user].add(
            accruedRewards
        );

        if (accruedRewards != 0) {
            if (updateStorage) {
                stakerRewardsToClaim[user] = unclaimedRewards;
            }
            emit RewardsAccrued(user, accruedRewards);
        }

        return unclaimedRewards;
    }

    /**
     * @dev Calculates the how is gonna be a new cooldown timestamp depending on the sender/receiver situation
     *  - If the timestamp of the sender is "better" or the timestamp of the recipient is 0, we take the one of the recipient
     *  - Weighted average of from/to cooldown timestamps if:
     *    # The sender doesn't have the cooldown activated (timestamp 0).
     *    # The sender timestamp is expired
     *    # The sender has a "worse" timestamp
     *  - If the receiver's cooldown timestamp expired (too old), the next is 0
     * @param fromCooldownTimestamp Cooldown timestamp of the sender
     * @param amountToReceive Amount
     * @param toAddress Address of the recipient
     * @param toBalance Current balance of the receiver
     * @return The new cooldown timestamp
     **/
    function getNextCooldownTimestamp(
        uint256 fromCooldownTimestamp,
        uint256 amountToReceive,
        address toAddress,
        uint256 toBalance
    ) internal returns (uint256) {
        uint256 toCooldownTimestamp = stakersCooldowns[toAddress];
        if (toCooldownTimestamp == 0) {
            return 0;
        }

        uint256 minimalValidCooldownTimestamp = block
            .timestamp
            .sub(COOLDOWN_SECONDS)
            .sub(UNSTAKE_WINDOW);

        if (minimalValidCooldownTimestamp > toCooldownTimestamp) {
            toCooldownTimestamp = 0;
        } else {
            uint256 fromCooldownTimestampFinal = (minimalValidCooldownTimestamp >
                    fromCooldownTimestamp)
                    ? block.timestamp
                    : fromCooldownTimestamp;

            if (fromCooldownTimestampFinal < toCooldownTimestamp) {
                return toCooldownTimestamp;
            } else {
                toCooldownTimestamp = (
                    amountToReceive.mul(fromCooldownTimestampFinal).add(
                        toBalance.mul(toCooldownTimestamp)
                    )
                ).div(amountToReceive.add(toBalance));
            }
        }
        stakersCooldowns[toAddress] = toCooldownTimestamp;

        return toCooldownTimestamp;
    }

    /**
     * @dev Return the total rewards pending to claim by an staker
     * @param staker The staker address
     * @return The rewards
     */
    function getTotalRewardsBalance(
        address staker
    ) external view returns (uint256) {
        DistributionTypes.UserStakeInput[]
            memory userStakeInputs = new DistributionTypes.UserStakeInput[](1);
        userStakeInputs[0] = DistributionTypes.UserStakeInput({
            underlyingAsset: address(this),
            stakedByUser: balanceOf(staker),
            totalStaked: totalSupply()
        });
        return
            stakerRewardsToClaim[staker].add(
                _getUnclaimedRewards(staker, userStakeInputs)
            );
    }
}
