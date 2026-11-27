#!/bin/bash
set -euo pipefail
component="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project="$(CDPATH= cd -- "$component/../../.." && pwd)"
out="$project/private/macos-approval-20261120"
flags=(-fobjc-arc -fblocks -Wall -Wextra -Werror -mmacosx-version-min=13.0)
xcrun clang -std=c11 -Wall -Wextra -Werror "$component/tests/ProcessFixture.c" \
    -o "$out/process-fixture"
# Rename only the boundary definitions in these test objects. Shipping source
# and the shipping bundle always use the fixed, verified production helper.
xcrun clang "${flags[@]}" -DPLFSpawnHelper=PLFProductionSpawnHelper \
    -c "$component/native/ChildProcess.m" -o "$out/native-build/ChildProcess-test.o"
xcrun clang "${flags[@]}" -I "$out/native-build" \
    -DPLFOpenVerifiedHelper=PLFProductionOpenVerifiedHelper \
    -c "$component/native/CodeTrust.m" -o "$out/native-build/CodeTrust-test.o"
xcrun clang "${flags[@]}" "$component/native/Invocation.m" "$component/native/Runner.m" \
    "$component/tests/RunnerTest.m" "$out/native-build/ChildProcess-test.o" \
    "$out/native-build/CodeTrust-test.o" "$out/native-build/TrustedFiles.o" \
    "$out/native-build/ScreenContext.o" \
    -framework Foundation -framework Security -framework CoreGraphics -framework SystemConfiguration \
    -o "$out/runner-test"
"$out/runner-test" "$out/process-fixture"
