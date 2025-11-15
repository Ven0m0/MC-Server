#!/usr/bin/env bash

# Source common functions (SCRIPT_DIR is auto-initialized)
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

init_strict_mode

# ── Configurable environment vars ─────────────────────
# MC_VERSION    : override to pin a Minecraft version (e.g. "1.21.6")
# LOADER        : override to pin a Fabric Loader version (e.g. "0.16.14")
# STABLE_LOADER : "true" (default) to pick newest stable loader; "false" for absolute newest

# Get JSON processor
JSON_PROC=$(get_json_processor) || exit 1

# Cache API responses to avoid redundant network calls
print_header "Fetching Minecraft and Fabric versions..."
ARIA2_OPTS=($(get_aria2c_opts_array))
GAME_VERSIONS=$(fetch_url "https://meta.fabricmc.net/v2/versions/game") || exit 1
MC_VERSION="${MC_VERSION:-$(echo "$GAME_VERSIONS" | $JSON_PROC -r '.[] | select(.stable == true) | .version' | head -n1)}"
FABRIC_VERSION=$(fetch_url "https://meta.fabricmc.net/v2/versions/installer" | $JSON_PROC -r '.[0].version') || exit 1

print_info "Minecraft version: $MC_VERSION"
print_info "Fabric installer version: $FABRIC_VERSION"

# Download and run Fabric installer
print_header "Downloading Fabric installer..."
download_file "https://maven.fabricmc.net/net/fabricmc/fabric-installer/${FABRIC_VERSION}/fabric-installer-${FABRIC_VERSION}.jar" "fabric-installer.jar" || exit 1
print_success "Fabric installer downloaded"

print_header "Installing Fabric server..."
java -jar fabric-installer.jar server -mcversion "$MC_VERSION" -downloadMinecraft
print_success "Fabric server installed"

# Resolve Loader version
print_header "Resolving Fabric Loader version..."
LOADER_VERSIONS=$(fetch_url "https://meta.fabricmc.net/v2/versions/loader") || exit 1
if [[ ${STABLE_LOADER:-true} = true ]]; then
  LOADER="${LOADER:-$(echo "$LOADER_VERSIONS" | $JSON_PROC -r '.[] | select(.stable==true) | .version' | head -n1)}"
else
  LOADER="${LOADER:-$(echo "$LOADER_VERSIONS" | $JSON_PROC -r '.[0].version')}"
fi

# Lookup matching intermediary (mappings) version
INTERMEDIARY="$(
  fetch_url "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${LOADER}" \
    | $JSON_PROC -r '.[0].intermediary'
)" || exit 1

print_info "Fabric Loader: $LOADER (stable filter: ${STABLE_LOADER:-true})"
print_info "Intermediary:  $INTERMEDIARY"

# Download the server-loader jar
print_header "Downloading server-loader jar..."
download_file "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${LOADER}/${INTERMEDIARY}/server/jar" \
  "fabric-server-mc.${MC_VERSION}-loader.${LOADER}-launcher.${INTERMEDIARY}.jar" || exit 1

print_success "Fabric server setup complete!"
