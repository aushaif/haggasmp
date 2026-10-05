#!/bin/bash
# ============================================================
#  Minecraft Server Background Service
#  Usage: ./minecraft-server.sh {start|stop|gstop|restart|status|console|logs}
# ============================================================

# ---------- CONFIGURE THESE ----------
SERVER_DIR="/home/aushaif/haggasmp"          # Folder containing your server .jar
JAR_FILE="purpur.jar"                        # Your server jar file name
MIN_RAM="2G"                                 # Minimum RAM
MAX_RAM="4G"                                 # Maximum RAM
SCREEN_NAME="minecraft"                      # Background session name
# -------------------------------------

PID_FILE="$SERVER_DIR/.server.pid"

is_running() {
    screen -list | grep -q "\.${SCREEN_NAME}[[:space:]]"
}

start() {
    if is_running; then
        echo "⚠️  Server is already running."
        exit 1
    fi
    if [ ! -f "$SERVER_DIR/$JAR_FILE" ]; then
        echo "❌ Jar not found: $SERVER_DIR/$JAR_FILE"
        echo "   Edit SERVER_DIR and JAR_FILE at the top of this script."
        exit 1
    fi

    echo "🚀 Starting Minecraft server in background..."
    cd "$SERVER_DIR" || exit 1
    screen -dmS "$SCREEN_NAME" bash -c \
        "java -Xms$MIN_RAM -Xmx$MAX_RAM -jar $JAR_FILE nogui; echo 'Server stopped.'; sleep 5"

    sleep 3
    if is_running; then
        echo "✅ Server started (session: $SCREEN_NAME)"
        echo "   Attach to console: $0 console"
    else
        echo "❌ Server failed to start. Check logs in $SERVER_DIR/logs/"
    fi
}

stop() {
    if ! is_running; then
        echo "⚠️  Server is not running."
        exit 1
    fi
    echo "⚡ Killing server immediately..."
    screen -S "$SCREEN_NAME" -X quit
    echo "✅ Server killed."
}

gstop() {
    if ! is_running; then
        echo "⚠️  Server is not running."
        exit 1
    fi
    echo "🛑 Stopping server gracefully..."
    screen -S "$SCREEN_NAME" -p 0 -X stuff "stop^M"
    # Wait up to 30s for graceful shutdown
    for i in $(seq 1 30); do
        is_running || { echo "✅ Server stopped."; return; }
        sleep 1
    done
    echo "⚠️  Forcing kill..."
    screen -S "$SCREEN_NAME" -X quit
    echo "✅ Server killed."
}

status() {
    if is_running; then
        # Get screen session PID
        screen_pid=$(screen -list | grep "\.${SCREEN_NAME}[[:space:]]" | awk '{print $1}' | cut -d. -f1)
        # Find Java child process PID
        java_pid=$(pgrep -P "$screen_pid" -f java 2>/dev/null | head -1)
        
        if [[ -n $java_pid ]]; then
            # Get process start time (macOS: lstart format)
            start_str=$(ps -o lstart= -p "$java_pid" 2>/dev/null | xargs)
            if [[ -n $start_str ]]; then
                # Parse: "Mon Sep  8 22:30:15 2024"
                start_epoch=$(date -j -f "%a %b %d %H:%M:%S %Y" "$start_str" +%s 2>/dev/null)
                if [[ -n $start_epoch ]]; then
                    now_epoch=$(date +%s)
                    diff=$((now_epoch - start_epoch))
                    days=$((diff / 86400))
                    hours=$(( (diff % 86400) / 3600 ))
                    mins=$(( (diff % 3600) / 60 ))
                    secs=$((diff % 60))
                    uptime=""
                    [[ $days -gt 0 ]] && uptime+="${days}d "
                    [[ $hours -gt 0 ]] && uptime+="${hours}h "
                    [[ $mins -gt 0 ]] && uptime+="${mins}m "
                    uptime+="${secs}s"
                    echo "🟢 Server is RUNNING (session: $SCREEN_NAME)"
                    echo "   Uptime: $uptime"
                else
                    echo "🟢 Server is RUNNING (session: $SCREEN_NAME)"
                fi
            else
                echo "🟢 Server is RUNNING (session: $SCREEN_NAME)"
            fi
        else
            echo "🟢 Server is RUNNING (session: $SCREEN_NAME)"
        fi
    else
        echo "🔴 Server is NOT running."
    fi
}

console() {
    if ! is_running; then
        echo "❌ Server is not running."
        exit 1
    fi
    echo "Attaching to console... (Detach with Ctrl+A then D)"
    screen -r "$SCREEN_NAME"
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    gstop)   gstop ;;
    restart) stop; sleep 2; start ;;
    status)  status ;;
    console) console ;;
    logs)    tail -f "$SERVER_DIR/logs/latest.log" ;;
    *)
        echo "Usage: ./mc.sh {start|stop|gstop|restart|status|console|logs}"
        echo ""
        echo "Commands:"
        echo "  ./mc.sh start    - Start server in background"
        echo "  ./mc.sh stop     - Immediate kill (no graceful shutdown)"
        echo "  ./mc.sh gstop    - Graceful shutdown (saves world, waits up to 30s)"
        echo "  ./mc.sh restart  - Restart server (stop + start)"
        echo "  ./mc.sh status   - Show server status and uptime"
        echo "  ./mc.sh console  - Attach to server console (detach: Ctrl+A, D)"
        echo "  ./mc.sh logs     - Tail live server logs"
        exit 1
        ;;
esac
