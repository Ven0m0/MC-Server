#!/usr/bin/env bash
# Config Format/Lint/Autofix Script
# Formats and minifies JSON, YAML, and other configuration files
# Inspired by https://github.com/Ven0m0/Linux-OS/blob/main/Cachyos/Scripts/other/minify.sh

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default options
MODE="format" # format, minify, or check
PARALLEL_JOBS=4
VERBOSE=false
DRY_RUN=false

# Directories to exclude from processing
readonly EXCLUDE_DIRS=(
  ".git"
  "node_modules"
  "dist"
  "build"
  "__pycache__"
  ".venv"
  "vendor"
  "target"
  ".gradle"
)

# Files to exclude (already minified or generated)
readonly EXCLUDE_PATTERNS=(
  "*.min.json"
  "*.min.yml"
  "*.min.yaml"
  "*-lock.json"
  "package-lock.json"
  "yarn.lock"
)

# Statistics
declare -i PROCESSED_FILES=0
declare -i FAILED_FILES=0
declare -i TOTAL_SIZE_BEFORE=0
declare -i TOTAL_SIZE_AFTER=0

#######################################
# Print colored message
# Arguments:
#   $1 - Color code
#   $2 - Message
#######################################
print_msg(){
  printf '%b' "${1}${2}${NC}\n"
}

#######################################
# Print error and exit
# Arguments:
#   $1 - Error message
#######################################
error_exit(){
  print_msg "$RED" "ERROR: $1" >&2
  exit 1
}

#######################################
# Check if command exists
# Arguments:
#   $1 - Command name
# Returns:
#   0 if exists, 1 otherwise
#######################################
command_exists(){
  command -v "$1" &>/dev/null
}

#######################################
# Check required dependencies
#######################################
check_dependencies(){
  local missing_deps=()

  # Check for jq (required for JSON)
  if ! command_exists jq; then
    missing_deps+=("jq")
  fi

  # Optional but recommended tools
  if [[ -n ${missing_deps[*]} ]]; then
    error_exit "Missing required dependencies: ${missing_deps[*]}\nPlease install them and try again."
  fi

  # Check for optional tools
  if ! command_exists yamlfmt; then
    if command_exists yq; then
      if ! yq --version 2>&1 | grep -q "mikefarah"; then
        print_msg "$YELLOW" "Warning: Found old Python-based yq. Install mikefarah/yq or yamlfmt for YAML formatting."
      fi
    else
      print_msg "$YELLOW" "Warning: Neither 'yq' nor 'yamlfmt' found. YAML formatting will be skipped."
    fi
  fi

  if ! command_exists parallel && ! command_exists rust-parallel; then
    print_msg "$YELLOW" "Warning: No parallel processing tool found. Will use sequential processing."
  fi
}

#######################################
# Build find exclusion arguments
# Returns:
#   Array of find arguments to exclude directories and patterns
#######################################
build_exclusions(){
  local -a exclusions=()

  # Exclude directories
  for dir in "${EXCLUDE_DIRS[@]}"; do
    exclusions+=(-path "*/${dir}/*" -prune -o)
  done

  # Exclude file patterns
  for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    exclusions+=(-name "$pattern" -prune -o)
  done

  echo "${exclusions[@]}"
}

#######################################
# Get file size in bytes
# Arguments:
#   $1 - File path
# Returns:
#   File size in bytes
#######################################
get_file_size(){
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0
}

#######################################
# Format JSON file with jq
# Arguments:
#   $1 - File path
# Returns:
#   0 on success, 1 on failure
#######################################
format_json(){
  local file="$1"
  local temp_file="${file}.tmp"

  if [[ ${DRY_RUN} == true ]]; then
    if jq empty "$file" 2>/dev/null; then
      print_msg "$BLUE" "[DRY RUN] Would format: ${file}"
      return 0
    else
      print_msg "$RED" "[DRY RUN] Invalid JSON: ${file}"
      return 1
    fi
  fi

  local size_before
  size_before=$(get_file_size "$file")

  # Validate and format based on mode
  if [[ ${MODE} == "minify" ]]; then
    # Minify: remove whitespace
    if jq -c . "$file" >"$temp_file" 2>/dev/null; then
      mv "$temp_file" "$file"
      local size_after
      size_after=$(get_file_size "$file")
      TOTAL_SIZE_BEFORE=$((TOTAL_SIZE_BEFORE + size_before))
      TOTAL_SIZE_AFTER=$((TOTAL_SIZE_AFTER + size_after))
      print_msg "$GREEN" "✓ Minified: ${file} (${size_before}B → ${size_after}B)"
      return 0
    fi
  elif [[ ${MODE} == "check" ]]; then
    # Check only: validate JSON
    if jq empty "$file" 2>/dev/null; then
      # Check if formatted correctly (2-space indent)
      if jq --indent 2 . "$file" | diff -q - "$file" &>/dev/null; then
        print_msg "$GREEN" "✓ Valid: ${file}"
        return 0
      else
        print_msg "$YELLOW" "⚠ Needs formatting: ${file}"
        return 1
      fi
    fi
  else
    # Format: pretty print with 2-space indent
    if jq --indent 2 . "$file" >"$temp_file" 2>/dev/null; then
      mv "$temp_file" "$file"
      local size_after
      size_after=$(get_file_size "$file")
      print_msg "$GREEN" "✓ Formatted: ${file}"
      return 0
    fi
  fi

  # If we got here, something failed
  rm -f "$temp_file"
  print_msg "$RED" "✗ Failed: ${file}"
  return 1
}

#######################################
# Format YAML file
# Arguments:
#   $1 - File path
# Returns:
#   0 on success, 1 on failure
#######################################
format_yaml(){
  local file="$1"
  local temp_file="${file}.tmp"

  if [[ ${DRY_RUN} == true ]]; then
    print_msg "$BLUE" "[DRY RUN] Would format: ${file}"
    return 0
  fi

  local size_before
  size_before=$(get_file_size "$file")

  # Try yamlfmt first (best formatter)
  if command_exists yamlfmt; then
    if [[ ${MODE} == "check" ]]; then
      if yamlfmt -lint "$file" 2>/dev/null; then
        print_msg "$GREEN" "✓ Valid: ${file}"
        return 0
      else
        print_msg "$YELLOW" "⚠ Needs formatting: ${file}"
        return 1
      fi
    else
      if yamlfmt "$file" 2>/dev/null; then
        local size_after
        size_after=$(get_file_size "$file")
        print_msg "$GREEN" "✓ Formatted: ${file}"
        return 0
      fi
    fi
  # Try yq as fallback (check if it's mikefarah/yq, not python yq)
  elif command_exists yq && yq --version 2>&1 | grep -q "mikefarah"; then
    if [[ ${MODE} == "check" ]]; then
      if yq eval . "$file" >/dev/null 2>&1; then
        print_msg "$GREEN" "✓ Valid: ${file}"
        return 0
      else
        print_msg "$RED" "✗ Invalid YAML: ${file}"
        return 1
      fi
    else
      if yq eval . "$file" >"$temp_file" 2>/dev/null; then
        mv "$temp_file" "$file"
        print_msg "$GREEN" "✓ Formatted: ${file}"
        return 0
      fi
    fi
  else
    # No proper YAML formatter available, skip silently in format mode
    if [[ ${MODE} == "check" ]]; then
      print_msg "$YELLOW" "⚠ Skipped (no YAML formatter): ${file}"
    fi
    return 0
  fi

  # If we got here, something failed
  rm -f "$temp_file"
  print_msg "$RED" "✗ Failed: ${file}"
  return 1
}

#######################################
# Process a single file
# Arguments:
#   $1 - File path
#######################################
process_file(){
  local file="$1"

  [[ ${VERBOSE} == true ]] && print_msg "$BLUE" "Processing: ${file}"

  case "$file" in
    *.json)
      if format_json "$file"; then
        ((PROCESSED_FILES++)) || true
      else
        ((FAILED_FILES++)) || true
      fi
      ;;
    *.yaml | *.yml)
      if format_yaml "$file"; then
        ((PROCESSED_FILES++)) || true
      else
        ((FAILED_FILES++)) || true
      fi
      ;;
    *)
      [[ ${VERBOSE} == true ]] && print_msg "$YELLOW" "Skipped (unknown type): ${file}"
      ;;
  esac
}

#######################################
# Find and process all config files
# Arguments:
#   $1 - Target directory (optional, defaults to PROJECT_ROOT)
#######################################
process_directory(){
  local target_dir="${1:-${PROJECT_ROOT}}"

  print_msg "$BLUE" "Processing config files in: ${target_dir}"
  print_msg "$BLUE" "Mode: ${MODE}"

  # Build find command with exclusions
  local -a find_cmd=(find "$target_dir")
  local exclusions
  read -ra exclusions <<<"$(build_exclusions)"
  find_cmd+=("${exclusions[@]}")

  # Find JSON and YAML files
  find_cmd+=(\( -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) -type f -print)

  # Get list of files
  local -a files
  mapfile -t files < <("${find_cmd[@]}")

  if [[ ${#files[@]} -eq 0 ]]; then
    print_msg "$YELLOW" "No config files found."
    return 0
  fi

  print_msg "$BLUE" "Found ${#files[@]} config file(s)"

  # Process files (with or without parallelization)
  if command_exists parallel && [[ ${#files[@]} -gt 3 ]]; then
    # GNU parallel
    printf '%s\n' "${files[@]}" | parallel -j "$PARALLEL_JOBS" "$(declare -f process_file format_json format_yaml get_file_size print_msg); $(declare -p MODE DRY_RUN VERBOSE GREEN RED YELLOW BLUE NC); process_file {}"
    # Note: parallel processing doesn't update counters in parent shell
    PROCESSED_FILES=${#files[@]}
  elif command_exists rust-parallel && [[ ${#files[@]} -gt 3 ]]; then
    # Rust parallel
    printf '%s\n' "${files[@]}" | rust-parallel -j "$PARALLEL_JOBS" bash -c "$(declare -f process_file format_json format_yaml get_file_size print_msg); $(declare -p MODE DRY_RUN VERBOSE GREEN RED YELLOW BLUE NC); process_file {}"
    PROCESSED_FILES=${#files[@]}
  else
    # Sequential processing
    for file in "${files[@]}"; do
      process_file "$file"
    done
  fi
}

#######################################
# Print usage information
#######################################
usage(){
  cat <<EOF
Config Format/Lint/Autofix Script

Usage: $(basename "$0") [OPTIONS] [DIRECTORY]

OPTIONS:
    -m, --mode MODE       Operation mode: format, minify, or check (default: format)
    -j, --jobs N          Number of parallel jobs (default: 4)
    -v, --verbose         Enable verbose output
    -n, --dry-run         Show what would be done without making changes
    -h, --help            Show this help message

MODES:
    format                Format files with proper indentation (default)
    minify                Minify files by removing unnecessary whitespace
    check                 Check if files are properly formatted (CI mode)

EXAMPLES:
    $(basename "$0")                          # Format all configs in project
    $(basename "$0") -m check                 # Check formatting (for CI)
    $(basename "$0") -m minify config/        # Minify configs in config/
    $(basename "$0") -n -v                    # Dry run with verbose output

DEPENDENCIES:
    Required: jq
    Optional: yq, yamlfmt, parallel, rust-parallel

EOF
}

#######################################
# Parse command line arguments
#######################################
parse_args(){
  while [[ $# -gt 0 ]]; do
    case $1 in
      -m | --mode)
        MODE="$2"
        if [[ ! ${MODE} =~ ^(format|minify|check)$ ]]; then
          error_exit "Invalid mode: ${MODE}. Must be 'format', 'minify', or 'check'"
        fi
        shift 2
        ;;
      -j | --jobs)
        PARALLEL_JOBS="$2"
        shift 2
        ;;
      -v | --verbose)
        VERBOSE=true
        shift
        ;;
      -n | --dry-run)
        DRY_RUN=true
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -*)
        error_exit "Unknown option: $1"
        ;;
      *)
        # Assume it's a directory
        if [[ -d $1 ]]; then
          TARGET_DIR="$1"
        else
          error_exit "Directory not found: $1"
        fi
        shift
        ;;
    esac
  done
}

#######################################
# Print summary statistics
#######################################
print_summary(){
  echo
  print_msg "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print_msg "$BLUE" "Summary"
  print_msg "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print_msg "$GREEN" "Processed: ${PROCESSED_FILES} file(s)"

  if [[ ${FAILED_FILES} -gt 0 ]]; then
    print_msg "$RED" "Failed: ${FAILED_FILES} file(s)"
  fi

  if [[ ${MODE} == "minify" && ${TOTAL_SIZE_BEFORE} -gt 0 ]]; then
    local saved=$((TOTAL_SIZE_BEFORE - TOTAL_SIZE_AFTER))
    local percent=$((saved * 100 / TOTAL_SIZE_BEFORE))
    print_msg "$GREEN" "Size before: ${TOTAL_SIZE_BEFORE} bytes"
    print_msg "$GREEN" "Size after: ${TOTAL_SIZE_AFTER} bytes"
    print_msg "$GREEN" "Saved: ${saved} bytes (${percent}%)"
  fi

  print_msg "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

#######################################
# Main function
#######################################
main(){
  local TARGET_DIR="$PROJECT_ROOT"

  parse_args "$@"

  print_msg "$GREEN" "Config Format/Lint/Autofix Script"
  echo

  check_dependencies

  process_directory "$TARGET_DIR"

  print_summary

  # Exit with error code if in check mode and files need formatting
  if [[ ${MODE} == "check" && ${FAILED_FILES} -gt 0 ]]; then
    exit 1
  fi

  # Exit with error code if any files failed to process
  if [[ ${FAILED_FILES} -gt 0 ]]; then
    exit 1
  fi
}

# Run main function if script is executed directly
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  main "$@"
fi
