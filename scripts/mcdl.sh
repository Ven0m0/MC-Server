#!/usr/bin/env bash
# mcdl.sh: Simple Fabric server downloader

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

init_strict_mode

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
