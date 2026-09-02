#!/bin/bash

cd "$(dirname "$0")"

echo "Restarting Minecraft server..."

./stop.sh

sleep 3

./start.sh
