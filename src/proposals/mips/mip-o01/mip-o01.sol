//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";
import "@protocol/utils/ChainIds.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Address} from "@utils/Address.sol";
import {Configs} from "@proposals/Configs.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {Comptroller, ComptrollerInterface} from "@protocol/Comptroller.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {ChainIds, OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";
import {JumpRateModel} from "@protocol/irm/JumpRateModel.sol";

/*
to deploy:

DO_DEPLOY=true DO_AFTER_DEPLOY=true DO_PRE_BUILD_MOCK=true DO_BUILD=true \
DO_RUN=true DO_VALIDATE=true forge script \
src/proposals/mips/mip-o01/mip-o01.sol:mipo01 -vvv --broadcast --account ~/.foundry/keystores/<your-account-keystore-name>

to dry-run:

DO_DEPLOY=true DO_AFTER_DEPLOY=true DO_PRE_BUILD_MOCK=true DO_BUILD=true \
  DO_RUN=true DO_VALIDATE=true forge script \
  src/proposals/mips/mip-o01/mip-o01.sol:mipo01 -vvv --account ~/.foundry/keystores/<your-account-keystore-name>

MIP-O00 deployment environment variables:

```
export DESCRIPTION_PATH=src/proposals/mips/mip-o00/MIP-O00.md
export PRIMARY_FORK_ID=2
export EMISSIONS_PATH=src/proposals/mips/mip-o00/emissionConfigWell.json
export MTOKENS_PATH=src/proposals/mips/mip-o00/mTokens.json
```


*/

contract mipo01 is HybridProposal, Configs {
    using Address for address;
    using ChainIds for uint256;
    using ProposalActions for *;

    string public constant override name = "MIP-01: Initialize Markets";
    uint8 public constant mTokenDecimals = 8; /// all mTokens have 8 decimals

    struct CTokenAddresses {
        address mTokenImpl;
        address irModel;
        address unitroller;
    }

    /// ---------------------- BREAK GLASS GUARDIAN CALLDATA ----------------------

    /// @notice whitelisted calldata for the break glass guardian
    bytes[] public approvedCalldata;

    /// @notice whitelisted calldata for the temporal governor
    bytes[] public temporalGovernanceCalldata;

    /// @notice address of the temporal governor
    address[] public temporalGovernanceTargets;

    /// @notice trusted senders for the temporal governor
    ITemporalGovernor.TrustedSender[] public temporalGovernanceTrustedSenders;

    function initProposal(Addresses) public override {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(vm.envString("DESCRIPTION_PATH"))
        );

        _setProposalDescription(proposalDescription);

        /// MToken/Emission configurations
        _setMTokenConfiguration(vm.envString("MTOKENS_PATH"));
    }

    /// @dev change this if wanting to deploy to a different chain
    /// double check addresses and change the WORMHOLE_CORE to the correct chain
    function primaryForkId() public view override returns (uint256 forkId) {
        forkId = OPTIMISM_FORK_ID;
    }

    function preBuildMock(Addresses addresses) public override {
        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);

        uint256 cTokenConfigsLength = cTokenConfigs.length;
        unchecked {
            for (uint256 i = 0; i < cTokenConfigsLength; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];
                address tokenAddress = addresses.getAddress(
                    config.tokenAddressName
                );
                deal(
                    tokenAddress,
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    cTokenConfigs[i].initialMintAmount
                );
            }
        }
    }

    function build(Addresses addresses) public override {
        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);

        address unitrollerAddress = addresses.getAddress("UNITROLLER");

        /// set mint unpaused for all of the deployed MTokens
        unchecked {
            for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];

                address cTokenAddress = addresses.getAddress(
                    config.addressesString
                );

                /// ------------ MTOKEN MARKET ACTIVIATION ------------

                _pushAction(
                    unitrollerAddress,
                    abi.encodeWithSignature(
                        "_setMintPaused(address,bool)",
                        cTokenAddress,
                        false
                    ),
                    "Unpause MToken market"
                );

                /// Approvals
                _pushAction(
                    addresses.getAddress(config.tokenAddressName),
                    abi.encodeWithSignature(
                        "approve(address,uint256)",
                        cTokenAddress,
                        config.initialMintAmount
                    ),
                    "Approve underlying token to be spent by market"
                );

                /// Initialize markets
                _pushAction(
                    cTokenAddress,
                    abi.encodeWithSignature(
                        "mint(uint256)",
                        config.initialMintAmount
                    ),
                    "Initialize token market to prevent exploit"
                );

                _pushAction(
                    cTokenAddress,
                    abi.encodeWithSignature(
                        "transfer(address,uint256)",
                        address(0),
                        1
                    ),
                    "Send 1 wei to address 0 to prevent a state where market has 0 mToken"
                );
            }
        }
    }

    function run(Addresses addresses, address) public override {
        require(
            actions.proposalActionTypeCount(ActionType(primaryForkId())) > 0,
            "MIP-00: should have actions on the chain being deployed to"
        );

        require(
            actions.proposalActionTypeCount(ActionType.Moonbeam) == 1,
            "MIP-00: should have 1 moonbeam actions"
        );

        super.run(addresses, address(0));
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        Comptroller comptroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );

        Configs.CTokenConfiguration[]
            memory cTokenConfigs = getCTokenConfigurations(block.chainid);

        unchecked {
            for (uint256 i = 0; i < cTokenConfigs.length; i++) {
                Configs.CTokenConfiguration memory config = cTokenConfigs[i];

                /// CToken Assertions
                assertFalse(
                    comptroller.mintGuardianPaused(
                        addresses.getAddress(config.addressesString)
                    )
                ); /// minting allowed by guardian
                assertFalse(
                    comptroller.borrowGuardianPaused(
                        addresses.getAddress(config.addressesString)
                    )
                ); /// borrowing allowed by guardian
                assertEq(
                    comptroller.borrowCaps(
                        addresses.getAddress(config.addressesString)
                    ),
                    config.borrowCap
                );
                assertEq(
                    comptroller.supplyCaps(
                        addresses.getAddress(config.addressesString)
                    ),
                    config.supplyCap
                );

                /// assert cToken irModel is correct
                JumpRateModel jrm = JumpRateModel(
                    addresses.getAddress(
                        string(
                            abi.encodePacked(
                                "JUMP_RATE_IRM_",
                                config.addressesString
                            )
                        )
                    )
                );
                assertEq(
                    address(
                        MToken(addresses.getAddress(config.addressesString))
                            .interestRateModel()
                    ),
                    address(jrm)
                );

                MErc20 mToken = MErc20(
                    addresses.getAddress(config.addressesString)
                );

                /// reserve factor and protocol seize share
                assertEq(
                    mToken.protocolSeizeShareMantissa(),
                    config.seizeShare
                );
                assertEq(mToken.reserveFactorMantissa(), config.reserveFactor);

                /// assert initial mToken balances are correct
                assertEq(mToken.balanceOf(address(0)), 1); /// address 0 has 1 wei of assets

                address governor = addresses.getAddress("TEMPORAL_GOVERNOR");

                /// assert cToken admin is the temporal governor
                assertEq(address(mToken.admin()), address(governor));

                /// assert mToken comptroller is correct
                assertEq(
                    address(mToken.comptroller()),
                    addresses.getAddress("UNITROLLER")
                );

                /// assert mToken underlying is correct
                assertEq(
                    address(mToken.underlying()),
                    addresses.getAddress(config.tokenAddressName)
                );

                if (
                    address(mToken.underlying()) == addresses.getAddress("WETH")
                ) {
                    /// assert mToken delegate for MOONWELL_WETH is mWETH_DELEGATE
                    assertEq(
                        address(
                            MErc20Delegator(payable(address(mToken)))
                                .implementation()
                        ),
                        addresses.getAddress("MWETH_IMPLEMENTATION"),
                        "mweth delegate implementation address incorrect"
                    );
                } else {
                    /// assert mToken delegate is uniform across contracts
                    assertEq(
                        address(
                            MErc20Delegator(payable(address(mToken)))
                                .implementation()
                        ),
                        addresses.getAddress("MTOKEN_IMPLEMENTATION"),
                        "mtoken delegate implementation address incorrect"
                    );
                }

                uint256 initialExchangeRate = (10 **
                    (8 +
                        ERC20(addresses.getAddress(config.tokenAddressName))
                            .decimals())) * 2;

                /// assert mToken initial exchange rate is correct
                assertEq(mToken.exchangeRateCurrent(), initialExchangeRate);

                /// assert mToken name and symbol are correct
                assertEq(mToken.name(), config.name);
                assertEq(mToken.symbol(), config.symbol);
                assertEq(mToken.decimals(), mTokenDecimals);

                /// Jump Rate Model Assertions
                {
                    assertEq(
                        jrm.baseRatePerTimestamp(),
                        (config.jrm.baseRatePerYear * 1e18) /
                            jrm.timestampsPerYear() /
                            1e18
                    );
                    assertEq(
                        jrm.multiplierPerTimestamp(),
                        (config.jrm.multiplierPerYear * 1e18) /
                            jrm.timestampsPerYear() /
                            1e18
                    );
                    assertEq(
                        jrm.jumpMultiplierPerTimestamp(),
                        (config.jrm.jumpMultiplierPerYear * 1e18) /
                            jrm.timestampsPerYear() /
                            1e18
                    );
                    assertEq(jrm.kink(), config.jrm.kink);
                }
            }
        }

        vm.selectFork(primaryForkId());
    }
}
