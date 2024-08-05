#!/bin/bash

export MIP_REWARDS_PATH=src/proposals/mips/mip-o02/o02.json
echo "MIP_REWARDS_PATH=$MIP_REWARDS_PATH"
export DESCRIPTION_PATH=src/proposals/pmips/mip-o02/o02.md
echo "DESCRIPTION_PATH=$DESCRIPTION_PATH"
export CHAIN_ID=10
echo "CHAIN_ID=$CHAIN_ID"
export PRIMARY_FORK_ID=0
echo "PRIMARY_FORK_ID=$PRIMARY_FORK_ID"
export TEMPLATE_PATH="src/proposals/templates/mipRewardsDistributionExternalChain.sol:mipRewardsDistributionExternalChain"
echo "TEMPLATE_PATH=$TEMPLATE_PATH"
