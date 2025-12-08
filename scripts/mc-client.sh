#!/usr/bin/env bash
# mc-client.sh: Minecraft client launcher with automatic version management
# Based on https://github.com/Sushkyn/mc-launcher

# Initialize strict mode
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C
user="${SUDO_USER:-${USER:-$(id -un)}}"
export HOME="/home/${user}"
SHELL="$(command -v bash 2>/dev/null || echo '/usr/bin/bash')"

# Check if command exists
has_command() { command -v "$1" &>/dev/null; }

# Check if required commands are available
check_dependencies() {
  local missing=()
  for cmd in "$@"; do
    has_command "$cmd" || missing+=("$cmd")
  done
  ((${#missing[@]})) && {
    echo "Error: Missing required dependencies: ${missing[*]}" >&2
    echo "Please install them before continuing." >&2
    return 1
  }
}

# Detect JSON processor (prefer jaq over jq)
get_json_processor() {
  has_command jaq && {
    echo "jaq"
    return
  }
  has_command jq && {
    echo "jq"
    return
  }
  echo "Error: No JSON processor found. Please install jq or jaq." >&2
  return 1
}

# Fetch URL to stdout
fetch_url() {
  local url="$1"
  has_command curl && {
    curl -fsSL -H "Accept-Encoding: identity" -H "Accept-Language: en" -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4.212 Safari/537.36" "$url"
    return
  }
  has_command wget && {
    wget -qO- "$url"
    return
  }
  echo "Error: No download tool found (aria2c, curl, or wget)" >&2
  return 1
}

# Download file with aria2c or curl fallback
download_file() {
  local url="$1" output="$2" connections="${3:-8}"
  has_command curl && {
    curl -fsL -H "Accept-Encoding: identity" -H "Accept-Language: en" -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4.212 Safari/537.36" -o "$output" "$url"
    return
  }
  has_command wget && {
    wget -qO "$output" "$url"
    return
  }
  echo "Error: No download tool found (aria2c, curl, or wget)" >&2
  return 1
}

# Create directory if it doesn't exist
ensure_dir() { [[ ! -d $1 ]] && mkdir -p "$1" || return 0; }

# Extract natives from JAR file
extract_natives() {
  local jar_file="$1" dest_dir="$2"
  ensure_dir "$dest_dir"
  unzip -q -o "$jar_file" -d "$dest_dir" 2>/dev/null || :
  rm -rf "${dest_dir}/META-INF"
}

# Calculate total RAM in GB
get_total_ram_gb() { awk '/MemTotal/ {printf "%.0f\n",$2/1024/1024}' /proc/meminfo 2>/dev/null; }

# Calculate client memory allocation
get_client_xms_gb() {
  local total_ram
  total_ram=$(get_total_ram_gb)
  local xms=$((total_ram / 4))
  ((xms < 1)) && xms=1
  echo "$xms"
}

get_client_xmx_gb() {
  local total_ram
  total_ram=$(get_total_ram_gb)
  local xmx=$((total_ram / 2))
  ((xmx < 2)) && xmx=2
  echo "$xmx"
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
  echo "Usage: $0 <VERSION> [USERNAME]"
  echo "Example: $0 1.21.6 MyPlayer"
  echo ""
  echo "Environment variables:"
  echo "  MC_DIR    : Minecraft directory (default: ~/.minecraft)"
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

echo "[*] Minecraft Client Launcher"
echo "→ Version: $VERSION"
echo "→ Username: $USERNAME"
echo "→ Directory: $MC_DIR"
echo ""

# Download version manifest
echo "[1/5] Fetching version manifest..."
VERSION_MANIFEST="$VERSIONS_DIR/version.json"

if [[ ! -f $VERSION_MANIFEST ]]; then
  echo "  Downloading version list..."
  VERSION_LIST=$(fetch_url "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
  VERSION_URL=$(echo "$VERSION_LIST" | "$JSON_PROC" -r ".versions[] | select(.id == \"$VERSION\") | .url")

  if [[ -z $VERSION_URL ]]; then
    echo "Error: Version $VERSION not found" >&2
    exit 1
  fi

  echo "  Downloading version manifest..."
  fetch_url "$VERSION_URL" >"$VERSION_MANIFEST"
else
  echo "  Using cached version manifest"
fi

# Download client JAR
echo "[2/5] Downloading client JAR..."
CLIENT_JAR="$VERSIONS_DIR/$VERSION.jar"

if [[ ! -f $CLIENT_JAR ]]; then
  CLIENT_URL=$("$JSON_PROC" -r '.downloads.client.url' <"$VERSION_MANIFEST")
  echo "  Downloading from Mojang servers..."
  download_file "$CLIENT_URL" "$CLIENT_JAR"
else
  echo "  Client JAR already exists"
fi

# Download assets
echo "[3/5] Downloading game assets..."
ASSET_INDEX=$("$JSON_PROC" -r '.assetIndex.id' <"$VERSION_MANIFEST")
ASSET_INDEX_URL=$("$JSON_PROC" -r '.assetIndex.url' <"$VERSION_MANIFEST")
ASSET_INDEX_FILE="$ASSETS_DIR/indexes/$ASSET_INDEX.json"

ensure_dir "$ASSETS_DIR/indexes"
ensure_dir "$ASSETS_DIR/objects"

if [[ ! -f $ASSET_INDEX_FILE ]]; then
  echo "  Downloading asset index..."
  download_file "$ASSET_INDEX_URL" "$ASSET_INDEX_FILE"
fi

# Download individual assets
echo "  Downloading asset objects..."
ASSET_COUNT=$("$JSON_PROC" -r '.objects | length' <"$ASSET_INDEX_FILE")
echo "  Total assets: $ASSET_COUNT"

# Create temporary file for aria2c input
ASSET_INPUT_FILE="/tmp/mc-assets-$$.txt"
"$JSON_PROC" -r '.objects[] | .hash' <"$ASSET_INDEX_FILE" | while read -r hash; do
  HASH_PREFIX="${hash:0:2}"
  ASSET_FILE="$ASSETS_DIR/objects/$HASH_PREFIX/$hash"

  if [[ ! -f $ASSET_FILE ]]; then
    ensure_dir "$ASSETS_DIR/objects/$HASH_PREFIX"
    echo "https://resources.download.minecraft.net/$HASH_PREFIX/$hash" >>"$ASSET_INPUT_FILE"
    echo "  dir=$ASSETS_DIR/objects/$HASH_PREFIX" >>"$ASSET_INPUT_FILE"
    echo "  out=$hash" >>"$ASSET_INPUT_FILE"
  fi
done

# Download missing assets with aria2c
if [[ -f $ASSET_INPUT_FILE ]] && [[ -s $ASSET_INPUT_FILE ]]; then
  if ! has_command aria2c; then
    echo "  Warning: aria2c not found, assets download may be slow"
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
  echo "  All assets already downloaded"
  rm -f "$ASSET_INPUT_FILE"
fi

# Download libraries
echo "[4/5] Downloading libraries..."
CLASSPATH="$CLIENT_JAR"

# Extract all library info in a single JSON parse (major performance improvement)
# Format: allowed|lib_path|lib_url|native_path|native_url
"$JSON_PROC" -r '.libraries[] |
  (
    if (.rules // []) | length > 0 then
      (.rules | map(select(.action == "allow") | (.os.name // "any") as $os | if $os == "any" or $os == "linux" then true else false end) | any)
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
      echo "  Downloading $(basename "$lib_path")..."
      download_file "$lib_url" "$LIB_FILE"
    fi

    CLASSPATH="$CLASSPATH:$LIB_FILE"
  fi

  # Process natives if present
  if [[ -n $native_url ]] && [[ -n $native_path ]]; then
    NATIVE_FILE="$LIBRARIES_DIR/$native_path"

    if [[ ! -f $NATIVE_FILE ]]; then
      ensure_dir "$(dirname "$NATIVE_FILE")"
      echo "  Downloading native $(basename "$native_path")..."
      download_file "$native_url" "$NATIVE_FILE"
    fi

    # Extract natives
    extract_natives "$NATIVE_FILE" "$NATIVES_DIR"
  fi
done

# Launch game
echo "[5/5] Launching Minecraft..."

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

echo ""
echo "Starting Minecraft $VERSION..."
echo ""

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
