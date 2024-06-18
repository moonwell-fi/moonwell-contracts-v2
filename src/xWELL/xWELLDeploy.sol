pragma solidity 0.8.19;

import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {XERC20Lockbox} from "@protocol/xWELL/XERC20Lockbox.sol";
import {AxelarBridgeAdapter} from "@protocol/xWELL/AxelarBridgeAdapter.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";

contract xWELLDeploy {
    /// @notice for base deployment
    /// @param tokenName The name of the token
    /// @param tokenSymbol The symbol of the token
    /// @param tokenOwner The owner of the token, Temporal Governor on Base, Timelock on Moonbeam
    /// @param newRateLimits The rate limits for the token
    /// @param newPauseDuration The duration of the pause
    /// @param newPauseGuardian The pause guardian address
    function deployXWell(
        string memory tokenName,
        string memory tokenSymbol,
        address tokenOwner,
        MintLimits.RateLimitMidPointInfo[] memory newRateLimits,
        uint128 newPauseDuration,
        address newPauseGuardian
    )
        public
        returns (address xwellLogic, address xwellImpl, address proxyAdmin)
    {
        /// deploy the ERC20 wrapper for USDBC
        xwellLogic = address(new xWELL());

        proxyAdmin = address(new ProxyAdmin());

        bytes memory initData = abi.encodeWithSignature(
            "initialize(string,string,address,(uint112,uint128,address)[],uint128,address)",
            tokenName,
            tokenSymbol,
            tokenOwner,
            newRateLimits,
            newPauseDuration,
            newPauseGuardian
        );

        xwellImpl = address(
            new TransparentUpgradeableProxy(
                address(xwellLogic),
                address(proxyAdmin),
                initData
            )
        );
    }

    /// @notice for Moonbeam deployment
    /// @param addresses The addresses contract
    /// @param tokenName The name of the token
    /// @param tokenSymbol The symbol of the token
    /// @param tokenOwner The owner of the token, Temporal Governor on Base, Timelock on Moonbeam
    /// @param newRateLimits The rate limits for the token
    /// @param newPauseDuration The duration of the pause
    /// @param newPauseGuardian The pause guardian address
    function deployXWellAndLockBox(
        Addresses addresses,
        string memory tokenName,
        string memory tokenSymbol,
        address tokenOwner,
        MintLimits.RateLimitMidPointInfo[] memory newRateLimits,
        uint128 newPauseDuration,
        address newPauseGuardian
    )
        public
        returns (
            address xwellLogic,
            address xwellProxy,
            address proxyAdmin,
            address lockbox
        )
    {
        /// deploy the ERC20 wrapper for USDBC
        xwellLogic = address(new xWELL());

        proxyAdmin = address(new ProxyAdmin());

        /// do not initialize the proxy, that is the final step
        xwellProxy = address(
            new TransparentUpgradeableProxy(
                address(xwellLogic),
                address(proxyAdmin),
                ""
            )
        );

        lockbox = deployLockBox(
            xwellProxy, /// proxy is actually the xWELL token contract
            addresses.getAddress("GOVTOKEN")
        );

        MintLimits.RateLimitMidPointInfo[]
            memory _newRateLimits = new MintLimits.RateLimitMidPointInfo[](
                newRateLimits.length + 1
            );

        for (uint256 i = 0; i < newRateLimits.length; i++) {
            _newRateLimits[i] = newRateLimits[i];
        }

        _newRateLimits[_newRateLimits.length - 1] = MintLimits
            .RateLimitMidPointInfo({
                bufferCap: type(uint112).max, /// max buffer cap, lock box can infinite mint up to max supply
                rateLimitPerSecond: 0, /// no rate limit
                bridge: lockbox
            });

        xWELL(xwellProxy).initialize(
            tokenName,
            tokenSymbol,
            tokenOwner,
            _newRateLimits,
            newPauseDuration,
            newPauseGuardian
        );
    }

    /// @notice deploy a system on base
    /// this includes the xWELL token, the proxy, the proxy admin, and the wormhole adapter
    /// but does not include the xWELL lockbox as there is no native WELL token on base
    /// @param existingProxyAdmin The proxy admin to use, if any
    function deployBaseSystem(
        address existingProxyAdmin
    )
        public
        returns (
            address xwellLogic,
            address xwellProxy,
            address proxyAdmin,
            address wormholeAdapterLogic,
            address wormholeAdapter
        )
    {
        /// deploy the ERC20 wrapper for USDBC
        xwellLogic = address(new xWELL());

        wormholeAdapterLogic = address(new WormholeBridgeAdapter());

        if (existingProxyAdmin == address(0)) {
            proxyAdmin = address(new ProxyAdmin());
        } else {
            proxyAdmin = existingProxyAdmin;
        }

        /// do not initialize the proxy, that is the final step
        xwellProxy = address(
            new TransparentUpgradeableProxy(xwellLogic, proxyAdmin, "")
        );

        wormholeAdapter = address(
            new TransparentUpgradeableProxy(
                wormholeAdapterLogic,
                proxyAdmin,
                ""
            )
        );
    }

    /// @notice well token address on Moonbeam
    function deployMoonbeamSystem(
        address wellAddress,
        address existingProxyAdmin
    )
        public
        returns (
            address xwellLogic,
            address xwellProxy,
            address proxyAdmin,
            address wormholeAdapterLogic,
            address wormholeAdapter,
            address lockbox
        )
    {
        (
            xwellLogic,
            xwellProxy,
            proxyAdmin,
            wormholeAdapterLogic,
            wormholeAdapter
        ) = deployBaseSystem(existingProxyAdmin);
        /// lockbox is deployed at the end so that xWELL and wormhole adapter can have the same addresses on all chains.
        lockbox = deployLockBox(
            xwellProxy, /// proxy is actually the xWELL token contract
            wellAddress
        );
    }

    function initializeXWell(
        address xwellProxy,
        string memory tokenName,
        string memory tokenSymbol,
        address tokenOwner,
        MintLimits.RateLimitMidPointInfo[] memory newRateLimits,
        uint128 newPauseDuration,
        address newPauseGuardian
    ) public {
        xWELL(xwellProxy).initialize(
            tokenName,
            tokenSymbol,
            tokenOwner,
            newRateLimits,
            newPauseDuration,
            newPauseGuardian
        );
    }

    function initializeWormholeAdapter(
        address wormholeAdapter,
        address xwellProxy,
        address tokenOwner,
        address wormholeRelayerAddress,
        uint16 chainId
    ) public {
        WormholeBridgeAdapter(wormholeAdapter).initialize(
            xwellProxy,
            tokenOwner,
            wormholeRelayerAddress,
            chainId
        );
    }

    /// @notice deploy lock box, for use on base only
    /// @param xwell The xWELL token address
    /// @param well The WELL token address
    function deployLockBox(
        address xwell,
        address well
    ) public returns (address) {
        return address(new XERC20Lockbox(xwell, well));
    }

    /// @notice deploy the axelar bridge adapter
    /// @param proxyAdmin The proxy admin address
    function deployAxelarBridgeAdapter(
        address proxyAdmin
    ) public returns (address axelarBridgeAddress, address axelarBridgeProxy) {
        axelarBridgeAddress = address(new AxelarBridgeAdapter());

        axelarBridgeProxy = address(
            new TransparentUpgradeableProxy(axelarBridgeAddress, proxyAdmin, "")
        );
    }

    /// @notice initialize the axelar bridge adapter
    /// @param axelarBridgeProxy The proxy address
    /// @param xwellProxy The xWELL token address
    /// @param owner The owner of the adapter
    /// @param axelarGateway The axelar gateway address
    /// @param axelarGasService The axelar gas service address
    /// @param chainIds The chain ids to support
    /// @param configs The chain configs
    function initializeAxelarBridgeAdapter(
        address axelarBridgeProxy,
        address xwellProxy,
        address owner,
        address axelarGateway,
        address axelarGasService,
        AxelarBridgeAdapter.ChainIds[] memory chainIds,
        AxelarBridgeAdapter.ChainConfig[] memory configs
    ) public {
        AxelarBridgeAdapter(axelarBridgeProxy).initialize(
            xwellProxy,
            owner,
            axelarGateway,
            axelarGasService,
            chainIds,
            configs
        );
    }
}
