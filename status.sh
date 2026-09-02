#!/bin/bash

cd "$(dirname "$0")"

if [ -f server.pid ]; then
    PID=$(cat server.pid)

    if kill -0 "$PID" 2>/dev/null; then
        echo "================================"
        echo " Minecraft Server Status"
        echo "================================"
        echo "Status : RUNNING"
        echo "PID    : $PID"

        echo ""
        echo "Memory Usage:"
        ps -p "$PID" -o %mem,rss,etime

    else
        echo "================================"
        echo " Minecraft Server Status"
        echo "================================"
        echo "Status : STOPPED"
        echo "Note   : PID file exists but process is not running."

        rm -f server.pid
    fi
else
    echo "================================"
    echo " Minecraft Server Status"
    echo "================================"

    if pgrep -f "purpur.jar" > /dev/null; then
        PID=$(pgrep -f "purpur.jar" | head -n 1)

        echo "Status : RUNNING"
        echo "PID    : $PID"
    else
        echo "Status : STOPPED"
    fi
fi
