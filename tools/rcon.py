#!/usr/bin/env python3
"""Minecraft RCON client — pure Python, no external deps."""

import os
import socket
import struct
import sys
from collections.abc import Callable
from typing import Any, Protocol


class _Readable(Protocol):
    def recv(self, n: int, /) -> bytes: ...


def _recv(sock: _Readable, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("Connection closed")
        buf += chunk
    return buf


def _packet(type_: int, payload: str, req_id: int) -> bytes:
    body = payload.encode() + b"\x00\x00"
    return struct.pack("<iii", 4 + 4 + len(body), req_id, type_) + body


def _read(sock: _Readable) -> tuple[int, str]:
    length = struct.unpack("<i", _recv(sock, 4))[0]
    data = _recv(sock, length)
    req_id = struct.unpack("<i", data[:4])[0]
    return req_id, data[8:-2].decode(errors="replace")


class RconAuthError(Exception):
    """The server rejected the RCON password."""


def rcon_command(
    host: str,
    port: str | int,
    password: str,
    command: str,
    connect: Callable[..., Any] = socket.create_connection,
) -> str:
    """Run one command; `connect` returns a socket-like context manager (fake in tests)."""
    with connect((host, int(port)), timeout=5) as s:
        s.sendall(_packet(3, password, 12))
        rid, _ = _read(s)
        if rid in (-1, 0xFFFFFFFF):
            raise RconAuthError("Authentication failed: wrong RCON password")
        s.sendall(_packet(2, command, 13))
        _, response = _read(s)
        return response


if __name__ == "__main__":
    # Connection settings come from the environment only: argv is visible to every local user in `ps`.
    host = os.environ.get("RCON_HOST", "localhost")
    port = os.environ.get("RCON_PORT", "25575")
    password = os.environ.get("RCON_PASSWORD", "")
    command = " ".join(sys.argv[1:])
    if not command:
        print(
            "Usage: rcon.py <command>  (env: RCON_HOST, RCON_PORT, RCON_PASSWORD)",
            file=sys.stderr,
        )
        sys.exit(1)
    try:
        print(rcon_command(host, port, password, command))
    except RconAuthError as e:
        print(e, file=sys.stderr)
        sys.exit(1)
