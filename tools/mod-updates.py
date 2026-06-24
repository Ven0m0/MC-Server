#!/usr/bin/env python3
"""Fabric server and mod management — replaces mod-updates.sh, eliminates jq dependency."""

import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import SCRIPT_DIR, header, success, error, info, fetch_json, download_file

MC_REPACK_CONFIG = Path.home() / ".config" / "mc-repack.toml"


def _has(cmd):
    return bool(shutil.which(cmd))


def clean_mod_name(name):
    name = re.sub(r"\.jar$", "", name)
    name = re.sub(r"[-_+]+(v|mc)?[0-9].*", "", name, flags=re.IGNORECASE)
    name = re.sub(r"[-_]fabric$", "", name, flags=re.IGNORECASE)
    return name.strip()


def install_fabric(mc_version="", loader=""):
    header("Installing Fabric Server")
    info("Fetching versions...")
    with ThreadPoolExecutor(max_workers=3) as ex:
        f_inst = ex.submit(
            fetch_json, "https://meta.fabricmc.net/v2/versions/installer"
        )
        f_mc = (
            ex.submit(fetch_json, "https://meta.fabricmc.net/v2/versions/game")
            if not mc_version
            else None
        )
        f_loader = (
            ex.submit(fetch_json, "https://meta.fabricmc.net/v2/versions/loader")
            if not loader
            else None
        )
    inst_ver = f_inst.result()[0]["version"]
    if f_mc:
        mc_version = next(v["version"] for v in f_mc.result() if v["stable"])
    if f_loader:
        loader = next(v["version"] for v in f_loader.result() if v["stable"])
    info(f"Minecraft: {mc_version} | Installer: {inst_ver} | Loader: {loader}")
    url = (
        f"https://maven.fabricmc.net/net/fabricmc/fabric-installer/"
        f"{inst_ver}/fabric-installer-{inst_ver}.jar"
    )
    download_file(url, "fabric-installer.jar")
    subprocess.run(
        [
            "java",
            "-jar",
            "fabric-installer.jar",
            "server",
            "-mcversion",
            mc_version,
            "-downloadMinecraft",
        ],
        check=True,
    )
    Path("fabric-installer.jar").unlink(missing_ok=True)
    success("Fabric server setup complete!")


def setup_server():
    header("Setting up server environment")
    Path("eula.txt").write_text("eula=true\n")
    success("Server setup complete")


def setup_mc_repack():
    header("Configuring mc-repack")
    MC_REPACK_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    MC_REPACK_CONFIG.write_text(
        "[json]\nremove_underscored = true\n"
        "[nbt]\nuse_zopfli = true\n"
        "[png]\nuse_zopfli = true\n"
        "[toml]\nstrip_strings = true\n"
        "[jar]\nkeep_dirs = false\nuse_zopfli = true\n"
    )
    success("mc-repack configured")


def setup_ferium():
    if not _has("ferium"):
        error("Ferium not installed")
        return
    header("Setting up Ferium profile")
    subprocess.run(
        [
            "ferium",
            "profile",
            "create",
            "--name",
            "server-mods",
            "--game-version",
            "1.21.5",
            "--mod-loader",
            "fabric",
        ],
        capture_output=True,
    )
    mods_file = SCRIPT_DIR / "docs" / "mods.txt"
    if mods_file.exists():
        for line in mods_file.read_text().splitlines():
            if name := clean_mod_name(line.strip()):
                info(f"Adding: {name}")
                subprocess.run(["ferium", "add", name], capture_output=True)
    else:
        for mod in ("fabric-api", "lithium"):
            subprocess.run(["ferium", "add", mod], capture_output=True)
    success("Ferium setup complete")


def ferium_update():
    if not _has("ferium"):
        error("Ferium not installed")
        return
    header("Running Ferium update")
    subprocess.run(["ferium", "scan"], check=True)
    subprocess.run(["ferium", "upgrade"], check=True)
    old = SCRIPT_DIR / "mods" / ".old"
    if old.exists():
        shutil.rmtree(old)
    success("Ferium update complete")


def update_geyserconnect(dest_dir=None):
    dest_dir = (
        Path(dest_dir)
        if dest_dir
        else SCRIPT_DIR / "minecraft" / "config" / "Geyser-Fabric" / "extensions"
    )
    header("Updating GeyserConnect")
    dest_dir.mkdir(parents=True, exist_ok=True)
    jar = dest_dir / "GeyserConnect.jar"
    if jar.exists():
        jar.rename(jar.with_suffix(".jar.bak"))
    url = "https://download.geysermc.org/v2/projects/geyserconnect/versions/latest/builds/latest/downloads/geyserconnect"
    download_file(url, jar)
    success("GeyserConnect updated")


USAGE = """\
Fabric Server & Mod Management
Usage: mod-updates.py <command> [options]
Commands:
  install-fabric [version] [loader]  Install Fabric server (defaults to latest stable)
  setup                              Write eula.txt
  setup-repack                       Configure mc-repack
  setup-ferium                       Setup Ferium profile and add mods
  ferium                             Run ferium scan + upgrade
  geyser [dir]                       Update GeyserConnect extension
  full-update                        Run complete update workflow
  help"""

args = sys.argv[1:]
cmd = args[0] if args else ""
if cmd in ("install-fabric", "install", "fabric"):
    install_fabric(args[1] if len(args) > 1 else "", args[2] if len(args) > 2 else "")
elif cmd == "setup":
    setup_server()
elif cmd == "setup-repack":
    setup_mc_repack()
elif cmd == "setup-ferium":
    setup_ferium()
elif cmd == "ferium":
    ferium_update()
elif cmd in ("geyser", "geyserconnect"):
    update_geyserconnect(args[1] if len(args) > 1 else None)
elif cmd == "full-update":
    setup_server()
    setup_mc_repack()
    if _has("ferium"):
        ferium_update()
    if (SCRIPT_DIR / "minecraft" / "config" / "Geyser-Fabric").exists():
        update_geyserconnect()
    success("Full update complete!")
elif cmd in ("help", "--help", "-h"):
    print(USAGE)
else:
    error(f"Unknown command: {cmd!r}")
    print(USAGE)
    sys.exit(1)
