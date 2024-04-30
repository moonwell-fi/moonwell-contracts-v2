#!/bin/bash
# This script is used on the CI to print proposal output for the highest numbered .sol file in the PR.

# PR_CHANGED_FILES is a list of files changed in the PR, set by the CI
CHANGED_FILES=$PR_CHANGED_FILES
FOLDER=$PROPOSALS_FOLDER

if [[ ! -z "$CHANGED_FILES" ]]; then
    IFS=' ' read -r -a files_array <<< "$CHANGED_FILES"

    max_number=-1
    selected_file=""

    for file in "${files_array[@]}"; do
        if [[ $file == "$FOLDER"/*.sol ]]; then
            # Extract the number before ".sol"
            number=$(echo "$file" | grep -o -E '[0-9]+(?=.sol)')

            # Update selected_file if this file has a higher number
            if [[ "$number" -gt "$max_number" ]]; then
                max_number=$number
                selected_file=$file
            fi
        fi
    done

    # If a valid .sol file was found
    if [[ ! -z "$selected_file" ]]; then
        echo "Processing $selected_file..."
        output=$(forge script "$selected_file" 2>&1)
        # Removal of ANSI Escape Codes
        clean_output=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')

        echo "Output for $selected_file:"
        echo "$clean_output"

        # Extracting the relevant part of the output
        selected_output=$(echo "$clean_output" | awk '
        /------------------ Proposal Actions ------------------/, /\n\nProposal Description:/ {
            if (/\n\nProposal Description:/) exit;  # Exit before printing the line with "Proposal Description:"
            print;
        }
        ')

        # Write to JSON if selected_output is not empty
        if [ ! -z "$selected_output" ]; then
            json_output=$(jq -n --arg file "$selected_file" --arg output "$selected_output" '{file: $file, output: $output}')
            echo "Writing JSON to output.json..."
            # Create output.json 
            touch output.json
            # Write JSON to output.json
            echo "$json_output" > output.json
        fi
    fi
fi
