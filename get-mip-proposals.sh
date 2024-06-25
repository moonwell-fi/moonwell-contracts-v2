#!/bin/bash
BASE_DIR="src/proposals/mips"

# Find directories starting with 'mip-XXX'
MIP_DIRS=$(find ${BASE_DIR} -type d -name 'mip-???')

# Initialize an array to store the JSON file paths
JSON_FILES=()

# Iterate over the directories and collect JSON file paths
for DIR in ${MIP_DIRS}; do
    for FILE in ${DIR}/*.sol; do
        # Check if file exists and is not the specific file to exclude
        if [ -f "$FILE" ] && [[ "$FILE" != "src/proposals/mips/mip-o00/mip-o00.sol" ]]; then
            # Check if file contains the specified import line
            if grep -q 'import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";' "$FILE"; then
                JSON_FILES+=("${FILE}")
            fi
        fi
    done
done

# Print the array of JSON file paths, separated by newlines
printf "%s\n" "${JSON_FILES[@]}"
