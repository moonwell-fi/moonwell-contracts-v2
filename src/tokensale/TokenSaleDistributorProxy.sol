// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./ReentrancyGuard.sol";
import "./TokenSaleDistributorProxyStorage.sol";

contract TokenSaleDistributorProxy is
    ReentrancyGuard,
    TokenSaleDistributorProxyStorage
{
    /** The admin was changed  */
    event AdminChanged(address newAdmin);

    /** The implementation was changed */
    event ImplChanged(address newImpl);

    constructor() public {
        admin = msg.sender;
    }

    /**
     * Request a new admin to be set for the contract.
     *
     * @param newAdmin New admin address
     */
    function setPendingAdmin(address newAdmin) public adminOnly {
        require(newAdmin != address(0), "Cannot set to zero address");
        pendingAdmin = newAdmin;
    }

    /**
     * Accept admin transfer from the current admin to the new.
     */
    function acceptPendingAdmin() public {
        require(
            msg.sender == pendingAdmin && pendingAdmin != address(0),
            "Caller must be the pending admin"
        );

        admin = pendingAdmin;
        pendingAdmin = address(0);

        emit AdminChanged(admin);
    }

    /**
     * Request a new implementation to be set for the contract.
     *
     * @param newImplementation New contract implementation contract address
     */
    function setPendingImplementation(
        address newImplementation
    ) public adminOnly {
        require(newImplementation != address(0), "Cannot set to zero address");
        pendingImplementation = newImplementation;
    }

    /**
     * Accept pending implementation change
     */
    function acceptPendingImplementation() public {
        require(
            msg.sender == pendingImplementation &&
                pendingImplementation != address(0),
            "Only the pending implementation contract can call this"
        );

        implementation = pendingImplementation;
        pendingImplementation = address(0);

        emit ImplChanged(implementation);
    }

    fallback() external payable {
        (bool success, ) = implementation.delegatecall(msg.data);

        assembly {
            let free_mem_ptr := mload(0x40)
            let size := returndatasize()
            returndatacopy(free_mem_ptr, 0, size)

            switch success
            case 0 {
                revert(free_mem_ptr, size)
            }
            default {
                return(free_mem_ptr, size)
            }
        }
    }

    /********************************************************
     *                                                      *
     *                      MODIFIERS                       *
     *                                                      *
     ********************************************************/

    modifier adminOnly() {
        require(msg.sender == admin, "admin only");
        _;
    }
}
