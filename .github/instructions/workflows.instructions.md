---
applyTo: ".github/workflows/**/*.yml,.github/workflows/**/*.yaml"
---
# Workflow rules

- Use pinned action SHAs and keep workflow `permissions` minimal.
- Scope `push` and `pull_request` triggers with `paths` filters whenever possible.
- Match the repository's real toolchain: Bash tooling, Java 21+, and `mise` for repo-managed tools.
- Prefer straightforward `run` steps over extra actions unless an action clearly reduces setup complexity.
- When validating shell automation, cover `tools/*.sh` and `minecraft/config/versions.sh`.
