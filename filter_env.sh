#!/bin/bash

root_dir="$1"
desired_pat=(5 10)     # Desired pat values
desired_res=(5 10)     # Desired res values
desired_win=(30 60)    # Desired win values

new_root_dir="${root_dir}_filtered"

# Array to store the results
results=()

process_tree() {
    # Iterate over the names array
    for n1 in "${desired_pat[@]}"; do
        for n2 in "${desired_res[@]}"; do
            for n3 in "${desired_win[@]}"; do
                # Execute the find command and store the results in an array
                mapfile -d '' current_results < <(find "$root_dir" -name "test-np$n1-res$n2-win$n3*" -type d -print0)

                # Append the current results to the main results array
                results+=("${current_results[@]}")
            done
        done
    done
}

# Create new root directory
mkdir -p "$new_root_dir"

process_tree

if [ -d "$root_dir" ]; then
    #The while loop iterates over the subdirectories found, and each subdirectory path is added to the subdirs array
    for subdir in "${results[@]}"; do
        echo $subdir 
        cp -r --parents $subdir $new_root_dir
    done
fi 
