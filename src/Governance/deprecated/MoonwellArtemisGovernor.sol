pragma solidity ^0.8.17;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract MoonwellArtemisGovernor {
    /// @notice The name of this contract
    string public constant name = "Moonwell Artemis Governor";

    /// @notice Values for votes
    uint8 public constant voteValueYes = 0;
    uint8 public constant voteValueNo = 1;
    uint8 public constant voteValueAbstain = 2;

    /// @notice The number of votes for a proposal required in order for a quorum to be reached and for a vote to succeed
    uint public quorumVotes = 100000000e18; // 100,000,000 WELL

    /// @notice The number of votes required in order for a voter to become a proposer
    uint public proposalThreshold = 400000e18; // 400,000 WELL

    /// @notice The maximum number of actions that can be included in a proposal
    uint public proposalMaxOperations = 25; // 25 actions

    /// @notice The delay before voting on a proposal may take place, once proposed
    uint public votingDelay = 0;

    /// @notice The duration of voting on a proposal, in blocks
    uint public votingPeriod = 3 minutes;

    /// @notice The address of the Well Protocol Timelock
    TimelockInterface public timelock;

    /// @notice The address of the Well governance token
    WellInterface public well;

    /// @notice The address of the Distributor contract
    SnapshotInterface public distributor;

    /// @notice The address of the Safety Module contract
    SnapshotInterface public safetyModule;

    /// @notice The total number of proposals
    uint public proposalCount;

    /// @notice The address of the Break Glass Guardian
    /// This address can opt to call '_executeBreakGlass*' which will execute an operation to return governance to
    /// the governance return addres in the event a bug is found in governnce.
    address public breakGlassGuardian;

    /// @notice An address that can set the governance return address.
    address public governanceReturnGuardian;

    /// @notice The address that will receive control of governance when glass is broken.
    address public governanceReturnAddress;

    /// @notice The timestamp when guardians may be stripped of their power through a vote.
    uint256 public guardianSunset;

    struct Proposal {
        /// @notice Unique id for looking up a proposal
        uint id;
        /// @notice Creator of the proposal
        address proposer;
        /// @notice The timestamp that the proposal will be available for execution, set once the vote succeeds
        uint eta;
        /// @notice the ordered list of target addresses for calls to be made
        address[] targets;
        /// @notice The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        uint[] values;
        /// @notice The ordered list of function signatures to be called
        string[] signatures;
        /// @notice The ordered list of calldata to be passed to each call
        bytes[] calldatas;
        /// @notice The timestamp at which voting begins: holders must delegate their votes prior to this time
        uint startTimestamp;
        /// @notice The timestamp at which voting ends: votes must be cast prior to this time
        uint endTimestamp;
        /// @notice The block at which voting began: holders must have delegated their votes prior to this block
        uint startBlock;
        /// @notice Current number of votes in favor of this proposal
        uint forVotes;
        /// @notice Current number of votes in opposition to this proposal
        uint againstVotes;
        /// @notice Current number of votes in abstention to this proposal
        uint abstainVotes;
        /// @notice The total votes on a proposal.
        uint totalVotes;
        /// @notice Flag marking whether the proposal has been canceled
        bool canceled;
        /// @notice Flag marking whether the proposal has been executed
        bool executed;
        /// @notice Receipts of ballots for the entire set of voters
        mapping(address => Receipt) receipts;
    }

    /// @notice Ballot receipt record for a voter
    struct Receipt {
        /// @notice Whether or not a vote has been cast
        bool hasVoted;
        /// @notice The value of the vote.
        uint8 voteValue;
        /// @notice The number of votes the voter had, which were cast
        uint votes;
    }

    /// @notice Possible states that a proposal may be in
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    /// @notice The official record of all proposals ever proposed
    mapping(uint => Proposal) public proposals;

    /// @notice The latest proposal for each proposer
    mapping(address => uint) public latestProposalIds;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    /// @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,uint8 voteValue)");

    /// @notice An event emitted when a new proposal is created
    event ProposalCreated(
        uint id,
        address proposer,
        address[] targets,
        uint[] values,
        string[] signatures,
        bytes[] calldatas,
        uint startTimestamp,
        uint endTimestamp,
        string description
    );

    /// @notice An event emitted when the first vote is cast in a proposal
    event StartBlockSet(uint proposalId, uint startBlock);

    /// @notice An event emitted when a vote has been cast on a proposal
    event VoteCast(address voter, uint proposalId, uint8 voteValue, uint votes);

    /// @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint id);

    /// @notice An event emitted when a proposal has been queued in the Timelock
    event ProposalQueued(uint id, uint eta);

    /// @notice An event emitted when a proposal has been executed in the Timelock
    event ProposalExecuted(uint id);

    /// @notice An event emitted when thee quorum votes is changed.
    event QuroumVotesChanged(uint256 oldValue, uint256 newValue);

    /// @notice An event emitted when the proposal threshold is changed.
    event ProposalThresholdChanged(uint256 oldValue, uint256 newValue);

    /// @notice An event emitted when the proposal max operations is changed.
    event ProposalMaxOperationsChanged(uint256 oldValue, uint256 newValue);

    /// @notice An event emitted when the voting delay is changed.
    event VotingDelayChanged(uint256 oldValue, uint256 newValue);

    /// @notice An event emitted when the voting period is changed.
    event VotingPeriodChanged(uint256 oldValue, uint256 newValue);

    /// @notice An event emitted when the break glass guardian is changed.
    event BreakGlassGuardianChanged(address oldValue, address newValue);

    /// @notice An event emitted when the governance return address is changed.
    event GovernanceReturnAddressChanged(address oldValue, address newValue);

    constructor(
        address timelock_,
        address well_,
        address distributor_,
        address safetyModule_,
        address breakGlassGuardian_,
        address governanceReturnAddress_,
        address governanceReturnGuardian_,
        uint guardianSunset_
    ) {
        timelock = TimelockInterface(timelock_);
        well = WellInterface(well_);
        distributor = SnapshotInterface(distributor_);
        safetyModule = SnapshotInterface(safetyModule_);
        breakGlassGuardian = breakGlassGuardian_;
        governanceReturnAddress = governanceReturnAddress_;
        governanceReturnGuardian = governanceReturnGuardian_;
        guardianSunset = guardianSunset_;
    }

    function propose(
        address[] memory targets,
        uint[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) public returns (uint) {
        require(
            _getVotingPower(msg.sender, sub256(block.number, 1)) >
                proposalThreshold,
            "GovernorArtemis::propose: proposer votes below proposal threshold"
        );
        require(
            targets.length == values.length &&
                targets.length == signatures.length &&
                targets.length == calldatas.length,
            "GovernorArtemis::propose: proposal function information arity mismatch"
        );
        require(
            targets.length != 0,
            "GovernorArtemis::propose: must provide actions"
        );
        require(
            targets.length <= proposalMaxOperations,
            "GovernorArtemis::propose: too many actions"
        );
        require(bytes(description).length > 0, "description can not be empty");

        uint latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
            ProposalState proposersLatestProposalState = state(
                latestProposalId
            );
            require(
                proposersLatestProposalState != ProposalState.Active,
                "GovernorArtemis::propose: one live proposal per proposer, found an already active proposal"
            );
            require(
                proposersLatestProposalState != ProposalState.Pending,
                "GovernorArtemis::propose: one live proposal per proposer, found an already pending proposal"
            );
        }

        uint startTimestamp = add256(block.timestamp, votingDelay);
        uint endTimestamp = add256(
            block.timestamp,
            add256(votingPeriod, votingDelay)
        );

        proposalCount++;

        Proposal storage newProposal = proposals[proposalCount];
        newProposal.id = proposalCount;
        newProposal.proposer = msg.sender;
        newProposal.eta = 0;
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.signatures = signatures;
        newProposal.calldatas = calldatas;
        newProposal.startTimestamp = startTimestamp;
        newProposal.endTimestamp = endTimestamp;
        newProposal.startBlock = 0;
        newProposal.forVotes = 0;
        newProposal.againstVotes = 0;
        newProposal.abstainVotes = 0;
        newProposal.totalVotes = 0;
        newProposal.canceled = false;
        newProposal.executed = false;

        latestProposalIds[newProposal.proposer] = proposalCount;

        emit ProposalCreated(
            newProposal.id,
            msg.sender,
            targets,
            values,
            signatures,
            calldatas,
            startTimestamp,
            endTimestamp,
            description
        );
        return newProposal.id;
    }

    function queue(uint proposalId) public {
        require(
            state(proposalId) == ProposalState.Succeeded,
            "GovernorArtemis::queue: proposal can only be queued if it is succeeded"
        );
        Proposal storage proposal = proposals[proposalId];
        uint eta = add256(block.timestamp, timelock.delay());
        for (uint i = 0; i < proposal.targets.length; i++) {
            _queueOrRevert(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                eta
            );
        }
        proposal.eta = eta;
        emit ProposalQueued(proposalId, eta);
    }

    function _queueOrRevert(
        address target,
        uint value,
        string memory signature,
        bytes memory data,
        uint eta
    ) internal {
        require(
            !timelock.queuedTransactions(
                keccak256(abi.encode(target, value, signature, data, eta))
            ),
            "GovernorArtemis::_queueOrRevert: proposal action already queued at eta"
        );
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    function execute(uint proposalId) external {
        require(
            state(proposalId) == ProposalState.Queued,
            "GovernorArtemis::execute: proposal can only be executed if it is queued"
        );
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        for (uint i = 0; i < proposal.targets.length; i++) {
            timelock.executeTransaction(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                proposal.eta
            );
        }
        emit ProposalExecuted(proposalId);
    }

    function cancel(uint proposalId) public {
        ProposalState proposalState = state(proposalId);
        require(
            proposalState != ProposalState.Executed,
            "GovernorArtemis::cancel: cannot cancel executed proposal"
        );

        Proposal storage proposal = proposals[proposalId];
        require(
            _getVotingPower(proposal.proposer, sub256(block.number, 1)) <
                proposalThreshold,
            "GovernorArtemis::cancel: proposer above threshold"
        );

        proposal.canceled = true;
        for (uint i = 0; i < proposal.targets.length; i++) {
            timelock.cancelTransaction(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                proposal.eta
            );
        }

        emit ProposalCanceled(proposalId);
    }

    function getActions(
        uint proposalId
    )
        public
        view
        returns (
            address[] memory targets,
            uint[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        )
    {
        Proposal storage p = proposals[proposalId];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    function getReceipt(
        uint proposalId,
        address voter
    ) public view returns (Receipt memory) {
        return proposals[proposalId].receipts[voter];
    }

    function state(uint proposalId) public view returns (ProposalState) {
        require(
            proposalCount >= proposalId && proposalId > 0,
            "GovernorArtemis::state: invalid proposal id"
        );
        Proposal storage proposal = proposals[proposalId];

        // First check if the proposal cancelled.
        if (proposal.canceled) {
            return ProposalState.Canceled;
            // Then check if the proposal is pending or active, in which case nothing else can be determined at this time.
        } else if (block.timestamp <= proposal.startTimestamp) {
            return ProposalState.Pending;
        } else if (block.timestamp <= proposal.endTimestamp) {
            return ProposalState.Active;
            // Then, check if the proposal is defeated. To hit this case, either (1) majority of yay/nay votes were nay or
            // (2) total votes was less than the quorum amount.
        } else if (
            proposal.forVotes <= proposal.againstVotes ||
            proposal.totalVotes < quorumVotes
        ) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (
            block.timestamp >= add256(proposal.eta, timelock.GRACE_PERIOD())
        ) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    function castVote(uint proposalId, uint8 voteValue) public {
        return _castVote(msg.sender, proposalId, voteValue);
    }

    function castVoteBySig(
        uint256 proposalId,
        uint8 voteValue,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                getChainId(),
                address(this)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(BALLOT_TYPEHASH, proposalId, voteValue)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        address signatory = ecrecover(digest, v, r, s);
        require(
            signatory != address(0),
            "GovernorArtemis::castVoteBySig: invalid signature"
        );
        return _castVote(signatory, proposalId, voteValue);
    }

    function _castVote(
        address voter,
        uint proposalId,
        uint8 voteValue
    ) internal {
        require(
            state(proposalId) == ProposalState.Active,
            "GovernorArtemis::_castVote: voting is closed"
        );
        Proposal storage proposal = proposals[proposalId];
        if (proposal.startBlock == 0) {
            proposal.startBlock = block.number - 1;
            emit StartBlockSet(proposalId, block.number);
        }
        Receipt storage receipt = proposal.receipts[voter];
        require(
            receipt.hasVoted == false,
            "GovernorArtemis::_castVote: voter already voted"
        );
        uint votes = _getVotingPower(voter, proposal.startBlock);

        if (voteValue == voteValueYes) {
            proposal.forVotes = add256(proposal.forVotes, votes);
        } else if (voteValue == voteValueNo) {
            proposal.againstVotes = add256(proposal.againstVotes, votes);
        } else if (voteValue == voteValueAbstain) {
            proposal.abstainVotes = add256(proposal.abstainVotes, votes);
        } else {
            // Catch all. If an above case isn't matched then the value is not valid.
            revert("GovernorArtemis::_castVote: invalid vote value");
        }

        // Increase total votes
        proposal.totalVotes = add256(proposal.totalVotes, votes);

        receipt.hasVoted = true;
        receipt.voteValue = voteValue;
        receipt.votes = votes;

        emit VoteCast(voter, proposalId, voteValue, votes);
    }

    function _getVotingPower(
        address voter,
        uint blockNumber
    ) internal view returns (uint) {
        // Get votes from the WELL contract, the distributor contract, and the safety module contact.
        uint96 wellVotes = well.getPriorVotes(voter, blockNumber);
        uint distibutorVotes = distributor.getPriorVotes(voter, blockNumber);
        uint safetyModuleVotes = safetyModule.getPriorVotes(voter, blockNumber);

        return
            add256(add256(uint(wellVotes), distibutorVotes), safetyModuleVotes);
    }

    // @notice Sweeps all tokens owned by Governor alpha to the given destination address.
    function sweepTokens(
        address tokenAddress,
        address destinationAddress
    ) external {
        require(
            msg.sender == address(timelock),
            "GovernorArtemis::sweepTokens: sender must be timelock"
        );

        IERC20 token = IERC20(tokenAddress);
        uint balance = token.balanceOf(address(this));

        token.transfer(destinationAddress, balance);
    }

    /// Governance Introspection

    function setQuorumVotes(uint newValue) external {
        require(msg.sender == address(timelock), "only timelock");

        uint256 oldValue = quorumVotes;

        quorumVotes = newValue;
        emit QuroumVotesChanged(oldValue, newValue);
    }

    function setProposalThreshold(uint newValue) external {
        require(msg.sender == address(timelock), "only timelock");

        uint256 oldValue = proposalThreshold;

        proposalThreshold = newValue;
        emit ProposalThresholdChanged(oldValue, newValue);
    }

    function setVotingDelay(uint newValue) external {
        require(msg.sender == address(timelock), "only timelock");

        uint256 oldValue = votingDelay;

        votingDelay = newValue;
        emit VotingDelayChanged(oldValue, newValue);
    }

    function setProposalMaxOperations(uint newValue) external {
        require(msg.sender == address(timelock), "only timelock");

        uint256 oldValue = proposalMaxOperations;

        proposalMaxOperations = newValue;
        emit ProposalMaxOperationsChanged(oldValue, newValue);
    }

    function setVotingPeriod(uint newValue) external {
        require(msg.sender == address(timelock), "only timelock");

        uint256 oldValue = votingPeriod;

        votingPeriod = newValue;
        emit VotingPeriodChanged(oldValue, newValue);
    }

    function setBreakGlassGuardian(address newGuardian) external {
        require(msg.sender == breakGlassGuardian, "only break glass guardian");

        address oldValue = breakGlassGuardian;

        breakGlassGuardian = newGuardian;
        emit BreakGlassGuardianChanged(oldValue, newGuardian);
    }

    /// Governance Return Guardian

    /// @notice Sets the address that governance will be returned to in an emergency. Only callable by the governance return guardian.
    function __setGovernanceReturnAddress(
        address governanceReturnAddress_
    ) external {
        require(
            msg.sender == governanceReturnGuardian,
            "GovernorArtemis::__setGovernanceReturnAddress: sender must be gov return guardian"
        );

        address oldValue = governanceReturnAddress;

        governanceReturnAddress = governanceReturnAddress_;

        emit GovernanceReturnAddressChanged(oldValue, governanceReturnAddress_);
    }

    /// Break Glass Guardian - Emergency Declarations

    /// @notice Fast tracks calling _setPendingAdmin on the given contracts through the timelock. Only callable by the break glass guardian.
    function __executeBreakGlassOnCompound(
        CompoundSetPendingAdminInterface[] calldata addresses
    ) external {
        require(
            msg.sender == breakGlassGuardian,
            "GovernorArtemis::__breakglass: sender must be bg guardian"
        );

        uint length = addresses.length;
        for (uint i = 0; i < length; ++i) {
            timelock.fastTrackExecuteTransaction(
                address(addresses[i]),
                0,
                "_setPendingAdmin(address)",
                abi.encode(governanceReturnAddress)
            );
        }
    }

    /// @notice Fast tracks calling setAdmin on the given contracts through the timelock. Only callable by the break glass guardian.
    function __executeBreakGlassOnSetAdmin(
        SetAdminInterface[] calldata addresses
    ) external {
        require(
            msg.sender == breakGlassGuardian,
            "GovernorArtemis::__breakglass: sender must be bg guardian"
        );

        uint length = addresses.length;
        for (uint i = 0; i < length; ++i) {
            timelock.fastTrackExecuteTransaction(
                address(addresses[i]),
                0,
                "setAdmin(address)",
                abi.encode(governanceReturnAddress)
            );
        }
    }

    /// @notice Fast tracks calling setPendingAdmin on the given contracts through the timelock. Only callable by the break glass guardian.
    function __executeBreakGlassOnSetPendingAdmin(
        SetPendingAdminInterface[] calldata addresses
    ) external {
        require(
            msg.sender == breakGlassGuardian,
            "GovernorArtemis::__breakglass: sender must be bg guardian"
        );

        uint length = addresses.length;
        for (uint i = 0; i < length; ++i) {
            timelock.fastTrackExecuteTransaction(
                address(addresses[i]),
                0,
                "setPendingAdmin(address)",
                abi.encode(governanceReturnAddress)
            );
        }
    }

    /// @notice Fast tracks calling changeAdmin on the given contracts through the timelock. Only callable by the break glass guardian.
    function __executeBreakGlassOnChangeAdmin(
        ChangeAdminInterface[] calldata addresses
    ) external {
        require(
            msg.sender == breakGlassGuardian,
            "GovernorArtemis::__breakglass: sender must be bg guardian"
        );

        uint length = addresses.length;
        for (uint i = 0; i < length; ++i) {
            timelock.fastTrackExecuteTransaction(
                address(addresses[i]),
                0,
                "changeAdmin(address)",
                abi.encode(governanceReturnAddress)
            );
        }
    }

    /// @notice Fast tracks calling transferOwnership on the given contracts through the timelock. Only callable by the break glass guardian.
    function __executeBreakGlassOnOwnable(
        OwnableInterface[] calldata addresses
    ) external {
        require(
            msg.sender == breakGlassGuardian,
            "GovernorArtemis::__breakglass: sender must be bg guardian"
        );

        uint length = addresses.length;
        for (uint i = 0; i < length; ++i) {
            timelock.fastTrackExecuteTransaction(
                address(addresses[i]),
                0,
                "transferOwnership(address)",
                abi.encode(governanceReturnAddress)
            );
        }
    }

    /// @notice Fast tracks setting an emissions manager on the given contracts through the timelock. Only callable by the break glass guardian.
    function __executeBreakGlassOnEmissionsManager(
        SetEmissionsManagerInterface[] calldata addresses
    ) external {
        require(
            msg.sender == breakGlassGuardian,
            "GovernorArtemis::__breakglass: sender must be bg guardian"
        );

        uint length = addresses.length;
        for (uint i = 0; i < length; ++i) {
            timelock.fastTrackExecuteTransaction(
                address(addresses[i]),
                0,
                "setEmissionsManager(address)",
                abi.encode(governanceReturnAddress)
            );
        }
    }

    /// Break Glass Guardian - Recovery Operations

    /// @notice Fast tracks calling _acceptAdmin through the timelock for the given targets.
    function __executeCompoundAcceptAdminOnContract(
        address[] calldata addresses
    ) external {
        require(
            msg.sender == breakGlassGuardian,
            "GovernorArtemis::__executeCompoundAcceptAdminOnContract: sender must be bg guardian"
        );

        uint length = addresses.length;
        for (uint i = 0; i < length; ++i) {
            timelock.fastTrackExecuteTransaction(
                addresses[i],
                0,
                "_acceptAdmin()",
                abi.encode()
            );
        }
    }

    /// @notice Fast tracks calling acceptPendingAdmin through the timelock for the given targets.
    function __executeAcceptAdminOnContract(
        address[] calldata addresses
    ) external {
        require(
            msg.sender == breakGlassGuardian,
            "GovernorArtemis::__executeAcceptAdminOnContract: sender must be bg guardian"
        );

        uint length = addresses.length;
        for (uint i = 0; i < length; ++i) {
            timelock.fastTrackExecuteTransaction(
                addresses[i],
                0,
                "acceptPendingAdmin()",
                abi.encode()
            );
        }
    }

    /// Break Glass Guardian - Timelock Management

    /// @notice Calls accept admin on the timelock. Only callable by the break glass guardian.
    function __acceptAdminOnTimelock() external {
        require(
            msg.sender == breakGlassGuardian,
            "GovernorArtemis::__acceptAdmin: sender must be bg guardian"
        );
        timelock.acceptAdmin();
    }

    /// Guardian Removeal

    /// @notice Removes Guardians from the governance process. Can only be called by the timelock. This is an irreversible operation.
    function __removeGuardians() external {
        // Removing power can only come via a governance vote, which will be executed from the timelock.
        require(
            msg.sender == address(timelock),
            "GovernorArtemis::__removeGuardians: sender must be the timelock"
        );

        // Removing the governance guardian can only occur after the sunset.
        require(
            block.timestamp >= guardianSunset,
            "GovernorArtemis::__removeGuardians cannot remove before sunset"
        );

        // Set both guardians to the zero address.
        breakGlassGuardian = address(0);
        governanceReturnGuardian = address(0);
    }

    function add256(uint256 a, uint256 b) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, "addition overflow");
        return c;
    }

    function sub256(uint256 a, uint256 b) internal pure returns (uint) {
        require(b <= a, "subtraction underflow");
        return a - b;
    }

    function getChainId() internal view returns (uint) {
        uint chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}

interface TimelockInterface {
    function delay() external view returns (uint);

    function GRACE_PERIOD() external view returns (uint);

    function acceptAdmin() external;

    function queuedTransactions(bytes32 hash) external view returns (bool);

    function queueTransaction(
        address target,
        uint value,
        string calldata signature,
        bytes calldata data,
        uint eta
    ) external returns (bytes32);

    function cancelTransaction(
        address target,
        uint value,
        string calldata signature,
        bytes calldata data,
        uint eta
    ) external;

    function executeTransaction(
        address target,
        uint value,
        string calldata signature,
        bytes calldata data,
        uint eta
    ) external payable returns (bytes memory);

    function fastTrackExecuteTransaction(
        address target,
        uint value,
        string calldata signature,
        bytes calldata data
    ) external payable returns (bytes memory);
}

interface WellInterface {
    function getPriorVotes(
        address account,
        uint blockNumber
    ) external view returns (uint96);
}

interface SnapshotInterface {
    function getPriorVotes(
        address account,
        uint blockNumber
    ) external view returns (uint256);
}

// Used on Compound Contracts - Unitroller, MTokens
interface CompoundSetPendingAdminInterface {
    function _setPendingAdmin(address newPendingAdmin) external;
}

// Used on Chainlink Oracle
interface SetAdminInterface {
    function setAdmin(address newAdmin) external;
}

// Used on TokenSaleDistributor
interface SetPendingAdminInterface {
    function setPendingAdmin(address newAdmin) external;
}

// Used on safety ProxyAdmin
interface SetEmissionsManagerInterface {
    function setEmissionsManager(address newEmissionsManager) external;
}

// Used on safety module ProxyAdmin
interface ChangeAdminInterface {
    function changeAdmin(address newAdmin) external;
}

// Used on Ownable contracts - EcoystemReserveController
interface OwnableInterface {
    function transferOwnership(address newOwner) external;
}
