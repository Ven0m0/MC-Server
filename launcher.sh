#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' SHELL="$(command -v bash 2>/dev/null)"
export LC_ALL=C LANG=C LANGUAGE=C HOME="/home/${SUDO_USER:-$USER}"
[[ $EUID -ne 0 ]] && sudo -v
builtin cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD" || exit 1
has(){ command -v "$1" &>/dev/null; }
# mc-launcher.sh: auto-tuned Minecraft JVM launcher

# Use Transparent Huge Pages (direct redirect is more efficient than echo pipe)
sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null <<< 'madvise'

JVM_FLAGS="
-XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+IgnoreUnrecognizedVMOptions --illegal-access=permit
-XX:+UseZGC
-Xlog:async -Dfile.encoding=UTF-8
-XX:+UseLargePages -XX:+UseTransparentHugePages -XX:LargePageSizeInBytes=2M
"
GRAAL_FLAGS="
-Djdk.graal.CompilerConfiguration=enterprise
-Djdk.graal.UsePriorityInlining=true -Djdk.graal.Vectorization=true -Djdk.graal.OptDuplication=true -Djdk.graal.DetectInvertedLoopsAsCounted=true -Djdk.graal.LoopInversion=true -Djdk.graal.VectorizeHashes=true -Djdk.graal.EnterprisePartialUnroll=true -Djdk.graal.VectorizeSIMD=true -Djdk.graal.StripMineNonCountedLoops=true -Djdk.graal.SpeculativeGuardMovement=true -Djdk.graal.TuneInlinerExploration=1 -Djdk.graal.LoopRotation=true
"
EXP_FLAGS="
-XX:+UseCMoveUnconditionally -XX:+UseNewLongLShift -XX:+UseVectorCmov -XX:+UseXmmI2D -XX:+UseXmmI2F
"

JARNAME="server.jar"
AFTERJAR="--nogui"

# Detect CPU cores and RAM (in GB)
CPU_CORES=$(nproc 2>/dev/null)
TOTAL_RAM=$(awk '/MemTotal/ {printf "%.0f\n",$2/1024/1024}' /proc/meminfo 2>/dev/null)

# Compute heap sizes: leave ~2GB for OS / background
XMS=$((TOTAL_RAM - 2))
XMX=$((TOTAL_RAM - 2))
if (( XMS < 1 )); then XMS=1; XMX=1; fi

# Detect JDK selection: default Temurin
: "${MC_JDK:=graalvm}"
: "${JAVA_CMD:=/usr/lib/jvm/default-rumtime/bin/java}"
if has archlinux-java; then
  sudo archlinux-java fix 2>/dev/null
  JAVA_CMD="$(archlinux-java get 2>/dev/null)"
fi
case "$MC_JDK" in
  graalvm)
    JAVA_CMD=${JAVA_GRAALVM:-/usr/lib/graalvm-ce-java21}/bin/java
    JVM_FLAGS=(
      -XX:+UseG1GC
      -XX:+UseJVMCICompiler
      -XX:+TieredStopAtLevel=4
      -XX:+AggressiveOpts
      -XX:CompileThreshold=500
      -XX:+OptimizeStringConcat
      -XX:+UseCompactObjectHeaders
      -XX:MaxGCPauseMillis=50
      -XX:InitiatingHeapOccupancyPercent=30
      -XX:+UseStringDeduplication
      --add-modules=jdk.incubator.vector
      -XX:ParallelGCThreads="$CPU_CORES" -XX:ConcGCThreads=$((CPU_CORES/2)) -Xms"${XMS}G" -Xmx"${XMX}G"
      -da
      -Xlog:gc*:file=/dev/null
    ) ;;
  temurin|*)
    JAVA_CMD=${JAVA_TEMURIN:-/usr/lib/jvm/java-25-temurin}/bin/java
    JVM_FLAGS=(
      -XX:+TieredCompilation
      -XX:+AggressiveOpts
      -XX:CompileThreshold=1000
      -XX:+OptimizeStringConcat
      -XX:+UseCompactObjectHeaders
      -XX:+UseStringDeduplication
      --add-modules=jdk.incubator.vector
      -XX:+UseG1GC
      -XX:MaxGCPauseMillis=50
      -XX:InitiatingHeapOccupancyPercent=30
      -XX:ParallelGCThreads="$CPU_CORES" -XX:ConcGCThreads=$((CPU_CORES/2)) -Xms"${XMS}G" -Xmx"${XMX}G"
      -da
      -Xlog:gc*:file=/dev/null
    ) ;;
esac

# Optional: pin CPU cores for consistent performance
TASKSET_CMD=(taskset -c 0-$((CPU_CORES-1)))

# Launch Minecraft server
sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null
read -rt 1 -- <> <(:) &>/dev/null || :
"${TASKSET_CMD[@]}" "$JAVA_CMD" "${JVM_FLAGS[@]}" -jar "$JARNAME" "$AFTERJAR"
