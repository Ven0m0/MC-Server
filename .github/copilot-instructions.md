# MC-Server Copilot bootstrap

Start with `AGENTS.md`; it is the canonical repo-wide guide for this repository.

## Repo at a glance

- Bash-first Minecraft Fabric server automation suite.
- Main code lives in `tools/*.sh`.
- Runtime and server state live under `minecraft/`.
- Setup and tool metadata live in `README.md`, `docs/*.md`, `mise.toml`, and `server.toml`.

## Working rules

- Prefer small edits to existing scripts and docs over adding new files.
- Follow the Bash conventions in `AGENTS.md`: strict mode, quoted variables, `[[ ]]`, and 2-space indentation.
- Reuse helpers from `tools/common.sh` for logging, dependency checks, downloads, and server detection.
- Treat `minecraft/worlds`, `minecraft/backups`, and `minecraft/logs` as live data; do not modify them unless the task explicitly requires it.

## Validation

- `bash -n tools/*.sh minecraft/config/versions.sh`
- `shellcheck tools/*.sh minecraft/config/versions.sh`
- Review workflow and guidance edits in `.github/workflows/`, `.github/instructions/`, and `.github/skills/` for real paths and commands only.
