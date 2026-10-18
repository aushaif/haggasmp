#!/bin/bash

# ============================================================
# Minecraft Live Player Monitor
# macOS + Linux
# Paper / Purpur
# ============================================================

SERVER_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SERVER_DIR/logs/latest.log"

# How often the dashboard refreshes
REFRESH=2

# GeoIP cache
CACHE_DIR="$SERVER_DIR/.geoip-cache"

# true  = 103.21.xxx.xxx
# false = 103.21.45.123
HIDE_IP=false


# ============================================================
# COLORS
# ============================================================

RESET='\033[0m'
BOLD='\033[1m'

GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
CYAN='\033[36m'
WHITE='\033[37m'
GRAY='\033[90m'


# ============================================================
# CHECK SERVER LOG
# ============================================================

if [ ! -f "$LOG_FILE" ]; then

    echo
    echo -e "${RED}ERROR:${RESET} Minecraft log not found."
    echo
    echo "Expected:"
    echo "$LOG_FILE"
    echo

    exit 1
fi


# ============================================================
# CHECK CURL
# ============================================================

if ! command -v curl >/dev/null 2>&1; then

    echo
    echo -e "${RED}ERROR:${RESET} curl is not installed."
    echo

    exit 1
fi


# ============================================================
# CHECK PYTHON
# ============================================================

if ! command -v python3 >/dev/null 2>&1; then

    echo
    echo -e "${RED}ERROR:${RESET} python3 is required."
    echo
    echo "Install Python 3 first."
    echo

    exit 1
fi


mkdir -p "$CACHE_DIR"


# ============================================================
# FORMAT IP
# ============================================================

format_ip() {

    local ip="$1"

    if [ "$HIDE_IP" = true ]; then

        case "$ip" in

            *.*.*.*)
                echo "$ip" | awk -F. '{print $1 "." $2 ".xxx.xxx"}'
                ;;

            *)
                echo "$ip"
                ;;

        esac

    else

        echo "$ip"

    fi
}


# ============================================================
# GEOIP
# ============================================================

get_location() {

    local ip="$1"
    local cache="$CACHE_DIR/$ip"


    # --------------------------------------------------------
    # Cached result
    # --------------------------------------------------------

    if [ -f "$cache" ]; then

        cat "$cache"

        return

    fi


    # --------------------------------------------------------
    # Local/private IPs
    # --------------------------------------------------------

    case "$ip" in

        127.*)
            echo "Localhost|Local" > "$cache"
            echo "Localhost|Local"
            return
            ;;

        10.*)
            echo "Local Network|Private" > "$cache"
            echo "Local Network|Private"
            return
            ;;

        192.168.*)
            echo "Local Network|Private" > "$cache"
            echo "Local Network|Private"
            return
            ;;

        172.16.*|172.17.*|172.18.*|172.19.*|172.2[0-9].*|172.3[0-1].*)
            echo "Local Network|Private" > "$cache"
            echo "Local Network|Private"
            return
            ;;

    esac


    # --------------------------------------------------------
    # Query GeoIP
    # --------------------------------------------------------

    RESPONSE=$(curl \
        -s \
        --max-time 5 \
        "https://ipwho.is/$ip")


    if [ -z "$RESPONSE" ]; then

        echo "Unknown|Unknown"

        return

    fi


    # --------------------------------------------------------
    # Parse JSON
    # --------------------------------------------------------

    LOCATION=$(python3 -c '
import sys
import json

try:
    data = json.loads(sys.stdin.read())

    if not data.get("success", False):
        print("Unknown|Unknown")
    else:
        city = data.get("city") or "Unknown"
        region = data.get("region") or ""
        country = data.get("country") or "Unknown"

        if region:
            location = city + ", " + region
        else:
            location = city

        print(location + "|" + country)

except Exception:
    print("Unknown|Unknown")
' <<< "$RESPONSE")


    echo "$LOCATION" > "$cache"

    echo "$LOCATION"
}


# ============================================================
# GET ONLINE PLAYERS
# ============================================================

get_players() {

    awk '

    BEGIN {
        FS="\\[Server thread/INFO\\]: "
    }

    {

        line=$2


        # ====================================================
        # PLAYER LOGIN
        #
        # Example:
        #
        # Steve[/1.2.3.4:54321] logged in with entity id
        # ====================================================

        if (line ~ /logged in with entity id/) {

            # Find the opening [ before the IP
            bracket = index(line, "[/")

            if (bracket > 0) {

                # Player name is everything before [/IP
                player = substr(line, 1, bracket - 1)

                # Remove possible whitespace
                gsub(/^[ \t]+|[ \t]+$/, "", player)

                # Get IP portion
                ip_start = bracket + 2

                ip_part = substr(line, ip_start)

                # Remove port and everything after it
                sub(/:.*/, "", ip_part)

                ip = ip_part

                if (player != "" && ip != "") {

                    online[player] = ip

                }

            }

        }


        # ====================================================
        # PLAYER LEFT
        # ====================================================

        if (line ~ / left the game/) {

            player=line

            sub(/ left the game.*/, "", player)

            gsub(/^[ \t]+|[ \t]+$/, "", player)

            if (player != "") {

                online[player]=""

            }

        }


        # ====================================================
        # PLAYER LOST CONNECTION
        # ====================================================

        if (line ~ / lost connection:/) {

            player=line

            sub(/ lost connection:.*/, "", player)

            gsub(/^[ \t]+|[ \t]+$/, "", player)

            if (player != "") {

                online[player]=""

            }

        }

    }


    END {

        for (player in online) {

            if (online[player] != "") {

                print player "|" online[player]

            }

        }

    }

    ' "$LOG_FILE"
}


# ============================================================
# CLEAN EXIT
# ============================================================

cleanup() {

    # Show cursor
    printf '\033[?25h'

    # Clear screen
    printf '\033[2J'
    printf '\033[H'

    echo
    echo -e "${GREEN}Minecraft monitor stopped.${RESET}"
    echo

    exit 0
}


trap cleanup INT TERM


# ============================================================
# HIDE CURSOR
# ============================================================

printf '\033[?25l'


# ============================================================
# INITIAL CLEAR
# ============================================================

printf '\033[2J'
printf '\033[H'


# ============================================================
# MAIN LOOP
# ============================================================

while true; do

    # Move cursor to top
    printf '\033[H'

    # Current time
    NOW=$(date '+%Y-%m-%d %H:%M:%S')

    # Get players
    PLAYERS=$(get_players)


    # Count
    if [ -z "$PLAYERS" ]; then

        COUNT=0

    else

        COUNT=$(printf '%s\n' "$PLAYERS" | wc -l | tr -d ' ')

    fi


    # Clear everything below cursor
    printf '\033[J'


    # ========================================================
    # HEADER
    # ========================================================

    echo

    echo -e "${CYAN}╭──────────────────────────────────────────────────────────────────────────────╮${RESET}"

    echo -e "${CYAN}│${RESET}              ${BOLD}${WHITE}MINECRAFT LIVE PLAYER MONITOR${RESET}                       ${CYAN}│${RESET}"

    echo -e "${CYAN}╰──────────────────────────────────────────────────────────────────────────────╯${RESET}"

    echo


    # ========================================================
    # PLAYER COUNT
    # ========================================================

    if [ "$COUNT" -eq 0 ]; then

        echo -e "  ${YELLOW}●${RESET} ${BOLD}${YELLOW}No players online${RESET}"

    elif [ "$COUNT" -eq 1 ]; then

        echo -e "  ${GREEN}●${RESET} ${BOLD}${GREEN}1 player online${RESET}"

    else

        echo -e "  ${GREEN}●${RESET} ${BOLD}${GREEN}${COUNT} players online${RESET}"

    fi

    echo


    # ========================================================
    # TABLE HEADER
    # ========================================================

    echo -e "${CYAN}  ┌──────────────────────┬────────────────────┬────────────────────────────────────────────┐${RESET}"

    echo -e "${CYAN}  │${RESET} ${BOLD}PLAYER${RESET}               ${CYAN}│${RESET} ${BOLD}IP ADDRESS${RESET}         ${CYAN}│${RESET} ${BOLD}LOCATION${RESET}                                            ${CYAN}│${RESET}"

    echo -e "${CYAN}  ├──────────────────────┼────────────────────┼────────────────────────────────────────────┤${RESET}"


    # ========================================================
    # NO PLAYERS
    # ========================================================

    if [ "$COUNT" -eq 0 ]; then

        echo -e "${CYAN}  │${RESET} ${GRAY}No players currently connected${RESET}                                                                    ${CYAN}│${RESET}"

    fi


    # ========================================================
    # PLAYER ROWS
    # ========================================================

    if [ "$COUNT" -gt 0 ]; then

        while IFS='|' read -r PLAYER IP; do

            [ -z "$PLAYER" ] && continue


            # Get display IP
            DISPLAY_IP=$(format_ip "$IP")


            # Get location
            GEO=$(get_location "$IP")


            CITY=$(echo "$GEO" | cut -d'|' -f1)

            COUNTRY=$(echo "$GEO" | cut -d'|' -f2)


            # Format player
            PLAYER_DISPLAY=$(printf "%-20s" "$PLAYER" | cut -c1-20)


            # Format IP
            IP_DISPLAY=$(printf "%-18s" "$DISPLAY_IP" | cut -c1-18)


            # Format location and wrap it across additional lines when needed.
            LOCATION="$CITY, $COUNTRY"
            LOCATION_WIDTH=44
            LOCATION_REMAINING="$LOCATION"
            FIRST_LOCATION_LINE=true

            while [ -n "$LOCATION_REMAINING" ]; do
                LOCATION_LINE="$(printf '%s' "$LOCATION_REMAINING" | cut -c1-${LOCATION_WIDTH})"
                LOCATION_REMAINING="$(printf '%s' "$LOCATION_REMAINING" | cut -c$((LOCATION_WIDTH + 1))- )"
                LOCATION_DISPLAY=$(printf "%-${LOCATION_WIDTH}s" "$LOCATION_LINE")

                if [ "$FIRST_LOCATION_LINE" = true ]; then
                    # First line includes player name and IP.
                    echo -e "  ${CYAN}│${RESET} ${GREEN}●${RESET} ${PLAYER_DISPLAY} ${CYAN}│${RESET} ${IP_DISPLAY} ${CYAN}│${RESET} ${LOCATION_DISPLAY} ${CYAN}│${RESET}"
                    FIRST_LOCATION_LINE=false
                else
                    # Continuation lines keep the player and IP cells blank.
                    echo -e "  ${CYAN}│${RESET}                      ${CYAN}│${RESET}                    ${CYAN}│${RESET} ${LOCATION_DISPLAY} ${CYAN}│${RESET}"
                fi
            done


        done <<< "$PLAYERS"

    fi


    # ========================================================
    # TABLE FOOTER
    # ========================================================

    echo -e "${CYAN}  └──────────────────────┴────────────────────┴────────────────────────────────────────────┘${RESET}"

    echo


    # ========================================================
    # FOOTER
    # ========================================================

    echo -e "  ${GRAY}Updated:${RESET} ${NOW}"

    echo -e "  ${GRAY}Refresh:${RESET} ${REFRESH}s"

    if [ "$HIDE_IP" = true ]; then
        echo -e "  ${GRAY}IP privacy:${RESET} ${GREEN}Enabled${RESET}"
    else
        echo -e "  ${GRAY}IP privacy:${RESET} ${RED}Disabled${RESET}"
    fi

    echo -e "  ${GRAY}Press Ctrl+C to exit${RESET}"


    # ========================================================
    # WAIT
    # ========================================================

    sleep "$REFRESH"

done
