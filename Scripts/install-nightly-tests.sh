#!/bin/bash
# Installs, updates, or removes the nightly test LaunchAgent for this user.
#
# Usage:
#   install-nightly-tests.sh                 install or update (default 2:00 AM)
#   install-nightly-tests.sh --print         show the LaunchAgent plist; change nothing
#   install-nightly-tests.sh --uninstall     unload and remove the LaunchAgent
#   install-nightly-tests.sh --uninstall --remove-simulators
#                                            also delete the dedicated Nightly simulators
#
# Environment: NIGHTLY_HOUR, NIGHTLY_MINUTE, NIGHTLY_ROOT, DEVELOPER_DIR, and optionally
# NIGHTLY_REF (default: the branch checked out in this working copy at run time).
# A scheduled run may start up to two hours after the scheduled time.
# Installing copies the runner and report scripts into $NIGHTLY_ROOT/bin, so the
# job keeps working when the main working copy switches branches. Re-run this
# after changing either script.

set -euo pipefail

LABEL="com.trialbyfyre.nextseason.nightly-tests"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NIGHTLY_ROOT="${NIGHTLY_ROOT:-$HOME/Library/Developer/NightlyTests/NextSeason}"
NIGHTLY_HOUR="${NIGHTLY_HOUR:-2}"
NIGHTLY_MINUTE="${NIGHTLY_MINUTE:-0}"
NIGHTLY_REF="${NIGHTLY_REF:-}"
# Late-start window: the scheduled time through two hours later (02:00-04:00 by default).
LATE_START_WINDOW="${LATE_START_WINDOW:-$(printf '%02d:%02d-%02d:%02d' \
    "$NIGHTLY_HOUR" "$NIGHTLY_MINUTE" "$(( (NIGHTLY_HOUR + 2) % 24 ))" "$NIGHTLY_MINUTE")}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.0.0.app/Contents/Developer}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

optional_ref() {
    if [ -n "$NIGHTLY_REF" ]; then
        printf '        <key>NIGHTLY_REF</key>\n        <string>%s</string>' "$(xml_escape "$NIGHTLY_REF")"
    fi
}

plist_contents() {
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$(xml_escape "$NIGHTLY_ROOT/bin/run-nightly-tests.sh")</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>REPO_DIR</key>
        <string>$(xml_escape "$REPO_DIR")</string>
        <key>NIGHTLY_ROOT</key>
        <string>$(xml_escape "$NIGHTLY_ROOT")</string>
$(optional_ref)
        <key>LATE_START_WINDOW</key>
        <string>$LATE_START_WINDOW</string>
        <key>DEVELOPER_DIR</key>
        <string>$(xml_escape "$DEVELOPER_DIR")</string>
        <key>NIGHTLY_SCHEDULED</key>
        <string>1</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$NIGHTLY_HOUR</integer>
        <key>Minute</key>
        <integer>$NIGHTLY_MINUTE</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Standard</string>
    <key>ExitTimeOut</key>
    <integer>120</integer>
    <key>StandardOutPath</key>
    <string>$(xml_escape "$NIGHTLY_ROOT/logs/launchd.log")</string>
    <key>StandardErrorPath</key>
    <string>$(xml_escape "$NIGHTLY_ROOT/logs/launchd.log")</string>
</dict>
</plist>
EOF
}

uninstall() {
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "Removed LaunchAgent $LABEL. Results remain in $NIGHTLY_ROOT."
}

remove_simulators() {
    export DEVELOPER_DIR
    xcrun simctl list devices | sed -n 's/^ *\(NextSeason Nightly .*\) (\([0-9A-F-]\{36\}\)).*/\2 \1/p' |
        while read -r udid name; do
            xcrun simctl delete "$udid" && echo "Deleted simulator $name ($udid)"
        done
}

case "${1:-}" in
    --print)
        plist_contents
        exit 0 ;;
    --uninstall)
        uninstall
        [ "${2:-}" = "--remove-simulators" ] && remove_simulators
        exit 0 ;;
    "") ;;
    *) sed -n '2,14p' "$0"; exit 2 ;;
esac

[ -d "$DEVELOPER_DIR" ] || { echo "DEVELOPER_DIR not found: $DEVELOPER_DIR" >&2; exit 1; }

mkdir -p "$NIGHTLY_ROOT/bin" "$NIGHTLY_ROOT/logs" "$(dirname "$PLIST")"
cp "$SCRIPT_DIR/run-nightly-tests.sh" "$SCRIPT_DIR/nightly-test-report.py" "$NIGHTLY_ROOT/bin/"
chmod +x "$NIGHTLY_ROOT/bin/run-nightly-tests.sh" "$NIGHTLY_ROOT/bin/nightly-test-report.py"

plist_contents > "$PLIST.tmp"
plutil -lint "$PLIST.tmp" > /dev/null
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
mv "$PLIST.tmp" "$PLIST"
launchctl bootstrap "$DOMAIN" "$PLIST"

printf 'Installed %s: daily at %02d:%02d (late-start window %s), testing %s.\n' \
    "$LABEL" "$NIGHTLY_HOUR" "$NIGHTLY_MINUTE" "$LATE_START_WINDOW" \
    "${NIGHTLY_REF:-the branch checked out in $REPO_DIR}"
echo "Results: $NIGHTLY_ROOT/latest/summary.md"
