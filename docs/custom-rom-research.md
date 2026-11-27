# 커스텀 롬 제작 조사

조사일: 2026-11-18. 이 문서는 공개 저장소, 문서, 커뮤니티 글을 읽고 정리한 **정적 조사**입니다. 기기에서 직접 측정하거나 시험한 결과는 들어 있지 않습니다. 출처는 [sources.md](sources.md)의 "커스텀 롬 조사" 절에 모아 두었습니다.

## 1. 지금 기기에 올라가 있는 것의 정체

현재 18.1은 [kyseong00 빌더](https://github.com/kyseong00/toss-front-lineageos-builder)의 `Build-PLF02WH.ps1`(마지막 커밋 `8fcad743`, 2026-09-11)이 만든 `super` 이미지입니다. 스크립트를 끝까지 읽고 확인한 구성은 다음과 같습니다.

| 논리 파티션 | 내용 | 크기(bytes) |
|---|---|---:|
| system | AndyYan `lineage-18.1-20240121-UNOFFICIAL-arm64_bvS` GSI를 `resize2fs`로 늘리고, 앱 25개 경로를 지운 뒤 OpenGApps Pico 핵심 구성요소 7개를 넣은 것 | 1,922,445,312 |
| vendor | 순정 vendor에서 `/etc/fstab.rk30board` 한 파일만 교체 | 220,258,304 |
| odm | 순정 그대로 | 585,728 |

- `super` 전체는 2 GiB(2,147,483,648)입니다. 동적 파티션 그룹 `rockchip_dynamic_partitions`는 2,143,289,344이고, 메타데이터 슬롯은 2개입니다.
- 순정 system은 1,381,257,216 bytes였습니다. 빌더가 그룹에 남는 공간을 모두 system에 할당했기 때문에 **1,922,445,312가 vendor/odm을 그대로 둔 상태에서 system이 가질 수 있는 최대치**입니다.
- 커널(`boot`), `vbmeta`, `dtbo`, 부트로더 계열은 순정 그대로이고 쓰지 않습니다. 빌더는 `super` 파티션 하나만 씁니다.

### 빌더가 의도적으로 바꾼 것

**1. 데이터 암호화를 껐습니다.** 교체한 fstab에서 `fileencryption=`과 `dirsync`를 뺐습니다. 주석에는 "순정 커널이 최종 `/data` 마운트에서 `dirsync`를 거부한다", "GSI 호환을 위해 암호화하지 않은 userdata를 쓴다"라고 적혀 있습니다. 검증 단계도 `fileencryption=`이 남아 있으면 실패하도록 짜여 있습니다.

**2. 우리가 유지하려는 기능 일부를 지웠습니다.**
- `Seedvault`: 요구사항 18번 백업·복원
- `DynamicSystemInstallationService`: DSU 시험 경로
- `PrintSpooler`

이 밖에 Contacts, Dialer, messaging, Jelly 등도 삭제 대상입니다. 직접 빌드할 때는 이 목록을 그대로 따르지 말고 요구사항 기준으로 다시 정해야 합니다.

**3. ext4 공유 블록 문제는 다른 도구에서도 확인됩니다.** [TF-Flasher](https://github.com/HITEYY/TF-Flasher)는 `shared_blocks`가 있는 ext4에서 `debugfs rm` 대신 `debugfs unlink`를 쓴다고 명시합니다. 이전 작업에서 첫 가공 이미지가 남겨야 할 파일까지 훼손했던 문제와 같은 원인으로 보입니다.

## 2. 커스텀 롬의 현실적인 형태

PLF02WH 전용 device tree나 커널 소스는 공개된 것을 찾지 못했습니다. 그래서 가장 현실적인 경로는 현재 빌더와 같은 구조를 유지하고 **system 입력만 직접 빌드한 GSI로 바꾸는 것**입니다.

```text
[LineageOS + GSI 패치 소스] --(x86_64 Linux에서 빌드)--> system.img
[순정 super] --lpunpack--> vendor.img(fstab 패치), odm.img
system + vendor + odm --lpmake--> super.img (2 GiB) --> super 파티션만 플래시
```

- 커널, vendor HAL, 드라이버는 순정을 그대로 씁니다. 따라서 Wi-Fi, Bluetooth, GPU 동작 여부는 새 system이 Android 11 vendor 인터페이스를 얼마나 잘 받아 주는지에 달려 있습니다.
- 빌더가 하는 일(lpunpack, fstab 교체, lpmake, 결과 검증)은 Linux/macOS 셸 스크립트로 옮길 수 있습니다. 필요한 도구는 e2fsprogs와 lpmake/lpunpack입니다.

## 3. LineageOS 버전별 부팅 가능성

| 기준 | 내용 | 출처 |
|---|---|---|
| GSI 일반 규칙 | vendor가 Android N이면 최소 N+3 버전 GSI까지는 부팅을 기대할 수 있습니다. 그 이상은 Google이 옛 HAL을 유지하느냐에 달렸고, 서드파티 GSI가 호환 패치를 되돌려 더 올릴 수도 있습니다. | Peter Cai(PeterGSI) |
| 이 기기 | vendor Android 11(VNDK 30) → Android 14 = LineageOS 21까지가 일반 규칙 범위입니다. | device-status.md |
| Android 16 QPR2 | AOSP가 기본으로 커널 5.4 이상의 BPF를 요구합니다. 4.19 이하는 부팅되지 않습니다. 되돌리는 패치(fuck-bpf, 34개)가 있고, 4.19에서 부팅된다고 보고됐습니다. | techyminati/fuck-bpf |
| LineageOS 23.2 GSI | MisterZtr 패치셋에 구형 커널 대응 패치가 들어 있습니다. epoll_pwait2(5.11 미만), MADV_WIPEONFORK(4.14 미만), eBPF 방화벽 맵이 없을 때의 대체 처리, BPF 없는 기기의 restricted networking 비활성화가 그 예입니다. | MisterZtr/LineageOS_gsi |
| LineageOS 24.0 | 구형 커널용 GSI 패치셋은 이번 조사에서 찾지 못했습니다. AndyYan pure GSI는 제작자가 호환 패치 없는 연구용이라고 밝힌 빌드입니다. | sources.md |

### 21과 22의 관리 상태 (2026-11-18, git 얼은 조회)

AndyYan의 21 GSI는 일반 21이 아니라 **pre-QPR2(Android 14 QPR1 기반)** 분기입니다.
- XDA 스레드에 따르면 "Android 14 이하 vendor 기기를 위한 피난처"로 만든 것입니다.
- QPR2 이후 생긴 구형 기기 호환성 문제를 피하고, 보안 패치는 직접 계속 적용합니다.

| 항목 | 21 pre-QPR2 | 22 light |
|---|---|---|
| Android | 14 (QPR1) | 15 |
| 이 기기 vendor(11) 기준 | N+3, 일반 규칙 범위 안 | N+4, 범위 밖 |
| 플랫폼 소스 보안 패치 | `LOS21-pre-QPR2/android` 최신 커밋 2026-11-08 "2026-11 ASB patching" | LineageOS 22 공식 소스 기준 |
| GSI 패치(`lineage_patches_unified`) | light 2026-04-10, td 2026-01-26 | 2025-06-07 이후 갱신 없음 |
| 빌드 스크립트 | 2026-01-26 | 2025-06-21 |
| 변형 | TD(TrebleDroid 전체 패치, 구형 기기 호환성 우선) / light(패치 최소) | light만 |
| 이전에 측정한 배포 이미지 크기 | TD 20261109: raw 2,548,965,376 B | light 20250621: raw 2,383,572,992 B |

주의할 점이 두 가지 있습니다.
- AndyYan 빌드는 **ADB가 기본으로 켜져 있고 인증 없이 열려 있습니다**(제작자가 일부러 그렇게 만듦). 요구사항 20번의 "디버깅 상시 개방은 목표 아님"과 맞지 않으므로, 직접 빌드할 때는 첫 부팅 디버깅이 끝난 뒤 되돌려야 합니다.
- pre-QPR2에서 QPR2 이후 빌드로는 데이터를 유지한 채 업그레이드할 수 없다고 제작자가 밝혔습니다.

**판단:**
- 위험이 낮은 순서는 21 → 22 → 23.2 → 24.0입니다.
- 22 light는 2025-06 이후 관리가 멈췄고, 21 pre-QPR2는 2026-11까지 보안 패치가 이어지고 있습니다.
- 커널 4.19와 Android 11 vendor로 24.0을 부팅시키려면 아직 아무도 공개하지 않은 호환 작업을 직접 해야 할 가능성이 높습니다.
- 24.0은 "기능 검토 기준"으로 두고, 첫 빌드 목표는 21 또는 22(light)로 잡는 편이 현실적입니다. 다만 이것은 추천일 뿐이며, 최종 결정은 사용자가 합니다.

## 4. 용량 문제를 푸는 선택지

이전 조사에서 확인한 크기는 22 light가 2,278,592,512 bytes, 23.2 ext4가 약 2.68 GB였습니다. 둘 다 한도인 1,922,445,312 bytes를 넘습니다. 아래 선택지의 절감량은 모두 **측정하지 않은 값**입니다.

| 선택지 | 내용 | 조건·위험 |
|---|---|---|
| 빌드 단계에서 덜어내기 | 직접 만든 product 구성에서 쓰지 않는 앱을 빼고, vendor가 쓰는 VNDK 30 하나만 남깁니다. crDroid GSI 배포자도 작은 파티션에서는 쓰지 않는 VNDK를 지우라고 안내합니다. | 소스 빌드라서 가공 방식보다 안전합니다. 줄어드는 양은 빌드해 봐야 압니다. |
| ext4 블록 중복 제거 | AOSP 빌드 옵션으로 ext4 공유 블록 이미지를 만듭니다. | 읽기 전용 system에만 적용됩니다. 이후 가공 도구는 `unlink` 방식이어야 합니다. |
| EROFS | 압축 파일시스템이라 크게 줄어듭니다. MisterZtr 23.2는 `bvNE`(erofs) 타깃을 제공합니다. | **2026-11-18 확인 결과 순정 커널에는 EROFS가 없습니다**(`# CONFIG_EROFS_FS is not set`). 쓰려면 4.19 백포트를 넣은 커널을 빌드하고 boot를 바꿔야 하는데, 이 기기용 커널 소스가 필요합니다. 현재는 사실상 제외되는 선택지입니다. |
| super 확장 | 바로 뒤의 userdata(약 11.62 GiB)를 줄이고 super를 키웁니다. | GPT 변경이 필요합니다. 이전에 중단된 경로라 별도 승인이 필요합니다. |
| GApps 정리 | OpenGApps는 Android 11(20220503)에서 멈췄습니다. 14 이상에서는 LineageOS 위키가 안내하는 GApps 패키지를 다시 골라야 합니다. | 크기는 패키지마다 다르니 측정이 필요합니다. |

## 5. 보안 요구사항을 다시 평가한 결과

| 번호 | 현재 상태 | 직접 빌드로 가능한 것 |
|---|---|---|
| 18 백업·복원 | 빌더가 Seedvault를 삭제함 | 빌드에 넣기만 하면 되므로 가능성이 높습니다. |
| 22 데이터 암호화 | fstab에서 의도적으로 끔. 순정 커널의 `dirsync` 거부 문제가 있음 | 커널은 FBE 기능(`FS_ENCRYPTION`, 인라인 암호화, `DM_DEFAULT_KEY`)을 갖추고 있습니다. keymaster는 4.0(HIDL), gatekeeper는 소프트웨어입니다. fstab에 `fileencryption`을 되살리고 새 system의 keystore가 keymaster 4.0과 맞는지 실기에서 시험해야 합니다. 소프트웨어 gatekeeper라서 하드웨어 기반 보호 수준은 기대하기 어렵습니다. |
| 23 부팅 검증·SELinux | 부트로더 잠금 해제 상태. `vbmeta`는 별도 1 MiB 파티션 | 사용자 키로 다시 잠그는 일은 Rockchip 부트로더 지원 범위를 확인해야 하며, 현재 정보로는 범위 밖입니다. SELinux enforcing 여부는 기기에서 확인해야 합니다. |
| 24 OS 업데이트 | 해당 없음 | GSI에는 기본 OTA 경로가 없습니다. 자체 배포와 서명을 만들어야 합니다. |

## 6. 빌드 환경

- LineageOS 위키 기준으로 lineage-21 이상은 **RAM 64 GB**를 권장하고, 공식 테스트 환경은 x86_64 Ubuntu입니다.
- Mac Studio(M1 Max, 32 GB)는 Apple Silicon이고 RAM도 권장치에 못 미치므로 전체 빌드용으로 맞지 않습니다.
- ccache는 50 GB 수준을 쓰는 예가 많고, 소스와 출력까지 합치면 수백 GB의 디스크가 필요합니다.

### 후보 빌드 호스트: SSH `dev`(192.168.0.151), 2026-11-18 읽기 전용 점검

| 항목 | 값 | 판단 |
|---|---|---|
| OS/아키텍처 | Ubuntu 24.04.3 LTS, x86_64 | 빌드 가능한 환경. 위키가 검증한 버전은 20.04이므로 컨테이너로 환경을 고정하는 편이 안전함 |
| CPU | Intel i5-10505, 6코어 12스레드 | 첫 빌드가 길어질 수 있음(미측정) |
| RAM | 31 GiB(점검 당시 가용 약 20 GiB), swap 4 GiB | 권장치 64 GB에 못 미침. 병렬 작업 수 제한과 메모리 상한이 필요 |
| 디스크 | NVMe 233G(여유 96G), `/mnt/storage` HDD(Seagate ST1000DM010, 7200rpm) 916G(여유 726G, 쓰기 가능) | 용량은 HDD가 충분하지만 작은 파일을 대량으로 다루는 빌드에는 느림 |
| 도구 | git, python3, java, docker 있음(docker 그룹 소속). repo, ccache 없음. sudo는 비밀번호 필요 | docker 컨테이너 안에서 빌드 환경을 만들면 호스트 패키지를 설치하지 않아도 됨 |
| 공유 상황 | Harbor 레지스트리, g1-* 서비스, sshow, PostgreSQL 등 컨테이너 20개 이상 운영 중 | 빌드가 메모리나 디스크 입출력을 독점하면 이 서비스들에 영향을 줌. OOM이 나면 다른 프로세스가 죽을 수 있음 |

**결론:** 조건부로 사용할 수 있습니다. 조건은 세 가지입니다.
1. docker 컨테이너에 메모리·CPU 상한을 걸고 빌드합니다.
2. 낙은 우선순위(`nice`/`ionice`)로 돌립니다.
3. 소스는 `/mnt/storage`에 둡니다.

아직 다운로드, 설치, 빌드는 하지 않았습니다.

참고할 빌드 스크립트는 다음과 같습니다.

**AndyYan**
- 저장소: `lineage_build_unified`, `lineage_patches_unified`, `android_device_lineage_gsi`
- 브랜치는 `lineage-22-light`까지 있습니다.
- 실행 예: `bash lineage_build_unified/build_unified.sh treble 64VN 64GN`

**MisterZtr `LineageOS_gsi`(23.2)**
- `repo init -b lineage-23.2`를 한 뒤 `treble_manifest`를 local manifest로 추가하고, 패치를 적용합니다.
- ext4 바닐라 타깃: `breakfast lineage_arm64_bvN4-bp4a-userdebug`, `make systemimage`
- 출력 위치: `out/target/product/tdgsi_arm64_ab`

## 7. macOS에서 백업과 플래시: TF-Flasher

[HITEYY/TF-Flasher](https://github.com/HITEYY/TF-Flasher)는 macOS, Linux, Windows에서 Rockchip 오픈소스 도구인 `rkdeveloptool`(libusb)을 써서 백업, super 패치, 플래시, 복구를 자동화합니다. RKDevTool은 필요하지 않습니다.

- 원래 목적은 순정 펌웨어에서 Toss 앱을 지우는 것입니다. LineageOS용 super를 쓰는 기능은 구성 요소(backup/flash/restore)만 참고할 수 있습니다.
- 이 기기에서 시험한 적은 없습니다. 작성자도 실기기 테스트가 되지 않은 도구라고 밝히고 있습니다.
- `rkdeveloptool`은 Homebrew에 없어서 소스로 빌드해야 합니다. Windows에서는 Rockusb 드라이버가 아니라 WinUSB가 필요합니다.
- 기기 파일에서 DTB를 추출하는 기능이 있습니다. 커널을 다시 빌드하는 경로를 조사할 때 참고할 수 있습니다.

## 8. 기기와 하드웨어 관련 추가 정보

- **사양:** RAM 2 GB(DDR4), 저장장치 16 GB, 7인치 800×1280입니다(나무위키). Android 14 이상에서 RAM 2 GB는 체감 성능과 lmkd 설정에 영향을 줄 수 있습니다.
- **기판 표기(ONEZIN 글):**
  - `RX_3V0`/`TX_3V0`: UART 디버그. 1500000 baud, 3.3V USB-TTL, VCC 미연결
  - `BOOT`/`VCC_1V8`, `RST`, `RECOV`(초기화 버튼), `DM1`/`DP1`
  - 부팅 실패 원인을 보려면 UART 로그가 가장 확실한 수단입니다.
- **같은 PLF02WH라도 개정판에 따라 다릅니다.** 어떤 기기는 초기화 버튼이나 BOOT 쇼트를 하면 Loader가 아니라 **실제 공장 초기화("지우는 중…")**로 들어갔다는 보고가 있습니다. 이 기기에서는 이미 Loader 진입이 확인됐지만, 버튼 조작이 데이터 삭제로 이어질 수 있다는 점은 기억해야 합니다.

## 9. 기기에서 읽은 값 (읽기 전용 ADB)

2026-11-18에 수집을 끝냈습니다. 결과는 [device-status.md](device-status.md)의 "읽기 전용 기기 증거" 절에 있습니다. 사용한 명령은 다음과 같습니다.

```text
getprop ro.vndk.version            # 30 예상
getprop ro.product.first_api_level
getprop ro.board.platform
uname -r                            # 4.19.193 예상
cat /proc/filesystems               # erofs 지원 여부
ls /sys/fs/bpf                      # BPF 파일시스템 존재 여부
getenforce                          # SELinux 상태
getprop ro.boot.verifiedbootstate
cat /proc/meminfo | head -3         # 실제 RAM
```

`/proc/config.gz`가 있으면 PC로 복사해 EROFS와 BPF 관련 커널 옵션을 확인합니다(`adb pull`, 읽기 전용).
