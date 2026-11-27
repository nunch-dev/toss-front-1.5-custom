#!/bin/bash
set -euo pipefail
component="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project="$(CDPATH= cd -- "$component/../../.." && pwd)"
out="$project/private/macos-approval-20261120"
mkdir -p "$out/native-build"
xcrun clang -std=c11 -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    -DPLFCaptureScreenContext=PLFProductionCaptureScreenContext \
    -c "$component/context/ScreenContext.c" -o "$out/native-build/Context-records-test.o"
xcrun clang -std=c11 -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    -c "$component/tests/ControlledContext.c" -o "$out/native-build/ControlledContext-records-test.o"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    "$component/native/Invocation.m" "$component/native/Records.m" \
    "$component/tests/RecordsTest.m" "$out/native-build/Context-records-test.o" \
    "$out/native-build/ControlledContext-records-test.o" \
    -framework Foundation -framework Security -framework CoreGraphics -framework SystemConfiguration \
    -o "$out/records-test"
"$out/records-test"
