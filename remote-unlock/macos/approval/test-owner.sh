#!/bin/bash
set -euo pipefail
component="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project="$(CDPATH= cd -- "$component/../../.." && pwd)"
out="$project/private/macos-approval-20261120"
mkdir -p "$out/native-build"
xcrun clang -std=c11 -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    -DPLFCaptureScreenContext=PLFProductionCaptureScreenContext \
    -c "$component/context/ScreenContext.c" -o "$out/native-build/Context-owner-test.o"
xcrun clang -std=c11 -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    -c "$component/tests/ControlledContext.c" -o "$out/native-build/ControlledContext-owner-test.o"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    "$component/native/Invocation.m" "$component/native/Records.m" \
    "$component/native/Mechanism.m" "$component/native/Plugin.m" \
    "$component/tests/ControlledRunner.m" "$component/tests/OwnerTest.m" \
    "$out/native-build/Context-owner-test.o" "$out/native-build/ControlledContext-owner-test.o" \
    -framework Foundation -framework Security -framework CoreGraphics -framework SystemConfiguration \
    -o "$out/owner-test"
"$out/owner-test"
