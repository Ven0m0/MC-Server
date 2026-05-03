#!/usr/bin/env bash
# Unit tests for tools/rcon.sh

# Source the rcon.sh script
# Since we wrapped the main execution call, it should only load functions
source "$(dirname "$0")/../rcon.sh"

# Test counter
tests_run=0
tests_failed=0

# Assertion function
assert_equals() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  ((tests_run++))
  if [[ "$expected" == "$actual" ]]; then
    printf "\e[32m[PASS]\e[0m %s\n" "$description"
  else
    printf "\e[31m[FAIL]\e[0m %s\n" "$description"
    printf "       Expected: '%s'\n" "$expected"
    printf "       Actual:   '%s'\n" "$actual"
    ((tests_failed++))
  fi
}

# ----------------------------------------------------------------------------
# Tests for reverse_hex_endian
# ----------------------------------------------------------------------------
printf "Running tests for reverse_hex_endian...\n"

# Standard 8-character hex
result=$(printf "01020304" | reverse_hex_endian)
assert_equals "04030201" "$result" "Standard 8-character hex reversal"

# Multiple 8-character blocks
result=$(printf "1234567801020304" | reverse_hex_endian)
assert_equals "7856341204030201" "$result" "Multiple 8-character blocks reversal"

# Short input (< 8 chars)
# Fixed implementation should return short input as-is instead of swallowing it.
result=$(printf "1234" | reverse_hex_endian)
assert_equals "1234" "$result" "Short input without 8 characters is returned as-is"

# ----------------------------------------------------------------------------
# Tests for decode_hex_int
# ----------------------------------------------------------------------------
printf "\nRunning tests for decode_hex_int...\n"

result=$(printf "01000000" | decode_hex_int)
assert_equals "1" "$result" "Decode 01000000 to 1"

result=$(printf "00010000" | decode_hex_int)
assert_equals "256" "$result" "Decode 00010000 to 256"

# ----------------------------------------------------------------------------
# Tests for encode_int
# ----------------------------------------------------------------------------
printf "\nRunning tests for encode_int...\n"

result=$(encode_int 1)
assert_equals "01000000" "$result" "Encode 1 to 01000000"

result=$(encode_int 256)
assert_equals "00010000" "$result" "Encode 256 to 00010000"

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
printf "\nTests completed: %d, Failed: %d\n" "$tests_run" "$tests_failed"

if [[ "$tests_failed" -eq 0 ]]; then
  exit 0
else
  exit 1
fi
