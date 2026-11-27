#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$source_dir/../../.." && pwd)"
out="$root/private/macos-auth-probe-20261120"
bundle="$out/PlfAuthProbe.bundle"
mkdir -p "$bundle/Contents/MacOS"
flags=(-std=c11 -Wall -Wextra -Werror -mmacosx-version-min=13.0)
xcrun clang "${flags[@]}" -bundle "$source_dir/Probe.c" \
    -framework Security -framework CoreFoundation -framework CoreGraphics \
    -framework SystemConfiguration \
    -o "$bundle/Contents/MacOS/PlfAuthProbe"
cp "$source_dir/Info.plist" "$bundle/Contents/Info.plist"
xcrun clang "${flags[@]}" "$source_dir/SelfTest.c" \
    -framework Security -o "$out/probe-self-test"
xcrun clang "${flags[@]}" "$source_dir/RunProbe.c" \
    -framework Security -framework CoreFoundation -o "$out/run-probe"
plutil -lint "$source_dir/right.plist" "$bundle/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$bundle"
codesign --verify --strict --verbose=2 "$bundle"
"$out/probe-self-test" "$bundle/Contents/MacOS/PlfAuthProbe"
printf '%s\n' MAC_AUTH_PROBE_BUILD_OK
