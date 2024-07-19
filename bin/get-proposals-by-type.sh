#!/bin/bash

# Check if the required argument is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <ProposalType>"
    exit 1
fi

PROPOSAL_TYPE=$1
BASE_DIR="src/proposals/mips"

# Find directories starting with 'mip-XXX'
MIP_DIRS=$(find ${BASE_DIR} -type d -name 'mip-???')

# Initialize an array to store the .sol file paths
SOL_FILES=()

# Iterate over the directories and collect .sol file paths
for DIR in ${MIP_DIRS}; do
    for FILE in ${DIR}/*.sol; do
        # Check if file exists and is not the specific file to exclude
        if [ -f "$FILE" ]; then
            # Check if file contains the import lines for the given proposal type
            if grep -Eq " from \"@proposals/proposalTypes/${PROPOSAL_TYPE}.sol\";" "$FILE"; then
                # Then check if the file also contains the build function signature
                if grep -q 'function build(Addresses addresses) public override {' "$FILE"; then
                    SOL_FILES+=("${FILE}")
                fi
            fi
        fi
    done
done

# Print the array of .sol file paths, separated by newlines
printf "%s\n" "${SOL_FILES[@]}"
