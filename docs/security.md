# PLF02WH 보안 조건 검토

## 현재 실측 상태

2026-11-19 보안 변경의 영구 반영과 재부팅 검증 후 상태다.

| 항목 | 현재 값 |
|---|---|
| ADB 인증 | 설치 이미지 기본값 1, 재부팅 후 `ro.adb.secure=1` 확인 |
| 기본 ADB 셸 권한 | `ro.secure=1`, 일반 셸 UID 2000 |
| 디버그 허용 | `ro.debuggable=1`, userdebug |
| Wi-Fi ADB | `adb_wifi_enabled=0`, TCP 포트 속성 비어 있음 |
| 사용자 데이터 암호화 | `ro.crypto.state=encrypted`, `ro.crypto.type=file` |
| 부트로더 | `ro.boot.flash.locked=0`, verified boot orange |
| SELinux | Enforcing |
| 서명 유형 | test-keys |

ADB 인증 기본값과 현재 소프트웨어 키 관리 구성의 FBE 적용을 완료했다. 재부팅 후 PIN 입력 전에는 DE 키만 존재하고 CE 키·파일은 접근할 수 없었으며, 기존 PIN 입력 후 CE 키와 시험 파일의 동일 해시가 복원됐다. 임시 도구·라이브러리·시험 파일을 제거하고 일반 셸 UID 2000·Enforcing·인증 1로 복귀했다. 하드웨어 키 보호, metadata encryption, rollback resistance, 부트로더 잠금은 이 결과에 포함되지 않는다.

사용자는 현재 보존할 데이터가 없다고 답했다. 이는 실제 초기화에 대한 승인이 아니며, 초기화가 필요한 변경은 별도로 범위와 복구 방법을 제시한다.

## ADB 인증

인증을 끄는 경로가 여러 곳에 있다.

- 프로젝트 `scripts/build-host/in-container.sh`의 재개 빌드는 `WITH_ADB_INSECURE=true`를 전달한다.
- 상위 `lineage_build_unified/build_unified.sh`의 systemimage·target-files 빌드도 같은 변수를 전달한다.
- `device/phh/treble/base.mk`와 `system.prop`에 `ro.adb.secure=0`이 직접 들어 있다.
- `vendor/lineage/config/common.mk`는 `ifdef WITH_ADB_INSECURE`로 판단하므로 **false 문자열을 대입해도 인증이 비활성화된다**.

영구 수정에서는 선택 제품의 위 경로를 일관되게 정리하고 실제 완성 이미지의 속성을 검사해야 한다. 중복 속성 허용이나 광범위한 SELinux 허용으로 우회하지 않는다.

[인증 기본값 패치](../patches/plf02wh-adb-auth.patch)와 빌드 스크립트 변경을 준비했다. 제품 구성 덤프에서 `WITH_ADB_INSECURE=true`를 전달해도 `lineage_arm64_bgN`은 `ro.adb.secure=1`만 생성했다. 기존 vanilla 제품 `lineage_arm64_bvN`은 종전 값 0을 유지했다. 프로젝트 안의 원본 사본에 대한 패치 dry-run과 빌드 스크립트 `bash -n`도 통과했다.

vendor 이미지 내부 `/build.prop`의 첫 추가 조회는 거부돼 중단했다. 외부 서버 경로·조회 목적·읽기 전용 범위를 설명한 뒤 사용자가 “허용할게”라고 재승인했다. 승인한 ADB·USB 속성 네 종류를 조회한 결과 일치 항목은 없었다. 다른 경로로 거부된 조회를 우회하지 않았다.

이후 기존 자원 제한으로 dev 서버에서 새 system 이미지 빌드를 실행했다. 2시간 13분 46초 뒤 종료 코드 0으로 완료됐다. 사용자 승인 후 system 기록·전체 재읽기 대조·재부팅 후 인증 유지 검증을 마쳤다.

### 인증 기본값 이미지 검사

- 서버 산출물: `home/build-output/lineage-21.0-20261119-044304-UNOFFICIAL-arm64_bgN.img`
- 크기: 2,272,292,864 bytes. 현재 system extent와 같아 파티션 확장이 필요 없다.
- SHA-256: `b5b3410b00d605b0137dc7de96d4eb0c47a67bfb231d6146f5b929bb809d7292`
- 읽기 전용 `e2fsck -fn`: 종료 0.
- 실제 `/system/build.prop`: `ro.adb.secure=1`, `ro.secure=1`, `ro.debuggable=1`.
- VNDK30: `/system/system_ext/apex/com.android.vndk.v30.apex` 및 펼쳐진 디렉터리를 확인했다.
- 실제 이미지의 system·system_ext VINTF 선언과 기존 vendor·odm 선언, 커널 4.19.193 설정, 최초 API 30을 사용한 검사: `COMPATIBLE`, 종료 0. 부팅 후 동적 APEX 상태는 실기 검증 대상이다.

첫 VINTF 실행은 `--rootdir` 인자를 줬는데도 경로 누락으로 종료 64였다. 현재 `system/libvintf/check_vintf.cpp`는 dirmap을 먼저 계산한 뒤 rootdir을 args에 추가하므로 그 값이 검사에 전달되지 않는다. 파티션별 `--dirmap`을 명시해 같은 입력으로 통과했다. 이 검사 도구의 소스는 수정하지 않았다.

검사 로그는 `private/security-20261119/adb-auth-image-check.txt`와 `adb-auth-vintf-mapped-check.txt`에 보관했다. 보존한 부팅 성공 super에서 system만 분리한 `system-rollback.img`도 기존 SHA-256 `bc5ff0710896f2ed9cd99843fdbaebe20b864faa78cba29ad211fe7bb6941ca2`와 일치했다.

Mac으로 전송한 `private/security-20261119/system-adb-auth.img`의 SHA-256도 서버 산출물과 일치했다.

기록 후보 범위는 system의 물리 LBA 1,988,608부터 4,438,072섹터다. 실제 기록 전 GPT·LP 메타데이터가 보관한 배치와 같은지 확인한다. 같은 범위에 원복 이미지를 기록하면 기존 system으로 돌아갈 수 있지만, Android가 부팅되지 않는 상태에서 수동 Loader 진입은 아직 검증하지 않았다. vendor의 memtrack 수정은 이 범위 밖이다. 사용자가 system에만 기록하고 재부팅하며 userdata를 초기화하지 않는 범위에 “승인할게”라고 답했다. 이 승인은 FBE vendor 기록·userdata 초기화를 포함하지 않는다.

기록 전 RAM Loader에서 양쪽 GPT와 super 첫 1 MiB를 읽어 보존한 확장 배치와 바이트 단위로 대조했다. 모두 일치했다. 초기 Loader 감시는 실제 출력에 없는 `Mode=Loader`를 기다려 만료됐지만 직접 조회에서 Loader를 확인했다. 이후 실제 출력에 맞춰 Maskrom 전환을 확인하고 기존 RAM Loader를 올렸다.

system의 LBA 1,988,608–6,426,679 기록은 종료 0으로 끝났다. 같은 범위의 2,272,292,864 bytes를 전부 다시 읽어 후보와 `cmp`가 일치했고 SHA-256도 `b5b3410b00d605b0137dc7de96d4eb0c47a67bfb231d6146f5b929bb809d7292`였다. GPT·vendor·odm·boot·userdata에는 기록하지 않았다. 정상 재부팅 명령을 실행했으며 증거는 `private/security-20261119/auth-flash/`에 보관했다.

재부팅 후 기존 승인 호스트가 자동으로 연결됐고 `sys.boot_completed=1`, 일반 셸 UID 2000, Enforcing, `ro.adb.secure=1`, `ro.secure=1`, `ro.debuggable=1`, `user_setup_complete=1`이었다. memtrack·SurfaceFlinger·audioserver는 running, boot animation은 stopped였다. Settings·SystemUI·Trebuchet·Google Play services가 존재했고 Wi-Fi·Bluetooth 설정은 켜짐을 유지했다. 부팅 후 crash 버퍼는 비어 있었으며 실제 잠금 화면도 정상 표시됐다. 이미지 적용으로 사용자 초기 설정을 다시 요구하는 상태로 돌아가지 않았다. 화면의 Google 추가 설정 알림은 남아 있으며 계정 설정 완료를 뜻한다고 해석하지 않는다.

현재 `AdbService`는 인증 관리자를 생성하며 실기 `dumpsys adb`도 관리자의 연결을 보고한다. adbd는 시작할 때 `ro.adb.secure`를 읽는다. 기기에 있는 `resetprop_phh`로 메모리상의 속성만 바꾸는 사전 시험을 검토할 수 있다. 이 경우 adbd 재시작으로 연결이 끊기고 사용자의 기기 화면 승인이 필요하다. 현재 ROM은 부팅 시 인증 비활성 설정을 다시 읽으므로 이 시험을 영구 적용으로 취급하지 않는다.

완료 기준은 속성값만이 아니라 미승인 연결의 셸 차단, 화면 승인 후 정상 연결, 기본 일반 셸 권한, 영구 반영 후 재부팅에서도 인증 유지다. 호스트 개인키를 읽거나 문서에 기록하지 않는다.

## 사용자 데이터 암호화

현재 최초 API는 실측 30이다. 커널 설정에는 ext4/fscrypt, AES-XTS·CTS, HMAC·SHA512, inline encryption 기반, dm-default-key가 있다. 따라서 우선 검토 후보는 `fileencryption=aes-256-xts:aes-256-cts:v2`다. 다만 설정 심볼만으로 실제 fscrypt v2 ioctl 동작을 증명하지 않는다.

FBE와 metadata encryption은 별개다. 후자는 vold의 키 디렉터리와 dm-default-key 형식까지 확인해야 한다. 기존 fstab의 `/metadata` 마운트만으로 metadata encryption이 켜지는 것은 아니다.

`tools/security-probe/`의 읽기 전용 도구를 빌드해 실기 `getHardwareInfo`를 조회했다. 결과는 `security_level=0`, `name=SoftwareKeymasterDevice`, `author=Google`이다. 대상 HAL 정의에서 0은 SOFTWARE다. 실행 중인 프로세스도 `libpuresoftkeymasterdevice.so`를 로드하고 있으며 Gatekeeper는 `android.hardware.gatekeeper@1.0-service.software`다. 키 생성·삭제 API는 호출하지 않았다.

`/dev/tee0`와 `/dev/teepriv0`는 있으나 현재 vendor의 일반적인 `tee-supplicant`, `libteec`, `optee_armtz` 경로에서는 대응 구성요소를 찾지 못했다. 따라서 하드웨어 자체에 TEE가 없다고 단정하지 않지만 **현재 키 관리 경로가 하드웨어 보호를 제공한다고 볼 수 없다.** FBE 속성만 켜서 키 보호까지 완료됐다고 주장해서는 안 된다.

추가 읽기 전용 조사에서도 PLF02WH/p681x의 현재 secure firmware에 바로 적용할 수 있다고 검증된 HAL·TA 조합은 찾지 못했다. 공개 RK3399 SDK와 OP-TEE 연동 예제는 참고 구현이며, 이 기기의 서명 키·프로비저닝·보안 저장소와의 호환성을 증명하지 않는다. 기존 프로젝트 이력만으로는 소프트웨어 키 관리의 출처를 확정하지 못해 아래 백업 비교를 추가했다.

### 승인된 외부 백업 비교

사용자에게 목적을 설명하고 “진행해봐” 승인을 받은 뒤 `/Users/nunch/Tools/toss-front`의 백업 기록을 읽었다. 사용자 데이터와 개인키는 제외했다. 분석은 로컬에서 수행했으며 백업을 다른 서버로 보내지 않았다.

11월 17일 `super-completion-20261117-0N3Xeh/super.img`는 2 GiB이며 manifest에 `COMPLETE_DOUBLE_READ_VERIFIED`, 256개 연속 청크로 기록돼 있다. 다시 계산한 SHA-256 `82b0418267b2c79551ad17cf6d5cd14abd6fe692a719334ce8e2a468047ec923`이 기록과 일치했고 LP geometry·header·tables 체크섬도 유효했다.

vendor·odm만 프로젝트 내부 분석 사본으로 분리했다. 백업 vendor의 SHA-256은 `20f48254caedab061e871ccd5a6f85b8e18dc5d138ec06016f1c078175eb1915`다. odm은 현재와 같은 `bb5e3c11dbbdde1a6ebfa59b1148f56722aa38735a189c77b14805fe0ba02fdb`였다.

백업의 Keymaster·software Gatekeeper 실행 파일, 관련 라이브러리 5개, init 선언 2개, VINTF 선언 2개 등 11개 파일이 현재 vendor와 바이트 단위로 같았다. 대소문자 구분 없이 조사한 백업 vendor/odm 목록에서도 대응하는 TEE 클라이언트·TA 구성을 찾지 못했다. 이름이 `bin/tee`인 항목은 TEE 키 관리 서비스의 증거로 취급하지 않는다.

백업 fstab은 현재와 달랐으며 실제 ext4 userdata 행에 `fileencryption=software`가 있었다. 따라서 이 백업 기준으로는 소프트웨어 키 관리가 이미 존재했고, 커스텀 과정에서 하드웨어 키 관리가 빠졌다는 증거는 없다. 이는 제조사 정식 배포본을 별도로 인증했다는 뜻은 아니다. 원본의 파일 암호화 설정과 하드웨어 키 보호 부재를 구분해야 한다.

원본은 변경하지 않았으며 비교 경계·파일별 해시는 `private/stock-comparison-20261119/comparison.json`에 보관했다.

도구는 제품 설치 대상에서 제외했다. 첫 Make 별칭 빌드는 비설치 모듈의 Make 숨김 규칙 때문에 실패했고, 실제 출력 타깃을 사용했다. 정적 HIDL 바인딩의 libcutils·liblog 링크 의존성을 추가한 뒤 빌드가 통과했다. 도구 SHA-256은 `c2eb5b9cfcfa388e0012e02f17042e227c4a5dda71e8aeef3c6e25317f2e5d01`이며, 실행 결과는 `private/security-20261119/keymaster-info.txt`에 보관했다.

기존 비암호화 디렉터리에 파일이 있으면 FBE 정책을 단순히 추가할 수 없다. 파일시스템의 encrypt 기능 비트 추가는 기존 파일의 암호화 이관이 아니다. 실제 전환 전에 격리된 파일시스템에서 v2 정책·키 추가/제거·재설치·재마운트를 확인하고, 필요 시 별도 승인한 새 포맷을 계획한다.

격리 진단용 Google fscryptctl 소스 사본은 `private/fscryptctl-source/`에 확보했고 파일별 해시는 `source-manifest.json`에 기록했다. 릴리스 태그는 확인되지 않았으므로 소스의 버전 문자열을 검증된 릴리스로 취급하지 않는다. 비설치 Android 진단 모듈은 7분 58초에 종료 0으로 빌드됐다. 실행 파일은 135,008 bytes이며 SHA-256은 `513c38ca05f3cee0a5108e06caffddb23d65d390e647a2a6263ced1fdf45216d`다. Mac 전송본과 일치했고 실기에서 `snapshot-c87bbafe4056`을 출력했다.

시험은 전용 임시 디렉터리 안의 일반 이미지 파일을 포맷하고 그 파일에 연결한 loop 장치만 대상으로 한다. 실제 userdata 블록 장치나 `/data` 마운트를 바꾸지 않는다. 폐기 가능한 시험 키로 AES-256-XTS·AES-256-CTS v2 정책을 적용한 뒤 파일 읽기, 키 제거 후 접근 차단, 같은 키 재추가 후 복원과 재마운트를 확인한다. 키 제거 명령의 종료 코드만으로 성공을 판단하지 않고 `key_status`의 `Absent` 상태를 확인한다. 종료 시 시험 마운트·loop 연결을 먼저 해제하고 임시 파일을 제거하며 일반 ADB 권한으로 돌아온다. 이 시험의 통과는 커널의 파일 암호화 기능에 대한 증거이며 하드웨어 키 보호의 증거는 아니다.

### 격리 fscrypt v2 실기 결과

`/data/local/tmp/plf-fbe-test/scratch.img`에 64 MiB 일반 파일을 만들고 ext4의 `encrypt` 기능을 활성화했다. `/dev/block/loop0`의 backing file과 시험 마운트의 실제 장치가 이 파일임을 확인한 뒤 시험했다. SELinux는 계속 Enforcing이었다.

| 검사 | 관찰 결과 |
|---|---|
| v2 키 추가 | 성공, 32자리 키 식별자 반환 |
| 빈 디렉터리 정책 적용 | version 2, AES-256-XTS / AES-256-CTS, PAD_32 |
| 키가 있는 상태의 쓰기·읽기 | 시험 문자열 일치 |
| 키 제거 | `Absent` 확인 |
| 키 없는 파일 접근 | 원래 이름은 보이지 않고 암호화된 이름으로 읽어도 `Required key not available`, 종료 1 |
| 같은 키 재추가 | 같은 식별자 반환, 원래 파일 내용 복원 |
| 마운트 해제 후 재연결·재마운트 | 정책 유지, 키는 `Absent`, 파일 접근은 ENOKEY로 차단 |
| 재마운트 뒤 같은 키 추가 | 원래 파일 내용 복원 |
| 마운트 해제한 이미지의 원시 바이트 | 시험 평문 문자열과 `payload.txt` 모두 검색되지 않음 |

첫 재마운트는 `Invalid argument`로 실패했다. 직후 loop0 조회에서 `No such device or address`, backing-file 속성 부재, 커널의 superblock 읽기 실패를 확인했다. 마운트 해제 뒤 loop 연결도 없어졌으므로 같은 시험 파일을 다시 연결했고 재마운트가 성공했다. 파일시스템이나 정책을 다시 만들지 않았다.

시험 마운트 해제와 해당 이미지의 loop 연결 부재를 확인한 뒤 시험 키·기기 내 이미지·실행 파일·디렉터리를 제거했다. 일반 셸 UID 2000, Enforcing, 임시 ADB 인증 1, 부팅 완료 1로 복귀했다. 실제 userdata는 여전히 `ro.crypto.state=unsupported`다.

시험 이미지 사본은 `private/security-20261119/fscrypt-v2-scratch.img`에 보관했으며 SHA-256은 `4943f2b7fe3bb69e9fc53008aa5ec30c912547225acf0ec604b1ff22133f2af4`다. 폐기한 시험 키는 호스트로 복사하지 않았다. 결과 기록은 `fscrypt-v2-results.txt`에 있다.

이 결과로 현재 커널의 기본 v2 파일 암호화 동작은 확인했다. Android vold의 실제 사용자 키 생성·부팅 시 DE/CE 해제·화면 잠금 연동, metadata encryption, 하드웨어 키 보호는 이 시험에 포함되지 않았다. 실제 userdata 전환은 별도 승인과 검증이 필요하다.

현재 소스의 `system/vold/Keystore.cpp:106–150`도 확인했다. vold는 Keystore2에 TRUSTED_ENVIRONMENT 수준을 요청하지만, 같은 코드의 주석은 실제 TEE가 없으면 Keystore2가 SOFTWARE 인스턴스를 그 인터페이스로 제공한다고 명시한다. 따라서 이 요청의 성공만으로 하드웨어 보호를 판정할 수 없다. 키는 BLOB 도메인과 vold namespace 100에서 생성한다. `system/vold/KeyStorage.cpp:119–135`는 AES-256-GCM 키 저장 키를 만들며 rollback resistance가 실패하면 그 태그 없이 재시도한다. 이 경로는 현재 소프트웨어 구현으로 Android FBE를 연동할 가능성을 뒷받침하지만 실제 vold 키 생성 성공을 검증한 것은 아니다. 기존 사용자 키를 조회하거나 생성·삭제 API를 호출하지 않았다.

사용자는 암호화 완료 기준으로 **현재 구성의 FBE**를 선택했다. 소프트웨어 키 관리의 한계를 명시한 상태에서 Android의 부팅·화면 잠금·데이터 암호화 연동을 검증한다. 이는 실제 userdata 초기화나 system/vendor 기록에 대한 승인은 아니다.

기존 vold 시험에는 키 저장·복원 통합 시험이 없어 `tools/security-probe/vold-key-storage.cpp`를 준비했다. 새 키 저장 구현을 만들지 않고 실제 `libvold`의 `storeKeyAtomically`, `retrieveKey`, `destroyKey`를 호출한다. 새로 만든 `/data/local/tmp/plf-vold-key-test-XXXXXX` 아래에서만 폐기 가능한 키를 저장하고, Keystore 경로와 secret 경로의 복원, 잘못된 secret 거부, 생성한 키의 정리를 검사한다. 실제 사용자 키 디렉터리와 전역 키 삭제 API는 사용하지 않는다.

비설치 모듈은 12분 20초에 종료 0으로 빌드됐다. 실행 파일은 207,520 bytes이고 SHA-256은 `3fbcaeb656d5c7e75b45a189f500306bb5664510d1cfbf8f3208181d0ba66cec`이며 Mac 전송본과 일치했다. 실기에서는 두 경로 모두 저장·원래 키 복원·시험 키 정리가 통과했고 잘못된 secret은 거부됐다. 최종 `VOLD_KEY_STORAGE_PASS`, 종료 0이었다.

로그의 첫 `generateKey` 오류 -67은 rollback-resistant 키 생성 실패 뒤 기존 vold가 그 속성 없이 재시도한 것이다. 실제 저장·복원은 성공했지만 rollback resistance까지 지원한다는 뜻은 아니다. `decryptWithoutKeystore failed`는 의도적으로 잘못된 secret을 넣은 음성 시험에서 발생했으며 올바른 secret으로 이어서 복원했다.

임시 키 디렉터리는 진단 도구가 정리했고 실행 파일도 제거했다. 일반 셸 UID 2000, Enforcing, 임시 ADB 인증 1, 부팅 완료 1을 확인했다. 실제 userdata는 여전히 `unsupported`다. 원문 결과는 `private/security-20261119/vold-key-storage-results.txt`에 보관했다. 이 시험은 실제 키 저장 라이브러리와 Keystore2 연동을 확인한 것이며 vold 서비스 도메인의 파일 접근, 초기 부팅의 DE/CE 생성, 화면 잠금 연동과 재부팅 후 복원은 실제 FBE 적용 단계에서 검증한다.

### FBE vendor 후보

`configs/plf02wh/fstab.rk30board`를 준비했다. 기존 활성 fstab 행과 비교해 userdata 행의 `fileencryption=aes-256-xts:aes-256-cts:v2` 추가만 확인했다. 기존 마운트 옵션을 유지했으며 `dirsync`, metadata encryption, inline encryption 또는 hardware-wrapped key 옵션을 추가하지 않았다.

memtrack 수정 vendor의 별도 사본에서 fstab만 교체했다. 서버 후보는 `expand-prep-20261118-ZimJvy/fbe-candidate/vendor-fbe.img`이며 크기는 기존과 같은 220,258,304 bytes다. SHA-256은 `6293278561cf220c99e2e10bcb0b54d53a7e9408ab6459d84410cb50b697fbe5`다.

Mac 전송본 `private/security-20261119/vendor-fbe.img`도 이 해시와 일치했다.

- `e2fsck -fn` 종료 0.
- 추출한 fstab과 입력 파일의 바이트 일치.
- UID/GID 0, mode 0644, SELinux 문맥 33 bytes 원본 일치.
- 추출한 memtrack 라이브러리 해시가 설치된 수정본과 일치.
- 바뀐 4 KiB 블록은 `[0, 40, 19352]`뿐이다. 블록 0은 쓰기 시각의 바이트 1072·1073, 블록 40은 fstab inode 581이며 그 inode 밖의 바이트는 같다. 블록 19352는 해당 파일 내용이다.

기기에는 아직 적용하지 않았다. 이 후보를 적용하려면 vendor의 물리 LBA 6,428,672부터 430,192섹터 기록과 기존 userdata의 새 포맷이 필요하다. 현재 초기 설정·설치 앱·설정·ADB 승인 키가 사라지므로 최초 설정과 ADB 화면 승인을 다시 해야 한다. userdata 시작 LBA는 7,229,440이며 실제 기록 전에 GPT·LP 배치를 다시 확인한다. 현재 단계에서는 GPT·boot·odm·metadata 변경을 계획하지 않는다.

먼저 ADB 인증 system 기록 승인을 받고 재부팅 검증을 끝낸 뒤 FBE 전환의 정확한 초기화 절차를 제시한다. FBE 실패 시 memtrack 수정이 포함된 비암호화 vendor `86744338a7647414064b087a293ae845f40b091b2ea2f3a243ffc1e2b5bf1d8c`로 복원하고 userdata를 다시 초기화하는 원복 범위를 함께 승인받아야 한다. 이 원복으로 초기화 전 사용자 데이터가 복구되는 것은 아니다.

ADB 인증 system의 재부팅 검증은 완료했다. 다음 FBE 적용에서 제안하는 초기화 방법은 RAM Loader 상태에서 userdata 시작 LBA 7,229,440의 첫 8섹터(4 KiB)를 0으로 만든 뒤 Android가 새 ext4를 생성하게 하는 것이다. 현재 `system/core/libcutils/partition_utils.cpp`는 첫 4 KiB가 모두 0이면 초기화된 파티션으로 판정한다. `fs_mgr.cpp:1563–1599`는 마운트 실패·formattable·해당 표식 조건에서 포맷하고 다시 마운트를 시도한다. `fs_mgr_format.cpp`는 전체 블록 장치 크기로 4 KiB 블록·512바이트 inode의 새 ext4를 만들며, 재마운트 전 `fs_mgr.cpp:469`의 `tune_encrypt`가 `encrypt` 기능을 활성화한다. 실제 설치 이미지에 mke2fs와 tune2fs가 존재함을 확인했다.

4 KiB 표식 기록은 데이터 보존 방식이 아니다. 뒤이어 전체 userdata의 파일시스템이 새로 만들어지므로 현재 앱·설정·사용자 파일·ADB 승인 키를 잃는다. 사용자에게 FBE 적용·초기화와 실패 시 비암호화 vendor 복원·userdata 재초기화까지 포함한 범위를 물었고 “좋아 이어서 쭉 진행해줘.”라는 승인을 받았다. system·GPT·boot·odm·metadata는 유지한다. 적용 증거는 `private/security-20261119/fbe-flash/`에 보관한다.

승인 후 RAM Loader에서 양쪽 GPT와 LP 메타데이터가 기준 배치와 같음을 확인했다. 현재 vendor 전체도 원복 이미지와 일치했다. userdata 시작의 첫 4 KiB에서는 예상한 ext4 서명을 확인했으며 이 사본은 메타데이터 증거일 뿐 사용자 데이터 백업은 아니다.

FBE vendor를 LBA 6,428,672부터 기록했고 전체 220,258,304 bytes 재읽기 `cmp`와 SHA-256 `6293278561cf220c99e2e10bcb0b54d53a7e9408ab6459d84410cb50b697fbe5`가 일치했다. 이어 userdata 시작 LBA 7,229,440에 4 KiB 초기화 표식을 기록하고 재읽기에서 모두 0임을 확인했다. 이 단계의 쓰기는 vendor와 승인된 userdata 표식에 한정됐다.

재부팅 후 새 사용자 데이터의 ADB 상태는 unauthorized였고, 사용자 화면 승인 후 device로 바뀌었다. 첫 부팅 완료 시 `ro.crypto.state=encrypted`, `ro.crypto.type=file`, `ro.adb.secure=1`, 일반 셸 UID 2000, Enforcing을 확인했다. 그 시점의 초기 설정 값은 0이었고 이후 사용자가 “설정·USB 승인 완료”로 답했다. 실제 디렉터리 정책과 PIN 설정 후 재부팅 잠금·해제·데이터 유지는 후속 검증 중이다.

후속 읽기에서 `/data/user_de/0`, `/data/system_de/0`는 동일한 DE 키 식별자, `/data/user/0`, `/data/media/0`, `/data/system_ce/0`는 그와 다른 CE 키 식별자를 사용했다. 다섯 경로 모두 version 2, AES-256-XTS·AES-256-CTS, PAD_16이었다. 실제 키 내용은 읽지 않았다. 원문은 `fbe-flash/actual-directory-policies.txt`에 보관했다.

재부팅 후 데이터 보존 확인용 파일 `/data/media/0/Download/plf02wh-fbe-roundtrip.txt`를 만들었다. SHA-256은 `33d0fcf11ffe460c3c087c40a3485528d7c369ddd2882e1a6677ab16379fb37d`다. 읽기 전용 정책 조회 도구는 `/data/local/tmp/plf-fbe-verify/`에 임시 보관하며 잠금 시험 후 제거한다. 진단 뒤 ADB를 unroot했다.

USB 승인은 완료됐지만 후속 설정 값은 여전히 0이었고, 화면을 깨운 캡처에서도 “Hi there” 초기 설정 시작 화면을 확인했다. 사용자에게 홈 화면까지 설정을 마치고 PIN을 직접 설정하도록 요청했다. PIN 값은 수집하지 않는다. 그 완료 답변 전에는 잠금 시험용 재부팅을 진행하지 않는다.

이후 초기 설정 완료 값 1과 일반 셸·Enforcing을 확인했고 사용자는 “홈 화면·PIN 설정 완료”라고 답했다. PIN을 입력하지 말아 달라고 안내한 뒤 재부팅했다. 부팅 후 암호화와 인증은 유지됐지만 사용자 상태는 `RUNNING_UNLOCKED`였고 Keyguard는 `secure=false`였다. uptime 약 66초로 실제 재부팅은 확인했다. 이 결과는 PIN 입력 전 CE 잠금 성공으로 인정하지 않는다. 현재 화면 잠금 방식이 PIN으로 저장돼 있는지 사용자에게 확인 중이며 원인은 아직 확정하지 않았다. 증거는 `fbe-flash/pin-reboot-state.txt`다.

사용자는 실제 화면 잠금 방식이 “스와이프 또는 없음”이라고 확인했다. 첫 시험은 PIN이 없는 구성에서 실행됐으므로 PIN 보호의 결함을 입증하지 않는다. 기기에서 PIN을 두 번 입력해 저장하고 설정 항목이 PIN으로 바뀐 것을 확인한 뒤 다시 시험하도록 안내했다. 실제 PIN 값은 요청하지 않았다.

PIN 저장 확인 후 두 번째 시험에서는 새 부팅 ID와 `RUNNING_LOCKED`를 확인했다. 다만 키 조회 시점에는 CE 키가 Present였고 사용자도 RUNNING_UNLOCKED로 바뀌어 시험 파일이 읽혔다. 사용자가 그 사이 PIN을 입력했다고 확인했다. 따라서 이 회차에서는 PIN 입력 전 키 부재를 검증하지 못했으며, 입력 전 상태를 먼저 수집한 뒤 PIN 입력을 요청하는 순서로 다시 진행한다. 증거는 `pin-locked-key-status.txt`, `pin-key-state-transition.txt`다.

후속 회차에서도 사용자가 검사 전에 PIN을 입력했다고 확인했다. 서비스 진단에서는 실제 CredentialType이 PIN이고 저장 성공 로그가 있었다. 이후에는 새 부팅에서 ADB가 연결되는 즉시 화면을 끄고, 잠금 상태를 먼저 수집하도록 순서를 바꿨다.

`pin-early-locked-check.txt`에서 새 부팅 ID, `CredentialType: PIN`, `RUNNING_LOCKED`, Enforcing을 확인했다. DE 키는 Present, CE 키는 Absent였고 CE 시험 파일의 원래 경로 읽기는 종료 1로 차단됐다. 따라서 PIN 설정의 재부팅 보존과 PIN 입력 전 CE 잠금을 검증했다. 화면을 다시 켜 사용자에게 PIN 입력을 요청했으며, 해제 후 CE 키와 시험 파일 해시 복원을 확인 중이다.

### PIN 입력 후 해제 실패: 원인 수정과 임시 적용 검증

사용자가 PIN 입력 후에도 잠금이 유지된다고 알렸다. 실제 사용자 상태도 RUNNING_LOCKED이고 CE 데이터 복원은 확인하지 못했다. 해제 대기 감시를 중단하고 인증 경로 조사로 전환했다.

로그에서는 `LockSettingsService: Verifying lockscreen credential` 뒤 Keyguard의 `keyguardDone`이 발생했지만, 이어 Keystore2의 키 연산이 `KEY_USER_NOT_AUTHENTICATED`로 실패했다. SyntheticPasswordCrypto는 Cipher 초기화에서 `UserNotAuthenticatedException`을 받았고, `Failed to decrypt blob` 예외가 SystemUI의 AsyncTask까지 전파돼 SystemUI가 재시작했다.

현재 소스의 `SyntheticPasswordManager.unlockLskfBasedProtector`는 Gatekeeper 응답 OK일 때만 progress callback을 호출한 뒤 SP blob을 복호화한다. 따라서 관찰된 실패는 Gatekeeper의 첫 PIN 확인 이후, 인증에 묶인 SP 보호 키를 Keystore에서 사용하는 단계다. 단순 PIN 오입력이나 fscrypt 정책 설정 실패로 취급하지 않는다. 인증 토큰 전달·검증의 어느 부분이 원인인지는 아직 확정하지 않았다.

증거: `pin-unlock-failure.log`, `pin-unlock-crash.log`, `synthetic-password-crypto-failure.log`. 현재 일반 셸 UID 2000과 Enforcing으로 복귀했다. 정책 조회 도구와 CE 시험 파일은 후속 검증용으로 남아 있다. 인증 요구를 제거하거나 PIN·키 파일을 삭제하는 우회는 하지 않았다. FBE의 실제 잠금 해제·데이터 복원 완료 조건은 충족되지 않았다.

소스 조사에서 software Gatekeeper는 HAT MAC을 0으로 채우지만, 대응하는 software Keymaster 소스는 서명 검사와 timeout 검사를 무조건 통과시킨다. 따라서 이 사실만으로 HMAC 불일치를 원인으로 단정할 수 없다. Keymaster는 별도로 토큰 존재·크기·버전·SID·인증 유형을 검사한다. 현재 Keystore2의 오류 위치는 자체 인증 토큰 선택 이후 backend `begin()` 호출 실패에 해당한다.

실제 Keymaster 프로세스의 보존 로그에서는 세부 거부 이유를 얻지 못했다. 보존 vendor의 `libkeymaster_portable.so`에는 각 거부 분기의 문자열이 있지만, 문자열 존재만으로 실행된 분기를 알 수는 없다.

다음 구분 시험으로 `tools/security-probe/auth-token-probe.cpp`를 준비했다. Android 사용자 ID 영역과 분리한 시험 ID와 무작위 시험 자격 증명을 사용해 Gatekeeper 토큰을 얻고, 해당 SID에 인증이 묶인 별도 AES 키를 Keymaster에 가져온다. 토큰 없는 begin은 거부되고 실제 토큰을 넣은 begin은 성공하는지 비교한다. 토큰 원문·SID·키 내용·사용자 PIN은 출력하지 않으며, 원래 사용자 키나 자격 증명은 사용하지 않는다. 시험 키는 삭제하고 시험 Gatekeeper ID의 선택적 삭제 API 결과도 기록한다. 소프트웨어 HAL의 비구현 결과는 휘발성 캐시가 즉시 삭제됐다는 뜻으로 취급하지 않는다. 비설치 진단 모듈을 빌드 중이며 아직 실행 결과는 없다.

진단 모듈의 첫 컴파일에서는 메모리 지우기 함수와 HIDL nonce 전달 형식이 맞지 않았다. 현재 Android의 `memset_explicit`과 기존 `blob2hidlVec` API로 고쳤으며 재빌드는 2분 27초에 종료 0으로 통과했다. 실행 파일은 291,040 bytes, SHA-256 `53b2816a4339929dc6b08fdf078fbbee58793e06d98640a696be0598800e8c86`이며 Mac 전송 해시가 일치했다. 필요한 system 라이브러리를 확인한 뒤 임시 경로에서 직접 토큰 전달 시험을 시작했다.

직접 전달 시험은 실패를 재현했다. Gatekeeper enroll·verify와 키 import는 0, 토큰 형식·필드 및 키 SID·인증 유형 대조는 모두 참이었다. 하지만 missing-token과 valid-token begin이 모두 -26이었다. 시험 키 삭제는 성공했고 선택적 Gatekeeper deleteUser는 -3(비구현)이었다. 결과는 `fbe-flash/auth-token-direct-results.txt`에 보관했다. 기존 사용자 자격 증명을 사용하지 않고도 backend에서 재현되므로 Keystore2 중간 전달 경로에만 국한된 문제는 아니다.

### vendor 토큰 길이 비교 결함과 수정 후보

보존 vendor의 실제 기계어에서 원인을 설명하는 결함을 확인했다. `/vendor/lib64/libkeymaster_portable.so`의 `KeymasterEnforcement::GetAndValidateAuthToken`은 주소 `0x2e38c`에서 토큰 길이를 `cmp x2, #8`로 검사한다. 그런데 같은 함수의 실패 로그 인자는 정상 길이 `0x45`(69)이고, `libkeymaster4support.so`의 `authToken2HidlVec`도 69바이트를 만든다. 현재 대응 소스의 계약은 `sizeof(**auth_token)`이며 포인터 크기인 8과의 비교는 정상 토큰을 거부한다.

`libpuresoftkeymasterdevice.so`의 vtable과 기계어에서도 서명 검사는 true, timeout 검사는 false를 반환함을 확인했다. 이 수정은 그 정책을 바꾸지 않는다. 토큰 존재·버전·SID·인증 유형 등 나머지 검사도 그대로 둔다.

재현 가능한 변경 명세는 `configs/plf02wh/keymaster-auth-token-size.json`이다. 원본 343,408 bytes의 SHA-256은 `1ce8cdc9b6301fbdfc87dcd68a5d0c1fe68230ebd780d7ebec80434ce507845b`다. 파일 offset 189,324의 명령 `5f2000f1`을 Clang 어셈블러로 확인한 `5f1401f1`(`cmp x2, #69`)로 바꿨다. 변경 바이트는 189,325·189,326뿐이다.

후보 `private/security-20261119/libkeymaster_portable-token-size-fixed.so`의 SHA-256은 `a1e67c7cb4768a11faa587fcf32130da55eb871920cdb3661c283af133bd9961`이다. 아직 실기 적용·검증하지 않았다. 로드된 실제 라이브러리 확인을 시도했으나 ADB와 Rockchip USB 목록 모두에서 기기가 사라져 재연결을 요청했고 감시 중이다. 연결 후 같은 진단의 음성·양성 대조와 실제 PIN 해제를 확인해야 수정 완료로 인정할 수 있다.

사용자 재연결 후 실제 Keymaster 프로세스의 maps에서 `/vendor/lib64/libkeymaster_portable.so` 로드를 확인했다. 기기 파일의 SHA-256도 위 결함 원본과 일치했다. init·ADB 셸·Keymaster는 같은 mount namespace를 사용하며 원본은 root:root, 0644, `u:object_r:vendor_file:s0`였다. 서비스 이름은 `vendor.keymaster-4-0`이다.

다음 실기 시험 범위는 후보 파일을 전용 임시 경로에 준비하고 원본 라이브러리 경로에 bind mount한 뒤 Keymaster를 재시작하는 것이다. 기존 연결 복구에 필요하면 Keystore2도 재시작한다. 저장장치의 vendor 원본·사용자 키·PIN·userdata는 변경하지 않는다. 실패 시 마운트를 해제하고 원본 서비스로 복귀하며, 재부팅도 임시 마운트를 해제한다. 영구 vendor 기록은 이 시험 범위에 포함하지 않는다. 일반 셸로 복귀한 상태에서 이 보안 서비스 임시 교체 범위를 설명하고 승인을 요청한다.

사용자가 이 임시 교체 범위에 “승인”이라고 답했다. 후보를 root:root·0644·vendor_file 문맥으로 준비하고 전송 해시를 확인했다. Keymaster 정지 상태를 확인한 뒤 bind mount하고 다시 시작했다. 서비스 running, 실제 라이브러리 경로의 수정본 해시, Enforcing을 확인했다. 동일한 인증 토큰 진단으로 음성·양성 대조를 실행 중이며 아직 영구 vendor 기록은 하지 않았다.

같은 직접 전달 진단에서 수정 전에는 missing·valid 토큰 모두 -26이었지만, 수정 후 missing-token begin은 -26을 유지하고 valid-token begin만 0으로 바뀌었다. 키 SID·인증 유형 일치와 시험 키 삭제도 통과해 최종 `AUTH_TOKEN_PROBE_PASS`, 종료 0이었다. 결과는 `fbe-flash/auth-token-fixed-results.txt`다. 인증 요구를 없애지 않고 길이 검사를 정상 구조체 크기로 바로잡으면 실패가 해소됨을 실기에서 확인했다.

실제 PIN 해제 시험을 위해 승인 범위의 Keystore2 재시작을 요청했다. 재시작 전 사용자는 RUNNING_LOCKED였으며 기존 SP blob과 사용자 키는 유지했다. 영구 반영·재부팅 검증은 아직 남아 있다.

Keystore2 재시작 후 기존 PIN 입력과 CE 키·시험 파일 복원을 감시 중이다. 동시에 영구 반영 후보 `private/security-20261119/vendor-fbe-keymaster-fixed.img`를 만들었다. 크기는 220,258,304 bytes, SHA-256은 `59c3081a43e147550da9c7784ff3f800bfbc2c818a9951b37cc440e7ad7631c1`이다.

기존 FBE vendor와 달라진 바이트는 195,281,805·195,281,806 두 개뿐이며 해당 라이브러리의 길이 비교 명령에 해당한다. 파일 inode·권한·SELinux 문맥·fstab·memtrack 등 나머지 바이트는 같다. 서버 전송 해시, `e2fsck -fn` 종료 0, 재추출한 라이브러리의 수정본 해시 일치를 확인했다. 이 영구 후보는 아직 기기에 기록하지 않았다.

임시 수정본과 재시작한 Keystore2에서 사용자가 기존 PIN을 입력하자 RUNNING_UNLOCKED로 전환됐다. CE 키는 Present였고 원래 시험 파일 SHA-256 `33d0fcf11ffe460c3c087c40a3485528d7c369ddd2882e1a6677ab16379fb37d`가 일치해 `FBE_FIXED_PIN_UNLOCK_PASS`, 종료 0이었다. 사용자 키 재생성·PIN 변경·데이터 초기화 없이 복원됐다.

SystemUI PID는 시험 전후 1154로 같았고 시험 시작 이후 crash 버퍼는 비어 있었다. 실제 홈 화면도 확인했다. ADB 인증 1·encrypted/file·Enforcing을 유지했고 일반 셸 UID 2000으로 복귀했다. 증거는 `fixed-pin-unlock-results.txt`, `fixed-pin-after-state.txt`, `fixed-pin-unlocked-screen.png`다.

수정본은 아직 bind mount로만 적용돼 있다. 재부팅하면 원래 결함 라이브러리가 다시 사용되므로 영구 vendor 기록과 재부팅 후 잠금·해제 검증이 남아 있다. 영구 기록 범위는 기존 vendor LBA 6,428,672부터 430,192섹터이며 userdata를 초기화하지 않는다. 문제가 생겨 원래 FBE vendor로 복원하면 기존 PIN 오류 상태로 돌아오므로, 필요 시 검증된 임시 교체로 다시 접근을 복구한다. 이 영구 기록은 별도 승인받는다.

사용자가 수정 vendor만 영구 기록하고 재부팅하며 userdata는 초기화하지 않는 범위에 “승인할게”라고 답했다. 후보 SHA-256은 `59c3081a43e147550da9c7784ff3f800bfbc2c818a9951b37cc440e7ad7631c1`이며 기록 증거는 `private/security-20261119/keymaster-flash/`에 보관한다. 승인 후 Loader 진입을 요청했다.

RAM Loader에서 양쪽 GPT와 LP 메타데이터가 보존된 배치와 일치함을 확인했다. vendor의 LBA 6,428,672–6,858,863에 수정 후보를 기록한 뒤 전체 220,258,304 bytes를 재읽었다. 후보와 바이트 단위 비교 및 SHA-256이 일치했다. userdata 초기화나 system·GPT·boot·odm·metadata 기록은 하지 않았다. 정상 재부팅을 요청하고 영구 수정 상태의 잠금·해제 검증을 시작했다.

영구 반영 후 재부팅에서도 수정 라이브러리 해시·CredentialType PIN·RUNNING_LOCKED·Enforcing·인증 1·encrypted/file을 확인했다. DE 키는 Present, CE 키는 Absent였고 시험 파일 읽기는 차단됐다. 사용자 PIN 입력 후에는 RUNNING_UNLOCKED와 CE 키 Present로 바뀌었고 기존 시험 파일 해시가 일치해 `FBE_PERMANENT_UNLOCK_PASS`, 종료 0이었다. 임시 마운트에 의존하지 않는 재부팅 후 잠금·해제 및 기존 데이터 보존을 검증했다. 증거는 `keymaster-flash/locked-boot-check.txt`, `pin-unlocked-results.txt`다.

부팅 완료·초기 설정 완료 값은 모두 1이었고 Keymaster·memtrack·audioserver·SurfaceFlinger는 running이었다. SystemUI PID는 PIN 시험 전후 1170으로 유지됐으며 새 부팅의 crash 버퍼는 비어 있었다. 파일 대상에 `mountpoint`를 적용한 첫 확인은 “not a directory”여서 근거로 쓰지 않았고, `/proc/1/mountinfo`에서 라이브러리 경로의 bind mount가 없음을 직접 확인했다.

기기의 `/data/local/tmp/plf-fbe-verify/` 안에 있던 정책 조회 도구·토큰 진단 도구·임시 수정 라이브러리와 CE 시험 파일을 제거했다. 일반 셸 UID 2000·Enforcing·ADB 인증 1 복귀까지 확인해 현재 구성의 FBE 적용 검증을 마쳤다. 호스트의 원본·원복 이미지·후보·로그는 증거와 복구 자료로 보존한다.

암호화 후에는 vendor fstab만 원복한다고 데이터가 평문으로 돌아오지 않는다. 초기화·키 저장 상태·백업 복구를 함께 다루는 원복 계획이 필요하다. 부트로더 잠금은 이 작업 범위에서 수행하지 않는다.

## 검토 중인 순서

1. 원복 가능한 ADB 인증 시험을 먼저 설계하고 사용자 승인 후 실행.
2. 실제 Keymaster 보안 수준과 격리된 fscrypt 동작 확인.
3. 필요한 권한과 영구 반영 범위를 확정.
4. 각 영구 변경을 별도로 검증하고 적용.

## 첫 영구 변경 범위

우선 `lineage_arm64_bgN-userdebug` 제품의 ADB 호스트 키 인증을 기본값으로 만든다. 공통 속성 파일의 중복 인증 해제 항목을 제거하고, 다른 제품에는 기존 기본값을 유지하며, 선택 제품에서는 빌드 스크립트의 insecure 플래그가 인증을 다시 끄지 않도록 한다.

이 단계에서는 SELinux 허용 규칙을 추가하지 않는다. 기본 ADB 셸은 UID 2000을 유지하고, 무선 ADB를 켜지 않는다. 개발·검증을 위한 userdebug와 승인된 호스트의 명시적 `adb root` 가능성은 유지하므로 운영용 user 빌드가 됐다고 주장하지 않는다.

데이터 암호화·키 관리 구현·부트로더 잠금·userdata 초기화는 이 이미지 변경에 포함하지 않는다. 암호화의 하드웨어 키 보호 경로와 격리 시험은 별도 보안 작업으로 추적한다. 새 이미지의 정적 검사와 원복 준비 후 실제 system 기록 범위를 제시하고 승인받는다.

## 임시 ADB 인증 시험 진행 상태

사용자가 “진행해”라고 승인한 뒤, 메모리상의 `ro.adb.secure`를 1로 바꾸고 adbd를 일반 권한으로 재시작했다. 호스트에서 `unauthorized`를 확인했고 실제 `adb shell id`도 종료 1과 `adb: device unauthorized.`로 거부됐다.

기기 화면에서 승인할 Mac 공개키 지문은 `A5:54:70:37:30:17:FE:32:E1:E5:F1:23:0E:D4:14:04`다. 개인키는 읽지 않았다.

첫 화면 승인 대기는 10분 후 종료됐고 직후에도 `unauthorized`였다. 사용자에게 잠금 해제와 USB 재연결을 안내하자 승인 창이 표시됐으며, 사용자가 지문을 확인하고 허용했다. 호스트에서 disconnected → unauthorized → device 전환을 관찰했다.

승인 후 `ro.adb.secure=1`, 일반 셸 UID 2000, SELinux Enforcing을 확인했다. 이후 Keymaster 진단용 adbd root 재시작에서도 인증 1을 유지한 채 연결됐다. 따라서 미승인 셸 차단과 사용자 승인 후 연결 복구를 모두 검증했다. 키 관리 조회 뒤 임시 실행 파일·디렉터리를 제거하고 unroot했다.

이 임시 시험에서는 ROM·fstab·userdata를 초기화하거나 기록하지 않았다. 시험 당시 인증 1은 메모리 값이어서 재부팅 시 기존 값 0으로 돌아갔다. 이후 위의 별도 승인 절차로 인증 기본값 이미지를 적용했고 재부팅 후에도 1을 유지하는 것을 검증했다.
