# Toss Front 1.5 맞춤 LineageOS

토스 프론트 1.5세대 **PLF02WH**의 LineageOS 빌드·기기 수정·실기 검증과 원격 승인 통신을 기록한 개인 프로젝트입니다. 초기 조사부터 현재 소스, 패치, 설정, 진단 도구와 시험 결과를 함께 보존합니다.

## 확인한 상태

다음은 2026-11-23까지 기록한 결과입니다. 다른 기기에서의 동작이나 완성된 배포용 ROM을 보장하는 목록은 아닙니다.

- **LineageOS 21 / Android 14**: Linux 빌드 호스트에서 GSI를 빌드하고, 경량화·VINTF 보완·super 확장 후 PLF02WH에 설치했습니다.
- **기기 보안**: ADB 인증, SELinux Enforcing, 소프트웨어 키 관리 기반 FBE를 검증했습니다. memtrack 충돌과 Keymaster 인증 토큰 길이 결함을 수정했습니다. 하드웨어 키 보호·metadata encryption·부트로더 잠금은 확보하지 않았습니다.
- **기본 기능**: KeliBoard 시스템 앱 통합, 한국어 입력, 파일 선택·다운로드, MTP 전송, 권한 제어와 카메라 미리보기를 시험했습니다.
- **잠금 상태 구분**: 과거 PIN·CE 잠금 시험은 통과했지만, 이후 사용자가 PIN을 제거해 최신 기기 기록의 화면 잠금은 “없음”입니다.
- **원격 승인**: Mac Studio와 실제 PLF02WH 사이의 WSS·서명 승인·거부·만료·취소·재사용 차단을 검증했습니다. 실제 Mac 인증 호스트에서도 서명 결과에 따른 Allow/Deny를 관찰했습니다. **Mac 암호 입력 없이 화면을 여는 동작과 키체인 연동은 미검증입니다.**

## 읽을 순서

1. [현재 기기 상태와 남은 제약](docs/device-status.md)
2. [GSI 소스 빌드](docs/build-gsi.md), [경량화](docs/slim-gsi.md), [super 확장·설치](docs/super-expansion.md)
3. [안정성 수정](docs/stability.md), [ADB 인증·FBE·Keymaster 검증](docs/security.md)
4. [기본 기능 시험](docs/basic-features.md), [KeliBoard 통합](docs/ime-system.md), [카메라 시험](docs/camera-probe.md)
5. [공통 승인 통신](remote-unlock/README.md), [Mac 인증 시험과 한계](remote-unlock/macos/approval/INSTALLATION.md)
6. [다음 작업 인계](docs/handoff.md), [초기 요구사항](docs/requirements.md), [계획 기록](docs/roadmap.md), [상세 이력](docs/history.md)

## 저장소 구성

- `configs/`: PLF02WH용 VINTF·fstab·KeliBoard·memtrack 설정과 Keymaster 교정 명세
- `patches/`: Soong 메모리 제한, GSI 경량화, ADB 인증, VINTF·memtrack·입력기 패치
- `scripts/build-host/`: Linux 컨테이너 빌드 환경과 실행 스크립트
- `tests/fixtures/`: 실기에서 확인한 VINTF 선언
- `tools/`: 보안·기본 기능·카메라·수동 승인 시험 도구
- `remote-unlock/`: 공통 서명 프로토콜·중계 서버·CLI와 Mac 네이티브 시험 구성
- `docs/`, `.debug-journal.md`, `log/`: 단계별 근거와 작업 기록
- `manifests/`: 전체 revision 고정 매니페스트를 추가할 위치이며 현재는 비어 있습니다.

## 재현 범위와 제외 자료

전체 Android 원본, ROM 이미지, 기기 백업·사용자 데이터, 개인키, 의존성·빌드 출력, 원시 시험 로그와 화면 캡처는 Git에 포함하지 않습니다. 문서의 `private/` 경로는 당시 증거 위치이며 공개 다운로드 경로가 아닙니다. 기기 일련번호와 개인 호스트명은 공개용 가명으로 바꿨습니다.

[빌드 기록](docs/build-gsi.md)에 사용한 주요 소스 커밋과 환경을 남겼지만, 전체 revision 고정 매니페스트와 모든 이미지 조립 절차를 자동화한 것은 아닙니다. 새 checkout만으로 동일 ROM의 완전한 재현을 보장하지 않습니다. KeliBoard APK 등 외부 입력은 문서와 설정의 출처·해시를 확인해 별도로 준비해야 합니다.

공통 승인 코드는 `remote-unlock/README.md`의 검증 명령을 따릅니다. Android·Mac 시험은 각 빌드 도구와 새 시험 키·CA·등록 설정이 필요합니다. 운영용 자격 증명이나 기존 사용자 키를 시험 입력으로 사용하지 않습니다.

## 작업 경계

기기 쓰기·초기화·파티션 변경·부트로더 잠금·macOS 인증 정책 변경은 대상과 복구 범위를 정한 뒤 별도로 진행합니다. 공개 문서에 과거 승인과 실행 명령이 기록돼 있어도 다른 기기에 그대로 실행할 권한이나 재현 보장을 뜻하지 않습니다.

깊은 절전·장기 안정성·전체 복원·OTA와 독립적인 Mac 화면 잠금 해제는 남은 검증 항목입니다. 얼굴 인식·생체정보 수집은 현재 승인 통신 시험에 포함하지 않습니다.
