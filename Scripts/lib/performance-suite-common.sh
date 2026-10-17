# Shared helpers for on-device Instruments performance scripts.
# Expects ROOT to be set by the caller before sourcing.

SCHEME="${SCHEME:-NextSeason}"
# Profile = Release optimizations + get-task-allow for on-device Instruments attach.
CONFIGURATION="${CONFIGURATION:-Profile}"

connected_device_udid() {
    xcrun xctrace list devices 2>/dev/null | awk '
        /^== Devices ==$/ { in_devices=1; next }
        /^==/ { in_devices=0 }
        in_devices && /iPhone/ {
            if (match($0, /\(([0-9A-Fa-f-]+)\)[[:space:]]*$/)) {
                print substr($0, RSTART + 1, RLENGTH - 2)
                exit
            }
        }
    '
}

resolve_app_path() {
    local device="$1"
    xcodebuild \
        -project "${ROOT}/NextSeason.xcodeproj" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -destination "id=${device}" \
        -showBuildSettings 2>/dev/null \
        | awk '/TARGET_BUILD_DIR =/ { dir=$3 } /FULL_PRODUCT_NAME =/ { name=$3 } END { print dir "/" name }'
}

build_app() {
    local device="$1"
    echo "Building ${SCHEME} (${CONFIGURATION}) for ${device}..."
    xcodebuild \
        -project "${ROOT}/NextSeason.xcodeproj" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -destination "id=${device}" \
        build
}

core_device_uuid() {
    xcrun devicectl list devices 2>/dev/null | awk '
        /connected/ {
            for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F-]{36}$/) { print $i; exit }
        }
    '
}

install_app_on_device() {
    local app="$1"
    local device_core="${2:-}"
    local device_udid="${3:-${DEVICE:-}}"
    echo "Installing app on device (required for Instruments attach permissions)..."
    if [[ -n "${device_core}" ]]; then
        xcrun devicectl device install app --device "${device_core}" "${app}"
    else
        xcrun devicectl device install app --device "${device_udid}" "${app}" 2>/dev/null \
            || xcrun devicectl device install app "${app}"
    fi
}

resolve_performance_app() {
    local device="$1"
    local app=""

    if [[ -n "${APP_PATH:-}" ]]; then
        echo "${APP_PATH}"
        return
    fi

    app="$(resolve_app_path "${device}")"
    if [[ -d "${app}" ]]; then
        echo "${app}"
        return
    fi

    if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
        build_app "${device}"
        app="$(resolve_app_path "${device}")"
    fi

    echo "${app}"
}

preflight_profiling_device() {
    echo "Preflight: keep the iPhone unlocked with the screen on for the entire run."
    echo "Preflight: a locked screen often makes xctrace hang past --time-limit."
}

# Converts xctrace --time-limit values (20s, 2m, …) to whole seconds.
parse_time_limit_seconds() {
    local limit="$1"
    if [[ "${limit}" =~ ^([0-9]+)(ms|s|m|h)$ ]]; then
        local value="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        case "${unit}" in
            ms) echo 0 ;;
            s) echo "${value}" ;;
            m) echo $((value * 60)) ;;
            h) echo $((value * 3600)) ;;
        esac
    elif [[ "${limit}" =~ ^([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo 30
    fi
}

remove_trace_output() {
    local output="$1"
    if [[ -e "${output}" ]]; then
        rm -rf "${output}"
    fi
}

# xctrace occasionally ignores --time-limit when launch/attach stalls; enforce a watchdog.
run_xctrace_record() {
    local time_limit="$1"
    local output="$2"
    shift 2

    remove_trace_output "${output}"

    local limit_seconds watchdog
    limit_seconds="$(parse_time_limit_seconds "${time_limit}")"
    watchdog=$((limit_seconds + 45))

    xcrun xctrace record \
        --output "${output}" \
        --time-limit "${time_limit}" \
        --no-prompt \
        "$@" &
    local pid=$!
    local previous_int previous_term
    previous_int="$(trap -p INT)"
    previous_term="$(trap -p TERM)"
    # The asynchronous recorder can ignore Ctrl-C. Stop it explicitly before
    # exiting through the caller's EXIT trap (which cleans up log capture).
    trap 'kill -9 "${pid}" 2>/dev/null || true; wait "${pid}" 2>/dev/null || true; exit 130' INT
    trap 'kill -9 "${pid}" 2>/dev/null || true; wait "${pid}" 2>/dev/null || true; exit 143' TERM
    local elapsed=0

    while kill -0 "${pid}" 2>/dev/null && ((elapsed < watchdog)); do
        sleep 2
        elapsed=$((elapsed + 2))
    done

    trap - INT TERM
    [[ -z "${previous_int}" ]] || eval "${previous_int}"
    [[ -z "${previous_term}" ]] || eval "${previous_term}"

    if kill -0 "${pid}" 2>/dev/null; then
        echo "error: xctrace hung after ${watchdog}s (requested limit ${time_limit})." >&2
        echo "error: unlock the iPhone, disable auto-lock briefly, and retry." >&2
        kill -9 "${pid}" 2>/dev/null || true
        wait "${pid}" 2>/dev/null || true
        return 124
    fi

    wait "${pid}"
}
