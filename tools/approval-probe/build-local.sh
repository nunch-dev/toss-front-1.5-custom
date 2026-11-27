#!/bin/bash
set -euo pipefail
umask 077
[[ "$#" -eq 1 ]] || exit 2
trial="$(CDPATH= cd -- "$1" && pwd)"
source_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
root="$(CDPATH= cd -- "$source_dir/../.." && pwd)"
out="$root/private/approval-probe-20261123"
sdk="${ANDROID_HOME:-$HOME/sdk/android}"
java_home="${JAVA_HOME:-$HOME/Library/Java/JavaVirtualMachines/openjdk-17.0.2/Contents/Home}"
export JAVA_HOME="$java_home"
export PATH="$JAVA_HOME/bin:$PATH"
tools="$sdk/build-tools/36.1.0"
android="$sdk/platforms/android-34/android.jar"
lib="$out/lib"
[[ -f "$trial/config.json" && -f "$trial/tls/ca.pem" ]] || exit 2
mkdir -p "$lib"
fetch() {
    local path="$1" hash="$2" file="$lib/${1##*/}"
    if [[ ! -f "$file" ]]; then
        /usr/bin/curl --fail --location --proto =https \
            "https://repo.maven.apache.org/maven2/$path" -o "$file"
    fi
    printf '%s  %s\n' "$hash" "$file" | /usr/bin/shasum -a 256 -c -
}
fetch com/nimbusds/nimbus-jose-jwt/10.10/nimbus-jose-jwt-10.10.jar \
    0edd2fbaab79e13f87d145d021f85a5c59956b2b6b5e761c0d664c87f94cda15
fetch org/java-websocket/Java-WebSocket/1.6.0/Java-WebSocket-1.6.0.jar \
    eae29213e4f16515639c28957200f011b3967fffcada1962cf0255d24919c22f
fetch org/slf4j/slf4j-api/2.0.13/slf4j-api-2.0.13.jar \
    e7c2a48e8515ba1f49fa637d57b4e2f590b3f5bd97407ac699c3aa5efb1204a9
fetch org/slf4j/slf4j-simple/2.0.13/slf4j-simple-2.0.13.jar \
    3153fe1d689cffb94f1530b58470c306685ba68844de8857116e3b6ebb81d9f7
work="$(mktemp -d "$out/build.XXXXXX")"
mkdir -p "$work/classes" "$work/dex" "$work/generated" "$work/assets" "$work/res/raw"
cp -R "$source_dir/res/." "$work/res/"
cp "$trial/tls/ca.pem" "$work/res/raw/trial_ca.pem"
cp "$trial/config.json" "$work/assets/trial.json"
"$tools/aapt2" compile --dir "$work/res" -o "$work/resources.zip"
"$tools/aapt2" link -I "$android" --manifest "$source_dir/AndroidManifest.xml" \
    --min-sdk-version 30 --target-sdk-version 34 --java "$work/generated" \
    -A "$work/assets" -o "$work/unsigned.apk" "$work/resources.zip"
"$java_home/bin/javac" -encoding UTF-8 --release 8 -Xlint:all -Werror \
    -classpath "$android:$lib/*" -d "$work/classes" \
    "$source_dir"/src/org/plf02wh/approvalprobe/*.java \
    "$work/generated/org/plf02wh/approvalprobe/R.java"
"$tools/d8" --lib "$android" --min-api 30 --output "$work/dex" \
    "$work"/classes/org/plf02wh/approvalprobe/*.class "$lib"/*.jar
zip -q -j "$work/unsigned.apk" "$work/dex/classes.dex"
"$tools/zipalign" -f 4 "$work/unsigned.apk" "$work/aligned.apk"
if [[ ! -f "$out/debug.keystore" ]]; then
    "$java_home/bin/keytool" -genkeypair -keystore "$out/debug.keystore" \
        -storepass android -keypass android -alias approval-probe \
        -keyalg RSA -keysize 2048 -validity 30 -dname "CN=PLF Local Approval Trial"
fi
"$tools/apksigner" sign --ks "$out/debug.keystore" --ks-key-alias approval-probe \
    --ks-pass pass:android --key-pass pass:android \
    --out "$out/PlfApprovalProbe.apk" "$work/aligned.apk"
"$tools/apksigner" verify --verbose "$out/PlfApprovalProbe.apk"
"$tools/aapt2" dump permissions "$out/PlfApprovalProbe.apk"
printf 'APPROVAL_APK_READY %s\n' "$out/PlfApprovalProbe.apk"
