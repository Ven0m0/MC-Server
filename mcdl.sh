#!/usr/bin/env bash
set -euo pipefail

# ── Configurable environment vars ─────────────────────
# MC            : override to pin a Minecraft version (e.g. "1.21.6")
# LOADER        : override to pin a Fabric Loader version (e.g. "0.16.14")
# STABLE_LOADER : "true" (default) to pick newest stable loader; "false" for absolute newest

available_versions=$(curl -s https://meta.fabricmc.net/v2/versions/game | jq -r '.[] | select( .stable == true ) | .version')
server_version="$output"
loader_version=$(curl -s https://meta.fabricmc.net/v2/versions/loader/$server_version | jq -r 'first( .[] | .loader | .version )')
installer_verison=$(curl -s https://meta.fabricmc.net/v2/versions/installer | jq -r 'first( .[] | .version )')
server_jar="fabric-server-mc.$server_version-loader.$loader_version-launcher.$installer_verison.jar"
wget -O "$server_jar" "https://meta.fabricmc.net/v2/versions/loader/$server_version/$loader_version/$installer_verison/server/jar" || exit 1

# Done
MC_VERSION=$(curl -sSL https://meta.fabricmc.net/v2/versions/game | jq -r '.[] | select(.stable== true )|.version' | head -n1)
FABRIC_VERSION=$(curl -sSL https://meta.fabricmc.net/v2/versions/installer | jq -r '.[0].version')
wget -O fabric-installer.jar https://maven.fabricmc.net/net/fabricmc/fabric-installer/$FABRIC_VERSION/fabric-installer-$FABRIC_VERSION.jar
java -jar fabric-installer.jar server -mcversion $MC_VERSION -downloadMinecraft

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
  curl -s "https://meta.fabricmc.net/v2/versions/loader/${MC}/${LOADER}" \
    | jq -r '.[0].intermediary'
)"

echo "→ Minecraft:   $MC"
echo "→ Fabric Loader: $LOADER (stable filter: ${STABLE_LOADER:-true})"
echo "→ Intermediary:  $INTERMEDIARY"

# 4. Download the server-loader jar
curl -OJ "https://meta.fabricmc.net/v2/versions/loader/${MC}/${LOADER}/${INTERMEDIARY}/server/jar"
