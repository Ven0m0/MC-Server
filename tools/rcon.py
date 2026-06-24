#!/usr/bin/env python3
"""Minecraft RCON client — pure Python, no external deps."""

import os
import socket
import struct
import sys
from typing import Protocol


class _Readable(Protocol):
    def recv(self, __n: int) -> bytes: ...


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


def rcon_command(host: str, port: str | int, password: str, command: str) -> str:
    with socket.create_connection((host, int(port)), timeout=5) as s:
        s.sendall(_packet(3, password, 12))
        rid, _ = _read(s)
        if rid in (-1, 0xFFFFFFFF):
            print("Authentication failed: wrong RCON password", file=sys.stderr)
            sys.exit(1)
        s.sendall(_packet(2, command, 13))
        _, response = _read(s)
        return response


if __name__ == "__main__":
    args = sys.argv[1:]
    host = args[0] if len(args) > 0 else os.environ.get("RCON_HOST", "localhost")
    port = args[1] if len(args) > 1 else os.environ.get("RCON_PORT", "25575")
    password = args[2] if len(args) > 2 else os.environ.get("RCON_PASSWORD", "")
    command = args[3] if len(args) > 3 else ""
    if not command:
        print("Usage: rcon.py [host] [port] [password] <command>", file=sys.stderr)
        sys.exit(1)
    print(rcon_command(host, port, password, command))
