---
name: maintain-shell-tools
description: Safely edit or review MC-Server shell tooling in `tools/` and related shell helpers.
allowed-tools: 'Read, Write, Edit, Glob, Grep, Bash'
---

# Maintain shell tools

Use this skill when changing `tools/*.sh`, `minecraft/config/versions.sh`, or closely related systemd assets.

## Goal

Make focused Bash changes without breaking server automation or modifying live Minecraft state by accident.

## Steps

1. Read `AGENTS.md`, `.github/copilot-instructions.md`, and the target files. Check `tools/common.sh` before adding new helpers.
2. Keep the existing script structure: shebang, shellcheck header, strict mode, quoted variables, `[[ ]]`, and 2-space indentation.
3. Reuse `print_*`, dependency helpers, download helpers, and server helpers from `tools/common.sh` whenever possible.
4. Avoid changing `minecraft/worlds`, `minecraft/backups`, `minecraft/logs`, or generated server artifacts unless the task explicitly asks for it.
5. If the change affects startup, backups, or monitoring, inspect the related sibling scripts to preserve CLI and file layout expectations.
6. Validate changed shell files with `bash -n` and `shellcheck`.

## Invariants

- Do not replace shared helpers with ad-hoc duplicate logic.
- Do not add new runtimes or package managers for shell-only changes.
- Report pre-existing validation failures outside the changed files instead of sweeping unrelated fixes.
