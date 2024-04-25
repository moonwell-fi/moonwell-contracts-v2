#!/bin/bash

# Step 1: Get the current branch name
current_branch=$(git branch --show-current)

# Step 2: Use GitHub CLI to get the PR number associated with the current branch
pr_details=$(gh pr list --head "$current_branch" --json number)
pr_number=$(echo "$pr_details" | jq -r '.[0].number')

# Step 3: Print changes if a PR number is found
if [ ! -z "$pr_number" ]; then
  # Get the list of modified .sol files in the 'src/proposals/mips/' directory
  modified_files=$(gh pr diff $pr_number --name-only | grep 'src/proposals/mips/.*\.sol$')

  # Filter out the specific file
  echo "$modified_files" | grep -v 'src/proposals/mips/mip-b00/mip-b00.sol'
fi
