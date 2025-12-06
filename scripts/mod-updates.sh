#!/usr/bin/env bash
# mod-updates.sh: Simplified mod update system

# Initialize strict mode
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C
user="${SUDO_USER:-${USER:-$(id -un)}}"
export HOME="/home/${user}"
SHELL="$(command -v bash 2>/dev/null || echo '/usr/bin/bash')"

# Check if command exists
has_command(){ command -v "$1" &>/dev/null; }

# Detect JSON processor (prefer jaq over jq)
get_json_processor(){
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

# Download file with aria2c or curl fallback
download_file(){
  local url="$1" output="$2" connections="${3:-8}"
  has_command curl && {
    curl -fsL -H "Accept-Encoding: identity" -H "Accept-Language: en" -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4.212 Safari/537.36" -o "$output" "$url"
    return
  }
  has_command wget && {
    wget -qO "$output" "$url"
    return
  }
  echo "Error: No download tool found (aria2c, curl, or wget)" >&2; return 1
}

# Output formatting helpers
print_header(){ printf '\033[0;34m==>\033[0m %s\n' "$1"; }
print_success(){ printf '\033[0;32m✓\033[0m %s\n' "$1"; }
print_error(){ printf '\033[0;31m✗\033[0m %s\n' "$1" >&2; }
print_info(){ printf '\033[1;33m→\033[0m %s\n' "$1"; }

# Configuration
MC_REPACK_CONFIG="${HOME}/.config/mc-repack.toml"

# Get JSON processor
JSON_PROC=$(get_json_processor) || exit 1

# Setup server environment
setup_server(){
  print_header "Setting up server environment"
  echo "eula=true" >eula.txt
  [[ -d world ]] && sudo chown -R "$(id -un):$(id -gn)" world 2>/dev/null || :
  sudo chmod -R 755 ./*.sh 2>/dev/null || :
  print_success "Server setup complete"
}

# Configure mc-repack
setup_mc_repack(){
  print_header "Configuring mc-repack"
  mkdir -p "$(dirname "$MC_REPACK_CONFIG")"
  cat >"$MC_REPACK_CONFIG" <<'EOF'
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
ferium_update(){
  has_command ferium || {
    print_error "Ferium not installed"
    return 1
  }
  print_header "Running Ferium update"
  ferium scan && ferium upgrade
  [[ -d mods/.old ]] && rm -rf mods/.old
  print_success "Ferium update complete"
}

# Repack mods
repack_mods(){
  has_command mc-repack || {
    print_error "mc-repack not installed"
    return 1
  }
  print_header "Repacking mods"
  local mods_src="${1:-$HOME/Documents/MC/Minecraft/mods}"
  local mods_dst="${2:-$HOME/Documents/MC/Minecraft/mods-$(printf '%(%Y%m%d_%H%M)T' -1)}"
  [[ ! -d $mods_src ]] && {
    print_error "Source not found: $mods_src"
    return 1
  }
  mc-repack jars -c "$MC_REPACK_CONFIG" --in "$mods_src" --out "$mods_dst"
  print_success "Repack complete: $mods_dst"
}

# Update GeyserConnect
update_geyserconnect(){
  print_header "Updating GeyserConnect"
  local dest_dir="${1:-$HOME/Documents/MC/Minecraft/config/Geyser-Fabric/extensions}"
  local url="https://download.geysermc.org/v2/projects/geyserconnect/versions/latest/builds/latest/downloads/geyserconnect"
  mkdir -p "$dest_dir"
  local jar="$dest_dir/GeyserConnect.jar"
  [[ -f $jar ]] && mv "$jar" "$jar.bak"
  download_file "$url" "$jar"
  has_command mc-repack && {
    print_info "Repacking GeyserConnect..."
    local tmp="$jar.tmp"
    mv "$jar" "$tmp"
    mc-repack jars -c "$MC_REPACK_CONFIG" --in "$tmp" --out "$jar"
    rm -f "$tmp"
  }
  print_success "GeyserConnect updated"
}

# Full update workflow
full_update(){
  print_header "Running full update"
  setup_server
  setup_mc_repack
  has_command ferium && {
    ferium_update
    echo ""
  }
  has_command mc-repack && {
    repack_mods
    echo ""
  }
  [[ -d "$HOME/Documents/MC/Minecraft/config/Geyser-Fabric" ]] && {
    update_geyserconnect
    echo ""
  }
  print_success "Full update complete!"
}

# Show help
show_help(){
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
setup) setup_server ;;
setup-repack) setup_mc_repack ;;
ferium) ferium_update ;;
repack) repack_mods "$2" "$3" ;;
geyser | geyserconnect) update_geyserconnect "$2" ;;
full-update) full_update ;;
help | --help | -h) show_help ;;
*)
  [[ -z $1 ]] && show_help || {
    print_error "Unknown command: $1"
    show_help
  }
  exit 1
  ;;
esac
