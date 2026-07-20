---
applyTo: "tools/*.py,minecraft/config/versions.py"
---
# Python tooling rules

- Follow the Python conventions and helper usage documented in `AGENTS.md`.
- Keep existing script headers (`#!/usr/bin/env python3`, module docstring) when present.
- Prefer shared helpers from `tools/common.py` over duplicate logging, download, dependency, or server-detection logic.
- Use type hints, `pathlib.Path` over string paths, and keep indentation at 4 spaces.
- Validate changed scripts with `python3 -m py_compile` and `ruff check` (if installed).
- Files vendored from third-party projects (e.g. `tools/mcpe-world-prune/*.py`) are exempt - don't reformat or restyle vendored code.
