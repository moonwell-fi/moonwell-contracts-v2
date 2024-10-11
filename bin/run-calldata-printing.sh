#!/bin/bash
# This script is used on the CI to print proposal calldata 

touch output.txt

# uses shangai for execution because wrsETH was deployed with shanghai https://github.com/foundry-rs/foundry/issues/6228#issuecomment-1812843644
forge script script/CalldataPrinting.s.sol -vv --ffi --block-gas-limit "18446744073709551615" --gas-limit "18446744073709551615" --evm-version shanghai > output.txt

echo "Printing calldata"
cat output.txt
