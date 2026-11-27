#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$source_dir/../.." && pwd)"
sdk="${ANDROID_HOME:-$HOME/sdk/android}"
java_home="${JAVA_HOME:-$HOME/Library/Java/JavaVirtualMachines/openjdk-17.0.2/Contents/Home}"
export JAVA_HOME="$java_home"
export PATH="$JAVA_HOME/bin:$PATH"
tools="$sdk/build-tools/34.0.0"
android="$sdk/platforms/android-34/android.jar"
out="$root/private/camera-probe-20261120"
mkdir -p "$out/classes" "$out/dex" "$out/generated"
classes_dir="$(mktemp -d "$out/classes/build.XXXXXX")"
"$tools/aapt2" compile --dir "$source_dir/res" -o "$out/resources.zip"
"$tools/aapt2" link -I "$android" --manifest "$source_dir/AndroidManifest.xml" \
    --min-sdk-version 30 --target-sdk-version 34 --java "$out/generated" \
    -o "$out/unsigned.apk" "$out/resources.zip"
sources=("$source_dir"/src/org/plf02wh/cameraprobe/*.java)
"$JAVA_HOME/bin/javac" -encoding UTF-8 --release 8 \
    -classpath "$android" -d "$classes_dir" "${sources[@]}" \
    "$out/generated/org/plf02wh/cameraprobe/R.java"
classes=("$classes_dir"/org/plf02wh/cameraprobe/*.class)
"$tools/d8" --lib "$android" --min-api 30 --output "$out/dex" "${classes[@]}"
zip -q -j "$out/unsigned.apk" "$out/dex/classes.dex"
"$tools/zipalign" -f 4 "$out/unsigned.apk" "$out/aligned.apk"
if [[ ! -f "$out/debug.keystore" ]]; then
    "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$out/debug.keystore" \
        -storepass android -keypass android -alias camera-probe \
        -keyalg RSA -keysize 2048 -validity 3650 \
        -dname "CN=PLF02WH Camera Probe Development"
fi
"$tools/apksigner" sign --ks "$out/debug.keystore" --ks-key-alias camera-probe \
    --ks-pass pass:android --key-pass pass:android \
    --out "$out/Plf02whCameraProbe.apk" "$out/aligned.apk"
"$tools/apksigner" verify --verbose --print-certs "$out/Plf02whCameraProbe.apk"
"$tools/aapt2" dump permissions "$out/Plf02whCameraProbe.apk"
unzip -l "$out/Plf02whCameraProbe.apk"
shasum -a 256 "$out/Plf02whCameraProbe.apk"
printf '%s\n' CAMERA_PROBE_BUILD_OK
