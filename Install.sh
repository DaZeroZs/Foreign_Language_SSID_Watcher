mkdir -p /root/rogue-ap-detector
mkdir -p /root/payloads/user/foreign-ssid-watch-start/foreign-ssid-watch-start
mkdir -p /root/payloads/user/foreign-ssid-watch-stop/foreign-ssid-watch-stop
mkdir -p /root/payloads/user/foreign-ssid-watch-status/foreign-ssid-watch-status
mkdir -p /root/payloads/user/foreign-ssid-watch-clear-seen/foreign-ssid-watch-clear-seen

cat > /root/rogue-ap-detector/foreign_ssid_watchd.sh << 'EOF'
#!/bin/sh
# Foreign / non-German SSID watcher
# Alerts when SSID contains letters outside German/Latin character set.

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
            print ssid "," bssid "," channel "," freq "," enc "," signal
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
        channel=$5
    }

    /^[ \t]*RSN:/ {
        if (enc == "OPEN") enc="WPA2/WPA3"
    }

    /^[ \t]*WPA:/ {
        if (enc == "OPEN") enc="WPA/WPA2"
    }

    END {
        if (bssid != "" && ssid != "") {
            print ssid "," bssid "," channel "," freq "," enc "," signal
        }
    }
    ' "$RAW" > "$TMP"
}

has_non_german_chars() {
    ssid="$1"

    # Remove German/Latin letters, numbers, spaces, and common special characters.
    # If anything remains, the SSID contains non-German / non-Latin characters.
    remaining="$(printf '%s' "$ssid" | sed 's/[A-Za-z0-9 äöüÄÖÜß._,;:!?\/\\(){}\[\]+=@#%&*'"'"'" -]//g')"

    [ -n "$remaining" ]
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
    enc="$4"
    rssi="$5"

    msg="Foreign SSID? $ssid"

    echo "$(date) $msg BSSID=$bssid CH=$channel ENC=$enc RSSI=$rssi" >> "$LOG"

    ALERT "$msg"
    RINGTONE "Alarm:d=4,o=5,b=180:c6,c6,c6,8p,c6,c6,c6"
    VIBRATE "Buzz:d=4,o=5,b=180:c,c,c,8p,c,c,c"
}

echo $$ > "$PIDFILE"
echo "$(date) foreign SSID watcher started interface=$INTERFACE interval=${SCAN_INTERVAL}s" >> "$LOG"

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

    while IFS=',' read -r ssid bssid channel freq enc rssi; do
        [ -z "$ssid" ] && continue
        [ -z "$bssid" ] && continue

        bssid_lc="$(normalize_mac "$bssid")"

        if has_non_german_chars "$ssid"; then
            key="$ssid|$bssid_lc"

            if ! already_alerted "$key"; then
                mark_alerted "$key"
                alert_foreign_ssid "$ssid" "$bssid_lc" "$channel" "$enc" "$rssi"
            else
                echo "$(date) already alerted foreign SSID=$ssid BSSID=$bssid_lc" >> "$LOG"
            fi
        fi
    done < "$TMP"

    sleep "$SCAN_INTERVAL"
done
EOF
