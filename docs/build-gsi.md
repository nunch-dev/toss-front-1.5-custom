# GSI 소스 빌드 기록

이 문서는 LineageOS 21 pre-QPR2 TrebleDroid 기반 GSI를 소스에서 빌드한 절차와 결과를 기록합니다.

## 최종 결과 (2026-11-18)

dev 서버에서 `systemimage` 빌드와 결과 폴더 복사가 완료됐습니다. 마지막 재개 실행은 6,113단계를 완료했고, 빌드 로그의 소요 시간은 1시간 1분 54초입니다. 이전 동기화와 실패한 실행 시간은 여기에 포함되지 않습니다.

| 항목 | 확인값 |
|---|---|
| 결과 이미지 | `/mnt/storage/toss-lineageos/home/build-output/lineage-21.0-20261118-UNOFFICIAL-arm64_bvN.img` |
| 파일 크기 | 2,548,199,424 bytes |
| SHA-256 | `50fe993c6aaa65732f939c821bb5b3587b2210d7780f286808b78f1e8b4fcc8f` |
| 빌드 로그 | `/mnt/storage/toss-lineageos/logs/build-20261118-071437.log` |
| 빌드 결과 | `build completed successfully (01:01:54 (hh:mm:ss))` |
| 읽기 전용 파일시스템 검사 | `e2fsck -fn` 종료 코드 0 |
| 성공한 병렬 설정 | `RESUME_JOBS=3`, `NINJA_HIGHMEM_NUM_JOBS=1`, 메모리 20 GiB, CPU 10 상한 |

기존 system 한도 1,922,445,312 bytes보다 **625,754,112 bytes 큽니다**. 이번 산출물은 기본 GSI 빌드 성공을 확인한 것이며, 현재 파티션 구성에 바로 설치할 수 있는 이미지가 아닙니다. 용량 축소와 실기 부팅·주변기기 검증은 하지 않았습니다. 기기 쓰기, 플래시, 서버 sudo 사용도 하지 않았습니다.

서버의 `/mnt/storage/toss-lineageos/build-host`에서 `RESUME_JOBS=3 ./run-gsi-build.sh`로 이미 동기화·패치된 트리를 이어 빌드했습니다. 처음 재개할 때 `nice … make`가 셸 함수 대신 시스템 make를 실행해 실패했고, 셸 자체의 우선순위를 낮춘 뒤 envsetup의 make 함수를 호출하도록 수정했습니다.

아래 매니페스트·빌드 스크립트·패치 커밋은 사용한 입력 기록입니다. 모든 저장소의 revision을 고정한 전체 매니페스트를 보관한 것은 아니므로, 이 세 값만으로 동일 소스의 재동기화를 보장하지 않습니다.

## 빌드 환경

| 항목 | 값 |
|---|---|
| 호스트 | SSH `dev`(192.168.0.151). Ubuntu 24.04 x86_64, i5-10505, RAM 31 GiB |
| 작업 위치 | `/mnt/storage/toss-lineageos` (HDD). 하위 디렉터리: `src`, `ccache`, `home`, `logs`, `build-host` |
| 컨테이너 | Ubuntu 22.04 이미지 `toss-lineageos-build:22.04`, 정의 파일은 [scripts/build-host/Dockerfile](../scripts/build-host/Dockerfile) |
| 자원 상한 | 메모리 20 GiB(swap 없음), CPU 10개, `nice 10`, `ionice -c2 -n7` |
| 실행 방법 | 최초 경로는 `TARGETS=64VN ./run-gsi-build.sh`. 이번 성공 실행은 동기화·패치가 끝난 트리에서 `RESUME_JOBS=3 ./run-gsi-build.sh` 사용 |
| 대상 | `64VN` = `lineage_arm64_bvN-userdebug` (GApps 없음, `WITH_ADB_INSECURE=true`, 사용자 릴리스 키로 재서명하지 않음) |

## 사용한 소스 커밋 (2026-11-18 동기화)

| 저장소 | 커밋 |
|---|---|
| 매니페스트 `LOS21-pre-QPR2/android` (`lineage-21.0`) | `bd554082d94a0dced2ff3f0a1a9e233fc976db2d` |
| `AndyCGYan/lineage_build_unified` (`lineage-21-pre-qpr2-td`) | `edac8329d0212a9609a40f3efc6eec877cc88b85` |
| `AndyCGYan/lineage_patches_unified` (`lineage-21-pre-qpr2-td`) | `c867009a0bb468843be4e1205d52dc43b5218cdd` |

- 소스는 `repo init --depth=1`로 받았습니다. 동기화 직후 `/mnt/storage` 사용량이 약 110 GB 늘었습니다.
- 패치 그룹 4개(`patches_treble_prerequisite`, `patches_treble_td`, `patches_platform`, `patches_treble`)와 TrebleApp 빌드가 모두 오류 없이 끝났습니다.

## 메모리 부족 대응

빌드 그래프를 분석하는 `soong_build`(Go 프로그램)가 컨테이너 상한 20 GiB를 넘어 두 번 강제 종료됐습니다. 관측된 OOM 대상은 빌드 컨테이너였고, 종료 뒤 호스트 가용 메모리는 약 23.8 GiB였습니다. 다른 서비스의 응답 시간과 기능은 검사하지 않았으므로 영향이 전혀 없었다고 단정하지 않습니다.

| 원인 | 조치 |
|---|---|
| TrebleApp 빌드가 끝난 뒤에도 Gradle/Kotlin 데몬이 남아 약 3.5 GB를 차지함 | `GRADLE_OPTS=-Dorg.gradle.daemon=false -Dkotlin.compiler.execution.strategy=in-process` |
| Bazel 혼합 빌드 분석(`--bazel-mode`)이 메모리를 추가로 씀 | `BUILD_BROKEN_DISABLE_BAZEL=1` |
| Go 힙이 실제 사용량의 약 2배까지 커짐. `soong_build`는 `env -i`로 실행돼 호출자의 `GOMEMLIMIT`가 전달되지 않음 | `build/soong`에 [`SOONG_GOMEMLIMIT`/`SOONG_GOGC` 전달 패치](../patches/build_soong/0001-Pass-SOONG_GOMEMLIMIT-and-SOONG_GOGC-to-soong_build.patch)를 적용하고, `SOONG_GOMEMLIMIT=15GiB`로 실행 |

세 번째 실행에서 `soong_build` 프로세스 환경에 `GOMEMLIMIT=15GiB`가 들어가고 `--bazel-mode`가 빠진 것을 확인했습니다. 이번에는 분석 단계를 통과했고, 컴파일 단계는 총 175,532단계입니다. 시작 14분 뒤 컨테이너 메모리는 약 8 GiB, 호스트 가용 메모리는 약 17.7 GiB였습니다.

세 번째 실행은 97%(171,097/175,532단계)에서 다시 컨테이너 메모리 상한에 걸려 `ninja`가 강제 종료됐습니다(`ninja failed with: signal: killed`). 종료 뒤 서버 가용 메모리는 약 23 GiB였습니다. 마지막 로그는 R8/Java 작업 구간이었지만 종료 순간의 작업별 메모리 사용량은 수집하지 못했습니다. `build_unified.sh`는 `make -j`를 물리 코어 수(6)로 고정하므로, 이미 받은 트리를 이어 빌드할 때는 `RESUME_JOBS=3 ./run-gsi-build.sh`로 `build_unified.sh`를 거치지 않고 `make -j3 systemimage`를 직접 실행합니다. 고메모리 풀의 동시 실행 수도 `NINJA_HIGHMEM_NUM_JOBS=1`로 제한했습니다. 모든 Java/R8 작업이 이 풀에 속한다고 확인한 것은 아닙니다.

`build/soong` 패치는 지금 빌드 트리에만 커밋돼 있습니다(`d1a542a`). 소스를 처음부터 다시 받으면 빌드 전에 `patches/build_soong/`의 패치를 `git am`으로 다시 적용해야 합니다.
