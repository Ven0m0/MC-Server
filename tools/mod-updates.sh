#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C
IFS=$'\n\t'
s=${BASH_SOURCE[0]}
[[ $s != /* ]] && s=$PWD/$s
cd -P -- "${s%/*}/.."
has(){ command -v -- "$1" &>/dev/null; }
date(){
  local x="${1:-%d/%m/%y-%R}"
  printf "%($x)T\n" '-1'
}
# mod-updates.sh: Fabric server and mod management system
# shellcheck source=lib/common.sh
source "${PWD}/lib/common.sh"

MC_REPACK_CONFIG="${HOME}/.config/mc-repack.toml"
JSON_PROC=$(get_json_processor) || exit 1

# ============================================================================
# FABRIC SERVER INSTALLATION
# ============================================================================
install_fabric(){
  local mc_version="${1:-}"
  local loader="${2:-}"

  print_header "Installing Fabric Server"

  # Fetch versions
  print_info "Fetching Minecraft and Fabric versions..."

  if [[ -z $mc_version ]]; then
    mc_version=$(fetch_url "https://meta.fabricmc.net/v2/versions/game" | "$JSON_PROC" -r '[.[] | select(.stable == true)][0].version')
  fi

  local fabric_installer
  fabric_installer=$(fetch_url "https://meta.fabricmc.net/v2/versions/installer" | "$JSON_PROC" -r '.[0].version')

  if [[ -z $loader ]]; then
    loader=$(fetch_url "https://meta.fabricmc.net/v2/versions/loader" | "$JSON_PROC" -r '[.[] | select(.stable==true)][0].version')
  fi

  print_info "Minecraft: $mc_version | Fabric installer: $fabric_installer | Loader: $loader"

  # Download installer
  print_info "Downloading Fabric installer..."
  download_file "https://maven.fabricmc.net/net/fabricmc/fabric-installer/${fabric_installer}/fabric-installer-${fabric_installer}.jar" "fabric-installer.jar"

  # Install Fabric server
  print_info "Installing Fabric server..."
  java -jar fabric-installer.jar server -mcversion "$mc_version" -downloadMinecraft

  # Cleanup
  rm -f fabric-installer.jar
  print_success "Fabric server setup complete!"
}

# ============================================================================
# SERVER SETUP
# ============================================================================
setup_server(){
  print_header "Setting up server environment"
  printf 'eula=true\n' >eula.txt
  [[ -d world ]] && sudo chown -R "$(id -un):$(id -gn)" world &>/dev/null || :
  sudo chmod -R 755 ./*.sh &>/dev/null || :
  print_success "Server setup complete"
}
setup_ferium(){
  # Create a profile for your server (e.g., Minecraft 1.20.1, Fabric)
  ferium profile create --name server-mods --game-version 1.21.5 --mod-loader fabric
  # Add your mods (You can use IDs or names, Ferium searches for them)
  ferium add fabric-api
  ferium add lithium
  ferium add phosphor
  # TODO: extend
}

# ============================================================================
# MC-REPACK CONFIGURATION
# ============================================================================
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

# ============================================================================
# MOD MANAGEMENT
# ============================================================================
ferium_update(){
  has ferium || {
    print_error "Ferium not installed"
    return 1
  }
  print_header "Running Ferium update"
  ferium scan && ferium upgrade
  [[ -d mods/.old ]] && rm -rf mods/.old
  print_success "Ferium update complete"
}

repack_mods(){
  has mc-repack || {
    print_error "mc-repack not installed"
    return 1
  }
  print_header "Repacking mods"
  local mods_src="${1:-$HOME/Documents/MC/Minecraft/mods}"
  local mods_dst="${2:-$HOME/Documents/MC/Minecraft/mods-$(date %Y%m%d_%H%M)}"
  [[ ! -d $mods_src ]] && {
    print_error "Source not found: $mods_src"
    return 1
  }
  mc-repack jars -c "$MC_REPACK_CONFIG" --in "$mods_src" --out "$mods_dst"
  print_success "Repack complete: $mods_dst"
}
update_geyserconnect(){
  print_header "Updating GeyserConnect"
  local dest_dir="${1:-$HOME/Documents/MC/Minecraft/config/Geyser-Fabric/extensions}"
  local url="https://download.geysermc.org/v2/projects/geyserconnect/versions/latest/builds/latest/downloads/geyserconnect"
  mkdir -p "$dest_dir"
  local jar="$dest_dir/GeyserConnect.jar"
  [[ -f $jar ]] && mv "$jar" "$jar.bak"
  download_file "$url" "$jar"
  has mc-repack && {
    print_info "Repacking GeyserConnect..."
    local tmp="$jar.tmp"
    mv "$jar" "$tmp"
    mc-repack jars -c "$MC_REPACK_CONFIG" --in "$tmp" --out "$jar"
    rm -f "$tmp"
  }
  print_success "GeyserConnect updated"
}

# ============================================================================
# FULL UPDATE WORKFLOW
# ============================================================================
full_update(){
  print_header "Running full update"
  setup_server
  setup_mc_repack
  has ferium && {
    ferium_update
    printf '\n'
  }
  has mc-repack && {
    repack_mods
    printf '\n'
  }
  [[ -d "$HOME/Documents/MC/Minecraft/config/Geyser-Fabric" ]] && {
    update_geyserconnect
    printf '\n'
  }
  print_success "Full update complete!"
}

# ============================================================================
# HELP
# ============================================================================
show_help(){
  cat <<EOF
Fabric Server & Mod Management System

USAGE:
    $0 <COMMAND> [OPTIONS]

COMMANDS:
    install-fabric [version] [loader]  Install Fabric server
                                       Version & loader optional (uses latest stable)
    setup                              Setup server (EULA, permissions)
    setup-repack                       Configure mc-repack
    ferium                             Run ferium update
    repack [src] [dst]                 Repack mods with mc-repack
    geyser [dir]                       Update GeyserConnect extension
    full-update                        Run complete update workflow
    help                               Show this help

EXAMPLES:
    $0 install-fabric                  # Install latest stable Fabric
    $0 install-fabric 1.21.5           # Install specific version
    $0 install-fabric 1.21.5 0.16.10   # Install with specific loader
    $0 full-update                     # Run full mod update workflow
    $0 ferium                          # Update mods via ferium
    $0 repack ./mods ./mods-repacked   # Repack mods

ENVIRONMENT VARIABLES:
    MC_VERSION     Minecraft version (default: latest stable)
    LOADER         Fabric loader version (default: latest stable)
EOF
}

# ============================================================================
# MAIN
# ============================================================================
case "${1:-}" in
  install-fabric | install | fabric) install_fabric "${2:-}" "${3:-}" ;;
  setup) setup_server ;;
  setup-repack) setup_mc_repack ;;
  ferium) ferium_update ;;
  repack) repack_mods "${2:-}" "${3:-}" ;;
  geyser | geyserconnect) update_geyserconnect "${2:-}" ;;
  full-update) full_update ;;
  help | --help | -h) show_help ;;
  *)
    [[ -z ${1:-} ]] && show_help || {
      print_error "Unknown command: $1"
      show_help
    }
    exit 1
    ;;
esac
