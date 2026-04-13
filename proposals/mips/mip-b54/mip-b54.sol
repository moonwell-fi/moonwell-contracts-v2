// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MTokenInterface} from "@protocol/MTokenInterfaces.sol";
import {MWethOwnerWrapper} from "@protocol/MWethOwnerWrapper.sol";

import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";

import {DeployMWethOwnerWrapper} from "@script/DeployMWethOwnerWrapper.s.sol";
import {ChainIds} from "@utils/ChainIds.sol";

/// @title MIP-B54: WETH Market Ownership Wrapper and Reserve Withdrawal
/// @notice Proposal to deploy and migrate WETH market admin to a wrapper contract
///         that can reliably receive native ETH, enabling reserve reductions.
/// @dev This proposal:
///      1. Deploys MWethOwnerWrapper implementation and proxy
///      2. Transfers WETH market admin from TEMPORAL_GOVERNOR to the wrapper
///      3. Wrapper is owned by TEMPORAL_GOVERNOR, maintaining governance control
///      4. Reduces WETH reserves by 347 WETH and sends to BAD_DEBT_REPAYER_EOA
contract mipb54 is HybridProposal {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-B54";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-b54/b54.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        initProposal(addresses);

        (, address deployerAddress, ) = vm.readCallers();

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);

        if (DO_BUILD) build(addresses);
        if (DO_RUN) simulate(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_VALIDATE) {
            validate(addresses, deployerAddress);
            console.log("Validation completed for proposal ", this.name());
        }
        if (DO_PRINT) {
            printProposalActionSteps();

            addresses.removeAllRestrictions();
            printCalldata(addresses);

            _printAddressesChanges(addresses);
        }
    }

    function deploy(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);

        // Deploy the MWethOwnerWrapper implementation and proxy
        DeployMWethOwnerWrapper deployer = new DeployMWethOwnerWrapper();
        deployer.deploy(addresses);
    }

    function build(Addresses addresses) public override {
        vm.selectFork(BASE_FORK_ID);

        address wrapperProxy = addresses.getAddress("MWETH_OWNER_WRAPPER");
        address moonwellWeth = addresses.getAddress("MOONWELL_WETH");
        address weth = addresses.getAddress("WETH");
        address badDebtRepayerEoa = addresses.getAddress(
            "BAD_DEBT_REPAYER_EOA"
        );

        uint256 wethReserveReduction = 347 ether;

        // Step 1: Set the wrapper as pending admin of the WETH market
        _pushAction(
            moonwellWeth,
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                payable(wrapperProxy)
            ),
            "Set MWethOwnerWrapper as pending admin of MOONWELL_WETH",
            ActionType.Base
        );

        // Step 2: Accept admin role from the wrapper
        _pushAction(
            wrapperProxy,
            abi.encodeWithSignature("_acceptAdmin()"),
            "MWethOwnerWrapper accepts admin role for MOONWELL_WETH",
            ActionType.Base
        );

        // Step 3: Reduce reserves by 347 WETH (sent as ETH, auto-wrapped to WETH by wrapper)
        _pushAction(
            wrapperProxy,
            abi.encodeWithSignature(
                "_reduceReserves(uint256)",
                wethReserveReduction
            ),
            "Reduce WETH market reserves by 347 WETH",
            ActionType.Base
        );

        // Step 4: Withdraw WETH from wrapper to BAD_DEBT_REPAYER_EOA
        _pushAction(
            wrapperProxy,
            abi.encodeWithSignature(
                "withdrawToken(address,address,uint256)",
                weth,
                badDebtRepayerEoa,
                wethReserveReduction
            ),
            "Transfer 347 WETH to BAD_DEBT_REPAYER_EOA",
            ActionType.Base
        );
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);

        address wrapperProxy = addresses.getAddress("MWETH_OWNER_WRAPPER");
        address moonwellWeth = addresses.getAddress("MOONWELL_WETH");
        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        address weth = addresses.getAddress("WETH");
        address badDebtRepayerEoa = addresses.getAddress(
            "BAD_DEBT_REPAYER_EOA"
        );

        uint256 wethReserveReduction = 347 ether;

        // Validate wrapper configuration
        MWethOwnerWrapper wrapper = MWethOwnerWrapper(payable(wrapperProxy));

        assertEq(
            wrapper.owner(),
            temporalGovernor,
            "Wrapper owner should be TEMPORAL_GOVERNOR"
        );

        assertEq(
            address(wrapper.mToken()),
            moonwellWeth,
            "Wrapper mToken should be MOONWELL_WETH"
        );

        assertEq(
            address(wrapper.weth()),
            weth,
            "Wrapper WETH address should be correct"
        );

        // Validate admin transfer
        MTokenInterface mToken = MTokenInterface(moonwellWeth);

        assertEq(
            mToken.admin(),
            wrapperProxy,
            "MOONWELL_WETH admin should be the wrapper"
        );

        assertEq(
            mToken.pendingAdmin(),
            address(0),
            "MOONWELL_WETH pendingAdmin should be zero after accepting"
        );

        // Validate WETH was transferred to BAD_DEBT_REPAYER_EOA
        assertGe(
            IERC20(weth).balanceOf(badDebtRepayerEoa),
            wethReserveReduction,
            "BAD_DEBT_REPAYER_EOA should have received WETH"
        );

        // Validate wrapper has no remaining WETH balance
        assertEq(
            IERC20(weth).balanceOf(wrapperProxy),
            0,
            "Wrapper should have no remaining WETH"
        );
    }
}
