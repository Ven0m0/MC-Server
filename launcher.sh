#!/usr/bin/env bash

# Source common functions (SCRIPT_DIR is auto-initialized)
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

init_strict_mode
shopt -s nullglob globstar
SHELL="$(command -v bash 2>/dev/null)"
export LC_ALL=C LANG=C LANGUAGE=C HOME="/home/${SUDO_USER:-$USER}"
[[ $EUID -ne 0 ]] && sudo -v
cd_script_dir
printf '%s\n' "$PWD" || exit 1
# mc-launcher.sh: auto-tuned Minecraft JVM launcher
has_command java || { echo >&2 "No JDK found. Aborting..."; exit 1; }

# Use Transparent Huge Pages (direct redirect is more efficient than echo pipe)
sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null <<< 'madvise'

powerprofilesctl set performance
echo kyber | sudo tee /sys/block/nvme0n1/queue/scheduler
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_govern

# Detect CPU cores and RAM (in GB)
CPU_CORES=$(get_cpu_cores)
# Calculate heap sizes: leave ~2GB for OS / background (uses get_heap_size_gb from common.sh)
XMS=$(get_heap_size_gb 2)
XMX=$(get_heap_size_gb 2)
JARNAME="server.jar"
AFTERJAR="--nogui"
# Detect JDK selection: default Temurin
: "${MC_JDK:=graalvm}"
: "${JAVA_CMD:=/usr/lib/jvm/default-rumtime/bin/java}"
if has archlinux-java; then
  sudo archlinux-java fix 2>/dev/null
  JAVA_CMD="$(archlinux-java get 2>/dev/null)"
fi
# Base JVM flags for performance
JVM_FLAGS=(
  -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+IgnoreUnrecognizedVMOptions --illegal-access=permit
  -Dfile.encoding=UTF-8 -Djdk.util.zip.disableZip64ExtraFieldValidation=true -Djdk.nio.zipfs.allowDotZipEntry=true
  -Xlog:async -Xlog:gc*:file=/dev/null
  -XX:+UseLargePages -XX:+UseTransparentHugePages -XX:LargePageSizeInBytes=2M -XX:+UseLargePagesInMetaspace
  "-Xms${XMS}G" "-Xmx${XMX}G"
  "-XX:ConcGCThreads=$((CPU_CORES/2))" "-XX:ParallelGCThreads=${CPU_CORES}"
  -XX:+AlwaysPreTouch -XX:+UseFastAccessorMethods -XX:+UseCompressedOops -XX:-DontCompileHugeMethods
  -XX:+AggressiveOpts -XX:+OptimizeStringConcat -XX:+UseCompactObjectHeaders -XX:+UseStringDeduplication
  --add-modules=jdk.incubator.vector -da
  -XX:MaxGCPauseMillis=50 -XX:InitiatingHeapOccupancyPercent=30
  -XX:+UseCMoveUnconditionally -XX:+UseNewLongLShift -XX:+UseVectorCmov -XX:+UseXmmI2D -XX:+UseXmmI2F
)

case "$MC_JDK" in
  graalvm)
    JAVA_CMD=${JAVA_GRAALVM:-/usr/lib/graalvm-ce-java21}/bin/java
    # Add GraalVM-specific optimizations to existing flags
    JVM_FLAGS+=(
      -XX:+UseG1GC
      -XX:+UseJVMCICompiler
      -XX:+TieredStopAtLevel=4
      -XX:CompileThreshold=500
      -Djdk.graal.CompilerConfiguration=enterprise
      -Djdk.graal.UsePriorityInlining=true -Djdk.graal.Vectorization=true
      -Djdk.graal.OptDuplication=true -Djdk.graal.TuneInlinerExploration=1
    ) ;;
  temurin|*)
    JAVA_CMD=${JAVA_TEMURIN:-/usr/lib/jvm/java-25-temurin}/bin/java
    # Add Temurin-specific optimizations to existing flags
    JVM_FLAGS+=(
      -XX:+UseG1GC
      -XX:+TieredCompilation
      -XX:CompileThreshold=1000
    ) ;;
esac

# Optional: pin CPU cores for consistent performance
TASKSET_CMD=(taskset -c 0-$((CPU_CORES-1)))

sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null
read -rt 1 -- <> <(:) &>/dev/null || :

# Start playit
setsid nohub playit >/dev/null & || :
read -rt 1 -- <> <(:) &>/dev/null || :

# Launch Minecraft server
"${TASKSET_CMD[@]}" "$JAVA_CMD" "${JVM_FLAGS[@]}" -jar "$JARNAME" "$AFTERJAR"
