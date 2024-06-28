#!/bin/bash
BASE_DIR="artifacts/foundry"

cd ./src/proposals/mips

# Gather mip-mXX directories, sort them descending by the number suffix
m_dirs=$(ls -d mip-m[0-9]* | sort -t 'm' -k2 -nr)

# Gather mip-bXX directories, sort them descending by the number suffix
b_dirs=$(ls -d mip-b[0-9]* | sort -t 'b' -k2 -nr)

# Convert string lists to arrays by replacing newlines with spaces
m_dirs="${m_dirs//$'\n'/ }"
b_dirs="${b_dirs//$'\n'/ }"

# Function to intercalate arrays
intercalate() {
    local m_arr=($1)
    local b_arr=($2)
    local result=""
    local moonbeamPath
    local basePath

    # Get the max index of the two arrays
    local max_index=$(( ${#m_arr[@]} > ${#b_arr[@]} ? ${#m_arr[@]} : ${#b_arr[@]} ))
        
    # Loop through the arrays and append the paths to the result string
    for (( i=0; i<$max_index; i++ )); do

        # Construct the paths, removing the dash from the directory name to get the file name
        moonbeamPath="${BASE_DIR}/${m_arr[i]}.sol/${m_arr[i]//-/}.json"
        basePath="${BASE_DIR}/${b_arr[i]}.sol/${b_arr[i]//-/}.json"
        
        # Append the paths to the result string if they are not empty
        if [[ -n "${m_arr[i]}" ]]; then
            result+="${moonbeamPath},"
        fi

        if [[ -n "${b_arr[i]}" ]]; then
            result+="${basePath},"
        fi
    done

    # Print the result string
    echo "${result%,}"
}


# Call intercalate and trim the last comma
intercalate "$m_dirs" "$b_dirs"
