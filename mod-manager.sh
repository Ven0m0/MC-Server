#!/usr/bin/env bash
# mod-manager.sh: Minecraft mod manager inspired by Ferium
# Supports downloading mods from Modrinth, CurseForge, and GitHub

# Source common functions
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

init_strict_mode

# Get JSON processor
JSON_PROC=$(get_json_processor) || exit 1

# Configuration
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mod-manager"
PROFILES_DIR="$CONFIG_DIR/profiles"
CURRENT_PROFILE="$CONFIG_DIR/current_profile"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_info() {
    echo -e "${YELLOW}→${NC} $1"
}

# Ensure config directories exist
ensure_dir "$CONFIG_DIR"
ensure_dir "$PROFILES_DIR"

# Profile management
create_profile() {
    local name="$1"
    local mc_version="$2"
    local mod_loader="$3"
    local output_dir="$4"

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
        local mc_version=$(cat "$profile" | $JSON_PROC -r '.mc_version')
        local mod_loader=$(cat "$profile" | $JSON_PROC -r '.mod_loader')
        local mod_count=$(cat "$profile" | $JSON_PROC -r '.mods | length')

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

# Mod operations
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

    # Get profile details
    local mc_version=$(cat "$profile_file" | $JSON_PROC -r '.mc_version')
    local mod_loader=$(cat "$profile_file" | $JSON_PROC -r '.mod_loader')

    # Check if mod already exists
    local exists=$(cat "$profile_file" | $JSON_PROC -r --arg id "$project_id" '.mods[] | select(.id == $id) | .id')
    if [[ -n "$exists" ]]; then
        print_error "Mod '$title' is already in the profile"
        return 1
    fi

    # Add mod to profile
    local temp_file=$(mktemp)
    cat "$profile_file" | $JSON_PROC \
        --arg id "$project_id" \
        --arg slug "$slug" \
        --arg title "$title" \
        '.mods += [{
            "source": "modrinth",
            "id": $id,
            "slug": $slug,
            "title": $title
        }]' > "$temp_file"
    mv "$temp_file" "$profile_file"

    print_success "Added '$title' to profile"
}

add_curseforge_mod() {
    local project_id="$1"
    local profile_file=$(get_current_profile) || return 1

    print_header "Adding CurseForge mod: $project_id"

    # Check if mod already exists
    local exists=$(cat "$profile_file" | $JSON_PROC -r --arg id "$project_id" '.mods[] | select(.id == $id) | .id')
    if [[ -n "$exists" ]]; then
        print_error "Mod with ID '$project_id' is already in the profile"
        return 1
    fi

    # Add mod to profile (CurseForge API requires API key, so we store minimal info)
    local temp_file=$(mktemp)
    cat "$profile_file" | $JSON_PROC \
        --arg id "$project_id" \
        '.mods += [{
            "source": "curseforge",
            "id": $id,
            "title": "CurseForge Mod " + $id
        }]' > "$temp_file"
    mv "$temp_file" "$profile_file"

    print_success "Added CurseForge mod (ID: $project_id) to profile"
    print_info "Note: CurseForge downloads require an API key"
}

list_mods() {
    local profile_file=$(get_current_profile) || return 1
    local profile_name=$(basename "$profile_file" .json)

    print_header "Mods in profile '$profile_name':"

    local mod_count=$(cat "$profile_file" | $JSON_PROC -r '.mods | length')

    if [[ $mod_count -eq 0 ]]; then
        print_info "No mods in profile. Add mods with: $0 add"
        return
    fi

    cat "$profile_file" | $JSON_PROC -r '.mods[] | "[\(.source)] \(.title) (\(.slug // .id))"' | \
    while IFS= read -r line; do
        echo "  $line"
    done
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
        print_error "No compatible version found for Minecraft $mc_version with $mod_loader"
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

upgrade_all() {
    local profile_file=$(get_current_profile) || return 1

    print_header "Upgrading all mods..."

    local mc_version=$(cat "$profile_file" | $JSON_PROC -r '.mc_version')
    local mod_loader=$(cat "$profile_file" | $JSON_PROC -r '.mod_loader')
    local output_dir=$(cat "$profile_file" | $JSON_PROC -r '.output_dir')

    # Clean output directory
    if [[ -d "$output_dir" ]]; then
        print_info "Cleaning output directory..."
        rm -f "$output_dir"/*.jar
    fi

    ensure_dir "$output_dir"

    local total=$(cat "$profile_file" | $JSON_PROC -r '.mods | length')
    local count=0

    cat "$profile_file" | $JSON_PROC -c '.mods[]' | while IFS= read -r mod; do
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

remove_mod() {
    local identifier="$1"
    local profile_file=$(get_current_profile) || return 1

    if [[ -z "$identifier" ]]; then
        print_error "Usage: $0 remove <slug|id>"
        return 1
    fi

    # Remove mod by slug or id
    local temp_file=$(mktemp)
    local removed=$(cat "$profile_file" | $JSON_PROC -r \
        --arg id "$identifier" \
        '.mods[] | select(.slug == $id or .id == $id) | .title')

    if [[ -z "$removed" ]]; then
        print_error "Mod '$identifier' not found in profile"
        return 1
    fi

    cat "$profile_file" | $JSON_PROC \
        --arg id "$identifier" \
        '.mods |= map(select(.slug != $id and .id != $id))' > "$temp_file"
    mv "$temp_file" "$profile_file"

    print_success "Removed '$removed' from profile"
}

# Command handling
show_help() {
    cat <<EOF
Mod Manager - Minecraft mod management tool inspired by Ferium

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

    Information:
        help                  Show this help message

EXAMPLES:
    # Create a profile
    $0 profile create fabric-mods 1.21.6 fabric ./mods

    # Add mods from Modrinth
    $0 add modrinth sodium
    $0 add modrinth lithium
    $0 add modrinth iris

    # Download all mods
    $0 upgrade

    # List mods in profile
    $0 list

    # Remove a mod
    $0 remove sodium

ENVIRONMENT:
    XDG_CONFIG_HOME   Config directory (default: ~/.config)

CONFIGURATION:
    Profiles are stored in: $CONFIG_DIR/profiles/
EOF
}

# Main command dispatcher
COMMAND="${1:-}"

case "$COMMAND" in
    profile)
        SUBCOMMAND="${2:-}"
        case "$SUBCOMMAND" in
            create)
                create_profile "$3" "$4" "$5" "$6"
                ;;
            list)
                list_profiles
                ;;
            switch)
                switch_profile "$3"
                ;;
            *)
                print_error "Unknown profile command: $SUBCOMMAND"
                echo "Use: profile [create|list|switch]"
                exit 1
                ;;
        esac
        ;;
    add)
        SOURCE="${2:-}"
        case "$SOURCE" in
            modrinth)
                add_modrinth_mod "$3"
                ;;
            curseforge)
                add_curseforge_mod "$3"
                ;;
            *)
                print_error "Unknown source: $SOURCE"
                echo "Use: add [modrinth|curseforge] <identifier>"
                exit 1
                ;;
        esac
        ;;
    list)
        list_mods
        ;;
    remove)
        remove_mod "$2"
        ;;
    upgrade)
        upgrade_all
        ;;
    help|--help|-h)
        show_help
        ;;
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
