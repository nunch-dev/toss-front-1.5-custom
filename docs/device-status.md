# 기기 상태와 제약

## 현재 상태: LineageOS 21·ADB 인증·FBE 적용

2026-11-18 작업에서 사용자 최종 승인 후 super를 2 GiB에서 2.5 GiB로 확장하고 userdata 시작점을 512 MiB 뒤로 옮겼다. VINTF 보완을 반영한 LineageOS 21 pre-QPR2 GApps를 기록했으며, 전체 재읽기 대조와 Android 14 / API 34 첫 부팅을 확인했다. vendor·odm·boot·부트로더는 보존했다.

설치 당시 userdata는 약 11 GiB로 새로 마운트됐고, Wi-Fi 검색·Bluetooth ON·화면·ADB 입력 반응을 확인했다. 2026-11-19 후속 확인에서 사용자 초기 설정 완료 상태도 확인했다. 이후 사용자 승인으로 ADB 인증 기본값 system과 FBE vendor를 적용했다. 현재 인증은 `ro.adb.secure=1`, 기본 셸은 UID 2000, SELinux는 Enforcing, 암호화 상태는 `encrypted`·`file`이다. 영구 반영 후 재부팅에서 PIN 입력 전 CE 잠금과 입력 후 동일한 파일 해시 복원을 검증했고 임시 진단 파일도 정리했다.

초기 memtrack HAL 충돌은 debugfs 미지원 커널에서 없는 계측 경로를 처리하지 못하는 제조사 코드 문제였다. 최소 수정본을 승인 후 vendor에 영구 반영했으며, 전체 재읽기·재부팅·VTS 3개 통과와 일반 ADB 셸 복귀를 확인했다. 이후 사용자와 실제 오디오 청취·물리 터치·스크롤·화면 절전 복귀를 확인했다. [안정성 검증](stability.md)에 근거를 기록했다. 주변기기 연결·커널 깊은 절전·소비전력·장기 안정성·복원 시험은 남아 있다.

정확한 GPT 경계·이미지 해시·백업 범위·검증 결과는 [super 확장 적용 기록](super-expansion.md)을 기준으로 한다.

최신 system은 2026-11-20 적용한 `system-keliboard-20261119.img`이며 SHA-256은 `4a740c91d8fd3a0dfb4c33fde3a166c7218bf7f49f71629d94d6b711e1407775`다. KeliBoard를 product 기본 앱으로 포함했고 system 두 extent와 LP 메타데이터 기록·전체 재읽기 대조를 통과했다. 최신 vendor는 memtrack 수정·FBE fstab·Keymaster 토큰 길이 교정을 포함하며 SHA-256은 `59c3081a43e147550da9c7784ff3f800bfbc2c818a9951b37cc440e7ad7631c1`다. vendor는 이번에 기록하지 않았고 전체 해시가 유지됐다. 이전 인증 system 해시 `b5b3410b00d605b0137dc7de96d4eb0c47a67bfb231d6146f5b929bb809d7292`와 LP 메타데이터는 원복본으로 보존한다. [보안 검증](security.md)과 [기본 앱 적용](ime-system.md)에 근거를 기록했다.

FBE 잠금 해제 실패의 원인은 vendor Keymaster가 69바이트 인증 토큰의 길이를 8과 비교하던 결함이었다. 비교 상수 한 개를 교정해 무인증 요청 거부·정상 토큰 허용을 검증했다. 이후 별도 승인을 받아 userdata를 유지한 채 수정 vendor를 영구 기록하고 전체 재읽기를 대조했다. 재부팅 후 기존 PIN과 CE 데이터 복원까지 통과했고 SystemUI 재시작·새 충돌도 없었다. 현재 소프트웨어 키 관리 구성의 FBE 적용은 완료했으며, 하드웨어 키 보호·metadata encryption·부트로더 잠금까지 확보한 것은 아니다.

기본 사용 기능 단계에서는 KeliBoard 4.0.1을 일반 앱으로 설치했다. 두벌식 조합·겹받침 삭제·영문 전환, SAF 저장·다시 열기, MTP 양방향 1 MiB 전송과 해시 일치, 런타임 권한 거부·허용에 따른 실제 API 차단·성공을 확인했다. 네트워크 연결 후 DownloadManager 완료 상태와 원본 파일 해시 일치도 확인했다. 진단 앱의 재시작 후 ID 조회 오류는 수정했고 같은 기존 다운로드의 조회까지 통과했다. system·vendor 이미지는 이 단계에서 변경하지 않았다. 상세 결과와 제한은 [기본 기능 검증](basic-features.md)에 기록한다.

후속 기본 앱 통합에서는 KeliBoard가 SYSTEM·UPDATED_SYSTEM_APP으로 등록됐고 기존 설치본과 앱 데이터를 유지했다. 재부팅 후 한영 입력과 “영어(미국)” 표시가 정상이며 CE 시험 파일도 보존됐다. 현재 화면 잠금은 “없음”이고 secure=false다. 사용자가 이번 기록 전에 PIN 설정을 직접 제거했다고 확인했으므로 원래 의도한 상태와 일치한다. 이번 재부팅을 PIN 인증 시험으로 기록하지 않는다. 시험 파일 정리도 완료했다.

## 확장 전 18.1 상태와 조사 기록

사용자 확인(2026-11-18)에 따르면 확장 전 기기의 18.1 설치본에는 [FLOVER124의 PLF02WH 설치 가이드](https://github.com/FLOVER124/toss-front-plf02wh-lineageos-guide)를 기반으로 진행한 작업이 반영돼 있다. 이전 작업 기록에는 18.1 + Pico GApps 빌더를 사용하고 이미지 가공 로직을 후속 수정한 경위가 있다. 정확한 입력 이미지와 수정 내역은 [작업 이력](history.md)과 HOME-PC의 산출물을 대조해야 한다.

아래 항목은 이전 작업 보고와 사용자 확인을 인계한 값이다. 이번에 재측정한 항목은 아래 Mac Studio 실측 절에 기록했다.

- 대상: Toss Front 1.5, PLF02WH, SUNMI p681x, Rockchip RK3399
- 제조사 기반: Android 11 / VNDK 30, 커널 4.19.193 계열, 빌드 673
- 저장장치 사용자 영역: 15,636,365,312 bytes (약 16 GB급)
- 물리 `super`: 2 GiB
- 기존 구성을 유지할 때 조사된 `system` 한도: **1,922,445,312 bytes**
- 현재 super 구성(빌더 스크립트 기준): system 1,922,445,312 / vendor 220,258,304 / odm 585,728 bytes. 그룹 `rockchip_dynamic_partitions` 2,143,289,344 bytes. 순정 system은 1,381,257,216 bytes였습니다. 상세 내용은 [커스텀 롬 제작 조사](custom-rom-research.md)를 보세요.
- vendor의 `/etc/fstab.rk30board`는 빌더가 교체한 것입니다. `fileencryption`과 `dirsync`를 빼서 암호화를 의도적으로 껐습니다.
- 전체 저장장치 여유와 system 이미지 한도는 별개입니다. 압축 다운로드 크기로 설치 가능 여부를 판단하지 않습니다.
- 현재 18.1: 사용자가 부팅·초기 설정 완료 확인. 모든 주변기기와 장기 안정성을 검증했다는 뜻은 아닙니다.
- 부트로더 잠금 해제 상태, 사용자 데이터 암호화 꺼짐. 최신 소스 빌드가 이 상태를 자동 해결하지 않습니다.
- PLF02WH 전용 24.0 device tree 및 현재 커널과 정확히 대응하는 공개 소스: 조사에서 미확인. 부재 확정은 아닙니다.

## 읽기 전용 기기 증거 (2026-11-18, Mac Studio ADB)

수집 방식은 `getprop`, `/proc` 읽기, `adb pull` 입니다. 기기에는 아무것도 쓰지 않았습니다.

원본 파일은 `private/device-evidence/20261118/`에 두었고 Git에서는 제외됩니다.
- `kernel-config.gz`: SHA-256 `50276ae3...3874`
- `vendor-manifest.xml`
- `vendor-compat-matrix.xml`
- `vendor-fstab.rk30board`

| 항목 | 값 | 의미 |
|---|---|---|
| `ro.product.first_api_level` / VINTF `target-level` | 30 / 5 | Android 11 출시 vendor(FCM 5) |
| 커널 | `4.19.193-ab673` | |
| EROFS | `# CONFIG_EROFS_FS is not set`, `/proc/filesystems`에도 없음 | **순정 커널로는 EROFS system 불가.** EROFS를 쓰려면 커널을 다시 빌드해야 함 |
| SquashFS | 꺼짐 | |
| BPF | `BPF_SYSCALL`, `CGROUP_BPF`, `BPF_JIT`, `NETFILTER_XT_MATCH_BPF`, `NET_CLS_BPF` 켜짐. `/sys/fs/bpf` 마운트됨 | 4.19 수준의 BPF는 있음. Android 16 QPR2의 5.4 이상 요구는 여전히 별개 |
| 파일 기반 암호화 커널 기능 | `FS_ENCRYPTION`, `FS_ENCRYPTION_INLINE_CRYPT`, `BLK_INLINE_ENCRYPTION(+FALLBACK)`, `DM_DEFAULT_KEY` 켜짐 | 커널은 FBE를 지원함. 현재 꺼져 있는 것은 fstab 때문 |
| 암호화 상태 | `ro.crypto.state=unsupported` | fstab에 암호화 항목이 없기 때문 |
| keymaster / gatekeeper | `android.hardware.keymaster@4.0::IKeymasterDevice/default`, gatekeeper 1.0 `software` | 하드웨어 TEE가 아닌 소프트웨어 gatekeeper로 보임 |
| 부팅 검증 | `verifiedbootstate=orange`, `flash.locked=0`, `DM_VERITY_AVB` 켜짐 | 잠금 해제 상태 |
| SELinux | `Enforcing` (현재 18.1) | |
| 방화벽 기반 | `IP_NF_IPTABLES`, `IP6_NF_IPTABLES` 켜짐 | 커널 쪽 전제는 있음(root/앱 권한은 별개) |
| RAM | `MemTotal 1,994,156 kB`, `ro.config.low_ram` 없음, ZRAM 커널 지원 | 약 2 GB |
| 보안 패치 | system 2024-01-05, vendor 2024-09-05 | |
| 저장 공간 | `/` 1.7G 중 58M 남음, `/vendor` 210M 가득, `/data` 11G | |
| 로드된 커널 모듈 | `bcmdhd`(Wi-Fi). vendor에는 `8723cs`, `8821cs`, `8822bs`, `mali_kbase`도 있음 | 이 기기의 Wi-Fi는 Broadcom 계열 |
| 화면 밀도 | `ro.sf.lcd_density=280` | |

## 파티션 표 (빌더 BACKUP.md 기준, 512바이트 LBA)

이 기기에서 다시 읽어 대조하기 전까지는 참고값입니다.

| 파티션 | Start | Count | 크기 |
|---|---:|---:|---:|
| EFI_part | `0x00000000` | `0x00002000` | 4 MiB |
| security | `0x00002000` | `0x00002000` | 4 MiB |
| uboot | `0x00004000` | `0x00002000` | 4 MiB |
| trust | `0x00006000` | `0x00002000` | 4 MiB |
| misc | `0x00008000` | `0x00002000` | 4 MiB |
| dtbo | `0x0000A000` | `0x00002000` | 4 MiB |
| vbmeta | `0x0000C000` | `0x00000800` | 1 MiB |
| boot | `0x0000C800` | `0x00014000` | 40 MiB |
| recovery | `0x00020800` | `0x0003C000` | 120 MiB |
| backup | `0x0005C800` | `0x000C0000` | 384 MiB |
| cache | `0x0011C800` | `0x000C0000` | 384 MiB |
| metadata | `0x001DC800` | `0x00008000` | 16 MiB |
| baseparameter | `0x001E4800` | `0x00000800` | 1 MiB |
| super | `0x001E5000` | `0x00400000` | 2 GiB |
| userdata | `0x005E5000` | `0x0173AFC0` | 약 11.62 GiB |

## 백업과 복구

HOME-PC `C:\toss\lineage18-current-backup-20261118`의 현재 eMMC 사용자 영역 백업 두 벌은 이전 작업에서 해시 일치가 기록됐습니다. RPMB와 별도 eMMC boot 영역은 제외입니다. **복원 성공 시험은 하지 않았으므로 롤백 보장이 아닙니다.** 이 프로젝트에는 원본 백업을 복사하지 않았습니다. 백업 삭제·변경 금지.

## USB/방화벽 미해결 사항

HOME-PC에서는 USB ADB 클래스가 노출되지만 기존 ADB 1.0.40이 기기를 나열하지 못했습니다. 사용자는 홈 화면과 USB 디버깅 연결 표시를 확인했습니다. PC 접근·드라이버·오래된 도구 중 원인은 미확정입니다.

**2026-11-18 Mac Studio에서 ADB 인식 성공.**
- 도구: platform-tools adb 1.0.41 / 37.0.0
- USB 정보: VID 0x2207 / PID 0x0006, 제품명 `Phh-Treble vanilla`, ADB 인터페이스 `FF/42/01`
- 처음 `adb devices`는 비어 있었습니다. `adb kill-server` 후 서버를 다시 띄우자 시리얼 `PLF02WH_SERIAL`이 `device`(인증 완료) 상태로 나왔습니다. 공개 기록의 일련번호는 가명입니다. 오래 떠 있던 adb 서버가 원인이었던 것으로 보입니다.
- 읽기 전용 getprop으로 확인한 값:
  - `ro.product.vendor.model=TOSS_Front`, `ro.board.platform=rk3399`, `ro.vndk.version=30`
  - vendor fingerprint `SUNMI/p681x/p681x:11/673/673:user/release-keys`
  - `ro.lineage.version=18.1-20240121-UNOFFICIAL-arm64_bvS`, 커널 `4.19.193-ab673`

SELinux는 Enforcing이고, 커널에 iptables/ip6tables 지원이 켜져 있습니다(위 증거 표 참고). root, 앱의 su 사용 가능 여부, 실제 방화벽 규칙 적용은 여전히 미검증입니다. ADB root와 앱의 root 권한은 동일하지 않습니다.

## Mac Studio 실측 (2026-11-18)

- M1 Max, RAM 32 GiB, macOS 26.6.2 arm64. 작업 볼륨의 가용 공간은 약 35 GiB였다.
- USB 장치 2207:0006에서 ADB 인터페이스 FF/42/01을 확인했다. Platform Tools 37.0.0의 기본 LIBUSB 서버에서는 목록이 비었지만, 같은 실행 파일의 macOS USB 백엔드는 독립 포트에서 두 차례 연결됐다. 재검사 시 기존 서버를 유지하고 빈 로컬 포트에서 `ADB_LIBUSB=0 adb -L tcp:<포트> nodaemon server`를 실행한 뒤 `adb -P <포트> -d shell`로 조회한다. 검사가 끝나면 해당 임시 서버를 종료한다.
- 실기에서 vendor 모델 TOSS_Front, 플랫폼 rk3399, LineageOS 18.1-20240121-UNOFFICIAL-arm64_bvS, Android 11, vendor SDK 및 VNDK 30, 커널 4.19.193-ab673을 확인했다.
- SELinux는 Enforcing, ADB 셸은 uid 2000, ro.crypto.state는 unsupported, ro.boot.verifiedbootstate는 orange였다. iptables와 ip6tables 실행 파일이 있고 앱 권한 및 방화벽 규칙 적용은 미검증이다.
- vendor 기본 VINTF manifest의 target-level은 5이며 HAL 항목은 12개다. 별도 manifest 조각도 있으므로 이 수치는 전체 HAL 수를 나타내지 않는다. super는 mmcblk2p13, system은 dm-0에 연결된다. 셸의 sysfs 크기 조회는 권한 거부로 끝나서 위 용량은 이전 기록을 유지한다.
- Mac의 11월 17일 전송 manifest 1,986개 항목에서 최종 18.1 super 해시와 일치하는 항목은 없었다. 로컬 `~/Tools/toss-front/super-completion-20261117-0N3Xeh/super.img`의 SHA-256은 `82b0418267b2c79551ad17cf6d5cd14abd6fe692a719334ce8e2a468047ec923`로 해당 manifest와 일치했다. 최종 가공본과 빌더 수정본은 HOME-PC 대조가 남아 있다.

## 금지할 추정

- 18.1 부팅 성공 → 24.0 부팅 보장
- 같은 RK3399 → 다른 보드 ROM 호환
- 파티션 확장 → 최신 OS 호환 해결
- GApps 설치 → Play 인증 보장
- 백업 존재 → 반드시 복구 가능
- OS 패치 날짜 → 기존 커널·vendor 보안까지 최신

## 커스텀 GSI 비교에 사용할 실기 자료 (2026-11-18)

현재 vendor는 `SUNMI/p681x/p681x:11/673/673:user/release-keys`이며 최초 API 30, Treble 활성, arm64 및 32비트 ARM ABI를 보고한다. 동적 파티션을 사용하며 실기에서 system, vendor, odm이 각각 dm-0, dm-1, dm-2의 ext4로 마운트됐다. 실행 중인 커널의 /proc/filesystems에는 ext4가 있고 EROFS는 보이지 않았다.

[vendor VINTF 원본](../tests/fixtures/plf02wh/vendor/etc/vintf)은 실기에서 읽은 기본 manifest, HAL 선언 조각 12개, 기기 호환성 매트릭스 총 14개다. 각 파일의 XML 구문을 확인했다. 기본 선언에는 audio 6.0, graphics composer 2.1, mapper 4.0, keymaster 4.0이 있고 조각에는 Wi-Fi 1.4와 Rockchip 전용 HAL이 있다. HAL 선언은 주변장치 동작 시험을 대신하지 않는다. 현재 시스템에는 compatibility_matrix.5.xml이 있다.

Mac의 11월 17일 super.img 논리 파티션 메타데이터에서 파일 크기 2,147,483,648 B, 그룹 한도 2,143,289,344 B, vendor 220,258,304 B, odm 581,632 B를 확인했다. 그 파일에는 product와 system_ext도 있다. 그룹 한도에서 vendor와 odm을 단순 차감하면 1,922,449,408 B로, 기존 기록의 system 한도 1,922,445,312 B보다 4,096 B 크다. 공개 빌더가 가정한 odm은 585,728 B로 이 백업보다 정확히 4,096 B 크다. 빌더의 system 입력 크기(1,381,257,216 B)도 이 백업의 system(1,337,540,608 B)과 다르다. 따라서 이 백업으로 빌더 입력을 그대로 대체할 수 있다고 판단할 근거가 없다. 빌드 예산에는 기존의 작은 값을 사용한다. 이는 세 파티션 구성의 예산이며 실제 새 이미지의 배치·정렬·파일시스템까지 검증해야 한다.
