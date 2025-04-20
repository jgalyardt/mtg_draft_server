#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO." >&2' ERR

# =========================================
# prompt.sh — Generate AI prompt with filtered project context
# =========================================

# Usage: prompt.sh [options]
# Options:
#   -h, --help             Show help
#   -o, --output FILE      Set output file (default: generated_prompt.txt)
#   -c, --context FILE     Set context file (default: context.txt)
#   --no-tree              Skip printing project tree
#   --max-size N           Skip files larger than N bytes (default: 1000000)
#   --include-config       Include config/ directory

# -----------------------------------------
# Defaults
# -----------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
CONTEXT_FILE="${SCRIPT_DIR}/context.txt"
OUTPUT_FILE="${SCRIPT_DIR}/generated_prompt.txt"
PRINT_TREE=true
MAX_SIZE=1000000
INCLUDE_CONFIG=false

# -----------------------------------------
# Help
# -----------------------------------------
show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generates a filtered prompt by combining:
  1. A context file
  2. (Optional) Project tree
  3. Contents of relevant source files

Options:
  -h, --help            Show this message
  -o, --output FILE     Output file (default: generated_prompt.txt)
  -c, --context FILE    Context file (default: context.txt)
  --no-tree             Do not include project structure tree
  --max-size N          Skip files larger than N bytes (default: 1000000)
  --include-config      Include config/ directory
EOF
}

# -----------------------------------------
# Parse args
# -----------------------------------------
echo "[LOG] Parsing arguments: $@"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
    -c|--context) CONTEXT_FILE="$2"; shift 2 ;;
    --no-tree) PRINT_TREE=false; shift ;;
    --max-size) MAX_SIZE="$2"; shift 2 ;;
    --include-config) INCLUDE_CONFIG=true; shift ;;
    *) echo "Unknown option: $1"; show_help; exit 1 ;;
  esac
done

echo "[LOG] Context file: $CONTEXT_FILE"

# -----------------------------------------
# Validate context file
# -----------------------------------------
[[ -f "$CONTEXT_FILE" ]] || { echo "[ERROR] Context file not found: $CONTEXT_FILE" >&2; exit 1; }

# -----------------------------------------
# Prepare output
# -----------------------------------------
echo "[LOG] Starting prompt build: output -> $OUTPUT_FILE"
cp "$CONTEXT_FILE" "$OUTPUT_FILE"
echo >> "$OUTPUT_FILE"

# -----------------------------------------
# Optional: print project tree
# -----------------------------------------
if [[ "$PRINT_TREE" == true ]]; then
  echo "[LOG] Generating project tree"
  echo -e "\nProject Structure:" >> "$OUTPUT_FILE"
  find "$PROJECT_ROOT" \( \
      -path "*/_build" -o -path "*/deps" -o -path "*/.git" -o -path "*/node_modules" \
      -o -path "*/.elixir_ls" -o -name ".DS_Store" \
      -o -path "*/priv/static*" -o -path "*/priv/gettext*" \
  \) -prune -o -print | sed "s|^$PROJECT_ROOT/||" >> "$OUTPUT_FILE"
  echo >> "$OUTPUT_FILE"
  echo "[LOG] Tree printed"
fi

# -----------------------------------------
# Detect source files
# -----------------------------------------
echo "[LOG] Detecting source files in $PROJECT_ROOT"
if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
  echo "[LOG] Using git ls-files"
  mapfile -t files < <(git -C "$PROJECT_ROOT" ls-files)
else
  echo "[LOG] Falling back to find"
  pushd "$PROJECT_ROOT" >/dev/null
  mapfile -t files < <(find . -type f | sed 's|^\./||')
  popd >/dev/null
fi

echo "[LOG] Found ${#files[@]} files"

# -----------------------------------------
# Pre-calc total files
# -----------------------------------------
TOTAL=0
for rel in "${files[@]}"; do
  case "$rel" in
    mix.exs|lib/*|priv/*) ;;
    config/*)
      [[ "$INCLUDE_CONFIG" == true ]] || continue
      ;;
    *) continue ;;
  esac

  case "$rel" in
    priv/static/*|priv/gettext/*|*gettext.ex|*telemetry.ex) continue ;;
  esac

  if [[ -f "$PROJECT_ROOT/$rel" ]] && (( $(wc -c < "$PROJECT_ROOT/$rel") > MAX_SIZE )); then
    continue
  fi

  case "$rel" in
    *.beam|*.ez|*.png|*.jpg|*.svg|*.lock|deps/*|_build/*) continue ;;
  esac

  ((++TOTAL))
done

echo "[LOG] Eligible files: $TOTAL"

# -----------------------------------------
# Process and append files
# -----------------------------------------
echo "[LOG] Processing files..."
CURRENT=0
for rel in "${files[@]}"; do
  case "$rel" in
    mix.exs|lib/*|priv/*) ;;
    config/*)
      [[ "$INCLUDE_CONFIG" == true ]] || continue
      ;;
    *) continue ;;
  esac

  case "$rel" in
    priv/static/*|priv/gettext/*|*gettext.ex|*telemetry.ex) continue ;;
  esac

  if [[ -f "$PROJECT_ROOT/$rel" ]] && (( $(wc -c < "$PROJECT_ROOT/$rel") > MAX_SIZE )); then
    continue
  fi

  case "$rel" in
    *.beam|*.ez|*.png|*.jpg|*.svg|*.lock|deps/*|_build/*) continue ;;
  esac

  ((++CURRENT))
  printf "\rProcessing files: [%d/%d]" "$CURRENT" "$TOTAL"
  echo "[LOG] Including: $rel"

  {
    echo -e "\n=== File: $rel ===\n"
    cat "$PROJECT_ROOT/$rel"
  } >> "$OUTPUT_FILE"
done

printf "\rProcessing files: [%d/%d]\n" "$CURRENT" "$TOTAL"
echo "[LOG] Prompt generation complete: $OUTPUT_FILE"
