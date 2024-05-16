pragma solidity 0.8.19;

import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract Proxy is TransparentUpgradeableProxy {
    using SafeERC20 for IERC20;

    /// @param _morpho The address of the Morpho contract
    /// @param _logic The address of the logic contract
    /// @param _admin The address of the admin to the proxy contract
    /// @param _owner The address of the owner of the proxy contract, will control the MetaMorhpo Vault
    /// @param _timelock The timelock for the proxy contract
    /// @param _underlyingAsset The address of the underlying asset
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    constructor(
        address _morpho,
        address _logic,
        address _admin,
        address _owner,
        uint256 _timelock,
        address _underlyingAsset,
        string memory _name,
        string memory _symbol
    ) TransparentUpgradeableProxy(_logic, _admin, "") {
        /// TODO test approval
        IERC20(_underlyingAsset).safeApprove(_morpho, type(uint256).max);

        require(bytes(_name).length <= 30, "name too long");
        require(bytes(_symbol).length <= 30, "symbol too long");

        require(
            _timelock >= 1 days && _timelock <= 2 weeks,
            "timelock too short"
        );

        /// variable  |  slot
        /// -----------------
        /// name      |   3
        /// symbol    |   4
        /// owner     |   8
        /// timelock  |  14

        /// first need to get the raw representation of the name and symbol
        /// then we need to set the least significant byte to the length
        /// of the string
        uint256 name;
        uint256 symbol;

        /// set the name and symbol to the start of the string
        assembly {
            name := mload(add(_name, 32))
            symbol := mload(add(_symbol, 32))
        }

        /// set the least significant byte to the length of the string * 2
        name |= uint8(bytes(_name).length * 2);
        symbol |= uint8(bytes(_symbol).length * 2);

        assembly {
            sstore(3, name)
            sstore(4, symbol)
            sstore(8, _owner)
            sstore(14, _timelock)
        }
    }
}
