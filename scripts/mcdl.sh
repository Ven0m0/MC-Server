#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C; IFS=$'\n\t'
s=${BASH_SOURCE[0]}; [[ $s != /* ]] && s=$PWD/$s; cd -P -- "${s%/*}/.."
has(){ command -v -- "$1" &>/dev/null; }
# mcdl.sh: Simple Fabric server downloader
# shellcheck source=lib/common.sh
source "${PWD}/lib/common.sh"
JSON_PROC=$(get_json_processor) || exit 1
print_info "Fetching Minecraft and Fabric versions..."
MC_VERSION="${MC_VERSION:-$(fetch_url "https://meta.fabricmc.net/v2/versions/game" | "$JSON_PROC" -r '[.[] | select(.stable == true)][0].version')}"
FABRIC_VERSION=$(fetch_url "https://meta.fabricmc.net/v2/versions/installer" | "$JSON_PROC" -r '.[0].version')
LOADER="${LOADER:-$(fetch_url "https://meta.fabricmc.net/v2/versions/loader" | "$JSON_PROC" -r '[.[] | select(.stable==true)][0].version')}"
print_info "Minecraft: $MC_VERSION | Fabric installer: $FABRIC_VERSION | Loader: $LOADER"
print_info "Downloading Fabric installer..."; download_file "https://maven.fabricmc.net/net/fabricmc/fabric-installer/${FABRIC_VERSION}/fabric-installer-${FABRIC_VERSION}.jar" "fabric-installer.jar"
print_info "Installing Fabric server..."; java -jar fabric-installer.jar server -mcversion "$MC_VERSION" -downloadMinecraft
rm -f fabric-installer.jar; print_success "Fabric server setup complete!"
