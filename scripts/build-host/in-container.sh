#!/usr/bin/env bash
set -euo pipefail

exec > >(tee -a "/logs/build-$(date +%Y%m%d-%H%M%S).log") 2>&1

git config --global user.name "toss-lineageos builder"
git config --global user.email "builder@localhost"
git config --global color.ui false
git lfs install --skip-repo
ccache -M 50G

cd /src

# build_unified.sh는 make -j를 물리 코어 수로 고정한다. 이미 동기화·패치된 트리를 이어서 빌드할 때는
# 메모리 상한에 맞춰 병렬 수를 직접 정한다.
if [ -n "${RESUME_JOBS:-}" ]; then
    set +u
    source build/envsetup.sh
    lunch "${LUNCH_TARGET:-lineage_arm64_bvN-userdebug}"
    set -u
    # make는 envsetup.sh의 셸 함수라 nice로 감싸면 /usr/bin/make가 실행된다. 셸 자체의 우선순위를 낮춘다.
    renice -n 10 -p $$ >/dev/null
    ionice -c2 -n7 -p $$
    if [ "$TARGET_PRODUCT" = lineage_arm64_bgN ]; then
        unset WITH_ADB_INSECURE
    else
        export WITH_ADB_INSECURE=true
    fi
    make -j"${RESUME_JOBS}" systemimage
    mkdir -p ~/build-output
    cp "${OUT}/system.img" ~/build-output/"lineage-21.0-$(date -u +%Y%m%d-%H%M%S)-UNOFFICIAL-${TARGET_PRODUCT#lineage_}.img"
    ls -l ~/build-output
    exit 0
fi

if [ ! -d .repo ]; then
    repo init -u https://github.com/LOS21-pre-QPR2/android.git -b lineage-21.0 --git-lfs --depth=1
fi

for repo_name in lineage_build_unified lineage_patches_unified; do
    if [ -d "${repo_name}" ]; then
        git -C "${repo_name}" pull --ff-only
    else
        git clone "https://github.com/AndyCGYan/${repo_name}" "${repo_name}" -b lineage-21-pre-qpr2-td
    fi
    echo "${repo_name} $(git -C "${repo_name}" rev-parse HEAD)"
done
echo "manifest $(git -C .repo/manifests rev-parse HEAD)"

# build_unified.sh는 서명 키가 없을 때 키 입력을 기다리므로 한 글자를 넘겨 서명 없이 진행한다.
echo x | nice -n 10 ionice -c2 -n7 bash lineage_build_unified/build_unified.sh treble ${TARGETS}
