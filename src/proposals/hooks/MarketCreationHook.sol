pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {ProposalAction} from "@proposals/proposalTypes/IProposal.sol";

contract MarketCreationHook {
    /// private so that contracts that inherit cannot write to functionDetectors
    mapping(bytes4 => bool) private functionDetectors;
    bytes4 private constant detector = Comptroller._supportMarket.selector;

    /// ordered actions to verify
    /// 1. supportMarket on Comptroller
    /// 2. acceptAdmin on mToken
    /// 3. approve underlying on ERC20
    /// 4. mint mToken
    bytes4[4] public orderedActions = [
        detector,
        MToken._acceptAdmin.selector,
        IERC20.approve.selector,
        MErc20.mint.selector
    ];

    /// @notice array of created mTokens in proposal
    address[] public createdMTokens;

    /// @notice comptroller address as specified by an mToken being created
    address public comptroller;

    constructor() {
        functionDetectors[detector] = true;
    }

    function _verifyActionsPreRun(ProposalAction[] memory proposal) internal {
        address[] memory targets = new address[](proposal.length);
        uint256[] memory values = new uint256[](proposal.length);
        bytes[] memory datas = new bytes[](proposal.length);

        for (uint256 i = 0; i < proposal.length; i++) {
            targets[i] = proposal[i].target;
            values[i] = proposal[i].value;
            datas[i] = proposal[i].data;
        }

        _verifyActionsPreRunSignatures(targets, values, datas);
    }

    /// @notice function to verify market listing actions
    /// run against every MIP cross chain proposal to ensure that the
    /// proposal conforms to the expected market creation pattern.
    function _verifyActionsPreRunSignatures(
        address[] memory targets,
        uint256[] memory,
        bytes[] memory datas
    ) internal {
        uint256 proposalLength = targets.length;
        for (uint256 i = 0; i < proposalLength; i++) {
            if (functionDetectors[bytesToBytes4(datas[i])]) {
                comptroller = targets[i];

                /// --------------- FUNCTION SIGNATURE VERIFICATION ---------------

                require(
                    bytesToBytes4(datas[i + 1]) == orderedActions[1],
                    "action 1 must accept admin"
                );
                require(
                    bytesToBytes4(datas[i + 2]) == orderedActions[2],
                    "action 2 must approve underlying"
                );
                require(
                    bytesToBytes4(datas[i + 3]) == orderedActions[3],
                    "action 3 must mint mtoken"
                );

                /// --------------- ARGUMENT VERIFICATION ---------------

                address mtoken = extractAddress(datas[i]);

                address secondMToken = targets[i + 3];

                address approvalMToken = extractAddress(datas[i + 2]);

                uint256 tokenAmount = getTokenAmount(datas[i + 2]);

                uint256 mintAmount = getMintAmount(datas[i + 3]);

                require(mintAmount != 0, "mint amount must be greater than 0");
                require(
                    tokenAmount != 0,
                    "token approve amount must be greater than 0"
                );
                require(
                    mtoken == secondMToken,
                    "mtoken supported and minted must be the same"
                );
                require(
                    mtoken == approvalMToken,
                    "must approve mtoken to spend tokens"
                );

                createdMTokens.push(mtoken); /// add mToken to created mTokens array

                i += 3; /// skip to next action
            }
        }
    }

    function _verifyMTokensPostRun() internal view {
        /// --------------- VERIFICATION ---------------

        /// verify that all created mTokens have the same admin
        /// and that they have been minted and sent to the burn address
        uint256 createdMTokensLength = createdMTokens.length;
        for (uint256 i = 0; i < createdMTokensLength; i++) {
            require(
                MToken(createdMTokens[i]).admin() ==
                    Comptroller(comptroller).admin(),
                "mToken admin must be the same as comptroller admin"
            );
            require(
                MToken(createdMTokens[i]).balanceOf(address(0)) >= 1,
                "mToken not minted and burned"
            );
        }

        MToken[] memory markets = Comptroller(comptroller).getAllMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            require(markets[i].totalSupply() >= 1e8, "empty market");
            require(markets[i].balanceOf(address(0)) > 0, "no burnt tokens");
        }
    }

    function getTokenAmount(
        bytes memory input
    ) public pure returns (uint256 result) {
        require(input.length == 68, "invalid length, input must be 68 bytes");

        /// first 32 bytes of a dynamic byte array is just the length of the array
        /// next 4 bytes are function selector
        /// next 32 bytes are address, final 32 bytes are uint256 amount
        bytes32 rawBytes;
        assembly {
            let dataPointer := add(add(input, 0x40), 0x04) // Adjust for dynamic array and skip the function selector
            rawBytes := mload(dataPointer) // Load 32 bytes
        }

        result = uint256(rawBytes);
    }

    function getMintAmount(
        bytes memory input
    ) public pure returns (uint256 result) {
        require(input.length == 36, "invalid length, input must be 36 bytes");

        /// first 32 bytes of a dynamic byte array is just the length of the array
        /// next 4 bytes are function selector
        /// final 32 bytes are uint256 amount
        bytes32 rawBytes;
        assembly {
            let dataPointer := add(add(input, 0x20), 0x04) // Adjust for dynamic array and skip the function selector
            rawBytes := mload(dataPointer) // Load 32 bytes
        }

        result = uint256(rawBytes);
    }

    function extractAddress(
        bytes memory input
    ) public pure returns (address result) {
        /// first 32 bytes of a dynamic byte array is just the length of the array
        bytes32 rawBytes;
        assembly {
            let dataPointer := add(add(input, 0x20), 0x04) // Adjust for dynamic array and skip the function selector
            rawBytes := mload(dataPointer) // Load 32 bytes
        }

        result = address(uint160(uint256(rawBytes)));
    }

    /// @notice function to grab the first 4 bytes of calldata payload
    function bytesToBytes4(
        bytes memory toSlice
    ) public pure returns (bytes4 functionSignature) {
        if (toSlice.length < 4) {
            return bytes4(0);
        }

        assembly {
            functionSignature := mload(add(toSlice, 0x20))
        }
    }

    /// Credit ethereum stackexchange https://ethereum.stackexchange.com/a/58341
    function toString(bytes memory data) public pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[3 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }
}
