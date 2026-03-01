#!/usr/bin/env bash
# mc-client.sh: Minecraft client launcher with automatic version management
# Based on https://github.com/Sushkyn/mc-launcher

# Source common library
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/common.sh
source "${SCRIPT_DIR}/tools/common.sh"
# Extract natives from JAR file
extract_natives(){
  local jar_file="$1" dest_dir="$2"
  ensure_dir "$dest_dir"
  unzip -q -o "$jar_file" -d "$dest_dir" 2>/dev/null || :
  rm -rf "${dest_dir:?}/META-INF"
}
# Check dependencies
check_dependencies java unzip || exit 1
# Get JSON processor
JSON_PROC=$(get_json_processor) || exit 1
# Configuration
MC_DIR="${MC_DIR:-$HOME/.minecraft}"
VERSION="${1:-}"
USERNAME="${2:-Player}"
# Show usage if no version specified
if [[ -z $VERSION ]]; then
  printf 'Usage: %s <VERSION> [USERNAME]\n' "$0"
  printf 'Example: %s 1.21.6 MyPlayer\n' "$0"
  printf '\n'
  printf 'Environment variables:\n'
  printf '  MC_DIR    : Minecraft directory (default: ~/.minecraft)\n'
  exit 1
fi
# Directory structure
VERSIONS_DIR="$MC_DIR/versions/$VERSION"
ASSETS_DIR="$MC_DIR/assets"
LIBRARIES_DIR="$MC_DIR/libraries"
NATIVES_DIR="$VERSIONS_DIR/natives"
# Create directories
ensure_dir "$VERSIONS_DIR"
ensure_dir "$ASSETS_DIR"
ensure_dir "$LIBRARIES_DIR"
ensure_dir "$NATIVES_DIR"
printf '[*] Minecraft Client Launcher\n'
printf '→ Version: %s\n' "$VERSION"
printf '→ Username: %s\n' "$USERNAME"
printf '→ Directory: %s\n' "$MC_DIR"
printf '\n'
# Download version manifest
printf '[1/5] Fetching version manifest...\n'
VERSION_MANIFEST="$VERSIONS_DIR/version.json"
if [[ ! -f $VERSION_MANIFEST ]]; then
  printf '  Downloading version list...\n'
  VERSION_LIST=$(fetch_url "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
  VERSION_URL=$(printf '%s' "$VERSION_LIST" | "$JSON_PROC" -r ".versions[] | select(.id == \"$VERSION\") | .url")
  [[ -z $VERSION_URL ]] && { printf 'Error: Version %s not found\n' "$VERSION" >&2; exit 1; }
  printf '  Downloading version manifest...\n'
  fetch_url "$VERSION_URL" >"$VERSION_MANIFEST"
else
  printf '  Using cached version manifest\n'
fi
# Download client JAR
printf '[2/5] Downloading client JAR...\n'
CLIENT_JAR="$VERSIONS_DIR/$VERSION.jar"
if [[ ! -f $CLIENT_JAR ]]; then
  CLIENT_URL=$("$JSON_PROC" -r '.downloads.client.url' <"$VERSION_MANIFEST")
  printf '  Downloading from Mojang servers...\n'
  download_file "$CLIENT_URL" "$CLIENT_JAR"
else
  printf '  Client JAR already exists\n'
fi
# Download assets
printf '[3/5] Downloading game assets...\n'
ASSET_INDEX=$("$JSON_PROC" -r '.assetIndex.id' <"$VERSION_MANIFEST")
ASSET_INDEX_URL=$("$JSON_PROC" -r '.assetIndex.url' <"$VERSION_MANIFEST")
ASSET_INDEX_FILE="$ASSETS_DIR/indexes/$ASSET_INDEX.json"
ensure_dir "$ASSETS_DIR/indexes"
ensure_dir "$ASSETS_DIR/objects"
if [[ ! -f $ASSET_INDEX_FILE ]]; then
  printf '  Downloading asset index...\n'
  download_file "$ASSET_INDEX_URL" "$ASSET_INDEX_FILE"
fi
# Download individual assets
printf '  Downloading asset objects...\n'
ASSET_COUNT=$("$JSON_PROC" -r '.objects | length' <"$ASSET_INDEX_FILE")
printf '  Total assets: %s\n' "$ASSET_COUNT"
# Create temporary file for aria2c input
ASSET_INPUT_FILE=$(mktemp) || { printf 'Failed to create temp file\n'; exit 1; }
trap 'rm -f "$ASSET_INPUT_FILE"' EXIT
"$JSON_PROC" -r '.objects[] | .hash' <"$ASSET_INDEX_FILE" | while read -r hash; do
  HASH_PREFIX="${hash:0:2}"
  ASSET_FILE="$ASSETS_DIR/objects/$HASH_PREFIX/$hash"
  if [[ ! -f $ASSET_FILE ]]; then
    ensure_dir "$ASSETS_DIR/objects/$HASH_PREFIX" >&2
    printf 'https://resources.download.minecraft.net/%s/%s\n' "$HASH_PREFIX" "$hash"
    printf '  dir=%s/objects/%s\n' "$ASSETS_DIR" "$HASH_PREFIX"
    printf '  out=%s\n' "$hash"
  fi
done >>"$ASSET_INPUT_FILE"
# Download missing assets with aria2c
if [[ -f $ASSET_INPUT_FILE ]] && [[ -s $ASSET_INPUT_FILE ]]; then
  if ! has aria2c; then
    printf '  Warning: aria2c not found, assets download may be slow\n'
    "$JSON_PROC" -r '.objects[] | .hash' <"$ASSET_INDEX_FILE" | while read -r hash; do
      HASH_PREFIX="${hash:0:2}"
      ASSET_FILE="$ASSETS_DIR/objects/$HASH_PREFIX/$hash"
      if [[ ! -f $ASSET_FILE ]]; then
        download_file "https://resources.download.minecraft.net/$HASH_PREFIX/$hash" "$ASSET_FILE"
      fi
    done
  else
    aria2c --input-file="$ASSET_INPUT_FILE" --check-certificate=false
  fi
  rm -f "$ASSET_INPUT_FILE"
else
  printf '  All assets already downloaded\n'
  rm -f "$ASSET_INPUT_FILE"
fi
# Download libraries
printf '[4/5] Downloading libraries...\n'
CLASSPATH="$CLIENT_JAR"
# Extract all library info in a single JSON parse (major performance improvement)
# Format: allowed|lib_path|lib_url|native_path|native_url
"$JSON_PROC" -r '.libraries[] |
  (
    if (.rules // []) | length > 0 then
      (.rules | map(select(.action == "allow") |
        (.os.name // "any") as $os |
        if $os == "any" or $os == "linux" then true else false end
      ) | any)
    else true end
  ) as $allowed |
  if $allowed then
    [
      "1",
      (.downloads.artifact.path // ""),
      (.downloads.artifact.url // ""),
      (.downloads.classifiers["natives-linux"].path // ""),
      (.downloads.classifiers["natives-linux"].url // "")
    ] | join("|")
  else empty end
' <"$VERSION_MANIFEST" | while IFS='|' read -r allowed lib_path lib_url native_path native_url; do
  # Process artifact
  if [[ -n $lib_url ]] && [[ -n $lib_path ]]; then
    LIB_FILE="$LIBRARIES_DIR/$lib_path"
    if [[ ! -f $LIB_FILE ]]; then
      ensure_dir "$(dirname "$LIB_FILE")"
      printf '  Downloading %s...\n' "$(basename "$lib_path")"
      download_file "$lib_url" "$LIB_FILE"
    fi
    CLASSPATH="$CLASSPATH:$LIB_FILE"
  fi
  # Process natives if present
  if [[ -n $native_url ]] && [[ -n $native_path ]]; then
    NATIVE_FILE="$LIBRARIES_DIR/$native_path"
    if [[ ! -f $NATIVE_FILE ]]; then
      ensure_dir "$(dirname "$NATIVE_FILE")"
      printf '  Downloading native %s...\n' "$(basename "$native_path")"
      download_file "$native_url" "$NATIVE_FILE"
    fi
    # Extract natives
    extract_natives "$NATIVE_FILE" "$NATIVES_DIR"
  fi
done
# Launch game
printf '[5/5] Launching Minecraft...\n'
# Get main class
MAIN_CLASS=$("$JSON_PROC" -r '.mainClass' <"$VERSION_MANIFEST")
# Build JVM arguments
JVM_ARGS=$("$JSON_PROC" -r '.arguments.jvm[]? // empty' <"$VERSION_MANIFEST" | grep -v '^\$' || echo "")
# Detect RAM and calculate memory allocation
XMS=$(get_client_xms_gb)
XMX=$(get_client_xmx_gb)
# Default JVM flags if not in manifest
if [[ -z $JVM_ARGS ]]; then
  JVM_ARGS="-Djava.library.path=$NATIVES_DIR -Dminecraft.launcher.brand=mc-client -Dminecraft.launcher.version=1.0"
fi
# Game arguments
GAME_ARGS=$("$JSON_PROC" -r '.arguments.game[]? // .minecraftArguments? // empty' <"$VERSION_MANIFEST" | tr '\n' ' ')
# Replace argument variables
GAME_ARGS="${GAME_ARGS//\$\{auth_player_name\}/$USERNAME}"
GAME_ARGS="${GAME_ARGS//\$\{version_name\}/$VERSION}"
GAME_ARGS="${GAME_ARGS//\$\{game_directory\}/$MC_DIR}"
GAME_ARGS="${GAME_ARGS//\$\{assets_root\}/$ASSETS_DIR}"
GAME_ARGS="${GAME_ARGS//\$\{assets_index_name\}/$ASSET_INDEX}"
GAME_ARGS="${GAME_ARGS//\$\{auth_uuid\}/00000000-0000-0000-0000-000000000000}"
GAME_ARGS="${GAME_ARGS//\$\{auth_access_token\}/0}"
GAME_ARGS="${GAME_ARGS//\$\{user_type\}/legacy}"
GAME_ARGS="${GAME_ARGS//\$\{version_type\}/release}"
printf '\n'
printf 'Starting Minecraft %s...\n' "$VERSION"
printf '\n'
# Enable detailed exception messages for better debugging
JAVA_OPTS="-XX:+ShowCodeDetailsInExceptionMessages"
# Launch the game
java \
  -Xms"${XMS}"G \
  -Xmx"${XMX}"G \
  "$JAVA_OPTS" \
  -XX:+UnlockExperimentalVMOptions \
  -XX:+UseG1GC \
  -XX:G1NewSizePercent=20 \
  -XX:G1ReservePercent=20 \
  -XX:MaxGCPauseMillis=50 \
  -XX:G1HeapRegionSize=32M \
  -Djava.library.path="$NATIVES_DIR" \
  -Dminecraft.launcher.brand=mc-client \
  -Dminecraft.launcher.version=1.0 \
  -cp "$CLASSPATH" \
  "$MAIN_CLASS" \
  "$GAME_ARGS"
