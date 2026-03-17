// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Script.sol";
import "@forge-std/Test.sol";
import {stdJson} from "@forge-std/StdJson.sol";

import "@protocol/utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IMetaMorphoFactory} from "@protocol/morpho/IMetaMorphoFactory.sol";
import {IMetaMorpho} from "@protocol/morpho/IMetaMorpho.sol";

/// @notice Template script: Deploy a MetaMorpho vaultAddress from JSON config
contract DeployMorphoVault is Script, Test {
    using ChainIds for uint256;
    using stdJson for string;

    struct VaultConfig {
        string addressName; // key used in Addresses registry, e.g. "llUSDC_METAMORPHO_VAULT"
        string vaultName; // ERC4626 name
        string vaultSymbol; // ERC4626 symbol
        string assetName; // name key to resolve via Addresses.getAddress(), e.g. "USDC"
        string saltString; // arbitrary string to hash into a salt, e.g. "llUSDC"
        uint256 initialTimelock; // initial timelock duration
    }

    function run() external {
        // Setup fork for Base chain
        BASE_FORK_ID.createForksAndSelect();

        string memory configPath = vm.envString("NEW_VAULT_PATH");
        string memory json = vm.readFile(configPath);

        VaultConfig memory cfg = _parseConfig(json);

        Addresses addresses = new Addresses();

        require(
            !addresses.isAddressSet(cfg.addressName),
            "Vault already exists"
        );

        address asset = addresses.getAddress(cfg.assetName);

        address initialOwner = msg.sender;
        bytes32 salt = keccak256(abi.encodePacked(cfg.saltString));

        vm.startBroadcast();
        address vaultAddress = IMetaMorphoFactory(
            addresses.getAddress("MORPHO_FACTORY_V1_1")
        ).createMetaMorpho(
                initialOwner,
                cfg.initialTimelock,
                asset,
                cfg.vaultName,
                cfg.vaultSymbol,
                salt
            );

        addresses.addAddress(cfg.addressName, vaultAddress);

        // Set msg.sender as initial curator; see SetFinalCurator where we set the final curator (ie anthias)
        IMetaMorpho(vaultAddress).setCurator(initialOwner);

        // Validate the created vault
        _validate(addresses, vaultAddress, cfg);

        vm.stopBroadcast();

        console.log("Deployed MetaMorpho vault:", vaultAddress);
        console.log("Registered as:", cfg.addressName);
        addresses.printAddresses();
    }

    function _parseConfig(
        string memory json
    ) internal pure returns (VaultConfig memory cfg) {
        cfg.addressName = json.readString(".addressName");
        cfg.vaultName = json.readString(".vaultName");
        cfg.vaultSymbol = json.readString(".vaultSymbol");
        cfg.assetName = json.readString(".assetName");
        // optional fields
        if (json.parseRaw(".saltString").length != 0) {
            cfg.saltString = json.readString(".saltString");
        }
        if (json.parseRaw(".initialTimelock").length != 0) {
            cfg.initialTimelock = json.readUint(".initialTimelock");
        }
    }

    function _validate(
        Addresses addresses,
        address vault,
        VaultConfig memory cfg
    ) internal view {
        IMetaMorpho v = IMetaMorpho(vault);

        // Verify the vault parameters
        assertEq(v.owner(), msg.sender, "Vault owner should match msg.sender");
        assertEq(
            v.asset(),
            addresses.getAddress(cfg.assetName),
            "Vault asset should match config asset"
        );
        assertEq(v.name(), cfg.vaultName, "Vault name mismatch");
        assertEq(v.symbol(), cfg.vaultSymbol, "Vault symbol mismatch");
        assertEq(v.curator(), msg.sender, "Curator should match msg.sender");

        console.log("Validation completed successfully");
        console.log("Vault owner:", v.owner());
        console.log("Vault asset:", v.asset());
        console.log("Vault name:", v.name());
        console.log("Vault symbol:", v.symbol());
        console.log("Vault curator:", v.curator());
    }
}

/// @notice Follow-up script to set the final curator on a deployed MetaMorpho vault
contract SetFinalCurator is Script, Test {
    using ChainIds for uint256;
    using stdJson for string;

    struct CuratorConfig {
        string addressName; // name in Addresses registry for the vault
        string curatorName; // name in Addresses registry for the final curator
    }

    function run() external {
        // Setup fork for Base chain
        BASE_FORK_ID.createForksAndSelect();

        string memory configPath = vm.envString("NEW_VAULT_PATH");
        string memory json = vm.readFile(configPath);

        CuratorConfig memory cfg = _parseConfig(json);

        Addresses addresses = new Addresses();

        assertTrue(
            addresses.isAddressSet(cfg.addressName),
            "Vault is not deployed"
        );
        assertTrue(bytes(cfg.curatorName).length != 0, "curatorName required");

        address vault = addresses.getAddress(cfg.addressName);
        address curator = addresses.getAddress(cfg.curatorName);

        vm.startBroadcast();
        IMetaMorpho(vault).setCurator(curator);
        vm.stopBroadcast();

        address newCurator = IMetaMorpho(vault).curator();
        console.log("Set final curator on vault:", vault);
        console.log("Curator:", newCurator);
    }

    function _parseConfig(
        string memory json
    ) internal pure returns (CuratorConfig memory cfg) {
        cfg.addressName = json.readString(".addressName");
        cfg.curatorName = json.readString(".curatorName");
    }
}
