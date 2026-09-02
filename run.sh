#!/bin/bash
java -Xms2G -Xmx4G \
-XX:+UseG1GC \
-XX:+ParallelRefProcEnabled \
-XX:MaxGCPauseMillis=200 \
-XX:+DisableExplicitGC \
-XX:+AlwaysPreTouch \
-XX:G1ReservePercent=20 \
-XX:InitiatingHeapOccupancyPercent=15 \
-XX:+PerfDisableSharedMem \
-jar purpur.jar nogui