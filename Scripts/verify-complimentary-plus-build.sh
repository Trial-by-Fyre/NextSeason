#!/bin/sh
# Runs on every app build. A scheme/command-line override must not enable the
# permanent grant in a normal production (or future TestFlight) configuration.
set -eu

# Check both sources of Swift -D flags, including -DNAME and -D NAME forms.
flags="${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-} ${OTHER_SWIFT_FLAGS:-}"
has_flag() {
    printf '%s\n' "$flags" | /usr/bin/tr -d "\"'" | /usr/bin/grep -Eq "(^|[[:space:]])(-D[[:space:]]*)?$1([[:space:]]|$)"
}

if [ "${CONFIGURATION:-}" = "BetaComplimentary" ]; then
    if ! has_flag COMPLIMENTARY_PLUS_BETA_GRANT || ! has_flag NEXTSEASON_BETA_COMPLIMENTARY_CONFIGURATION; then
        printf '%s\n' "error: BetaComplimentary requires both COMPLIMENTARY_PLUS_BETA_GRANT and NEXTSEASON_BETA_COMPLIMENTARY_CONFIGURATION. Restore the dedicated beta flags before archiving." >&2
        exit 1
    fi
elif has_flag COMPLIMENTARY_PLUS_BETA_GRANT || has_flag NEXTSEASON_BETA_COMPLIMENTARY_CONFIGURATION; then
    printf '%s\n' "error: Complimentary Plus granting is allowed only in BetaComplimentary. Use the final beta scheme or remove the grant flags." >&2
    exit 1
fi
