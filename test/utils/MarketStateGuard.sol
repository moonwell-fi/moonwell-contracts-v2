// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Vm} from "@forge-std/Vm.sol";

import {MToken} from "@protocol/MToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Proposal} from "@proposals/Proposal.sol";

/// @notice Morpho Blue oracle surface (MorphoChainlinkOracleV2).
interface IMorphoOracle {
    function price() external view returns (uint256);
}

/// @notice Snapshots every market's risk parameters, stored accounting and
/// every registered Morpho Blue oracle price, so a test can diff them after
/// the pending proposals run. Assertions live in the caller.
contract MarketStateGuard {
    Vm internal constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct ComptrollerState {
        address oracle;
        uint256 closeFactor;
        uint256 liquidationIncentive;
        address pauseGuardian;
        address borrowCapGuardian;
        address supplyCapGuardian;
        bool transferPaused;
        bool seizePaused;
        address implementation;
        uint256 marketCount;
    }

    struct MarketState {
        bool isListed;
        uint256 collateralFactor;
        uint256 supplyCap;
        uint256 borrowCap;
        bool mintPaused;
        bool borrowPaused;
        uint256 reserveFactor;
        address interestRateModel;
        address admin;
        address comptroller;
        uint256 totalSupply;
        uint256 totalBorrows;
        uint256 totalReserves;
        uint256 cash;
        uint256 exchangeRate;
        uint256 borrowIndex;
        uint256 accrualTimestamp;
        bool priced;
        address feed;
        address innerFeed;
    }

    mapping(uint256 => bool) public snapshotTaken;
    mapping(uint256 => uint256) public snapshotTimestamp;

    mapping(uint256 => ComptrollerState) internal _comptroller;
    mapping(uint256 => address[]) internal _markets;
    mapping(uint256 => mapping(address => MarketState)) internal _market;
    mapping(uint256 => address[]) internal _morphoOracles;
    mapping(uint256 => mapping(address => uint256)) internal _morphoPrice;

    /// @notice record every market and Morpho oracle on `forkId`; forks without
    /// a live Comptroller (placeholder RPC) are skipped
    function snapshot(Addresses addresses, uint256 forkId) external {
        vm.selectFork(forkId);
        if (
            !addresses.isAddressSet("UNITROLLER") ||
            addresses.getAddress("UNITROLLER").code.length == 0
        ) {
            return;
        }

        Comptroller comptroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );
        _comptroller[forkId] = readComptroller(comptroller);
        snapshotTimestamp[forkId] = block.timestamp;

        MToken[] memory markets = comptroller.getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            _markets[forkId].push(address(markets[i]));
            _market[forkId][address(markets[i])] = readMarket(
                comptroller,
                markets[i]
            );
        }

        address[] memory oracles = morphoOraclesOf(block.chainid);
        for (uint256 i = 0; i < oracles.length; i++) {
            uint256 price = readMorphoPrice(oracles[i]);
            if (price == 0) {
                continue;
            }
            _morphoOracles[forkId].push(oracles[i]);
            _morphoPrice[forkId][oracles[i]] = price;
        }

        snapshotTaken[forkId] = true;
    }

    function comptrollerBefore(
        uint256 forkId
    ) external view returns (ComptrollerState memory) {
        return _comptroller[forkId];
    }

    function marketsBefore(
        uint256 forkId
    ) external view returns (address[] memory) {
        return _markets[forkId];
    }

    function marketBefore(
        uint256 forkId,
        address market
    ) external view returns (MarketState memory) {
        return _market[forkId][market];
    }

    function morphoOraclesBefore(
        uint256 forkId
    ) external view returns (address[] memory) {
        return _morphoOracles[forkId];
    }

    function morphoPriceBefore(
        uint256 forkId,
        address oracle
    ) external view returns (uint256) {
        return _morphoPrice[forkId][oracle];
    }

    /// @notice a proposal's expectedMarketStateChanges(), resolved on its
    /// primary fork. Raw staticcall: an artifact compiled before the hook
    /// existed returns no data; fail closed (nothing declared).
    function declaredChanges(
        Addresses addresses,
        Proposal proposal
    ) external returns (address[] memory declared) {
        uint256 activeFork = vm.activeFork();
        try proposal.primaryForkId() returns (uint256 primaryFork) {
            vm.selectFork(primaryFork);
        } catch {
            return declared;
        }

        (bool ok, bytes memory ret) = address(proposal).staticcall(
            abi.encodeWithSelector(
                Proposal.expectedMarketStateChanges.selector,
                addresses
            )
        );
        if (ok && ret.length > 0) {
            declared = abi.decode(ret, (address[]));
        }

        vm.selectFork(activeFork);
    }

    function readComptroller(
        Comptroller comptroller
    ) public view returns (ComptrollerState memory s) {
        s.oracle = address(comptroller.oracle());
        s.closeFactor = comptroller.closeFactorMantissa();
        s.liquidationIncentive = comptroller.liquidationIncentiveMantissa();
        s.pauseGuardian = comptroller.pauseGuardian();
        s.borrowCapGuardian = comptroller.borrowCapGuardian();
        s.supplyCapGuardian = address(
            uint160(
                _tryUint(
                    address(comptroller),
                    abi.encodeWithSignature("supplyCapGuardian()")
                )
            )
        );
        s.transferPaused = comptroller.transferGuardianPaused();
        s.seizePaused = comptroller.seizeGuardianPaused();
        s.implementation = comptroller.comptrollerImplementation();
        s.marketCount = comptroller.getAllMarkets().length;
    }

    function readMarket(
        Comptroller comptroller,
        MToken market
    ) public view returns (MarketState memory s) {
        (s.isListed, s.collateralFactor) = comptroller.markets(address(market));
        s.supplyCap = _tryUint(
            address(comptroller),
            abi.encodeWithSignature("supplyCaps(address)", address(market))
        );
        s.borrowCap = comptroller.borrowCaps(address(market));
        s.mintPaused = comptroller.mintGuardianPaused(address(market));
        s.borrowPaused = comptroller.borrowGuardianPaused(address(market));
        s.reserveFactor = market.reserveFactorMantissa();
        s.interestRateModel = address(market.interestRateModel());
        s.admin = market.admin();
        s.comptroller = address(market.comptroller());
        s.totalSupply = market.totalSupply();
        s.totalBorrows = market.totalBorrows();
        s.totalReserves = market.totalReserves();
        s.cash = market.getCash();
        s.exchangeRate = market.exchangeRateStored();
        s.borrowIndex = market.borrowIndex();
        s.accrualTimestamp = market.accrualBlockTimestamp();
        try comptroller.oracle().getUnderlyingPrice(market) returns (
            uint256 p
        ) {
            s.priced = p > 0;
        } catch {}
        (s.feed, s.innerFeed) = resolveFeeds(
            address(comptroller.oracle()),
            address(market)
        );
    }

    /// @notice feed ChainlinkOracle resolves for a market, and the feed it
    /// reads in turn (OEV wrapper priceFeed() or composite base()); zero when
    /// priced by a direct override or not resolvable
    function resolveFeeds(
        address oracle,
        address market
    ) public view returns (address feed, address innerFeed) {
        (bool ok, bytes memory ret) = market.staticcall(
            abi.encodeWithSignature("underlying()")
        );
        if (!ok || ret.length != 32) return (feed, innerFeed);
        address underlying = abi.decode(ret, (address));

        if (
            _tryUint(
                oracle,
                abi.encodeWithSignature("assetPrices(address)", underlying)
            ) != 0
        ) {
            return (feed, innerFeed);
        }

        (ok, ret) = underlying.staticcall(abi.encodeWithSignature("symbol()"));
        if (!ok || ret.length == 0) return (feed, innerFeed);
        feed = address(
            uint160(
                _tryUint(
                    oracle,
                    abi.encodeWithSignature(
                        "getFeed(string)",
                        abi.decode(ret, (string))
                    )
                )
            )
        );
        if (feed.code.length == 0) return (feed, innerFeed);

        innerFeed = address(
            uint160(_tryUint(feed, abi.encodeWithSignature("priceFeed()")))
        );
        if (innerFeed == address(0)) {
            innerFeed = address(
                uint160(_tryUint(feed, abi.encodeWithSignature("base()")))
            );
        }
    }

    function readMorphoPrice(address oracle) public view returns (uint256) {
        if (oracle.code.length == 0) {
            return 0;
        }
        try IMorphoOracle(oracle).price() returns (uint256 p) {
            return p;
        } catch {
            return 0;
        }
    }

    /// @notice every live MORPHO_CHAINLINK_*_ORACLE entry in chains/<id>.json
    function morphoOraclesOf(
        uint256 chainId
    ) public view returns (address[] memory out) {
        (string[] memory names, address[] memory addrs) = registry(chainId);
        out = new address[](names.length);
        uint256 n;
        for (uint256 i = 0; i < names.length; i++) {
            if (
                _startsWith(names[i], "MORPHO_CHAINLINK_") &&
                _endsWith(names[i], "_ORACLE")
            ) {
                out[n++] = addrs[i];
            }
        }
        assembly {
            mstore(out, n)
        }
    }

    /// @notice addresses of registry entries marked retired: any name holding
    /// DEPRECATED, or a Chainlink SVR proxy (_SVR)
    function retiredOf(
        uint256 chainId
    ) public view returns (address[] memory out) {
        (string[] memory names, address[] memory addrs) = registry(chainId);
        out = new address[](names.length);
        uint256 n;
        for (uint256 i = 0; i < names.length; i++) {
            if (
                vm.indexOf(names[i], "DEPRECATED") != type(uint256).max ||
                _endsWith(names[i], "_SVR")
            ) {
                out[n++] = addrs[i];
            }
        }
        assembly {
            mstore(out, n)
        }
    }

    function registry(
        uint256 chainId
    ) public view returns (string[] memory names, address[] memory addrs) {
        string memory path = string.concat(
            "chains/",
            vm.toString(chainId),
            ".json"
        );
        string memory json = vm.readFile(path);
        names = abi.decode(vm.parseJson(json, "$[*].name"), (string[]));
        addrs = abi.decode(vm.parseJson(json, "$[*].addr"), (address[]));
    }

    /// @notice zero when the getter is absent (Moonbeam's older Comptroller
    /// has no supply caps); before and after read the same way
    function _tryUint(
        address target,
        bytes memory data
    ) internal view returns (uint256) {
        (bool ok, bytes memory ret) = target.staticcall(data);
        return ok && ret.length == 32 ? abi.decode(ret, (uint256)) : 0;
    }

    function _startsWith(
        string memory s,
        string memory prefix
    ) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(prefix);
        if (b.length > a.length) return false;
        for (uint256 i = 0; i < b.length; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    function _endsWith(
        string memory s,
        string memory suffix
    ) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(suffix);
        if (b.length > a.length) return false;
        for (uint256 i = 0; i < b.length; i++) {
            if (a[a.length - b.length + i] != b[i]) return false;
        }
        return true;
    }
}
