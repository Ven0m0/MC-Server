#!/bin/bash
set -euo pipefail; IFS=$'\n\t'
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
shopt -s nullglob globstar

WORKDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
cd $WORKDIR

echo eula=true >eula.txt

echo "[*] Starting Minecraft mod and GeyserConnect update..."

echo "Taking ownership of all server files/folders in dirname/minecraft..."
sudo chown -R "$(id -un):$(id -gn)" $WORKDIR/world
sudo chmod -R 755 $WORKDIR/*.sh

echo "Complete"

# ─── Update mc-repack.toml config using sd ─────────────────────────────────────
config="$HOME/mc-repack.toml"
touch "$config"

echo "[*] Updating mc-repack config at $config..."

# Remove specific TOML sections cleanly using sd
for section in json nbt png toml jar; do
    sd -s "^\[$section\](\n(?!\[).*)*" "" "$config" || true
done

# Append updated configuration
cat >> "$config" <<'EOF'

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

echo "[✔] mc-repack.toml updated."

# ─── Ferium Mod Update ─────────────────────────────────────────────────────────
echo "[*] Running ferium scan and upgrade..."
ferium scan && ferium upgrade

# ─── Clean .old Mods Folder ────────────────────────────────────────────────────
if [[ -d mods/.old ]]; then
    echo "[*] Cleaning old mod backups..."
    rm -f mods/.old/*
else
    echo "[*] Skipping cleanup: mods/.old does not exist."
fi

# ─── Repack Mods ───────────────────────────────────────────────────────────────
timestamp=$(date +%Y-%m-%d_%H-%M)
mods_src="$HOME/Documents/MC/Minecraft/mods"
mods_dst="$HOME/Documents/MC/Minecraft/mods-$timestamp"

echo "[*] Repacking mods to: $mods_dst"
mc-repack jars -c "$config" --in "$mods_src" --out "$mods_dst"

# ─── Download GeyserConnect ────────────────────────────────────────────────────
echo "[*] Downloading latest GeyserConnect..."
curlopts=(-fsSL -Z --parallel-immediate --compressed --http3)

URL="https://download.geysermc.org/v2/projects/geyserconnect/versions/latest/builds/latest/downloads/geyserconnect"
dest_dir="$HOME/Documents/MC/Minecraft/config/Geyser-Fabric/extensions"
tmp_jar="$dest_dir/GeyserConnect2.jar"
final_jar="$dest_dir/GeyserConnect.jar"

mkdir -p "$dest_dir"

if curl "${curlopts[@]}" -o "$tmp_jar" "$URL"; then
    echo "[*] Download complete: $tmp_jar"
else
    echo "[!] Failed to download GeyserConnect!" >&2
    exit 1
fi

# ─── Backup Existing JAR ───────────────────────────────────────────────────────
if [[ -f "$final_jar" ]]; then
    echo "[*] Backing up existing GeyserConnect.jar..."
    mv "$final_jar" "$final_jar.bak"
fi

# ─── Repack and Cleanup ────────────────────────────────────────────────────────
echo "[*] Repacking GeyserConnect..."
mc-repack jars -c "$config" --in "$tmp_jar" --out "$final_jar"
rm -f "$tmp_jar"
echo "[✔] GeyserConnect updated and cleaned up."

echo "[✅] Minecraft update process complete."
