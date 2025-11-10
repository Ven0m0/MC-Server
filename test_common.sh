#!/bin/bash
# Simple test script to validate common.sh functions

# Source the common functions (SCRIPT_DIR is auto-initialized)
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

echo "Testing common.sh functions..."
echo ""

# Test get_total_ram_gb
ram=$(get_total_ram_gb)
echo "✓ get_total_ram_gb: $ram GB"
[[ $ram -gt 0 ]] || { echo "✗ FAILED: RAM should be > 0"; exit 1; }

# Test get_heap_size_gb
heap=$(get_heap_size_gb 2)
echo "✓ get_heap_size_gb(2): $heap GB"
[[ $heap -gt 0 ]] || { echo "✗ FAILED: Heap size should be > 0"; exit 1; }

# Test get_minecraft_memory_gb
mem=$(get_minecraft_memory_gb 3)
echo "✓ get_minecraft_memory_gb(3): $mem GB"
[[ $mem -gt 0 ]] || { echo "✗ FAILED: Memory should be > 0"; exit 1; }

# Test get_client_xms_gb
xms=$(get_client_xms_gb)
echo "✓ get_client_xms_gb: $xms GB"
[[ $xms -ge 1 ]] || { echo "✗ FAILED: XMS should be >= 1"; exit 1; }

# Test get_client_xmx_gb
xmx=$(get_client_xmx_gb)
echo "✓ get_client_xmx_gb: $xmx GB"
[[ $xmx -ge 2 ]] || { echo "✗ FAILED: XMX should be >= 2"; exit 1; }

# Test get_cpu_cores
cores=$(get_cpu_cores)
echo "✓ get_cpu_cores: $cores"
[[ $cores -gt 0 ]] || { echo "✗ FAILED: CPU cores should be > 0"; exit 1; }

# Test get_aria2c_opts
opts=$(get_aria2c_opts)
echo "✓ get_aria2c_opts: $opts"
[[ -n "$opts" ]] || { echo "✗ FAILED: aria2c opts should not be empty"; exit 1; }

# Test get_aria2c_opts_array
opts_array=($(get_aria2c_opts_array))
echo "✓ get_aria2c_opts_array: ${opts_array[*]} (${#opts_array[@]} elements)"
[[ ${#opts_array[@]} -ge 2 ]] || { echo "✗ FAILED: aria2c opts array should have at least 2 elements"; exit 1; }

# Test has_command
if has_command bash; then
    echo "✓ has_command: bash found"
else
    echo "✗ FAILED: bash should be found"
    exit 1
fi

# Test get_json_processor
json_proc=$(get_json_processor)
echo "✓ get_json_processor: $json_proc"
[[ -n "$json_proc" ]] || { echo "✗ FAILED: JSON processor should be found"; exit 1; }

# Test ensure_dir
test_dir="/tmp/mc-server-test-$$"
ensure_dir "$test_dir"
[[ -d "$test_dir" ]] || { echo "✗ FAILED: ensure_dir should create directory"; exit 1; }
echo "✓ ensure_dir: directory created"
rm -rf "$test_dir"

# Test init_strict_mode (should not error)
init_strict_mode
echo "✓ init_strict_mode: enabled"

echo ""
echo "All tests passed! ✅"
