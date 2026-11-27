#!/bin/bash
set -euo pipefail
umask 077
component="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project="$(CDPATH= cd -- "$component/../../.." && pwd)"
out="$project/private/macos-screen-trial"
mkdir -p "$out"
xcrun swiftc -swift-version 6 -warnings-as-errors \
    "$component/ScreenRule.swift" "$component/TrialDeadline.swift" \
    "$component/TrialController.swift" -o "$out/restore"
codesign --force --sign - --options runtime --timestamp=none \
    --identifier org.plf02wh.remoteunlock.screen-trial-restore "$out/restore"
codesign --verify --strict "$out/restore"
plutil -lint "$component/restore.plist"
xcrun swiftc -swift-version 6 -warnings-as-errors \
    "$component/ScreenRule.swift" "$component/TrialDeadline.swift" \
    "$component/tests/ScreenRuleTests.swift" -o "$out/rule-tests"
"$out/rule-tests"
printf '%s\n' SCREEN_TRIAL_BUILD_OK
