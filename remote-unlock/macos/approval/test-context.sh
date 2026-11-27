#!/bin/bash
set -euo pipefail
component="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project="$(CDPATH= cd -- "$component/../../.." && pwd)"
out="$project/private/macos-approval-20261120"
mkdir -p "$out"
xcrun clang -std=c11 -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    "$component/context/ScreenContext.c" "$component/tests/ScreenContextTest.c" \
    -framework Security -framework CoreFoundation -framework CoreGraphics \
    -framework SystemConfiguration -o "$out/context-test"
"$out/context-test"
