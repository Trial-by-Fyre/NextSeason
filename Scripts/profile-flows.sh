#!/usr/bin/env bash
#
# profile-flows.sh
# NextSeason
#
# Records Profile-build Instruments traces on a connected iPhone for:
#   launch, searchEmpty, search, showDetails, viewWishlist, addToWishlist,
#   removeFromWishlist, launch-with-data (after seedWatchlist setup)
#
# Uses the Xcode "Profile" configuration (Release optimizations + get-task-allow)
# so xctrace can attach on device. Plain Release builds lack that entitlement
# and fail with "Permission to debug ... was denied".
#
# Usage:
#   ./Scripts/profile-flows.sh
#   DEVICE_UDID=00008140-001178E92EF3001C ./Scripts/profile-flows.sh
#   SKIP_BUILD=1 ./Scripts/profile-flows.sh
#
# Output traces are written to .instruments/*.trace (gitignored).
# Open in Instruments and inspect the Points of Interest track for flow intervals.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/performance-suite-common.sh
source "${ROOT}/Scripts/lib/performance-suite-common.sh"

CONFIGURATION="${CONFIGURATION:-Profile}"
OUTPUT_DIR="${ROOT}/.instruments"
LAUNCH_TIME_LIMIT="${LAUNCH_TIME_LIMIT:-20s}"
FLOW_TIME_LIMIT="${FLOW_TIME_LIMIT:-25s}"
SEED_TIME_LIMIT="${SEED_TIME_LIMIT:-45s}"

usage() {
    sed -n '2,20p' "$0" | tr -d '#'
}

profile_launch() {
    local device="$1"
    local app="$2"
    local output="$3"

    echo "Profiling launch -> ${output}"
    run_xctrace_record "${LAUNCH_TIME_LIMIT}" "${output}" \
        --template "App Launch" \
        --device "${device}" \
        --launch -- "${app}"
}

profile_flow() {
    local flow="$1"
    local device="$2"
    local app="$3"
    local output="${OUTPUT_DIR}/${flow}.trace"
    local time_limit="${4:-${FLOW_TIME_LIMIT}}"

    echo "Profiling ${flow} -> ${output}"
    run_xctrace_record "${time_limit}" "${output}" \
        --template "Time Profiler" \
        --device "${device}" \
        --launch -- "${app}" -ProfileRequireSignposts -ProfileFlow "${flow}"
}

seed_watchlist() {
    local device="$1"
    local app="$2"

    echo "Seeding watchlist (setup for launch-with-data)..."
    profile_flow "seedWatchlist" "${device}" "${app}" "${SEED_TIME_LIMIT}"
}

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    local device="${DEVICE_UDID:-$(connected_device_udid)}"
    if [[ -z "${device}" ]]; then
        echo "error: no connected iPhone found. Plug in a device or set DEVICE_UDID." >&2
        exit 1
    fi

    mkdir -p "${OUTPUT_DIR}"

    local app
    app="$(resolve_performance_app "${device}")"
    if [[ ! -d "${app}" ]]; then
        echo "error: app not found at ${app}. Build first or unset SKIP_BUILD." >&2
        exit 1
    fi

    local core_device
    core_device="$(core_device_uuid)"
    install_app_on_device "${app}" "${core_device}" "${device}"

    preflight_profiling_device

    echo "Device: ${device}"
    echo "App: ${app}"
    echo "Configuration: ${CONFIGURATION}"
    echo "Traces: ${OUTPUT_DIR}"
    echo

    # Clean cold launch before any watchlist seeding or mutations.
    profile_launch "${device}" "${app}" "${OUTPUT_DIR}/launch.trace"

    local flow
    for flow in searchEmpty search showDetails viewWishlist addToWishlist removeFromWishlist; do
        profile_flow "${flow}" "${device}" "${app}"
    done

    seed_watchlist "${device}" "${app}"
    profile_launch "${device}" "${app}" "${OUTPUT_DIR}/launch-with-data.trace"

    echo
    echo "Done. Traces are in ${OUTPUT_DIR}/"
    echo
    echo "Launch (App Launch template — no ProfileFlow signposts):"
    echo "  open \"${OUTPUT_DIR}/launch.trace\""
    echo "  open \"${OUTPUT_DIR}/launch-with-data.trace\""
    echo
    echo "Flows (Time Profiler + ProfileFlow — Points of Interest signposts):"
    echo "  open \"${OUTPUT_DIR}/search.trace\"          # flow.search, search.query"
    echo "  open \"${OUTPUT_DIR}/showDetails.trace\"     # flow.showDetails, showDetails.load"
    echo "  open \"${OUTPUT_DIR}/addToWishlist.trace\"   # flow.addToWishlist, watchlist.add"
    echo "  # Also: searchEmpty, viewWishlist, removeFromWishlist"
    echo
    echo "In Instruments: open a flow trace above → Points of Interest → filter table to"
    echo "  com.TrialByFyre.NextSeason (launch traces will not show flow.* signposts)."
    echo
    echo "For a markdown report, run: ./Scripts/profile-performance-suite.sh"
}

main "$@"
