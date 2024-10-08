#!/bin/bash

echo $PR_CHANGED_FILES
# Check if PR_CHANGED_FILES contains any files in the specified directories
if echo "$PR_CHANGED_FILES" | grep -qE "src/proposals/templates|src/proposal/proposalTypes/"; then
  echo "Matching files found, running on chain calldata check..."
  
  # Run the forge command
  time forge test --match-contract TestProposalCalldataGeneration \
       -vvv --ffi --block-gas-limit 10000000000 --evm-version shanghai
else
  echo "No matching files found. Skipping job.."
fi
