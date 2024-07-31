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
  "https://moonwell-reward-automation.moonwell.workers.dev/?type=markdown&proposal=O01&network=Optimism"
  "https://moonwell-reward-automation.moonwell.workers.dev/?type=json&proposal=O01&network=Optimism"
)

FILENAMES=(
  "m35.md"
  "m35.json"
  "b23.md"
  "b23.json"
  "o01.md"
  "o01.json"
)

# Download the files
for i in {1..${#URLS[@]}}; do
  URL=${URLS[$i]}
  FILENAME=${FILENAMES[$i]}
  curl -o $OUTPUT_DIR/$FILENAME $URL
done

echo "Files downloaded to $OUTPUT_DIR"
