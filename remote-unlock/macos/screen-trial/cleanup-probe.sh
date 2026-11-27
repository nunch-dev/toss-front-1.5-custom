#!/bin/bash
set -euo pipefail
[[ "$#" -eq 0 ]] || exit 1
[[ "$(/usr/bin/id -u)" -eq 0 ]] || exit 1
base="/Library/Application Support/PLF02WHRemoteApproval"
state="$base/screen-trial"
job="/Library/LaunchDaemons/org.plf02wh.remoteunlock.screen-trial-restore.plist"
# A conflicting policy stops cleanup here and preserves the snapshots for recovery.
"$state/restore" restore
[[ -f "$state/mode" && ! -L "$state/mode" ]] || exit 1
IFS= read -r mode < "$state/mode"
case "$mode" in
    probe) bundle_name=PlfAuthProbe ;;
    screen-trial) bundle_name=PlfRemoteApproval ;;
    *) exit 2 ;;
esac
bundle="/Library/Security/SecurityAgentPlugins/$bundle_name.bundle"
/bin/launchctl bootout system "$job"
/usr/bin/security authorizationdb remove org.plf02wh.remoteunlock.screen-test
/bin/rm "$job"
/bin/rm -R "$bundle"
if [[ "$mode" == screen-trial ]]; then
    /bin/rm "$base/screen-requester.private.json"
fi
# Remove only this trial's files; an unexpected file makes rmdir fail and remains intact.
for name in restore original.plist trial.plist deadline ready restored lock watch.log mode; do
    if [[ -f "$state/$name" && ! -L "$state/$name" ]]; then
        /bin/rm "$state/$name"
    fi
done
/bin/rmdir "$state" "$base"
printf '%s\n' SCREEN_TRIAL_CLEANUP_OK
