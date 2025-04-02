#!/bin/bash

# Show usage information
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generates a comprehensive prompt file by combining:
1. Context from a context file
2. Project directory structure (excluding irrelevant directories/files)
3. Contents of all relevant source files

The generated prompt will be saved as 'generated_prompt.txt' by default.

Options:
    -h, --help              Show this help message
    -o, --output FILE       Specify output file (default: generated_prompt.txt)
    -c, --context FILE      Specify context file (default: context.txt)
    --no-stats              Skip generation statistics
    --max-file-size SIZE   Skip files larger than SIZE in bytes (default: 1000000)

Examples:
    $(basename "$0")                    # Generate using defaults
    $(basename "$0") -o custom.txt      # Save output to custom.txt
    $(basename "$0") -c my_context.txt  # Use different context file
EOF
}

# Built-in tree function to replace the external tree command
print_tree() {
    local dir="${1:-.}"
    local prefix="${2}"
    # Expanded excluded patterns to ignore extra irrelevant files (e.g. .DS_Store, coverage, image files)
    local excluded="${3:-node_modules|_build|deps|.git|*.beam|*.ez|ai|.DS_Store|coverage|*.lock|*.ico|*.svg|*.png|*.jpg}"

    # List items excluding hidden files and matching excluded patterns
    local items=($(ls -A "$dir" 2>/dev/null | grep -Ev "$excluded" | sort))
    local total=${#items[@]}

    local i
    for ((i=0; i<$total; i++)); do
        local item="${items[$i]}"
        local path="$dir/$item"
        local is_last=$((i == total-1))

        if [ $is_last -eq 1 ]; then
            echo "${prefix}└── $item"
            new_prefix="${prefix}    "
        else
            echo "${prefix}├── $item"
            new_prefix="${prefix}│   "
        fi

        if [ -d "$path" ]; then
            print_tree "$path" "$new_prefix" "$excluded"
        fi
    done
}

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -W)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -W)"
CONTEXT_FILE="$SCRIPT_DIR/context.txt"
OUTPUT_FILE="$SCRIPT_DIR/generated_prompt.txt"
INCLUDE_STATS=true
MAX_FILE_SIZE=1000000

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -c|--context)
            CONTEXT_FILE="$2"
            shift 2
            ;;
        --no-stats)
            INCLUDE_STATS=false
            shift
            ;;
        --max-file-size)
            MAX_FILE_SIZE="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option $1"
            show_help
            exit 1
            ;;
    esac
done

# Verify context file exists
if [ ! -f "$CONTEXT_FILE" ]; then
    echo "Error: Context file not found: $CONTEXT_FILE"
    echo "Create the file or specify a different one with -c option"
    exit 1
fi

# Print initial directory information
echo "Script running from: $SCRIPT_DIR"
echo "Project root: $PROJECT_ROOT"
echo

# Create or clear the output file by copying the context
cp "$CONTEXT_FILE" "$OUTPUT_FILE"

# Uncomment if you want to include the project structure tree in the prompt:
# echo -e "\n\nProject Structure:\n" >> "$OUTPUT_FILE"
# print_tree "$PROJECT_ROOT" "" 'node_modules|_build|deps|.git|*.beam|*.ez|ai|.DS_Store|coverage|*.lock|*.ico|*.svg|*.png|*.jpg' >> "$OUTPUT_FILE"

# Function to decide if a file path should be processed (only include mix.exs, lib/, or priv/)
should_process_path() {
    local path="$1"
    local rel_path="${path#$PROJECT_ROOT/}"

    if [[ "$rel_path" == "mix.exs" ]] || [[ "$rel_path" == lib/* ]] || [[ "$rel_path" == priv/* ]]; then
        return 0
    fi
    return 1
}

# Function to decide if a file should be included
should_include_file() {
    local file="$1"

    # Ignore directories
    if [ -d "$file" ]; then
        return 1
    fi

    # Exclude files based on patterns (hidden files, build artifacts, images, etc.)
    case "$file" in
        *node_modules*|*_build*|*deps*|*.git*|*.beam|*.ez|*ai*|*.ico|*.svg|*.lock|*.heex|.*|*coverage*)
            return 1
            ;;
    esac

    # Check file size
    local size
    size=$(stat --format=%s "$file" 2>/dev/null)
    if [ $? -eq 0 ] && [ "$size" -gt "$MAX_FILE_SIZE" ]; then
        echo "Skipping large file: $file ($size bytes)"
        return 1
    fi

    # Check if file is binary
    if file "$file" | grep -q "binary"; then
        return 1
    fi

    return 0
}

# Function to process and append a file's content to the output file
process_file() {
    local file="$1"
    local rel_path="${file#$PROJECT_ROOT/}"
    
    if should_include_file "$file"; then
        echo -e "\n=== File: $rel_path ===\n" >> "$OUTPUT_FILE"
        cat "$file" >> "$OUTPUT_FILE"
    fi
}

# Simple progress counter
print_progress() {
    local current=$1
    local total=$2
    printf "\rProcessing files: [%d/%d]" "$current" "$total"
}

# Count total files to process (only from mix.exs, lib/, and priv/ directories)
total_files=$(find "$PROJECT_ROOT" \( -name "mix.exs" -o -path "*/lib/*" -o -path "*/priv/*" \) \
    -type f ! -path "*/deps/*" ! -path "*/_build/*" ! -path "*/node_modules/*" ! -path "*/.git/*" | wc -l)
current_file=0

echo "Starting file processing from $(dirname "$PROJECT_ROOT")..."
echo "Including: mix.exs, lib/, and priv/ directories"

# Process each file found
while IFS= read -r file; do
    if should_process_path "$file"; then
        ((current_file++))
        print_progress "$current_file" "$total_files"
        process_file "$file"
    fi
done < <(find "$PROJECT_ROOT" \( -name "mix.exs" -o -path "*/lib/*" -o -path "*/priv/*" \) \
    -type f ! -path "*/deps/*" ! -path "*/_build/*" ! -path "*/node_modules/*" ! -path "*/.git/*")

printf "\rFile processing completed! Processed %d files.\n" "$total_files"
echo "Prompt has been generated in $OUTPUT_FILE"
