#!/usr/bin/env bash
set -euo pipefail
cd /mnt/storage/toss-lineageos/src
apk="out/soong/.intermediates/device/phh/treble/plf02wh_feature_probe/Plf02whFeatureProbe/android_common/Plf02whFeatureProbe.apk"
export JAVA_HOME="$PWD/prebuilts/jdk/jdk17/linux-x86"
export PATH="$JAVA_HOME/bin:$PATH"
test -s "$apk"
sha256sum "$apk"
java -jar prebuilts/sdk/tools/linux/lib/apksigner.jar verify --verbose --print-certs "$apk"
prebuilts/sdk/tools/linux/bin/aapt2 dump badging "$apk"
prebuilts/sdk/tools/linux/bin/aapt2 dump xmltree "$apk" --file AndroidManifest.xml
prebuilts/sdk/tools/linux/bin/aapt2 dump xmltree "$apk" --file res/xml/network_security_config.xml
python3 - "$apk" <<'PY'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as apk:
    assert "classes.dex" in apk.namelist(), "Missing application dex"
    assert apk.testzip() is None, "APK ZIP integrity failure"
    dex = apk.read("classes.dex")
    assert b"Lorg/plf02wh/featureprobe/MainActivity;" in dex, "Missing activity"
    print("APK_DEX_AND_ZIP_OK", "dex_bytes=" + str(len(dex)))
PY
printf '%s\n' 'PROBE_STATIC_ARTIFACT_OK'
