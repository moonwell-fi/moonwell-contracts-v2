// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SafetyModuleInterfaceV1} from "@protocol/views/SafetyModuleInterfaceV1.sol";

/**
 * @title Moonwell Staking Views
 * @author Moonwell
 * @notice Read-only views for the stkWELL safety module, decoupled from the
 *         Comptroller / market views in `BaseMoonwellViews`. Suitable for
 *         chains where stkWELL is deployed but no lending markets exist
 *         (e.g. Ethereum mainnet), so the views proxy never needs to bind
 *         to a Comptroller. The struct surface intentionally matches the
 *         staking-related portion of `BaseMoonwellViews` so consumers can
 *         share decoders across chains.
 */
contract MoonwellStakingViews is Initializable {
    struct StakingInfo {
        uint cooldown;
        uint unstakeWindow;
        uint distributionEnd;
        uint totalSupply;
        uint emissionPerSecond;
        uint lastUpdateTimestamp;
        uint index;
    }

    struct UserStakingInfo {
        uint cooldown;
        uint pendingRewards;
        uint totalStaked;
    }

    struct Votes {
        uint delegatedVotingPower;
        uint votingPower;
        address delegates;
    }

    SafetyModuleInterfaceV1 public safetyModule;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _safetyModule) external initializer {
        require(
            _safetyModule != address(0),
            "safetyModule cant be the 0 address!"
        );
        safetyModule = SafetyModuleInterfaceV1(_safetyModule);
    }

    /// @notice Protocol-wide stkWELL configuration and emission state.
    function getStakingInfo()
        external
        view
        returns (StakingInfo memory _result)
    {
        _result.cooldown = safetyModule.COOLDOWN_SECONDS();
        _result.unstakeWindow = safetyModule.UNSTAKE_WINDOW();
        _result.distributionEnd = safetyModule.DISTRIBUTION_END();
        _result.totalSupply = safetyModule.totalSupply();

        SafetyModuleInterfaceV1.AssetData memory asset = safetyModule.assets(
            address(safetyModule)
        );
        _result.emissionPerSecond = asset.emissionPerSecond;
        _result.lastUpdateTimestamp = asset.lastUpdateTimestamp;
        _result.index = asset.index;
    }

    /// @notice Per-user stkWELL position: cooldown timestamp, pending
    ///         rewards, and staked balance.
    function getUserStakingInfo(
        address _user
    ) external view returns (UserStakingInfo memory _result) {
        _result.pendingRewards = safetyModule.getTotalRewardsBalance(_user);
        _result.cooldown = safetyModule.stakersCooldowns(_user);
        _result.totalStaked = safetyModule.balanceOf(_user);
    }

    /// @notice Per-user staking voting power. stkWELL snapshots
    ///         (ERC20WithSnapshot) are keyed by `block.timestamp`, not
    ///         `block.number` — query `getPriorVotes` with a timestamp.
    function getUserStakingVotingPower(
        address _user
    ) external view returns (Votes memory _result) {
        uint _priorVotes = safetyModule.getPriorVotes(
            _user,
            block.timestamp - 1
        );
        _result = Votes(_priorVotes, safetyModule.balanceOf(_user), address(0));
    }
}
