# Check all error.log in all subfolders of data/reference_clusterings/
# if any show "Command terminated by signal 4", print the path to the error.log file

#!/bin/bash

# find data/reference_clusterings/ -type f -name "error.log" | while read -r file; do
#     if grep -q "Command terminated by signal 4" "$file"; then
#         echo "Found in: $file"
#     fi
# done

# find recursively in all subfolders of data/empirical_networks/stats
# all files with only "" (two double quotes) in the content, and print the path to the file
# remove all the found files
find data/estimated_clusterings/ec-sbm-v2/*/acc -type f -name "*" | while read -r file; do
    if [[ $(cat "$file") == '""' ]]; then
        echo "Found empty content in: $file"
        rm "$file"
    fi
done
