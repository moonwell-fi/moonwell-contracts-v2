#!/bin/bash
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

echo "${BASE_DIR}/${LATEST_MIP_DIR}/mipb${MIP_NUM}.json"
