#!/usr/bin/env bash
# mod-updates.sh: Unified Minecraft mod manager and update system

# Source common functions (SCRIPT_DIR is auto-initialized)
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

init_strict_mode

# ─── Configuration ──────────────────────────────────────────────────────────────

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mod-manager"
PROFILES_DIR="$CONFIG_DIR/profiles"
CURRENT_PROFILE="$CONFIG_DIR/current_profile"
MC_REPACK_CONFIG="${HOME}/.config/mc-repack.toml"

# Get JSON processor
JSON_PROC=$(get_json_processor) || exit 1

# Ensure config directories exist
ensure_dir "$CONFIG_DIR"
ensure_dir "$PROFILES_DIR"

# ─── System Setup ───────────────────────────────────────────────────────────────

setup_server(){
    print_header "Setting up Minecraft server environment"
    # Accept EULA
    echo "eula=true" > eula.txt
    print_success "EULA accepted"
    # Fix ownership and permissions
    if [[ -d world ]]; then
        print_info "Fixing ownership of server files..."
        sudo chown -R "$(id -un):$(id -gn)" world 2>/dev/null || :
    fi
    sudo chmod -R 755 ./*.sh 2>/dev/null || :
    print_success "Ownership and permissions fixed"
}

setup_mc_repack(){
    print_header "Configuring mc-repack"
    touch "$MC_REPACK_CONFIG"
    # Remove old TOML sections
    if has_command sd; then
        sd -s '^\[(json|nbt|png|toml|jar)\](\n(?!\[).*)*' '' "$MC_REPACK_CONFIG" 2>/dev/null || :
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

create_profile(){
    local name="$1" mc_version="$2" mod_loader="$3" output_dir="$4"
    if [[ -z "$name" ]] || [[ -z "$mc_version" ]] || [[ -z "$mod_loader" ]] || [[ -z "$output_dir" ]]; then
        print_error "Usage: $0 profile create <name> <mc_version> <mod_loader> <output_dir>"
        print_info "Example: $0 profile create my-mods 1.21.6 fabric ./mods"; return 1
    fi
    local profile_file="$PROFILES_DIR/$name.json"
    [[ -f "$profile_file" ]] && { print_error "Profile '$name' already exists"; return 1; }
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
    print_info "Minecraft: $mc_version | Loader: $mod_loader | Output: $output_dir"
}

list_profiles(){
    local current=""
    [[ -f "$CURRENT_PROFILE" ]] && current=$(cat "$CURRENT_PROFILE")
    print_header "Available Profiles:"
    if [[ ! -d "$PROFILES_DIR" ]] || [[ -z "$(ls -A "$PROFILES_DIR" 2>/dev/null)" ]]; then
        print_info "No profiles found. Create one with: $0 profile create"; return
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

switch_profile(){
    local name="$1"
    local profile_file="$PROFILES_DIR/$name.json"
    if [[ ! -f "$profile_file" ]]; then
        print_error "Profile '$name' not found"; return 1
    fi
    echo "$name" > "$CURRENT_PROFILE"
    print_success "Switched to profile '$name'"
}

get_current_profile(){
    if [[ ! -f "$CURRENT_PROFILE" ]]; then
        print_error "No active profile. Create one with: $0 profile create"; return 1
    fi
    local name=$(cat "$CURRENT_PROFILE")
    local profile_file="$PROFILES_DIR/$name.json"
    if [[ ! -f "$profile_file" ]]; then
        print_error "Current profile '$name' not found"; return 1
    fi
    echo "$profile_file"
}

# ─── Mod Operations ─────────────────────────────────────────────────────────────

add_modrinth_mod(){
    local slug="$1"
    local profile_file=$(get_current_profile) || return 1
    print_header "Adding Modrinth mod: $slug"
    local project_info=$(fetch_url "https://api.modrinth.com/v2/project/$slug")
    [[ -z "$project_info" ]] && { print_error "Failed to fetch mod info for '$slug'"; return 1; }
    local project_id=$(echo "$project_info" | $JSON_PROC -r '.id')
    local title=$(echo "$project_info" | $JSON_PROC -r '.title')
    local exists=$($JSON_PROC -r --arg id "$project_id" '.mods[] | select(.id == $id) | .id' < "$profile_file")
    [[ -n "$exists" ]] && { print_error "Mod '$title' is already in the profile"; return 1; }
    local temp_file=$(mktemp)
    $JSON_PROC \
        --arg id "$project_id" \
        --arg slug "$slug" \
        --arg title "$title" \
        '.mods += [{"source": "modrinth", "id": $id, "slug": $slug, "title": $title}]' \
        < "$profile_file" > "$temp_file"

    mv "$temp_file" "$profile_file"
    print_success "Added '$title' to profile"
}

add_curseforge_mod(){
    local project_id="$1"
    local profile_file=$(get_current_profile) || return 1
    print_header "Adding CurseForge mod: $project_id"
    local exists=$($JSON_PROC -r --arg id "$project_id" '.mods[] | select(.id == $id) | .id' < "$profile_file")
    [[ -n "$exists" ]] && { print_error "Mod with ID '$project_id' already in profile"; return 1; }
    local temp_file=$(mktemp)
    $JSON_PROC \
        --arg id "$project_id" \
        '.mods += [{"source": "curseforge", "id": $id, "title": "CurseForge Mod " + $id}]' \
        < "$profile_file" > "$temp_file"
    mv "$temp_file" "$profile_file"
    print_success "Added CurseForge mod (ID: $project_id)"
    print_info "Note: CurseForge downloads require an API key"
}

list_mods(){
    local profile_file=$(get_current_profile) || return 1
    local profile_name=$(basename "$profile_file" .json)
    print_header "Mods in profile '$profile_name':"
    local mod_count=$($JSON_PROC -r '.mods | length' < "$profile_file")
    [[ $mod_count -eq 0 ]] && { print_info "No mods in profile. Add with: $0 add"; return; }
    $JSON_PROC -r '.mods[] | "[\(.source)] \(.title) (\(.slug // .id))"' < "$profile_file" | \
    while IFS= read -r line; do echo "  $line"; done
}

remove_mod(){
    local identifier="$1"
    local profile_file=$(get_current_profile) || return 1
    [[ -z "$identifier" ]] && { print_error "Usage: $0 remove <slug|id>"; return 1; }
    local removed=$($JSON_PROC -r --arg id "$identifier" \
        '.mods[] | select(.slug == $id or .id == $id) | .title' < "$profile_file")
    [[ -z "$removed" ]] && { print_error "Mod '$identifier' not found"; return 1; }
    local temp_file=$(mktemp)
    $JSON_PROC --arg id "$identifier" \
        '.mods |= map(select(.slug != $id and .id != $id))' < "$profile_file" > "$temp_file"
    mv "$temp_file" "$profile_file"
    print_success "Removed '$removed'"
}

download_modrinth_mod(){
    local project_id="$1" mc_version="$2" mod_loader="$3" output_dir="$4"
    local versions=$(fetch_url "https://api.modrinth.com/v2/project/$project_id/version")
    local version_file=$(echo "$versions" | $JSON_PROC -r \
        --arg mc "$mc_version" \
        --arg loader "$mod_loader" \
        'map(select((.game_versions | index($mc)) and (.loaders | map(ascii_downcase) | index($loader)))) | .[0]')
    if [[ "$version_file" == "null" ]] || [[ -z "$version_file" ]]; then
        print_error "No compatible version for MC $mc_version with $mod_loader"; return 1
    fi
    local download_url=$(echo "$version_file" | $JSON_PROC -r '.files[0].url')
    local filename=$(echo "$version_file" | $JSON_PROC -r '.files[0].filename')
    [[ -z "$download_url" ]] && { print_error "Failed to get download URL"; return 1; }
    ensure_dir "$output_dir"
    local output_file="$output_dir/$filename"
    [[ -f "$output_file" ]] && { print_info "Already downloaded: $filename"; return 0; }
    print_info "Downloading $filename..."
    download_file "$download_url" "$output_file"
    print_success "Downloaded $filename"
}

upgrade_all(){
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
            modrinth) download_modrinth_mod "$id" "$mc_version" "$mod_loader" "$output_dir";;
            curseforge) print_error "CurseForge downloads not yet implemented";;
            *) print_error "Unknown source: $source";;
        esac
    done
    echo ""
    print_success "Upgrade complete!"
}

# ─── Update Operations ──────────────────────────────────────────────────────────

ferium_update(){
    print_header "Running Ferium mod update..."
    if ! has_command ferium; then
        print_error "Ferium not installed. Skipping."
        print_info "Install from: https://github.com/gorilla-devs/ferium"; return 1
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

repack_mods(){
    print_header "Repacking mods with mc-repack..."
    if ! has_command mc-repack; then
        print_error "mc-repack not installed. Skipping."
        print_info "Install from: https://github.com/jascotty2/mc-repack"; return 1
    fi
    local timestamp=$(date +%Y-%m-%d_%H-%M)
    local mods_src="${1:-$HOME/Documents/MC/Minecraft/mods}"
    local mods_dst="${2:-$HOME/Documents/MC/Minecraft/mods-$timestamp}"
    [[ ! -d "$mods_src" ]] && { print_error "Source not found: $mods_src"; return 1; }
    print_info "Source: $mods_src"
    print_info "Destination: $mods_dst"
    mc-repack jars -c "$MC_REPACK_CONFIG" --in "$mods_src" --out "$mods_dst"
    print_success "Repack complete: $mods_dst"
}

update_geyserconnect(){
    print_header "Updating GeyserConnect..."
    local dest_dir="${1:-$HOME/Documents/MC/Minecraft/config/Geyser-Fabric/extensions}"
    local url="https://download.geysermc.org/v2/projects/geyserconnect/versions/latest/builds/latest/downloads/geyserconnect"
    ensure_dir "$dest_dir"
    local tmp_jar="$dest_dir/GeyserConnect2.jar"
    local final_jar="$dest_dir/GeyserConnect.jar"
    print_info "Downloading latest GeyserConnect..."
    download_file "$url" "$tmp_jar" || { print_error "Download failed"; return 1; }
    print_success "Download complete"
    # Backup existing JAR
    [[ -f "$final_jar" ]] && { print_info "Backing up existing..."; mv "$final_jar" "$final_jar.bak"; }
    # Repack if available
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

full_update(){
    print_header "Running full update workflow..."
    echo ""
    setup_server
    setup_mc_repack
    echo ""
    has_command ferium && { ferium_update; echo ""; }
    [[ -f "$CURRENT_PROFILE" ]] && { upgrade_all 2>/dev/null || :; echo ""; }
    has_command mc-repack && { repack_mods; echo ""; }
    [[ -d "$HOME/Documents/MC/Minecraft/config/Geyser-Fabric" ]] && { update_geyserconnect; echo ""; }
    print_success "Full update workflow complete!"
}

# ─── Help ───────────────────────────────────────────────────────────────────────

show_help(){
    cat <<EOF
Mod Updates - Unified Minecraft mod manager and update system

USAGE:
    $0 <COMMAND> [OPTIONS]

COMMANDS:
    Profile Management:
        profile create <name> <mc_version> <loader> <output_dir>
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

    # Create profile and add mods
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
        esac;;
    add)
        SOURCE="${2:-}"
        case "$SOURCE" in
            modrinth) add_modrinth_mod "$3";;
            curseforge) add_curseforge_mod "$3";;
            *) print_error "Unknown source: $SOURCE"; echo "Use: add [modrinth|curseforge] <identifier>"; exit 1;;
        esac;;
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
        fi; exit 1;;
esac
