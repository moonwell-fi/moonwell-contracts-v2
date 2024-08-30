#!/bin/zsh

# Define the output directory
OUTPUT_DIR=~/tmp/mip-rewards-distribution
mkdir -p $OUTPUT_DIR

# Define the URLs and filenames
URLS=(
  "https://moonwell-reward-automation.moonwell.workers.dev/?type=markdown&proposal=M37&network=Moonbeam&timestamp=1724782480"
  "https://moonwell-reward-automation.moonwell.workers.dev/?type=json&proposal=M37&network=Moonbeam&timestamp=1724782480"
  "https://moonwell-reward-automation.moonwell.workers.dev/?type=markdown&proposal=B26&network=Base&timestamp=1724782480"
  "https://moonwell-reward-automation.moonwell.workers.dev/?type=json&proposal=B26&network=Base&timestamp=1724782480"
  "https://moonwell-reward-automation.moonwell.workers.dev/?type=markdown&proposal=O06&network=Optimism&timestamp=1724782480"
  "https://moonwell-reward-automation.moonwell.workers.dev/?type=json&proposal=O06&network=Optimism&timestamp=1724782480"
)

FILENAMES=(
  "m37.md"
  "m37.json"
  "b26.md"
  "b26.json"
  "o06.md"
  "o06.json"
)

# Download the files
for i in {1..${#URLS[@]}}; do
  URL=${URLS[$i]}
  FILENAME=${FILENAMES[$i]}
  curl -o $OUTPUT_DIR/$FILENAME $URL
done

echo "Files downloaded to $OUTPUT_DIR"
