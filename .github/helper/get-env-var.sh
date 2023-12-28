#!/bin/bash
# do not run mip-b07 as it has already run, and running again causes an error as all integration tests
# run the latest proposal automatically.
# once proposals have been successfully executed onchain, they will be added to the list of proposals
# to exclude from running in this script.

BASE_DIR="artifacts/foundry"

LATEST_MIP_DIR=$(ls -1v ${BASE_DIR}/ | grep '^mip-b' | tail -n 1)

MIP_NUM=${LATEST_MIP_DIR:5:2}

if [[ "$LATEST_MIP_DIR" == "mip-b12-moonbeam.sol" ]]; then
    echo "PROPOSAL_ARTIFACT_PATH="
else
    echo "PROPOSAL_ARTIFACT_PATH=${BASE_DIR}/${LATEST_MIP_DIR}/mipb${MIP_NUM}.json"
fi
