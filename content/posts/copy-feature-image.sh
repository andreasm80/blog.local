#!/bin/bash

# Find all index.md files in subdirectories
find . -type f -name "index.md" | while read -r file; do
    echo "Processing file: $file"

    # Extract the first #thumbnail: line
    thumbnail_line=$(grep -m 1 "^#thumbnail:" "$file")

    if [ -n "$thumbnail_line" ]; then
        echo "Thumbnail line: $thumbnail_line"

        # Extract the image path and remove inline comments
        image_path=$(echo "$thumbnail_line" | sed -E 's/^#thumbnail:\s*//; s/ #.*$//')

        # Trim leading and trailing whitespace and remove leading slashes
        image_path=$(echo "$image_path" | sed 's|^/||; s|\"||g' | xargs)
        echo "Cleaned image path: $image_path"

        # Get the directory where index.md is located
        post_dir=$(dirname "$file")
        echo "Post directory: $post_dir"

        # Construct the full path to the image
        full_image_path="$post_dir/$image_path"
        echo "Full image path: $full_image_path"

        # Ensure the image file exists
        if [ -f "$full_image_path" ]; then
            # Extract the image file name and prepend "feature-"
            image_name=$(basename "$image_path")
            new_image_name="feature-$image_name"
            echo "New image name: $new_image_name"

            # Copy the file to the post directory with the new name
            cp "$full_image_path" "$post_dir/$new_image_name"
            echo "Copied: $full_image_path to $post_dir/$new_image_name"
        else
            echo "Image file not found at: $full_image_path"
        fi
    else
        echo "No #thumbnail: line found in $file"
    fi
done

