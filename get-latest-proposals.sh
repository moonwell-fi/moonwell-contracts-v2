#!/bin/bash
BASE_DIR="artifacts/foundry"

cd ./src/proposals/mips

# Gather mip-mXX directories, sort them descending by the number suffix
m_dirs=$(ls -d mip-m[0-9]* | sort -t 'm' -k2 -nr)

# Gather mip-bXX directories, sort them descending by the number suffix
b_dirs=$(ls -d mip-b[0-9]* | sort -t 'b' -k2 -nr)

# Function to intercalate arrays
intercalate() {
    local m_arr=($1)
    local b_arr=($2)
    local max_index=$(( ${#m_arr[@]} > ${#b_arr[@]} ? ${#m_arr[@]} : ${#b_arr[@]} ))
    local result=""
    local moonbeamPath
    local basePath
    
    for (( i=0; i<$max_index; i++ )); do
        moonbeamPath="${BASE_DIR}/${m_arr[i]}/${m_arr[i]}.sol"
        basePath="${BASE_DIR}/${b_arr[i]}/${b_arr[i]}.sol"
        
        if [[ -n "${m_arr[i]}" ]]; then
            result+="${moonbeamPath},"
        fi
        if [[ -n "${b_arr[i]}" ]]; then
            result+="${basePath},"
        fi
    done
    echo "${result%,}"
}

# Convert string lists to arrays by replacing newlines with spaces
m_dirs="${m_dirs//$'\n'/ }"
b_dirs="${b_dirs//$'\n'/ }"

# Call intercalate and trim the last comma
intercalate "$m_dirs" "$b_dirs"
