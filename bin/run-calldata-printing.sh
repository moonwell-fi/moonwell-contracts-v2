#!/bin/bash
# This script is used on the CI to print proposal calldata 

touch output.txt
forge script script/CalldataPrinting.s.sol -vv --ffi --block-gas-limit "18446744073709551615" --gas-limit "18446744073709551615" > output.txt

echo "Printing calldata"
cat output.txt
