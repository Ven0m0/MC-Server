#!/usr/bin/env bash
# mc-launcher.sh: auto-tuned Minecraft JVM launcher

# Use Transparent Huge Pages (direct redirect is more efficient than echo pipe)
sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null <<< 'madvise'

JVM_FLAGS="
-XX:+UseZGC

"

# Detect CPU cores and RAM (in GB)
CPU_CORES=$(nproc)
TOTAL_RAM=$(awk '/MemTotal/ {printf "%.0f\n",$2/1024/1024}' /proc/meminfo)

# Compute heap sizes: leave ~2GB for OS / background
XMS=$((TOTAL_RAM - 2))
XMX=$((TOTAL_RAM - 2))
if (( XMS < 1 )); then XMS=1; XMX=1; fi

# Detect JDK selection: default Temurin
: "${MC_JDK:=temurin}"  # can set env MC_JDK=graalvm for GraalVM

case "$MC_JDK" in
  graalvm)
    JAVA_CMD=${JAVA_GRAALVM:-/usr/lib/graalvm-ce-java21}/bin/java
    JVM_FLAGS=(
      -XX:+UnlockExperimentalVMOptions
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
      -XX:+UseLargePages
      -XX:ParallelGCThreads="$CPU_CORES"
      -XX:ConcGCThreads=$((CPU_CORES/2))
      -Xms"${XMS}G"
      -Xmx"${XMX}G"
      -da
      -Xlog:gc*:file=/dev/null
    )
    ;;
  temurin|*)
    JAVA_CMD=${JAVA_TEMURIN:-/usr/lib/jvm/temurin-17}/bin/java
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
      -XX:ParallelGCThreads="$CPU_CORES"
      -XX:ConcGCThreads=$((CPU_CORES/2))
      -XX:+UseLargePages
      -Xms"${XMS}G"
      -Xmx"${XMX}G"
      -da
      -Xlog:gc*:file=/dev/null
    )
    ;;
esac

# Optional: pin CPU cores for consistent performance
TASKSET_CMD=(taskset -c 0-$((CPU_CORES-1)))

# Launch Minecraft server
"${TASKSET_CMD[@]}" "$JAVA_CMD" "${JVM_FLAGS[@]}" -jar server.jar nogui
