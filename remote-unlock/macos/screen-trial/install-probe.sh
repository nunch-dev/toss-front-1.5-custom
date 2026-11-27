#!/bin/bash
set -euo pipefail
# macOS Bash 3.2 does not apply errexit to a standalone [[ ... ]] command.
[[ "$#" -le 1 ]] || exit 1
case "${1:-probe}" in
    probe) mode=probe; bundle_name=PlfAuthProbe; right_file=probe-right.plist ;;
    --signed-approval) mode=screen-trial; bundle_name=PlfRemoteApproval; right_file=screen-right.plist ;;
    *) exit 2 ;;
esac
[[ "$(/usr/bin/id -u)" -eq 0 ]] || exit 1
umask 022
stage="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
base="/Library/Application Support/PLF02WHRemoteApproval"
state="$base/screen-trial"
bundle="/Library/Security/SecurityAgentPlugins/$bundle_name.bundle"
job="/Library/LaunchDaemons/org.plf02wh.remoteunlock.screen-trial-restore.plist"
right="org.plf02wh.remoteunlock.screen-test"
for target in "$base" "$bundle" "$job"; do
    if [[ -e "$target" || -L "$target" ]]; then
        printf 'SCREEN_TRIAL_REFUSE_EXISTING %s\n' "$target" >&2
        exit 1
    fi
done
if /usr/bin/security authorizationdb read "$right" >/dev/null 2>&1; then
    printf '%s\n' SCREEN_TRIAL_REFUSE_EXISTING_RIGHT >&2
    exit 1
fi
/usr/bin/codesign --verify --strict "$stage/restore"
/usr/bin/codesign --verify --strict "$stage/$bundle_name.bundle"
/usr/bin/plutil -lint "$stage/restore.plist" "$stage/$right_file"
if [[ "$mode" == screen-trial ]]; then
    # This installer is scoped to the observed UID 92 / console UID 501 trial.
    [[ "$(/usr/bin/id -u _securityagent)" == 92 ]] || exit 1
    policy="$stage/$bundle_name.bundle/Contents/Resources/policy.json"
    [[ "$(/usr/bin/plutil -extract version raw -o - "$policy")" == 2 ]] || exit 1
    [[ "$(/usr/bin/plutil -extract mode raw -o - "$policy")" == screen-trial ]] || exit 1
    [[ "$(/usr/bin/plutil -extract executionUID raw -o - "$policy")" == 92 ]] || exit 1
    [[ "$(/usr/bin/plutil -extract targetConsoleUID raw -o - "$policy")" == 501 ]] || exit 1
    [[ "$(/usr/bin/plutil -extract relay.account raw -o - "$policy")" == screen-trial-uid-501 ]] || exit 1
    [[ "$(/usr/bin/plutil -extract requesterKeyFile raw -o - "$policy")" == "$base/screen-requester.private.json" ]] || exit 1
    [[ "$(/usr/bin/plutil -extract caCertificateFile raw -o - "$policy")" == "$bundle/Contents/Resources/relay-ca.der" ]] || exit 1
    [[ -f "$stage/screen-requester.private.json" && ! -L "$stage/screen-requester.private.json" ]] || exit 1
    [[ -f "$stage/$bundle_name.bundle/Contents/Resources/relay-ca.der" ]] || exit 1
    /usr/bin/codesign --verify --strict "$stage/$bundle_name.bundle/Contents/MacOS/approval-helper"
fi
/usr/bin/install -d -o root -g wheel -m 0755 "$base" "$state"
printf '%s\n' "$mode" > "$state/mode"
/usr/bin/install -o root -g wheel -m 0755 "$stage/restore" "$state/restore"
"$state/restore" capture
/usr/bin/ditto "$stage/$bundle_name.bundle" "$bundle"
/usr/sbin/chown -R root:wheel "$bundle"
/bin/chmod -R u=rwX,go=rX "$bundle"
/usr/bin/codesign --verify --strict "$bundle"
if [[ "$mode" == screen-trial ]]; then
    /usr/bin/install -o 92 -g wheel -m 0600 \
        "$stage/screen-requester.private.json" "$base/screen-requester.private.json"
fi
/usr/bin/security authorizationdb write "$right" < "$stage/$right_file"
/usr/bin/install -o root -g wheel -m 0644 "$stage/restore.plist" "$job"
/bin/launchctl bootstrap system "$job"
/bin/launchctl print system/org.plf02wh.remoteunlock.screen-trial-restore >/dev/null
printf '%s\n' SCREEN_TRIAL_INSTALLED_NOT_APPLIED
