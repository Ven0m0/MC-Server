#!/usr/bin/env bash
# mod-updates.sh: Simplified mod update system

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

init_strict_mode

# Configuration
MC_REPACK_CONFIG="${HOME}/.config/mc-repack.toml"

# Get JSON processor
JSON_PROC=$(get_json_processor) || exit 1

# Setup server environment
setup_server() {
    print_header "Setting up server environment"
    echo "eula=true" > eula.txt
    [[ -d world ]] && sudo chown -R "$(id -un):$(id -gn)" world 2>/dev/null || :
    sudo chmod -R 755 ./*.sh 2>/dev/null || :
    print_success "Server setup complete"
}

# Configure mc-repack
setup_mc_repack() {
    print_header "Configuring mc-repack"
    mkdir -p "$(dirname "$MC_REPACK_CONFIG")"
    cat > "$MC_REPACK_CONFIG" <<'EOF'
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
    print_success "mc-repack configured"
}

# Update with Ferium
ferium_update() {
    if ! has_command ferium; then
        print_error "Ferium not installed"
        return 1
    fi
    print_header "Running Ferium update"
    ferium scan && ferium upgrade
    [[ -d mods/.old ]] && rm -rf mods/.old
    print_success "Ferium update complete"
}

# Repack mods
repack_mods() {
    if ! has_command mc-repack; then
        print_error "mc-repack not installed"
        return 1
    fi
    print_header "Repacking mods"
    local mods_src="${1:-$HOME/Documents/MC/Minecraft/mods}"
    local mods_dst="${2:-$HOME/Documents/MC/Minecraft/mods-$(date +%Y%m%d_%H%M)}"

    [[ ! -d "$mods_src" ]] && { print_error "Source not found: $mods_src"; return 1; }

    mc-repack jars -c "$MC_REPACK_CONFIG" --in "$mods_src" --out "$mods_dst"
    print_success "Repack complete: $mods_dst"
}

# Update GeyserConnect
update_geyserconnect() {
    print_header "Updating GeyserConnect"
    local dest_dir="${1:-$HOME/Documents/MC/Minecraft/config/Geyser-Fabric/extensions}"
    local url="https://download.geysermc.org/v2/projects/geyserconnect/versions/latest/builds/latest/downloads/geyserconnect"

    mkdir -p "$dest_dir"
    local jar="$dest_dir/GeyserConnect.jar"

    [[ -f "$jar" ]] && mv "$jar" "$jar.bak"

    download_file "$url" "$jar"

    if has_command mc-repack; then
        print_info "Repacking GeyserConnect..."
        local tmp="$jar.tmp"
        mv "$jar" "$tmp"
        mc-repack jars -c "$MC_REPACK_CONFIG" --in "$tmp" --out "$jar"
        rm -f "$tmp"
    fi

    print_success "GeyserConnect updated"
}

# Full update workflow
full_update() {
    print_header "Running full update"
    setup_server
    setup_mc_repack
    has_command ferium && { ferium_update; echo ""; }
    has_command mc-repack && { repack_mods; echo ""; }
    [[ -d "$HOME/Documents/MC/Minecraft/config/Geyser-Fabric" ]] && { update_geyserconnect; echo ""; }
    print_success "Full update complete!"
}

# Show help
show_help() {
    cat <<EOF
Mod Updates - Simplified mod update system

USAGE:
    $0 <COMMAND> [OPTIONS]

COMMANDS:
    setup              Setup server (EULA, permissions)
    setup-repack       Configure mc-repack
    ferium             Run ferium update
    repack [src] [dst] Repack mods with mc-repack
    geyser [dir]       Update GeyserConnect
    full-update        Run complete workflow
    help               Show this help

EXAMPLES:
    $0 full-update
    $0 ferium
    $0 repack ./mods ./mods-repacked
EOF
}

# Command dispatcher
case "${1:-}" in
    setup) setup_server;;
    setup-repack) setup_mc_repack;;
    ferium) ferium_update;;
    repack) repack_mods "$2" "$3";;
    geyser|geyserconnect) update_geyserconnect "$2";;
    full-update) full_update;;
    help|--help|-h) show_help;;
    *)
        [[ -z "$1" ]] && show_help || {
            print_error "Unknown command: $1"
            show_help
        }
        exit 1;;
esac
