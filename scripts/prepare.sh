#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C; IFS=$'\n\t'
s=${BASH_SOURCE[0]}; [[ $s != /* ]] && s=$PWD/$s; cd -P -- "${s%/*}/.."
has(){ command -v -- "$1" &>/dev/null; }
# prepare.sh: Prepare Minecraft server/client environment
# shellcheck source=lib/common.sh
source "${PWD}/lib/common.sh"
print_header "Minecraft Environment Preparation"
TOTAL_RAM=$(get_total_ram_gb)
SERVER_HEAP=$(get_heap_size_gb 2)
CLIENT_HEAP=$(get_client_xmx_gb)
print_info "Total RAM: ${TOTAL_RAM}G | Server heap: ${SERVER_HEAP}G | Client heap: ${CLIENT_HEAP}G"
if [[ -f server.jar ]]; then
  print_info "Generating AppCDS archive for server..."
  java -Xms"${SERVER_HEAP}G" -Xmx"${SERVER_HEAP}G" \
    -XX:ArchiveClassesAtExit=minecraft_server.jsa \
    -jar server.jar --nogui || print_error "Server AppCDS generation failed"
  [[ -f minecraft_server.jsa ]] && print_success "Server AppCDS archive created"
else
  print_error "server.jar not found - skipping server preparation"
fi
if [[ -f client.jar ]]; then
  print_info "Generating AppCDS archive for client..."
  java -Xms"${CLIENT_HEAP}G" -Xmx"${CLIENT_HEAP}G" \
    -XX:ArchiveClassesAtExit=minecraft_client.jsa \
    -jar client.jar || print_error "Client AppCDS generation failed"
  [[ -f minecraft_client.jsa ]] && print_success "Client AppCDS archive created"
else
  print_info "client.jar not found - skipping client preparation"
fi
print_success "Preparation complete!"

sudo ufw allow 25565
echo "Taking ownership of all server files/folders in ${PWD}/minecraft..."
sudo chown -R "${USER:-$(id -un)}" "${PWD}/minecraft"
sudo chmod -R 755 ./*.sh
umask 077
sudo systemctl daemon-reload
# sudo apt-get install -y screen
has screen || sudo pacman -Sq screen --needed --noconfirm &>/dev/null
