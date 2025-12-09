#!/usr/bin/env bash
# mcdl.sh: Simple Fabric server downloader

# Source common library
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
JSON_PROC=$(get_json_processor) || exit 1
print_info "Fetching Minecraft and Fabric versions..."
MC_VERSION="${MC_VERSION:-$(fetch_url "https://meta.fabricmc.net/v2/versions/game" | "$JSON_PROC" -r '[.[] | select(.stable == true)][0].version')}"
FABRIC_VERSION=$(fetch_url "https://meta.fabricmc.net/v2/versions/installer" | "$JSON_PROC" -r '.[0].version')
LOADER="${LOADER:-$(fetch_url "https://meta.fabricmc.net/v2/versions/loader" | "$JSON_PROC" -r '[.[] | select(.stable==true)][0].version')}"
print_info "Minecraft: $MC_VERSION | Fabric installer: $FABRIC_VERSION | Loader: $LOADER"
print_info "Downloading Fabric installer..."; download_file "https://maven.fabricmc.net/net/fabricmc/fabric-installer/${FABRIC_VERSION}/fabric-installer-${FABRIC_VERSION}.jar" "fabric-installer.jar"
print_info "Installing Fabric server..."; java -jar fabric-installer.jar server -mcversion "$MC_VERSION" -downloadMinecraft
rm -f fabric-installer.jar; print_success "Fabric server setup complete!"
