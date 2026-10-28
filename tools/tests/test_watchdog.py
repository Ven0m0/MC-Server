#!/usr/bin/env python3
"""Unit tests for the watchdog RestartPolicy (no server needed)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from watchdog import RestartPolicy


def test_cap_blocks_after_max_attempts():
    p = RestartPolicy(2)
    assert [p.allow(), p.allow(), p.allow()] == [True, True, False]


def test_reset_reopens_the_cap():
    p = RestartPolicy(1)
    assert p.allow()
    assert not p.allow()
    p.reset()
    assert p.allow()


tests = [test_cap_blocks_after_max_attempts, test_reset_reopens_the_cap]
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
