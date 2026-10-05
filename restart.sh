#!/bin/bash

cd "$(dirname "$0")"

echo "Restarting Minecraft server..."

./stop.sh

sleep 1

./start.sh
