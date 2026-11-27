#!/bin/bash
set -euo pipefail
umask 077
source_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(CDPATH= cd -- "$source_dir/../../../.." && pwd)"
output_dir="$project_root/private/macos-approval-20261120"
mkdir -p "$output_dir/module-cache"
swiftc -swift-version 6 -warnings-as-errors \
  -module-cache-path "$output_dir/module-cache" \
  -o "$output_dir/protocol-conformance" \
  "$source_dir/JSONSupport.swift" \
  "$source_dir/Message.swift" \
  "$source_dir/Protocol.swift" \
  "$source_dir/ConformanceMain.swift"
printf '%s\n' "$output_dir/protocol-conformance"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror \
  -c "$source_dir/../context/ScreenContext.c" -o "$output_dir/RequestorScreenContext.o"
swiftc -swift-version 6 -warnings-as-errors \
  -module-cache-path "$output_dir/module-cache" \
  -import-objc-header "$source_dir/../context/ScreenContext.h" \
  -o "$output_dir/requestor-conformance" \
  "$source_dir/JSONSupport.swift" \
  "$source_dir/Message.swift" \
  "$source_dir/Protocol.swift" \
  "$source_dir/RelayPolicy.swift" \
  "$source_dir/LocalScreenContext.swift" \
  "$source_dir/LocalInvocation.swift" \
  "$source_dir/TLSAnchor.swift" \
  "$source_dir/RelayClient.swift" \
  "$source_dir/RequestorConformanceMain.swift" \
  "$output_dir/RequestorScreenContext.o" \
  -framework Security -framework SystemConfiguration -framework CoreGraphics
printf '%s\n' "$output_dir/requestor-conformance"
