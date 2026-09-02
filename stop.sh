#!/bin/bash

cd "$(dirname "$0")"

if [ -f server.pid ]; then
    PID=$(cat server.pid)

    if kill -0 "$PID" 2>/dev/null; then
        echo "Stopping Minecraft server..."

        kill -SIGTERM "$PID"

        # Wait up to 30 seconds
        for i in {1..30}; do
            if ! kill -0 "$PID" 2>/dev/null; then
                rm -f server.pid
                echo "Minecraft server stopped."
                exit 0
            fi
            sleep 1
        done

        echo "Server did not stop gracefully. Force stopping..."
        kill -9 "$PID"
        rm -f server.pid
    else
        echo "Server process not running."
        rm -f server.pid
    fi
else
    echo "Minecraft server is not running."
fi
