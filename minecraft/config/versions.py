#!/usr/bin/env python3
"""Centralized version and checksum management."""

# External tools
LAZYMC_VERSION = "0.2.11"
LAZYMC_SHA256 = {
    "x86_64": "9332f3d39fc030cc38e95f636d901404dc1c0cbf41df809692f3951858d03606",
    "aarch64": "a2b80b32e0b2825a44a1bf79cf1c0f01fba2bf3e12af09e426379091e2945202",
}

RUSTIC_VERSION = "0.19.1"
RUSTIC_SHA256 = {"x86_64": "", "aarch64": ""}  # Auto-download from GitHub if empty

CHUNKCLEANER_VERSION = "1.0.0"
CHUNKCLEANER_SHA256 = ""  # Add checksum from releases page

# Minecraft plugins (for mcctl)
LUCKPERMS_VERSION = "5.4.146"
FREEDOMCHAT_VERSION = "1.5.0"
DELUXEMENUS_VERSION = "1.14.0"

_CHECKSUMS = {
    "lazymc": LAZYMC_SHA256,
    "rustic": RUSTIC_SHA256,
    "chunkcleaner": {"any": CHUNKCLEANER_SHA256},
}


def get_checksum_for_arch(tool: str, arch: str) -> str:
    table = _CHECKSUMS.get(tool, {})
    return table.get(arch, table.get("any", ""))
