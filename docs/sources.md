# 자료

기준일 2026-11-18. 기능 포함 선언은 하드웨어에서 동작한다는 증거가 아닙니다. 브랜치 URL은 변할 수 있어 실제 빌드 전 commit을 고정해야 합니다.

- LineageOS 24.0 공통 구성: https://github.com/LineageOS/android_vendor_lineage/blob/lineage-24.0/config/common.mk
- 모바일 구성: https://github.com/LineageOS/android_vendor_lineage/blob/lineage-24.0/config/common_mobile.mk
- Full 모바일 구성: https://github.com/LineageOS/android_vendor_lineage/blob/lineage-24.0/config/common_mobile_full.mk
- GApps 안내: https://github.com/LineageOS/lineage_wiki/blob/main/pages/gapps.md
- Android GSI: https://source.android.com/docs/core/tests/vts/gsi
- Android 파일 기반 암호화: https://source.android.com/docs/security/features/encryption/file-based
- Android 보안: https://source.android.com/docs/security/overview
- SELinux: https://source.android.com/docs/security/features/selinux
- 기존 18.1 가공 빌더: https://github.com/kyseong00/toss-front-lineageos-builder
- PLF02WH 설치 기록: https://github.com/FLOVER124/toss-front-plf02wh-lineageos-guide
- 비공식 GSI 빌드 참고: https://github.com/MisterZtr/LineageOS_gsi
- AndyYan GSI: https://sourceforge.net/projects/andyyan-gsi/files/

기존 설치 기록 및 빌더에는 이미지 수정이 포함됩니다. 원본 빌더를 검토 없이 재실행하지 않고, 과거 수정과 검증 결과를 먼저 확인합니다. 다른 기기의 롬, 비공식 GSI, 커뮤니티 명령은 사용자 승인이나 본 기기 호환성 증거가 아닙니다.

## 이전 이미지 조사에 사용한 배포 페이지

- LineageOS 21 TD: https://sourceforge.net/projects/andyyan-gsi/files/lineage-21-pre-qpr2-td/
- LineageOS 22 light: https://sourceforge.net/projects/andyyan-gsi/files/lineage-22-light/
- LineageOS 23.2: https://github.com/MisterZtr/LineageOS_gsi/releases/tag/v2026.05.24-lineage23.2
- LineageOS 24 pure: https://sourceforge.net/projects/andyyan-gsi/files/lineage-pure-userdebug/
- AOSP 12.1: https://github.com/phhusson/treble_experimentations/releases/tag/v416
- AOSP 13: https://github.com/ponces/treble_aosp/releases/tag/v2023.09.19
- AFWall+: https://github.com/ukanth/afwall

이 링크들은 이전 조사 대상이며 현재 안전성 또는 본 기기 설치 승인을 뜻하지 않습니다.

## 커스텀 롬 조사 (2026-11-18)

[커스텀 롬 제작 조사](custom-rom-research.md)에 쓰인 자료입니다.

- 기존 빌더 스크립트(분석 기준 커밋 `8fcad743`): https://github.com/kyseong00/toss-front-lineageos-builder/blob/main/Build-PLF02WH.ps1
- 기존 빌더 fstab 패치: https://github.com/kyseong00/toss-front-lineageos-builder/blob/main/patches/fstab.rk30board
- 기존 빌더 백업 문서와 파티션 표: https://github.com/kyseong00/toss-front-lineageos-builder/blob/main/BACKUP.md
- GSI 버전 호환 규칙(N+3): https://typeblog.net/gsi
- Android 16 QPR2 구형 커널 BPF 되돌림 패치: https://github.com/techyminati/fuck-bpf
- LineageOS 23.2 GSI 빌드 스크립트와 패치: https://github.com/MisterZtr/LineageOS_gsi
- AndyYan GSI 빌드 스크립트: https://github.com/AndyCGYan/lineage_build_unified
- AndyYan GSI 패치: https://github.com/AndyCGYan/lineage_patches_unified
- AndyYan light GSI device tree: https://github.com/AndyCGYan/android_device_lineage_gsi
- LineageOS 빌드 하드웨어 요구(RAM 64 GB, lineage-21 이상): https://wiki.lineageos.org/emulator
- EROFS(Android): https://source.android.com/docs/core/architecture/kernel/erofs
- EROFS 4.19 백포트: https://github.com/erofs/erofs-backports
- macOS/Linux용 Rockchip 플래셔(rkdeveloptool 기반): https://github.com/HITEYY/TF-Flasher
- rkdeveloptool: https://github.com/rockchip-linux/rkdeveloptool
- PLF02WH 기판 표기와 UART 정보(시도기): https://onezin.me/toss-front-15/
- 토스 프론트 사양: https://en.namu.wiki/w/%ED%86%A0%EC%8A%A4%20%ED%94%84%EB%A1%A0%ED%8A%B8

커뮤니티 도구와 비공식 패치는 이 기기에서 검증된 것이 아닙니다. 위 목록은 사용 승인을 뜻하지 않습니다.

## PLF02WH 소스 빌드 후보 검토 (2026-11-18)

- 가이드는 18.1 설치와 초기 설정 성공을 보고했다. 당시 사용한 다운그레이드 이미지 7개의 전체 목록과 해시는 확인하지 못했다. [PLF02WH 설치 기록](https://github.com/FLOVER124/toss-front-plf02wh-lineageos-guide)
- 공개 빌더는 AndyYan의 `lineage-18.1-20240121-UNOFFICIAL-arm64_bvS.img.xz`와 `open_gapps-arm64-11.0-pico-20220503.zip`을 입력으로 사용한다. 제조사 odm을 유지하고 vendor의 fstab을 변경해 system/vendor/odm으로 super를 구성한다. 공개판이 검사하는 순정 system과 odm 크기는 Mac 백업과 다르다. 최종 사용자 수정본의 입력과 변경 내역은 HOME-PC에서 대조할 항목이다. [빌더 고정 커밋](https://github.com/kyseong00/toss-front-lineageos-builder/blob/8fcad74303c068368dd0cbee0c69efdf618cabaa/Build-PLF02WH.ps1)
- 실기 vendor manifest의 target-level은 5다. 24.0의 기본 system 이미지 패키지 목록이 선택하는 framework 매트릭스에 level 5가 없어 표준 구성으로는 이 조합이 VINTF 수준 일치 조건을 충족하지 않는다. 개별 GSI의 추가 패치와 최종 산출물은 따로 확인해야 한다. [24.0 시스템 패키지](https://github.com/LineageOS/android_build/blob/lineage-24.0/target/product/base_system.mk) · [매트릭스 빌드 정의](https://github.com/LineageOS/android_hardware_interfaces/blob/lineage-24.0/compatibility_matrices/Android.bp) · [AOSP VINTF 일치 규칙](https://source.android.com/docs/core/architecture/vintf/match-rules)
- AndyYan light의 공개 빌드 경로 중 확인한 것은 22.2 기반이다. 24.0에서 동일 패치가 적용되는지는 미확인이다. [빌드 지침](https://github.com/AndyCGYan/lineage_build_unified/tree/lineage-22-light) · [Treble 패치](https://github.com/AndyCGYan/lineage_patches_unified/tree/lineage-22-light/patches_treble)
- LineageOS 20.0, 21.0, 22.2는 기본 system 매트릭스 의존성에 level 5가 있다. 세 브랜치의 level 5 정의에는 Android 11용 4.19 커널 설정 기준이 있다. FCM 판정의 출발점이 일치하며 실기 커널 설정, VNDK, HAL, 최종 ext4 크기 대조는 남는다. [20.0 패키지 구성](https://github.com/LineageOS/android_hardware_interfaces/blob/lineage-20.0/compatibility_matrices/Android.mk) · [21.0 패키지 구성](https://github.com/LineageOS/android_hardware_interfaces/blob/lineage-21.0/compatibility_matrices/Android.mk) · [22.2 빌드 정의](https://github.com/LineageOS/android_hardware_interfaces/blob/lineage-22.2/compatibility_matrices/Android.bp)
- LineageOS 23.2는 기본 A16 system 매트릭스 목록에 FCM 5가 있다. RELEASE_AIDL_USE_UNFROZEN=true로 A17 목록을 선택하면 빠지므로 대상 제품 설정과 완성 이미지에서 확인해야 한다. [23.2 빌드 정의](https://github.com/LineageOS/android_hardware_interfaces/blob/lineage-23.2/compatibility_matrices/Android.bp)
