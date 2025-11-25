#!/bin/bash

# Script to analyze which Terraform directories contain changes
# Usage: ./analyze_tofu_directories.sh "file1,file2,file3"

set -e

CHANGED_TOFU_FILES_INPUT="$1"

if [ -z "$CHANGED_TOFU_FILES_INPUT" ]; then
    echo "No Terraform files provided for analysis"
    echo "tofu-directories=" >> "$GITHUB_OUTPUT"
    exit 0
fi

IFS=',' read -ra CHANGED_TOFU_FILES_ARRAY <<< "$CHANGED_TOFU_FILES_INPUT"

echo "🔍 Analyzing which Terraform directories contain changes..."

declare -A UNIQUE_DIRS_MAP
UNIQUE_DIRS=()

for file in "${CHANGED_TOFU_FILES_ARRAY[@]}"; do
    trimmed_file=$(echo "$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -f "$trimmed_file" ]; then
        logical_dir=$(dirname "$trimmed_file")

        if [[ -z "${UNIQUE_DIRS_MAP[$logical_dir]}" ]]; then
            UNIQUE_DIRS_MAP[$logical_dir]=1
            UNIQUE_DIRS+=("$logical_dir")
        fi
    fi
done

echo "Detected Terraform directories with changes:"
for dir in "${UNIQUE_DIRS[@]}"; do
    echo "  📁 $dir"
done

CHANGED_DIRS=""
for dir in "${UNIQUE_DIRS[@]}"; do
    if [ -z "$CHANGED_DIRS" ]; then
        CHANGED_DIRS="$dir"
    else
        CHANGED_DIRS="$CHANGED_DIRS,$dir"
    fi
done

echo "tofu-directories=$CHANGED_DIRS" >> "$GITHUB_OUTPUT"
