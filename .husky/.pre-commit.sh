#!/bin/bash

# Run solhint
SOLHINT_OUTPUT=$(npx solhint --config ./.solhintrc **/*.sol --ignore-path .solhintignore)
SOLHINT_EXIT_CODE=$?

# Check for solhint errors
if [ $SOLHINT_EXIT_CODE -ne 0 ]; then
    echo "Solhint errors detected:"
    echo "$SOLHINT_OUTPUT"
    exit $SOLHINT_EXIT_CODE
fi

# Run prettier and check for errors
PRETTIER_OUTPUT=$(npx prettier **/* --ignore-path .prettierignore -w --check)
PRETTIER_EXIT_CODE=$?

if [ $PRETTIER_EXIT_CODE -ne 0 ]; then
    echo "Prettier formatting errors detected:"
    echo "$PRETTIER_OUTPUT"
    exit $PRETTIER_EXIT_CODE
fi

# If we reach this point, either there were no issues or only warnings.
# Warnings are allowed, so we exit successfully.
exit 0
