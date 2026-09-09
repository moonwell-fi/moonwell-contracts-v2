#!/bin/bash
export MIP_REWARDS_PATH=proposals/mips/mip-x67/x67.json
echo "MIP_REWARDS_PATH=$MIP_REWARDS_PATH"

export DESCRIPTION_PATH=proposals/mips/mip-x67/x67.md
echo "DESCRIPTION_PATH=$DESCRIPTION_PATH"

export PRIMARY_FORK_ID=3
echo "PRIMARY_FORK_ID=$PRIMARY_FORK_ID"

# on-chain proposal id from the first (init) propose() call; append calls
# are encoded against it when DO_PRINT regenerates the batch
export BATCH_PROPOSAL_ID=186
echo "BATCH_PROPOSAL_ID=$BATCH_PROPOSAL_ID"
