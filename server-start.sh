#!/usr/bin/env bash
# server-start.sh: Unified Minecraft server launcher with playit integration
# Consolidates launcher.sh, start.sh, and Server.sh functionality
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C LANG=C

# ─── Utility Functions ──────────────────────────────────────────────────────────
has_command(){ command -v "$1" &>/dev/null; }
get_cpu_cores(){ nproc 2>/dev/null || echo 4; }
get_total_ram_gb(){ awk '/MemTotal/ {printf "%.0f\n",$2/1024/1024}' /proc/meminfo 2>/dev/null; }
get_heap_size_gb(){
    local reserved="${1:-2}"
    local total_ram=$(get_total_ram_gb)
    local heap=$((total_ram - reserved))
    [[ $heap -lt 1 ]] && heap=1
    echo "$heap"
}

# ─── Configuration ──────────────────────────────────────────────────────────────
# Default settings (override via environment variables)
: "${MC_JDK:=graalvm}"                    # JDK: graalvm, temurin, or default
: "${SERVER_JAR:=server.jar}"             # Server jar file
: "${USE_ALACRITTY:=false}"               # Launch in Alacritty terminal
: "${ENABLE_PLAYIT:=true}"                # Enable playit for hosting
: "${ENABLE_OPTIMIZATIONS:=true}"         # Enable system optimizations
: "${ENABLE_GAMEMODE:=false}"             # Use gamemoderun
: "${MIN_HEAP_GB:=4}"                     # Minimum heap size

# ─── Validation ─────────────────────────────────────────────────────────────────
has_command java || { echo >&2 "Error: Java not found. Install Java and try again."; exit 1; }
[[ ! -f "$SERVER_JAR" ]] && {
    echo >&2 "Error: Server jar not found: $SERVER_JAR"
    echo >&2 "Set SERVER_JAR environment variable or place server.jar in current directory"; exit 1
}

# ─── System Optimizations ───────────────────────────────────────────────────────
if [[ "$ENABLE_OPTIMIZATIONS" == "true" ]]; then
    echo "[*] Applying system optimizations..."
    [[ $EUID -ne 0 ]] && sudo -v
    sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null <<< 'madvise' 2>/dev/null || :
    sudo tee /sys/kernel/mm/transparent_hugepage/shmem_enabled >/dev/null <<< 'always' 2>/dev/null || :
    powerprofilesctl set performance 2>/dev/null || :
    [[ -e /sys/block/nvme0n1/queue/scheduler ]] && echo kyber | sudo tee /sys/block/nvme0n1/queue/scheduler &>/dev/null || :
    sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null <<< 'performance' 2>/dev/null || :
    sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null || :
    echo "[✓] System optimizations applied"
fi

# ─── Memory Configuration ───────────────────────────────────────────────────────
CPU_CORES=$(get_cpu_cores)
HEAP_SIZE=$(get_heap_size_gb 2)
[[ $HEAP_SIZE -lt $MIN_HEAP_GB ]] && HEAP_SIZE=$MIN_HEAP_GB
XMS="${HEAP_SIZE}G"
XMX="${HEAP_SIZE}G"
echo "[*] Memory: ${XMS} - ${XMX} | CPU Cores: ${CPU_CORES}"

# ─── JDK Detection and Configuration ────────────────────────────────────────────

if has_command archlinux-java; then
    sudo archlinux-java fix 2>/dev/null || :
    DETECTED_JAVA="$(archlinux-java get 2>/dev/null)"
    [[ -n "$DETECTED_JAVA" ]] && JAVA_CMD="$DETECTED_JAVA"
fi

case "$MC_JDK" in
    graalvm)
        JAVA_CMD="${JAVA_GRAALVM:-/usr/lib/jvm/graalvm-ce-java21/bin/java}"
        [[ ! -x "$JAVA_CMD" ]] && JAVA_CMD=$(command -v java)
        echo "[*] Using GraalVM: $JAVA_CMD"

        JVM_FLAGS=(
            -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+IgnoreUnrecognizedVMOptions 
            -Dfile.encoding=UTF-8 -Xlog:async,gc*:file=/dev/null --illegal-access=permit
            -Djdk.util.zip.disableZip64ExtraFieldValidation=true -Djdk.nio.zipfs.allowDotZipEntry=true
            # Memory
            "-Xms${XMS}" "-Xmx${XMX}"
            -XX:+UseLargePages -XX:LargePageSizeInBytes=2M
            -XX:+UseLargePagesInMetaspace -XX:+UseTransparentHugePages
            -XX:+AlwaysPreTouch -XX:+UseCompressedOops 
            # GraalVM JVMCI Compiler
            -XX:+UseG1GC -XX:+UseJVMCICompiler -XX:+EagerJVMCI -XX:+DisableExplicitGC
            -Djdk.graal.CompilerConfiguration=enterprise
            -Djdk.graal.UsePriorityInlining=true -Djdk.graal.Vectorization=true
            -Djdk.graal.OptDuplication=true -Djdk.graal.TuneInlinerExploration=1
            -XX:CompileThreshold=500 -XX:+TieredStopAtLevel=4
            # GC tuning
            "-XX:ConcGCThreads=$((CPU_CORES/2))" "-XX:ParallelGCThreads=${CPU_CORES}"
            -XX:MaxGCPauseMillis=50 -XX:InitiatingHeapOccupancyPercent=15
            -XX:G1NewSizePercent=30 -XX:G1ReservePercent=15
            -XX:G1HeapRegionSize=16M -XX:G1MixedGCCountTarget=4
            # Optimizations
            -XX:-DontCompileHugeMethods -XX:+AggressiveOpts -XX:+AlwaysActAsServerClassMachine
            -XX:+OptimizeStringConcat -XX:+UseCompactObjectHeaders
            -XX:+UseStringDeduplication --add-modules=jdk.incubator.vector -da
            -XX:+UseCMoveUnconditionally -XX:+UseNewLongLShift
            -XX:+UseVectorCmov -XX:+UseXmmI2D -XX:+UseXmmI2F -XX:+UseFastAccessorMethods
        );;
    temurin)
        JAVA_CMD="${JAVA_TEMURIN:-/usr/lib/jvm/java-25-temurin/bin/java}"
        [[ ! -x "$JAVA_CMD" ]] && JAVA_CMD=$(command -v java)
        echo "[*] Using Temurin: $JAVA_CMD"
        JVM_FLAGS=(
            -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+IgnoreUnrecognizedVMOptions 
            -Dfile.encoding=UTF-8 -Xlog:async,gc*:file=/dev/null --illegal-access=permit
            -Djdk.util.zip.disableZip64ExtraFieldValidation=true -Djdk.nio.zipfs.allowDotZipEntry=true
            # Memory
            "-Xms${XMS}" "-Xmx${XMX}"
            -XX:+UseLargePages -XX:LargePageSizeInBytes=2M
            -XX:+UseLargePagesInMetaspace -XX:+UseTransparentHugePages
            -XX:+AlwaysPreTouch -XX:+UseCompressedOops
            # HotSpot C2 Compiler
            -XX:+UseG1GC -XX:+TieredCompilation -XX:CompileThreshold=1000 -XX:+DisableExplicitGC
            -XX:ReservedCodeCacheSize=400M -XX:InitialCodeCacheSize=256M
            # GC tuning
            "-XX:ConcGCThreads=$((CPU_CORES/2))" "-XX:ParallelGCThreads=${CPU_CORES}"
            -XX:MaxGCPauseMillis=50 -XX:InitiatingHeapOccupancyPercent=30
            -XX:G1NewSizePercent=35 -XX:G1ReservePercent=20
            -XX:G1HeapRegionSize=16M -XX:G1MixedGCCountTarget=3
            -XX:MaxTenuringThreshold=1 -XX:SurvivorRatio=8
            -XX:+ParallelRefProcEnabled -XX:+UseTLAB
            # Optimizations
            -XX:-DontCompileHugeMethods -XX:+AggressiveOpts -XX:+AlwaysActAsServerClassMachine
            -XX:+OptimizeStringConcat -XX:+UseCompactObjectHeaders
            -XX:+UseStringDeduplication --add-modules=jdk.incubator.vector -da
            -XX:+UseCMoveUnconditionally -XX:+UseNewLongLShift
            -XX:+UseVectorCmov -XX:+UseXmmI2D -XX:+UseXmmI2F
            -XX:+UseFastAccessorMethods -XX:+UseInlineCaches
            -XX:+RangeCheckElimination -XX:+EliminateLocks -XX:+OptimizeFill
        );;
    fabric|default|*)
        JAVA_CMD="${JAVA_CMD:-$(command -v java 2>/dev/null)}"
        echo "[*] Using Default JDK: $JAVA_CMD"
        JVM_FLAGS=(
            # Memory
            "-Xms${XMS}" "-Xmx${XMX}"
            -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+IgnoreUnrecognizedVMOptions 
            -XX:+UseTransparentHugePages -XX:+AlwaysPreTouch
            # GC Configuration
            -XX:+UseG1GC -XX:+AlwaysActAsServerClassMachine -XX:+DisableExplicitGC
            -XX:MaxGCPauseMillis=130 -XX:G1NewSizePercent=28 -XX:G1HeapRegionSize=16M
            -XX:G1ReservePercent=20 -XX:G1MixedGCCountTarget=3
            -XX:InitiatingHeapOccupancyPercent=10 -XX:G1MixedGCLiveThresholdPercent=90
            -XX:G1RSetUpdatingPauseTimePercent=0 -XX:SurvivorRatio=32 -XX:MaxTenuringThreshold=1
            -XX:G1SATBBufferEnqueueingThresholdPercent=30 -XX:G1ConcMarkStepDurationMillis=5.0
            -XX:AllocatePrefetchStyle=3 -XX:ConcGCThreads=2
            # Code Cache
            -XX:ReservedCodeCacheSize=400M -XX:NonNMethodCodeHeapSize=12M
            -XX:ProfiledCodeHeapSize=194M -XX:NonProfiledCodeHeapSize=194M
            -XX:+SegmentedCodeCache
            # Compiler
            -XX:-DontCompileHugeMethods -XX:MaxNodeLimit=240000 -XX:NodeLimitFudgeFactor=8000
            -XX:NmethodSweepActivity=1
            # Performance
            -XX:+UseStringDeduplication -XX:+UseFMA -XX:+ParallelRefProcEnabled
            -XX:+UseTLAB -XX:+UseCompressedOops -XX:+OptimizeStringConcat
            -XX:+RangeCheckElimination -XX:+UseLoopPredicate -XX:+OmitStackTraceInFastThrow
            -XX:+UseNewLongLShift -XX:+UseFPUForSpilling -XX:+EliminateLocks -XX:+OptimizeFill
            # Vector & SIMD
            -XX:+EnableVectorSupport -XX:+UseVectorStubs -XX:+UseVectorCmov
            # Memory & Cache
            -XX:+UseFastJNIAccessors -XX:+UseInlineCaches -XX:+PerfDisableSharedMem
            # Thread Priority
            -XX:+UseCriticalJavaThreadPriority -XX:ThreadPriorityPolicy=1
            -XX:+UseFastUnorderedTimeStamps
            # Logging
            -Xlog:async,gc*:file=/dev/null -Dfile.encoding=UTF-8
        )
        ;;
esac

# ─── Playit Integration ─────────────────────────────────────────────────────────

if [[ "$ENABLE_PLAYIT" == "true" ]] && has_command playit; then
    echo "[*] Starting playit for server hosting..."
    { setsid nohup playit &>/dev/null & } || echo "[!] Warning: Failed to start playit"
    read -rt 2 -- <> <(:) &>/dev/null || :
elif [[ "$ENABLE_PLAYIT" == "true" ]]; then
    echo "[!] Warning: playit not found. Install from: https://playit.gg"
fi

# ─── Launch Server ──────────────────────────────────────────────────────────────
LAUNCH_CMD=()
# CPU affinity
if has_command taskset && [[ "$ENABLE_OPTIMIZATIONS" == "true" ]]; then
    LAUNCH_CMD+=(taskset -c "0-$((CPU_CORES-1))")
    echo "[*] CPU affinity: cores 0-$((CPU_CORES-1))"
fi
# Gamemode
if [[ "$ENABLE_GAMEMODE" == "true" ]] && has_command gamemoderun; then
    LAUNCH_CMD+=(sudo gamemoderun)
    echo "[*] Using gamemoderun"
fi
LAUNCH_CMD+=("$JAVA_CMD" "${JVM_FLAGS[@]}" -jar "$SERVER_JAR" --nogui)

echo ""
echo "─────────────────────────────────────────────────────────────"
echo "[*] Starting Minecraft Server"
echo "[*] JAR: $SERVER_JAR | Memory: ${XMS} - ${XMX}"
echo "─────────────────────────────────────────────────────────────"
echo ""

# Launch
if [[ "$USE_ALACRITTY" == "true" ]] && has_command alacritty; then
    echo "[*] Launching in Alacritty..."
    alacritty -e bash -c "${LAUNCH_CMD[*]}"
else
    exec "${LAUNCH_CMD[@]}"
fi
