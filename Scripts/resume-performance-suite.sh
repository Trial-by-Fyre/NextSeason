#!/usr/bin/env bash
#
# resume-performance-suite.sh
# NextSeason
#
# Resume network, stress, and analysis for an existing session directory.
#
# Usage:
#   ./Scripts/resume-performance-suite.sh .instruments/20260628-222731
#   DEVICE_UDID=... ./Scripts/resume-performance-suite.sh SESSION_DIR
#   APP_PATH=/path/to/NextSeason.app SKIP_BUILD=1 ./Scripts/resume-performance-suite.sh SESSION_DIR
#
set -euo pipefail

SESSION="${1:?usage: resume-performance-suite.sh SESSION_DIR}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/device-log-capture.sh
source "${ROOT}/Scripts/lib/device-log-capture.sh"
# shellcheck source=lib/performance-suite-common.sh
source "${ROOT}/Scripts/lib/performance-suite-common.sh"
device_log_capture_install_cleanup_trap
DEVICE_LOG_CAPTURE_BACKEND="${DEVICE_LOG_CAPTURE_BACKEND:-trace}"
SUBSYSTEM="com.TrialByFyre.NextSeason"

if [[ ! -d "${SESSION}" ]]; then
    echo "error: session directory not found: ${SESSION}" >&2
    exit 1
fi

MANIFEST="${SESSION}/manifest.json"
if [[ ! -f "${MANIFEST}" ]]; then
    echo "error: manifest not found: ${MANIFEST}" >&2
    exit 1
fi

DEVICE="${DEVICE_UDID:-$(connected_device_udid)}"
if [[ -z "${DEVICE}" ]]; then
    echo "error: no connected iPhone. Set DEVICE_UDID or plug in a device." >&2
    exit 1
fi

APP="$(resolve_performance_app "${DEVICE}")"
if [[ ! -d "${APP}" ]]; then
    echo "error: app not found at ${APP}" >&2
    exit 1
fi

mkdir -p "${SESSION}/har"

append_manifest() {
    local flow="$1" trace="$2" log="${3:-}" har="${4:-}"
    python3 - <<PY
import json
from pathlib import Path
p = Path("${MANIFEST}")
data = json.loads(p.read_text())
entry = {"flow": "${flow}", "trace": "${trace}"}
if "${log}":
    entry["log"] = "${log}"
if "${har}":
    entry["har"] = "${har}"
data["runs"].append(entry)
p.write_text(json.dumps(data, indent=2))
PY
}

start_log() {
    local log_file="$1"
    local predicate="subsystem == \"${SUBSYSTEM}\" OR processImagePath CONTAINS \"NextSeason\""
    device_log_capture_begin "${DEVICE}" "${log_file}" "${predicate}"
}

stop_log() {
    local window="${1:-2m}"
    device_log_capture_end "${window}" "${2:-}"
}

already_ran() {
    local flow="$1"
    local trace_path="${2:-}"
    if [[ -n "${trace_path}" && -d "${SESSION}/${trace_path}" ]]; then
        echo "yes"
        return
    fi
    python3 - <<PY
import json
from pathlib import Path
flows = [r["flow"] for r in json.loads(Path("${MANIFEST}").read_text())["runs"]]
print("yes" if "${flow}" in flows else "no")
PY
}

echo "Resuming session: ${SESSION}"
echo "Device: ${DEVICE}"
echo "App: ${APP}"
echo

echo ">> network captures"
for net_flow in search showDetails addToWishlist; do
    TRACE="${SESSION}/traces/network-${net_flow}.trace"
    if [[ "$(already_ran "network-${net_flow}" "traces/network-${net_flow}.trace")" == "yes" ]]; then
        python3 - <<PY
import json
from pathlib import Path
p = Path("${MANIFEST}")
data = json.loads(p.read_text())
if not any(r.get("flow") == "network-${net_flow}" for r in data["runs"]):
    data["runs"].append({"flow": "network-${net_flow}", "trace": "traces/network-${net_flow}.trace", "log": "logs/network-${net_flow}.log", "har": "har/${net_flow}.har"})
    p.write_text(json.dumps(data, indent=2))
PY
        echo "  skip network-${net_flow} (trace exists)"
        continue
    fi
    HAR="${SESSION}/har/${net_flow}.har"
    LOG="${SESSION}/logs/network-${net_flow}.log"
    start_log "${LOG}"
    xcrun xctrace record --template "Time Profiler" --instrument "HTTP Traffic" --instrument os_log --device "${DEVICE}" \
        --output "${TRACE}" --time-limit "35s" --no-prompt \
        --launch -- "${APP}" -ProfileFlow "${net_flow}" || true
    "${PROFILE_PYTHON:-/usr/bin/python3}" "${ROOT}/Scripts/export-performance-evidence.py" "${TRACE}" --har "${HAR}" || true
    stop_log "45s" "${TRACE}"
    append_manifest "network-${net_flow}" "traces/network-${net_flow}.trace" "logs/network-${net_flow}.log" "har/${net_flow}.har"
    echo "  network ${net_flow} done"
done

for item in "stressSearchDetailsBack:200s" "stressAddRemoveWishlist:120s" "stressSearchEmpty:140s"; do
    stress="${item%%:*}"
    limit="${item##*:}"
    if [[ "$(already_ran "${stress}" "traces/${stress}.trace")" == "yes" ]]; then
        echo ">> skip ${stress} (already recorded)"
        continue
    fi
    echo ">> ${stress}"
    TRACE="${SESSION}/traces/${stress}.trace"
    LOG="${SESSION}/logs/${stress}.log"
    start_log "${LOG}"
    xcrun xctrace record --template "Time Profiler" --instrument os_log \
        --instrument "Allocations" --instrument "Leaks" --instrument "Activity Monitor" \
        --device "${DEVICE}" --output "${TRACE}" --time-limit "${limit}" --no-prompt \
        --launch -- "${APP}" -ProfileRequireSignposts -ProfileFlow "${stress}" || true
    stop_log "${limit}" "${TRACE}"
    append_manifest "${stress}" "traces/${stress}.trace" "logs/${stress}.log"
    echo "  ${stress} done"
done

if [[ "$(already_ran stress-launch-with-data)" != "yes" ]]; then
    echo ">> stress launch-with-data (10x)"
    for run in $(seq 1 10); do
        TRACE="${SESSION}/traces/stress-launch-with-data-run${run}.trace"
        LOG="${SESSION}/logs/stress-launch-with-data-run${run}.log"
        start_log "${LOG}"
        xcrun xctrace record --template "App Launch" --instrument os_log \
            --instrument "Allocations" --instrument "Activity Monitor" \
            --device "${DEVICE}" --output "${TRACE}" --time-limit "25s" --no-prompt \
            --launch -- "${APP}" -ProfileRequireSignposts -ProfileFlow "launchWithData" || true
        stop_log "35s" "${TRACE}"
        append_manifest "stress-launch-with-data" "traces/stress-launch-with-data-run${run}.trace" "logs/stress-launch-with-data-run${run}.log"
        echo "  launch ${run}/10 done"
    done
fi

echo ">> analyzing"
python3 "${ROOT}/Scripts/analyze-performance-traces.py" "${SESSION}"
echo "Done."
