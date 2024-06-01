// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

library String {
    function hasChar(
        string memory _string,
        bytes1 delimiter
    ) internal pure returns (bool) {
        bytes memory stringBytes = bytes(_string);

        unchecked {
            for (uint256 i = 0; i < stringBytes.length; i++) {
                if (stringBytes[i] == delimiter) {
                    return true;
                }
            }
        }

        return false;
    }

    function countWords(
        string memory str,
        bytes1 delimiter
    ) public pure returns (uint256) {
        bytes memory strBytes = bytes(str);
        uint256 ctr = 0;

        for (uint256 i = 0; i < strBytes.length; i++) {
            if (
                /// bounds check on i + 1, want to prevent revert on trying to access index that isn't allocated
                (strBytes[i] != delimiter && i + 1 == strBytes.length) ||
                (strBytes[i] != delimiter && strBytes[i + 1] == delimiter)
            ) {
                ctr++;
            }
        }

        return (ctr);
    }

    /// @notice returns true if no double delimiters are found
    /// returns false if two delimiters are adjacent
    function checkNoDoubleDelimiters(
        string memory str,
        bytes1 delimiter
    ) public pure returns (bool) {
        bytes memory strBytes = bytes(str);

        for (uint256 i = 0; i < strBytes.length; i++) {
            /// include out of bounds check so we don't revert
            if (
                strBytes[i] == delimiter &&
                i + 1 < strBytes.length &&
                strBytes[i + 1] == delimiter
            ) {
                return false;
            }
        }

        return true;
    }

    /// @notice returns an array of strings split by the delimiter
    /// @param str the string to split
    /// @param delimiter the delimiter to split the string by
    function split(
        string memory str,
        bytes1 delimiter
    ) public pure returns (string[] memory) {
        // Check if the input string is empty
        if (bytes(str).length == 0) {
            return new string[](0);
        }

        uint256 stringCount = countWords(str, delimiter);

        string[] memory splitStrings = new string[](stringCount);
        bytes memory strBytes = bytes(str);
        uint256 startIndex = 0;
        uint256 splitIndex = 0;

        uint256 i = 0;

        while (i < strBytes.length) {
            if (strBytes[i] == delimiter) {
                splitStrings[splitIndex] = new string(i - startIndex);

                for (uint256 j = startIndex; j < i; j++) {
                    bytes(splitStrings[splitIndex])[j - startIndex] = strBytes[
                        j
                    ];
                }

                while (i < strBytes.length && strBytes[i] == delimiter) {
                    i++;
                }

                splitIndex++;
                startIndex = i;
            }
            i++;
        }

        /// handle final word

        while (i < strBytes.length && strBytes[i] == delimiter) {
            i++;
            startIndex++;
        }

        /// handle the last word
        splitStrings[splitIndex] = new string(strBytes.length - startIndex);

        for (
            uint256 j = startIndex;
            j < strBytes.length && strBytes[j] != delimiter;
            j++
        ) {
            bytes(splitStrings[splitIndex])[j - startIndex] = strBytes[j];
        }

        return splitStrings;
    }
}
