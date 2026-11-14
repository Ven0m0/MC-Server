#!/usr/bin/env python3
"""Minecraft client launcher with automatic version management.

Based on https://github.com/Sushkyn/mc-launcher
"""

import argparse
import json
import os
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import (
    check_dependencies,
    download_file,
    ensure_dir,
    fetch_json,
    get_client_xms_gb,
    get_client_xmx_gb,
)


def extract_natives(jar_file: Path, dest_dir: Path) -> None:
    ensure_dir(dest_dir)
    try:
        with zipfile.ZipFile(jar_file) as z:
            z.extractall(dest_dir)
    except zipfile.BadZipFile:
        pass
    meta_inf = dest_dir / "META-INF"
    if meta_inf.is_dir():
        import shutil

        shutil.rmtree(meta_inf)


def main() -> None:
    parser = argparse.ArgumentParser(description="Minecraft client launcher")
    parser.add_argument("version", nargs="?", help="Minecraft version (e.g. 1.21.6)")
    parser.add_argument("username", nargs="?", default="Player")
    args = parser.parse_args()

    if not args.version:
        print(f"Usage: {sys.argv[0]} <VERSION> [USERNAME]")
        print(f"Example: {sys.argv[0]} 1.21.6 MyPlayer")
        print()
        print("Environment variables:")
        print("  MC_DIR    : Minecraft directory (default: ~/.minecraft)")
        sys.exit(1)

    if not check_dependencies("java"):
        sys.exit(1)

    version, username = args.version, args.username
    mc_dir = Path(os.environ.get("MC_DIR", Path.home() / ".minecraft"))
    versions_dir = mc_dir / "versions" / version
    assets_dir = mc_dir / "assets"
    libraries_dir = mc_dir / "libraries"
    natives_dir = versions_dir / "natives"
    for d in (versions_dir, assets_dir, libraries_dir, natives_dir):
        ensure_dir(d)

    print("[*] Minecraft Client Launcher")
    print(f"→ Version: {version}")
    print(f"→ Username: {username}")
    print(f"→ Directory: {mc_dir}")
    print()

    print("[1/5] Fetching version manifest...")
    manifest_file = versions_dir / "version.json"
    if manifest_file.is_file():
        print("  Using cached version manifest")
        manifest = json.loads(manifest_file.read_text())
    else:
        print("  Downloading version list...")
        version_list = fetch_json(
            "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
        )
        entry = next((v for v in version_list["versions"] if v["id"] == version), None)
        if entry is None:
            print(f"Error: Version {version} not found", file=sys.stderr)
            sys.exit(1)
        print("  Downloading version manifest...")
        manifest = fetch_json(entry["url"])
        manifest_file.write_text(json.dumps(manifest))

    print("[2/5] Downloading client JAR...")
    client_jar = versions_dir / f"{version}.jar"
    if client_jar.is_file():
        print("  Client JAR already exists")
    else:
        print("  Downloading from Mojang servers...")
        download_file(manifest["downloads"]["client"]["url"], client_jar)

    print("[3/5] Downloading game assets...")
    asset_index = manifest["assetIndex"]["id"]
    asset_index_file = assets_dir / "indexes" / f"{asset_index}.json"
    ensure_dir(assets_dir / "indexes")
    ensure_dir(assets_dir / "objects")
    if asset_index_file.is_file():
        asset_manifest = json.loads(asset_index_file.read_text())
    else:
        print("  Downloading asset index...")
        asset_manifest = fetch_json(manifest["assetIndex"]["url"])
        asset_index_file.write_text(json.dumps(asset_manifest))

    print("  Downloading asset objects...")
    objects = asset_manifest["objects"]
    print(f"  Total assets: {len(objects)}")
    missing = 0
    for obj in objects.values():
        h = obj["hash"]
        prefix = h[:2]
        asset_file = assets_dir / "objects" / prefix / h
        if not asset_file.is_file():
            ensure_dir(asset_file.parent)
            download_file(
                f"https://resources.download.minecraft.net/{prefix}/{h}", asset_file
            )
            missing += 1
    if missing == 0:
        print("  All assets already downloaded")

    print("[4/5] Downloading libraries...")
    classpath = [str(client_jar)]
    for lib in manifest.get("libraries", []):
        rules = lib.get("rules") or []
        if rules:
            allowed = any(
                r.get("action") == "allow"
                and r.get("os", {}).get("name", "any") in ("any", "linux")
                for r in rules
            )
            if not allowed:
                continue
        artifact = lib.get("downloads", {}).get("artifact")
        if artifact and artifact.get("url"):
            lib_file = libraries_dir / artifact["path"]
            if not lib_file.is_file():
                ensure_dir(lib_file.parent)
                print(f"  Downloading {lib_file.name}...")
                download_file(artifact["url"], lib_file)
            classpath.append(str(lib_file))
        native = lib.get("downloads", {}).get("classifiers", {}).get("natives-linux")
        if native and native.get("url"):
            native_file = libraries_dir / native["path"]
            if not native_file.is_file():
                ensure_dir(native_file.parent)
                print(f"  Downloading native {native_file.name}...")
                download_file(native["url"], native_file)
            extract_natives(native_file, natives_dir)

    print("[5/5] Launching Minecraft...")
    main_class = manifest["mainClass"]
    xms, xmx = get_client_xms_gb(), get_client_xmx_gb()

    game_args = manifest.get("arguments", {}).get("game") or manifest.get(
        "minecraftArguments", ""
    )
    if isinstance(game_args, list):
        game_args = " ".join(a for a in game_args if isinstance(a, str))
    replacements = {
        "${auth_player_name}": username,
        "${version_name}": version,
        "${game_directory}": str(mc_dir),
        "${assets_root}": str(assets_dir),
        "${assets_index_name}": asset_index,
        "${auth_uuid}": "00000000-0000-0000-0000-000000000000",
        "${auth_access_token}": "0",
        "${user_type}": "legacy",
        "${version_type}": "release",
    }
    for k, v in replacements.items():
        game_args = game_args.replace(k, v)

    print()
    print(f"Starting Minecraft {version}...")
    print()

    cmd = [
        "java",
        f"-Xms{xms}G",
        f"-Xmx{xmx}G",
        "-XX:+ShowCodeDetailsInExceptionMessages",
        "-XX:+UnlockExperimentalVMOptions",
        "-XX:+UseG1GC",
        "-XX:G1NewSizePercent=20",
        "-XX:G1ReservePercent=20",
        "-XX:MaxGCPauseMillis=50",
        "-XX:G1HeapRegionSize=32M",
        f"-Djava.library.path={natives_dir}",
        "-Dminecraft.launcher.brand=mc-client",
        "-Dminecraft.launcher.version=1.0",
        "-cp",
        ":".join(classpath),
        main_class,
        *game_args.split(),
    ]
    os.execvp("java", cmd)


if __name__ == "__main__":
    main()
