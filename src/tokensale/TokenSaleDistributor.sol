// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./TokenSaleDistributorStorage.sol";
import "./TokenSaleDistributorProxy.sol";
import "./ReentrancyGuard.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract TokenSaleDistributor is ReentrancyGuard, TokenSaleDistributorStorage {
    using SafeERC20 for IERC20;

    event Claimed(address indexed recipient, uint amount);

    /** The token address was set by the administrator. */
    event AdminSetToken(address tokenAddress);

    /** The administratory withdrew tokens. */
    event AdminWithdrewTokens(address tokenAddress, uint amount, address targetAddress);

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    /// @notice An event thats emitted when the voting enabled property changes.
    event VotingEnabledChanged(bool oldValue, bool newValue);

    /// @notice A record of each accounts delegate
    mapping (address => address) public delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;
    
    /// @notice Whether or not voting is enabled.
    bool public votingEnabled;

    /// @notice EIP-20 token name for this token
    string public constant name = "vWELL";

    function getChainId() internal view returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(address delegatee, uint nonce, uint expiry, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (address signatory, ECDSA.RecoverError error) = ECDSA.tryRecover(digest, v, r, s);

        require(error == ECDSA.RecoverError.NoError, "invalid sig");
        require(signatory != address(0), "invalid sig");
        require(nonce == nonces[signatory]++, "invalid nonce");
        require(block.timestamp <= expiry, "signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint) {
        // No users have any voting power if voting is disabled.
        if (!votingEnabled) {
            return 0;
        }

        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints != 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber) external view returns (uint) {
        require(blockNumber < block.number, "not yet determined");

        // No users have any voting power if voting is disabled.
        if (!votingEnabled) {
            return 0;
        }

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint delegatorBalance = totalVotingPower(delegator);
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint amount) internal {
        if (srcRep != dstRep && amount != 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint srcRepOld = srcRepNum != 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint srcRepNew = srcRepOld - amount;
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint dstRepOld = dstRepNum != 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint dstRepNew = dstRepOld + amount;
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint oldVotes, uint newVotes) internal {
      uint32 blockNumber = uint32(block.number);
      
      if (nCheckpoints != 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
          checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
      } else {
          checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
          numCheckpoints[delegatee] = nCheckpoints + 1;
      }

      emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function totalVotingPower(address user) public view returns (uint) {
        uint totalAllocatedToUser = totalAllocated(user);
        uint totalClaimedByUser = totalClaimed(user);
        return totalAllocatedToUser - totalClaimedByUser;
    }

    /********************************************************
     *                                                      *
     *                   PUBLIC FUNCTIONS                   *
     *                                                      *
     ********************************************************/

    /**
     * @notice Claim the tokens that have already vested
     */
    function claim() external nonReentrant {
        uint claimed;

        uint length = allocations[msg.sender].length;
        for (uint i; i < length; ++i) {
            claimed += _claim(allocations[msg.sender][i]);
        }

        if (claimed != 0) {
            emit Claimed(msg.sender, claimed);
            _moveDelegates(delegates[msg.sender], address(0), claimed);
        }
    }

    /**
     * @notice Get the total number of allocations for `recipient`
     */
    function totalAllocations(address recipient) external view returns (uint) {
        return allocations[recipient].length;
    }

    /**
     * @notice Get all allocations for `recipient`
     */
    function getUserAllocations(address recipient) external view returns (Allocation[] memory) {
        return allocations[recipient];
    }

    /**
     * @notice Get the total amount of tokens allocated for `recipient`
     */
    function totalAllocated(address recipient) public view returns (uint) {
        uint total;

        uint length = allocations[recipient].length;
        for (uint i; i < length; ++i) {
            total += allocations[recipient][i].amount;
        }

        return total;
    }

    /**
     * @notice Get the total amount of vested tokens for `recipient` so far
     */
    function totalVested(address recipient) external view returns (uint) {
        uint tokensVested;

        uint length = allocations[recipient].length;
        for (uint i; i < length; ++i) {
            tokensVested += _vested(allocations[recipient][i]);
        }

        return tokensVested;
    }

    /**
     * @notice Get the total amount of claimed tokens by `recipient`
     */
    function totalClaimed(address recipient) public view returns (uint) {
        uint total;

        uint length = allocations[recipient].length;
        for (uint i; i < length; ++i) {
            total += allocations[recipient][i].claimed;
        }

        return total;
    }

    /**
     * @notice Get the total amount of claimable tokens by `recipient`
     */
    function totalClaimable(address recipient) external view returns (uint) {
        uint total;

        uint length = allocations[recipient].length;
        for (uint i; i < length; ++i) {
            total += _claimable(allocations[recipient][i]);
        }

        return total;
    }

    /********************************************************
     *                                                      *
     *               ADMIN-ONLY FUNCTIONS                   *
     *                                                      *
     ********************************************************/

    /**
     * @notice Set the amount of purchased tokens per user.
     * @param recipients Token recipients
     * @param isLinear Allocation types
     * @param epochs Vesting epochs
     * @param vestingDurations Vesting period lengths
     * @param cliffs Vesting cliffs, if any
     * @param cliffPercentages Vesting cliff unlock percentages, if any
     * @param amounts Purchased token amounts
     */
    function setAllocations(
        address[] memory recipients,
        bool[] memory isLinear,
        uint[] memory epochs,
        uint[] memory vestingDurations,
        uint[] memory cliffs,
        uint[] memory cliffPercentages,
        uint[] memory amounts
    )
        external
        adminOnly
    {
        require(recipients.length == epochs.length);
        require(recipients.length == isLinear.length);
        require(recipients.length == vestingDurations.length);
        require(recipients.length == cliffs.length);
        require(recipients.length == cliffPercentages.length);
        require(recipients.length == amounts.length);

        uint length = recipients.length;
        for (uint i; i < length; ++i) {
            require(cliffPercentages[i] <= 1e18);

            allocations[recipients[i]].push(
                Allocation(
                    isLinear[i],
                    epochs[i],
                    vestingDurations[i],
                    cliffs[i],
                    cliffPercentages[i],
                    amounts[i],
                    0
                )
            );

            _moveDelegates(address(0), delegates[recipients[i]], amounts[i]);
        }
    }

    /**
     * @notice Reset all claims data for the given addresses and transfer tokens to the admin.
     * @param targetUser The address data to reset. This will also reduce the voting power of these users.
     */
    function resetAllocationsByUser(address targetUser) external adminOnly {
        // Get the user's current total voting power, which is the number of unclaimed tokens in the contract
        uint votingPower = totalVotingPower(targetUser);
        
        // Decrease the voting power to zero
        _moveDelegates(delegates[targetUser], address(0), votingPower);

        // Delete all allocations
        delete allocations[targetUser];
    
        // Withdraw tokens associated with the user's voting power
        if (votingPower != 0) {
             IERC20(tokenAddress).safeTransfer(admin, votingPower);
        }
        emit AdminWithdrewTokens(tokenAddress, votingPower, admin);
    }

    /**
     * @notice Withdraw deposited tokens from the contract. This method cannot be used with the reward token
     *
     * @param token The token address to withdraw
     * @param amount Amount to withdraw from the contract balance
     */
    function withdraw(address token, uint amount) external adminOnly {
        require(token != tokenAddress, "use resetAllocationsByUser");

        if (amount != 0) {
            IERC20(token).safeTransfer(admin, amount);
        }
    }

    /**
     * @notice Enables or disables voting for all users on this contract, in case of emergency.
     * @param enabled Whether or not voting should be allowed
     */
     function setVotingEnabled(bool enabled) external adminOnly {
        // Cache old value.
        bool oldValue = votingEnabled;

        votingEnabled = enabled;

        emit VotingEnabledChanged(oldValue, votingEnabled);
     }

    /**
     * @notice Set the vested token address
     * @param newTokenAddress ERC-20 token address
     */
    function setTokenAddress(address newTokenAddress) external adminOnly {
        require(tokenAddress == address(0), "address already set");
        tokenAddress = newTokenAddress;

        emit AdminSetToken(newTokenAddress);
    }

    /**
     * @notice Accept this contract as the implementation for a proxy.
     * @param proxy TokenSaleDistributorProxy
     */
    function becomeImplementation(TokenSaleDistributorProxy proxy) external {
        require(msg.sender == proxy.admin(), "not proxy admin");
        proxy.acceptPendingImplementation();
    }

    /********************************************************
     *                                                      *
     *                  INTERNAL FUNCTIONS                  *
     *                                                      *
     ********************************************************/

    /**
     * @notice Calculate the amount of vested tokens at the time of calling
     * @return Amount of vested tokens
     */
    function _vested(Allocation memory allocation) internal view returns (uint) {
        if (block.timestamp < allocation.epoch + allocation.cliff) {
            return 0;
        }

        uint initialAmount = allocation.amount * allocation.cliffPercentage / 1e18;
        uint postCliffAmount = allocation.amount - initialAmount;
        uint elapsed = block.timestamp - allocation.epoch - allocation.cliff;

        if (allocation.isLinear) {
            if (elapsed >= allocation.vestingDuration) {
                return allocation.amount;
            }

            return initialAmount + (postCliffAmount * elapsed / allocation.vestingDuration);
        }

        uint elapsedPeriods = elapsed / monthlyVestingInterval;
        if (elapsedPeriods >= allocation.vestingDuration) {
            return allocation.amount;
        }

        uint monthlyVestedAmount = postCliffAmount / allocation.vestingDuration;

        return initialAmount + (monthlyVestedAmount * elapsedPeriods);
    }

    /**
     * @notice Get the amount of claimable tokens for `allocation`
     */
    function _claimable(Allocation memory allocation) internal view returns (uint) {
        return _vested(allocation) - allocation.claimed;
    }

    /**
     * @notice Claim all vested tokens from the allocation
     * @return The amount of claimed tokens
     */
    function _claim(Allocation storage allocation) internal returns (uint) {
        uint claimable = _claimable(allocation);
        if (claimable == 0) {
            return 0;
        }

        allocation.claimed += claimable;
        IERC20(tokenAddress).safeTransfer(msg.sender, claimable);

        return claimable;
    }

    modifier adminOnly {
        require(msg.sender == admin, "admin only");
        _;
    }
}
