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
echo "[*] Fetching Minecraft and Fabric versions..."
ARIA2_OPTS=($(get_aria2c_opts_array))
GAME_VERSIONS=$(aria2c -q -d /tmp -o - https://meta.fabricmc.net/v2/versions/game)
MC_VERSION="${MC_VERSION:-$(echo "$GAME_VERSIONS" | $JSON_PROC -r '.[] | select(.stable == true) | .version' | head -n1)}"
FABRIC_VERSION=$(aria2c -q -d /tmp -o - https://meta.fabricmc.net/v2/versions/installer | $JSON_PROC -r '.[0].version')

echo "→ Minecraft version: $MC_VERSION"
echo "→ Fabric installer version: $FABRIC_VERSION"

# Download and run Fabric installer (single approach)
echo "[*] Downloading Fabric installer..."
aria2c "${ARIA2_OPTS[@]}" -o fabric-installer.jar "https://maven.fabricmc.net/net/fabricmc/fabric-installer/${FABRIC_VERSION}/fabric-installer-${FABRIC_VERSION}.jar" || exit 1

echo "[*] Installing Fabric server..."
java -jar fabric-installer.jar server -mcversion "$MC_VERSION" -downloadMinecraft

# 2. Resolve Loader version (cache loader versions API call)
LOADER_VERSIONS=$(aria2c -q -d /tmp -o - https://meta.fabricmc.net/v2/versions/loader)
if [[ ${STABLE_LOADER:-true} = true ]]; then
  LOADER="${LOADER:-$(echo "$LOADER_VERSIONS" | $JSON_PROC -r '.[] | select(.stable==true) | .version' | head -n1)}"
else
  LOADER="${LOADER:-$(echo "$LOADER_VERSIONS" | $JSON_PROC -r '.[0].version')}"
fi

# 3. Lookup matching intermediary (mappings) version
INTERMEDIARY="$(
  aria2c -q -d /tmp -o - "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${LOADER}" \
    | $JSON_PROC -r '.[0].intermediary'
)"

echo "→ Fabric Loader: $LOADER (stable filter: ${STABLE_LOADER:-true})"
echo "→ Intermediary:  $INTERMEDIARY"

# 4. Download the server-loader jar
echo "[*] Downloading server-loader jar..."
aria2c "${ARIA2_OPTS[@]}" "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${LOADER}/${INTERMEDIARY}/server/jar"

echo "[✔] Fabric server setup complete."
