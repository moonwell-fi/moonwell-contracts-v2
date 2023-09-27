#!/bin/bash

# Define the base directory
BASE_DIR="artifacts/foundry"

# Find the highest numbered mip-bXX directory
LATEST_MIP_DIR=$(ls -1v ${BASE_DIR}/ | grep '^mip-b' | tail -n 1)

# Output the command to set the PROPOSAL_ARTIFACT_PATH environment variable
echo "PROPOSAL_ARTIFACT_PATH=${BASE_DIR}/${LATEST_MIP_DIR}/mipb${LATEST_MIP_DIR:6}.json" >> $GITHUB_ENV
