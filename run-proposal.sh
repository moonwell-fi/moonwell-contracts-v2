#!/bin/bash
# This script is used on the CI to print proposal output for the files encountered in the PR.

# PR_CHANGED_FILES is a list of files changed in the PR, set by the CI
CHANGED_FILES=$PR_CHANGED_FILES
FOLDER=$PROPOSALS_FOLDER

declare -a results

if [[ ! -z "$CHANGED_FILES" ]]; then
    IFS=' ' read -r -a files_array <<< "$CHANGED_FILES"

    for file in "${files_array[@]}"; do
        if [[ $file == "$FOLDER"/* ]]; then
            output=$(forge script "$file" 2>&1)
            # Removal of ANSI Escape Codes
            clean_output=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')

            # Extracting the relevant part of the output
            selected_output=$(echo "$clean_output" | awk '
            /------------------ Proposal Actions ------------------/, /\n\nProposal Description:/ {
                if (/\n\nProposal Description:/) exit;  # Exit before printing the line with "Proposal Description:"
                print;
            }
            ')

            # Only add to results if selected_output is not empty
            if [ ! -z "$selected_output" ]; then
                json_entry=$(jq -n --arg file "$file" --arg output "$selected_output" '{file: $file, output: $output}')
                results+=("$json_entry")
            fi
        fi
    done

    # Construct JSON array from results
    if [ ${#results[@]} -ne 0 ]; then
        json_output=$(jq -n --argjson entries "$(echo ${results[@]} | jq -s '.')" '{"results": $entries}')
        # Encode to base64 to ensure safe passage through environment variables
        base64_output=$(echo "$json_output" | base64 | tr -d '\n')
        echo "$base64_output"
    else
        echo "No relevant output found in $FOLDER"
    fi
else
    echo "No PR changes detected in $FOLDER"
fi
