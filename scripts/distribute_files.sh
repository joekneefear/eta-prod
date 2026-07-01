#!/bin/bash

# Check passed arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <source directory> <filename>"
    exit 1
elif [ $# -eq 1 ]; then
	echo "Usage: $0 <source directory> <filename>"
	exit 1
fi

src_dir="$1"
dir_list="$2"

# Check if source directory exists
if [ -d "$src_dir" ]; then
    echo "Source directory exists: $src_dir"
else
    echo "Source directory does not exists: $src_dir"
    exit 1
fi

# Check if the file exists
if [ ! -f "$dir_list" ]; then
    echo "List of destination directory not found: $dir_list"
    exit 1
else
    echo "List of destination directory found: $dir_list"
fi

# Read lines into an array
mapfile -t dest_dirs < "$dir_list"

# Create destination directories if they don't exist
for dir in "${dest_dirs[@]}"; do
    mkdir -p "$dir"
done

# Read files into an array safely (handles spaces)
files=()
while IFS= read -r -d '' file; do
    files+=("$file")
done < <(find "$src_dir" -maxdepth 1 -type f -print0)

# Total number of files
total_files=${#files[@]}
num_dirs=${#dest_dirs[@]}

# Calculate how many files per directory
files_per_dir=$((total_files / num_dirs))
remainder=$((total_files % num_dirs))

# Move files
file_index=0
for ((i = 0; i < num_dirs; i++)); do
    count=$files_per_dir
    if ((i < remainder)); then
        count=$((count + 1))
    fi

    for ((j = 0; j < count; j++)); do
        mv "${files[$file_index]}" "${dest_dirs[$i]}"
        ((file_index++))
    done
done

echo "Moved $total_files files into ${num_dirs} directories."
