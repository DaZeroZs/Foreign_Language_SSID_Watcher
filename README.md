# Foreign / Non-German SSID Watch for WiFi Pineapple Pager

A simple display-driven alert watcher for the **WiFi Pineapple Pager**.

This feature alerts when nearby WiFi access points use SSIDs containing characters outside a German/Latin character set.

It is useful for quick field awareness when you want to notice SSIDs using non-Latin scripts, for example Cyrillic, Chinese, Japanese, Korean, Arabic, Greek, and similar character sets.

> This feature does **not** prove that an AP is from another country.  
> It only detects SSID names containing characters outside the configured German/Latin character set.

---

## What It Detects

The watcher allows:

```text
A-Z
a-z
0-9
ä ö ü Ä Ö Ü ß
spaces
common punctuation and special characters
```

Common special characters are ignored, for example:

```text
- _ . , ; : ! ? / \ ( ) { } [ ] + = @ # % & * ' "
```

### Examples

| SSID | Result | Meaning |
|---|---|---|
| `FRITZ!Box 7590` | No alert | Normal Latin/German characters |
| `Müller-WLAN` | No alert | German umlauts are allowed |
| `Cafe_Guest-2` | No alert | Common special characters are ignored |
| `xyz-Intern` | No alert | Normal Latin characters |
| `Кафе-WiFi` | Alert | Contains Cyrillic |
| `咖啡WiFi` | Alert | Contains Chinese characters |
| `東京WiFi` | Alert | Contains Japanese characters |
| `شبكةWiFi` | Alert | Contains Arabic characters |

Alert example:

```text
Foreign SSID? 東京WiFi
```

---

## Files Installed

The installer creates the watcher daemon:

```text
/root/rogue-ap-detector/foreign_ssid_watchd.sh
```

And four display payloads:

```text
/root/payloads/user/foreign-ssid-watch-start/foreign-ssid-watch-start/payload.sh
/root/payloads/user/foreign-ssid-watch-stop/foreign-ssid-watch-stop/payload.sh
/root/payloads/user/foreign-ssid-watch-status/foreign-ssid-watch-status/payload.sh
/root/payloads/user/foreign-ssid-watch-clear-seen/foreign-ssid-watch-clear-seen/payload.sh
```

Runtime files:

```text
/root/rogue-ap-detector/foreign-ssid-watch.log
/root/rogue-ap-detector/foreign-ssid-watch-start.log
/root/rogue-ap-detector/foreign-ssid-watch.pid
/root/rogue-ap-detector/foreign-ssid-seen.cache
/tmp/foreign-ssid-raw-scan.txt
/tmp/foreign-ssid-aps.tmp
/tmp/foreign-ssid-scan-error.txt
```

---

## Installation

Connect to the Pager via SSH:

```sh
ssh root@172.16.52.1
```

Copy the install script to the Pager:

```sh
scp Install_Foreign_SSID_Watch.sh root@172.16.52.1:/root/
```

Make it executable:

```sh
chmod +x /root/Install_Foreign_SSID_Watch.sh
```

Run it:

```sh
/root/Install_Foreign_SSID_Watch.sh
```

Reboot the Pager:

```sh
reboot
```

After reboot, the display payloads should appear under:

```text
Dashboard → Payloads
```

---

## Display Usage

### Start the watcher

```text
Dashboard → Payloads → foreign-ssid-watch-start
```

Expected result:

```text
Foreign watch PID <number>
```

The watcher now scans nearby APs every 60 seconds.

---

### Check status

```text
Dashboard → Payloads → foreign-ssid-watch-status
```

Possible results:

```text
Foreign watch running PID <number>
```

or:

```text
Foreign watch stopped
```

---

### Stop the watcher

```text
Dashboard → Payloads → foreign-ssid-watch-stop
```

Expected result:

```text
Foreign watch stopped
```

---

### Clear repeated-alert memory

The watcher remembers already-alerted SSID/BSSID pairs to avoid alert spam.

To allow the same SSID/BSSID pair to alert again:

```text
Dashboard → Payloads → foreign-ssid-watch-clear-seen
```

Expected result:

```text
Foreign seen cache cleared
```

---

## Detection Flow

Every 60 seconds, the watcher runs:

```sh
iw dev wlan0 scan
```

Then it parses all nearby APs and checks their SSIDs.

Simplified logic:

```text
SSID contains only German/Latin characters and allowed punctuation
→ No alert

SSID contains non-German / non-Latin characters
→ Alert, ringtone, vibrate, log finding

Same SSID+BSSID was already alerted
→ No repeated alert until seen cache is cleared
```

---

## Alert Cases and Meanings

### Case 1: Normal German / Latin SSID

Detected:

```text
SSID = Müller-WLAN
BSSID = aa:bb:cc:dd:ee:ff
```

Meaning:

```text
No alert.
```

Reason:

```text
SSID contains only allowed characters.
```

---

### Case 2: Normal SSID with symbols

Detected:

```text
SSID = Guest-WiFi!!!
BSSID = aa:bb:cc:dd:ee:ff
```

Meaning:

```text
No alert.
```

Reason:

```text
Common punctuation and special characters are ignored.
```

---

### Case 3: Non-Latin SSID

Detected:

```text
SSID = 東京WiFi
BSSID = aa:bb:cc:dd:ee:ff
```

Meaning:

```text
Alert.
```

Display alert:

```text
Foreign SSID? 東京WiFi
```

Reason:

```text
SSID contains characters outside the configured German/Latin character set.
```

---

### Case 4: Same foreign SSID appears again

First detection:

```text
Foreign SSID? 東京WiFi
```

Second detection 60 seconds later:

```text
No repeated alert.
```

Reason:

```text
The watcher stores already-alerted SSID+BSSID pairs in foreign-ssid-seen.cache.
```

To alert again:

```text
Dashboard → Payloads → foreign-ssid-watch-clear-seen
```

---

### Case 5: Scan failure

Log example:

```text
scan failed rc=<code> error=<message>
```

Meaning:

```text
The Pager could not scan on wlan0.
```

Common causes:

- `wlan0` is busy
- another payload is scanning
- Recon or another process is using the radio
- temporary driver/radio issue

Check logs:

```sh
tail -n 50 /root/rogue-ap-detector/foreign-ssid-watch.log
cat /tmp/foreign-ssid-scan-error.txt
```

---

## Verification over SSH

After starting the watcher from the display, verify it:

```sh
cat /root/rogue-ap-detector/foreign-ssid-watch.pid
ps | grep foreign_ssid_watchd | grep -v grep
tail -n 30 /root/rogue-ap-detector/foreign-ssid-watch.log
```

Working example:

```text
1234
1234 root 1436 S sh /root/rogue-ap-detector/foreign_ssid_watchd.sh
Fri May 22 12:30:00 UTC 2026 foreign SSID watcher started interface=wlan0 interval=60s
```

---

## Troubleshooting

### Payloads do not appear on display

Check the payload structure:

```sh
find /root/payloads/user -maxdepth 5 -type f -name "payload.sh" -print
```

Expected paths:

```text
/root/payloads/user/foreign-ssid-watch-start/foreign-ssid-watch-start/payload.sh
/root/payloads/user/foreign-ssid-watch-stop/foreign-ssid-watch-stop/payload.sh
/root/payloads/user/foreign-ssid-watch-status/foreign-ssid-watch-status/payload.sh
/root/payloads/user/foreign-ssid-watch-clear-seen/foreign-ssid-watch-clear-seen/payload.sh
```

Fix permissions and line endings:

```sh
find /root/payloads/user -type f -name "payload.sh" -exec sed -i 's/\r$//' {} \;
find /root/payloads/user -type f -name "payload.sh" -exec chmod +x {} \;
reboot
```

---

### Watcher does not start

Check:

```sh
cat /root/rogue-ap-detector/foreign-ssid-watch-start.log
cat /root/rogue-ap-detector/foreign-ssid-watch.log
ps | grep foreign_ssid_watchd | grep -v grep
```

Try starting directly:

```sh
/root/payloads/user/foreign-ssid-watch-start/foreign-ssid-watch-start/payload.sh
```

---

### Watcher says stopped but PID file exists

The PID file may be stale:

```sh
rm -f /root/rogue-ap-detector/foreign-ssid-watch.pid
```

Then start again from the display:

```text
Dashboard → Payloads → foreign-ssid-watch-start
```

---

### Scan returns no APs

Test scan manually:

```sh
iw dev wlan0 scan | grep -E "^BSS|SSID:|signal:|freq:|DS Parameter" | head -n 40
```

If manual scan works but the watcher logs scan failures, stop other scanning features and retry.

---

## Operational Notes

Recommended flow:

```text
1. Start foreign-ssid-watch-start.
2. Check status with foreign-ssid-watch-status.
3. Carry/use the Pager.
4. If a foreign/non-Latin SSID appears, the Pager alerts.
5. Stop with foreign-ssid-watch-stop when finished.
```

This watcher can run independently from the rogue AP allowlist watcher, but both use active scans on `wlan0`. Running multiple scanning workflows at the same time can increase radio contention or scan failures.

---

## Limitations

- Character-based detection does not prove country of origin.
- SSIDs can be spoofed or intentionally named to look foreign.
- Some legitimate local networks may use non-Latin names.
- Short-lived APs may be missed because scanning happens every 60 seconds.
- Running multiple watchers using `wlan0` can cause scan conflicts.
- The rule is intentionally simple and may need tuning for your environment.

---

## Security and Legal Note

Use only in environments where you are authorized to monitor WiFi signals.

This tool does not attack APs or clients. It performs passive/active local scanning and local SSID string analysis only.
