# Foreign / Foreign Language Watch for WiFi Pineapple Pager

A display-driven alert watcher for the **WiFi Pineapple Pager**.

This feature alerts when nearby WiFi access points use SSIDs containing characters outside a German/Latin character set. It is designed for quick field awareness when you want to notice SSIDs using non-Latin or non-German characters.

> This feature does **not** prove that an AP is from another country.  
> It only detects SSID names containing characters outside the configured German/Latin character set.

---

## What It Detects

The watcher allows:

```text
A-Z
a-z
0-9
all normal printable ASCII special characters
ä ö ü Ä Ö Ü ß
```

Everything else triggers an alert.

This final version also handles the way `iw` may print non-ASCII SSIDs as escaped UTF-8 byte strings, for example:

```text
S24\xc4\x83\xc4\x81\xc3\xa0\xc3\xa3\xc3\xa5\xc3\xa2
```

Allowed escaped German sequences are:

```text
\xc3\xa4  ä
\xc3\xb6  ö
\xc3\xbc  ü
\xc3\x84  Ä
\xc3\x96  Ö
\xc3\x9c  Ü
\xc3\x9f  ß
```

Any other `\xHH` escaped byte sequence is treated as foreign / non-German and triggers an alert.

---

## Examples

| SSID | Result | Meaning |
|---|---|---|
| `DIRECT-w0Restaurant_BRd154` | No alert | Normal ASCII characters |
| `FRITZ!Box 7590` | No alert | Normal ASCII characters and punctuation |
| `Müller-WLAN` | No alert | German umlaut is allowed |
| `S24-Test_123!` | No alert | ASCII letters, numbers, and symbols |
| `xyz-intern` | No alert | Normal ASCII characters |
| `S24ăāàãåâ` | Alert | Contains non-German accented letters |
| `S24 ā` | Alert | Contains `ā`, not a German character |
| `S24 ā` | Alert | Contains a combining macron |
| `Café` | Alert | `é` is not in the German allowlist |
| `Кафе-WiFi` | Alert | Contains Cyrillic |
| `咖啡WiFi` | Alert | Contains Chinese characters |
| `東京WiFi` | Alert | Contains Japanese characters |
| `شبكةWiFi` | Alert | Contains Arabic characters |

Alert example:

```text
Foreign SSID? S24\xc4\x83\xc4\x81\xc3\xa0\xc3\xa3\xc3\xa5\xc3\xa2
```

Depending on how the Pager receives the SSID, the alert may show the escaped representation instead of the pretty characters. Detection is still correct.

---

## Installer

The installer script is named:

```text
install.sh
```

It installs:

```text
/root/rogue-ap-detector/foreign_ssid_watchd.sh
```

And the following display payloads:

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

Copy `install.sh` to the Pager:

```sh
scp install.sh root@172.16.52.1:/root/
```

Make it executable:

```sh
chmod +x /root/install.sh
```

Run it:

```sh
/root/install.sh
```

Reboot the Pager:

```sh
reboot
```

After reboot, the payloads should appear under:

```text
Dashboard → Payloads
```

---

## Updating an Existing Installation

You can safely run `install.sh` again.

The installer overwrites:

```text
/root/rogue-ap-detector/foreign_ssid_watchd.sh

/root/payloads/user/foreign-ssid-watch-start/foreign-ssid-watch-start/payload.sh
/root/payloads/user/foreign-ssid-watch-stop/foreign-ssid-watch-stop/payload.sh
/root/payloads/user/foreign-ssid-watch-status/foreign-ssid-watch-status/payload.sh
/root/payloads/user/foreign-ssid-watch-clear-seen/foreign-ssid-watch-clear-seen/payload.sh
```

It also stops old `foreign_ssid_watchd.sh` processes and clears the seen cache:

```text
/root/rogue-ap-detector/foreign-ssid-seen.cache
```

Recommended update flow:

```sh
/root/install.sh
reboot
```

Then start the watcher again from the display.

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

### Stop the watcher

```text
Dashboard → Payloads → foreign-ssid-watch-stop
```

Expected result:

```text
Foreign watch stopped
```

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
SSID contains only printable ASCII and German umlauts
→ No alert

SSID contains allowed escaped German UTF-8 sequences
→ No alert

SSID contains any other escaped UTF-8 byte sequence
→ Alert

SSID contains direct non-German UTF-8 characters
→ Alert

Same SSID+BSSID was already alerted
→ No repeated alert until seen cache is cleared
```

---

## Alert Cases and Meanings

### Case 1: Normal ASCII SSID

Detected:

```text
SSID = DIRECT-w0Restaurant_BRd154
```

Meaning:

```text
No alert.
```

Reason:

```text
SSID contains only printable ASCII characters.
```

### Case 2: German SSID

Detected:

```text
SSID = Müller-WLAN
```

Meaning:

```text
No alert.
```

Reason:

```text
German umlauts are explicitly allowed.
```

### Case 3: Non-German accented SSID

Detected:

```text
SSID = S24ăāàãåâ
```

Possible `iw` representation:

```text
SSID = S24\xc4\x83\xc4\x81\xc3\xa0\xc3\xa3\xc3\xa5\xc3\xa2
```

Meaning:

```text
Alert.
```

Reason:

```text
The SSID contains non-German accented characters.
```

Expected log:

```text
DECISION=FOREIGN_ESCAPED SSID=[S24\xc4\x83\xc4\x81\xc3\xa0\xc3\xa3\xc3\xa5\xc3\xa2]
ALERT Foreign SSID? S24\xc4\x83\xc4\x81\xc3\xa0\xc3\xa3\xc3\xa5\xc3\xa2
```

### Case 4: Non-Latin SSID

Detected:

```text
SSID = 東京WiFi
```

Meaning:

```text
Alert.
```

Reason:

```text
SSID contains characters outside printable ASCII and German umlauts.
```

### Case 5: Same foreign SSID appears again

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

### Case 6: Scan failure

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
tail -n 100 /root/rogue-ap-detector/foreign-ssid-watch.log
```

Working example:

```text
1234
1234 root 1436 S sh /root/rogue-ap-detector/foreign_ssid_watchd.sh
Fri May 22 12:21:51 UTC 2026 foreign SSID watcher started FINAL interface=wlan0 interval=60s
```

Example decisions:

```text
DECISION=CLEAN SSID=[DIRECT-w0Restaurant_BRd154]
DECISION=CLEAN SSID=[xyz-intern]
DECISION=FOREIGN_ESCAPED SSID=[S24\xc4\x83\xc4\x81\xc3\xa0\xc3\xa3\xc3\xa5\xc3\xa2]
ALERT Foreign SSID? S24\xc4\x83\xc4\x81\xc3\xa0\xc3\xa3\xc3\xa5\xc3\xa2
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

### Watcher says stopped but PID file exists

The PID file may be stale:

```sh
rm -f /root/rogue-ap-detector/foreign-ssid-watch.pid
```

Then start again from the display:

```text
Dashboard → Payloads → foreign-ssid-watch-start
```

### Scan returns no APs

Test scan manually:

```sh
iw dev wlan0 scan | grep -E "^BSS|SSID:|signal:|freq:|DS Parameter" | head -n 40
```

If manual scan works but the watcher logs scan failures, stop other scanning features and retry.

### A normal SSID is falsely detected

Check the exact decision and SSID representation:

```sh
grep -i "<SSID_PART>" /root/rogue-ap-detector/foreign-ssid-watch.log
grep -i "<SSID_PART>" /tmp/foreign-ssid-aps.tmp
```

The watcher should treat this as clean:

```text
DIRECT-w0Restaurant_BRd154
```

If not, inspect the raw output:

```sh
grep -i "<SSID_PART>" /tmp/foreign-ssid-aps.tmp | od -An -tx1 -v
```

### A foreign SSID is not detected

Clear the seen cache and restart:

```sh
/root/payloads/user/foreign-ssid-watch-stop/foreign-ssid-watch-stop/payload.sh
: > /root/rogue-ap-detector/foreign-ssid-seen.cache
/root/payloads/user/foreign-ssid-watch-start/foreign-ssid-watch-start/payload.sh
```

Check the log after one scan cycle:

```sh
tail -n 100 /root/rogue-ap-detector/foreign-ssid-watch.log
```

---

## Operational Notes

Recommended flow:

```text
1. Run install.sh.
2. Reboot.
3. Start foreign-ssid-watch-start from the display.
4. Check status with foreign-ssid-watch-status.
5. Carry/use the Pager.
6. If a foreign/non-German SSID appears, the Pager alerts.
7. Stop with foreign-ssid-watch-stop when finished.
```

This watcher can run independently from the rogue AP allowlist watcher, but both use active scans on `wlan0`. Running multiple scanning workflows at the same time can increase radio contention or scan failures.

---

## Limitations

- Character-based detection does not prove country of origin.
- SSIDs can be spoofed or intentionally named to look foreign.
- Some legitimate local networks may use non-German names.
- Short-lived APs may be missed because scanning happens every 60 seconds.
- Running multiple watchers using `wlan0` can cause scan conflicts.
- The rule is intentionally strict: only printable ASCII and German umlauts are allowed.

---

## Security and Legal Note

Use only in environments where you are authorized to monitor WiFi signals.

This tool does not attack APs or clients. It performs local WiFi scanning and local SSID string analysis only.
