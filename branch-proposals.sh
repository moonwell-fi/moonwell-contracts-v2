#!/bin/bash

# Step 1: Get the current branch name
current_branch=$(git branch --show-current)

# Step 2: Use GitHub CLI to get the PR number associated with the current branch
# Fetching the PR number, assuming the repository is the current repository and you are the owner
pr_details=$(gh pr list --head "$current_branch" --json number)
pr_number=$(echo "$pr_details" | jq -r '.[0].number')

# Step 3: Print changes if a PR number is found
if [ ! -z "$pr_number" ]; then
  gh pr diff $pr_number --name-only | grep 'src/proposals/mips/'
fi
