#!/bin/bash
set -euo pipefail
umask 077
component="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project="$(CDPATH= cd -- "$component/../../.." && pwd)"
bash "$component/swift/build-local.sh"
tls_dir="$(mktemp -d "$project/private/macos-approval-20261120/tls.XXXXXX")"
trap 'rm -R -- "$tls_dir"' EXIT
bash "$component/prepare-tls.sh" "$tls_dir"
cd "$component/../.."
NODE_TLS_REJECT_UNAUTHORIZED=1 NODE_EXTRA_CA_CERTS="$tls_dir/ca.pem" NATIVE_TLS_DIR="$tls_dir" \
    bun test ./macos/approval/tests --timeout 15000 "$@"
