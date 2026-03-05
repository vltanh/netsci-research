# Check all error.log in all subfolders of data/reference_clusterings/
# if any show "Command terminated by signal 4", print the path to the error.log file

#!/bin/bash

find data/reference_clusterings/ -type f -name "error.log" | while read -r file; do
    if grep -q "Command terminated by signal 4" "$file"; then
        echo "Found in: $file"
    fi
done