# PLF02WH 안정성 검증

## 기준본과 조사 범위

기준본은 [super 확장 적용 기록](super-expansion.md)의 LineageOS 21 pre-QPR2 GApps다. 사용자 요청에 따라 안정성, 보안, 기능 순서로 진행한다. 이 문서는 안정성 단계의 근거와 미완료 사항을 기록한다.

## memtrack 충돌

### 실기에서 확인한 원인

사용자 승인 후 일시적으로 ADB root를 사용했다. SELinux는 계속 Enforcing이었다.

- 제조사 라이브러리: `/vendor/lib64/hw/memtrack.rk3399.so`, 11,920 bytes.
- SHA-256: `6a01a602e8b8f1aa8fd4343384f37d2bdca815b538f31c48e11a31850e78da85`.
- BuildId: `c341cffd689490bd93f342b571144663`. 최초 충돌 기록과 일치한다.
- HAL은 UID/GID 1000, `u:r:hal_memtrack_default:s0`에서 실행된다.
- 실제 커널 설정은 `# CONFIG_DEBUG_FS is not set`이며 현재 `/proc/filesystems`에도 debugfs가 없다.
- `/sys/kernel/debug` 경로 자체가 없다. SELinux 거부 때문에 HAL이 경로를 읽지 못한 사례와 구분된다.

기존 Android VTS의 `PerInstance/MemtrackHidlTest.BadPidTest/0_default`를 실행하자 `ret.isOk()`가 false여서 실패했다. 같은 시점에 HAL에 부착한 strace에서 다음 순서를 확인했다.

```text
openat(AT_FDCWD, "/sys/kernel/debug/mali0/ctx", O_RDONLY|O_CLOEXEC|O_DIRECTORY) = -1 ENOENT
SIGABRT
```

실기 `find_dir`의 0x11c4에서 `opendir`를 호출한 뒤, NULL 검사 없이 0x11d4에서 `readdir`를 호출한다. 따라서 계측 경로 부재가 프로세스 종료로 이어진다. 단순히 root로 실행하거나 SELinux를 끄는 방식으로 해결할 문제가 아니다.

### 수정 범위와 상태

공개 기반은 TinkerBoard-Android의 `rockchip-android-hardware-rk29-libmemtrack` 커밋 `c591424c9c90a115d5498a19551fa40fb79bab81`이다. 해당 코드의 함수와 오류 처리 흐름이 실기 바이너리와 일치한다. 소스는 Apache-2.0이며 원 저작권 표기를 보존했다.

[최소 수정 패치](../patches/plf02wh-memtrack.patch)는 디렉터리 열기 실패를 즉시 반환하고, 검색 오류의 errno가 `closedir`로 덮이지 않도록 보존한다. 디렉터리가 있지만 해당 PID의 GPU 문맥이 없는 정상 경우와, 계측 경로 자체가 없는 오류를 구분한다. 레코드 개수만 조회하는 호출과 정상 계측 경로는 유지한다.

[Android 빌드 설정](../configs/plf02wh/memtrack/Android.bp)으로 수정 라이브러리만 빌드했다(8분 19초, 종료 0). 크기는 134,272 bytes, SHA-256은 `2b981d0268ad5c44905d909cb91625c7cf48811e3d5cc1db0fbf0443e436e23b`다.

실기에서 원본을 덮어쓰지 않는 임시 bind mount로 비교했다. 수정본은 기존 VTS의 `BadPidTest`, `BadTypeTest`, `GetMemoryTest`를 모두 통과했다. 임시 마운트를 해제하고 원본으로 되돌리자 `BadPidTest`가 다시 같은 오류로 실패했다. 따라서 원본 실패 → 수정본 통과 → 원본 실패를 확인했다.

임시 비교 후 원본 HAL의 실행을 확인하고 임시 파일과 진단 디렉터리를 제거했다. 이후 아래 승인 절차를 거쳐 수정본을 영구 반영했다.

이 수정은 충돌을 없애기 위한 것이다. 커널에 없는 GPU 메모리 계측 기능을 복원하거나 실제 GPU 메모리 사용량을 검증한 결과가 아니다. 계측이 실패한 값을 임의의 정상 수치로 만들어 반환하지 않는다.

### 증거

`private/stability-20261118/`에 다음을 보관한다.

- `root-runtime.txt`: 실기 HAL 도메인·자격·마운트 정보.
- `memtrack.rk3399.so`: 진단용 원본 복사.
- `VtsHalMemtrackV1_0TargetTest`: 기존 Android 소스로 빌드한 테스트.
- `vts-baseline.txt`: 수정 전 VTS 실패.
- `memtrack-vts-open.trace`: 실제 경로의 ENOENT와 SIGABRT.
- `vts-fixed.txt`: 수정본의 VTS 3개 통과.
- `vts-restored-baseline.txt`: 원본 복귀 후 동일 실패.
- `memtrack-open.trace`: 최초 dumpsys 시도. HAL 파일 열기가 없어 유효한 재현으로 취급하지 않는다.

자료 수집과 비교 검증을 마친 뒤 일반 ADB 셸(`uid=2000`, `u:r:shell:s0`)과 SELinux Enforcing 복귀를 확인했다. `/data/local/tmp/plf02wh-memtrack-diag/`의 두 임시 파일과 디렉터리를 제거했다.

### 영구 반영 후보와 원복본

Mac의 같은 증거 디렉터리에 각각 220,258,304 bytes의 다음 이미지를 보관했다. 서버 생성본과 전송본의 해시가 일치한다.

| 파일 | SHA-256 |
|---|---|
| `vendor-original.img` | `3f25245fac06f2fa50d9ce964b7754f4316a78d749f2a1bd2a8826f05e5d34c4` |
| `vendor-memtrack-fixed.img` | `86744338a7647414064b087a293ae845f40b091b2ea2f3a243ffc1e2b5bf1d8c` |

후보에서 변경한 파일은 `/lib64/hw/memtrack.rk3399.so` 하나다. UID/GID 0, mode 0644, 원래 `security.selinux` 값 26 bytes를 보존했다. 후보에서 재추출한 라이브러리가 실기 VTS를 통과한 빌드와 전체 일치하고, xattr도 원본과 전체 일치한다. `e2fsck -fn`은 종료 0으로 통과했다.

원본 대비 변경된 4 KiB 블록은 0, 32811, 47014, 47015, 47016 다섯 개뿐이다. 각각 파일시스템 슈퍼블록, 대상 inode 1356의 블록, 대상 파일의 데이터 블록 세 개다. 같은 inode 블록의 다른 inode 바이트는 동일하다. 슈퍼블록 변경은 마지막 쓰기 시각과 누적 쓰기량(34 → 38 KiB)뿐이다. 초기 대조에서 누적 쓰기량 필드를 빠뜨려 검사가 실패했으며, e2fsprogs 헤더의 `s_kbytes_written` 정의를 확인한 후 두 필드만 허용해 다시 대조했다.

실기 반영 시 바뀌는 범위는 super 안의 vendor 단일 extent다. 현재 메타데이터에서 vendor는 super 상대 LBA 4,442,112부터 430,192섹터이며, 디스크 절대 LBA는 **6,428,672부터 6,858,863까지**다. GPT·system·odm·boot·userdata는 수정 대상이 아니다.

2026-11-19 사용자가 “승인할게”라고 답해 이 범위의 기록·재부팅·VTS 재검증을 승인했다. 승인 뒤 대상 시리얼과 기존 ROM을 확인하고 검증된 RAM Loader에 진입했다. 쓰기 직전 GPT와 super 메타데이터 첫 1 MiB가 기존 확장 기준본과 일치했고, vendor 전체도 원복본과 일치했다.

vendor 기록 후 전체 재읽기 `vendor-after-write.img`가 후보와 일치했고 SHA-256도 `86744338a7647414064b087a293ae845f40b091b2ea2f3a243ffc1e2b5bf1d8c`로 일치했다. 정상 재부팅 뒤 `sys.boot_completed=1`, `user_setup_complete=1`, HAL `running`을 확인했다. 같은 VTS 3개가 다시 모두 통과했다(`vts-permanent.txt`). 부팅 직후와 VTS 이후 crash 버퍼 수집 파일은 모두 0 bytes였다. 이 검사는 장기 무충돌을 보장하는 것은 아니다.

임시 VTS 파일과 디렉터리를 제거하고 ADB 일반 셸(`uid=2000`, `u:r:shell:s0`) 및 SELinux Enforcing 복귀를 확인했다. GPT·system·odm·boot·userdata에는 기록하지 않았다.

문제가 생겨 Loader에 접근할 수 있다면 보관한 원본 vendor를 같은 범위에 복원한다. 실제 복원 시험과 부팅 불가 상태에서의 수동 복구 진입은 여전히 미검증이다.

## 오디오·물리 터치·화면 절전 확인

2026-11-19 사용자 실기 확인을 함께 진행했다.

- 사용자가 설정을 직접 열고 스크롤한 뒤 “터치·스크롤 정상”으로 답했다. `/dev/input/event2`의 실제 `BTN_TOUCH DOWN`과 `ABS_MT_TRACKING_ID` 이벤트도 수집했다.
- 사용자가 알림음 미리듣기를 한 뒤 “정상적으로 들림”으로 답했다. 이후 AudioFlinger의 출력 경로에서 `writeErrors=0`, `underruns=0`, `overruns=0`을 확인했다.
- 명시적인 화면 절전 요청 후 디스플레이 OFF, `mWakefulness=Dozing`, 표시·wake lock suspend blocker 해제를 확인했다.
- 깨우기 요청 후 디스플레이 ON, `mWakefulness=Awake`, `mHalInteractiveModeEnabled=true`, 터치 매퍼 DIRECT, viewport `isActive=[1]`을 확인했다.
- 사용자가 복귀한 화면을 직접 조작한 뒤 “화면·터치 모두 정상”으로 답했다.

증거는 `physical-touch-events.txt`, `audio-after-listening.txt`, `display-sleep-verified.txt`, `power-sleep-verified.txt`, `display-resume-verified.txt`, `power-resume-verified.txt`, `input-resume-verified.txt`다.

확인한 절전 범위는 화면 꺼짐·복귀와 그 뒤의 조작이다. `suspend_control_internal`의 전체 덤프와 `--suspend_controls` 덤프는 `FAILED_TRANSACTION`으로 완료되지 않았다. 호출 전후 서비스 PID는 같았다. **커널의 깊은 절전 진입·소비전력·장시간 반복 안정성은 이 결과로 확인된 것이 아니다.** 이 제한을 남기고 다음 보안 조건 검토로 진행한다.
