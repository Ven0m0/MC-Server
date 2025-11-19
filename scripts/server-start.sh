#!/usr/bin/env bash
# server-start.sh: Simplified Minecraft server launcher

# Source common functions
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

init_strict_mode

# Configuration
: "${SERVER_JAR:=server.jar}"
: "${ENABLE_PLAYIT:=true}"
: "${MIN_HEAP_GB:=4}"

# Validation
check_dependencies java || exit 1
[[ ! -f "$SERVER_JAR" ]] && {
    print_error "Server jar not found: ${SERVER_JAR}"
    exit 1
}

# Memory Configuration
CPU_CORES=$(get_cpu_cores)
HEAP_SIZE=$(get_heap_size_gb 2)
[[ $HEAP_SIZE -lt $MIN_HEAP_GB ]] && HEAP_SIZE=$MIN_HEAP_GB
XMS="${HEAP_SIZE}G"
XMX="${HEAP_SIZE}G"

print_info "Memory: ${XMS} - ${XMX} | CPU Cores: ${CPU_CORES}"

# JDK Detection
JAVA_CMD="java"
if has_command archlinux-java; then
    sudo archlinux-java fix 2>/dev/null || :
    SEL_JAVA="$(archlinux-java get 2>/dev/null)"
    [[ -n "$SEL_JAVA" ]] && JAVA_CMD="/usr/lib/jvm/${SEL_JAVA}/bin/java"
elif has_command mise; then
    JAVA_CMD="$(mise which java 2>/dev/null)" || JAVA_CMD="java"
fi

# Simplified JVM Flags
JVM_FLAGS=(
    "-Xms${XMS}" "-Xmx${XMX}"
    -XX:+UseG1GC
    -XX:+UnlockExperimentalVMOptions
    -XX:MaxGCPauseMillis=50
    -XX:G1NewSizePercent=30
    -XX:G1ReservePercent=15
    -XX:G1HeapRegionSize=16M
    -XX:+AlwaysPreTouch
    -XX:+DisableExplicitGC
    -XX:+ParallelRefProcEnabled
    "-XX:ParallelGCThreads=${CPU_CORES}"
    -Dfile.encoding=UTF-8
)

# Playit Integration
if [[ "$ENABLE_PLAYIT" == "true" ]] && has_command playit; then
    print_info "Starting playit..."
    { setsid nohup playit &>/dev/null & } || :
    sleep 2
fi

# Launch Server
print_header "Starting Minecraft Server"
echo "  JAR: ${SERVER_JAR}"
echo "  Memory: ${XMS} - ${XMX}"
echo "  CPU Cores: ${CPU_CORES}"
echo ""

exec "$JAVA_CMD" "${JVM_FLAGS[@]}" -jar "$SERVER_JAR" --nogui
