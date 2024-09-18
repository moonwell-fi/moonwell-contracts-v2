#!/bin/bash
# This script is used on the CI to print proposal calldata 

touch output.txt
forge script script/CalldataPrinting.s.sol -vvv > output.txt
