#!/bin/bash

# Find all index.md files in subdirectories
find . -type f -name "index.md" | while read -r file; do
    echo "Processing file: $file"

    # Comment out the first instance of "thumbnail:" in the file
    awk 'NR==1, /thumbnail:/ {if (!done && $0 ~ /^thumbnail:/) {$0="#" $0; done=1} } 1' "$file" > "$file.tmp" && mv "$file.tmp" "$file"

    echo "Updated: $file"
done

