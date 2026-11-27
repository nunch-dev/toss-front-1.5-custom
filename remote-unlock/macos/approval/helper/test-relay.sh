#!/bin/bash
set -euo pipefail
umask 077
component="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
project="$(CDPATH= cd -- "$component/../../.." && pwd)"
# Run helper/build-local.sh, helper/test-local.sh and swift/build-local.sh first.
# Only fresh local fixtures are used; nothing is staged or installed.
tls_dir="$(mktemp -d "$project/private/macos-approval-20261120/helper-tls.XXXXXX")"
trap 'rm -R -- "$tls_dir"' EXIT
bash "$component/prepare-tls.sh" "$tls_dir"
cd "$component/../.."
NODE_TLS_REJECT_UNAUTHORIZED=1 NODE_EXTRA_CA_CERTS="$tls_dir/ca.pem" NATIVE_TLS_DIR="$tls_dir" \
    bun test ./macos/approval/tests/swift-relay.test.ts \
    ./macos/approval/helper/tests/helper-relay.test.ts \
    ./macos/approval/helper/tests/policy-cli.test.ts --timeout 15000 "$@"
