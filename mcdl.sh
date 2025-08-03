#!/usr/bin/env bash
set -euo pipefail

# ── Configurable environment vars ─────────────────────
# MC            : override to pin a Minecraft version (e.g. "1.21.6")
# LOADER        : override to pin a Fabric Loader version (e.g. "0.16.14")
# STABLE_LOADER : "true" (default) to pick newest stable loader; "false" for absolute newest

# 1. Resolve MC (latest non-snapshot) unless $MC is set
MC="${MC:-$(
  curl -s https://meta.fabricmc.net/v2/versions/game \
    | jq -r '.[] 
        | select(.version|test("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$")) 
        | .version' \
    | head -n1
)}"

# 2. Resolve Loader version
if [ "${STABLE_LOADER:-true}" = "true" ]; then
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
