#!/usr/bin/env bash
# mcctl.sh: Paper/Spigot server management tool
# Integrated from: https://github.com/Kraftland/mcctl
#
# Original Author: Kimiblock (https://github.com/Kimiblock/mcctl)
# Original Version: v1.6-stable
# License: GPL-3.0 (inherited from upstream)
#
# This is a modernized integration that follows the MC-Server repository's
# code standards while preserving the core functionality of the original mcctl.

# Source common library
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=config/versions.sh
source "${SCRIPT_DIR}/config/versions.sh"

# Version
MCCTL_VERSION="2.1.0-integrated"

# Get latest git tag from repository
get_latest_tag(){
  local repo_url="$1"

  # Try GitHub API first (much faster, no clone needed)
  if [[ $repo_url == *"github.com"* ]]; then
    local api_url="${repo_url/github.com/api.github.com\/repos}"
    api_url="${api_url%.git}/releases/latest"
    local tag
    tag=$(curl -fsSL "$api_url" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null)
    if [[ -n $tag ]]; then
      printf '%s' "$tag"
      return 0
    fi
  fi

  # Fallback to git ls-remote only (no clone needed)
  local tag
  tag=$(git ls-remote --tags --sort=v:refname "$repo_url" 2>/dev/null | tail -1 | sed 's/.*\///' | sed 's/\^{}//')
  if [[ -n $tag ]]; then
    printf '%s' "$tag"
    return 0
  fi

  return 1
}

# Get download URLs for various components
get_url(){
  local component="$1"
  local version="${2:-}"
  local build="${3:-}"
  local url=""

  case "$component" in
    eula)
      url="https://account.mojang.com/documents/minecraft_eula"
      ;;
    viaversion)
      local tag
      tag=$(get_latest_tag "https://github.com/ViaVersion/ViaVersion.git" || echo "5.0.0")
      url="https://github.com/ViaVersion/ViaVersion/releases/latest/download/ViaVersion-${tag}.jar"
      ;;
    viabackwards)
      local tag
      tag=$(get_latest_tag "https://github.com/ViaVersion/ViaBackwards.git" || echo "5.0.0")
      url="https://github.com/ViaVersion/ViaBackwards/releases/latest/download/ViaBackwards-${tag}.jar"
      ;;
    multilogin)
      url="https://github.com/CaaMoe/MultiLogin/releases/latest/download/MultiLogin-Bukkit.jar"
      ;;
    buildtools)
      # BuildTools only available via Jenkins - pin to stable build
      url="https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar"
      ;;
    floodgate)
      # Use GitHub releases instead of Jenkins builds
      url="https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"
      ;;
    geyser)
      # Use GitHub releases instead of Jenkins builds
      url="https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot"
      ;;
    paper)
      [[ -z $version || -z $build ]] && {
        print_error "Paper requires version and build number"
        return 1
      }
      url="https://papermc.io/api/v2/projects/paper/versions/${version}/builds/${build}/downloads/paper-${version}-${build}.jar"
      ;;
    protocollib)
      # Use GitHub releases instead of Jenkins
      url="https://github.com/dmulloy2/ProtocolLib/releases/latest/download/ProtocolLib.jar"
      ;;
    vault)
      url="https://github.com/MilkBowl/Vault/releases/latest/download/Vault.jar"
      ;;
    luckperms)
      url="https://download.luckperms.net/1564/bukkit/loader/LuckPerms-Bukkit-${LUCKPERMS_VERSION}.jar"
      ;;
    griefprevention)
      url="https://github.com/TechFortress/GriefPrevention/releases/latest/download/GriefPrevention.jar"
      ;;
    freedomchat)
      url="https://cdn.modrinth.com/data/MubyTbnA/versions/v${FREEDOMCHAT_VERSION}/FreedomChat-${FREEDOMCHAT_VERSION}.jar"
      ;;
    deluxemenus)
      url="https://github.com/HelpChat/DeluxeMenus/releases/latest/download/DeluxeMenus.jar"
      ;;
    noencryption)
      local tag
      tag=$(get_latest_tag "https://github.com/Doclic/NoEncryption.git" || echo "1.0.0")
      url="https://github.com/Doclic/NoEncryption/releases/latest/download/NoEncryption-${tag}.jar"
      ;;
    craftgui)
      local tag
      tag=$(get_latest_tag "https://github.com/Fireflyest/CraftGUI.git" || echo "1.0.0")
      local version_num
      version_num=$(echo "$tag" | cut -c 2-)
      url="https://github.com/Fireflyest/CraftGUI/releases/download/${tag}/CraftGUI-${version_num}.jar"
      ;;
    globalmarket)
      local tag
      tag=$(get_latest_tag "https://github.com/Fireflyest/GlobalMarket.git" || echo "1.0.0")
      local version_num
      version_num=$(echo "$tag" | cut -c 2-)
      url="https://github.com/Fireflyest/GlobalMarket/releases/download/${tag}/GlobalMarket-${version_num}.jar"
      ;;
    *)
      print_error "Unknown component: $component"
      return 1
      ;;
  esac

  printf '%s' "$url"
}

# Get latest Paper build for version
get_latest_paper_build(){
  local version="$1"
  local json_proc
  json_proc=$(get_json_processor) || return 1

  local builds_json
  builds_json=$(curl -fsSL "https://papermc.io/api/v2/projects/paper/versions/${version}")

  printf '%s' "$builds_json" | "$json_proc" -r '.builds[-1]'
}

# Build/Download Paper server
build_paper(){
  local version="${1:-1.21.1}"

  print_header "Building Paper ${version}"

  local build
  build=$(get_latest_paper_build "$version") || {
    print_error "Failed to get Paper build info"
    return 1
  }

  print_info "Latest build: ${build}"

  local url
  url=$(get_url paper "$version" "$build") || return 1

  local output="paper-${version}-${build}.jar"
  download_file "$url" "$output" || {
    print_error "Download failed"
    return 1
  }

  [[ -f server.jar ]] && mv server.jar server.jar.bak
  ln -sf "$output" server.jar

  print_success "Paper ${version} build ${build} installed"
}

# Build Spigot server
build_spigot(){
  local version="${1:-latest}"

  print_header "Building Spigot ${version}"

  has_command java || {
    print_error "Java not found"
    return 1
  }

  local url
  url=$(get_url buildtools) || return 1

  download_file "$url" "BuildTools.jar" || return 1

  print_info "Running BuildTools (this may take several minutes)..."

  if [[ $version == "latest" ]]; then
    java -jar BuildTools.jar --compile spigot
  else
    java -jar BuildTools.jar --compile spigot --rev "$version"
  fi

  local spigot_jar
  spigot_jar=$(find . -maxdepth 1 -name "spigot-*.jar" -type f | head -1)

  [[ -z $spigot_jar ]] && {
    print_error "Build failed - no jar found"
    return 1
  }

  [[ -f server.jar ]] && mv server.jar server.jar.bak
  ln -sf "$spigot_jar" server.jar

  print_success "Spigot built successfully"
}

# Update plugin
update_plugin(){
  local plugin="$1"
  local plugins_dir="${2:-${SCRIPT_DIR}/plugins}"

  mkdir -p "$plugins_dir"

  print_header "Updating ${plugin}"

  local url
  url=$(get_url "$plugin") || return 1

  local jar_name
  case "$plugin" in
    viaversion) jar_name="ViaVersion.jar" ;;
    viabackwards) jar_name="ViaBackwards.jar" ;;
    multilogin) jar_name="MultiLogin.jar" ;;
    floodgate) jar_name="floodgate-spigot.jar" ;;
    geyser) jar_name="Geyser-Spigot.jar" ;;
    protocollib) jar_name="ProtocolLib.jar" ;;
    vault) jar_name="Vault.jar" ;;
    luckperms) jar_name="LuckPerms.jar" ;;
    griefprevention) jar_name="GriefPrevention.jar" ;;
    freedomchat) jar_name="FreedomChat.jar" ;;
    deluxemenus) jar_name="DeluxeMenus.jar" ;;
    noencryption) jar_name="NoEncryption.jar" ;;
    craftgui) jar_name="CraftGUI.jar" ;;
    globalmarket) jar_name="GlobalMarket.jar" ;;
    *) jar_name="${plugin}.jar" ;;
  esac

  local output="${plugins_dir}/${jar_name}"
  [[ -f $output ]] && mv "$output" "${output}.bak"

  download_file "$url" "$output" || {
    print_error "Failed to download ${plugin}"
    [[ -f ${output}.bak ]] && mv "${output}.bak" "$output"
    return 1
  }

  print_success "${plugin} updated"
}

# Accept EULA
accept_eula(){
  print_info "Accepting EULA..."
  printf 'eula=true\n' >"${SCRIPT_DIR}/eula.txt"
  print_success "EULA accepted"
}

# Initialize server directory
init_server(){
  print_header "Initializing server directory"

  mkdir -p "$SCRIPT_DIR"/{plugins,world,logs,backups}

  accept_eula

  print_success "Server initialized"
}

# Update all plugins
update_all_plugins(){
  local plugins=(
    viaversion
    viabackwards
    protocollib
    vault
  )

  print_header "Updating all plugins"

  # Parallel downloads with xargs (network-bound operations benefit from parallelism)
  if has_command xargs; then
    printf '%s\n' "${plugins[@]}" | xargs -P 4 -I {} bash -c '
      source "'"${SCRIPT_DIR}"'/lib/common.sh"
      plugins_dir="'"${SCRIPT_DIR}"'/plugins"
      '"$(declare -f get_url download_file print_header print_info print_success print_error)"'
      '"$(declare -f update_plugin)"'
      update_plugin "{}" "$plugins_dir" || print_error "Failed: {}"
    '
  else
    # Fallback to sequential if xargs not available
    for plugin in "${plugins[@]}"; do
      update_plugin "$plugin" || print_error "Failed to update ${plugin}"
    done
  fi

  print_success "All plugins updated"
}

# Show usage
show_usage(){
  cat <<EOF
mcctl - Paper/Spigot Server Management Tool
Version: ${MCCTL_VERSION}

USAGE:
    $0 <COMMAND> [OPTIONS]

COMMANDS:
    Server Management:
        build-paper [version]       Build/download Paper server (default: 1.21.1)
        build-spigot [version]      Build Spigot server (default: latest)
        init                        Initialize server directory
        accept-eula                 Accept Minecraft EULA

    Plugin Management:
        update <plugin>             Update specific plugin
        update-all                  Update all common plugins

    Available Plugins:
        viaversion, viabackwards, multilogin, floodgate, geyser,
        protocollib, vault, luckperms, griefprevention, freedomchat,
        deluxemenus, noencryption, craftgui, globalmarket

    Info:
        version                     Show version
        help                        Show this help

EXAMPLES:
    $0 build-paper 1.21.1
    $0 build-spigot latest
    $0 update geyser
    $0 update-all
    $0 init

NOTES:
    - This tool is integrated from the Kraftland/mcctl project
    - Designed to work alongside Fabric server tools
    - Use tools/backup.sh for backups and snapshots
    - Use tools/systemd-service.sh for systemd integration
EOF
}

case "${1:-help}" in build-paper) build_paper "${2:-1.21.1}" ;; build-spigot) build_spigot "${2:-latest}" ;; init) init_server ;; accept-eula) accept_eula ;; update)
  [[ -z ${2:-} ]] && {
    print_error "Plugin name required"
    printf "Available plugins: viaversion, viabackwards, multilogin, floodgate, geyser, protocollib, vault, luckperms, griefprevention, freedomchat, deluxemenus, noencryption, craftgui, globalmarket\n"
    exit 1
  }
  update_plugin "$2"
  ;;
update-all) update_all_plugins ;; version)
  print_header "mcctl version ${MCCTL_VERSION}"
  printf "Integrated from: https://github.com/Kraftland/mcctl\n"
  ;;
help | --help | -h) show_usage ;; *)
  print_error "Unknown command: $1"
  show_usage
  exit 1
  ;;
esac
