#!/bin/bash
BASE_DIR="artifacts/foundry"

# Find moonbeam directories, excluding any that start with 'mip-market-listing' and get the latest one
LATEST_MIP_DIR=$(ls -1v ${BASE_DIR}/ |  tr '[:upper:]' '[:lower:]' | grep '^mip-m' | grep -v '^mip-market-listing' | tail -n 1)

# Get the MIP number from the directory path 
MIP_NUM=${LATEST_MIP_DIR:5:2}

# Initialize variable to store the greatest MIP directory
LATEST_MIP_DIR=""

# Iterate over all files, normalize to lowercase, and find the greatest file name
for FILE in $(ls -1v ${BASE_DIR}/ | tr '[:upper:]' '[:lower:]' | grep '^mip-m' | grep -v '^mip-market-listing' ); do
    if [[ -z "$LATEST_MIP_DIR" || "$FILE" > "$LATEST_MIP_DIR" ]]; then
        LATEST_MIP_DIR="$FILE"
    fi
done

# Extract the MIP number from the latest file
MIP_NUM=${LATEST_MIP_DIR:5:2}

# skip MIP-M27 as it has already executed
if [[ $MIP_NUM == 27 ]]; then
    echo ""
else
    echo "${BASE_DIR}/${LATEST_MIP_DIR}/mipm${MIP_NUM}.json"
fi
