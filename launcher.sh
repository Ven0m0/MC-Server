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

# Detect CPU cores and RAM (in GB)
CPU_CORES=$(nproc 2>/dev/null)
TOTAL_RAM=$(awk '/MemTotal/ {printf "%.0f\n",$2/1024/1024}' /proc/meminfo 2>/dev/null)
# Compute heap sizes: leave ~2GB for OS / background
XMS=$((TOTAL_RAM - 2)) XMX=$((TOTAL_RAM - 2))
(( XMS < 1 )) && XMS=1 XMX=1
JARNAME="server.jar"
AFTERJAR="--nogui"
# Detect JDK selection: default Temurin
: "${MC_JDK:=graalvm}"
: "${JAVA_CMD:=/usr/lib/jvm/default-rumtime/bin/java}"
if has archlinux-java; then
  sudo archlinux-java fix 2>/dev/null
  JAVA_CMD="$(archlinux-java get 2>/dev/null)"
fi
[[ $TOTAL_RAM -ge 1 ]] && JVM_FLAGS=+(-XX:+DisableExplicitGC -XX:-UseParallelGC)

JVM_FLAGS="
-XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+IgnoreUnrecognizedVMOptions --illegal-access=permit
-Dfile.encoding=UTF-8 
-Xlog:async -Xlog:gc*:file=/dev/null
-XX:+UseLargePages -XX:+UseTransparentHugePages -XX:LargePageSizeInBytes=2M -XX:+UseLargePagesInMetaspace
-Xms"${XMS}G" -Xmx"${XMX}G"
-XX:ConcGCThreads=$((CPU_CORES/2)) -XX:ParallelGCThreads="$CPU_CORES"
-XX:+AlwaysPreTouch -XX:+UseFastAccessorMethods -XX:+UseCompressedOops -XX:-DontCompileHugeMethods
-XX:+AggressiveOpts -XX:+OptimizeStringConcat -XX:+UseCompactObjectHeaders -XX:+UseStringDeduplication
--add-modules=jdk.incubator.vector -da
-XX:MaxGCPauseMillis=50 -XX:InitiatingHeapOccupancyPercent=30
"
GRAAL_FLAGS="
-Djdk.graal.CompilerConfiguration=enterprise
-Djdk.graal.UsePriorityInlining=true -Djdk.graal.Vectorization=true -Djdk.graal.OptDuplication=true -Djdk.graal.DetectInvertedLoopsAsCounted=true -Djdk.graal.LoopInversion=true -Djdk.graal.VectorizeHashes=true -Djdk.graal.EnterprisePartialUnroll=true -Djdk.graal.VectorizeSIMD=true -Djdk.graal.StripMineNonCountedLoops=true -Djdk.graal.SpeculativeGuardMovement=true -Djdk.graal.TuneInlinerExploration=1 -Djdk.graal.LoopRotation=true
"
EXP_FLAGS="
-XX:+UseCMoveUnconditionally -XX:+UseNewLongLShift -XX:+UseVectorCmov -XX:+UseXmmI2D -XX:+UseXmmI2F
"

case "$MC_JDK" in
  graalvm)
    JAVA_CMD=${JAVA_GRAALVM:-/usr/lib/graalvm-ce-java21}/bin/java
    JVM_FLAGS=(
      -XX:+UseG1GC
      -XX:+UseJVMCICompiler
      -XX:+TieredStopAtLevel=4
      -XX:CompileThreshold=500
    ) ;;
  temurin|*)
    JAVA_CMD=${JAVA_TEMURIN:-/usr/lib/jvm/java-25-temurin}/bin/java
    JVM_FLAGS=(
      -XX:+UseG1GC
      -XX:+TieredCompilation
      -XX:CompileThreshold=1000
    ) ;;
esac

# Optional: pin CPU cores for consistent performance
TASKSET_CMD=(taskset -c 0-$((CPU_CORES-1)))

# Launch Minecraft server
sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null
read -rt 1 -- <> <(:) &>/dev/null || :
"${TASKSET_CMD[@]}" "$JAVA_CMD" "${JVM_FLAGS[@]}" -jar "$JARNAME" "$AFTERJAR"
