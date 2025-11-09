#!/usr/bin/env bash

# Source common functions
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

init_strict_mode

# ── Configurable environment vars ─────────────────────
# MC_VERSION    : override to pin a Minecraft version (e.g. "1.21.6")
# LOADER        : override to pin a Fabric Loader version (e.g. "0.16.14")
# STABLE_LOADER : "true" (default) to pick newest stable loader; "false" for absolute newest

# Detect JSON processor: prefer jaq, fallback to jq
if command -v jaq &>/dev/null; then
  JSON_PROC="jaq"
else
  JSON_PROC="jq"
fi

# Cache API responses to avoid redundant network calls
echo "[*] Fetching Minecraft and Fabric versions..."
GAME_VERSIONS=$(aria2c -q -d /tmp -o - https://meta.fabricmc.net/v2/versions/game)
MC_VERSION="${MC_VERSION:-$(echo "$GAME_VERSIONS" | $JSON_PROC -r '.[] | select(.stable == true) | .version' | head -n1)}"
FABRIC_VERSION=$(aria2c -q -d /tmp -o - https://meta.fabricmc.net/v2/versions/installer | $JSON_PROC -r '.[0].version')

echo "→ Minecraft version: $MC_VERSION"
echo "→ Fabric installer version: $FABRIC_VERSION"

# Download and run Fabric installer (single approach)
echo "[*] Downloading Fabric installer..."
aria2c -x 16 -s 16 -o fabric-installer.jar "https://maven.fabricmc.net/net/fabricmc/fabric-installer/${FABRIC_VERSION}/fabric-installer-${FABRIC_VERSION}.jar" || exit 1

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
aria2c -x 16 -s 16 "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${LOADER}/${INTERMEDIARY}/server/jar"

echo "[✔] Fabric server setup complete."
