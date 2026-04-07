pragma solidity 0.8.19;

import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";

/// @notice Wormhole Bridge Base Contract
/// Useful or when you want to send to and receive from the same addresses
/// on many different chains
abstract contract WormholeBridgeBase {
    using EnumerableSet for EnumerableSet.UintSet;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ---------------------- CONSTANTS ------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice Wormhole consistency level for publishMessage.
    /// 1 = finalized: on Ethereum this means L1 finality (~15 min);
    ///                on Base/Optimism this means L2 safe head finality.
    uint8 public constant CONSISTENCY_LEVEL = 1;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------------ SINGLE STORAGE SLOT ------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @dev packing these variables into a single slot saves a
    /// COLD SLOAD on bridge out operations.

    /// @notice gas limit for wormhole relayer, changeable incase gas prices change on external network
    uint96 public gasLimit;

    /// @notice address of the wormhole relayer cannot be changed by owner
    /// @dev DEPRECATED
    /// because the relayer contract is a proxy and should never change its address
    IWormholeRelayer public wormholeRelayer;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ----------------------- MAPPINGS ------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice nonces that have already been processed
    /// @dev DEPRECATED — used by the old Wormhole standard relayer path.
    ///      Superseded by processedVAAHashes in leaf contracts. Retained
    ///      to preserve storage layout for upgradeable proxies.
    mapping(bytes32 nonce => bool processed) public processedNonces;

    /// @notice chain id of the target chain to address for bridging
    /// starts off mapped to itself, but can be changed by governance
    mapping(uint16 chainId => address target) public targetAddress;

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// -------------------- STATE VARIABLES -------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice set of target chains to bridge out to
    /// @dev values are less or equal to 2^16 - 1, as add function takes uint16 as parameter
    /// should be impossible to ever have duplicate values in this set
    /// the reason being that the add function only adds if the value is not already in the set
    EnumerableSet.UintSet internal _targetChains;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------------------ EVENTS -------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice chain id of the target chain to address for bridging
    /// @param dstChainId destination chain id to send tokens to
    /// @param target address to send tokens to
    event TargetAddressUpdated(
        uint16 indexed dstChainId,
        address indexed target
    );

    /// @notice emitted when the gas limit changes on external chains
    /// @param oldGasLimit old gas limit
    /// @param newGasLimit new gas limit
    event GasLimitUpdated(uint96 oldGasLimit, uint96 newGasLimit);

    /// @notice emitted when a bridge out fails
    /// @param dstChainId destination chain id to send tokens to
    /// @param payload payload that failed to send
    /// @param refundAmount amount to refund
    event BridgeOutFailed(
        uint16 dstChainId,
        bytes payload,
        uint256 refundAmount
    );

    /// @notice event emitted when a bridge out succeeds
    /// @param dstWormholeChainId destination wormhole chain id to send tokens to
    /// @param cost cost of the bridge out
    /// @param dst destination address to send tokens to
    /// @param payload payload that was sent
    event BridgeOutSuccess(
        uint16 dstWormholeChainId,
        uint256 cost,
        address dst,
        bytes payload
    );

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------------------ HELPERS ------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice set a gas limit for the relayer on the external chain
    /// should only be called if there is a change in gas prices on the external chain
    /// @param newGasLimit new gas limit to set
    function _setGasLimit(uint96 newGasLimit) internal {
        uint96 oldGasLimit = gasLimit;
        gasLimit = newGasLimit;

        emit GasLimitUpdated(oldGasLimit, newGasLimit);
    }

    /// @notice add map of target addresses for external chains
    /// @dev there is no check here to ensure there isn't an existing configuration
    /// ensure the proper add or remove is being called when using this function
    /// @param _chainConfig array of chainids to addresses to add
    function _addTargetAddresses(
        WormholeTrustedSender.TrustedSender[] memory _chainConfig
    ) internal {
        for (uint256 i = 0; i < _chainConfig.length; ) {
            _addTargetAddress(_chainConfig[i].chainId, _chainConfig[i].addr);

            unchecked {
                i++;
            }
        }
    }

    /// @notice add map of target addresses for external chains
    /// @param chainId chain id to add
    /// @param addr address to add
    function _addTargetAddress(uint16 chainId, address addr) internal {
        require(
            targetAddress[chainId] == address(0),
            "WormholeBridge: chain already added"
        );
        require(addr != address(0), "WormholeBridge: invalid target address");

        /// this code should be unreachable
        require(
            _targetChains.add(chainId),
            "WormholeBridge: chain already added to set"
        );

        targetAddress[chainId] = addr;

        emit TargetAddressUpdated(chainId, addr);
    }

    /// @notice remove map of target addresses for external chains
    /// @dev there is no check here to ensure there isn't an existing configuration
    /// ensure the proper add or remove is being called when using this function
    /// @param _chainConfig array of chainids to addresses to remove
    function _removeTargetAddresses(
        WormholeTrustedSender.TrustedSender[] memory _chainConfig
    ) internal {
        for (uint256 i = 0; i < _chainConfig.length; ) {
            uint16 chainId = _chainConfig[i].chainId;
            targetAddress[chainId] = address(0);
            require(
                _targetChains.remove(chainId),
                "WormholeBridge: chain not added"
            );

            emit TargetAddressUpdated(chainId, address(0));

            unchecked {
                i++;
            }
        }
    }

    /// @notice sets the wormhole relayer contract
    /// @param _wormholeRelayer address of the wormhole relayer
    function _setWormholeRelayer(address _wormholeRelayer) internal {
        require(
            address(wormholeRelayer) == address(0),
            "WormholeBridge: relayer already set"
        );

        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ---------------- View Only Functions -------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice returns all target wormhole chain ids for this contract instance
    function getAllTargetChains() external view returns (uint16[] memory) {
        uint256 chainsLength = _targetChains.length();
        uint16[] memory chains = new uint16[](chainsLength);

        for (uint256 i = 0; i < chainsLength; ) {
            chains[i] = uint16(_targetChains.at(i));
            unchecked {
                i++;
            }
        }

        return chains;
    }

    /// @notice returns the length of the target chains set
    function getAllTargetChainsLength() external view returns (uint256) {
        return _targetChains.length();
    }

    /// @notice Estimate bridge cost to bridge out to a destination chain.
    ///         Returns the Wormhole core messageFee (currently 0 on all chains).
    ///         The deprecated relayer quoter is no longer called since we use
    ///         direct publishMessage via Wormhole core.
    function bridgeCost(uint16) public view returns (uint256) {
        return _wormhole().messageFee();
    }

    /// @notice Estimate bridge cost to bridge out to all chains
    function bridgeCostAll() public view returns (uint256) {
        uint256 totalCost = 0;

        uint256 chainsLength = _targetChains.length();
        for (uint256 i = 0; i < chainsLength; ) {
            totalCost += bridgeCost(uint16(_targetChains.at(i)));
            unchecked {
                i++;
            }
        }

        return totalCost;
    }

    /// @notice returns whether or not the address is in the trusted senders list for a given chain
    /// @param chainId The wormhole chain id to check
    /// @param addr The address to check
    function isTrustedSender(
        uint16 chainId,
        bytes32 addr
    ) public view returns (bool) {
        return isTrustedSender(chainId, fromWormholeFormat(addr));
    }

    /// @notice returns whether or not the address is in the trusted senders list for a given chain
    /// @param chainId The wormhole chain id to check
    /// @param addr The address to check
    function isTrustedSender(
        uint16 chainId,
        address addr
    ) public view returns (bool) {
        return targetAddress[chainId] == addr;
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// -------------------- Bridge In/Out ---------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice Bridge Out Funds to all external chains.
    /// @param payload Payload to send to the external chain
    function _bridgeOutAll(bytes memory payload) internal {
        require(
            msg.value >= bridgeCostAll(),
            "WormholeBridge: total cost not equal to quote"
        );

        uint256 chainsLength = _targetChains.length();

        uint256 totalRefundAmount = msg.value;

        for (uint256 i = 0; i < chainsLength; ) {
            uint16 targetChain = uint16(_targetChains.at(i));
            uint256 cost = bridgeCost(targetChain);

            try
                _wormhole().publishMessage{value: cost}(
                    0,
                    abi.encode(
                        targetChain,
                        targetAddress[targetChain],
                        payload
                    ),
                    CONSISTENCY_LEVEL
                )
            {
                totalRefundAmount -= cost;
                emit BridgeOutSuccess(
                    targetChain,
                    cost,
                    targetAddress[targetChain],
                    payload
                );
            } catch {
                emit BridgeOutFailed(targetChain, payload, cost);
            }

            unchecked {
                i++;
            }
        }

        if (totalRefundAmount != 0) {
            /// send bridge funds back to sender using call
            (bool success, ) = msg.sender.call{value: totalRefundAmount}("");
            require(success, "WormholeBridge: refund failed");
        }
    }

    /// @notice Process a guardian-signed VAA to complete a payload transfer.
    ///         Callable by anyone (permissionless). The VAA must be signed by
    ///         the Wormhole guardian quorum. The emitter must be a trusted sender
    /// @param signedVAA The full guardian-signed VAA bytes
    function processVAA(bytes calldata signedVAA) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = _wormhole()
            .parseAndVerifyVM(signedVAA);

        require(valid, reason);
        require(
            isTrustedSender(vm.emitterChainId, vm.emitterAddress),
            "untrusted emitter"
        );

        require(!_isVAAHashProcessed(vm.hash), "VAA already processed");
        _setVAAHashProcessed(vm.hash);

        /// Parse the target
        (uint16 targetChain, address targetContract, bytes memory payload) = abi
            .decode(vm.payload, (uint16, address, bytes));

        /// Validate we are the target
        require(
            targetChain == _wormhole().chainId() &&
                targetContract == address(this),
            "invalid target"
        );

        _bridgeIn(vm.emitterChainId, payload);
    }

    /// @notice converts a bytes32 to address,
    /// wormhole stores the address in the first 20 bytes
    /// so if we shift right by 160 bits and there is still
    /// a non zero value, we know we have the wrong address
    /// @param whFormatAddress the bytes32 address to convert
    /// @return the address
    function fromWormholeFormat(
        bytes32 whFormatAddress
    ) public pure returns (address) {
        require(
            uint256(whFormatAddress) >> 160 == 0,
            "WormholeBridge: invalid address"
        );

        return address(uint160(uint256(whFormatAddress)));
    }

    // @notice logic for bringing payload in from external chain
    // @dev must be overridden by implementation contract
    // @param sourceChain the chain id of the source chain
    // @param payload the payload of the message
    function _bridgeIn(
        uint16 sourceChain,
        bytes memory payload
    ) internal virtual;

    /// @notice return the wormhole core contract
    function _wormhole() internal view virtual returns (IWormhole);

    /// @notice check if a VAA hash has already been processed (replay protection).
    ///         Storage lives in the leaf contract to avoid shifting existing slots.
    function _isVAAHashProcessed(
        bytes32 hash
    ) internal view virtual returns (bool);

    /// @notice mark a VAA hash as processed.
    function _setVAAHashProcessed(bytes32 hash) internal virtual;
}
