#!/bin/bash

cd "$(dirname "$0")"

if pgrep -f "purpur.jar" > /dev/null; then
    echo "Minecraft server is already running."
    exit 1
fi

nohup java -Xms2G -Xmx4G \
-XX:+UseG1GC \
-XX:+ParallelRefProcEnabled \
-XX:MaxGCPauseMillis=200 \
-XX:+DisableExplicitGC \
-XX:+AlwaysPreTouch \
-XX:G1ReservePercent=20 \
-XX:InitiatingHeapOccupancyPercent=15 \
-XX:+PerfDisableSharedMem \
-jar purpur.jar nogui > server.log 2>&1 &

echo $! > server.pid

echo "Minecraft server started. PID: $!"
