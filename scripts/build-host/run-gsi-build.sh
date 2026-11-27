#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/mnt/storage/toss-lineageos}"
TARGETS="${TARGETS:-64VN}"
MEM="${MEM:-20g}"
CPUS="${CPUS:-10}"
IMAGE="toss-lineageos-build:22.04"
NAME="toss-los21-build"
HERE="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "${ROOT}/src" "${ROOT}/ccache" "${ROOT}/home" "${ROOT}/logs"

docker build -t "${IMAGE}" --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" "${HERE}"

docker run -d --rm --name "${NAME}" --hostname "${NAME}" \
    --memory "${MEM}" --memory-swap "${MEM}" --cpus "${CPUS}" --cpu-shares 256 \
    -v "${ROOT}/src:/src" -v "${ROOT}/ccache:/ccache" -v "${ROOT}/home:/home/builder" \
    -v "${ROOT}/logs:/logs" -v "${HERE}/in-container.sh:/in-container.sh:ro" \
    -e USE_CCACHE=1 -e CCACHE_EXEC=/usr/bin/ccache -e CCACHE_DIR=/ccache -e TARGETS="${TARGETS}" \
    -e RESUME_JOBS="${RESUME_JOBS:-}" -e NINJA_HIGHMEM_NUM_JOBS="${NINJA_HIGHMEM_NUM_JOBS:-1}" \
    -e LUNCH_TARGET="${LUNCH_TARGET:-lineage_arm64_bvN-userdebug}" \
    -e BUILD_BROKEN_DISABLE_BAZEL=1 -e SOONG_GOMEMLIMIT="${SOONG_GOMEMLIMIT:-15GiB}" \
    -e GRADLE_OPTS="-Dorg.gradle.daemon=false -Dkotlin.compiler.execution.strategy=in-process" \
    "${IMAGE}" bash /in-container.sh
