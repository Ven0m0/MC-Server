#!/usr/bin/env bash
# Simple test utility for Bash scripts

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Expected '$expected' but got '$actual'}"

  if [[ "$expected" == "$actual" ]]; then
    printf '  \033[0;32mPASS\033[0m\n'
    return 0
  else
    printf '  \033[0;31mFAIL: %s\033[0m\n' "$message"
    return 1
  fi
}

run_test() {
  local test_name="$1"
  printf 'Running %s... ' "$test_name"
  if "$test_name"; then
    return 0
  else
    return 1
  fi
}
