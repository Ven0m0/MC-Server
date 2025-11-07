#!/usr/bin/env bash
set -euo pipefail

# ── Configurable environment vars ─────────────────────
# MC            : override to pin a Minecraft version (e.g. "1.21.6")
# LOADER        : override to pin a Fabric Loader version (e.g. "0.16.14")
# STABLE_LOADER : "true" (default) to pick newest stable loader; "false" for absolute newest

# Cache API responses to avoid redundant curl calls
echo "[*] Fetching Minecraft and Fabric versions..."
MC_VERSION="${MC:-$(curl -sSL https://meta.fabricmc.net/v2/versions/game | jq -r '.[] | select(.stable == true) | .version' | head -n1)}"
FABRIC_VERSION=$(curl -sSL https://meta.fabricmc.net/v2/versions/installer | jq -r '.[0].version')

echo "→ Minecraft version: $MC_VERSION"
echo "→ Fabric installer version: $FABRIC_VERSION"

# Download and run Fabric installer (single approach)
echo "[*] Downloading Fabric installer..."
wget -O fabric-installer.jar "https://maven.fabricmc.net/net/fabricmc/fabric-installer/${FABRIC_VERSION}/fabric-installer-${FABRIC_VERSION}.jar" || exit 1

echo "[*] Installing Fabric server..."
java -jar fabric-installer.jar server -mcversion "$MC_VERSION" -downloadMinecraft

# 2. Resolve Loader version
if [[ ${STABLE_LOADER:-true} = true ]]; then
  LOADER="${LOADER:-$(
    curl -s https://meta.fabricmc.net/v2/versions/loader \
      | jq -r '.[] 
          | select(.stable==true) 
          | .version' \
      | head -n1
  )}"
else
  LOADER="${LOADER:-$(
    curl -s https://meta.fabricmc.net/v2/versions/loader \
      | jq -r '.[0].version'
  )}"
fi

# 3. Lookup matching intermediary (mappings) version
INTERMEDIARY="$(
  curl -s "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${LOADER}" \
    | jq -r '.[0].intermediary'
)"

echo "→ Fabric Loader: $LOADER (stable filter: ${STABLE_LOADER:-true})"
echo "→ Intermediary:  $INTERMEDIARY"

# 4. Download the server-loader jar
echo "[*] Downloading server-loader jar..."
curl -OJ "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${LOADER}/${INTERMEDIARY}/server/jar"

echo "[✔] Fabric server setup complete."
