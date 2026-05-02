#!/usr/bin/env bash
# shellcheck disable=all
set -euo pipefail

# Source test utilities
source "tools/tests/test_utils.sh"

# Source the script under test
source "tools/rcon.sh"

# Redefine xxd-dependent mocks to override rcon.sh versions
# This is necessary because xxd might not be available in the environment
stream_to_hex() {
  python3 -c 'import sys; print(sys.stdin.buffer.read().hex(), end="")'
}

hex_to_stream() {
  python3 -c 'import sys; sys.stdout.buffer.write(bytes.fromhex(sys.stdin.read().strip()))'
}

test_reverse_hex_endian() {
  local result
  result=$(printf '01020304' | reverse_hex_endian)
  assert_equals "04030201" "$result" "Should reverse 4-byte hex string"
}

test_decode_hex_int() {
  local result
  # 0x0000000a in little-endian hex is 0a000000
  result=$(printf '0a000000' | decode_hex_int)
  assert_equals "10" "$result" "Should decode little-endian hex 0a000000 to 10"

  result=$(printf 'ff000000' | decode_hex_int)
  assert_equals "255" "$result" "Should decode little-endian hex ff000000 to 255"
}

test_encode_int() {
  local result
  result=$(encode_int 10)
  assert_equals "0a000000" "$result" "Should encode 10 to little-endian hex 0a000000"

  result=$(encode_int 255)
  assert_equals "ff000000" "$result" "Should encode 255 to little-endian hex ff000000"
}

test_resp_request_id() {
  local result
  # Request ID is first 4 bytes (8 hex chars)
  # 0d000000 is 13
  result=$(resp_request_id "0d0000000200000068656c6c6f0000")
  assert_equals "13" "$result" "Should extract request ID 13"
}

test_resp_payload() {
  local result
  # Payload starts at byte 8 (hex char 16), ends 2 bytes from end (hex char -4)
  # 68656c6c6f is "hello"
  result=$(resp_payload "0d0000000200000068656c6c6f0000")
  assert_equals "hello" "$result" "Should extract payload 'hello'"
}

test_encode_packet() {
  local result_hex
  # type=2 (COMMAND), payload="test", request_id=13
  # plen = 4, total = 4 + 4 + 4 + 1 + 1 = 14 (0e000000)
  # request_id = 13 (0d000000)
  # type = 2 (02000000)
  # payload = "test" (74657374)
  # suffix = 0000
  # Expected hex: 0e0000000d00000002000000746573740000
  result_hex=$(encode_packet 2 "test" 13 | stream_to_hex)
  assert_equals "0e0000000d00000002000000746573740000" "$result_hex" "Should encode RCON packet correctly"
}

# Run tests
errors=0
run_test test_reverse_hex_endian || errors=$((errors + 1))
run_test test_decode_hex_int || errors=$((errors + 1))
run_test test_encode_int || errors=$((errors + 1))
run_test test_resp_request_id || errors=$((errors + 1))
run_test test_resp_payload || errors=$((errors + 1))
run_test test_encode_packet || errors=$((errors + 1))

if [ "$errors" -eq 0 ]; then
  printf '\033[0;32mAll tests passed!\033[0m\n'
  exit 0
else
  printf '\033[0;31m%d tests failed.\033[0m\n' "$errors"
  exit 1
fi
