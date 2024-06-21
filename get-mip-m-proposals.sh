#!/bin/bash
BASE_DIR="src/proposals/mips"

# Find directories starting with 'mip-mXX'
MIP_M_DIRS=$(find ${BASE_DIR} -type d -name 'mip-m??')

# Initialize an array to store the JSON file paths
JSON_FILES=()

# Iterate over the directories and collect JSON file paths
for DIR in ${MIP_M_DIRS}; do
    for FILE in ${DIR}/*.sol; do
        if [ -f "$FILE" ] && [[ "$FILE" != "src/proposals/mips/mip-m16/mip-m16.sol" ]]; then
            JSON_FILES+=("${FILE}")
        fi
    done
done

# Print the array of JSON file paths, separated by newlines
printf "%s\n" "${JSON_FILES[@]}"
