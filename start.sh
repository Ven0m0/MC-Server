#!/usr/bin/env bash

# Source common functions (SCRIPT_DIR is auto-initialized)
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

sudo -v

# Calculate dynamic memory allocation (leaving 2GB for system)
HEAP_SIZE=$(get_heap_size_gb 2)
# Ensure minimum 4GB heap
[[ $HEAP_SIZE -lt 4 ]] && HEAP_SIZE=4

# G1GC-optimized configuration with dynamic memory
sudo gamemoderun java "-Xms${HEAP_SIZE}G" "-Xmx${HEAP_SIZE}G" \
  -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions \
  -XX:+UseG1GC -XX:+AlwaysActAsServerClassMachine -XX:+AlwaysPreTouch -XX:+DisableExplicitGC \
  -XX:NmethodSweepActivity=1 -XX:ReservedCodeCacheSize=400M \
  -XX:NonNMethodCodeHeapSize=12M -XX:ProfiledCodeHeapSize=194M -XX:NonProfiledCodeHeapSize=194M \
  -XX:-DontCompileHugeMethods -XX:MaxNodeLimit=240000 -XX:NodeLimitFudgeFactor=8000 \
  -XX:+UseVectorCmov -XX:+PerfDisableSharedMem -XX:+UseFastUnorderedTimeStamps \
  -XX:+UseCriticalJavaThreadPriority -XX:ThreadPriorityPolicy=1 \
  -XX:MaxGCPauseMillis=130 -XX:G1NewSizePercent=28 -XX:G1HeapRegionSize=16M \
  -XX:G1ReservePercent=20 -XX:G1MixedGCCountTarget=3 -XX:InitiatingHeapOccupancyPercent=10 \
  -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=0 \
  -XX:SurvivorRatio=32 -XX:MaxTenuringThreshold=1 -XX:G1SATBBufferEnqueueingThresholdPercent=30 \
  -XX:G1ConcMarkStepDurationMillis=5.0 -XX:AllocatePrefetchStyle=3 -XX:ConcGCThreads=2 \
  -XX:+UseTransparentHugePages -XX:+UseStringDeduplication \
  -XX:+UseFMA -XX:+ParallelRefProcEnabled -XX:+UseTLAB -XX:+UseCompressedOops \
  -XX:+OptimizeStringConcat -XX:+RangeCheckElimination -XX:+UseLoopPredicate \
  -XX:+OmitStackTraceInFastThrow -XX:+UseNewLongLShift -XX:+UseFPUForSpilling \
  -XX:+EliminateLocks -XX:+OptimizeFill \
  -XX:+EnableVectorSupport -XX:+UseVectorStubs -XX:+UseFastJNIAccessors \
  -XX:+UseInlineCaches -XX:+SegmentedCodeCache \
  -Xlog:async -Dfile.encoding=UTF-8 \
  -jar fabric-server.jar --nogui
