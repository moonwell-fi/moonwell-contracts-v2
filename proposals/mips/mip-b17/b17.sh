#!/usr/bin/env bash

# Set paths for MIP-B17 related files
export MTOKENS_PATH=proposals/mips/mip-b17/MTokens.json
export EMISSION_CONFIGURATIONS_PATH=proposals/mips/mip-b17/RewardStreams.json
export DESCRIPTION_PATH=proposals/mips/mip-b17/MIP-B17.md

# Set configuration parameters
export PRIMARY_FORK_ID=1
export EXCLUDE_MARKET_ADD_CHECKER=true
export NONCE=0

# Echo all set variables for confirmation
echo "MTOKENS_PATH=$MTOKENS_PATH"
echo "EMISSION_CONFIGURATIONS_PATH=$EMISSION_CONFIGURATIONS_PATH"
echo "DESCRIPTION_PATH=$DESCRIPTION_PATH"
echo "PRIMARY_FORK_ID=$PRIMARY_FORK_ID"
echo "EXCLUDE_MARKET_ADD_CHECKER=$EXCLUDE_MARKET_ADD_CHECKER"
echo "NONCE=$NONCE"
