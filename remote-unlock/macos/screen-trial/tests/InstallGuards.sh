#!/bin/bash
set -euo pipefail
[[ "$(/usr/bin/id -u)" -ne 0 ]] || exit 2
component="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

check() {
    local expected="$1" status=0 output
    shift
    output="$(/bin/bash "$component/$@" 2>&1)" || status=$?
    if [[ "$status" -ne "$expected" || -n "$output" ]]; then
        printf 'INSTALL_GUARD_FAIL expected=%s actual=%s output=%s\n' \
            "$expected" "$status" "$output" >&2
        exit 1
    fi
    printf 'INSTALL_GUARD_OK %s\n' "$*"
}

check 1 install-probe.sh
check 1 install-probe.sh --signed-approval
check 2 install-probe.sh --unknown
check 1 install-probe.sh --signed-approval extra
check 1 cleanup-probe.sh
check 1 cleanup-probe.sh extra
printf '%s\n' 'INSTALL_GUARDS_OK count=6'
