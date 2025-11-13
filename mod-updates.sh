#!/usr/bin/env bash
# mod-updates.sh: Unified Minecraft mod manager and update system
# Combines mod-manager.sh and Updates.sh functionality

# Source common functions
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

init_strict_mode
LC_ALL=C
shopt -s nullglob globstar

# Get JSON processor
JSON_PROC=$(get_json_processor) || exit 1

# ─── Configuration ──────────────────────────────────────────────────────────────

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mod-manager"
PROFILES_DIR="$CONFIG_DIR/profiles"
CURRENT_PROFILE="$CONFIG_DIR/current_profile"
MC_REPACK_CONFIG="${HOME}/.config/mc-repack.toml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ─── Helper Functions ───────────────────────────────────────────────────────────

print_header() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1" >&2; }
print_info() { echo -e "${YELLOW}→${NC} $1"; }

# Ensure config directories exist
ensure_dir "$CONFIG_DIR"
ensure_dir "$PROFILES_DIR"

# ─── System Setup Functions ─────────────────────────────────────────────────────

setup_server() {
    print_header "Setting up Minecraft server environment"
    local workdir=$(get_script_dir)
    cd "$workdir" || exit 1

    # Accept EULA
    echo "eula=true" > eula.txt
    print_success "EULA accepted"

    # Fix ownership and permissions
    if [[ -d "$workdir/world" ]]; then
        print_info "Fixing ownership of server files..."
        sudo chown -R "$(id -un):$(id -gn)" "$workdir/world" 2>/dev/null || true
    fi

    sudo chmod -R 755 "$workdir"/*.sh 2>/dev/null || true
    print_success "Ownership and permissions fixed"
}

setup_mc_repack() {
    print_header "Configuring mc-repack"

    touch "$MC_REPACK_CONFIG"

    # Remove old TOML sections using sd if available
    if command -v sd &>/dev/null; then
        sd -s '^\[(json|nbt|png|toml|jar)\](\n(?!\[).*)*' '' "$MC_REPACK_CONFIG" 2>/dev/null || true
    fi

    # Append optimized configuration
    cat >> "$MC_REPACK_CONFIG" <<'EOF'
[json]
remove_underscored = true
[nbt]
use_zopfli = false
[png]
use_zopfli = true
[toml]
strip_strings = true
[jar]
keep_dirs = false
use_zopfli = true
EOF

    print_success "mc-repack.toml configured"
}

# ─── Profile Management ─────────────────────────────────────────────────────────

create_profile() {
    local name="$1" mc_version="$2" mod_loader="$3" output_dir="$4"

    if [[ -z "$name" ]] || [[ -z "$mc_version" ]] || [[ -z "$mod_loader" ]] || [[ -z "$output_dir" ]]; then
        print_error "Usage: $0 profile create <name> <mc_version> <mod_loader> <output_dir>"
        print_info "Example: $0 profile create my-mods 1.21.6 fabric ./mods"
        return 1
    fi

    local profile_file="$PROFILES_DIR/$name.json"

    if [[ -f "$profile_file" ]]; then
        print_error "Profile '$name' already exists"
        return 1
    fi

    # Create profile JSON
    cat > "$profile_file" <<EOF
{
  "name": "$name",
  "mc_version": "$mc_version",
  "mod_loader": "$mod_loader",
  "output_dir": "$output_dir",
  "mods": []
}
EOF

    echo "$name" > "$CURRENT_PROFILE"
    print_success "Created profile '$name'"
    print_info "Minecraft: $mc_version | Loader: $mod_loader"
    print_info "Output directory: $output_dir"
}

list_profiles() {
    local current=""
    [[ -f "$CURRENT_PROFILE" ]] && current=$(cat "$CURRENT_PROFILE")

    print_header "Available Profiles:"

    if [[ ! -d "$PROFILES_DIR" ]] || [[ -z "$(ls -A "$PROFILES_DIR" 2>/dev/null)" ]]; then
        print_info "No profiles found. Create one with: $0 profile create"
        return
    fi

    for profile in "$PROFILES_DIR"/*.json; do
        [[ ! -f "$profile" ]] && continue
        local name=$(basename "$profile" .json)
        local mc_version=$($JSON_PROC -r '.mc_version' < "$profile")
        local mod_loader=$($JSON_PROC -r '.mod_loader' < "$profile")
        local mod_count=$($JSON_PROC -r '.mods | length' < "$profile")

        if [[ "$name" == "$current" ]]; then
            echo -e "${GREEN}* $name${NC} (MC $mc_version, $mod_loader, $mod_count mods)"
        else
            echo "  $name (MC $mc_version, $mod_loader, $mod_count mods)"
        fi
    done
}

switch_profile() {
    local name="$1"
    local profile_file="$PROFILES_DIR/$name.json"

    if [[ ! -f "$profile_file" ]]; then
        print_error "Profile '$name' not found"
        return 1
    fi

    echo "$name" > "$CURRENT_PROFILE"
    print_success "Switched to profile '$name'"
}

get_current_profile() {
    if [[ ! -f "$CURRENT_PROFILE" ]]; then
        print_error "No active profile. Create one with: $0 profile create"
        return 1
    fi

    local name=$(cat "$CURRENT_PROFILE")
    local profile_file="$PROFILES_DIR/$name.json"

    if [[ ! -f "$profile_file" ]]; then
        print_error "Current profile '$name' not found"
        return 1
    fi

    echo "$profile_file"
}

# ─── Mod Operations ─────────────────────────────────────────────────────────────

add_modrinth_mod() {
    local slug="$1"
    local profile_file=$(get_current_profile) || return 1

    print_header "Adding Modrinth mod: $slug"

    # Fetch project info
    local project_info=$(fetch_url "https://api.modrinth.com/v2/project/$slug")

    if [[ -z "$project_info" ]]; then
        print_error "Failed to fetch mod info for '$slug'"
        return 1
    fi

    local project_id=$(echo "$project_info" | $JSON_PROC -r '.id')
    local title=$(echo "$project_info" | $JSON_PROC -r '.title')

    # Check if mod already exists
    local exists=$($JSON_PROC -r --arg id "$project_id" '.mods[] | select(.id == $id) | .id' < "$profile_file")

    if [[ -n "$exists" ]]; then
        print_error "Mod '$title' is already in the profile"
        return 1
    fi

    # Add mod to profile
    local temp_file=$(mktemp)
    $JSON_PROC \
        --arg id "$project_id" \
        --arg slug "$slug" \
        --arg title "$title" \
        '.mods += [{
            "source": "modrinth",
            "id": $id,
            "slug": $slug,
            "title": $title
        }]' < "$profile_file" > "$temp_file"

    mv "$temp_file" "$profile_file"
    print_success "Added '$title' to profile"
}

add_curseforge_mod() {
    local project_id="$1"
    local profile_file=$(get_current_profile) || return 1

    print_header "Adding CurseForge mod: $project_id"

    # Check if mod already exists
    local exists=$($JSON_PROC -r --arg id "$project_id" '.mods[] | select(.id == $id) | .id' < "$profile_file")

    if [[ -n "$exists" ]]; then
        print_error "Mod with ID '$project_id' is already in the profile"
        return 1
    fi

    # Add mod to profile
    local temp_file=$(mktemp)
    $JSON_PROC \
        --arg id "$project_id" \
        '.mods += [{
            "source": "curseforge",
            "id": $id,
            "title": "CurseForge Mod " + $id
        }]' < "$profile_file" > "$temp_file"

    mv "$temp_file" "$profile_file"
    print_success "Added CurseForge mod (ID: $project_id) to profile"
    print_info "Note: CurseForge downloads require an API key"
}

list_mods() {
    local profile_file=$(get_current_profile) || return 1
    local profile_name=$(basename "$profile_file" .json)

    print_header "Mods in profile '$profile_name':"

    local mod_count=$($JSON_PROC -r '.mods | length' < "$profile_file")

    if [[ $mod_count -eq 0 ]]; then
        print_info "No mods in profile. Add mods with: $0 add"
        return
    fi

    $JSON_PROC -r '.mods[] | "[\(.source)] \(.title) (\(.slug // .id))"' < "$profile_file" | \
    while IFS= read -r line; do
        echo "  $line"
    done
}

remove_mod() {
    local identifier="$1"
    local profile_file=$(get_current_profile) || return 1

    if [[ -z "$identifier" ]]; then
        print_error "Usage: $0 remove <slug|id>"
        return 1
    fi

    # Remove mod by slug or id
    local temp_file=$(mktemp)
    local removed=$($JSON_PROC -r \
        --arg id "$identifier" \
        '.mods[] | select(.slug == $id or .id == $id) | .title' < "$profile_file")

    if [[ -z "$removed" ]]; then
        print_error "Mod '$identifier' not found in profile"
        return 1
    fi

    $JSON_PROC \
        --arg id "$identifier" \
        '.mods |= map(select(.slug != $id and .id != $id))' < "$profile_file" > "$temp_file"

    mv "$temp_file" "$profile_file"
    print_success "Removed '$removed' from profile"
}

download_modrinth_mod() {
    local project_id="$1"
    local mc_version="$2"
    local mod_loader="$3"
    local output_dir="$4"

    # Fetch versions
    local versions=$(fetch_url "https://api.modrinth.com/v2/project/$project_id/version")

    # Filter compatible version
    local version_file=$(echo "$versions" | $JSON_PROC -r \
        --arg mc "$mc_version" \
        --arg loader "$mod_loader" \
        'map(select(
            (.game_versions | index($mc)) and
            (.loaders | map(ascii_downcase) | index($loader))
        )) | .[0]')

    if [[ "$version_file" == "null" ]] || [[ -z "$version_file" ]]; then
        print_error "No compatible version found for MC $mc_version with $mod_loader"
        return 1
    fi

    local download_url=$(echo "$version_file" | $JSON_PROC -r '.files[0].url')
    local filename=$(echo "$version_file" | $JSON_PROC -r '.files[0].filename')

    if [[ -z "$download_url" ]]; then
        print_error "Failed to get download URL"
        return 1
    fi

    ensure_dir "$output_dir"
    local output_file="$output_dir/$filename"

    if [[ -f "$output_file" ]]; then
        print_info "Already downloaded: $filename"
        return 0
    fi

    print_info "Downloading $filename..."
    download_file "$download_url" "$output_file"
    print_success "Downloaded $filename"
}

# ─── Update Functions ───────────────────────────────────────────────────────────

upgrade_all() {
    local profile_file=$(get_current_profile) || return 1

    print_header "Upgrading all mods..."

    local mc_version=$($JSON_PROC -r '.mc_version' < "$profile_file")
    local mod_loader=$($JSON_PROC -r '.mod_loader' < "$profile_file")
    local output_dir=$($JSON_PROC -r '.output_dir' < "$profile_file")

    # Clean output directory
    if [[ -d "$output_dir" ]]; then
        print_info "Cleaning output directory..."
        rm -f "$output_dir"/*.jar
    fi

    ensure_dir "$output_dir"

    local total=$($JSON_PROC -r '.mods | length' < "$profile_file")
    local count=0

    $JSON_PROC -c '.mods[]' < "$profile_file" | while IFS= read -r mod; do
        ((count++))
        local source=$(echo "$mod" | $JSON_PROC -r '.source')
        local title=$(echo "$mod" | $JSON_PROC -r '.title')
        local id=$(echo "$mod" | $JSON_PROC -r '.id')

        echo ""
        print_info "[$count/$total] $title"

        case "$source" in
            modrinth)
                download_modrinth_mod "$id" "$mc_version" "$mod_loader" "$output_dir"
                ;;
            curseforge)
                print_error "CurseForge downloads not yet implemented (requires API key)"
                ;;
            *)
                print_error "Unknown source: $source"
                ;;
        esac
    done

    echo ""
    print_success "Upgrade complete!"
}

ferium_update() {
    print_header "Running Ferium mod update..."

    if ! has_command ferium; then
        print_error "Ferium not installed. Skipping ferium update."
        print_info "Install from: https://github.com/gorilla-devs/ferium"
        return 1
    fi

    ferium scan && ferium upgrade
    print_success "Ferium update complete"

    # Clean old mod backups
    if [[ -d mods/.old ]]; then
        print_info "Cleaning old mod backups..."
        rm -f mods/.old/*
        print_success "Cleanup complete"
    fi
}

repack_mods() {
    print_header "Repacking mods with mc-repack..."

    if ! has_command mc-repack; then
        print_error "mc-repack not installed. Skipping repack."
        print_info "Install from: https://github.com/jascotty2/mc-repack"
        return 1
    fi

    local timestamp=$(date +%Y-%m-%d_%H-%M)
    local mods_src="${1:-$HOME/Documents/MC/Minecraft/mods}"
    local mods_dst="${2:-$HOME/Documents/MC/Minecraft/mods-$timestamp}"

    if [[ ! -d "$mods_src" ]]; then
        print_error "Mods source directory not found: $mods_src"
        return 1
    fi

    print_info "Source: $mods_src"
    print_info "Destination: $mods_dst"

    mc-repack jars -c "$MC_REPACK_CONFIG" --in "$mods_src" --out "$mods_dst"
    print_success "Repack complete: $mods_dst"
}

update_geyserconnect() {
    print_header "Updating GeyserConnect..."

    local dest_dir="${1:-$HOME/Documents/MC/Minecraft/config/Geyser-Fabric/extensions}"
    local url="https://download.geysermc.org/v2/projects/geyserconnect/versions/latest/builds/latest/downloads/geyserconnect"

    ensure_dir "$dest_dir"

    local tmp_jar="$dest_dir/GeyserConnect2.jar"
    local final_jar="$dest_dir/GeyserConnect.jar"

    # Get aria2c options
    local aria2_opts=($(get_aria2c_opts_array) --allow-overwrite=true)

    print_info "Downloading latest GeyserConnect..."

    if aria2c "${aria2_opts[@]}" -o "$tmp_jar" "$url"; then
        print_success "Download complete"
    else
        print_error "Failed to download GeyserConnect"
        return 1
    fi

    # Backup existing JAR
    if [[ -f "$final_jar" ]]; then
        print_info "Backing up existing GeyserConnect.jar..."
        mv "$final_jar" "$final_jar.bak"
    fi

    # Repack if mc-repack is available
    if has_command mc-repack; then
        print_info "Repacking GeyserConnect..."
        mc-repack jars -c "$MC_REPACK_CONFIG" --in "$tmp_jar" --out "$final_jar"
        rm -f "$tmp_jar"
    else
        mv "$tmp_jar" "$final_jar"
    fi

    print_success "GeyserConnect updated: $final_jar"
}

# ─── Full Update Workflow ───────────────────────────────────────────────────────

full_update() {
    print_header "Running full update workflow..."
    echo ""

    # Setup environment
    setup_server
    setup_mc_repack
    echo ""

    # Update mods using ferium (if available)
    if has_command ferium; then
        ferium_update
        echo ""
    fi

    # Upgrade mods in current profile (if profile exists)
    if [[ -f "$CURRENT_PROFILE" ]]; then
        upgrade_all 2>/dev/null || true
        echo ""
    fi

    # Repack mods (if mc-repack available)
    if has_command mc-repack; then
        repack_mods
        echo ""
    fi

    # Update GeyserConnect (if applicable)
    if [[ -d "$HOME/Documents/MC/Minecraft/config/Geyser-Fabric" ]]; then
        update_geyserconnect
        echo ""
    fi

    print_success "Full update workflow complete!"
}

# ─── Command Help ───────────────────────────────────────────────────────────────

show_help() {
    cat <<EOF
Mod Updates - Unified Minecraft mod manager and update system

USAGE:
    $0 <COMMAND> [OPTIONS]

COMMANDS:
    Profile Management:
        profile create <name> <mc_version> <loader> <output_dir>
                              Create a new profile
        profile list          List all profiles
        profile switch <name> Switch to a different profile

    Mod Management:
        add modrinth <slug>   Add a mod from Modrinth
        add curseforge <id>   Add a mod from CurseForge
        list                  List all mods in current profile
        remove <slug|id>      Remove a mod from current profile
        upgrade               Download/update all mods in current profile

    System Setup:
        setup                 Setup server environment (EULA, permissions)
        setup-repack          Configure mc-repack settings

    Update Operations:
        ferium                Run ferium scan and upgrade
        repack [src] [dst]    Repack mods using mc-repack
        geyserconnect [dir]   Update GeyserConnect extension
        full-update           Run complete update workflow

    Information:
        help                  Show this help message

EXAMPLES:
    # Setup and full update
    $0 full-update

    # Create a profile and add mods
    $0 profile create fabric-mods 1.21.6 fabric ./mods
    $0 add modrinth sodium
    $0 add modrinth lithium
    $0 upgrade

    # Repack mods
    $0 repack ./mods ./mods-repacked

ENVIRONMENT:
    XDG_CONFIG_HOME   Config directory (default: ~/.config)

CONFIGURATION:
    Profiles: $CONFIG_DIR/profiles/
    mc-repack: $MC_REPACK_CONFIG
EOF
}

# ─── Main Command Dispatcher ────────────────────────────────────────────────────

COMMAND="${1:-}"

case "$COMMAND" in
    profile)
        SUBCOMMAND="${2:-}"
        case "$SUBCOMMAND" in
            create) create_profile "$3" "$4" "$5" "$6";;
            list) list_profiles;;
            switch) switch_profile "$3";;
            *) print_error "Unknown profile command: $SUBCOMMAND"; echo "Use: profile [create|list|switch]"; exit 1;;
        esac
        ;;
    add)
        SOURCE="${2:-}"
        case "$SOURCE" in
            modrinth) add_modrinth_mod "$3";;
            curseforge) add_curseforge_mod "$3";;
            *) print_error "Unknown source: $SOURCE"; echo "Use: add [modrinth|curseforge] <identifier>"; exit 1;;
        esac
        ;;
    list) list_mods;;
    remove) remove_mod "$2";;
    upgrade) upgrade_all;;
    setup) setup_server;;
    setup-repack) setup_mc_repack;;
    ferium) ferium_update;;
    repack) repack_mods "$2" "$3";;
    geyserconnect) update_geyserconnect "$2";;
    full-update) full_update;;
    help|--help|-h) show_help;;
    *)
        if [[ -z "$COMMAND" ]]; then
            show_help
        else
            print_error "Unknown command: $COMMAND"
            echo ""
            show_help
        fi
        exit 1
        ;;
esac
