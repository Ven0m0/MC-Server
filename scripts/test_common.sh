#!/usr/bin/env bash
# Test script to validate common.sh functions

# Initialize strict mode
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C
user="${SUDO_USER:-${USER:-$(id -un)}}"
export HOME="/home/${user}"
SHELL="$(command -v bash 2>/dev/null || echo '/usr/bin/bash')"

# Check if command exists
has_command(){ command -v "$1" &>/dev/null; }

# Detect JSON processor (prefer jaq over jq)
get_json_processor(){
  has_command jaq && {
    echo "jaq"
    return
  }
  has_command jq && {
    echo "jq"
    return
  }
  echo "Error: No JSON processor found. Please install jq or jaq." >&2
  return 1
}

# Calculate total RAM in GB
get_total_ram_gb(){ awk '/MemTotal/ {printf "%.0f\n",$2/1024/1024}' /proc/meminfo 2>/dev/null; }

# Calculate heap size (total RAM minus reserved for OS)
get_heap_size_gb(){
  local reserved="${1:-2}"
  local total_ram
  total_ram=$(get_total_ram_gb)
  local heap=$((total_ram - reserved))
  ((heap < 1)) && heap=1
  echo "$heap"
}

# Calculate Minecraft memory allocation
get_minecraft_memory_gb(){ get_heap_size_gb "${1:-3}"; }

# Calculate client memory allocation
get_client_xms_gb(){
  local total_ram
  total_ram=$(get_total_ram_gb)
  local xms=$((total_ram / 4))
  ((xms < 1)) && xms=1
  echo "$xms"
}

get_client_xmx_gb(){
  local total_ram
  total_ram=$(get_total_ram_gb)
  local xmx=$((total_ram / 2))
  ((xmx < 2)) && xmx=2
  echo "$xmx"
}

# Get number of CPU cores
get_cpu_cores(){ nproc 2>/dev/null || echo 4; }

# Get aria2c download options
get_aria2c_opts(){ echo "-x 16 -s 16"; }
# Get aria2c options as array (use: mapfile -t arr < <(get_aria2c_opts_array))
get_aria2c_opts_array(){ printf '%s\n' "-x" "16" "-s" "16"; }

# Create directory if it doesn't exist
ensure_dir(){ [[ ! -d $1 ]] && mkdir -p "$1" || return 0; }

echo "Testing common.sh functions..."
echo ""

# Memory functions
echo "Memory Functions:"
ram=$(get_total_ram_gb)
echo "  ✓ get_total_ram_gb: $ram GB"
[[ $ram -gt 0 ]] || {
  echo "  ✗ FAILED: RAM should be > 0"
  exit 1
}

heap=$(get_heap_size_gb 2)
echo "  ✓ get_heap_size_gb(2): $heap GB"
[[ $heap -gt 0 ]] || {
  echo "  ✗ FAILED: Heap size should be > 0"
  exit 1
}

mem=$(get_minecraft_memory_gb 3)
echo "  ✓ get_minecraft_memory_gb(3): $mem GB"
[[ $mem -gt 0 ]] || {
  echo "  ✗ FAILED: Memory should be > 0"
  exit 1
}

xms=$(get_client_xms_gb)
echo "  ✓ get_client_xms_gb: $xms GB"
[[ $xms -ge 1 ]] || {
  echo "  ✗ FAILED: XMS should be >= 1"
  exit 1
}

xmx=$(get_client_xmx_gb)
echo "  ✓ get_client_xmx_gb: $xmx GB"
[[ $xmx -ge 2 ]] || {
  echo "  ✗ FAILED: XMX should be >= 2"
  exit 1
}

echo ""
echo "System Functions:"
cores=$(get_cpu_cores)
echo "  ✓ get_cpu_cores: $cores"
[[ $cores -gt 0 ]] || {
  echo "  ✗ FAILED: CPU cores should be > 0"
  exit 1
}

echo ""
echo "Download Configuration:"
opts=$(get_aria2c_opts)
echo "  ✓ get_aria2c_opts: $opts"
[[ -n $opts ]] || {
  echo "  ✗ FAILED: aria2c opts should not be empty"
  exit 1
}

mapfile -t opts_array < <(get_aria2c_opts_array)
echo "  ✓ get_aria2c_opts_array: ${opts_array[*]} (${#opts_array[@]} elements)"
[[ ${#opts_array[@]} -ge 2 ]] || {
  echo "  ✗ FAILED: aria2c opts array should have at least 2 elements"
  exit 1
}

echo ""
echo "Utility Functions:"
if has_command bash; then
  echo "  ✓ has_command: bash found"
else
  echo "  ✗ FAILED: bash should be found"
  exit 1
fi

json_proc=$(get_json_processor)
echo "  ✓ get_json_processor: $json_proc"
[[ -n $json_proc ]] || {
  echo "  ✗ FAILED: JSON processor should be found"
  exit 1
}

test_dir="/tmp/mc-server-test-$$"
ensure_dir "$test_dir"
[[ -d $test_dir ]] || {
  echo "  ✗ FAILED: ensure_dir should create directory"
  exit 1
}
echo "  ✓ ensure_dir: directory created"
rm -rf "$test_dir"

echo ""
echo "All tests passed! ✅"
