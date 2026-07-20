#!/usr/bin/env python3
"""Minecraft server launcher with integrated lazymc support."""

import argparse
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import (
    check_dependencies,
    cpu_cores,
    detect_java,
    error,
    get_minecraft_memory_gb,
    header,
    info,
    success,
)

SERVER_JAR = os.environ.get("SERVER_JAR", "server.jar")
ENABLE_PLAYIT = os.environ.get("ENABLE_PLAYIT", "true") == "true"
ENABLE_LAZYMC = os.environ.get("ENABLE_LAZYMC", "false") == "true"
MIN_HEAP_GB = int(os.environ.get("MIN_HEAP_GB", "4"))
MC_NICE = os.environ.get("MC_NICE", "")
MC_IONICE = os.environ.get("MC_IONICE", "")

CONFIG_DIR = Path(os.environ.get("CONFIG_DIR", Path.cwd() / "config"))
LAZYMC_CONFIG = CONFIG_DIR / "lazymc.toml"
LAZYMC_PID_FILE = Path("/tmp/lazymc.pid")
LAZYMC_LOG_FILE = Path("logs/lazymc.log")


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except (OSError, ProcessLookupError):
        return False
    return True


def _read_pid() -> int | None:
    try:
        return int(LAZYMC_PID_FILE.read_text().strip())
    except (OSError, ValueError):
        return None


def check_lazymc() -> bool:
    if not shutil.which("lazymc"):
        error("lazymc not found")
        info("Run './tools/prepare.py lazymc-install' to install")
        return False
    return True


def check_lazymc_config() -> bool:
    if not LAZYMC_CONFIG.is_file():
        error(f"Configuration not found: {LAZYMC_CONFIG}")
        info("Run './tools/prepare.py lazymc-config' to generate")
        return False
    return True


def start_lazymc() -> bool:
    if not (check_lazymc() and check_lazymc_config()):
        return False

    pid = _read_pid()
    if pid and _pid_alive(pid):
        info(f"lazymc is already running (PID: {pid})")
        return True

    header("Starting lazymc")
    LAZYMC_LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(LAZYMC_LOG_FILE, "ab") as log:
        proc = subprocess.Popen(
            ["lazymc", "start", "--config", str(LAZYMC_CONFIG)],
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    LAZYMC_PID_FILE.write_text(str(proc.pid))
    time.sleep(2)

    if _pid_alive(proc.pid):
        success(f"lazymc started (PID: {proc.pid})")
        info(f"Log file: {LAZYMC_LOG_FILE}")
        return True
    error("Failed to start lazymc")
    info(f"Check logs: {LAZYMC_LOG_FILE}")
    LAZYMC_PID_FILE.unlink(missing_ok=True)
    return False


def stop_lazymc() -> None:
    pid = _read_pid()
    if pid is None:
        info("lazymc is not running (no PID file)")
        return
    if not _pid_alive(pid):
        info("lazymc is not running (stale PID file)")
        LAZYMC_PID_FILE.unlink(missing_ok=True)
        return

    header("Stopping lazymc")
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        error(f"Failed to stop lazymc (PID: {pid})")
        return

    for _ in range(10):
        if not _pid_alive(pid):
            break
        time.sleep(1)
    if _pid_alive(pid):
        info("Force killing lazymc")
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass

    LAZYMC_PID_FILE.unlink(missing_ok=True)
    success("lazymc stopped")


def restart_lazymc() -> None:
    stop_lazymc()
    time.sleep(1)
    start_lazymc()


def status_lazymc() -> None:
    if not check_lazymc():
        return
    header("lazymc Status")

    pid = _read_pid()
    if pid is not None:
        if _pid_alive(pid):
            success(f"Running (PID: {pid})")
            if shutil.which("ps"):
                print()
                subprocess.run(["ps", "-p", str(pid), "-o", "pid,ppid,cmd,etime,rss"])
        else:
            error("Not running (stale PID file)")
            LAZYMC_PID_FILE.unlink(missing_ok=True)
    else:
        info("Not running")

    if LAZYMC_CONFIG.is_file():
        print()
        info(f"Configuration: {LAZYMC_CONFIG}")

    if LAZYMC_LOG_FILE.is_file():
        print()
        header("Recent Logs")
        lines = LAZYMC_LOG_FILE.read_text(errors="replace").splitlines()
        print("\n".join(lines[-10:]))


def show_lazymc_logs(lines: int = 50) -> None:
    if not LAZYMC_LOG_FILE.is_file():
        error(f"Log file not found: {LAZYMC_LOG_FILE}")
        sys.exit(1)
    content = LAZYMC_LOG_FILE.read_text(errors="replace").splitlines()
    print("\n".join(content[-lines:]))


def follow_lazymc_logs() -> None:
    if not LAZYMC_LOG_FILE.is_file():
        error(f"Log file not found: {LAZYMC_LOG_FILE}")
        sys.exit(1)
    subprocess.run(["tail", "-f", str(LAZYMC_LOG_FILE)])


def launch_server() -> None:
    if not check_dependencies("java"):
        sys.exit(1)
    if not Path(SERVER_JAR).is_file():
        error(f"Server jar not found: {SERVER_JAR}")
        sys.exit(1)

    cores = cpu_cores()
    available_ram = get_minecraft_memory_gb()
    if available_ram < MIN_HEAP_GB:
        info(
            f"Warning: Available RAM ({available_ram}GB) is less than configured minimum ({MIN_HEAP_GB}GB)."
        )
        info(f"Using {available_ram}GB to prevent OOM crash.")
        heap = available_ram
    else:
        heap = max(available_ram, MIN_HEAP_GB)
    xms = xmx = f"{heap}G"
    info(f"Memory: {xms} - {xmx} | CPU Cores: {cores}")

    java_cmd = detect_java()
    if shutil.which("archlinux-java"):
        subprocess.run(["sudo", "archlinux-java", "fix"], capture_output=True)

    version_out = subprocess.run([java_cmd, "-version"], capture_output=True, text=True)
    is_graalvm = "GraalVM" in (version_out.stdout + version_out.stderr)

    jvm_flags = [
        f"-Xms{xms}",
        f"-Xmx{xmx}",
        "-XX:+UseG1GC",
        "-XX:+UnlockExperimentalVMOptions",
        "-XX:MaxGCPauseMillis=200",
        "-XX:G1NewSizePercent=30",
        "-XX:G1ReservePercent=15",
        "-XX:G1HeapRegionSize=32M",
        "-XX:+AlwaysPreTouch",
        "-XX:+DisableExplicitGC",
        "-XX:+ParallelRefProcEnabled",
        f"-XX:ParallelGCThreads={cores}",
        f"-XX:ConcGCThreads={max(1, cores // 4)}",
        "-Dfile.encoding=UTF-8",
        "-Djava.awt.headless=true",
    ]

    if is_graalvm:
        jvm_flags += [
            "-Djdk.graal.TuneInlinerExploration=1",
            "-Djdk.graal.CompilerConfiguration=enterprise",
            "-Djdk.graal.Vectorization=true",
            "-XX:+UseJVMCICompiler",
        ]

    thp = Path("/sys/kernel/mm/transparent_hugepage/enabled")
    if thp.is_file() and "[always]" in thp.read_text():
        jvm_flags.append("-XX:+UseTransparentHugePages")
        success("Transparent Huge Pages enabled")

    if ENABLE_PLAYIT and shutil.which("playit"):
        info("Starting playit...")
        if (
            subprocess.run(["pgrep", "-x", "playit"], capture_output=True).returncode
            != 0
        ):
            subprocess.Popen(
                ["playit"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            time.sleep(2)

    if ENABLE_LAZYMC and not start_lazymc():
        info("Continuing without lazymc...")

    cmd = [java_cmd, *jvm_flags, "-jar", SERVER_JAR, "--nogui"]

    if MC_IONICE and shutil.which("ionice"):
        cmd = ["ionice", *MC_IONICE.split(), *cmd]
        info(f"IO Priority: {MC_IONICE}")

    if MC_NICE and shutil.which("nice"):
        cmd = ["nice", "-n", MC_NICE, *cmd]
        info(f"Nice Level: {MC_NICE}")

    header("Starting Minecraft Server")
    print(f"  JAR: {SERVER_JAR}")
    print(f"  Memory: {xms} - {xmx}")
    print(f"  CPU Cores: {cores}")
    os.execvp(cmd[0], cmd)


def show_usage() -> None:
    header("Minecraft Server Launcher")
    print()
    print(f"Usage: {sys.argv[0]} [command] [options]")
    print()
    print("Commands:")
    print("  (none)              Start the Minecraft server directly")
    print("  lazymc start        Start lazymc daemon (auto sleep/wake proxy)")
    print("  lazymc stop         Stop lazymc daemon")
    print("  lazymc restart      Restart lazymc daemon")
    print("  lazymc status       Show lazymc status")
    print("  lazymc logs [n]     Show recent logs (default: 50 lines)")
    print("  lazymc follow       Follow logs in real-time")
    print("  help                Show this help message")
    print()
    print("Environment Variables:")
    print("  SERVER_JAR          Server jar file (default: server.jar)")
    print("  ENABLE_PLAYIT       Enable playit.gg tunnel (default: true)")
    print("  ENABLE_LAZYMC       Start lazymc with server (default: false)")
    print("  MIN_HEAP_GB         Minimum heap size in GB (default: 4)")
    print("  MC_NICE             Nice level for CPU priority")
    print("  MC_IONICE           Ionice class for IO priority")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Minecraft Server Launcher", add_help=False
    )
    parser.add_argument("command", nargs="?", default="")
    parser.add_argument("args", nargs="*")
    ns = parser.parse_args()

    if ns.command in ("help", "--help", "-h"):
        show_usage()
        return

    if ns.command == "lazymc":
        subcmd = ns.args[0] if ns.args else "help"
        if subcmd == "start":
            start_lazymc()
        elif subcmd == "stop":
            stop_lazymc()
        elif subcmd == "restart":
            restart_lazymc()
        elif subcmd == "status":
            status_lazymc()
        elif subcmd == "logs":
            show_lazymc_logs(int(ns.args[1]) if len(ns.args) > 1 else 50)
        elif subcmd == "follow":
            follow_lazymc_logs()
        elif subcmd in ("help", "--help", "-h"):
            show_usage()
        else:
            error(f"Unknown lazymc command: {subcmd}")
            sys.exit(1)
        return

    if ns.command == "":
        launch_server()
        return

    error(f"Unknown command: {ns.command}")
    sys.exit(1)


if __name__ == "__main__":
    main()
