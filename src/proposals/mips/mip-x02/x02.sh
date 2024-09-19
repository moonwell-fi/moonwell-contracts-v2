#!/bin/bash
export MIP_REWARDS_PATH=src/proposals/mips/mip-x02/x02.json
echo "MIP_REWARDS_PATH=$MIP_REWARDS_PATH"

export DESCRIPTION_PATH=src/proposals/mips/mip-x02/x02.md
echo "DESCRIPTION_PATH=$DESCRIPTION_PATH"

export PRIMARY_FORK_ID=0
echo "PRIMARY_FORK_ID=$PRIMARY_FORK_ID"

export TEMPLATE_PATH="src/proposals/templates/mipRewardsDistribution.sol:mipRewardsDistribution"
echo "TEMPLATE_PATH=$TEMPLATE_PATH"

