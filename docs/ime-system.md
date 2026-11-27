# 한국어 입력기 기본 앱 통합

## 요청과 현재 상태

2026-11-19 사용자가 KeliBoard를 기본 앱으로 넣고 영어 지역명 불일치도 해결해 달라고 요청했다. 제품 소스 통합, system 이미지와 기록 후보 검증을 완료했다. 2026-11-20 사용자는 userdata 초기화 없는 system·LP 기록·재부팅과 필요시 기존 system·LP 원복 범위에 “좋아 진행해”라고 승인했다. 승인된 기록과 적용 후 실기 검증을 완료했다.

영어 설정은 실기에서 바로잡았다. 최초 조사에서 KeliBoard의 저장값은 `en-CA`였으며 다시 연 설정 화면도 캐나다가 활성화돼 있었다. 이전에 미국이 활성화됐다고 판단한 확인이 잘못됐다. 캐나다를 끄고 미국을 켠 뒤 저장값 `en-US`와 선택창의 “영어(미국)”이 일치함을 확인했다. 한국어 두벌식 설정은 그대로 유지했다.

APK의 미국 영어 한국어 번역도 “영어(미국)”으로 정상이다. 스페이스 길게 누르기로 여는 선택창은 KeliBoard 자체 구현이며, 원본 소스의 `InputMethodPicker.kt`와 `SubtypeLocaleUtils.kt`에서 이름 경로를 확인했다. APK 코드나 번역을 수정할 필요는 없었다.

## 통합 방식

- 대상 제품: `lineage_arm64_bgN-userdebug`.
- 모듈: `PLF02WHKeliBoard`, 일반 product 앱. privileged 앱이나 플랫폼 서명 앱으로 만들지 않는다.
- 예상 설치 위치: `/system/product/app/PLF02WHKeliBoard/PLF02WHKeliBoard.apk`.
- 원본 APK·서명·버전 고정: [배포 manifest](../configs/plf02wh/keliboard.json).
- 모듈 원본: [Android.mk](../configs/plf02wh/keliboard/Android.mk).
- 제품 패치: [PLF02WH 제품에 모듈 추가](../patches/plf02wh-keliboard.patch).
- 빌드 소스 위치: `device/phh/treble/plf02wh_keliboard`.

공식 APK는 DEX와 JNI가 압축돼 있고 `extractNativeLibs=true`다. 이 트리의 일반 APK 변환 경로로 압축을 바꾸면 원본 서명이 손상될 수 있다. 기존 Make의 `LOCAL_REPLACE_PREBUILT_APK_INSTALLED` 경로로 원본 APK를 그대로 설치하고, 같은 APK의 arm64 라이브러리 두 개를 앱 전용 `lib/arm64`에 별도로 설치한다. DEX 사전 최적화는 하지 않으며 런타임 ART가 기존 일반 앱과 같이 처리한다.

빌드 입력을 재현하려면 고정 APK의 해시를 배포 manifest와 비교한 뒤 모듈 디렉터리에 `KeliBoard.apk`로 복사한다. 동일한 APK에서 아래 두 파일을 원래 경로대로 추출하고 `Android.mk`를 함께 둔다.

```text
lib/arm64-v8a/libandroidx.graphics.path.so
lib/arm64-v8a/libjni_latinime.so
```

전체 system 빌드 도중 모듈의 설치 산출물은 먼저 생성됐다. `out/target/product/tdgsi_arm64_ab/system/product/app/PLF02WHKeliBoard/`의 APK와 `lib/arm64` 두 파일을 확인했고 세 파일 모두 원본과 SHA-256이 일치했다. APK는 서명된 원본 그대로이며 라이브러리도 별도 앱 경로에 설치됐다. 이는 설치 디렉터리 검증이며 최종 system 이미지 추출 검증을 대신하지 않는다.

제품 파일에 모듈을 추가하고 기존 20 GiB 메모리·작업 수 3 제한으로 `m -j3 PLF02WHKeliBoard systemimage`를 실행한다. `WITH_ADB_INSECURE`는 unset한다. LatinIME, VNDK30, framework 라이브러리, SELinux, 기존 FBE vendor는 유지한다.

## 용량과 적용 전 검증

현재 system 논리 파티션은 2,272,292,864바이트다. 실기 `df`에서 일반 가용 공간은 약 16 MiB였으므로, 22,784,167바이트 APK와 별도 JNI가 들어간 새 이미지의 실제 크기로 기록 방식을 결정한다. super는 이미 2.5 GiB이며 userdata 시작점은 이동하지 않는다. 예전 18.1의 1,922,445,312바이트 한도는 현재 기준이 아니다.

설치 APK의 원본 해시·서명, 별도 JNI의 원본 일치, 파일시스템, 이미지 크기와 파티션 배치, ADB 인증 설정을 검증한 뒤 기록 범위를 확정한다. 현재 인증 system과 Keymaster 수정 FBE vendor는 `private/security-20261119/`에 보존돼 있다. 초기 설치 당시 전체 super에는 이후 보안 변경이 없으므로 그것만 덮어쓰는 원복은 사용하지 않는다.

완료된 빌드는 7시간 15분 35초, 컨테이너 종료 코드 0이었다. 서버 산출물은 `home/build-output/system-keliboard-20261119.img`, 크기는 2,296,836,096바이트, SHA-256은 `4a740c91d8fd3a0dfb4c33fde3a166c7218bf7f49f71629d94d6b711e1407775`다. 기존보다 24,543,232바이트(23.40625 MiB) 크다.

최종 이미지의 읽기 전용 `e2fsck -fn`은 종료 0이었다. 이미지에서 직접 추출한 APK와 JNI 두 파일도 원본 해시와 일치했다. APK inode는 root 소유, 0644, `u:object_r:system_file:s0`였다. `/system/build.prop`에서 ro.secure=1·ro.adb.secure=1·ro.debuggable=1을 확인했다.

새 이미지에서 추출한 VINTF 선언을 보존된 vendor·odm 선언, 최초 API 30, 커널 4.19.193 설정과 비교해 `COMPATIBLE`, 종료 0을 확인했다. 추출 시 호스트의 소유자 변경은 일반 계정 권한으로 거부됐으나 파일 내용은 생성됐고 검사가 읽어 통과했다. 소유자를 바꾸려고 권한을 올리지 않았다. `/apex`는 기존 검사와 같은 오프라인 매핑이며 부팅 후 동적 APEX 상태까지 이 검사로 확인한 것은 아니다.

AVB 자체 검증도 종료 0이었다. 첫 실행은 사용자 지정 이미지 파일명 때문에 descriptor가 참조하는 `system.img`를 찾지 못했다. 같은 파일을 가리키는 검사용 `system.img` 경로를 만든 뒤 SHA256_RSA2048 vbmeta 서명과 system의 SHA-256 해시트리가 통과했다. 검증을 끄거나 이미지 서명을 바꾸지 않았다. VNDK30의 APEX·펼친 디렉터리도 실제 이미지에 남아 있음을 확인했다.

적용 후 데이터 보존을 확인할 자체 CE 시험 파일을 Download 폴더에 생성했다. 사용자 파일 내용은 읽지 않았으며, 경로와 기준 해시는 `private/ime-system-20261119/ce-preservation.json`에 기록했다. 새 이미지 적용 후 기존 PIN으로 잠금을 해제한 상태에서 같은 해시를 확인하고 시험 파일을 제거한다.

인증 system 기록 직전 보존한 1 MiB 메타데이터를 기존 `lpdump`로 읽은 배치는 다음과 같다. 이후 작업에서 LP 배치는 변경하지 않았다. 모든 위치는 super 시작 기준 512바이트 섹터다.

| 파티션 | 시작 섹터 | 섹터 수 | 바이트 |
|---|---:|---:|---:|
| system | 2,048 | 4,438,072 | 2,272,292,864 |
| vendor | 4,442,112 | 430,192 | 220,258,304 |
| odm | 4,874,240 | 1,136 | 581,632 |

그룹 한도 2,680,160,256바이트에서 세 파티션을 뺀 여유는 187,027,456바이트다. 새 system이 기존 크기를 넘으면 단순히 기존 system 시작점부터 길게 기록해서는 안 된다. 그 뒤의 vendor를 덮어쓸 수 있으므로 LP 메타데이터와 실제 extent에 맞춘 준비가 필요하다.

기존 AOSP `lpadd --replace` 구현은 대상 파티션을 재할당하고 두 메타데이터 슬롯을 갱신할 수 있다. `system/extras/partition_tools/lpadd.cc`에서 경로를 확인했다. 초기에는 호스트 바이너리가 없었으므로 아래 후속 빌드로 준비했다.

후속 `lpadd` 빌드는 11분 27초, 종료 0으로 끝났다. 기기가 아닌 super 작업 사본에 현재 보안 vendor와 새 system을 반영했다. 두 슬롯 모두 metadata 10.0·540바이트·readonly 속성을 유지했고 vendor·odm의 위치와 크기는 그대로였다. system은 기존 앞쪽 공간과 super 뒤쪽 여유 공간을 쓰는 두 extent로 배치됐다.

| 기록 후보 | 기기 절대 시작 LBA | 섹터 수 | 기기 절대 끝 LBA |
|---|---:|---:|---:|
| system 첫 extent | 1,988,608 | 4,440,064 | 6,428,671 |
| system 둘째 extent | 6,862,848 | 45,944 | 6,908,791 |
| super 메타데이터 영역 | 1,986,560 | 2,048 | 1,988,607 |

system 두 조각을 먼저 기록·대조하고 메타데이터를 마지막에 기록하는 범위다. vendor 시작은 LBA 6,428,672이며 첫 extent와 겹치지 않는다. userdata 시작 LBA 7,229,440, GPT, boot, odm, vendor는 기록 대상에 넣지 않는다.

긴 빌드 뒤 현재 기기에서 GPT 두 벌과 super 앞 1 MiB를 읽었으며 보존된 인증 적용 직전 기준본과 전체 `cmp`가 일치했다. 실제 eMMC 경로는 `/dev/block/mmcblk2`였다. 조사 후 ADB는 UID 2000으로 복원했다.

후보를 다시 분리한 system·vendor·odm은 각각 새 system, 현재 보안 vendor, 보존된 odm의 해시와 일치했다. 기록용 세 조각을 Mac으로 전송해 크기·SHA-256을 대조했고 두 system 조각을 순서대로 해시하면 원본 system 해시와 같았다. 기록 범위가 서로 겹치지 않고 vendor·odm·userdata를 침범하지 않는 검사도 통과했다. 실제 파일과 범위는 `private/ime-system-20261119/flash-plan.json`, 전송 검증은 `payload-verification.json`에 고정했다.

원복안은 보존된 인증 system `system-adb-auth.img`를 기존 system 범위에 다시 기록하고, 그 뒤 현재 기기에서 읽은 원래 LP 메타데이터 1 MiB를 복원하는 것이다. 보안 vendor와 GPT·userdata는 이 원복에서도 기록하지 않는다. 원래 메타데이터로 돌아가면 새로 쓴 뒤쪽 extent는 참조되지 않는다. 원복 절차의 실제 실패 상황 검증과 userdata 전체 복원 검증은 하지 않았으므로 데이터 복원을 보장하는 백업으로 표현하지 않는다.

승인 후 기존에 검증한 Rockchip RAM Loader 경로로 진입해 장치·배치를 다시 대조한다. 각 system 조각 기록 후 전체 재읽기 대조를 통과해야 메타데이터 기록으로 진행하고, 메타데이터도 재읽어 대조한 뒤 재부팅한다. 마지막으로 기본 앱 등록, 입력 언어, 기존 PIN 해제와 CE 시험 파일 해시를 확인한다. 초기화와 부트로더 기록·잠금은 수행하지 않는다.

## 2026-11-20 기록 결과

시리얼 `PLF02WH_SERIAL`(공개용 가명), RK3399, 인증 ADB·FBE·Enforcing 상태를 확인한 뒤 기록 모드로 전환했다. 단일 USB 위치 801의 장치를 확인했고 RAM Loader의 capability는 `3F 06 00 00 00 00 00 00`, eMMC는 30,539,776섹터였다. RAM Loader로 읽은 GPT 두 벌과 LP 메타데이터가 승인 기준본과 전체 일치했다.

승인된 순서대로 system 첫 extent, 둘째 extent, LP 메타데이터를 기록했다. 각 명령은 종료 0이었고 각각 전체 재읽기 `cmp`를 통과했다. vendor 전체 SHA-256 `59c3081a43e147550da9c7784ff3f800bfbc2c818a9951b37cc440e7ad7631c1`과 odm 전체 SHA-256 `bb5e3c11dbbdde1a6ebfa59b1148f56722aa38735a189c77b14805fe0ba02fdb`도 유지됐다.

GPT·userdata·boot·vendor·odm에 기록하는 명령은 실행하지 않았다. 초기화나 부트로더 업그레이드도 하지 않았다. 기록·재읽기 증거는 `private/ime-system-20261119/flash-20261120/`에 보관한다.

재부팅은 완료됐고 새 system fingerprint, 인증 ADB=1, UID 2000, SELinux Enforcing, FBE encrypted/file, 초기 설정 완료 상태를 확인했다. 기존 CE 시험 파일도 원래 SHA-256과 일치했다.

PackageManager는 `/system/product/app/PLF02WHKeliBoard`를 SYSTEM 기본 패키지로 등록했다. 기존 `/data/app` 설치본은 같은 버전의 UPDATED_SYSTEM_APP으로 유지돼 앱 데이터가 보존됐다. 연락처·사진 관련 선택 권한은 여전히 미허용이다. 공장 초기화는 하지 않았고, 읽기 전용 이미지 포함과 시스템 패키지 등록으로 기본 앱 통합을 확인했다.

설정 앱 검색 필드에서 실제 화면 키로 “한글 abc”를 입력했다. 한영 전환과 선택창의 “영어(미국)”·“한국어” 표시도 정상이며 재부팅 전 선택이 유지됐다. 시험 검색어를 지우고 한국어를 마지막 선택으로 되돌렸다.

부팅 후 사용자는 RUNNING_UNLOCKED였으며 Keyguard의 secure=false와 설정 화면의 “기기 잠금 해제: 없음”을 확인했다. 사용자는 “기존 PIN 설정: 직접 없앴음”이라고 답해 이번 기록 전에 PIN을 제거한 상태였음을 확인했다. 현재 잠금 설정은 그 기준과 일치한다. 이번 재부팅을 PIN 인증 시험으로 기록하지 않으며 새 PIN을 설정하지도 않았다. PIN 값은 요청하거나 기록하지 않았다.

검증용 CE 파일과 UI 덤프를 제거했고 검색어를 비운 뒤 홈 화면으로 돌아갔다. 일반 ADB UID 2000을 유지한다. 공장 초기화 후 제공될 기본 앱을 이미지와 PackageManager 등록으로 확인했으며, userdata 보존을 위해 실제 공장 초기화는 하지 않았다.

실기 언어 교정과 빌드 증거는 `private/ime-system-20261119/`에 보관한다. 초기화 시험을 위해 userdata를 삭제하지 않는다.
