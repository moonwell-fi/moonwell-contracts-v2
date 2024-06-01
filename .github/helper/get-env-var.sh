#!/bin/bash
# Do not run mip-b07 as it has already run, and running again causes an error as all integration tests
# run the latest proposal automatically.
# Once proposals have been successfully executed onchain, they will be added to the list of proposals
# to exclude from running in this script.

BASE_DIR="artifacts/foundry"

# Initialize variable to store the greatest MIP directory
LATEST_MIP_DIR=""

# Iterate over all files, normalize to lowercase, and find the greatest file name
for FILE in $(ls -1v ${BASE_DIR}/ | tr '[:upper:]' '[:lower:]' | grep '^mip-b'); do
    if [[ -z "$LATEST_MIP_DIR" || "$FILE" > "$LATEST_MIP_DIR" ]]; then
        LATEST_MIP_DIR="$FILE"
    fi
done

# Extract the MIP number from the latest file
MIP_NUM=${LATEST_MIP_DIR:5:2}

if [[ "$LATEST_MIP_DIR" == "mip-b18.sol" ]]; then
    echo "PROPOSAL_ARTIFACT_PATH="
else
    echo "PROPOSAL_ARTIFACT_PATH=${BASE_DIR}/${LATEST_MIP_DIR}/mipb${MIP_NUM}.json"
fi
