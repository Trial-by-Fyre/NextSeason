#!/usr/bin/env bash
#
# profile-performance-suite.sh
# NextSeason
#
# Full on-device Instruments performance battery:
#   - 5 runs per core flow (averaged in analyze-performance-traces.py)
#   - Memory / leaks / CPU / hangs / network / console capture
#   - Stress loops
#
# Usage:
#   ./Scripts/profile-performance-suite.sh
#   DEVICE_UDID=00008140-001178E92EF3001C RUNS=5 ./Scripts/profile-performance-suite.sh
#   SKIP_BUILD=1 ./Scripts/profile-performance-suite.sh
#
# Output: .instruments/<timestamp>/ (gitignored)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/device-log-capture.sh
source "${ROOT}/Scripts/lib/device-log-capture.sh"
# shellcheck source=lib/performance-suite-common.sh
source "${ROOT}/Scripts/lib/performance-suite-common.sh"
device_log_capture_install_cleanup_trap
DEVICE="${DEVICE_UDID:-}"
RUNS="${RUNS:-5}"
SUBSYSTEM="com.TrialByFyre.NextSeason"
DEVICE_LOG_CAPTURE_BACKEND="${DEVICE_LOG_CAPTURE_BACKEND:-trace}"

start_log_stream() {
    local device="$1"
    local log_file="$2"
    local predicate="subsystem == \"${SUBSYSTEM}\" OR processImagePath CONTAINS \"NextSeason\""
    device_log_capture_begin "${device}" "${log_file}" "${predicate}"
}

stop_log_stream() {
    local window="${1:-2m}"
    device_log_capture_end "${window}" "${2:-}"
}

record_trace() {
    local template="$1"
    local device="$2"
    local app="$3"
    local output="$4"
    local time_limit="$5"
    shift 5
    local -a extra_instruments=()
    local -a launch_args=()
    local parsing_launch=0

    for arg in "$@"; do
        if [[ "${arg}" == "--" ]]; then
            parsing_launch=1
            continue
        fi
        if [[ "${parsing_launch}" -eq 1 ]]; then
            launch_args+=("${arg}")
        else
            extra_instruments+=("${arg}")
        fi
    done

    local cmd=(
        --template "${template}"
        --instrument "os_log"
        --device "${device}"
    )
    if ((${#extra_instruments[@]} > 0)); then
        for inst in "${extra_instruments[@]}"; do
            [[ -n "${inst}" ]] && cmd+=(--instrument "${inst}")
        done
    fi
    cmd+=(--launch -- "${app}")
    if ((${#launch_args[@]})); then
        cmd+=("${launch_args[@]}")
    fi
    run_xctrace_record "${time_limit}" "${output}" "${cmd[@]}"
}

record_launch() {
    local device="$1"
    local app="$2"
    local output="$3"
    local profile_flow="${4:-}"

    local cmd=(
        --template "App Launch"
        --instrument "os_log"
        --instrument "Allocations"
        --instrument "Activity Monitor"
        --device "${device}"
        --launch -- "${app}"
    )
    if [[ -n "${profile_flow}" ]]; then
        cmd+=(-ProfileRequireSignposts -ProfileFlow "${profile_flow}")
    fi
    run_xctrace_record "25s" "${output}" "${cmd[@]}"
}

record_flow() {
    local flow="$1"
    local device="$2"
    local app="$3"
    local output="$4"
    local time_limit="${5:-30s}"

    record_trace "Time Profiler" "${device}" "${app}" "${output}" "${time_limit}" \
        "Allocations" "Leaks" "Activity Monitor" -- \
        -ProfileRequireSignposts -ProfileFlow "${flow}"
}

record_network() {
    local flow="$1"
    local device="$2"
    local app="$3"
    local output="$4"
    local har_output="$5"
    local time_limit="${6:-30s}"

    record_trace "Time Profiler" "${device}" "${app}" "${output}" "${time_limit}" "HTTP Traffic" -- \
        -ProfileFlow "${flow}"
    if [[ -e "${output}" ]]; then
        "${PROFILE_PYTHON:-/usr/bin/python3}" "${ROOT}/Scripts/export-performance-evidence.py" "${output}" --har "${har_output}" || true
    fi
}

append_manifest() {
    local manifest="$1"
    local flow="$2"
    local trace_rel="$3"
    local log_rel="${4:-}"
    local har_rel="${5:-}"

    python3 - <<PY
import json
from pathlib import Path
p = Path("${manifest}")
data = json.loads(p.read_text()) if p.exists() else {"runs": []}
entry = {"flow": "${flow}", "trace": "${trace_rel}"}
if "${log_rel}":
    entry["log"] = "${log_rel}"
if "${har_rel}":
    entry["har"] = "${har_rel}"
data["runs"] = [r for r in data["runs"] if r.get("trace") != entry["trace"]]
data["runs"].append(entry)
p.write_text(json.dumps(data, indent=2))
PY
}

# A trace directory alone may be an interrupted recording. Only skip a run
# after capture finished and its exact trace was added to the manifest.
run_completed() {
    python3 - "${MANIFEST}" "$1" "${SESSION}" <<'PY'
import json
import sys
from pathlib import Path
manifest, trace, session = sys.argv[1:]
complete = any(r.get("trace") == trace for r in json.loads(Path(manifest).read_text())["runs"])
sys.exit(0 if complete and (Path(session) / trace).exists() else 1)
PY
}

main() {
    DEVICE="${DEVICE:-$(connected_device_udid)}"
    if [[ -z "${DEVICE}" ]]; then
        echo "error: no connected iPhone. Set DEVICE_UDID or plug in a device." >&2
        exit 1
    fi

    if [[ -n "${SESSION_DIR:-}" ]]; then
        SESSION="$(cd "${SESSION_DIR}" && pwd)"
        [[ -f "${SESSION}/manifest.json" ]] || { echo "error: session manifest missing" >&2; exit 1; }
        RUNS="$(python3 - "${SESSION}/manifest.json" <<'PY'
import json
import sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text()).get("runs_per_flow", 5))
PY
        )"
    else
        STAMP="$(date +%Y%m%d-%H%M%S)"
        SESSION="${ROOT}/.instruments/${STAMP}"
    fi
    TRACE_DIR="${SESSION}/traces"
    LOG_DIR="${SESSION}/logs"
    HAR_DIR="${SESSION}/har"
    mkdir -p "${TRACE_DIR}" "${LOG_DIR}" "${HAR_DIR}"

    APP="$(resolve_performance_app "${DEVICE}")"
    if [[ ! -d "${APP}" ]]; then
        echo "error: app not found at ${APP}" >&2
        exit 1
    fi

    # Install on the same device selected for recording; a separate lookup can pick a simulator.
    install_app_on_device "${APP}" "${DEVICE}"

    MANIFEST="${SESSION}/manifest.json"
    # runs_per_flow lets the analyzer detect missing runs.
    if [[ -z "${SESSION_DIR:-}" ]]; then
        echo "{\"runs\": [], \"runs_per_flow\": ${RUNS}}" > "${MANIFEST}"
    fi

    echo "=== NextSeason performance suite ==="
    echo "Device: ${DEVICE}"
    echo "App: ${APP}"
    echo "Session: ${SESSION}"
    echo "Runs per flow: ${RUNS}"
    echo

    # --- Seed watchlist once for launch-with-data ---
    if ! run_completed "traces/seedWatchlist.trace"; then
        echo ">> Setup: seed watchlist"
        LOG="${LOG_DIR}/seedWatchlist.log"
        TRACE="${TRACE_DIR}/seedWatchlist.trace"
        start_log_stream "${DEVICE}" "${LOG}"
        record_flow "seedWatchlist" "${DEVICE}" "${APP}" "${TRACE}" "60s"
        stop_log_stream "90s" "${TRACE}"
        append_manifest "${MANIFEST}" "seedWatchlist" "traces/seedWatchlist.trace" "logs/seedWatchlist.log"
    fi

    CORE_FLOWS=(
        "launch:cold"
        "launch-with-data:launchWithData"
        "search:search"
        "searchEmpty:searchEmpty"
        "showDetails:showDetails"
        "viewWishlist:viewWishlist"
        "addToWishlist:addToWishlist"
        "removeFromWishlist:removeFromWishlist"
    )

    for entry in "${CORE_FLOWS[@]}"; do
        flow_key="${entry%%:*}"
        profile_flow="${entry##*:}"
        echo ">> Flow: ${flow_key} (${RUNS} runs)"

        for run in $(seq 1 "${RUNS}"); do
            if run_completed "traces/${flow_key}-run${run}.trace"; then
                echo "   skip ${flow_key}-run${run} (complete)"
                continue
            fi
            TRACE="${TRACE_DIR}/${flow_key}-run${run}.trace"
            LOG="${LOG_DIR}/${flow_key}-run${run}.log"
            start_log_stream "${DEVICE}" "${LOG}"

            if [[ "${flow_key}" == "launch" || "${flow_key}" == "launch-with-data" ]]; then
                pf=""
                [[ "${flow_key}" == "launch-with-data" ]] && pf="${profile_flow}"
                record_launch "${DEVICE}" "${APP}" "${TRACE}" "${pf}"
                stop_log_stream "35s" "${TRACE}"
            else
                record_flow "${profile_flow}" "${DEVICE}" "${APP}" "${TRACE}" "35s"
                stop_log_stream "45s" "${TRACE}"
            fi

            append_manifest "${MANIFEST}" "${flow_key}" "traces/${flow_key}-run${run}.trace" "logs/${flow_key}-run${run}.log"
            echo "   run ${run}/${RUNS} done"
        done
    done

    # --- Network captures (one run each for network-heavy flows) ---
    if [[ "${SKIP_NETWORK:-0}" == "1" ]]; then
        echo ">> Skipping Network captures (SKIP_NETWORK=1); network evidence remains incomplete."
    else
        echo ">> Network captures"
        for net_flow in search showDetails addToWishlist; do
            if run_completed "traces/network-${net_flow}.trace"; then
                echo "   skip network-${net_flow} (complete)"
                continue
            fi
            TRACE="${TRACE_DIR}/network-${net_flow}.trace"
            HAR="${HAR_DIR}/${net_flow}.har"
            LOG="${LOG_DIR}/network-${net_flow}.log"
            start_log_stream "${DEVICE}" "${LOG}"
            record_network "${net_flow}" "${DEVICE}" "${APP}" "${TRACE}" "${HAR}" "35s"
            stop_log_stream "45s" "${TRACE}"
            append_manifest "${MANIFEST}" "network-${net_flow}" "traces/network-${net_flow}.trace" "logs/network-${net_flow}.log" "har/${net_flow}.har"
        done
    fi

    # --- Stress loops ---
    echo ">> Stress loops"
    for stress in stressSearchDetailsBack stressAddRemoveWishlist stressSearchEmpty; do
        case "${stress}" in
            stressSearchDetailsBack) limit=200s ;;
            stressAddRemoveWishlist) limit=120s ;;
            stressSearchEmpty) limit=140s ;;
            *) limit=120s ;;
        esac
        if run_completed "traces/${stress}.trace"; then
            echo "   skip ${stress} (complete)"
            continue
        fi
        TRACE="${TRACE_DIR}/${stress}.trace"
        LOG="${LOG_DIR}/${stress}.log"
        start_log_stream "${DEVICE}" "${LOG}"
        record_flow "${stress}" "${DEVICE}" "${APP}" "${TRACE}" "${limit}"
        stop_log_stream "${limit}" "${TRACE}"
        append_manifest "${MANIFEST}" "${stress}" "traces/${stress}.trace" "logs/${stress}.log"
    done

    # --- Launch with existing data: 10 cold launches ---
    echo ">> Stress: launch-with-data (10 launches)"
    for run in $(seq 1 10); do
        if run_completed "traces/stress-launch-with-data-run${run}.trace"; then
            echo "   skip stress-launch-with-data-run${run} (complete)"
            continue
        fi
        TRACE="${TRACE_DIR}/stress-launch-with-data-run${run}.trace"
        LOG="${LOG_DIR}/stress-launch-with-data-run${run}.log"
        start_log_stream "${DEVICE}" "${LOG}"
        record_launch "${DEVICE}" "${APP}" "${TRACE}" "launchWithData"
        stop_log_stream "35s" "${TRACE}"
        append_manifest "${MANIFEST}" "stress-launch-with-data" "traces/stress-launch-with-data-run${run}.trace" "logs/stress-launch-with-data-run${run}.log"
        echo "   launch ${run}/10 done"
    done

    echo
    echo ">> Analyzing traces..."
    python3 "${ROOT}/Scripts/analyze-performance-traces.py" "${SESSION}"

    echo
    echo "Done."
    echo "  Report: ${SESSION}/report.md"
    echo "  JSON:   ${SESSION}/report.json"
    echo "  Traces: ${TRACE_DIR}/"
}

main "$@"
