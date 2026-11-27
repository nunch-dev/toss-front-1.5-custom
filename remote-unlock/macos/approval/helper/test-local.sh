#!/bin/bash
set -euo pipefail
umask 077
source_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(CDPATH= cd -- "$source_dir/../../../.." && pwd)"
output_dir="$project_root/private/macos-approval-20261120"
shared="$source_dir/../swift"
# Run build-local.sh first; this script never rebuilds or installs production.
test -x "$output_dir/approval-helper"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror \
    "$source_dir/tests/TrustedFilesTests.c" -o "$output_dir/trusted-files-tests"
"$output_dir/trusted-files-tests" "$output_dir"
sources=(
    "$shared/JSONSupport.swift" "$shared/Message.swift" "$shared/Protocol.swift"
    "$shared/RelayPolicy.swift" "$shared/RelayClient.swift" "$shared/TLSAnchor.swift"
    "$shared/LocalScreenContext.swift" "$shared/LocalInvocation.swift"
    "$source_dir/TrustedData.swift" "$source_dir/HelperPolicy.swift" "$source_dir/HelperPipe.swift"
    "$source_dir/HelperContextBinding.swift"
)
flags=(-O -swift-version 6 -warnings-as-errors -parse-as-library
    -module-cache-path "$output_dir/helper-module-cache"
    -import-objc-header "$source_dir/HelperBridge.h")
xcrun swiftc "${flags[@]}" "${sources[@]}" "$source_dir/tests/BoundaryTests.swift" \
    "$output_dir/TrustedFiles.o" "$output_dir/HelperScreenContext.o" \
    -framework Security -framework SystemConfiguration -framework CoreGraphics \
    -o "$output_dir/helper-boundary-tests"
"$output_dir/helper-boundary-tests" "$output_dir"
xcrun swiftc "${flags[@]}" "${sources[@]}" "$source_dir/tests/PipeConformanceMain.swift" \
    "$output_dir/TrustedFiles.o" "$output_dir/HelperScreenContext.o" \
    -framework Security -framework SystemConfiguration -framework CoreGraphics \
    -o "$output_dir/helper-pipe-conformance"
xcrun swiftc "${flags[@]}" "$shared/JSONSupport.swift" "$source_dir/tests/PipeTests.swift" \
    -o "$output_dir/helper-pipe-tests"
"$output_dir/helper-pipe-tests" "$output_dir"
xcrun swiftc "${flags[@]}" "${sources[@]}" "$source_dir/tests/ContextTests.swift" \
    "$output_dir/TrustedFiles.o" "$output_dir/HelperScreenContext.o" \
    -framework Security -framework SystemConfiguration -framework CoreGraphics \
    -o "$output_dir/helper-context-tests"
"$output_dir/helper-context-tests"
# Only the capture/file OS boundary is substituted in this TEST-only executable.
# Validation/equality still come from the genuine shared C implementation.
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror \
    -DPLFCaptureScreenContext=PLFSystemCaptureScreenContext \
    -c "$source_dir/../context/ScreenContext.c" -o "$output_dir/TestScreenContext.o"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror \
    -c "$source_dir/tests/TestRuntime.c" -o "$output_dir/TestRuntime.o"
xcrun swiftc "${flags[@]}" "${sources[@]}" "$source_dir/HelperMain.swift" \
    "$output_dir/TestRuntime.o" "$output_dir/TestScreenContext.o" \
    -framework Security -framework SystemConfiguration -framework CoreGraphics \
    -o "$output_dir/helper-runtime-conformance"
xcrun swiftc "${flags[@]}" "$source_dir/tests/RuntimeLauncher.swift" \
    -o "$output_dir/helper-runtime-launcher"
printf 'HELPER_TEST_RUNTIME_OK\n'
