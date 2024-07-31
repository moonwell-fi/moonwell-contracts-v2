#!/bin/zsh

# Define the output directory
OUTPUT_DIR=~/tmp/mip-rewards-distribution
mkdir -p $OUTPUT_DIR

# Define the URLs and filenames
URLS=(
  "https://moonwell-reward-automation.moonwell.workers.dev/?type=markdown&proposal=M35&network=Moonbeam"
  "https://moonwell-reward-automation.moonwell.workers.dev/?type=json&proposal=M35&network=Moonbeam"
  "https://moonwell-reward-automation.moonwell.workers.dev/?type=markdown&proposal=B23&network=Base"
  "https://moonwell-reward-automation.moonwell.workers.dev/?type=json&proposal=B23&network=Base"
  "https://moonwell-reward-automation.moonwell.workers.dev/?type=markdown&proposal=O02&network=Optimism"
  "https://moonwell-reward-automation.moonwell.workers.dev/?type=json&proposal=O02&network=Optimism"
)

FILENAMES=(
  "Moonbeam_M35.md"
  "Moonbeam_M35.json"
  "Base_B23.md"
  "Base_B23.json"
  "Optimism_O02.md"
  "Optimism_O02.json"
)

# Download the files
for i in {1..${#URLS[@]}}; do
  URL=${URLS[$i]}
  FILENAME=${FILENAMES[$i]}
  curl -o $OUTPUT_DIR/$FILENAME $URL
done

echo "Files downloaded to $OUTPUT_DIR"
