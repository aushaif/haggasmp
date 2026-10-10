#!/bin/bash

# ============================================================
# MINECRAFT PLAYER HISTORY
# ============================================================
#
# Compatible with:
#   macOS
#   Linux
#   Paper
#   Purpur
#
# Features:
#   - Reads all Minecraft logs
#   - Reads compressed .gz logs
#   - Stores every unique player
#   - First join date/time
#   - Latest join date/time
#   - Total join count
#   - Latest IP
#   - Latest GeoIP location
#   - Continuously detects new joins
#   - Persistent SQLite database
#   - IST date/time display
#
# ============================================================


# ============================================================
# CONFIGURATION
# ============================================================

# ------------------------------------------------------------
# Minecraft server directory
#
# If this script is inside your server folder, DON'T CHANGE.
# ------------------------------------------------------------

SERVER_DIR="$(cd "$(dirname "$0")" && pwd)"


# ------------------------------------------------------------
# Minecraft logs directory
# ------------------------------------------------------------

LOG_DIR="$SERVER_DIR/logs"


# ------------------------------------------------------------
# Database file
# ------------------------------------------------------------

DATABASE="$SERVER_DIR/player-history.db"


# ------------------------------------------------------------
# GeoIP cache directory
# ------------------------------------------------------------

CACHE_DIR="$SERVER_DIR/.geoip-cache"


# ------------------------------------------------------------
# Refresh interval
#
# How often the script checks for new players.
# ------------------------------------------------------------

REFRESH=5


# ------------------------------------------------------------
# Display timezone
#
# India Standard Time
# ------------------------------------------------------------

DISPLAY_TIMEZONE="Asia/Kolkata"


# ------------------------------------------------------------
# Timezone used by Minecraft logs
#
# If your Minecraft server itself uses IST, keep:
#
# Asia/Kolkata
#
# If your server logs are UTC, change this to:
#
# UTC
# ------------------------------------------------------------

LOG_TIMEZONE="Asia/Kolkata"


# ------------------------------------------------------------
# Hide IP addresses in terminal
#
# true:
#   103.21.xxx.xxx
#
# false:
#   103.21.45.123
# ------------------------------------------------------------

HIDE_IP=true


# ------------------------------------------------------------
# Number of players shown
#
# 0 = ALL PLAYERS
# ------------------------------------------------------------

MAX_DISPLAY_PLAYERS=0


# ------------------------------------------------------------
# GeoIP service
# ------------------------------------------------------------

GEOIP_URL="https://ipwho.is"


# ============================================================
# END CONFIGURATION
# ============================================================


# ============================================================
# CHECKS
# ============================================================

if [ ! -d "$LOG_DIR" ]; then

    echo
    echo "ERROR: Minecraft logs directory not found:"
    echo
    echo "$LOG_DIR"
    echo

    exit 1

fi


if ! command -v python3 >/dev/null 2>&1; then

    echo
    echo "ERROR: Python 3 is required."
    echo
    echo "Install Python 3 and run the script again."
    echo

    exit 1

fi


mkdir -p "$CACHE_DIR"


# ============================================================
# PYTHON ENGINE
# ============================================================

python3 - \
    "$SERVER_DIR" \
    "$LOG_DIR" \
    "$DATABASE" \
    "$CACHE_DIR" \
    "$REFRESH" \
    "$DISPLAY_TIMEZONE" \
    "$LOG_TIMEZONE" \
    "$HIDE_IP" \
    "$MAX_DISPLAY_PLAYERS" \
    "$GEOIP_URL" <<'PY'


# ============================================================
# IMPORTS
# ============================================================

import sys
import os
import re
import sqlite3
import gzip
import glob
import time
import json
import urllib.request
import hashlib

from datetime import datetime
from zoneinfo import ZoneInfo


# ============================================================
# ARGUMENTS
# ============================================================

SERVER_DIR = sys.argv[1]

LOG_DIR = sys.argv[2]

DATABASE = sys.argv[3]

CACHE_DIR = sys.argv[4]

REFRESH = int(sys.argv[5])

DISPLAY_TIMEZONE = sys.argv[6]

LOG_TIMEZONE = sys.argv[7]

HIDE_IP = sys.argv[8].lower() == "true"

MAX_DISPLAY_PLAYERS = int(sys.argv[9])

GEOIP_URL = sys.argv[10]


# ============================================================
# TIMEZONE
# ============================================================

try:

    DISPLAY_TZ = ZoneInfo(DISPLAY_TIMEZONE)

except Exception:

    DISPLAY_TZ = ZoneInfo("Asia/Kolkata")


try:

    LOG_TZ = ZoneInfo(LOG_TIMEZONE)

except Exception:

    LOG_TZ = ZoneInfo("Asia/Kolkata")


# ============================================================
# DATABASE
# ============================================================

db = sqlite3.connect(
    DATABASE,
    check_same_thread=False
)


# ============================================================
# PLAYERS TABLE
# ============================================================

db.execute("""
CREATE TABLE IF NOT EXISTS players (

    id INTEGER PRIMARY KEY AUTOINCREMENT,

    name TEXT UNIQUE NOT NULL,

    first_join TEXT NOT NULL,

    last_join TEXT NOT NULL,

    joins INTEGER NOT NULL DEFAULT 1,

    ip TEXT,

    city TEXT,

    region TEXT,

    country TEXT,

    country_code TEXT

)
""")


# ============================================================
# EVENTS TABLE
# ============================================================
#
# This prevents the same log line from being counted twice.
#
# Important:
# If latest.log gets rotated into another filename,
# the event hash stays the same.
#
# ============================================================

db.execute("""
CREATE TABLE IF NOT EXISTS events (

    event_id TEXT PRIMARY KEY,

    player TEXT NOT NULL,

    timestamp TEXT,

    ip TEXT

)
""")


db.commit()


# ============================================================
# CURRENT IST TIME
# ============================================================

def current_time():

    return datetime.now(
        DISPLAY_TZ
    ).strftime(
        "%Y-%m-%d %H:%M:%S"
    )


# ============================================================
# GEOIP LOOKUP
# ============================================================

def get_location(ip):

    if not ip:

        return (
            "Unknown",
            "",
            "Unknown",
            ""
        )


    # --------------------------------------------------------
    # LOCAL IP
    # --------------------------------------------------------

    if (
        ip.startswith("127.")
        or ip.startswith("10.")
        or ip.startswith("192.168.")
        or ip.startswith("172.16.")
        or ip.startswith("172.17.")
        or ip.startswith("172.18.")
        or ip.startswith("172.19.")
        or ip.startswith("172.2")
        or ip.startswith("172.3")
    ):

        return (
            "Local Network",
            "",
            "Private",
            ""
        )


    # --------------------------------------------------------
    # CACHE
    # --------------------------------------------------------

    safe_ip = re.sub(
        r"[^a-zA-Z0-9_.-]",
        "_",
        ip
    )


    cache_file = os.path.join(
        CACHE_DIR,
        safe_ip + ".json"
    )


    if os.path.exists(cache_file):

        try:

            with open(
                cache_file,
                "r",
                encoding="utf-8"
            ) as f:

                data = json.load(f)


            return (
                data.get("city", "Unknown"),
                data.get("region", ""),
                data.get("country", "Unknown"),
                data.get("country_code", "")
            )

        except Exception:

            pass


    # --------------------------------------------------------
    # API REQUEST
    # --------------------------------------------------------

    try:

        url = GEOIP_URL.rstrip("/") + "/" + ip


        request = urllib.request.Request(
            url,
            headers={
                "User-Agent":
                "MinecraftPlayerHistory/1.0"
            }
        )


        with urllib.request.urlopen(
            request,
            timeout=5
        ) as response:

            data = json.loads(
                response.read().decode(
                    "utf-8"
                )
            )


        if not data.get(
            "success",
            False
        ):

            return (
                "Unknown",
                "",
                "Unknown",
                ""
            )


        city = data.get(
            "city"
        ) or "Unknown"


        region = data.get(
            "region"
        ) or ""


        country = data.get(
            "country"
        ) or "Unknown"


        country_code = data.get(
            "country_code"
        ) or ""


        # ----------------------------------------------------
        # CACHE
        # ----------------------------------------------------

        try:

            with open(
                cache_file,
                "w",
                encoding="utf-8"
            ) as f:

                json.dump(
                    {
                        "city": city,
                        "region": region,
                        "country": country,
                        "country_code":
                            country_code
                    },
                    f
                )

        except Exception:

            pass


        return (
            city,
            region,
            country,
            country_code
        )


    except Exception:

        return (
            "Unknown",
            "",
            "Unknown",
            ""
        )


# ============================================================
# FIND LOG FILES
# ============================================================

def get_log_files():

    files = []


    # Normal logs

    files.extend(
        glob.glob(
            os.path.join(
                LOG_DIR,
                "*.log"
            )
        )
    )


    # Compressed logs

    files.extend(
        glob.glob(
            os.path.join(
                LOG_DIR,
                "*.log.gz"
            )
        )
    )


    # Remove duplicates

    files = list(
        set(files)
    )


    # Oldest first

    files.sort(
        key=lambda x:
        os.path.getmtime(x)
    )


    return files


# ============================================================
# OPEN LOG
# ============================================================

def open_log(path):

    if path.endswith(".gz"):

        return gzip.open(
            path,
            "rt",
            encoding="utf-8",
            errors="ignore"
        )

    return open(
        path,
        "r",
        encoding="utf-8",
        errors="ignore"
    )


# ============================================================
# GET DATE FROM LOG FILENAME
# ============================================================

def date_from_filename(path):

    filename = os.path.basename(path)


    # Example:
    #
    # 2026-10-07-1.log.gz
    #

    match = re.search(
        r"(20\d{2}-\d{2}-\d{2})",
        filename
    )


    if match:

        return match.group(1)


    return None


# ============================================================
# PARSE LOG TIMESTAMP
# ============================================================

def parse_timestamp(
    line,
    log_file
):

    # --------------------------------------------------------
    # Full timestamp
    #
    # [2026-10-07 18:31:42 INFO]
    # --------------------------------------------------------

    match = re.search(
        r"\[(20\d{2}-\d{2}-\d{2} "
        r"\d{2}:\d{2}:\d{2})",
        line
    )


    if match:

        value = match.group(1)


        try:

            dt = datetime.strptime(
                value,
                "%Y-%m-%d %H:%M:%S"
            )


            dt = dt.replace(
                tzinfo=LOG_TZ
            )


            return dt.astimezone(
                DISPLAY_TZ
            ).strftime(
                "%Y-%m-%d %H:%M:%S"
            )

        except Exception:

            pass


    # --------------------------------------------------------
    # Time only
    #
    # [18:31:42 INFO]
    # --------------------------------------------------------

    match = re.search(
        r"\[(\d{2}:\d{2}:\d{2})",
        line
    )


    if match:

        time_value = match.group(1)


        date_value = date_from_filename(
            log_file
        )


        if not date_value:

            date_value = datetime.now(
                LOG_TZ
            ).strftime(
                "%Y-%m-%d"
            )


        try:

            dt = datetime.strptime(
                date_value
                + " "
                + time_value,
                "%Y-%m-%d %H:%M:%S"
            )


            dt = dt.replace(
                tzinfo=LOG_TZ
            )


            return dt.astimezone(
                DISPLAY_TZ
            ).strftime(
                "%Y-%m-%d %H:%M:%S"
            )

        except Exception:

            pass


    # --------------------------------------------------------
    # Fallback
    # --------------------------------------------------------

    return current_time()


# ============================================================
# PARSE PLAYER JOIN
# ============================================================

def parse_join(
    line,
    log_file
):

    if "logged in with entity id" not in line:

        return None


    # --------------------------------------------------------
    # Player and IP
    #
    # Example:
    #
    # Steve[/103.21.45.123:54321]
    # logged in with entity id
    #
    # --------------------------------------------------------

    match = re.search(
        r"\]:\s*([^\[]+)"
        r"\[\/([0-9a-fA-F:.]+):\d+\]"
        r"\s+logged in with entity id",
        line
    )


    if not match:

        return None


    player = match.group(1).strip()

    ip = match.group(2).strip()


    if not player:

        return None


    if not ip:

        return None


    timestamp = parse_timestamp(
        line,
        log_file
    )


    return (
        player,
        ip,
        timestamp
    )


# ============================================================
# EVENT ID
# ============================================================
#
# Uses the complete original log line.
#
# This means:
#
# latest.log
#     ↓
# rotated log
#     ↓
# compressed log
#
# will NOT create duplicate join events.
#
# ============================================================

def make_event_id(line):

    return hashlib.sha256(
        line.strip().encode(
            "utf-8",
            errors="ignore"
        )
    ).hexdigest()


# ============================================================
# SAVE PLAYER
# ============================================================

def save_player(
    player,
    ip,
    timestamp,
    event_id
):

    # --------------------------------------------------------
    # Duplicate event?
    # --------------------------------------------------------

    exists = db.execute(
        """
        SELECT 1
        FROM events
        WHERE event_id = ?
        """,
        (event_id,)
    ).fetchone()


    if exists:

        return False


    # --------------------------------------------------------
    # Location
    # --------------------------------------------------------

    city, region, country, country_code = \
        get_location(ip)


    # --------------------------------------------------------
    # Existing player
    # --------------------------------------------------------

    existing = db.execute(
        """
        SELECT
            first_join,
            joins

        FROM players

        WHERE name = ?
        """,
        (player,)
    ).fetchone()


    if existing:

        first_join = existing[0]

        joins = existing[1] + 1


        db.execute(
            """
            UPDATE players

            SET
                last_join = ?,
                joins = ?,
                ip = ?,
                city = ?,
                region = ?,
                country = ?,
                country_code = ?

            WHERE name = ?

            """,
            (
                timestamp,
                joins,
                ip,
                city,
                region,
                country,
                country_code,
                player
            )
        )


    else:

        db.execute(
            """
            INSERT INTO players
            (
                name,
                first_join,
                last_join,
                joins,
                ip,
                city,
                region,
                country,
                country_code
            )

            VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?)

            """,
            (
                player,
                timestamp,
                timestamp,
                1,
                ip,
                city,
                region,
                country,
                country_code
            )
        )


    # --------------------------------------------------------
    # Save event
    # --------------------------------------------------------

    db.execute(
        """
        INSERT OR IGNORE INTO events
        (
            event_id,
            player,
            timestamp,
            ip
        )

        VALUES
        (?, ?, ?, ?)

        """,
        (
            event_id,
            player,
            timestamp,
            ip
        )
    )


    db.commit()


    return True


# ============================================================
# PROCESS LOG
# ============================================================

def process_log(path):

    try:

        with open_log(path) as f:

            for line in f:

                result = parse_join(
                    line,
                    path
                )


                if not result:

                    continue


                player, ip, timestamp = result


                event_id = make_event_id(
                    line
                )


                save_player(
                    player,
                    ip,
                    timestamp,
                    event_id
                )


    except Exception as e:

        print(
            "Log error:",
            path,
            e
        )


# ============================================================
# INITIAL HISTORY SCAN
# ============================================================

print()
print(
    "Minecraft Player History"
)
print(
    "=" * 70
)
print()
print(
    "Scanning all Minecraft logs..."
)
print()


for log_file in get_log_files():

    print(
        "Reading:",
        os.path.basename(
            log_file
        )
    )

    process_log(
        log_file
    )


print()
print(
    "Initial scan complete."
)
print()


# ============================================================
# HIDE IP
# ============================================================

def display_ip(ip):

    if not ip:

        return "Unknown"


    if not HIDE_IP:

        return ip


    # IPv4

    parts = ip.split(".")


    if len(parts) == 4:

        return (
            parts[0]
            + "."
            + parts[1]
            + ".xxx.xxx"
        )


    # IPv6

    if ":" in ip:

        parts = ip.split(":")

        if len(parts) >= 3:

            return (
                ":".join(
                    parts[:3]
                )
                + ":xxxx"
            )


    return ip


# ============================================================
# LOCATION STRING
# ============================================================

def location_string(
    city,
    region,
    country
):

    if city == "Local Network":

        return "Local Network, Private"


    if region:

        return (
            city
            + ", "
            + region
            + ", "
            + country
        )


    return (
        city
        + ", "
        + country
    )


# ============================================================
# DASHBOARD
# ============================================================

def dashboard():

    # Clear screen

    os.system(
        "clear"
    )


    # --------------------------------------------------------
    # Total players
    # --------------------------------------------------------

    total = db.execute(
        """
        SELECT COUNT(*)
        FROM players
        """
    ).fetchone()[0]


    # --------------------------------------------------------
    # ALL PLAYERS
    # --------------------------------------------------------

    query = """
        SELECT
            name,
            first_join,
            last_join,
            joins,
            ip,
            city,
            region,
            country

        FROM players

        ORDER BY
            last_join DESC
    """


    players = db.execute(
        query
    ).fetchall()


    # --------------------------------------------------------
    # Limit only if configured
    # --------------------------------------------------------

    if MAX_DISPLAY_PLAYERS > 0:

        players = players[
            :MAX_DISPLAY_PLAYERS
        ]


    # ========================================================
    # HEADER
    # ========================================================

    print()

    print(
        "╭──────────────────────────────────────────────────────────────────────────────────────────────╮"
    )

    print(
        "│                         MINECRAFT PLAYER HISTORY                                             │"
    )

    print(
        "╰──────────────────────────────────────────────────────────────────────────────────────────────╯"
    )

    print()


    # ========================================================
    # INFO
    # ========================================================

    print(
        f"  Total unique players: {total}"
    )

    print(
        f"  Timezone: {DISPLAY_TIMEZONE} (IST)"
    )

    print(
        f"  Current time: {current_time()}"
    )

    print()


    # ========================================================
    # TABLE
    # ========================================================

    print(
        "  ALL PLAYERS"
    )

    print(
        "  "
        + "─" * 145
    )


    print(
        f"  {'#':<5}"
        f"{'PLAYER':<22}"
        f"{'FIRST JOIN (IST)':<21}"
        f"{'LAST JOIN (IST)':<21}"
        f"{'JOINS':<8}"
        f"{'IP ADDRESS':<18}"
        f"LOCATION"
    )


    print(
        "  "
        + "─" * 145
    )


    # ========================================================
    # PLAYER ROWS
    # ========================================================

    if not players:

        print()

        print(
            "  No players found."
        )

    else:

        for index, row in enumerate(
            players,
            start=1
        ):

            name = row[0]

            first_join = row[1]

            last_join = row[2]

            joins = row[3]

            ip = row[4]

            city = row[5]

            region = row[6]

            country = row[7]


            # -----------------------------------------------
            # Location
            # -----------------------------------------------

            location = location_string(
                city,
                region,
                country
            )


            # -----------------------------------------------
            # IP
            # -----------------------------------------------

            ip_display = display_ip(
                ip
            )


            # -----------------------------------------------
            # Clean strings
            # -----------------------------------------------

            name = str(name)[:21]

            first_join = str(
                first_join
            )[:20]

            last_join = str(
                last_join
            )[:20]

            ip_display = str(
                ip_display
            )[:17]

            location = str(
                location
            )[:45]


            # -----------------------------------------------
            # Print
            # -----------------------------------------------

            print(
                f"  {index:<5}"
                f"{name:<22}"
                f"{first_join:<21}"
                f"{last_join:<21}"
                f"{joins:<8}"
                f"{ip_display:<18}"
                f"{location}"
            )


    # ========================================================
    # FOOTER
    # ========================================================

    print()

    print(
        "  "
        + "─" * 145
    )

    print()

    print(
        "  Database:",
        DATABASE
    )

    print(
        "  Players:",
        total
    )

    print(
        "  Timezone:",
        DISPLAY_TIMEZONE,
        "(IST)"
    )

    print(
        "  Monitoring new joins..."
    )

    print(
        f"  Refresh: {REFRESH}s"
    )

    print()

    print(
        "  Press Ctrl+C to exit."
    )


# ============================================================
# MONITOR
# ============================================================

try:

    while True:

        # ----------------------------------------------------
        # Process current/latest logs
        # ----------------------------------------------------

        for log_file in get_log_files():

            # The event database prevents duplicates,
            # so it is safe to process the logs repeatedly.

            process_log(
                log_file
            )


        # ----------------------------------------------------
        # Dashboard
        # ----------------------------------------------------

        dashboard()


        # ----------------------------------------------------
        # Wait
        # ----------------------------------------------------

        time.sleep(
            REFRESH
        )


except KeyboardInterrupt:

    print()
    print()
    print(
        "Player history monitor stopped."
    )
    print()


finally:

    db.close()

PY
