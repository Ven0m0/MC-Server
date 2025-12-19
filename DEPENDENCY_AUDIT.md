# Dependency Audit Report
**Generated:** 2025-12-19
**Repository:** MC-Server (Minecraft Server Management Suite)

## Executive Summary

This audit analyzed all dependencies across GitHub Actions workflows, shell scripts, and external tool downloads. The project is primarily Bash-based with no traditional package managers (npm, pip, etc.), but has configuration bloat for unused ecosystems.

### Key Findings
- ✅ **Good:** GitHub Actions use SHA pinning for security
- ✅ **Good:** All external downloads use HTTPS
- ⚠️ **Issue:** Dependabot configured for 6 ecosystems but only 1 is actually used
- ⚠️ **Issue:** Several plugins use unpinned Jenkins "lastSuccessfulBuild" URLs
- ⚠️ **Issue:** No checksum verification for binary downloads
- ⚠️ **Issue:** One outdated GitHub Action (github-push-action v1.0.0)

---

## 1. GitHub Actions Dependencies

### Current Status
All actions use SHA commit pinning for security ✓

| Action | Version | SHA | Status |
|--------|---------|-----|--------|
| actions/checkout | v6.0.1 | 8e8c483... | ✅ Current |
| actions/github-script | v8.0.0 | ed59741... | ✅ Current |
| actions/upload-artifact | v6.0.0 | b7c566a... | ✅ Current |
| peter-evans/create-pull-request | v8.0.0 | 9835718... | ✅ Current |
| peter-evans/create-or-update-comment | v5.0.0 | e8674b0... | ✅ Current |
| oxsecurity/megalinter | v9.2.0 | 55a59b2... | ✅ Current |
| ComunidadAylas/PackSquash-action | v4.0.3 | a9128de... | ✅ Current |
| **ad-m/github-push-action** | **v1.0.0** | 77c5b41... | **⚠️ OUTDATED** |

### Recommendations
1. **CRITICAL:** Replace `ad-m/github-push-action@v1.0.0` with native git commands
   - Last updated: 2019-2020 (5+ years old)
   - Known security issues with PAT handling
   - Recommended alternative: Use native git push in run steps
   ```yaml
   - name: Push changes
     run: |
       git push origin ${{ github.head_ref || github.ref }}
   ```

2. **OPTIONAL:** Consider MegaLinter upgrade path
   - Current: v9.2.0 (2024)
   - Check for v10.x releases in 2025

---

## 2. Dependabot Configuration Bloat

### Current Configuration
`.github/dependabot.yml` configures **6 ecosystems**, but only **1 is actively used**.

| Ecosystem | Configured | Actually Used | Files Expected |
|-----------|------------|---------------|----------------|
| github-actions | ✅ | ✅ | `.github/workflows/*.yml` |
| gitsubmodule | ✅ | ❌ | `.gitmodules` (missing) |
| pip | ✅ | ❌ | `requirements.txt` (missing) |
| uv | ✅ | ❌ | `pyproject.toml` (missing) |
| npm | ✅ | ❌ | `package.json` (missing) |
| bun | ✅ | ❌ | `package.json` (missing) |

### Impact
- **5 unnecessary Dependabot checks** run weekly → wasted CI minutes
- Potential for confusion if package files are added later
- False sense of coverage for non-existent dependencies

### Recommendations
**REMOVE unused ecosystems** from `.github/dependabot.yml`:

```yaml
version: 2
updates:
  # Keep only github-actions
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      github-actions-all:
        patterns:
          - "*"
        update-types:
          - "minor"
          - "patch"
```

**Estimated savings:** ~5 wasted Dependabot runs per week

---

## 3. External Binary Downloads

### Download Sources Audit

| Tool | Source | Version Pinning | Checksum | Security Risk |
|------|--------|-----------------|----------|---------------|
| lazymc | GitHub releases | ✅ v0.2.11 | ❌ None | Low |
| rustic | GitHub releases | ✅ v0.19.1 | ❌ None | Low |
| ChunkCleaner | GitHub releases | ✅ v1.0.0 | ❌ None | Low |
| Minecraft client/server | Mojang API | ✅ Dynamic | ❌ None | Low |

**All downloads use HTTPS** ✓

### Minecraft Plugin Downloads (mcctl.sh)

#### Versioned Downloads (Good)
- ViaVersion: GitHub releases (latest tag) ✅
- ViaBackwards: GitHub releases (latest tag) ✅
- MultiLogin: GitHub releases (latest) ✅
- Vault: GitHub releases (latest) ✅
- GriefPrevention: GitHub releases (latest) ✅
- NoEncryption: GitHub releases (latest tag) ✅
- CraftGUI: GitHub releases (tagged) ✅
- GlobalMarket: GitHub releases (tagged) ✅
- Paper: PaperMC API (versioned builds) ✅

#### Unversioned/Unstable Downloads (Risk)
⚠️ **Jenkins "lastSuccessfulBuild" URLs** (no version pinning):
- **BuildTools** (`hub.spigotmc.org/jenkins`) - tools/mcctl.sh:72
- **Floodgate** (`ci.opencollab.dev/jenkins`) - tools/mcctl.sh:75
- **Geyser** (`ci.opencollab.dev/jenkins`) - tools/mcctl.sh:78
- **ProtocolLib** (`ci.dmulloy2.net/jenkins`) - tools/mcctl.sh:88
- **DeluxeMenus** (`ci.extendedclip.com/jenkins`) - tools/mcctl.sh:103

#### Hardcoded Versions (Outdated Risk)
⚠️ **Plugins with hardcoded versions** (won't auto-update):
- **LuckPerms** v5.4.56 (hardcoded) - tools/mcctl.sh:94
- **FreedomChat** v1.3.1 (hardcoded) - tools/mcctl.sh:100
- **DeluxeMenus** v1.13.7-DEV-152 (hardcoded) - tools/mcctl.sh:103

### Recommendations

1. **HIGH PRIORITY:** Add checksum verification for binary downloads
   ```bash
   # Example for lazymc download
   download_file "$url" "$target_file"
   echo "$expected_sha256  $target_file" | sha256sum -c - || {
     print_error "Checksum verification failed"
     exit 1
   }
   ```

2. **MEDIUM PRIORITY:** Pin Jenkins builds or migrate to stable releases
   - Replace `lastSuccessfulBuild` with specific build numbers
   - Or migrate to GitHub releases where available
   - Example: Geyser/Floodgate have GitHub releases as alternative

3. **LOW PRIORITY:** Update hardcoded plugin versions
   - LuckPerms: Update to v5.4.x latest or use dynamic lookup
   - FreedomChat: Use Modrinth API for latest version
   - DeluxeMenus: Pin to specific build number instead of DEV

4. **OPTIONAL:** Update ChunkCleaner
   - Current: v1.0.0 (likely 2020-2021)
   - Check for newer releases at https://github.com/zeroBzeroT/ChunkCleaner

---

## 4. Shell Tool Dependencies

### Required System Tools
These tools must be installed on the host system:

| Tool | Purpose | Priority | Fallback |
|------|---------|----------|----------|
| **bash** 5.0+ | Shell runtime | Critical | None |
| **java** 21+ | Minecraft runtime | Critical | None |
| **curl** or **wget** | Downloads | Critical | Each other |
| **jq** or **jaq** | JSON processing | Critical | Each other (jaq preferred) |
| **tar** | Backups | High | None |
| **screen** or **tmux** | Server sessions | High | Each other |

### Optional Performance Tools
| Tool | Purpose | Benefit | Auto-installed |
|------|---------|---------|----------------|
| **aria2c** | Parallel downloads | 3-5x faster | No |
| **parallel** | Parallel processing | Faster config format | No |
| **yq** | YAML processing | Better formatting | No |
| **yamlfmt** | YAML formatting | Code quality | No |
| **rustic** | Btrfs backups | Advanced backups | Yes (auto-download) |
| **mcrcon** | RCON client | Server control | No |

### Missing Documentation
⚠️ **No installation guide** for required dependencies

### Recommendations

1. **Create `DEPENDENCIES.md`** documenting required tools:
   ```markdown
   # Required Dependencies

   ## Arch Linux
   ```bash
   pacman -S bash jdk21-openjdk curl jq screen
   ```

   ## Ubuntu/Debian
   ```bash
   apt install bash openjdk-21-jdk curl jq screen
   ```
   ```

2. **Add dependency checker** at start of key scripts:
   ```bash
   # In tools/server-start.sh, tools/mcctl.sh, etc.
   check_dependencies java jq curl tar || exit 1
   ```

3. **Document optional tools** in CLAUDE.md under "Tool Preferences"

---

## 5. Version Management Issues

### Hardcoded Versions Across Codebase

| Component | File | Line | Current | Update Strategy |
|-----------|------|------|---------|-----------------|
| lazymc | prepare.sh | 18 | 0.2.11 | Manual (good) |
| ChunkCleaner | world-optimize.sh | 25 | 1.0.0 | **Consider auto-update** |
| LuckPerms | mcctl.sh | 94 | 5.4.56 | **Add version variable** |
| FreedomChat | mcctl.sh | 100 | 1.3.1 | **Add version variable** |

### Recommendations

1. **Consolidate version variables** in single config file:
   ```bash
   # config/versions.sh
   LAZYMC_VERSION="0.2.11"
   CHUNKCLEANER_VERSION="1.0.0"
   LUCKPERMS_VERSION="5.4.56"
   FREEDOMCHAT_VERSION="1.3.1"
   ```

2. **Document version update process** in CLAUDE.md

---

## 6. Security Vulnerabilities

### Assessment: **LOW RISK** ✅

**Positive findings:**
- ✅ All downloads use HTTPS (no HTTP)
- ✅ GitHub Actions use SHA commit pinning
- ✅ No obvious injection vulnerabilities in shell scripts
- ✅ Strict mode enabled (`set -euo pipefail`) in most scripts
- ✅ Variables properly quoted

**Minor issues:**
- ⚠️ No checksum/signature verification for binaries
- ⚠️ Jenkins builds can change unexpectedly (supply chain risk)
- ⚠️ No SBOM (Software Bill of Materials)

### Recommendations

1. **Add integrity checks** for critical binaries (java, plugins)
2. **Document trust assumptions** for third-party sources
3. **Consider generating SBOM** with `syft` or similar tool

---

## 7. Unnecessary Bloat

### Identified Bloat

1. **Dependabot config bloat** (5 unused ecosystems)
   - Impact: Wasted CI minutes, maintenance overhead
   - Solution: Remove unused ecosystems (see Section 2)

2. **GitHub Actions workflows may have unused features**
   - `image-optimization.yml`: Only triggers on image changes (minimal impact)
   - `packsquash.yml`: Workflow dispatch only (good)
   - `config-format.yml`: Runs on all JSON/YAML changes (appropriate)

3. **Shell script duplication**
   - `has()` function redefined in multiple scripts (tools/server-start.sh:10, tools/prepare.sh:10, tools/lazymc.sh:10, tools/mod-updates.sh:10)
   - Already available in `lib/common.sh` as `has_command()`
   - **Impact:** Minor code duplication, not critical

### Recommendations

1. **Remove duplicate `has()` definitions**
   - Use `has_command()` from `lib/common.sh` everywhere
   - Or keep local `has()` for scripts that run before sourcing common.sh

2. **Audit workflow triggers**
   - Consider reducing `claude/**` branch builds if not needed
   - Review if all workflow jobs are necessary

---

## 8. Priority Action Items

### 🔴 CRITICAL (Do First)
1. **Remove dependabot bloat** (5 unused ecosystems)
   - File: `.github/dependabot.yml`
   - Savings: ~5 wasted runs/week
   - Difficulty: Easy (5 min)

2. **Replace ad-m/github-push-action**
   - File: `.github/workflows/packsquash.yml:30`
   - Risk: Outdated action (5+ years old)
   - Difficulty: Easy (10 min)

### 🟡 HIGH (Do Soon)
3. **Add checksum verification** for binary downloads
   - Files: `tools/prepare.sh`, `tools/world-optimize.sh`, `tools/backup.sh`
   - Risk: Supply chain attacks
   - Difficulty: Medium (30-60 min)

4. **Pin or version Jenkins builds**
   - File: `tools/mcctl.sh` (5 plugins)
   - Risk: Unexpected changes, breakage
   - Difficulty: Medium (20-30 min)

### 🟢 MEDIUM (Nice to Have)
5. **Create DEPENDENCIES.md**
   - Document installation requirements
   - Difficulty: Easy (15 min)

6. **Update hardcoded plugin versions**
   - LuckPerms, FreedomChat, DeluxeMenus
   - Difficulty: Medium (20 min)

7. **Remove duplicate has() functions**
   - Standardize on `has_command()` from lib/common.sh
   - Difficulty: Easy (10 min)

### 🔵 LOW (Future)
8. **Update ChunkCleaner** (if newer version exists)
9. **Generate SBOM** for compliance/security
10. **Add version update automation** (bot or script)

---

## 9. Implementation Plan

### Phase 1: Quick Wins (1 hour)
```bash
# 1. Clean up dependabot.yml (5 min)
edit .github/dependabot.yml  # Remove pip, uv, npm, bun, gitsubmodule

# 2. Fix github-push-action (10 min)
edit .github/workflows/packsquash.yml  # Replace with native git push

# 3. Create DEPENDENCIES.md (15 min)
# Document required tools for Arch, Ubuntu, Fedora

# 4. Test workflows (30 min)
git checkout -b dependency-cleanup
git add .github/dependabot.yml .github/workflows/packsquash.yml
git commit -m "chore: remove dependabot bloat and update push action"
git push -u origin dependency-cleanup
```

### Phase 2: Security Hardening (2 hours)
```bash
# 1. Add checksum verification (60 min)
# Update prepare.sh, world-optimize.sh, backup.sh

# 2. Pin Jenkins builds (30 min)
# Update mcctl.sh with specific build numbers

# 3. Update plugin versions (20 min)
# LuckPerms, FreedomChat, DeluxeMenus

# 4. Add dependency checks (10 min)
# Add check_dependencies calls to main scripts
```

### Phase 3: Code Quality (1 hour)
```bash
# 1. Remove duplicate has() (10 min)
# Standardize on lib/common.sh

# 2. Consolidate version variables (20 min)
# Create config/versions.sh

# 3. Documentation updates (30 min)
# Update CLAUDE.md with new sections
```

---

## 10. Maintenance Recommendations

### Ongoing Tasks
1. **Weekly:** Review Dependabot PRs for GitHub Actions
2. **Monthly:** Check for new plugin versions (manual or scripted)
3. **Quarterly:** Audit external download URLs for deprecation
4. **Yearly:** Full dependency security audit

### Automation Opportunities
1. **Version checker script** to detect outdated hardcoded versions
2. **Checksum updater** for when upstream binaries change
3. **Plugin version scraper** to auto-update mcctl.sh URLs

---

## Conclusion

The MC-Server project has **good security hygiene** overall (HTTPS, SHA pinning) but suffers from **configuration bloat** (unused Dependabot ecosystems) and **missing integrity checks** for binary downloads.

### Overall Risk Level: **LOW** ✅
### Bloat Level: **MEDIUM** ⚠️
### Maintainability: **GOOD** ✅

**Recommended immediate action:** Remove 5 unused Dependabot ecosystems to reduce waste (5 min fix).

**Next steps:** Follow Phase 1 implementation plan above for quick wins in ~1 hour.
