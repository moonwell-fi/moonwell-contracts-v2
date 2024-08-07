#!/bin/bash

# Define the directory to search
SEARCH_DIR="src/proposals/mips"

# Exclude the examples and mip-xwell directories and mip00.sol file
EXCLUDE_DIRS=("$SEARCH_DIR/examples" "$SEARCH_DIR/mip-xwell")
EXCLUDE_FILES=("$SEARCH_DIR/mip00.sol")

# Construct the find command
find_cmd="find \"$SEARCH_DIR\""

# Add exclusions for directories
for exclude_dir in "${EXCLUDE_DIRS[@]}"; do
    find_cmd+=" -path \"$exclude_dir\" -prune -o"
done

# Add exclusions for files
for exclude_file in "${EXCLUDE_FILES[@]}"; do
    find_cmd+=" ! -path \"$exclude_file\""
done

# Add the condition to find .sol and .sh files
find_cmd+=" \( -name \"*.sol\" -o -name \"*.sh\" \)"

# Execute the find command
results=$(eval $find_cmd)

# Filter out files that end with a letter
filtered_results=$(echo "$results" | grep -E '.*[0-9]\.(sol|sh)$')

# Print the filtered results
echo "$filtered_results"
