#!/bin/bash
set -euo pipefail
umask 077
source_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(CDPATH= cd -- "$source_dir/../../../.." && pwd)"
output_dir="$project_root/private/macos-approval-20261120"
shared="$source_dir/../swift"
mkdir -p "$output_dir/helper-module-cache"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror \
    -c "$source_dir/TrustedFiles.c" -o "$output_dir/TrustedFiles.o"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror \
    -c "$source_dir/HelperLaunch.c" -o "$output_dir/HelperLaunch.o"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror \
    -c "$source_dir/../context/ScreenContext.c" -o "$output_dir/HelperScreenContext.o"
xcrun swiftc -O -swift-version 6 -warnings-as-errors -parse-as-library \
    -module-cache-path "$output_dir/helper-module-cache" \
    -import-objc-header "$source_dir/HelperBridge.h" \
    "$shared/JSONSupport.swift" "$shared/Message.swift" "$shared/Protocol.swift" \
    "$shared/RelayPolicy.swift" "$shared/RelayClient.swift" "$shared/TLSAnchor.swift" \
    "$shared/LocalScreenContext.swift" "$shared/LocalInvocation.swift" \
    "$source_dir/TrustedData.swift" "$source_dir/HelperPolicy.swift" \
    "$source_dir/HelperContextBinding.swift" "$source_dir/HelperPipe.swift" "$source_dir/HelperMain.swift" \
    "$output_dir/TrustedFiles.o" "$output_dir/HelperLaunch.o" "$output_dir/HelperScreenContext.o" \
    -framework Security -framework SystemConfiguration -framework CoreGraphics \
    -o "$output_dir/approval-helper"
printf 'BUILD_OK %s\n' "$output_dir/approval-helper"
