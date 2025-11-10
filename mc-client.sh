#!/usr/bin/env bash
# mc-client.sh: Minecraft client launcher with automatic version management
# Based on https://github.com/Sushkyn/mc-launcher

# Source common functions
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

init_strict_mode

# Check dependencies
check_dependencies java unzip || exit 1

# Get JSON processor
JSON_PROC=$(get_json_processor) || exit 1

# Configuration
MC_DIR="${MC_DIR:-$HOME/.minecraft}"
VERSION="${1:-}"
USERNAME="${2:-Player}"

# Show usage if no version specified
if [[ -z "$VERSION" ]]; then
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

if [[ ! -f "$VERSION_MANIFEST" ]]; then
    echo "  Downloading version list..."
    VERSION_LIST=$(fetch_url "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
    VERSION_URL=$(echo "$VERSION_LIST" | $JSON_PROC -r ".versions[] | select(.id == \"$VERSION\") | .url")

    if [[ -z "$VERSION_URL" ]]; then
        echo "Error: Version $VERSION not found" >&2
        exit 1
    fi

    echo "  Downloading version manifest..."
    fetch_url "$VERSION_URL" > "$VERSION_MANIFEST"
else
    echo "  Using cached version manifest"
fi

# Download client JAR
echo "[2/5] Downloading client JAR..."
CLIENT_JAR="$VERSIONS_DIR/$VERSION.jar"

if [[ ! -f "$CLIENT_JAR" ]]; then
    CLIENT_URL=$(cat "$VERSION_MANIFEST" | $JSON_PROC -r '.downloads.client.url')
    echo "  Downloading from Mojang servers..."
    download_file "$CLIENT_URL" "$CLIENT_JAR"
else
    echo "  Client JAR already exists"
fi

# Download assets
echo "[3/5] Downloading game assets..."
ASSET_INDEX=$(cat "$VERSION_MANIFEST" | $JSON_PROC -r '.assetIndex.id')
ASSET_INDEX_URL=$(cat "$VERSION_MANIFEST" | $JSON_PROC -r '.assetIndex.url')
ASSET_INDEX_FILE="$ASSETS_DIR/indexes/$ASSET_INDEX.json"

ensure_dir "$ASSETS_DIR/indexes"
ensure_dir "$ASSETS_DIR/objects"

if [[ ! -f "$ASSET_INDEX_FILE" ]]; then
    echo "  Downloading asset index..."
    download_file "$ASSET_INDEX_URL" "$ASSET_INDEX_FILE"
fi

# Download individual assets
echo "  Downloading asset objects..."
ASSET_COUNT=$(cat "$ASSET_INDEX_FILE" | $JSON_PROC -r '.objects | length')
echo "  Total assets: $ASSET_COUNT"

# Create temporary file for aria2c input
ASSET_INPUT_FILE="/tmp/mc-assets-$$.txt"
cat "$ASSET_INDEX_FILE" | $JSON_PROC -r '.objects[] | .hash' | while read -r hash; do
    HASH_PREFIX="${hash:0:2}"
    ASSET_FILE="$ASSETS_DIR/objects/$HASH_PREFIX/$hash"

    if [[ ! -f "$ASSET_FILE" ]]; then
        ensure_dir "$ASSETS_DIR/objects/$HASH_PREFIX"
        echo "https://resources.download.minecraft.net/$HASH_PREFIX/$hash" >> "$ASSET_INPUT_FILE"
        echo "  dir=$ASSETS_DIR/objects/$HASH_PREFIX" >> "$ASSET_INPUT_FILE"
        echo "  out=$hash" >> "$ASSET_INPUT_FILE"
    fi
done

# Download missing assets with aria2c
if [[ -f "$ASSET_INPUT_FILE" ]] && [[ -s "$ASSET_INPUT_FILE" ]]; then
    if has_command aria2c; then
        echo "  Downloading missing assets with aria2c..."
        aria2c -x 16 -s 16 -j 16 -i "$ASSET_INPUT_FILE" --auto-file-renaming=false --allow-overwrite=true
    else
        echo "  Warning: aria2c not found, assets download may be slow"
        cat "$ASSET_INDEX_FILE" | $JSON_PROC -r '.objects[] | .hash' | while read -r hash; do
            HASH_PREFIX="${hash:0:2}"
            ASSET_FILE="$ASSETS_DIR/objects/$HASH_PREFIX/$hash"
            if [[ ! -f "$ASSET_FILE" ]]; then
                download_file "https://resources.download.minecraft.net/$HASH_PREFIX/$hash" "$ASSET_FILE"
            fi
        done
    fi
    rm -f "$ASSET_INPUT_FILE"
else
    echo "  All assets already downloaded"
    rm -f "$ASSET_INPUT_FILE"
fi

# Download libraries
echo "[4/5] Downloading libraries..."
CLASSPATH="$CLIENT_JAR"

cat "$VERSION_MANIFEST" | $JSON_PROC -c '.libraries[]' | while IFS= read -r library; do
    # Check if library applies to current OS
    RULES=$(echo "$library" | $JSON_PROC -r '.rules // [] | length')
    if [[ $RULES -gt 0 ]]; then
        ALLOWED=$(echo "$library" | $JSON_PROC -r '
            .rules | map(
                select(.action == "allow") |
                (.os.name // "any") as $os |
                if $os == "any" or $os == "linux" then true else false end
            ) | any
        ')
        if [[ "$ALLOWED" != "true" ]]; then
            continue
        fi
    fi

    # Get library download info
    LIB_PATH=$(echo "$library" | $JSON_PROC -r '.downloads.artifact.path // empty')
    LIB_URL=$(echo "$library" | $JSON_PROC -r '.downloads.artifact.url // empty')

    if [[ -n "$LIB_URL" ]] && [[ -n "$LIB_PATH" ]]; then
        LIB_FILE="$LIBRARIES_DIR/$LIB_PATH"

        if [[ ! -f "$LIB_FILE" ]]; then
            ensure_dir "$(dirname "$LIB_FILE")"
            echo "  Downloading $(basename "$LIB_PATH")..."
            download_file "$LIB_URL" "$LIB_FILE"
        fi

        CLASSPATH="$CLASSPATH:$LIB_FILE"
    fi

    # Download natives if present
    NATIVES=$(echo "$library" | $JSON_PROC -r '.downloads.classifiers // {} | keys | length')
    if [[ $NATIVES -gt 0 ]]; then
        NATIVE_KEY="natives-linux"
        NATIVE_PATH=$(echo "$library" | $JSON_PROC -r ".downloads.classifiers[\"$NATIVE_KEY\"].path // empty")
        NATIVE_URL=$(echo "$library" | $JSON_PROC -r ".downloads.classifiers[\"$NATIVE_KEY\"].url // empty")

        if [[ -n "$NATIVE_URL" ]] && [[ -n "$NATIVE_PATH" ]]; then
            NATIVE_FILE="$LIBRARIES_DIR/$NATIVE_PATH"

            if [[ ! -f "$NATIVE_FILE" ]]; then
                ensure_dir "$(dirname "$NATIVE_FILE")"
                echo "  Downloading native $(basename "$NATIVE_PATH")..."
                download_file "$NATIVE_URL" "$NATIVE_FILE"
            fi

            # Extract natives
            extract_natives "$NATIVE_FILE" "$NATIVES_DIR"
        fi
    fi
done

# Launch game
echo "[5/5] Launching Minecraft..."

# Get main class
MAIN_CLASS=$(cat "$VERSION_MANIFEST" | $JSON_PROC -r '.mainClass')

# Build JVM arguments
JVM_ARGS=$(cat "$VERSION_MANIFEST" | $JSON_PROC -r '.arguments.jvm[]? // empty' | grep -v '^\$' || echo "")

# Detect CPU cores and RAM
CPU_CORES=$(nproc 2>/dev/null || echo 4)
TOTAL_RAM=$(get_total_ram_gb)
XMS=$((TOTAL_RAM / 4))
XMX=$((TOTAL_RAM / 2))
(( XMS < 1 )) && XMS=1
(( XMX < 2 )) && XMX=2

# Default JVM flags if not in manifest
if [[ -z "$JVM_ARGS" ]]; then
    JVM_ARGS="-Djava.library.path=$NATIVES_DIR -Dminecraft.launcher.brand=mc-client -Dminecraft.launcher.version=1.0"
fi

# Game arguments
GAME_ARGS=$(cat "$VERSION_MANIFEST" | $JSON_PROC -r '.arguments.game[]? // .minecraftArguments? // empty' | tr '\n' ' ')

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

# Launch the game
java \
    -Xms${XMS}G \
    -Xmx${XMX}G \
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
    $GAME_ARGS
