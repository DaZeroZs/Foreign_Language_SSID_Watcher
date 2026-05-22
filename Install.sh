cat > /root/Install_Foreign_SSID_Watch.sh << 'EOF'
#!/bin/sh
# Install Foreign / Non-German SSID Watch for WiFi Pineapple Pager
#
# Final version:
# - Detects escaped UTF-8 SSIDs from iw, e.g. \xc4\x83
# - Allows printable ASCII characters
# - Allows German characters: ä ö ü Ä Ö Ü ß
# - Alerts on everything else
#
# Should NOT alert:
#   DIRECT-w0Restaurant_BRd154
#   FRITZ!Box 7590
#   Müller-WLAN
#   S24-Test_123!
#   xyz-intern
#
# Should alert:
#   S24ăāàãåâ
#   S24 ā
#   S24 ā
#   Café
#   東京WiFi
#   Кафе-WiFi
#   咖啡WiFi
#   شبكةWiFi

BASE="/root/rogue-ap-detector"

mkdir -p "$BASE"
mkdir -p /root/payloads/user/foreign-ssid-watch-start/foreign-ssid-watch-start
mkdir -p /root/payloads/user/foreign-ssid-watch-stop/foreign-ssid-watch-stop
mkdir -p /root/payloads/user/foreign-ssid-watch-status/foreign-ssid-watch-status
mkdir -p /root/payloads/user/foreign-ssid-watch-clear-seen/foreign-ssid-watch-clear-seen

echo "[*] Stopping old foreign SSID watcher processes..."

ps | grep "foreign_ssid_watchd.sh" | grep -v grep | awk '{print $1}' | while read -r pid; do
    kill "$pid" 2>/dev/null
done

sleep 1

ps | grep "foreign_ssid_watchd.sh" | grep -v grep | awk '{print $1}' | while read -r pid; do
    kill -9 "$pid" 2>/dev/null
done

rm -f "$BASE/foreign-ssid-watch.pid"

cat > "$BASE/foreign_ssid_watchd.sh" << 'WATCHER_EOF'
#!/bin/sh
# Foreign / Non-German SSID watcher
#
# Detection:
# - Allows normal printable ASCII.
# - Allows German UTF-8 characters:
#   ä ö ü Ä Ö Ü ß
# - Allows iw escaped German UTF-8 sequences:
#   \xc3\xa4 \xc3\xb6 \xc3\xbc \xc3\x84 \xc3\x96 \xc3\x9c \xc3\x9f
# - Alerts on all other UTF-8 / escaped byte sequences.

BASE="/root/rogue-ap-detector"
LOG="$BASE/foreign-ssid-watch.log"
SEEN="$BASE/foreign-ssid-seen.cache"
PIDFILE="$BASE/foreign-ssid-watch.pid"

INTERFACE="wlan0"
SCAN_INTERVAL="60"

RAW="/tmp/foreign-ssid-raw-scan.txt"
TMP="/tmp/foreign-ssid-aps.tmp"
ERR="/tmp/foreign-ssid-scan-error.txt"

mkdir -p "$BASE"
touch "$SEEN"

normalize_mac() {
    echo "$1" | tr 'A-F' 'a-f'
}

has_foreign_chars() {
    ssid="$1"

    # iw often prints non-ASCII SSIDs as escaped UTF-8 byte strings,
    # for example:
    #   S24\xc4\x83\xc4\x81\xc3\xa0
    #
    # Allowed escaped German UTF-8 sequences:
    #   ä = \xc3\xa4
    #   ö = \xc3\xb6
    #   ü = \xc3\xbc
    #   Ä = \xc3\x84
    #   Ö = \xc3\x96
    #   Ü = \xc3\x9c
    #   ß = \xc3\x9f

    cleaned="$ssid"

    cleaned="$(printf '%s' "$cleaned" | sed \
        -e 's/\\xc3\\xa4//g' \
        -e 's/\\xc3\\xb6//g' \
        -e 's/\\xc3\\xbc//g' \
        -e 's/\\xc3\\x84//g' \
        -e 's/\\xc3\\x96//g' \
        -e 's/\\xc3\\x9c//g' \
        -e 's/\\xc3\\x9f//g')"

    # If any other escaped byte sequence remains, alert.
    if printf '%s' "$cleaned" | grep -q '\\x[0-9a-fA-F][0-9a-fA-F]'; then
        echo "$(date) DECISION=FOREIGN_ESCAPED SSID=[$ssid]" >> "$LOG"
        return 0
    fi

    # Also handle the case where real UTF-8 characters appear directly.
    # Remove normal printable ASCII.
    remaining="$(printf '%s' "$cleaned" | LC_ALL=C sed 's/[ -~]//g')"

    # Remove direct German umlauts if they appear directly.
    remaining="$(printf '%s' "$remaining" | sed \
        -e 's/ä//g' \
        -e 's/ö//g' \
        -e 's/ü//g' \
        -e 's/Ä//g' \
        -e 's/Ö//g' \
        -e 's/Ü//g' \
        -e 's/ß//g')"

    if [ -n "$remaining" ]; then
        echo "$(date) DECISION=FOREIGN_DIRECT SSID=[$ssid] REMAINING=[$remaining]" >> "$LOG"
        return 0
    fi

    echo "$(date) DECISION=CLEAN SSID=[$ssid]" >> "$LOG"
    return 1
}

parse_scan() {
    awk '
    BEGIN {
        bssid="";
        ssid="";
        signal="";
        channel="";
        freq="";
        enc="OPEN";
    }

    /^BSS / {
        if (bssid != "" && ssid != "") {
            print ssid "\t" bssid "\t" channel "\t" freq "\t" enc "\t" signal
        }

        bssid=$2
        gsub(/\(.*/, "", bssid)

        ssid="";
        signal="";
        channel="";
        freq="";
        enc="OPEN";
    }

    /^[ \t]*SSID:/ {
        ssid=substr($0, index($0, "SSID:") + 6)
    }

    /^[ \t]*signal:/ {
        signal=$2
    }

    /^[ \t]*freq:/ {
        freq=$2
    }

    /^[ \t]*DS Parameter set:/ {
        channel=$4
    }

    /^[ \t]*RSN:/ {
        if (enc == "OPEN") enc="WPA2/WPA3"
    }

    /^[ \t]*WPA:/ {
        if (enc == "OPEN") enc="WPA/WPA2"
    }

    END {
        if (bssid != "" && ssid != "") {
            print ssid "\t" bssid "\t" channel "\t" freq "\t" enc "\t" signal
        }
    }
    ' "$RAW" > "$TMP"
}

already_alerted() {
    key="$1"
    grep -Fxq "$key" "$SEEN"
}

mark_alerted() {
    key="$1"
    echo "$key" >> "$SEEN"
}

alert_foreign_ssid() {
    ssid="$1"
    bssid="$2"
    channel="$3"
    freq="$4"
    enc="$5"
    rssi="$6"

    msg="Foreign SSID? $ssid"

    echo "$(date) ALERT $msg BSSID=$bssid CH=$channel FREQ=$freq ENC=$enc RSSI=$rssi" >> "$LOG"

    ALERT "$msg"
    RINGTONE "Alarm:d=4,o=5,b=180:c6,c6,c6,8p,c6,c6,c6"
    VIBRATE "Buzz:d=4,o=5,b=180:c,c,c,8p,c,c,c"
}

echo $$ > "$PIDFILE"
echo "$(date) foreign SSID watcher started FINAL interface=$INTERFACE interval=${SCAN_INTERVAL}s" >> "$LOG"

while true; do
    iw dev "$INTERFACE" scan > "$RAW" 2> "$ERR"
    RC="$?"

    if [ "$RC" != "0" ]; then
        ERRMSG="$(cat "$ERR" 2>/dev/null | head -c 120)"
        echo "$(date) scan failed rc=$RC error=$ERRMSG" >> "$LOG"
        sleep "$SCAN_INTERVAL"
        continue
    fi

    if ! grep -q '^BSS ' "$RAW"; then
        echo "$(date) scan returned no BSS entries" >> "$LOG"
        sleep "$SCAN_INTERVAL"
        continue
    fi

    parse_scan

    while IFS="$(printf '\t')" read -r ssid bssid channel freq enc rssi; do
        [ -z "$ssid" ] && continue
        [ -z "$bssid" ] && continue

        bssid_lc="$(normalize_mac "$bssid")"

        if has_foreign_chars "$ssid"; then
            key="$ssid|$bssid_lc"

            if ! already_alerted "$key"; then
                mark_alerted "$key"
                alert_foreign_ssid "$ssid" "$bssid_lc" "$channel" "$freq" "$enc" "$rssi"
            else
                echo "$(date) already alerted SSID=[$ssid] BSSID=$bssid_lc" >> "$LOG"
            fi
        fi
    done < "$TMP"

    sleep "$SCAN_INTERVAL"
done
WATCHER_EOF

cat > /root/payloads/user/foreign-ssid-watch-start/foreign-ssid-watch-start/payload.sh << 'START_EOF'
#!/bin/sh
# Title: Start Foreign SSID Watch
# Description: Starts non-German SSID watcher
# Author: local

BASE="/root/rogue-ap-detector"
WATCHER="$BASE/foreign_ssid_watchd.sh"
PIDFILE="$BASE/foreign-ssid-watch.pid"
STARTLOG="$BASE/foreign-ssid-watch-start.log"

mkdir -p "$BASE"

echo "$(date) foreign SSID start payload executed" >> "$STARTLOG"

if ps | grep "foreign_ssid_watchd.sh" | grep -v grep >/dev/null 2>&1; then
    pid="$(ps | grep "foreign_ssid_watchd.sh" | grep -v grep | awk '{print $1}' | head -n 1)"
    echo "$pid" > "$PIDFILE"
    ALERT "Foreign watch already running"
    exit 0
fi

if [ ! -f "$WATCHER" ]; then
    ALERT "Foreign watcher missing"
    echo "$(date) missing watcher script: $WATCHER" >> "$STARTLOG"
    exit 0
fi

sed -i 's/\r$//' "$WATCHER"
chmod +x "$WATCHER"

rm -f "$PIDFILE"

sh "$WATCHER" >> "$STARTLOG" 2>&1 &

sleep 3

if ps | grep "foreign_ssid_watchd.sh" | grep -v grep >/dev/null 2>&1; then
    pid="$(ps | grep "foreign_ssid_watchd.sh" | grep -v grep | awk '{print $1}' | head -n 1)"
    echo "$pid" > "$PIDFILE"
    ALERT "Foreign watch PID $pid"
    echo "$(date) watcher started pid=$pid" >> "$STARTLOG"
else
    ALERT "Foreign watch failed"
    echo "$(date) watcher failed to stay running" >> "$STARTLOG"
fi

exit 0
START_EOF

cat > /root/payloads/user/foreign-ssid-watch-stop/foreign-ssid-watch-stop/payload.sh << 'STOP_EOF'
#!/bin/sh
# Title: Stop Foreign SSID Watch
# Description: Stops non-German SSID watcher
# Author: local

BASE="/root/rogue-ap-detector"
PIDFILE="$BASE/foreign-ssid-watch.pid"
STARTLOG="$BASE/foreign-ssid-watch-start.log"

mkdir -p "$BASE"

echo "$(date) foreign SSID stop payload executed" >> "$STARTLOG"

ps | grep "foreign_ssid_watchd.sh" | grep -v grep | awk '{print $1}' | while read -r pid; do
    kill "$pid" 2>/dev/null
done

sleep 1

ps | grep "foreign_ssid_watchd.sh" | grep -v grep | awk '{print $1}' | while read -r pid; do
    kill -9 "$pid" 2>/dev/null
done

rm -f "$PIDFILE"

ALERT "Foreign watch stopped"
exit 0
STOP_EOF

cat > /root/payloads/user/foreign-ssid-watch-status/foreign-ssid-watch-status/payload.sh << 'STATUS_EOF'
#!/bin/sh
# Title: Foreign SSID Watch Status
# Description: Shows non-German SSID watcher status
# Author: local

BASE="/root/rogue-ap-detector"
PIDFILE="$BASE/foreign-ssid-watch.pid"

if ps | grep "foreign_ssid_watchd.sh" | grep -v grep >/dev/null 2>&1; then
    pid="$(ps | grep "foreign_ssid_watchd.sh" | grep -v grep | awk '{print $1}' | head -n 1)"
    echo "$pid" > "$PIDFILE"
    ALERT "Foreign watch running PID $pid"
else
    rm -f "$PIDFILE"
    ALERT "Foreign watch stopped"
fi

exit 0
STATUS_EOF

cat > /root/payloads/user/foreign-ssid-watch-clear-seen/foreign-ssid-watch-clear-seen/payload.sh << 'CLEAR_EOF'
#!/bin/sh
# Title: Clear Foreign SSID Seen
# Description: Allows repeated alerts for foreign SSID findings
# Author: local

BASE="/root/rogue-ap-detector"
SEEN="$BASE/foreign-ssid-seen.cache"

mkdir -p "$BASE"

: > "$SEEN"

ALERT "Foreign seen cache cleared"
exit 0
CLEAR_EOF

sed -i 's/\r$//' "$BASE/foreign_ssid_watchd.sh"
sed -i 's/\r$//' /root/payloads/user/foreign-ssid-watch-start/foreign-ssid-watch-start/payload.sh
sed -i 's/\r$//' /root/payloads/user/foreign-ssid-watch-stop/foreign-ssid-watch-stop/payload.sh
sed -i 's/\r$//' /root/payloads/user/foreign-ssid-watch-status/foreign-ssid-watch-status/payload.sh
sed -i 's/\r$//' /root/payloads/user/foreign-ssid-watch-clear-seen/foreign-ssid-watch-clear-seen/payload.sh

chmod +x "$BASE/foreign_ssid_watchd.sh"
chmod +x /root/payloads/user/foreign-ssid-watch-start/foreign-ssid-watch-start/payload.sh
chmod +x /root/payloads/user/foreign-ssid-watch-stop/foreign-ssid-watch-stop/payload.sh
chmod +x /root/payloads/user/foreign-ssid-watch-status/foreign-ssid-watch-status/payload.sh
chmod +x /root/payloads/user/foreign-ssid-watch-clear-seen/foreign-ssid-watch-clear-seen/payload.sh

: > "$BASE/foreign-ssid-seen.cache"

echo "Foreign SSID Watch installed."
echo "Final escaped-SSID aware version installed."
echo "Allowed: printable ASCII + ä ö ü Ä Ö Ü ß"
echo "Everything else will alert."
echo "Reboot recommended."
EOF

chmod +x /root/Install_Foreign_SSID_Watch.sh
/root/Install_Foreign_SSID_Watch.sh
