pragma solidity 0.8.19;

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {IWormholeReceiver} from "@protocol/wormhole/IWormholeReceiver.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/// @notice Wormhole Bridge Base Contract
/// Useful or when you want to send to and receive from the same addresses
/// on many different chains
abstract contract WormholeBridgeBase is IWormholeReceiver {
    using EnumerableSet for EnumerableSet.UintSet;

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
    /// because the relayer contract is a proxy and should never change its address
    IWormholeRelayer public wormholeRelayer;

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ----------------------- MAPPINGS ------------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice nonces that have already been processed
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

    /// @notice Estimate bridge cost to bridge out to a destination chain
    /// @dev this function returns 0 if the quote fails.
    /// in all other cases, the value returned should be non zero.
    /// @param dstWormholeChainId Destination chain id
    function bridgeCost(
        uint16 dstWormholeChainId
    ) public view returns (uint256 gasCost) {
        try
            wormholeRelayer.quoteEVMDeliveryPrice(
                dstWormholeChainId,
                0,
                gasLimit
            )
        returns (uint256 cost, uint256) {
            gasCost = cost;
        } catch {
            /// this is a bad situation, but we still want to allow the bridge out
            /// so fail silently and set gasCost to 0.
            /// Would like to emit an event here, but that would be a side affect
            /// to the logs and cause this function to be non view.
            /// the bridge out will most likely fail from this point out, however,
            /// the proposal on Moonbeam will still be created.
            gasCost = 0;
        }
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
            bridgeCostAll() == msg.value,
            "WormholeBridge: total cost not equal to quote"
        );

        uint256 chainsLength = _targetChains.length();

        uint256 totalRefundAmount = 0;

        for (uint256 i = 0; i < chainsLength; ) {
            uint16 targetChain = uint16(_targetChains.at(i));
            uint256 cost = bridgeCost(targetChain);

            try
                wormholeRelayer.sendPayloadToEvm{value: cost}(
                    targetChain,
                    targetAddress[targetChain],
                    payload,
                    /// no receiver value allowed, only message passing
                    0,
                    gasLimit
                )
            {
                emit BridgeOutSuccess(
                    targetChain,
                    cost,
                    targetAddress[targetChain],
                    payload
                );
            } catch {
                totalRefundAmount += cost;
                emit BridgeOutFailed(targetChain, payload, cost);
            }

            unchecked {
                i++;
            }
        }

        if (totalRefundAmount > 0) {
            // send bridge funds back to sender
            payable(msg.sender).transfer(totalRefundAmount);
        }
    }

    /// @notice callable only by the wormhole relayer
    /// @param payload the payload of the message, contains the to and amount
    /// additional vaas, unused parameter
    /// @param senderAddress the address of the sender on the source chain, bytes32 encoded
    /// @param sourceChain the chain id of the source chain
    /// @param nonce the unique message ID
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory, // additionalVaas
        bytes32 senderAddress,
        uint16 sourceChain,
        bytes32 nonce
    ) external payable override {
        require(msg.value == 0, "WormholeBridge: no value allowed");
        require(
            msg.sender == address(wormholeRelayer),
            "WormholeBridge: only relayer allowed"
        );
        require(
            isTrustedSender(sourceChain, senderAddress),
            "WormholeBridge: sender not trusted"
        );
        require(
            !processedNonces[nonce],
            "WormholeBridge: message already processed"
        );

        processedNonces[nonce] = true;

        _bridgeIn(sourceChain, payload);
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
}
