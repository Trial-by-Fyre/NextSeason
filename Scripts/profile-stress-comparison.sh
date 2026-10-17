#!/usr/bin/env bash
# Paired empty-search stress capture: same fresh build and 20 searches in each mode.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT}/Scripts/lib/performance-suite-common.sh"
DEVICE="${DEVICE_UDID:?Set DEVICE_UDID to the physical iPhone identifier}"
PROFILE_PYTHON="${PROFILE_PYTHON:-/usr/bin/python3}"
TIME_LIMIT="${TIME_LIMIT:-60s}"
SESSION="${ROOT}/.instruments/stress-comparison-$(date +%Y%m%d-%H%M%S)"

xcrun --find xctrace >/dev/null
"${PROFILE_PYTHON}" --version
preflight_profiling_device
# Rebuild by default: the cached Profile app may predate the driver repair.
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    build_app "${DEVICE}"
fi
APP="${APP_PATH:-$(resolve_app_path "${DEVICE}")}"
[[ -d "${APP}" ]] || { echo "error: Profile app not found: ${APP}" >&2; exit 1; }
install_app_on_device "${APP}" "${DEVICE}"
mkdir -p "${SESSION}"
"${PROFILE_PYTHON}" - "${SESSION}" <<'PY'
import json,sys,uuid
from pathlib import Path
runs=[{"mode":m,"run_id":str(uuid.uuid4()),"trace":m+".trace","outcomes":m+".jsonl"}
      for m in ("time-profiler","instrumented")]
(Path(sys.argv[1])/"comparison-manifest.json").write_text(json.dumps({"runs":runs},indent=2))
PY
echo "Comparison session: ${SESSION}"
for MODE in time-profiler instrumented; do
    RUN_ID="$("${PROFILE_PYTHON}" - "${SESSION}" "${MODE}" <<'PY'
import json,sys
from pathlib import Path
data=json.loads((Path(sys.argv[1])/"comparison-manifest.json").read_text())
print(next(r["run_id"] for r in data["runs"] if r["mode"]==sys.argv[2]))
PY
    )"
    EXTRA=()
    if [[ "${MODE}" == "instrumented" ]]; then
        EXTRA=(--instrument "Allocations" --instrument "Leaks" --instrument "Activity Monitor")
    fi
    echo ">> ${MODE}: ${TIME_LIMIT}, 20 searches"
    # Bash 3.2's nounset rejects an empty array expansion; branch explicitly.
    if [[ "${MODE}" == "instrumented" ]]; then
        run_xctrace_record "${TIME_LIMIT}" "${SESSION}/${MODE}.trace" \
            --template "Time Profiler" "${EXTRA[@]}" --device "${DEVICE}" \
            --launch -- "${APP}" -ProfileRequireSignposts -ProfileFlow stressSearchEmpty -ProfileRunID "${RUN_ID}"
    else
        run_xctrace_record "${TIME_LIMIT}" "${SESSION}/${MODE}.trace" \
            --template "Time Profiler" --device "${DEVICE}" \
            --launch -- "${APP}" -ProfileRequireSignposts -ProfileFlow stressSearchEmpty -ProfileRunID "${RUN_ID}"
    fi
    xcrun devicectl device copy from --device "${DEVICE}" \
        --domain-type appDataContainer --domain-identifier com.TrialByFyre.NextSeason \
        --source Documents/profile-flow-timing.jsonl --destination "${SESSION}/${MODE}.jsonl"
    if ! "${PROFILE_PYTHON}" "${ROOT}/Scripts/analyze-stress-comparison.py" \
        "${SESSION}/${MODE}.jsonl" --check-outcomes "${RUN_ID}"; then
        echo "error: driver did not complete; stopping before another capture. Results: ${SESSION}" >&2
        "${PROFILE_PYTHON}" "${ROOT}/Scripts/analyze-stress-comparison.py" "${SESSION}" || true
        exit 1
    fi
done
"${PROFILE_PYTHON}" "${ROOT}/Scripts/analyze-stress-comparison.py" "${SESSION}"
