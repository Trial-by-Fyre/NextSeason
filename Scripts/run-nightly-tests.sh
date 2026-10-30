#!/bin/bash
# Nightly unit + UI test run on each supported iOS simulator, one at a time.
#
# Tests the latest commit of the branch checked out in the main working copy
# (never its uncommitted changes) in an isolated Git worktree with its own
# DerivedData, builds once (build-for-testing), then runs the SerialTesting
# plan with test-without-building on dedicated "Nightly" simulators. Never
# touches the main working copy, Xcode's DerivedData, or existing simulators.
#
# Usage: run-nightly-tests.sh [--ref REF] [--os VERSION]... [--only-testing ID]...
# See Scripts/README.md ("Nightly tests") for installation and configuration.
#
# Exit status: 0 all passed (or a late-start / detached-HEAD skip), 1 test/build failure,
# 2 setup error, 75 another run holds the lock, 130/143 interrupted.

set -uo pipefail

# --- Configuration (environment overrides) ----------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
NIGHTLY_ROOT="${NIGHTLY_ROOT:-$HOME/Library/Developer/NightlyTests/NextSeason}"
# Empty: test the branch checked out in REPO_DIR when the run starts.
NIGHTLY_REF="${NIGHTLY_REF:-}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.0.0.app/Contents/Developer}"
PROJECT_FILE="${PROJECT_FILE:-NextSeason.xcodeproj}"
SCHEME="${SCHEME:-NextSeason}"
TEST_PLAN="${TEST_PLAN:-SerialTesting}"
# "iOS version|device type" entries, separated by semicolons.
DESTINATIONS="${DESTINATIONS:-18.6|iPhone 16 Pro;26.5|iPhone 17 Pro;27.0|iPhone 18 Pro Max}"
SIMULATOR_PREFIX="${SIMULATOR_PREFIX:-NextSeason Nightly}"
# Untracked files copied from the main working copy (relative paths, colon-separated).
COPY_UNTRACKED="${COPY_UNTRACKED:-Config/Secrets.xcconfig}"
KNOWN_FAILURES_FILE="${KNOWN_FAILURES_FILE:-$REPO_DIR/Scripts/nightly-known-failures.txt}"
KEEP_RUNS="${KEEP_RUNS:-14}"
STEP_TIMEOUT_SECONDS="${STEP_TIMEOUT_SECONDS:-5400}"   # per build or per-OS test step
NIGHTLY_SCHEDULED="${NIGHTLY_SCHEDULED:-0}"            # set to 1 by the LaunchAgent
LATE_START_WINDOW="${LATE_START_WINDOW:-02:00-04:00}"  # scheduled runs start only in this window
NIGHTLY_CLEAN_BUILD="${NIGHTLY_CLEAN_BUILD:-0}"        # 1 deletes DerivedData first
# /usr/bin/python3, not PATH: a PATH python3 may be an unusable x86_64 build.
PYTHON="${PYTHON:-/usr/bin/python3}"

# launchd provides a minimal PATH; keep any caller PATH first (tests use fakes).
export PATH="${PATH:-}:/usr/bin:/bin:/usr/sbin:/sbin"

ONLY_TESTING=()
OS_FILTER=()
while [ $# -gt 0 ]; do
    case "$1" in
        --ref) NIGHTLY_REF="$2"; shift 2 ;;
        --os) OS_FILTER+=("$2"); shift 2 ;;
        --only-testing) ONLY_TESTING+=("-only-testing:$2"); shift 2 ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

CHECKOUT_DIR="$NIGHTLY_ROOT/checkout"
DERIVED_DATA="$NIGHTLY_ROOT/DerivedData"
PACKAGES_DIR="$NIGHTLY_ROOT/SourcePackages"
RUNS_DIR="$NIGHTLY_ROOT/runs"
LOCK_DIR="$NIGHTLY_ROOT/lock"
RUN_ID="$(date +%Y-%m-%d_%H%M%S)"
RUN_DIR="$RUNS_DIR/$RUN_ID"

mkdir -p "$RUNS_DIR" "$NIGHTLY_ROOT/logs" || exit 2
while [ -e "$RUN_DIR" ]; do RUN_ID="${RUN_ID}x"; RUN_DIR="$RUNS_DIR/$RUN_ID"; done
mkdir -p "$RUN_DIR" || exit 2

# --- Helpers ------------------------------------------------------------------

log() {
    printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$RUN_DIR/run.log"
}

# Appends key=value metadata for the report.
meta() {
    printf '%s=%s\n' "$1" "$2" >> "$RUN_DIR/run.env"
}

# Whether the login session's screen is locked: locked, unlocked, or unknown.
screen_state() {
    local value
    value=$(ioreg -n Root -d1 2>/dev/null | grep -o '"CGSSessionScreenIsLocked"=[A-Za-z]*' | head -1)
    case "$value" in
        *Yes) echo locked ;;
        "") echo unlocked ;;
        *) echo unknown ;;
    esac
}

json_value() {  # python expression over parsed JSON `d` from stdin
    "$PYTHON" -c "import json,sys; d=json.load(sys.stdin); print($1)"
}

LOCK_HELD=0
FINISHED=0
CHILD_PID=""
WATCHDOG_PID=""
CURRENT_STEP=""     # tab-separated step fields while a step is running
BOOTED_UDIDS=()

stop_watchdog() {
    if [ -n "$WATCHDOG_PID" ]; then
        kill -TERM "$WATCHDOG_PID" 2>/dev/null
        wait "$WATCHDOG_PID" 2>/dev/null
        WATCHDOG_PID=""
    fi
}

# Records one step: kind, OS, device, udid, runtime build, start, end, exit, state.
record_step() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$RUN_DIR/steps.tsv"
}

# Runs a command in the background with a watchdog so signals and timeouts
# can stop it. Output goes to $1. Sets STEP_STATE to ok, failed, or timeout.
run_step() {
    local logfile="$1"; shift
    "$@" > "$logfile" 2>&1 &
    CHILD_PID=$!
    # Sleeps run in the background and are awaited so the TERM trap fires at once.
    (
        trap 'kill "$sleeper" 2>/dev/null; exit 0' TERM
        sleep "$STEP_TIMEOUT_SECONDS" & sleeper=$!
        wait "$sleeper"
        echo "nightly: step exceeded ${STEP_TIMEOUT_SECONDS}s; stopping it" >> "$logfile"
        touch "$logfile.timeout"
        kill -TERM "$CHILD_PID" 2>/dev/null
        sleep 30 & sleeper=$!
        wait "$sleeper"
        kill -KILL "$CHILD_PID" 2>/dev/null
    ) &
    WATCHDOG_PID=$!
    STEP_EXIT=0
    wait "$CHILD_PID" || STEP_EXIT=$?
    stop_watchdog
    CHILD_PID=""
    if [ -e "$logfile.timeout" ]; then
        STEP_STATE=timeout
    elif [ "$STEP_EXIT" -eq 0 ]; then
        STEP_STATE=ok
    else
        STEP_STATE=failed
    fi
}

shutdown_simulators() {
    local udid
    for udid in "${BOOTED_UDIDS[@]+"${BOOTED_UDIDS[@]}"}"; do
        xcrun simctl shutdown "$udid" > /dev/null 2>&1
    done
    BOOTED_UDIDS=()
}

prune_old_runs() {
    local entry
    # Run IDs are timestamps, so reverse order is newest first.
    ls -1 "$RUNS_DIR" | sort -r | tail -n +"$((KEEP_RUNS + 1))" | while read -r entry; do
        [ "$entry" = "$RUN_ID" ] || rm -rf "${RUNS_DIR:?}/$entry"
    done
    # Keep the launchd log from growing without bound.
    local launchd_log="$NIGHTLY_ROOT/logs/launchd.log"
    if [ -f "$launchd_log" ] && [ "$(wc -c < "$launchd_log")" -gt 5000000 ]; then
        tail -c 500000 "$launchd_log" > "$launchd_log.tmp" && cat "$launchd_log.tmp" > "$launchd_log"
        rm -f "$launchd_log.tmp"
    fi
}

finish() {
    local status=$?
    [ "$FINISHED" -eq 1 ] && return
    FINISHED=1
    trap - INT TERM
    shutdown_simulators
    meta finished_at "$(date +%s)"
    meta exit_status "$status"
    "$PYTHON" "$SCRIPT_DIR/nightly-test-report.py" "$RUN_DIR" \
        --runs-dir "$RUNS_DIR" --known "$KNOWN_FAILURES_FILE" \
        --history "$NIGHTLY_ROOT/history.log" > /dev/null 2>> "$RUN_DIR/run.log" \
        || log "Report generation failed; see run.log"
    ln -sfn "$RUN_DIR" "$NIGHTLY_ROOT/latest"
    [ -f "$RUN_DIR/summary.md" ] && cat "$RUN_DIR/summary.md"
    prune_old_runs
    if [ "$LOCK_HELD" -eq 1 ]; then
        rm -rf "$LOCK_DIR"
    fi
    exit "$status"
}

on_signal() {
    local code=$1
    log "Received signal; stopping the current step."
    meta interrupted 1
    if [ -n "$CHILD_PID" ]; then
        kill -TERM "$CHILD_PID" 2>/dev/null
        wait "$CHILD_PID" 2>/dev/null
    fi
    stop_watchdog
    if [ -n "$CURRENT_STEP" ]; then
        printf '%s\t%s\t-1\tinterrupted\n' "$CURRENT_STEP" "$(date +%s)" >> "$RUN_DIR/steps.tsv"
    fi
    exit "$code"
}

setup_error() {
    log "ERROR: $*"
    meta setup_error "$*"
    exit 2
}

trap finish EXIT
trap 'on_signal 130' INT
trap 'on_signal 143' TERM

meta run_id "$RUN_ID"
meta started_at "$(date +%s)"
meta scheduled "$NIGHTLY_SCHEDULED"
[ ${#ONLY_TESTING[@]} -gt 0 ] && meta only_testing "${ONLY_TESTING[*]}"

# --- Late-start guard (scheduled runs only) ----------------------------------
# launchd runs a missed job when the Mac wakes; don't start a long run mid-morning.

minutes() {  # HH:MM -> minutes since midnight
    echo $((10#${1%%:*} * 60 + 10#${1#*:}))
}

# True when $1 (HH:MM) falls in LATE_START_WINDOW, which may span midnight.
in_start_window() {
    local now first last
    now=$(minutes "$1"); first=$(minutes "${LATE_START_WINDOW%-*}"); last=$(minutes "${LATE_START_WINDOW#*-}")
    if [ "$first" -le "$last" ]; then
        [ "$now" -ge "$first" ] && [ "$now" -le "$last" ]
    else
        [ "$now" -ge "$first" ] || [ "$now" -le "$last" ]
    fi
}

if [ "$NIGHTLY_SCHEDULED" = "1" ]; then
    now="${NIGHTLY_TEST_TIME:-$(date +%H:%M)}"
    if ! in_start_window "$now"; then
        log "Scheduled start at $now is outside $LATE_START_WINDOW; skipping."
        meta skipped "late start at $now (allowed $LATE_START_WINDOW)"
        exit 0
    fi
fi

# --- Lock: one run at a time --------------------------------------------------

if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_HELD=1
else
    other_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
    if [ -n "$other_pid" ] && kill -0 "$other_pid" 2>/dev/null; then
        log "Another nightly run (pid $other_pid) is still running; skipping."
        meta skipped "another run (pid $other_pid) is still running"
        exit 75
    fi
    log "Removing stale lock left by an interrupted run (pid ${other_pid:-unknown})."
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || setup_error "Could not take the lock at $LOCK_DIR"
    LOCK_HELD=1
fi
echo $$ > "$LOCK_DIR/pid"

# Prevent idle sleep for the life of this run (no system settings change).
if command -v caffeinate > /dev/null; then
    caffeinate -i -w $$ &
fi

# --- Revision and isolated checkout ------------------------------------------

[ -d "$DEVELOPER_DIR" ] || setup_error "DEVELOPER_DIR not found: $DEVELOPER_DIR"
git -C "$REPO_DIR" rev-parse --git-dir > /dev/null 2>&1 || setup_error "Not a Git repository: $REPO_DIR"
if [ -n "$NIGHTLY_REF" ]; then
    REF="$NIGHTLY_REF"
    BRANCH=""
    git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/$REF" && BRANCH="$REF"
else
    # The branch checked out now; its latest commit, not the working-copy state.
    if ! BRANCH=$(git -C "$REPO_DIR" symbolic-ref --quiet --short HEAD); then
        log "The working copy is in a detached HEAD state, so there is no branch to test; skipping."
        meta skipped "the working copy at $REPO_DIR is in a detached HEAD state (no branch checked out)"
        exit 0
    fi
    REF="refs/heads/$BRANCH"
fi
meta ref "${NIGHTLY_REF:-$BRANCH}"
meta branch "$BRANCH"
SHA=$(git -C "$REPO_DIR" rev-parse --verify --quiet "$REF^{commit}") \
    || setup_error "Cannot resolve revision '${NIGHTLY_REF:-$BRANCH}'"
meta sha "$SHA"
meta subject "$(git -C "$REPO_DIR" log -1 --format=%s "$SHA")"
meta commit_date "$(git -C "$REPO_DIR" log -1 --format=%ci "$SHA")"
log "Testing ${BRANCH:-$NIGHTLY_REF} at $SHA"

if [ -e "$CHECKOUT_DIR/.git" ]; then
    git -C "$CHECKOUT_DIR" checkout --quiet --force --detach "$SHA" >> "$RUN_DIR/run.log" 2>&1 \
        || setup_error "Could not check out $SHA in $CHECKOUT_DIR"
    git -C "$CHECKOUT_DIR" clean -ffdxq >> "$RUN_DIR/run.log" 2>&1
else
    rm -rf "$CHECKOUT_DIR"
    # --force re-registers a worktree path whose directory was deleted.
    git -C "$REPO_DIR" worktree add --force --detach "$CHECKOUT_DIR" "$SHA" >> "$RUN_DIR/run.log" 2>&1 \
        || setup_error "Could not create worktree at $CHECKOUT_DIR"
fi
[ "$(git -C "$CHECKOUT_DIR" rev-parse HEAD)" = "$SHA" ] || setup_error "Checkout is not at $SHA"
[ -z "$(git -C "$CHECKOUT_DIR" status --porcelain)" ] || setup_error "Checkout has unexpected changes"

IFS=':' read -r -a untracked <<< "$COPY_UNTRACKED"
for rel in "${untracked[@]+"${untracked[@]}"}"; do
    if [ -f "$REPO_DIR/$rel" ]; then
        mkdir -p "$(dirname "$CHECKOUT_DIR/$rel")"
        cp "$REPO_DIR/$rel" "$CHECKOUT_DIR/$rel"
    else
        log "WARNING: $rel not found in $REPO_DIR; tests that need it may fail."
        meta warning "$rel was not found in the main working copy"
    fi
done

[ -d "$CHECKOUT_DIR/$PROJECT_FILE" ] || setup_error "$PROJECT_FILE not found at $SHA"
[ -n "$(find "$CHECKOUT_DIR" -name "$TEST_PLAN.xctestplan" -not -path '*/.git/*' | head -1)" ] \
    || setup_error "$TEST_PLAN.xctestplan not found at $SHA"

# --- Environment --------------------------------------------------------------

meta xcode "$(xcrun xcodebuild -version 2>/dev/null | tr '\n' ' ')"
meta macos "$(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
meta developer_dir "$DEVELOPER_DIR"

RUNTIMES_JSON=$(xcrun simctl list runtimes -j 2>/dev/null) || setup_error "simctl could not list runtimes"

# Resolves each destination to a dedicated simulator, creating it if needed.
DEST_OS=(); DEST_DEVICE=(); DEST_UDID=(); DEST_BUILD=()
IFS=';' read -r -a destinations <<< "$DESTINATIONS"
for entry in "${destinations[@]}"; do
    os="${entry%%|*}"; device="${entry#*|}"
    if [ ${#OS_FILTER[@]} -gt 0 ] && [[ " ${OS_FILTER[*]} " != *" $os "* ]]; then
        continue
    fi
    runtime=$(printf '%s' "$RUNTIMES_JSON" | json_value \
        "next((r['identifier']+' '+r.get('buildversion','?') for r in d['runtimes'] if r.get('platform','iOS')=='iOS' and r['version']=='$os' and r.get('isAvailable',True)),'')")
    [ -n "$runtime" ] || setup_error "iOS $os simulator runtime is not installed"
    runtime_id="${runtime% *}"; runtime_build="${runtime#* }"
    name="$SIMULATOR_PREFIX $device iOS $os"
    udid=$(xcrun simctl list devices -j | json_value \
        "next((x['udid'] for x in d['devices'].get('$runtime_id',[]) if x['name']=='$name' and x.get('isAvailable',True)),'')")
    if [ -z "$udid" ]; then
        udid=$(xcrun simctl create "$name" "$device" "$runtime_id" 2>> "$RUN_DIR/run.log") \
            || setup_error "Could not create simulator '$name'"
        log "Created simulator '$name' ($udid)"
    fi
    DEST_OS+=("$os"); DEST_DEVICE+=("$device"); DEST_UDID+=("$udid"); DEST_BUILD+=("$runtime_build")
done
[ ${#DEST_OS[@]} -gt 0 ] || setup_error "No destinations selected"

# --- Build once ---------------------------------------------------------------

if [ "$NIGHTLY_CLEAN_BUILD" = "1" ]; then
    log "Deleting DerivedData for a clean build."
    rm -rf "$DERIVED_DATA"
fi
rm -f "$DERIVED_DATA"/Build/Products/*.xctestrun

log "Building for testing ($SCHEME, $TEST_PLAN)"
start=$(date +%s)
CURRENT_STEP=$(printf 'build\t-\t-\t%s\t-\t%s' "${DEST_UDID[0]}" "$start")
run_step "$RUN_DIR/build.log" xcrun xcodebuild build-for-testing \
    -project "$CHECKOUT_DIR/$PROJECT_FILE" -scheme "$SCHEME" -testPlan "$TEST_PLAN" \
    -destination "id=${DEST_UDID[0]}" \
    -derivedDataPath "$DERIVED_DATA" -clonedSourcePackagesDirPath "$PACKAGES_DIR" \
    -resultBundlePath "$RUN_DIR/build.xcresult"
CURRENT_STEP=""
record_step build - - "${DEST_UDID[0]}" - "$start" "$(date +%s)" "$STEP_EXIT" "$STEP_STATE"

XCTESTRUN=$(ls -t "$DERIVED_DATA"/Build/Products/*"$TEST_PLAN"*.xctestrun 2>/dev/null | head -1)
if [ "$STEP_STATE" != ok ] || [ -z "$XCTESTRUN" ]; then
    log "Build failed ($STEP_STATE, exit $STEP_EXIT); see build.log"
    exit 1
fi

# --- Test each OS, one at a time ---------------------------------------------

overall=0
for i in "${!DEST_OS[@]}"; do
    os="${DEST_OS[$i]}"; device="${DEST_DEVICE[$i]}"; udid="${DEST_UDID[$i]}"
    label="ios-$os"
    log "Testing iOS $os on $device ($udid)"
    xcrun simctl shutdown "$udid" > /dev/null 2>&1
    xcrun simctl erase "$udid" >> "$RUN_DIR/run.log" 2>&1 || log "WARNING: could not erase $udid"
    BOOTED_UDIDS+=("$udid")
    meta "screen_$os" "$(screen_state)"
    start=$(date +%s)
    CURRENT_STEP=$(printf 'test\t%s\t%s\t%s\t%s\t%s' "$os" "$device" "$udid" "${DEST_BUILD[$i]}" "$start")
    run_step "$RUN_DIR/$label.log" xcrun xcodebuild test-without-building \
        -xctestrun "$XCTESTRUN" -destination "id=$udid" \
        -resultBundlePath "$RUN_DIR/$label.xcresult" "${ONLY_TESTING[@]+"${ONLY_TESTING[@]}"}"
    CURRENT_STEP=""
    record_step test "$os" "$device" "$udid" "${DEST_BUILD[$i]}" "$start" "$(date +%s)" "$STEP_EXIT" "$STEP_STATE"
    log "iOS $os finished: $STEP_STATE (exit $STEP_EXIT)"
    [ "$STEP_STATE" = ok ] || overall=1
    shutdown_simulators
done

exit "$overall"
