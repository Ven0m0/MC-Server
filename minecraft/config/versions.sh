#!/usr/bin/env bash
# shellcheck enable=all shell=bash
# versions.sh: Centralized version and checksum management
# ============================================================================
# EXTERNAL TOOLS
# ============================================================================
# lazymc - Automatic server sleep/wake proxy
LAZYMC_VERSION="0.2.11"
LAZYMC_SHA256_X86_64="9332f3d39fc030cc38e95f636d901404dc1c0cbf41df809692f3951858d03606"
LAZYMC_SHA256_AARCH64="a2b80b32e0b2825a44a1bf79cf1c0f01fba2bf3e12af09e426379091e2945202"

# rustic - Backup tool
RUSTIC_VERSION="0.19.1"
RUSTIC_SHA256_X86_64=""  # Auto-download from GitHub if empty
RUSTIC_SHA256_AARCH64=""  # Auto-download from GitHub if empty

# ChunkCleaner - World optimization
CHUNKCLEANER_VERSION="1.0.0"
CHUNKCLEANER_SHA256=""  # Add checksum from releases page

# ============================================================================
# MINECRAFT PLUGINS (for mcctl.sh)
# ============================================================================
# LuckPerms - Permissions plugin
LUCKPERMS_VERSION="5.4.146"  # Updated from 5.4.56

# FreedomChat - Chat plugin
FREEDOMCHAT_VERSION="1.5.0"  # Updated from 1.3.1

# DeluxeMenus - Menu plugin
DELUXEMENUS_VERSION="1.14.0"  # Updated from 1.13.7-DEV-152

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
get_checksum_for_arch(){
  local tool="$1" arch="$2"
  case "$tool" in
    lazymc)
      case "$arch" in
        x86_64) printf '%s' "$LAZYMC_SHA256_X86_64" ;;
        aarch64) printf '%s' "$LAZYMC_SHA256_AARCH64" ;;
        *) printf '' ;;
      esac
      ;;
    rustic)
      case "$arch" in
        x86_64) printf '%s' "$RUSTIC_SHA256_X86_64" ;;
        aarch64) printf '%s' "$RUSTIC_SHA256_AARCH64" ;;
        *) printf '' ;;
      esac
      ;;
    chunkcleaner)
      printf '%s' "$CHUNKCLEANER_SHA256"
      ;;
    *)
      printf ''
      ;;
  esac
}
