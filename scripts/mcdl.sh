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
  if has_command jaq; then
    echo "jaq"
  elif has_command jq; then
    echo "jq"
  else
    echo "Error: No JSON processor found. Please install jq or jaq." >&2
    return 1
  fi
}

# Fetch URL to stdout
fetch_url() {
  local url="$1"
  if has_command aria2c; then
    aria2c -q -d /tmp -o - "$url" 2>/dev/null
  elif has_command curl; then
    curl -fsSL "$url"
  elif has_command wget; then
    wget -qO- "$url"
  else
    echo "Error: No download tool found (aria2c, curl, or wget)" >&2
    return 1
  fi
}

# Download file with aria2c or curl fallback
download_file() {
  local url="$1" output="$2" connections="${3:-8}"
  if has_command aria2c; then
    aria2c -x "$connections" -s "$connections" -o "$output" "$url"
  elif has_command curl; then
    curl -fsL -o "$output" "$url"
  elif has_command wget; then
    wget -qO "$output" "$url"
  else
    echo "Error: No download tool found (aria2c, curl, or wget)" >&2
    return 1
  fi
}

# Output formatting helpers
print_info() { echo -e "\033[1;33m→\033[0m $1"; }
print_success() { echo -e "\033[0;32m✓\033[0m $1"; }

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
