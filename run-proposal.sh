#!/bin/bash
# This script is used on the CI to print proposal output for the highest numbered .sol file in the PR.

CHANGED_FILES=$PR_CHANGED_FILES
FOLDER=$PROPOSALS_FOLDER

if [[ ! -z "$CHANGED_FILES" ]]; then
    IFS=' ' read -r -a files_array <<< "$CHANGED_FILES"

    # Initialize an empty array to hold numbers and corresponding file names
    max_number=-1
    selected_file=""

    for file in "${files_array[@]}"; do
        if [[ $file == "$FOLDER"/*.sol && $file != *"/examples/"* ]]; then
            # Extract the number following 'm', 'b', or 'o' before '.sol', make sure to capture correctly and avoid non-numeric values
            number=$(echo $file | grep -o -E '[mbo]([0-9]+)\.sol' | grep -o -E '[0-9]+')

            # Logging for debugging
            echo "File: $file, Extracted Number: $number"

            # Only perform the comparison if number is not empty and is a numeric value
            if [[ ! -z "$number" && "$number" =~ ^[0-9]+$ ]]; then
                if [[ "$number" -gt "$max_number" ]]; then
                    max_number=$number
                    selected_file=$file
                fi
            else
                echo "Skipping $file as no valid number was extracted."
            fi
        fi
    done

    # If a file was found
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

        # Prepare JSON output
        json_output=""
        if [[ ! -z "$selected_output" ]]; then
            json_output=$(jq -n --arg file "$selected_file" --arg output "$selected_output" '{file: $file, output: $output}')
        else
            json_output=$(jq -n --arg file "$selected_file" --arg output "Proposal $selected_file failed. Check CI logs" '{file: $file, output: $output}')
        fi

        echo "Writing JSON to output.json..."
        echo "$json_output" > output.json
    else
        echo "No suitable file found to process."
    fi
fi
