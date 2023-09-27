#!/bin/bash

BASE_DIR="artifacts/foundry"

LATEST_MIP_DIR=$(ls -1v ${BASE_DIR}/ | grep '^mip-b' | tail -n 1)

MIP_NUM=${LATEST_MIP_DIR:5:2}

echo "PROPOSAL_ARTIFACT_PATH=${BASE_DIR}/${LATEST_MIP_DIR}/mipb${MIP_NUM}.json" >> $GITHUB_ENV
