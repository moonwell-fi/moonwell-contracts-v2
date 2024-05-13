pragma solidity 0.8.19;

import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract Proxy is TransparentUpgradeableProxy {
    using SafeERC20 for IERC20;

    /// logic contract on testnet: 0x10e5196375e6461703662DE1c11F0C28884cBf3b

    // address owner,
    // address morpho,
    // uint256 initialTimelock,
    // address _asset,
    // string memory _name,
    // string memory _symbol
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
        IERC20(_underlyingAsset).safeApprove(_morpho, type(uint256).max);

        require(bytes(_name).length <= 30, "name too long");
        require(bytes(_symbol).length <= 30, "symbol too long");

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

        assembly {
            name := mload(add(_name, 32))
            symbol := mload(add(_symbol, 32))
        }

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
