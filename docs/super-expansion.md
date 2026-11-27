# PLF02WH super 확장 준비

이 문서는 2.5 GiB 확장과 최초 LineageOS 21 설치의 기준본 기록이다. 이후 vendor의 memtrack·FBE·Keymaster 변경을 적용했으므로 아래 전체 super 해시는 확장 당시 기준 이미지의 해시이며, 현재 저장장치 전체의 해시로 사용하지 않는다. 최신 vendor와 검증 결과는 [기기 상태](device-status.md)와 [보안 검증](security.md)을 따른다.

## 승인 범위와 현재 상태

2026-11-18 사용자가 userdata를 줄이고 시스템 용량을 늘리는 준비를 요청했다. 보존할 사용자 데이터는 없다고 확인했지만, 실제 GPT 쓰기·userdata 초기화·ROM 기록 직전에는 대상과 복구 방법을 제시하고 최종 확인을 받는다.

준비 단계에서는 재부팅·모드 전환, RAM Loader 적재, 읽기 전용 백업을 수행했다. 이후 실제 변경 범위와 복구 한계를 제시한 질문에 사용자가 “좋아 진행해”라고 승인했다.

실기 기록·재읽기 검증·첫 부팅을 완료했다. 쓰기 직전 USB 위치 801의 단일 RK3399 장치, RAM Loader capability `3F 06 00 00 00 00 00 00`, 기존 GPT와 `gpt-prewrite.bin`의 전체 일치를 확인했다. 아래 기록 결과를 확인한 뒤 재부팅했고, Android 14·LineageOS 21의 초기 설정 화면을 확인했다.

대상은 시리얼 `PLF02WH_SERIAL`(공개용 가명), TOSS_Front, RK3399이며 기존 OS는 `18.1-20240121-UNOFFICIAL-arm64_bvS`다.

## 작업 위치

- Mac 준비·백업: `/Users/nunch/Desktop/toss-lineageos/private/expand-prep-20261118-ZimJvy`
- dev 서버 작업: `/mnt/storage/toss-lineageos/expand-prep-20261118-ZimJvy`
- 새 system 원본: `home/build-output/lineage-21.0-20261118-124241-UNOFFICIAL-arm64_bgN.img` (dev 서버 프로젝트 디렉터리 기준)
- 새 system 크기: 2,272,292,864 bytes
- 새 system SHA-256: `bc5ff0710896f2ed9cd99843fdbaebe20b864faa78cba29ad211fe7bb6941ca2`

Mac의 `system-lineage21-gapps.img`는 VINTF 보완 전 `092248` 원본의 전송 검증본이다. 이 파일과 첫 super 후보를 최종 기록에 사용하지 않는다. 최종 기록 대상은 아래의 `super-lineage21-vintf-expanded.img`다.

## 읽기 경로

`adb reboot bootloader`는 Fastboot로 진입했다. 소프트웨어 재부팅·continue로 ADB에 복귀하지 못해 사용자가 전원을 완전히 껐다 켰고, 기존 Android 복귀를 확인했다. 이후 `adb reboot loader`로 Rockchip Loader에 진입했다.

이 Loader는 기본 GPT는 정상 반환했지만 super 앞부분과 디스크 끝의 백업 GPT를 전부 `0xCC`로 반환했다. 명령의 성공 코드만으로 백업 성공을 판단하지 않는다.

따라서 `rd 3`으로 Maskrom에 진입하고 기존 RK3399 Loader를 `db`로 RAM에 적재했다. 이 경로는 `ul` 부트로더 업그레이드와 다르다. RAM Loader 적재 뒤에도 도구의 모드 표시는 `Maskrom`이며, 이전 정상 읽기 기록과 동일한 capability `3F 06 00 00 00 00 00 00`을 확인했다.

- 도구: `~/Tools/toss-front/rkdeveloptool-official-20261117/build-macos/rkdeveloptool`
- Loader: `~/Tools/toss-front/loader-ram-test-20261117-MpIsi6/rk3399_loader_v1.30.130.bin`
- Loader 크기: 454,990 bytes
- Loader SHA-256: `e7ea515e2185c67946268ccf2f2aa85d581fc1a69eb40c0b3ec634499178963a`

`gpt-backup-a.bin`과 `super-head-loader.bin`은 잘못된 채움 데이터이므로 **복구 입력으로 사용하지 않는다**. 정상 샘플은 이름에 `ram`이 붙은 파일이다.

## 현재 기기 백업 검증

| 파일 | 범위·크기 | SHA-256 |
|---|---|---|
| `current-prefix-a.img`, `current-prefix-b.img` | LBA 0부터 6,180,863까지 각각 3,164,602,368 bytes | `aa2e97c5bf6132f7553808cf5fd52e6de940d4cbe27ae2f9c6644ba06344f04c` |
| `gpt-primary-ram.bin` | 기본 GPT 34섹터 | `e551a100b43b0aecd50e00a6376a64e6a6f304658cb50dce97c70e02ee544a49` |
| `gpt-backup-ram.bin` | 마지막 33섹터 | `d7c320771c2ce2eba226dca5db6be5ca23e96a6e698dece5c03107aa65909575` |
| `super-current-a.img` | 현재 super 2 GiB를 첫 백업에서 추출 | `bfc53ac3d388a93126f7604caeec26bd989d3d5cc6a94f29d275f8816f08844a` |

두 prefix 백업은 전체 `cmp`도 통과했다. 양쪽 GPT의 CRC와 파티션 배열 일치, 디스크 범위, super geometry의 SHA-256을 확인했다. 현재 GPT는 보관된 11월 17일 원본과 일치하며, 현재 super의 해시는 이전 정상 18.1 가공본 기록과 일치한다.

백업 범위에는 GPT, security, uboot, trust, misc, dtbo, vbmeta, boot, recovery, backup, cache, metadata, baseparameter, super 및 그 사이 영역이 포함된다. **userdata, 별도 eMMC boot 영역과 RPMB는 포함하지 않는다. 실제 복원 시험을 통과했다는 뜻은 아니다.**

## PC에서 생성한 GPT 후보

섹터 크기는 512 bytes다. 디스크 전체는 30,539,776섹터이며 백업 GPT 헤더는 LBA 30,539,775에 있다.

| 항목 | 현재 | 확장 후보 |
|---|---:|---:|
| super 시작 LBA | 1,986,560 | 1,986,560 |
| super 끝 LBA | 6,180,863 | 7,229,439 |
| super 크기 | 2,147,483,648 bytes | 2,684,354,560 bytes |
| userdata 시작 LBA | 6,180,864 | 7,229,440 |
| userdata 끝 LBA | 30,539,711 | 30,539,711 |

다른 파티션의 경계·GUID·속성, 디스크 GUID, 보호 MBR은 보존한다. 두 GPT의 파티션 배열 CRC와 헤더 CRC만 변경 내용에 맞춰 갱신했다.

- `gpt-expanded-primary.img`: 17,408 bytes, SHA-256 `0eea489f31babcc5424b16d63eda4898b94795bdf1645247157ad527dd23ac30`
- `gpt-expanded-backup.img`: 16,896 bytes, SHA-256 `e776be94995ad6b2808528e1d0019813726e82dd7e80d504f7283bdece7dfbff`

독립된 Python `struct`·`zlib` 검사로 CRC, 양쪽 헤더 위치, 파티션 배열 일치, 두 경계 외의 필드 보존을 교차 검증했다. 겹침이 없고 새 userdata 시작점은 1 MiB 정렬을 유지한다. 최종 승인 후 이 후보를 기기에 기록하고 재읽기로 대조했다.

## 확장 super 후보 검증

**이 절의 첫 후보는 구조·내용 검사는 통과했지만 아래 VINTF 불일치가 발견되어 기록 대상으로 승인하지 않았다. 이후 보완된 system을 재빌드해 아래 최종 super 후보로 대체했다.**

- 파일: `super-lineage21-expanded.img`
- 크기: 2,684,354,560 bytes
- SHA-256: `4c0d32f02e568db27defdcabda5b57d58804c3ab6f2b9edfdf74af3ab74f05b6`
- 서버 생성본과 Mac 전송본의 해시가 일치한다.
- 메타데이터: 버전 10.0, 최대 65,536 bytes, 슬롯 2개, 블록 크기 4,096 bytes, 정렬 1 MiB.
- `rockchip_dynamic_partitions` 그룹 한도: 2,680,160,256 bytes.

| 논리 파티션 | 크기 | 새 super에서 재추출한 이미지 SHA-256 |
|---|---:|---|
| system | 2,272,292,864 | `de850e39ed69cbb725caa6749b12e5cc670193203f00e2b38f9203956729f1e9` |
| vendor | 220,258,304 | `3f25245fac06f2fa50d9ce964b7754f4316a78d749f2a1bd2a8826f05e5d34c4` |
| odm | 581,632 | `bb5e3c11dbbdde1a6ebfa59b1148f56722aa38735a189c77b14805fe0ba02fdb` |

재추출한 system은 빌드 원본과, vendor·odm은 현재 기기 백업에서 분리한 이미지와 전체 `cmp`가 일치한다. system은 앞선 빌드의 읽기 전용 fsck 통과본과 동일하며, vendor·odm도 `e2fsck -fn`을 통과했다. 메타데이터 슬롯 0과 1에서 동일한 파티션 크기와 그룹 구성을 확인했다.

## userdata 초기화와 복구 계획

현재 vendor의 `/data` fstab에는 `latemount,wait,formattable,check,quota,reservedsize=128M`이 있다. 암호화 설정은 기존과 같이 빠져 있다. 새 system에는 `mke2fs`, `e2fsdroid`, `mke2fs.conf`가 포함돼 있다.

Android 14의 `partition_wiped`는 파티션 앞 4,096바이트가 모두 0 또는 `0xFF`인지 확인한다. `fs_mgr`는 마운트가 실패하고 `formattable` 및 wiped 조건을 충족하면 포맷을 시도한다. 이 경로를 이용할 초기화 표식을 PC에 준비했다.

- 파일: `userdata-wipe-marker-4k.bin`, 4,096 bytes의 0
- SHA-256: `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7`
- 적용 후보 위치: 새 userdata 시작 LBA 7,229,440부터 8섹터

이는 기존 사용자 데이터를 안전하게 삭제했다는 보장이 아니라, 새 파일시스템 생성을 요청하는 표식이다. 적용 후 새 userdata 마운트와 첫 부팅 성공을 확인했다.

최종 승인 후의 기록 순서는 새 super 기록·전체 재읽기 검증, 새 userdata 초기화 표식 기록·대조, 백업 GPT와 기본 GPT 기록·대조, 재부팅이다. 각 단계 실패 시 다음 쓰기를 계속하지 않는다. `prm`이나 `ul`, 전체 저장장치 삭제, 부트로더 잠금은 사용하지 않는다.

원복안은 보관한 기존 super와 양쪽 GPT를 복원하고 원래 userdata 시작 LBA 6,180,864에 초기화 표식을 적용해 기존 18.1의 새 사용자 영역을 만드는 것이다. 사용자 데이터 복원은 이 백업 범위에 포함되지 않는다. 이 원복 절차 자체와 Android가 부팅되지 않을 때의 수동 복구 진입은 아직 실기 검증하지 않았다.

## VINTF 검사에서 발견한 불일치와 보완

새 system 이미지와 현재 기기의 vendor·odm에서 추출한 VINTF 선언 32개를 검사했다. XML 구문은 정상이었고 product·odm의 별도 VINTF 디렉터리는 이미지에 없었다. 추출 도구의 소유자 변경은 일반 계정 권한으로 거부됐으나 파일 내용은 생성됐으며, 소유자를 변경하려고 권한을 올리지 않았다.

첫 검사에서는 `/apex` 경로 매핑 누락으로 도구가 중단됐다. 경로를 추가하고 실제 라이브러리가 지원하는 APEX 정보 파일 부재 경로로 검사했다. 이 검사는 부팅 후의 동적 APEX 활성화 상태까지 재현한 것은 아니다.

커널 `4.19.193`과 실기에서 수집한 커널 설정, 최초 API 30을 사용한 검사에서 다음 제조사 HAL 두 개가 framework 호환성 표에 없다는 이유로 `INCOMPATIBLE`이 나왔다(종료 코드 65).

- `rockchip.hardware.outputmanager@1.0::IRkOutputManager/default`
- `rockchip.hardware.rockit.hw@1.0::IRockitHwService/default`

제조사 HAL을 제거하지 않고 [기기 전용 매트릭스](../configs/plf02wh/framework_compatibility_matrix.xml)에 두 선택 HAL의 실제 버전·인터페이스·인스턴스를 선언했다. `lineage_arm64_bgN`의 BoardConfig에서 `DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE`로 연결하는 변경은 [VINTF 패치](../patches/plf02wh-vintf.patch)에 보관했다.

검사용 매트릭스에 이 선언을 병합하자 동일한 커널·vendor 입력으로 `COMPATIBLE`이 나왔다. 검사 우회 플래그나 제조사 manifest 삭제는 사용하지 않았다. 이 결과는 보완 방향을 검증한 것이며, 보완을 반영해 재빌드한 실제 system·super에서도 다시 검사해야 한다.

## VINTF 보완 후 최종 후보

`logs/build-20261118-103107.log`의 재빌드는 2시간 11분 29초에 종료 코드 0으로 완료됐다. 새 system의 크기는 이전과 같은 2,272,292,864 bytes이며 SHA-256은 `bc5ff0710896f2ed9cd99843fdbaebe20b864faa78cba29ad211fe7bb6941ca2`다. `e2fsck -fn`이 통과했고, 실제 새 이미지에서 호환성 매트릭스를 추출한 검사도 `COMPATIBLE`이었다.

- 최종 super 후보: `super-lineage21-vintf-expanded.img`
- 크기: 2,684,354,560 bytes
- SHA-256: `4ddd890fbf9e0f595a151e7bac61f81442835dde1f6346365865a30360547db4`
- 양쪽 메타데이터 슬롯: 버전 10.0, 크기 516 bytes, 최대 65,536 bytes, 슬롯 2개
- 그룹 한도: 2,680,160,256 bytes

최종 super를 다시 분리한 system은 새 빌드 원본과 전체 `cmp`가 일치한다. vendor·odm도 현재 기기 백업과 전체 `cmp`가 일치하므로 제조사 파일시스템과 앞서 확인한 해시가 그대로 유지된다. 빌드 대기 후에도 동일한 Rockchip USB 장치가 RAM Loader의 `Maskrom` 상태로 연결돼 있음을 확인했다.

최종 후보의 Mac 전송본도 크기 2,684,354,560 bytes와 위 SHA-256이 일치했다. 준비 검증과 최종 승인을 마쳤으며 실제 적용 결과는 각 기록·재읽기와 부팅 확인 이후 갱신한다.

승인 대상은 시리얼 `PLF02WH_SERIAL` 기기의 super LBA 1,986,560부터 5,242,880섹터, 새 userdata 시작 LBA 7,229,440부터 8섹터, 기본 GPT LBA 0부터 34섹터, 백업 GPT LBA 30,539,743부터 33섹터다. userdata는 첫 부팅에서 새 파일시스템 생성이 필요하며 기존 사용자 데이터는 유지하지 않는다.

데이터 암호화는 기존 vendor 구성에서 꺼져 있고, 이번 system은 `WITH_ADB_INSECURE=true`로 만든 실기 검증용 빌드다. 이 준비가 운영용 보안 검증까지 완료했다는 뜻은 아니다.

## 실기 기록 결과

다음 순서로 기록했으며 각 단계의 기록 성공을 확인한 뒤 재읽기와 전체 `cmp`를 수행했다.

| 기록 대상 | 시작 LBA | 섹터 수 | 재읽기 증거 |
|---|---:|---:|---|
| 최종 super | 1,986,560 | 5,242,880 | `super-readback.img`, 최종 후보와 전체 일치 |
| 새 userdata 초기화 표식 | 7,229,440 | 8 | `userdata-marker-readback.bin`, 4 KiB 표식과 전체 일치 |
| 백업 GPT | 30,539,743 | 33 | `gpt-backup-readback.bin`, 검증한 후보와 전체 일치 |
| 기본 GPT | 0 | 34 | `gpt-primary-readback.bin`, 검증한 후보와 전체 일치 |

super 재읽기 크기는 2,684,354,560 bytes이며 SHA-256은 `4ddd890fbf9e0f595a151e7bac61f81442835dde1f6346365865a30360547db4`로 최종 이미지와 일치한다. boot·부트로더·별도 제조사 파티션에는 기록하지 않았다.

정상 재부팅 명령 `rd`는 `Reset Device OK.`로 완료됐다. 이후 ADB 연결, userdata 재생성 및 Android 첫 부팅 성공을 확인했다.

## 첫 부팅과 기본 동작 결과

- `ro.lineage.version=21.0-20261118-UNOFFICIAL-arm64_bgN`, Android 14 / API 34.
- `sys.boot_completed=1`, `init.svc.bootanim=stopped`.
- Google 초기 설정 화면 표시: `boot-complete.png`.
- userdata는 `/dev/block/by-name/userdata`에서 ext4 읽기·쓰기로 마운트됐다. 최초 확인 당시 `df`는 약 11 GiB, 사용량 12 MiB를 보고했다.
- 화면 800×1280, 밀도 280. ADB 탭으로 언어 선택 창이 열리는 것을 `input-response.png`에서 확인하고 뒤로 돌아왔다. 물리 터치를 직접 시험한 것은 아니다.
- Wi-Fi가 켜져 있고 검색 결과에 AP 22개가 있었다. 인증·인터넷 연결은 시험하지 않았다.
- Bluetooth는 `ON`, 해당 수집 시점의 서비스 충돌 횟수는 0이었다. 주변기기 페어링은 시험하지 않았다.
- Play 서비스·Play Store·Settings·WebView·LatinIME의 설치 경로를 확인했다. Google 로그인과 앱 다운로드는 시험하지 않았다.
- SELinux `Enforcing`, 암호화 상태 `unsupported`, `ro.adb.secure=0`. 암호화와 ADB 인증은 운영용 보안 목표를 충족하지 않는다.

초기 충돌 로그에는 제조사 `/vendor/bin/hw/android.hardware.memtrack@1.0-service`의 SIGABRT 1건이 있었다. `memtrack.rk3399.so`의 `find_dir`에서 `readdir: null DIR*`가 발생했다. 수집한 부팅 완료 시점의 crash 버퍼에는 같은 초기 충돌만 있었으며, 이 충돌을 고쳤다는 뜻은 아니다. GPU 메모리 계측의 별도 후속 조사가 필요하다. vendor를 임의로 수정하거나 SELinux를 끄지 않았다.

오디오·물리 터치·절전·GPU 전체 기능·장기 안정성·복원 시험은 이 설치 확인에서 수행하지 않았다. 계정·네트워크 초기 설정도 완료하지 않았으며 기기는 초기 설정 시작 화면에 있다.

추가 증거는 같은 준비 디렉터리의 `boot-basic-services.txt`, `wifi-scan-results.txt`, `firstboot-crash.log`, `boot-complete-crash.log`에 보관했다. 셸의 sysfs 파티션 필드 읽기는 권한 거부로 중단했으며 다른 권한으로 우회하지 않았다. 기록 경계 증거는 이미 검증한 GPT 후보와 기기 재읽기의 전체 일치다.
