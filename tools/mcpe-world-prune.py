#!/usr/bin/env python3
"""Wrapper for MCPE-World-Prune-Tool (vendored in tools/mcpe-world-prune/).

The tool is Tk GUI-only (world/zone selection via file dialogs) - this
script just makes sure Python + deps are present and launches it.
"""

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import SCRIPT_DIR, check_dependencies, error, header, info

PRUNE_DIR = SCRIPT_DIR / "tools" / "mcpe-world-prune"


def main() -> None:
    if not check_dependencies("python3"):
        sys.exit(1)
    try:
        import tkinter  # noqa: F401
    except ImportError:
        error("python3-tkinter not installed (Debian/Ubuntu: apt install python3-tk)")
        sys.exit(1)
    try:
        import numpy  # noqa: F401  # pyright: ignore[reportMissingImports]  # ty: ignore[unresolved-import]
    except ImportError:
        info("Installing numpy for the current user...")
        r = subprocess.run([sys.executable, "-m", "pip", "install", "--user", "numpy"])
        if r.returncode != 0:
            error("Failed to install numpy")
            sys.exit(1)

    header("MCPE World Prune Tool")
    info(
        "Export a .mcworld backup of your Bedrock world first - pruning is destructive."
    )
    info(
        "In the GUI: browse to the .mcworld file, set the area to keep, add extra delete zones, then Export."
    )

    import os

    os.chdir(PRUNE_DIR)
    os.execvp(sys.executable, [sys.executable, "chunkDeleter.py"])


if __name__ == "__main__":
    main()
