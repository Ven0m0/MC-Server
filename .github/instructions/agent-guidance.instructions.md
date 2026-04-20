---
applyTo: "AGENTS.md,.github/copilot-instructions.md,.github/instructions/**/*.md,.github/skills/**/*.md"
---
# Agent guidance rules

- Keep `.github/copilot-instructions.md` short and point detailed guidance back to `AGENTS.md`.
- Reference only commands, files, and workflows that exist in this repository.
- Prefer narrow instructions and skills over copying repo-wide rules into every file.
- Call out unsafe stateful paths when relevant, especially `minecraft/` and `minecraft/backups/`.
