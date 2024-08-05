#!/bin/bash
# This script is used on the CI to print proposal output for the current epoch rewards proposal

MIP=$MIP_JSON_PATH
SOL_TEMPLATE_PATH=$TEMPLATE_PATH

output=$(forge script $SOL_TEMPLATE_PATH 2>&1)

# Removal of ANSI Escape Codes
clean_output=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')

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
    json_output=$(jq -n --arg file "$MIP" --arg output "$selected_output" '{file: $file, output: $output}')
else
    json_output=$(jq -n --arg file "$MIP" --arg output "Proposal $MIP failed. Check CI logs" '{file: $file, output: $output}')
fi

echo "Writing JSON to output.json..."

# Create output.json
touch output.json

# Write JSON to output.json
echo "$json_output" > output.json
