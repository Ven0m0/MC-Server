---
applyTo: "tools/**/*.sh,minecraft/config/versions.sh"
---
# Shell tooling rules

- Follow the Bash conventions and helper usage documented in `AGENTS.md`.
- Keep existing script headers, strict mode, locale settings, and `IFS` handling when present.
- Prefer shared helpers from `tools/common.sh` over duplicate logging, download, dependency, or server-detection logic.
- Use `local` variables inside functions, quote every expansion, and keep indentation at 2 spaces.
- Validate changed shell files with `bash -n` and `shellcheck`.
