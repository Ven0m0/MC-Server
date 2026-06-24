#!/usr/bin/env python3
"""Unit tests for rcon.py packet encoding/decoding (no server needed)."""

import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from rcon import _packet, _read


class FakeSocket:
    def __init__(self, data: bytes) -> None:
        self._buf = data

    def recv(self, n: int) -> bytes:
        chunk, self._buf = self._buf[:n], self._buf[n:]
        return chunk


def test_packet_roundtrip():
    pkt = _packet(2, "say hello", 13)
    # Length field is first 4 bytes LE
    length = struct.unpack("<i", pkt[:4])[0]
    assert length == len(pkt) - 4, f"bad length: {length}"
    req_id, type_ = struct.unpack("<ii", pkt[4:12])
    assert req_id == 13
    assert type_ == 2
    payload = pkt[12:-2]
    assert payload == b"say hello"


def test_read_roundtrip():
    # Build a fake response packet
    body = b"\x0d\x00\x00\x00" + b"\x00\x00\x00\x00" + b"pong" + b"\x00\x00"
    length_prefix = struct.pack("<i", len(body))
    sock = FakeSocket(length_prefix + body)
    rid, text = _read(sock)
    assert rid == 13, f"req_id: {rid}"
    assert text == "pong", f"payload: {text!r}"


def test_encode_int_little_endian():
    pkt = _packet(3, "", 1)
    req_id = struct.unpack("<i", pkt[4:8])[0]
    assert req_id == 1


def test_auth_failure_detection():
    body = struct.pack("<ii", -1, 2) + b"\x00\x00"
    length_prefix = struct.pack("<i", len(body))
    sock = FakeSocket(length_prefix + body)
    rid, _ = _read(sock)
    assert rid in (-1, 0xFFFFFFFF), f"expected -1 or 0xFFFFFFFF, got {rid}"


tests = [
    test_packet_roundtrip,
    test_read_roundtrip,
    test_encode_int_little_endian,
    test_auth_failure_detection,
]
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
