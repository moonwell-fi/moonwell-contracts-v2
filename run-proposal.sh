#!/bin/bash
# This script is used on the CI to print proposal output for the highest numbered .sol file in the PR.

# PR_CHANGED_FILES is a list of files changed in the PR, set by the CI
CHANGED_FILES=$PR_CHANGED_FILES
FOLDER=$PROPOSALS_FOLDER

if [[ ! -z "$CHANGED_FILES" ]]; then
    IFS=' ' read -r -a files_array <<< "$CHANGED_FILES"

    # Initialize an empty array to hold numbers and corresponding file names
    max_number=-1
    selected_file=""

    for file in "${files_array[@]}"; do
        if [[ $file == "$FOLDER"/*.sol && $file != *"/examples/"* ]]; then
            echo "Processing file: $file"
            
            # Extract the number following 'm', 'b', or 'o' before '.sol'
            number=$(echo $file | sed -E 's/.*[bmo]([0-9]+)[a-z]*\.sol/\1/')

            # Check if a number was actually found; if not, skip this file
            if [[ -z "$number" ]]; then
                echo "No number found in $file, skipping."
                continue
            fi

            # Check if this number is the highest found so far
            if [[ "$number" -gt "$max_number" ]]; then
                max_number=$number
                selected_file=$file
            fi        
        fi
    done

    # If file was found
    if [[ ! -z "$selected_file" ]]; then
        echo "Selected file with highest number: $selected_file"
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

        json_output=""
        # Write to JSON if selected_output otherwise write a failure message
        if [ ! -z "$selected_output" ]; then
            json_output=$(jq -n --arg file "$selected_file" --arg output "$selected_output" '{file: $file, output: $output}')
        else
            json_output=$(jq -n --arg file "$selected_file" --arg output "Proposal $selected_file failed. Check CI logs" '{file: $file, output: $output}')
        fi

        echo "Writing JSON to output.json..."
        # Create output.json 
        touch output.json
        # Write JSON to output.json
        echo "$json_output" > output.json
    else
        echo "No suitable file found for processing."
    fi
else
    echo "No changed files detected."
fi
