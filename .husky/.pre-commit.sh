#!/bin/bash

# Temporary file to hold list of staged .sol files
STAGED_SOL_FILES=$(mktemp)
# Temporary file to hold list of all staged files for prettier
STAGED_FILES=$(mktemp)

# List staged .sol files ignoring deleted files
git diff --cached --name-status -- '*.sol' | grep -v '^D' | cut -f2- > "$STAGED_SOL_FILES"
# List all staged files ignoring deleted files
git diff --cached --name-status | grep -v '^D' | cut -f2- > "$STAGED_FILES"

# Run Solhint on staged .sol files, if any
if [ -s "$STAGED_SOL_FILES" ]; then
    # If there are staged .sol files, run Solhint on them
    SOLHINT_OUTPUT=$(cat "$STAGED_SOL_FILES" | xargs npx solhint --config ./.solhintrc --ignore-path .solhintignore)
    SOLHINT_EXIT_CODE=$?

    if [ $SOLHINT_EXIT_CODE -ne 0 ]; then
        echo "Solhint errors detected:"
        echo "$SOLHINT_OUTPUT"
        rm "$STAGED_SOL_FILES" "$STAGED_FILES"
        exit $SOLHINT_EXIT_CODE
    else
        # Re-add the .sol files to include any automatic fixes by Solhint
        cat "$STAGED_SOL_FILES" | xargs git add
    fi
fi

# Run Prettier and check for errors on staged files
if [ -s "$STAGED_FILES" ]; then
    # Note: Using `--write` with Prettier to automatically fix formatting
    PRETTIER_OUTPUT=$(cat "$STAGED_FILES" | xargs npx prettier --ignore-path .prettierignore --write)
    PRETTIER_EXIT_CODE=$?

    if [ $PRETTIER_EXIT_CODE -ne 0 ]; then
        echo "Prettier formatting errors detected:"
        echo "$PRETTIER_OUTPUT"
        rm "$STAGED_SOL_FILES" "$STAGED_FILES"
        exit $PRETTIER_EXIT_CODE
    else
        # Re-add the files to include any formatting changes by Prettier
        cat "$STAGED_FILES" | xargs git add
    fi
fi

# Clean up
rm "$STAGED_SOL_FILES" "$STAGED_FILES"

# If we reach this point, either there were no issues or only warnings.
# Warnings are allowed, so we exit successfully.
exit 0
