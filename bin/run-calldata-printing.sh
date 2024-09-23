#!/bin/bash
# This script is used on the CI to print proposal calldata 

touch output.txt
forge script script/CalldataPrinting.s.sol -vvv --ffi --block-gas-limit "99999999999" > output.txt
