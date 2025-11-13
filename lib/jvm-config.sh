#!/usr/bin/env bash
# JVM configuration library for Minecraft server and client
# Provides optimized JVM flags for different JDK implementations and use cases

# Detect JDK implementation and set JAVA_CMD
# Sets: JAVA_CMD, MC_JDK (graalvm or temurin)
detect_jdk() {
    : "${MC_JDK:=graalvm}"
    : "${JAVA_CMD:=/usr/lib/jvm/default-runtime/bin/java}"

    if has_command archlinux-java; then
        sudo archlinux-java fix 2>/dev/null
        JAVA_CMD="$(archlinux-java get 2>/dev/null)"
    fi

    case "$MC_JDK" in
        graalvm)
            JAVA_CMD="${JAVA_GRAALVM:-/usr/lib/graalvm-ce-java21/bin/java}"
            ;;
        temurin|*)
            JAVA_CMD="${JAVA_TEMURIN:-/usr/lib/jvm/java-25-temurin/bin/java}"
            ;;
    esac

    export JAVA_CMD MC_JDK
}

# Base JVM flags common to all server configurations
_get_base_server_flags() {
    local xms="$1"
    local xmx="$2"
    local cpu_cores="${3:-$(get_cpu_cores)}"

    echo "-XX:+UnlockExperimentalVMOptions"
    echo "-XX:+UnlockDiagnosticVMOptions"
    echo "-XX:+IgnoreUnrecognizedVMOptions"
    echo "--illegal-access=permit"
    echo "-Dfile.encoding=UTF-8"
    echo "-Djdk.util.zip.disableZip64ExtraFieldValidation=true"
    echo "-Djdk.nio.zipfs.allowDotZipEntry=true"
    echo "-Xlog:async"
    echo "-Xlog:gc*:file=/dev/null"
    echo "-XX:+UseLargePages"
    echo "-XX:+UseTransparentHugePages"
    echo "-XX:LargePageSizeInBytes=2M"
    echo "-XX:+UseLargePagesInMetaspace"
    echo "-Xms${xms}G"
    echo "-Xmx${xmx}G"
    echo "-XX:ConcGCThreads=$((cpu_cores/2))"
    echo "-XX:ParallelGCThreads=${cpu_cores}"
    echo "-XX:+AlwaysPreTouch"
    echo "-XX:+UseFastAccessorMethods"
    echo "-XX:+UseCompressedOops"
    echo "-XX:-DontCompileHugeMethods"
    echo "-XX:+AggressiveOpts"
    echo "-XX:+OptimizeStringConcat"
    echo "-XX:+UseCompactObjectHeaders"
    echo "-XX:+UseStringDeduplication"
    echo "--add-modules=jdk.incubator.vector"
    echo "-da"
    echo "-XX:MaxGCPauseMillis=50"
    echo "-XX:InitiatingHeapOccupancyPercent=30"
    echo "-XX:+UseCMoveUnconditionally"
    echo "-XX:+UseNewLongLShift"
    echo "-XX:+UseVectorCmov"
    echo "-XX:+UseXmmI2D"
    echo "-XX:+UseXmmI2F"
}

# GraalVM-specific optimizations
_get_graalvm_flags() {
    echo "-XX:+UseG1GC"
    echo "-XX:+UseJVMCICompiler"
    echo "-XX:+TieredStopAtLevel=4"
    echo "-XX:CompileThreshold=500"
    echo "-Djdk.graal.CompilerConfiguration=enterprise"
    echo "-Djdk.graal.UsePriorityInlining=true"
    echo "-Djdk.graal.Vectorization=true"
    echo "-Djdk.graal.OptDuplication=true"
    echo "-Djdk.graal.TuneInlinerExploration=1"
}

# Temurin/OpenJDK-specific optimizations
_get_temurin_flags() {
    echo "-XX:+UseG1GC"
    echo "-XX:+TieredCompilation"
    echo "-XX:CompileThreshold=1000"
}

# G1GC-tuned flags for fabric server
_get_g1gc_tuned_flags() {
    echo "-XX:+UseG1GC"
    echo "-XX:+AlwaysActAsServerClassMachine"
    echo "-XX:+AlwaysPreTouch"
    echo "-XX:+DisableExplicitGC"
    echo "-XX:NmethodSweepActivity=1"
    echo "-XX:ReservedCodeCacheSize=400M"
    echo "-XX:NonNMethodCodeHeapSize=12M"
    echo "-XX:ProfiledCodeHeapSize=194M"
    echo "-XX:NonProfiledCodeHeapSize=194M"
    echo "-XX:-DontCompileHugeMethods"
    echo "-XX:MaxNodeLimit=240000"
    echo "-XX:NodeLimitFudgeFactor=8000"
    echo "-XX:+UseVectorCmov"
    echo "-XX:+PerfDisableSharedMem"
    echo "-XX:+UseFastUnorderedTimeStamps"
    echo "-XX:+UseCriticalJavaThreadPriority"
    echo "-XX:ThreadPriorityPolicy=1"
    echo "-XX:MaxGCPauseMillis=130"
    echo "-XX:G1NewSizePercent=28"
    echo "-XX:G1HeapRegionSize=16M"
    echo "-XX:G1ReservePercent=20"
    echo "-XX:G1MixedGCCountTarget=3"
    echo "-XX:InitiatingHeapOccupancyPercent=10"
    echo "-XX:G1MixedGCLiveThresholdPercent=90"
    echo "-XX:G1RSetUpdatingPauseTimePercent=0"
    echo "-XX:SurvivorRatio=32"
    echo "-XX:MaxTenuringThreshold=1"
    echo "-XX:G1SATBBufferEnqueueingThresholdPercent=30"
    echo "-XX:G1ConcMarkStepDurationMillis=5.0"
    echo "-XX:AllocatePrefetchStyle=3"
    echo "-XX:ConcGCThreads=2"
    echo "-XX:+UseTransparentHugePages"
    echo "-XX:+UseStringDeduplication"
    echo "-XX:+UseFMA"
    echo "-XX:+ParallelRefProcEnabled"
    echo "-XX:+UseTLAB"
    echo "-XX:+UseCompressedOops"
    echo "-XX:+OptimizeStringConcat"
    echo "-XX:+RangeCheckElimination"
    echo "-XX:+UseLoopPredicate"
    echo "-XX:+OmitStackTraceInFastThrow"
    echo "-XX:+UseNewLongLShift"
    echo "-XX:+UseFPUForSpilling"
    echo "-XX:+EliminateLocks"
    echo "-XX:+OptimizeFill"
    echo "-XX:+EnableVectorSupport"
    echo "-XX:+UseVectorStubs"
    echo "-XX:+UseFastJNIAccessors"
    echo "-XX:+UseInlineCaches"
    echo "-XX:+SegmentedCodeCache"
    echo "-Xlog:async"
}

# Client JVM flags (lighter weight)
_get_client_flags() {
    local xms="$1"
    local xmx="$2"

    echo "-Xms${xms}G"
    echo "-Xmx${xmx}G"
    echo "-XX:+UnlockExperimentalVMOptions"
    echo "-XX:+UseG1GC"
    echo "-XX:G1NewSizePercent=20"
    echo "-XX:G1ReservePercent=20"
    echo "-XX:MaxGCPauseMillis=50"
    echo "-XX:G1HeapRegionSize=32M"
}

# Build JVM flags array for launcher.sh (high-performance server)
# Usage: build_launcher_flags <xms_gb> <xmx_gb> <cpu_cores> <jdk_type>
build_launcher_flags() {
    local xms="$1"
    local xmx="$2"
    local cpu_cores="$3"
    local jdk_type="${4:-temurin}"

    local -a flags
    mapfile -t flags < <(_get_base_server_flags "$xms" "$xmx" "$cpu_cores")

    case "$jdk_type" in
        graalvm)
            mapfile -t -O "${#flags[@]}" flags < <(_get_graalvm_flags)
            ;;
        temurin|*)
            mapfile -t -O "${#flags[@]}" flags < <(_get_temurin_flags)
            ;;
    esac

    printf '%s\n' "${flags[@]}"
}

# Build JVM flags array for start.sh (G1GC-tuned fabric server)
# Usage: build_start_flags <xms_gb> <xmx_gb>
build_start_flags() {
    local xms="$1"
    local xmx="$2"

    printf '%s\n' "-Xms${xms}G" "-Xmx${xmx}G"
    _get_g1gc_tuned_flags
}

# Build JVM flags for client
# Usage: build_client_flags <xms_gb> <xmx_gb>
build_client_flags() {
    local xms="$1"
    local xmx="$2"

    _get_client_flags "$xms" "$xmx"
}

# Convenience function: Get all flags as array for launcher.sh
get_launcher_jvm_flags() {
    local xms="${1:-$(get_heap_size_gb 2)}"
    local xmx="${2:-$(get_heap_size_gb 2)}"
    local cpu_cores="${3:-$(get_cpu_cores)}"
    local jdk_type="${MC_JDK:-temurin}"

    build_launcher_flags "$xms" "$xmx" "$cpu_cores" "$jdk_type"
}

# Convenience function: Get all flags as array for start.sh
get_start_jvm_flags() {
    local heap_size="${1:-$(get_heap_size_gb 2)}"
    [[ $heap_size -lt 4 ]] && heap_size=4

    build_start_flags "$heap_size" "$heap_size"
}

# Convenience function: Get all flags for client
get_client_jvm_flags() {
    local xms="${1:-$(get_client_xms_gb)}"
    local xmx="${2:-$(get_client_xmx_gb)}"

    build_client_flags "$xms" "$xmx"
}
