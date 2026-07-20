---
name: maintain-python-tools
description: Use when editing or reviewing MC-Server Python tooling in `tools/` and related helpers.
allowed-tools: 'Read, Write, Edit, Glob, Grep, Bash'
---

# Maintain Python tools

Use this skill when changing `tools/*.py`, `minecraft/config/versions.py`, or closely related systemd assets.

## Goal

Make focused Python changes without breaking server automation or modifying live Minecraft state by accident.

## Steps

1. Read `AGENTS.md`, `.github/copilot-instructions.md`, and the target files. Check `tools/common.py` before adding new helpers.
2. Keep the existing script structure: shebang, module docstring, type hints, and 4-space indentation.
3. Reuse logging (`header`, `success`, `info`, `error`), dependency, download, and server helpers from `tools/common.py` whenever possible.
4. Avoid changing `minecraft/`, especially `minecraft/backups/`, or generated server artifacts unless the task explicitly asks for it.
5. If the change affects startup, backups, or monitoring, inspect the related sibling scripts to preserve CLI and file layout expectations.
6. Validate changed scripts with `python3 -m py_compile` and `ruff check` (if installed).

## Invariants

- Do not replace shared helpers with ad-hoc duplicate logic.
- Do not add new runtimes or package managers for tooling-only changes.
- Report pre-existing validation failures outside the changed files instead of sweeping unrelated fixes.
