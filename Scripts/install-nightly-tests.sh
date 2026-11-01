#!/bin/bash
# Installs, updates, or removes the nightly test LaunchAgent for this user.
#
# Usage:
#   install-nightly-tests.sh                 install or update (default 2:00 AM)
#   install-nightly-tests.sh --print         show the LaunchAgent plist; change nothing
#   install-nightly-tests.sh --check-access  check, as launchd runs it, that the job can
#                                            read this repository (macOS privacy protection)
#   install-nightly-tests.sh --uninstall     unload and remove the LaunchAgent
#   install-nightly-tests.sh --uninstall --remove-simulators
#                                            also delete the dedicated Nightly simulators
#
# Environment: NIGHTLY_HOUR, NIGHTLY_MINUTE, NIGHTLY_ROOT, DEVELOPER_DIR, and optionally
# NIGHTLY_REF (default: the branch checked out in this working copy at run time).
# A scheduled run may start up to two hours after the scheduled time.
# Installing copies the runner and report scripts into $NIGHTLY_ROOT/bin, so the
# job keeps working when the main working copy switches branches, and builds
# nightly-launcher there (the program launchd runs; it needs Full Disk Access
# because the repository is in ~/Documents). Re-run this after changing a script.

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
LAUNCHER="$NIGHTLY_ROOT/bin/nightly-launcher"
DOMAIN="gui/$(id -u)"

xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

optional_ref() {
    if [ -n "$NIGHTLY_REF" ]; then
        printf '        <key>NIGHTLY_REF</key>\n        <string>%s</string>' "$(xml_escape "$NIGHTLY_REF")"
    fi
}

# Usage: plist_contents [label [extra runner argument]]. With an extra argument the
# job runs once at load instead of on the schedule (used by --check-access).
plist_contents() {
    local label="${1:-$LABEL}" extra="${2:-}" when log="$NIGHTLY_ROOT/logs/launchd.log"
    if [ -n "$extra" ]; then
        extra="
        <string>$extra</string>"
        when="<key>RunAtLoad</key>
    <true/>"
        log="$NIGHTLY_ROOT/logs/check-access.log"
    else
        when="<key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$NIGHTLY_HOUR</integer>
        <key>Minute</key>
        <integer>$NIGHTLY_MINUTE</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>"
    fi
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(xml_escape "$LAUNCHER")</string>$extra
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
    $when
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Standard</string>
    <key>ExitTimeOut</key>
    <integer>120</integer>
    <key>StandardOutPath</key>
    <string>$(xml_escape "$log")</string>
    <key>StandardErrorPath</key>
    <string>$(xml_escape "$log")</string>
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

# Runs the access check once under launchd, exactly as the nightly job would.
check_access() {
    local label="$LABEL.check-access" plist="$NIGHTLY_ROOT/check-access.plist"
    local out="$NIGHTLY_ROOT/logs/check-access.log"
    [ -x "$LAUNCHER" ] || { echo "Not installed yet: run this script without options first." >&2; exit 1; }
    mkdir -p "$NIGHTLY_ROOT/logs"
    rm -f "$out"
    plist_contents "$label" --check-access > "$plist"
    launchctl bootout "$DOMAIN/$label" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$plist"
    for _ in $(seq 1 30); do
        grep -q '^Access check' "$out" 2>/dev/null && break
        sleep 1
    done
    launchctl bootout "$DOMAIN/$label" 2>/dev/null || true
    rm -f "$plist"
    cat "$out" 2>/dev/null || echo "No result after 30 seconds; see $out."
    grep -q '^Access check OK' "$out" 2>/dev/null
}

# Builds the launcher only when its source changed: a rebuilt binary has a new
# signature, and macOS then no longer recognizes the Full Disk Access grant.
build_launcher() {
    if [ -x "$LAUNCHER" ] && cmp -s "$SCRIPT_DIR/nightly-launcher.c" "$LAUNCHER.c"; then
        return
    fi
    DEVELOPER_DIR="$DEVELOPER_DIR" xcrun clang -O2 -Wall -o "$LAUNCHER" "$SCRIPT_DIR/nightly-launcher.c"
    cp "$SCRIPT_DIR/nightly-launcher.c" "$LAUNCHER.c"
    LAUNCHER_REBUILT=1
}

case "${1:-}" in
    --print)
        plist_contents
        exit 0 ;;
    --check-access)
        check_access
        exit $? ;;
    --uninstall)
        uninstall
        [ "${2:-}" = "--remove-simulators" ] && remove_simulators
        exit 0 ;;
    "") ;;
    *) sed -n '2,17p' "$0"; exit 2 ;;
esac

[ -d "$DEVELOPER_DIR" ] || { echo "DEVELOPER_DIR not found: $DEVELOPER_DIR" >&2; exit 1; }

mkdir -p "$NIGHTLY_ROOT/bin" "$NIGHTLY_ROOT/logs" "$(dirname "$PLIST")"
cp "$SCRIPT_DIR/run-nightly-tests.sh" "$SCRIPT_DIR/nightly-test-report.py" "$NIGHTLY_ROOT/bin/"
chmod +x "$NIGHTLY_ROOT/bin/run-nightly-tests.sh" "$NIGHTLY_ROOT/bin/nightly-test-report.py"
LAUNCHER_REBUILT=0
build_launcher

plist_contents > "$PLIST.tmp"
plutil -lint "$PLIST.tmp" > /dev/null
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
mv "$PLIST.tmp" "$PLIST"
launchctl bootstrap "$DOMAIN" "$PLIST"

printf 'Installed %s: daily at %02d:%02d (late-start window %s), testing %s.\n' \
    "$LABEL" "$NIGHTLY_HOUR" "$NIGHTLY_MINUTE" "$LATE_START_WINDOW" \
    "${NIGHTLY_REF:-the branch checked out in $REPO_DIR}"
echo "Results: $NIGHTLY_ROOT/latest/summary.md"
echo
if ! check_access; then
    echo
    echo "Action needed: macOS blocks the job from reading the repository (in ~/Documents). Grant access once:"
    echo "  1. System Settings > Privacy & Security > Full Disk Access > +"
    echo "  2. Press Cmd-Shift-G, enter $LAUNCHER, and add it (leave it switched on)."
    echo "  3. Check again with: $0 --check-access"
    if [ "$LAUNCHER_REBUILT" = 1 ]; then
        echo "The launcher was rebuilt; remove any older nightly-launcher entry from that list."
    fi
fi
