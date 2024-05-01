#!/bin/bash
BASE_DIR="artifacts/foundry"

# Get all moonbeam MIP directories
LATEST_MIP_DIR=$(ls -1v ${BASE_DIR}/ | grep '^mip-m' | tail -n 1)

# Filter directories, excluding any that start with 'mip-market-listing'
LATEST_MIP_DIR=$(ls -1v ${BASE_DIR}/ | grep '^mip-m' | grep -v '^mip-market-listing' | tail -n 1)

# Get the MIP number from the directory path 
MIP_NUM=${LATEST_MIP_DIR:5:2}

# Print the path to the latest moonbeam MIP artifact json file
echo "${BASE_DIR}/${LATEST_MIP_DIR}/mipm${MIP_NUM}.json"
