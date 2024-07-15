#!/bin/bash
source .env

output_title() {
  local text="# $1"
  echo "$text" > test/mutation/resultGovernor.md
}

output_heading() {
  local text="\n## $1"
  echo "$text" >> test/mutation/resultGovernor.md
}

output_results() {
  local result="$1"
  local heading="$2"
  local content="<details>
<summary>$heading</summary>\n
\`\`\`\n$result\n\`\`\`
</details>"
  echo "$content" >> test/mutation/resultGovernor.md
}

# Function to extract the last line from a file
get_last_line() {
  local file="$1"
  tail -n 1 "$file"
}

get_content_after_pattern() {
  local output="$1"
  local pattern="$2"

  line_number=$(grep -n "$pattern" "$output" | head -n 1 | cut -d ':' -f1)

  content_after_n_lines=$(tail -n +$((line_number)) "$output")

  clean_content=$(echo "$content_after_n_lines" | sed 's/\x1B\[[0-9;]*m//g')

  # Return the extracted content
  echo "$clean_content"
}


process_test_output() {
  local test_type="$1"
  local output="$2"

  echo "\n### $test_type:" >> test/mutation/resultGovernor.md

  # Check if output contains "Failing tests: "
  if grep -q "Failing tests:" "$output"; then
    
    # Extract last line
    last_line=$(get_last_line "$output")

    # Remove escape sequences and color codes using sed
    clean_line=$(echo "$last_line" | sed 's/\x1B\[[0-9;]*m//g')

    # Extract failed and passed tests using awk
    failed_tests=$(echo "$clean_line" | awk '{print $5}')
    passed_tests=$(echo "$clean_line" | awk '{print $8}')

    # Mark current mutation as failed
    is_current_mutation_failed=1

    # Append to last_lines.txt with desired format
    echo "Failed $test_type: $failed_tests, Passed Tests: $passed_tests" >> test/mutation/resultGovernor.md

    content_after_pattern=$(get_content_after_pattern "$output" "Failing tests:")
    output_results "$content_after_pattern" "View Failing tests"
  else
    # Extract last line
    last_line=$(get_last_line "$output")

    # Remove escape sequences and color codes using sed
    clean_line=$(echo "$last_line" | sed 's/\x1B\[[0-9;]*m//g')

    # Extract failed and passed tests using awk
    passed_tests=$(echo "$clean_line" | awk '{print $7}')

    # Append to last_lines.txt with desired format
    echo "Failed $test_type: 0, Passed Tests: $passed_tests" >> test/mutation/resultGovernor.md
  fi
}

target_file="src/Governance/MultichainGovernor/MultichainGovernor.sol"
target_dir="MutationTestOutput"
num_files=407

# Create directory for output files if it doesn't exist
mkdir -p "$target_dir"

# Number of failed mutations
failed_mutation=0

is_current_mutation_failed=0 # Intialized as false

# Append Mutation Result to Result_MultichainGovernor.md with desired format
output_title "Mutation Results\n"

# Loop through the number of files
for (( i=1; i <= num_files; i++ )); do
  # Construct dynamic file path using iterator
  file_path="gambit_out_MultichainGovernor/mutants/$i/src/Governance/MultichainGovernor/MultichainGovernor.sol"

  # Check if file exists before copying
  if [[ -f "$file_path" ]]; then
    # Mark current mutation as not failed at the start of run
    (( is_current_mutation_failed=0 ))
    # Copy the file's contents to the target file
    cat "$file_path" > "$target_file"

    output_heading "Mutation $i"

    mutation_diff=$(gambit summary --mids $i --mutation-directory gambit_out_MultichainGovernor)
    clean_mutation_diff=$(echo "$mutation_diff" | sed 's/\x1B\[[0-9;]*m//g')
    output_results "$clean_mutation_diff" "View mutation diff"

    temp_output_file="$target_dir/temp.txt"

    touch "$temp_output_file"

    # Run unit tests and capture output
    unit_command_output=$(forge test --mc Multichain -v)
    echo "$unit_command_output" > "$temp_output_file"

    # Process unit test outputs using the function
    process_test_output "Unit and Multichain Tests" "$temp_output_file"

    # Run moonbeam integration tests and capture output
    integration_command_output=$(forge test --match-contract MoonbeamTest --fork-url moonbeam -v --fork-block-number $MOONBEAM_FORK_BLOCK_NUMBER --block-number $MOONBEAM_BLOCK_NUMBER --block-timestamp $MOONBEAM_TIMESTAMP --chain-id $MOONBEAM_CHAIN_ID)
    echo "$integration_command_output" > "$temp_output_file"

    # Process integration test outputs using the function
    process_test_output "Moonbeam Integration Tests" "$temp_output_file"

    # Run base integration tests and capture output
    integration_command_output=$(forge test --match-contract LiveSystemBaseTest --fork-url base -v --fork-block-number $BASE_FORK_BLOCK_NUMBER --block-number $BASE_BLOCK_NUMBER --block-timestamp $BASE_TIMESTAMP --chain-id $BASE_CHAIN_ID)
    echo "$integration_command_output" > "$temp_output_file"

    # Process integration test outputs using the function
    process_test_output "Base Integration Test" "$temp_output_file"

    rm "$temp_output_file"

    if [[ $is_current_mutation_failed -eq 1 ]]; then
      # Increament total mutation failed
      (( failed_mutation++ ))
    fi

  else
    echo "Warning: File '$file_path' not found."
  fi
done

output_heading "Mutation Testing Result"
echo "$failed_mutation failed out of total $num_files through integration tests" >> test/mutation/resultGovernor.md
