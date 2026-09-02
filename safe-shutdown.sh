#!/bin/bash

# Minecraft Server Safe Shutdown Script
# This script will:
# 1. Announce server shutdown at intervals
# 2. Save all player data and worlds
# 3. Safely stop the server

# Variables
SCREEN_NAME="minecraft_server"
CANCEL_FILE="/tmp/cancel_shutdown.tmp"
LOG_FILE="server-shutdown.log"

# Function to send command to the Minecraft server
send_command() {
    local command="$1"
    if screen -list | grep -q "$SCREEN_NAME"; then
        screen -S "$SCREEN_NAME" -p 0 -X stuff "$command$(printf '\r')"
    else
        # If not running in screen, try direct input to server process
        echo "$command" > /proc/$(pgrep -f "java.*paper.jar")/fd/0 2>/dev/null || echo "$command" >> server_commands.txt
    fi
    echo "[$(date)] Sent command: $command" >> "$LOG_FILE"
}

# Function to broadcast message
broadcast() {
    local message="$1"
    local color="$2"
    send_command "tellraw @a {\"text\":\"$message\",\"color\":\"$color\",\"bold\":true}"
    echo "[$(date)] Broadcast: $message" >> "$LOG_FILE"
}

# Function to check if shutdown should be canceled
check_cancel() {
    if [ -f "$CANCEL_FILE" ]; then
        broadcast "Server shutdown has been CANCELED!" "green"
        rm -f "$CANCEL_FILE"
        echo "[$(date)] Shutdown cancelled by admin" >> "$LOG_FILE"
        exit 0
    fi
}

# Function to cancel shutdown
cancel_shutdown() {
    touch "$CANCEL_FILE"
    echo "[$(date)] Cancel flag created" >> "$LOG_FILE"
    echo "Shutdown will be cancelled at the next check."
}

# Start log
echo "[$(date)] Starting server shutdown sequence" > "$LOG_FILE"

# Create cancel instructions
echo "To cancel the shutdown, run: touch $CANCEL_FILE"
echo "Or run: $0 cancel"

# Check for cancel argument
if [ "$1" = "cancel" ]; then
    cancel_shutdown
    echo "Shutdown cancellation requested. If a shutdown is in progress, it will be cancelled at the next announcement."
    exit 0
fi

# 5 minute warning
broadcast "WARNING: Server will shutdown in 5 minutes!" "gold"
broadcast "Please finish your work and log out safely." "gold"
sleep 240  # 4 minutes
check_cancel

# 1 minute warning
broadcast "WARNING: Server will shutdown in 1 minute!" "red"
broadcast "Save your progress and prepare to log out!" "red"
sleep 30   # 30 seconds
check_cancel

# 30 second warning
broadcast "FINAL WARNING: Server shutdown in 30 seconds!" "dark_red"
sleep 20   # 20 seconds
check_cancel

# 10 second countdown
for i in {10..1}; do
    broadcast "Shutting down in $i seconds..." "dark_red"
    sleep 1
    check_cancel
done

# Save all data
broadcast "Saving world data... Please wait!" "aqua"
send_command "save-all flush"
sleep 5

# Stop the server
broadcast "Server is now shutting down. Thank you for playing!" "light_purple"
sleep 2
send_command "stop"

echo "[$(date)] Shutdown sequence completed" >> "$LOG_FILE"
echo "Server shutdown complete. Check $LOG_FILE for details."

