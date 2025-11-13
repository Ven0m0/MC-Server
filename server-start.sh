#!/usr/bin/env bash
# server-start.sh: Unified Minecraft server launcher with playit integration
# Combines launcher.sh, start.sh, and Server.sh functionality

# Source common functions
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

init_strict_mode
cd_script_dir

# ─── Configuration ──────────────────────────────────────────────────────────────

# Default settings (can be overridden via environment variables)
: "${MC_JDK:=graalvm}"                    # JDK type: graalvm, temurin, or default
: "${SERVER_JAR:=server.jar}"             # Server jar file
: "${USE_ALACRITTY:=false}"               # Launch in Alacritty terminal
: "${ENABLE_PLAYIT:=true}"                # Enable playit for hosting
: "${ENABLE_OPTIMIZATIONS:=true}"         # Enable system optimizations
: "${ENABLE_GAMEMODE:=false}"             # Use gamemoderun
: "${MIN_HEAP_GB:=4}"                     # Minimum heap size

# ─── Validation ─────────────────────────────────────────────────────────────────

has_command java || { echo >&2 "No JDK found. Install Java and try again."; exit 1; }

if [[ ! -f "$SERVER_JAR" ]]; then
    echo >&2 "Server jar not found: $SERVER_JAR"
    echo >&2 "Set SERVER_JAR environment variable or place server.jar in current directory"
    exit 1
fi

# ─── System Optimizations ───────────────────────────────────────────────────────

if [[ "$ENABLE_OPTIMIZATIONS" == "true" ]]; then
    echo "[*] Applying system optimizations..."

    # Require sudo for optimizations
    [[ $EUID -ne 0 ]] && sudo -v

    # Transparent huge pages
    sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null <<< 'madvise' 2>/dev/null || true

    # CPU performance profile
    powerprofilesctl set performance 2>/dev/null || true

    # I/O scheduler (if nvme exists)
    if [[ -e /sys/block/nvme0n1/queue/scheduler ]]; then
        echo kyber | sudo tee /sys/block/nvme0n1/queue/scheduler >/dev/null 2>&1 || true
    fi

    # CPU governor
    echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true

    # Clear caches
    sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null || true

    echo "[✓] System optimizations applied"
fi

# ─── Memory Configuration ───────────────────────────────────────────────────────

CPU_CORES=$(get_cpu_cores)
HEAP_SIZE=$(get_heap_size_gb 2)

# Ensure minimum heap size
[[ $HEAP_SIZE -lt $MIN_HEAP_GB ]] && HEAP_SIZE=$MIN_HEAP_GB

XMS="${HEAP_SIZE}G"
XMX="${HEAP_SIZE}G"

echo "[*] Memory: ${XMS} - ${XMX} | CPU Cores: ${CPU_CORES}"

# ─── JDK Detection and Configuration ────────────────────────────────────────────

# Auto-detect Java command
if has_command archlinux-java; then
    sudo archlinux-java fix 2>/dev/null || true
    DETECTED_JAVA="$(archlinux-java get 2>/dev/null)"
    [[ -n "$DETECTED_JAVA" ]] && JAVA_CMD="$DETECTED_JAVA"
fi

# JDK-specific optimized flags
case "$MC_JDK" in
    graalvm)
        JAVA_CMD="${JAVA_GRAALVM:-/usr/lib/jvm/graalvm-ce-java21/bin/java}"
        [[ ! -x "$JAVA_CMD" ]] && JAVA_CMD=$(command -v java)

        echo "[*] Using GraalVM JDK: $JAVA_CMD"

        # GraalVM Enterprise optimizations
        JVM_FLAGS=(
            -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions
            -XX:+IgnoreUnrecognizedVMOptions --illegal-access=permit
            -Dfile.encoding=UTF-8
            -Djdk.util.zip.disableZip64ExtraFieldValidation=true
            -Djdk.nio.zipfs.allowDotZipEntry=true
            -Xlog:async,gc*:file=/dev/null
            # Memory
            "-Xms${XMS}" "-Xmx${XMX}"
            -XX:+UseLargePages -XX:+UseTransparentHugePages
            -XX:LargePageSizeInBytes=2M -XX:+UseLargePagesInMetaspace
            -XX:+AlwaysPreTouch -XX:+UseCompressedOops
            # GraalVM JVMCI Compiler
            -XX:+UseG1GC -XX:+UseJVMCICompiler
            -XX:+EagerJVMCI -Djdk.graal.CompilerConfiguration=enterprise
            -Djdk.graal.UsePriorityInlining=true -Djdk.graal.Vectorization=true
            -Djdk.graal.OptDuplication=true -Djdk.graal.TuneInlinerExploration=1
            -XX:CompileThreshold=500 -XX:+TieredStopAtLevel=4
            # GC tuning for GraalVM
            "-XX:ConcGCThreads=$((CPU_CORES/2))" "-XX:ParallelGCThreads=${CPU_CORES}"
            -XX:MaxGCPauseMillis=50 -XX:InitiatingHeapOccupancyPercent=15
            -XX:G1NewSizePercent=30 -XX:G1ReservePercent=15
            -XX:G1HeapRegionSize=16M -XX:G1MixedGCCountTarget=4
            # Optimizations
            -XX:-DontCompileHugeMethods -XX:+AggressiveOpts
            -XX:+OptimizeStringConcat -XX:+UseCompactObjectHeaders
            -XX:+UseStringDeduplication --add-modules=jdk.incubator.vector -da
            -XX:+UseCMoveUnconditionally -XX:+UseNewLongLShift
            -XX:+UseVectorCmov -XX:+UseXmmI2D -XX:+UseXmmI2F
            -XX:+UseFastAccessorMethods
        )
        ;;
    temurin)
        JAVA_CMD="${JAVA_TEMURIN:-/usr/lib/jvm/java-25-temurin/bin/java}"
        [[ ! -x "$JAVA_CMD" ]] && JAVA_CMD=$(command -v java)

        echo "[*] Using Temurin/OpenJDK: $JAVA_CMD"

        # Temurin/OpenJDK HotSpot optimizations
        JVM_FLAGS=(
            -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions
            -XX:+IgnoreUnrecognizedVMOptions --illegal-access=permit
            -Dfile.encoding=UTF-8
            -Djdk.util.zip.disableZip64ExtraFieldValidation=true
            -Djdk.nio.zipfs.allowDotZipEntry=true
            -Xlog:async,gc*:file=/dev/null
            # Memory
            "-Xms${XMS}" "-Xmx${XMX}"
            -XX:+UseLargePages -XX:+UseTransparentHugePages
            -XX:LargePageSizeInBytes=2M -XX:+UseLargePagesInMetaspace
            -XX:+AlwaysPreTouch -XX:+UseCompressedOops
            # HotSpot C2 Compiler
            -XX:+UseG1GC -XX:+TieredCompilation -XX:CompileThreshold=1000
            -XX:ReservedCodeCacheSize=400M -XX:InitialCodeCacheSize=256M
            # GC tuning for Temurin
            "-XX:ConcGCThreads=$((CPU_CORES/2))" "-XX:ParallelGCThreads=${CPU_CORES}"
            -XX:MaxGCPauseMillis=50 -XX:InitiatingHeapOccupancyPercent=30
            -XX:G1NewSizePercent=35 -XX:G1ReservePercent=20
            -XX:G1HeapRegionSize=16M -XX:G1MixedGCCountTarget=3
            -XX:MaxTenuringThreshold=1 -XX:SurvivorRatio=8
            -XX:+ParallelRefProcEnabled -XX:+UseTLAB
            # Optimizations
            -XX:-DontCompileHugeMethods -XX:+AggressiveOpts
            -XX:+OptimizeStringConcat -XX:+UseCompactObjectHeaders
            -XX:+UseStringDeduplication --add-modules=jdk.incubator.vector -da
            -XX:+UseCMoveUnconditionally -XX:+UseNewLongLShift
            -XX:+UseVectorCmov -XX:+UseXmmI2D -XX:+UseXmmI2F
            -XX:+UseFastAccessorMethods -XX:+UseInlineCaches
            -XX:+RangeCheckElimination -XX:+EliminateLocks -XX:+OptimizeFill
        )
        ;;
    fabric|default|*)
        JAVA_CMD="${JAVA_CMD:-$(command -v java)}"

        echo "[*] Using Default JDK: $JAVA_CMD"

        # G1GC-tuned flags for Fabric and other servers
        JVM_FLAGS=(
            # Memory
            "-Xms${XMS}" "-Xmx${XMX}"
            -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions
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
            # Performance Optimizations
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
            # Logging & Encoding
            -Xlog:async,gc*:file=/dev/null -Dfile.encoding=UTF-8
        )
        ;;
esac

# ─── Playit Integration ─────────────────────────────────────────────────────────

if [[ "$ENABLE_PLAYIT" == "true" ]]; then
    if has_command playit; then
        echo "[*] Starting playit for server hosting..."
        # Start playit in detached background session
        { setsid nohup playit >/dev/null 2>&1 & } || echo "[!] Warning: Failed to start playit"
        # Small delay to let playit initialize
        sleep 2
    else
        echo "[!] Warning: playit command not found. Skipping playit integration."
        echo "    Install playit from: https://playit.gg"
    fi
fi

# ─── CPU Affinity ───────────────────────────────────────────────────────────────

# Set CPU affinity if taskset is available
if has_command taskset && [[ "$ENABLE_OPTIMIZATIONS" == "true" ]]; then
    TASKSET_CMD=(taskset -c "0-$((CPU_CORES-1))")
    echo "[*] CPU affinity: cores 0-$((CPU_CORES-1))"
else
    TASKSET_CMD=()
fi

# ─── Launch Server ──────────────────────────────────────────────────────────────

# Build launch command
LAUNCH_CMD=("${TASKSET_CMD[@]}")

if [[ "$ENABLE_GAMEMODE" == "true" ]] && has_command gamemoderun; then
    LAUNCH_CMD+=(sudo gamemoderun)
    echo "[*] Using gamemoderun for performance boost"
fi

LAUNCH_CMD+=("$JAVA_CMD" "${JVM_FLAGS[@]}" -jar "$SERVER_JAR" --nogui)

echo ""
echo "─────────────────────────────────────────────────────────────"
echo "[*] Starting Minecraft Server"
echo "[*] JAR: $SERVER_JAR"
echo "[*] Heap: ${XMS} - ${XMX}"
echo "[*] Playit: $ENABLE_PLAYIT"
echo "─────────────────────────────────────────────────────────────"
echo ""

# Launch in Alacritty or current terminal
if [[ "$USE_ALACRITTY" == "true" ]] && has_command alacritty; then
    echo "[*] Launching in Alacritty terminal..."
    alacritty -e bash -c "${LAUNCH_CMD[*]}"
else
    # Direct execution in current terminal
    exec "${LAUNCH_CMD[@]}"
fi
