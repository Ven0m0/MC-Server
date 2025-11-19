#!/usr/bin/env bash
# server-start.sh: Unified Minecraft server launcher with playit integration
# Consolidates launcher.sh, start.sh, and Server.sh functionality

# Source common functions (SCRIPT_DIR is auto-initialized)
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

init_strict_mode

# Alias for consistency with rest of script
has() { has_command "$@"; }

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
check_dependencies java || exit 1
[[ ! -f "$SERVER_JAR" ]] && {
    print_error "Server jar not found: ${SERVER_JAR}"
    print_info "Set SERVER_JAR environment variable or place server.jar in current directory"
    exit 1
}

# ─── System Optimizations ───────────────────────────────────────────────────────
if [[ "$ENABLE_OPTIMIZATIONS" == "true" ]]; then
    print_header "Applying system optimizations..."
    [[ $EUID -ne 0 ]] && sudo -v
    echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled &>/dev/null || :
    echo always | sudo tee /sys/kernel/mm/transparent_hugepage/shmem_enabled &>/dev/null || :
    [[ -e /sys/block/nvme0n1/queue/scheduler ]] && echo kyber | sudo tee /sys/block/nvme0n1/queue/scheduler &>/dev/null || :
    has powerprofilesctl && powerprofilesctl set performance &>/dev/null || :
    echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor &>/dev/null || :
    sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null || :
    print_success "System optimizations applied"
fi

# ─── Memory Configuration ───────────────────────────────────────────────────────
CPU_CORES=$(get_cpu_cores)
HEAP_SIZE=$(get_heap_size_gb 2)
[[ $HEAP_SIZE -lt $MIN_HEAP_GB ]] && HEAP_SIZE=$MIN_HEAP_GB
XMS="${HEAP_SIZE}G"
XMX="${HEAP_SIZE}G"
print_info "Memory: ${XMS} - ${XMX} | CPU Cores: ${CPU_CORES}"

# ─── JDK Detection and Configuration ────────────────────────────────────────────
if has archlinux-java; then
    sudo archlinux-java fix 2>/dev/null || :
    SEL_JAVA="$(archlinux-java get 2>/dev/null)"
    JAVA_CMD="${SEL_JAVA:-/usr/lib/jvm/default-runtime/bin/java}"
elif has mise; then
    JAVA_CMD="$(mise which java 2>/dev/null)"
elif [[ -d "${HOME}/.local/share/mise/installs/java/oracle-graalvm-latest" ]]; then
    JAVA_CMD="${HOME}/.local/share/mise/installs/java/oracle-graalvm-latest/bin/java"
elif [[ -d "${HOME}/.local/share/mise/installs/java/temurin-latest" ]]; then
    JAVA_CMD="${HOME}/.local/share/mise/installs/java/temurin-latest/bin/java"
fi
BASE_FLAGS=(
    -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+IgnoreUnrecognizedVMOptions
    -Dfile.encoding=UTF-8 -Dawt.useSystemAAFontSettings=on -Dswing.aatext=true --illegal-access=permit
    -Xlog:async,gc*:file=/dev/null -Djdk.util.zip.disableZip64ExtraFieldValidation=true
    -Djdk.nio.zipfs.allowDotZipEntry=true -XX:+AlwaysPreTouch -XX:+AlwaysActAsServerClassMachine
    -XX:+DisableExplicitGC -XX:+UseCompressedOops -XX:-DontCompileHugeMethods
    -XX:+OptimizeStringConcat -XX:+OptimizeFill
)
LARGE_PAGES=(-XX:+UseLargePages -XX:LargePageSizeInBytes=2M -XX:+UseLargePagesInMetaspace -XX:+UseTransparentHugePages)

case "$MC_JDK" in
    graalvm)
        JAVA_CMD="${JAVA_GRAALVM:-/usr/lib/jvm/default-runtime/bin/java}"
        [[ ! -x "$JAVA_CMD" ]] && JAVA_CMD=$(command -v java)
        print_info "Using GraalVM: $JAVA_CMD"
        JVM_FLAGS=(
            "${BASE_FLAGS[@]}" "-Xms${XMS}" "-Xmx${XMX}" "${LARGE_PAGES[@]}"
            # GraalVM JVMCI Compiler
            -XX:+UseG1GC -XX:+UseJVMCICompiler -XX:+EagerJVMCI
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
            -XX:+AggressiveOpts
            -XX:+UseCompactObjectHeaders
            -XX:+UseStringDeduplication --add-modules=jdk.incubator.vector -da
            -XX:+UseCMoveUnconditionally -XX:+UseNewLongLShift
            -XX:+UseVectorCmov -XX:+UseXmmI2D -XX:+UseXmmI2F -XX:+UseFastAccessorMethods
        );;
    temurin)
        JAVA_CMD="${JAVA_TEMURIN:-/usr/lib/jvm/java-25-temurin/bin/java}"
        [[ ! -x "$JAVA_CMD" ]] && JAVA_CMD=$(command -v java)
        print_info "Using Temurin: $JAVA_CMD"
        JVM_FLAGS=(
            "${BASE_FLAGS[@]}" "-Xms${XMS}" "-Xmx${XMX}" "${LARGE_PAGES[@]}"
            # HotSpot C2 Compiler
            -XX:+UseG1GC -XX:+TieredCompilation -XX:CompileThreshold=1000
            -XX:ReservedCodeCacheSize=400M -XX:InitialCodeCacheSize=256M
            # GC tuning
            "-XX:ConcGCThreads=$((CPU_CORES/2))" "-XX:ParallelGCThreads=${CPU_CORES}"
            -XX:MaxGCPauseMillis=50 -XX:InitiatingHeapOccupancyPercent=30
            -XX:G1NewSizePercent=35 -XX:G1ReservePercent=20
            -XX:G1HeapRegionSize=16M -XX:G1MixedGCCountTarget=3
            -XX:MaxTenuringThreshold=1 -XX:SurvivorRatio=8
            -XX:+ParallelRefProcEnabled -XX:+UseTLAB
            # Optimizations
            -XX:+AggressiveOpts
            -XX:+UseCompactObjectHeaders
            -XX:+UseStringDeduplication --add-modules=jdk.incubator.vector -da
            -XX:+UseCMoveUnconditionally -XX:+UseNewLongLShift
            -XX:+UseVectorCmov -XX:+UseXmmI2D -XX:+UseXmmI2F
            -XX:+UseFastAccessorMethods -XX:+UseInlineCaches
            -XX:+RangeCheckElimination -XX:+EliminateLocks
        );;
    fabric|default|*)
        JAVA_CMD="${JAVA_CMD:-$(command -v java 2>/dev/null)}"
        print_info "Using Default JDK: $JAVA_CMD"
        JVM_FLAGS=(
            # Memory
            "${BASE_FLAGS[@]}" "-Xms${XMS}" "-Xmx${XMX}" "${LARGE_PAGES[@]}"
            # GC Configuration
            -XX:+UseG1GC
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
            -XX:MaxNodeLimit=240000 -XX:NodeLimitFudgeFactor=8000
            -XX:NmethodSweepActivity=1
            # Performance
            -XX:+UseStringDeduplication -XX:+UseFMA -XX:+ParallelRefProcEnabled
            -XX:+UseTLAB
            -XX:+RangeCheckElimination -XX:+UseLoopPredicate -XX:+OmitStackTraceInFastThrow
            -XX:+UseNewLongLShift -XX:+UseFPUForSpilling -XX:+EliminateLocks
            # Vector & SIMD
            -XX:+EnableVectorSupport -XX:+UseVectorStubs -XX:+UseVectorCmov
            # Memory & Cache
            -XX:+UseFastJNIAccessors -XX:+UseInlineCaches -XX:+PerfDisableSharedMem
            # Thread Priority
            -XX:+UseCriticalJavaThreadPriority -XX:ThreadPriorityPolicy=1
            -XX:+UseFastUnorderedTimeStamps
        );;
esac

# ─── Playit Integration ─────────────────────────────────────────────────────────
if [[ "$ENABLE_PLAYIT" == "true" ]] && has playit; then
    print_info "Starting playit for server hosting..."
    { setsid nohup playit &>/dev/null & } || print_error "Failed to start playit"
    read -rt 2 -- <> <(:) &>/dev/null || :
elif [[ "$ENABLE_PLAYIT" == "true" ]]; then
    print_info "playit not found. Install from: https://playit.gg"
fi

# ─── Launch Server ──────────────────────────────────────────────────────────────
LAUNCH_CMD=()
# CPU affinity
if has taskset && [[ "$ENABLE_OPTIMIZATIONS" == "true" ]]; then
    LAUNCH_CMD+=(taskset -c "0-$((CPU_CORES-1))")
    print_info "CPU affinity: cores 0-$((CPU_CORES-1))"
fi
# Gamemode
if [[ "$ENABLE_GAMEMODE" == "true" ]] && has gamemoderun; then
    LAUNCH_CMD+=(sudo gamemoderun)
    print_info "Using gamemoderun"
fi
LAUNCH_CMD+=("$JAVA_CMD" "${JVM_FLAGS[@]}" -jar "$SERVER_JAR" --nogui)

echo ""
echo "─────────────────────────────────────────────────────────────"
print_header "Starting Minecraft Server"
echo "  JAR: ${SERVER_JAR}"
echo "  Memory: ${XMS} - ${XMX}"
echo "  CPU Cores: ${CPU_CORES}"
echo "─────────────────────────────────────────────────────────────"
echo ""

# Launch
if [[ "$USE_ALACRITTY" == "true" ]] && has alacritty; then
    print_info "Launching in Alacritty..."
    alacritty -e bash -c "${LAUNCH_CMD[*]}"
elif command -v rio &>/dev/null; then
  print_info "Launching in Rio..."
  rio -e bash -c "${LAUNCH_CMD[*]}"
elif command -v ghostty &>/dev/null; then
  print_info "Launching in Ghostty..."
  ghostty -e bash -c "${LAUNCH_CMD[*]}"
else
  exec "${LAUNCH_CMD[@]}"
fi
