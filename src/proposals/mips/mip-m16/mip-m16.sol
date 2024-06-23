//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ForkID} from "@utils/Enums.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {GovernanceProposal} from "@proposals/proposalTypes/GovernanceProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract mipm16 is GovernanceProposal {
    string public constant override name = "MIP-M16";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m16/MIP-M16.md")
        );
        _setProposalDescription(proposalDescription);

        onchainProposalId = 70;
    }

    function primaryForkId() public pure override returns (ForkID) {
        return ForkID.Moonbeam;
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        address mUSDCAddress = addresses.getAddress("MOONWELL_mUSDC");
        address mETHAddress = addresses.getAddress("DEPRECATED_MOONWELL_mETH");
        address mwBTCAddress = addresses.getAddress(
            "DEPRECATED_MOONWELL_mWBTC"
        );

        /// @dev mUSDC.mad
        MErc20Delegator mUSDC = MErc20Delegator(payable(mUSDCAddress));
        uint256 mUSDCReserves = mUSDC.totalReserves();

        /// @dev mETH.mad
        MErc20Delegator mETH = MErc20Delegator(payable(mETHAddress));
        uint256 mETHReserves = mETH.totalReserves();

        /// @dev mBTC.mad
        MErc20Delegator mwBTC = MErc20Delegator(payable(mwBTCAddress));
        uint256 mwBTCReserves = mwBTC.totalReserves();

        /// @dev set max operations on artemis governor to 1000
        _pushGovernanceAction(
            addresses.getAddress("ARTEMIS_GOVERNOR"),
            "Set the max operations on the artemis governor to 1000",
            abi.encodeWithSignature("setProposalMaxOperations(uint256)", 1000)
        );

        /// @dev reduce mUSDC.mad reserves
        _pushGovernanceAction(
            address(mUSDC),
            "Reduce the reserves of mUSDC.mad",
            abi.encodeWithSignature("_reduceReserves(uint256)", mUSDCReserves)
        );

        /// @dev reduce mETH.mad reserves
        _pushGovernanceAction(
            address(mETH),
            "Reduce the reserves of mETH.mad",
            abi.encodeWithSignature("_reduceReserves(uint256)", mETHReserves)
        );

        /// @dev reduce mBTC.mad reserves
        _pushGovernanceAction(
            address(mwBTC),
            "Reduce the reserves of mwBTC.mad",
            abi.encodeWithSignature("_reduceReserves(uint256)", mwBTCReserves)
        );

        /// @dev Nomad reallocation multisig
        address nomadReallocationMultisig = addresses.getAddress(
            "NOMAD_REALLOCATION_MULTISIG"
        );

        /// @dev transfer USDC from the timelock to the multisig
        _pushGovernanceAction(
            addresses.getAddress("madUSDC"),
            "Transfer madUSDC from the Timelock to the multisig",
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                nomadReallocationMultisig,
                mUSDCReserves
            )
        );

        /// @dev transfer WETH from the timelock to the multisig
        _pushGovernanceAction(
            addresses.getAddress("madWETH"),
            "Transfer madETH from the Timelock to the multisig",
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                nomadReallocationMultisig,
                mETHReserves
            )
        );

        /// @dev transfer WBTC from the timelock to the multisig
        _pushGovernanceAction(
            addresses.getAddress("madWBTC"),
            "Transfer madWBTC from the Timelock to the multisig",
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                nomadReallocationMultisig,
                mwBTCReserves
            )
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {}

    function run(Addresses addresses, address) public override {
        /// @dev enable debugging
        setDebug(true);

        _simulateGovernanceActions(
            addresses.getAddress("MOONBEAM_TIMELOCK"),
            addresses.getAddress("ARTEMIS_GOVERNOR"),
            address(this)
        );
    }
}
