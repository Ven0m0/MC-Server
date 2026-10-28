#!/usr/bin/env python3
"""Unit tests for common.py process detection (no server needed)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from common import find_server_pids


def test_pids_from_both_patterns_deduplicated():
    out = {"fabric-server-launch.jar": "10\n11\n", "server.jar": "11\n12\n"}
    assert find_server_pids(lambda pat: out[pat]) == [10, 11, 12]


def test_no_match_means_no_pids():
    assert find_server_pids(lambda _pat: "") == []


tests = [test_pids_from_both_patterns_deduplicated, test_no_match_means_no_pids]
failed = 0
for t in tests:
    try:
        t()
        print(f"\033[0;32m✓\033[0m {t.__name__}")
    except AssertionError as e:
        print(f"\033[0;31m✗\033[0m {t.__name__}: {e}")
        failed += 1

print(f"\nTests: {len(tests)}, Failed: {failed}")
sys.exit(failed)
