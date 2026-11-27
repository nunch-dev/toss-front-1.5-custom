# PLF02WH 전용 GApps 경량 빌드

## 2차 실측 결과 (2026-11-18)

접근성 앱과 전화·연락처·문자 앱을 제외한 추가 빌드도 성공했다. 필수 파일과 파일시스템 검사는 통과했지만 기존 system 예산은 아직 초과한다.

| 항목 | 확인값 |
|---|---|
| 결과 이미지 | `/mnt/storage/toss-lineageos/home/build-output/lineage-21.0-20261118-092248-UNOFFICIAL-arm64_bgN.img` |
| 크기 | 2,272,292,864 bytes |
| SHA-256 | `de850e39ed69cbb725caa6749b12e5cc670193203f00e2b38f9203956729f1e9` |
| 1차 GApps 이미지 대비 감소량 | 144,388,096 bytes |
| 기존 system 예산 초과량 | 349,847,552 bytes |
| 빌드 시간·종료 코드 | 10분 7초, 종료 코드 0 |
| 파일시스템 검사 | `e2fsck -fn` 종료 코드 0 |
| 로그 | `/mnt/storage/toss-lineageos/logs/build-20261118-091239.log` |

설치 목록에서 TalkBack, Google 음성 서비스, AccessibilityMenu, Dialer, Contacts, messaging의 제외를 확인했다. 실제 이미지의 읽기 전용 inode 조회로 Play 서비스·스토어·Google 기본 서비스·초기 설정·복원, Seedvault, 키보드, 홈 화면, Settings, SystemUI, DocumentsUI, WebView, TrebleApp의 포함을 확인했다. 구성 검사 원본은 `logs/slim2-product-vars.txt`에 있다.

원본 vanilla 및 1차 GApps 이미지도 별도 파일로 보존했다. 실기 부팅·앱 동작은 검증하지 않았으며 플래시나 파티션 변경을 수행하지 않았다. 이번에 승인된 추가 제외는 적용했으나, 남은 약 350 MB를 해결하려면 별도의 최적화 또는 용량 배치 결정을 해야 한다.

## 1차 실측 결과 (2026-11-18)

빌드는 성공했으나 기존 system 예산은 충족하지 못했다.

| 항목 | 확인값 |
|---|---|
| 결과 이미지 | `/mnt/storage/toss-lineageos/home/build-output/lineage-21.0-20261118-UNOFFICIAL-arm64_bgN.img` |
| 크기 | 2,416,680,960 bytes |
| SHA-256 | `42b1dbf288883ef5ca4bac47a375c721733d148dd3f588e354acc9090514d3be` |
| 기존 system 예산 초과량 | 494,235,648 bytes |
| 원본 vanilla 대비 감소량 | 131,518,464 bytes. 새 이미지에는 GApps가 포함되므로 동일 구성끼리의 비교는 아님 |
| 빌드 시간·종료 코드 | 27분 25초, 종료 코드 0 |
| 읽기 전용 파일시스템 검사 | `e2fsck -fn` 통과, 종료 코드 0 |
| 로그 | `/mnt/storage/toss-lineageos/logs/build-20261118-083324.log` |

실제 이미지에서 `debugfs`의 읽기 전용 inode 조회로 GmsCore, Phonesky, GoogleServicesFramework, GoogleRestore, SetupWizard, TalkBack, 음성 합성, Seedvault, LatinIME, TrebuchetQuickStep, Settings, SystemUI, DocumentsUI, WebView, TrebleApp, phh-ota, update_engine과 VNDK 30의 포함을 확인했다.

`installed-files.txt`에서는 제외 앱 23개, VNDK 28·29·31·32·33, CompOS, Microdroid 및 VM 실행 바이너리가 빠졌음을 확인했다. 이미지에 남은 dex 사전 컴파일 파일의 논리 크기 합계는 약 140 MB이고, 파일시스템 빈 공간은 약 34 MB다. 이 둘의 합계도 약 494 MB의 부족분에 미치지 못하며, 모두 회수할 수 있는 공간이라는 뜻도 아니다.

이번 실측은 승인받은 축소 범위만으로 예산을 충족하지 못했다는 근거다. 기능을 유지하는 모든 최적화가 불가능하다는 증명은 아니다. 추가 APEX 형식 최적화는 실제 기기의 활성화 경로를 확인해야 하고, 사전 컴파일 축소는 초기 실행·데이터 영역 사용량과의 교환이므로 후속 범위를 정해야 한다. 파티션을 변경하거나 필수 기능을 임의로 제거하지 않았다.

## 추가 경량화 선택 (2026-11-18)

1차 결과 후 사용자가 접근성은 "전부 불필요", 전화·연락처·문자는 "세 앱 모두 불필요"라고 답했다. [현재 요구사항](requirements.md)에 이 변경을 반영했다.

- 추가 제외: `talkback`, `SpeechServicesByGoogle`, `AccessibilityMenu`, `Dialer`, `Contacts`, `messaging`.
- 유지: Google Play 스토어·서비스·초기 설정·복원, WebView, LatinIME, Seedvault, 홈 화면, 파일 관리 및 보안 기반.
- 접근성 및 통신 공통 API·provider는 일괄 삭제하지 않는다. 사용자에게 해당 기능이 필요 없다는 것과 프레임워크 의존성을 제거해도 된다는 것은 구분한다.
- 기존 출력 파일을 보존하기 위해 새 결과 파일명에는 UTC 날짜와 시각을 넣는다.
- 재빌드는 기존 `RESUME_JOBS=3 LUNCH_TARGET=lineage_arm64_bgN-userdebug` 경로와 자원 제한을 유지한다.

패치 파일은 추가 제외까지 포함하도록 갱신했으며, 변경 전 소스에 대한 적용 검사와 실행 스크립트의 셸 문법 검사를 통과했다.

## 1차 구성의 범위와 기준

2026-11-18에 WebView·키보드·백업 등 [유지 요구사항](requirements.md)과 Google Play 스토어·서비스를 보존하면서 경량화하기로 했다. 원본 vanilla 이미지와 해시는 [최초 빌드 기록](build-gsi.md)에 있다. 원본 이미지는 덮어쓰지 않는다.

| 항목 | 구성 |
|---|---|
| 빌드 타깃 | `lineage_arm64_bgN-userdebug` |
| 서버 작업 위치 | `dev:/mnt/storage/toss-lineageos/src` |
| 실행 위치 | `dev:/mnt/storage/toss-lineageos/build-host` |
| 실행 명령 | `RESUME_JOBS=3 LUNCH_TARGET=lineage_arm64_bgN-userdebug ./run-gsi-build.sh` |
| 제한 | 메모리 20 GiB, swap 미사용, CPU 10, 병렬 3, 고메모리 풀 1 |
| 목표 이미지 예산 | 1,922,445,312 bytes |
| 소스 변경 | [경량화 패치](../patches/plf02wh-slim-gapps.patch) |

이 패치는 이미 AndyYan 패치와 Go 메모리 제한 패치를 적용한 소스에 대한 추가 변경이다. 모든 제품 제외 조건은 `lineage_arm64_bgN`에 한정한다. 최초 입력 커밋은 최초 빌드 기록을 따르며, 이번 변경은 커밋하지 않았다.

## 의존성에 따른 선택

| 대상 | 처리와 근거 |
|---|---|
| VNDK | vendor의 VNDK 30 계약에 맞춰 `PRODUCT_EXTRA_VNDK_VERSIONS := 30`으로 제한. 현재 framework의 VNDK와 SELinux 정책은 유지 |
| APEX 형식 | 기존 GSI의 패키지형·펼친 형식을 모두 유지. 해당 기기의 실제 APEX 활성화 경로를 아직 검증하지 않음 |
| AVF | `PRODUCT_AVF_ENABLED := false`. `com.android.virt` 공통 API·JNI·bootclasspath는 유지하고 VM 실행용 구성만 축소 |
| CompOS | 패키지·system-server jar·활성화 속성을 함께 제외. AVF 스위치만으로는 이 세 선언이 사라지지 않음 |
| Lineage 앱 | 계산기, Jelly, Eleven, Etar, Profiles, Recorder, Aperture, AudioFX, Backgrounds, Glimpse, ThemePicker, DeskClock 제외 |
| 대체 AOSP 앱 | 위 앱 제거 후 대신 선택될 수 있는 Browser2, Calendar, Gallery2, Music, Camera2, MusicFX도 제외 |
| Google 선택 앱 | Velvet 검색 앱, Markup 편집기, AndroidAutoStub, Wellbeing 제외 |
| Google 유지 앱 | GmsCore, Phonesky, GoogleServicesFramework, 초기 설정·복원, TalkBack, 음성 합성 및 나머지 선택하지 않은 구성은 유지 |

관련 소스는 `device/phh/treble/base.mk`, `build/make/target/product/gsi_release.mk`, `packages/modules/Virtualization/apex/product_packages.mk`와 `Android.bp`, `vendor/gapps/{arm64,common}/*-vendor.mk`다.

패키지 제외는 각 선언 파일에서 수행한다. 자식 제품 파일에서만 `filter-out`을 호출하면 아직 확장되지 않은 상속 목록 안의 패키지가 남을 수 있기 때문이다.

## 구성 검사 결과

빌드 전 `soong_ui.bash --dumpvars-mode`로 확인한 결과:

- `PRODUCT_EXTRA_VNDK_VERSIONS=30`, `PRODUCT_AVF_ENABLED=false`.
- 제외 목록의 패키지 24개가 최종 `PRODUCT_PACKAGES`에 남아 있지 않다.
- GmsCore, Phonesky, GoogleServicesFramework, GoogleRestore, SetupWizard, talkback, SpeechServicesByGoogle, Seedvault, LatinIME, TrebuchetQuickStep, Settings, SystemUI, DocumentsUI, Updater, webview가 모두 포함된다.
- CompOS의 system-server jar와 Wellbeing의 전용 복사 파일이 제외됐다.
- 패치는 변경 전 작업 사본에 `patch --dry-run`으로 적용 가능함을 확인했다. 실행 스크립트의 `bash -n` 검사도 통과했다.

원본 근거는 서버 `logs/slim-product-vars.txt`와 `logs/slim-lunch.log`에 있다. 이 검사는 빌드 구성 검사이며 기기에서의 기능 동작 검증이 아니다.

`Updater`는 구성 목록에는 있지만 최종 APK로 설치되지 않는다. 기존 `vendor/hardware_overlay/TrebleApp/Android.mk`의 `LOCAL_OVERRIDES_PACKAGES := Updater`가 원인이며, 원본 vanilla 이미지에서도 동일했다. 이번 경량화에서는 이 관계를 변경하지 않았고 TrebleApp·phh-ota·update_engine을 유지했다. 자체 OTA 배포와 복구 검증까지 완료한 것은 아니다.

## 검증 범위

최종 용량은 중복 블록 공유가 적용된 실제 이미지로 측정한다. 개별 파일 크기의 합계를 절감량으로 사용하지 않는다. GApps를 포함한 이미지를 생성하기 전에는 목표 예산 충족을 확정하지 않는다.

위 결과는 이미지 크기·SHA-256·읽기 전용 파일시스템 검사와 설치 파일 목록으로 확인했다. 기기 부팅, Google 로그인·Play 서비스, 한글 입력, 백업 복원, 암호화와 SELinux의 실제 동작은 별도 실기 검증이 필요하다. 이번 작업은 기기 쓰기나 플래시를 포함하지 않는다.
