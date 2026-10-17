#!/usr/bin/env bash
#
# Shared device unified-log capture helpers for NextSeason scripts.
# Source this file; do not execute directly.
#
# macOS `log stream` does not support --device-udid on current releases.
# When streaming is unavailable, callers collect a recent window via `log collect`.

DEVICE_LOG_CMD="${DEVICE_LOG_CMD:-/usr/bin/log}"
_DEVICE_LOG_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

device_log_stream_supports_device() {
    # Captured first: under callers' pipefail, `grep -q` exiting early could make
    # the pipeline fail even when the option is listed.
    local help_text
    help_text="$("${DEVICE_LOG_CMD}" help stream 2>&1)" || true
    [[ "${help_text}" == *--device* ]]
}

device_log_collect() {
    local udid="$1"
    local output_path="$2"
    local window="$3"
    local predicate="$4"

    local -a args=(
        collect
        --device-udid "${udid}"
        --last "${window}"
        --output "${output_path}"
        --predicate "${predicate}"
    )

    if "${DEVICE_LOG_CMD}" "${args[@]}"; then
        return 0
    fi

    if [[ "${USE_SUDO:-0}" == "1" ]] && sudo "${DEVICE_LOG_CMD}" "${args[@]}"; then
        return 0
    fi

    return 1
}

device_log_capture_to_file() {
    local udid="$1"
    local output_file="$2"
    local window="$3"
    local predicate="$4"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local archive="${tmp_dir}/device-capture.logarchive"

    if device_log_collect "${udid}" "${archive}" "${window}" "${predicate}"; then
        "${DEVICE_LOG_CMD}" show "${archive}" --style compact --info >> "${output_file}" || {
            echo "warning: could not read device log archive for ${output_file}" >&2
        }
    else
        echo "warning: console capture failed for ${output_file}; evidence remains unavailable" >&2
    fi

    rm -rf "${tmp_dir}"
}

# State for one active capture (trace export, native stream, or native collect).
# Begin and end keep it in these globals, so
# call them directly in the script's own shell, never inside `$(...)`: a command
# substitution runs in a subshell and its assignments are lost.
_DEVICE_LOG_CAPTURE_MODE=""  # "", "trace", "stream", or "collect"
_DEVICE_LOG_CAPTURE_UDID=""
_DEVICE_LOG_CAPTURE_FILE=""
_DEVICE_LOG_CAPTURE_PREDICATE=""
_DEVICE_LOG_CAPTURE_PID=""

_device_log_capture_clear() {
    _DEVICE_LOG_CAPTURE_MODE=""
    _DEVICE_LOG_CAPTURE_UDID=""
    _DEVICE_LOG_CAPTURE_FILE=""
    _DEVICE_LOG_CAPTURE_PREDICATE=""
    _DEVICE_LOG_CAPTURE_PID=""
}

_device_log_capture_stop_stream() {
    if [[ -n "${_DEVICE_LOG_CAPTURE_PID}" ]]; then
        kill "${_DEVICE_LOG_CAPTURE_PID}" 2>/dev/null || true
        # Reaps the process even if it had already exited.
        wait "${_DEVICE_LOG_CAPTURE_PID}" 2>/dev/null || true
    fi
}

# Begin capture for a bounded Instruments/trace run. Truncates the output file.
device_log_capture_begin() {
    local udid="$1"
    local output_file="$2"
    local predicate="$3"

    # A capture that was never ended must not leave its stream running.
    device_log_capture_abort

    _DEVICE_LOG_CAPTURE_UDID="${udid}"
    _DEVICE_LOG_CAPTURE_FILE="${output_file}"
    _DEVICE_LOG_CAPTURE_PREDICATE="${predicate}"

    : > "${output_file}"

    if [[ "${DEVICE_LOG_CAPTURE_BACKEND:-native}" == "trace" ]]; then
        _DEVICE_LOG_CAPTURE_MODE="trace"
    elif device_log_stream_supports_device; then
        "${DEVICE_LOG_CMD}" stream \
            --device-udid "${udid}" \
            --style compact \
            --predicate "${predicate}" \
            >> "${output_file}" 2>&1 &
        _DEVICE_LOG_CAPTURE_PID=$!
        _DEVICE_LOG_CAPTURE_MODE="stream"
    else
        _DEVICE_LOG_CAPTURE_MODE="collect"
    fi
}

# End capture: export the supplied trace, stop the stream, or collect the recent
# window. In trace mode pass the saved trace as argument 2. Native collection
# needs a window at least as long as the trace. No active capture is a no-op.
device_log_capture_end() {
    local window="${1:-2m}"
    local trace="${2:-}"

    case "${_DEVICE_LOG_CAPTURE_MODE}" in
        trace)
            if [[ -n "${trace}" ]]; then
                "${PROFILE_PYTHON:-/usr/bin/python3}" "${_DEVICE_LOG_HELPER_DIR}/../export-performance-evidence.py" \
                    "${trace}" --log "${_DEVICE_LOG_CAPTURE_FILE}" || true
            else
                echo "warning: no trace supplied for console capture; evidence remains unavailable" >&2
            fi
            ;;
        stream)
            _device_log_capture_stop_stream
            ;;
        collect)
            device_log_capture_to_file \
                "${_DEVICE_LOG_CAPTURE_UDID}" \
                "${_DEVICE_LOG_CAPTURE_FILE}" \
                "${window}" \
                "${_DEVICE_LOG_CAPTURE_PREDICATE}"
            ;;
    esac
    _device_log_capture_clear
}

# Cleanup for a run that did not finish: stops any stream without collecting.
# The interrupted run is never added to the manifest, so its log is not needed.
# Does nothing when no capture is active.
device_log_capture_abort() {
    if [[ "${_DEVICE_LOG_CAPTURE_MODE}" == "stream" ]]; then
        _device_log_capture_stop_stream
    fi
    _device_log_capture_clear
}

# Stops an active capture when the script exits early: on a failure under
# `set -e`, or on Ctrl-C / SIGTERM. Background jobs in a non-interactive script
# ignore SIGINT, so without this a `log stream` process would outlive the script.
# INT/TERM exit through the EXIT trap, so cleanup runs once.
device_log_capture_install_cleanup_trap() {
    trap 'device_log_capture_abort' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
}
