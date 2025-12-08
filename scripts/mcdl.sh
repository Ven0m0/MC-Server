#!/usr/bin/env bash
# mcdl.sh: Simple Fabric server downloader

# Initialize strict mode
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C
user="${SUDO_USER:-${USER:-$(id -un)}}"
export HOME="/home/${user}"
SHELL="$(command -v bash 2>/dev/null || echo '/usr/bin/bash')"

# Check if command exists
has_command() { command -v "$1" &>/dev/null; }

# Detect JSON processor (prefer jaq over jq)
get_json_processor() {
  has_command jaq && { printf 'jaq'; return; }
  has_command jq && { printf 'jq'; return; }
  printf 'Error: No JSON processor found. Please install jq or jaq.\n' >&2
  return 1
}

# Fetch URL to stdout
fetch_url() {
  local url="$1"
  has_command aria2c && { aria2c -q -d /tmp -o - "$url" 2>/dev/null; return; }
  has_command curl && { curl -fsSL "$url"; return; }
  has_command wget && { wget -qO- "$url"; return; }
  printf 'Error: No download tool found (aria2c, curl, or wget)\n' >&2
  return 1
}

# Download file with aria2c or curl fallback
download_file() {
  local url="$1" output="$2" connections="${3:-8}"
  has_command curl && {
    curl -fsL -H "Accept-Encoding: identity" -H "Accept-Language: en" -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4.212 Safari/537.36" -o "$output" "$url"
    return
  }
  has_command wget && { wget -qO "$output" "$url"; return; }
  printf 'Error: No download tool found (aria2c, curl, or wget)\n' >&2
  return 1
}

# Output formatting helpers
print_info() { printf '\033[1;33m→\033[0m %s\n' "$1"; }
print_success() { printf '\033[0;32m✓\033[0m %s\n' "$1"; }

# Get JSON processor
JSON_PROC=$(get_json_processor) || exit 1

# Fetch versions
print_info "Fetching Minecraft and Fabric versions..."
MC_VERSION="${MC_VERSION:-$(fetch_url "https://meta.fabricmc.net/v2/versions/game" | "$JSON_PROC" -r '[.[] | select(.stable == true)][0].version')}"
FABRIC_VERSION=$(fetch_url "https://meta.fabricmc.net/v2/versions/installer" | "$JSON_PROC" -r '.[0].version')
LOADER="${LOADER:-$(fetch_url "https://meta.fabricmc.net/v2/versions/loader" | "$JSON_PROC" -r '[.[] | select(.stable==true)][0].version')}"

print_info "Minecraft: $MC_VERSION | Fabric installer: $FABRIC_VERSION | Loader: $LOADER"

# Download and run Fabric installer
print_info "Downloading Fabric installer..."
download_file "https://maven.fabricmc.net/net/fabricmc/fabric-installer/${FABRIC_VERSION}/fabric-installer-${FABRIC_VERSION}.jar" \
  "fabric-installer.jar"

print_info "Installing Fabric server..."
java -jar fabric-installer.jar server -mcversion "$MC_VERSION" -downloadMinecraft

# Cleanup installer
rm -f fabric-installer.jar

print_success "Fabric server setup complete!"
