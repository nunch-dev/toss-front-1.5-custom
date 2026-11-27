#!/bin/bash
set -euo pipefail
umask 077
component="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project="$(CDPATH= cd -- "$component/../../.." && pwd)"
out="$project/private/macos-approval-20261120"
bundle="$out/PlfRemoteApproval.bundle"
bash "$component/helper/build-local.sh"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$out/native-build"
cp "$out/approval-helper" "$bundle/Contents/MacOS/approval-helper"
codesign --force --sign - --options runtime --timestamp=none \
    --identifier org.plf02wh.remoteunlock.approval-helper "$bundle/Contents/MacOS/approval-helper"
identity="$(codesign -d --verbose=4 "$bundle/Contents/MacOS/approval-helper" 2>&1)"
hash="$(printf '%s\n' "$identity" | awk -F= '$1 == "CDHash" { print $2 }')"
[[ "$hash" =~ ^[[:xdigit:]]{40}$ ]]
printf '#define PLF_HELPER_CDHASH "%s"\n' "$hash" > "$out/native-build/HelperIdentity.h"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    -c "$component/helper/TrustedFiles.c" -o "$out/native-build/TrustedFiles.o"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    -c "$component/context/ScreenContext.c" -o "$out/native-build/ScreenContext.o"
xcrun clang -O2 -fobjc-arc -fblocks -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    -I "$out/native-build" -bundle \
    "$component/native/Plugin.m" "$component/native/Mechanism.m" \
    "$component/native/Runner.m" "$component/native/ChildProcess.m" \
    "$component/native/CodeTrust.m" "$component/native/Invocation.m" \
    "$component/native/Records.m" "$out/native-build/TrustedFiles.o" \
    "$out/native-build/ScreenContext.o" \
    -framework Foundation -framework Security -framework CoreGraphics -framework SystemConfiguration \
    -o "$bundle/Contents/MacOS/PlfRemoteApproval"
cp "$component/native/Info.plist" "$bundle/Contents/Info.plist"
plutil -lint "$bundle/Contents/Info.plist" "$component/native/right.plist" \
    "$component/native/screen-right.plist"
codesign --force --sign - --timestamp=none "$bundle"
codesign --verify --strict --verbose=2 "$bundle/Contents/MacOS/approval-helper"
codesign --verify --strict --verbose=2 "$bundle"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    "$component/native/RunApproval.c" -framework Security -framework CoreFoundation \
    -o "$out/run-approval"
codesign --force --sign - --options runtime --timestamp=none \
    --identifier org.plf02wh.remoteunlock.approval-client "$out/run-approval"
codesign --verify --strict --verbose=2 "$out/run-approval"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    -I "$out/native-build" "$component/tests/SignatureTest.m" \
    -framework Foundation -framework Security -o "$out/signature-test"
"$out/signature-test" "$bundle/Contents/MacOS/approval-helper"
printf '%s\n' 'EXPECT_REJECTION: a different signed executable cannot substitute the helper.'
if "$out/signature-test" "$out/run-approval"; then
    printf '%s\n' 'ERROR: helper pin accepted the wrong executable.' >&2
    exit 1
else
    status=$?
    [[ "$status" -eq 1 ]]
fi
printf '%s\n' NATIVE_APPROVAL_CLIENT_BUILD_OK
printf 'NATIVE_BUNDLE_BUILD_OK helper_cdhash=%s\n' "$hash"
printf '%s\n' 'BUILD_ONLY: policy and dedicated identity must be provisioned before an approved installation.'
