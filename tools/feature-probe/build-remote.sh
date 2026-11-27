#!/usr/bin/env bash
set -euo pipefail
cd /mnt/storage/toss-lineageos
log="logs/plf02wh-feature-probe-20261119.log"
set -o pipefail
docker run --rm --name plf02wh-feature-probe-build \
    --user builder --memory=20g --memory-swap=20g --cpus=10 --cpu-shares=256 \
    -v "$PWD/src:/src" -v "$PWD/home:/home/builder" -v "$PWD/ccache:/ccache" \
    -w /src \
    -e SOONG_GOMEMLIMIT=15GiB -e NINJA_HIGHMEM_NUM_JOBS=1 \
    -e BUILD_BROKEN_DISABLE_BAZEL=1 \
    toss-lineageos-build:22.04 bash -lc '
        set -eo pipefail
        unset WITH_ADB_INSECURE
        source build/envsetup.sh
        lunch lineage_arm64_bgN-userdebug
        m -j3 out/soong/.intermediates/device/phh/treble/plf02wh_feature_probe/Plf02whFeatureProbe/android_common/Plf02whFeatureProbe.apk
    ' 2>&1 | tee "$log"
printf '%s\n' 'PROBE_BUILD_OK'
