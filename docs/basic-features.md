# 기본 사용 기능 적용과 검증

## 확정한 범위

사용자는 다음 기능 묶음으로 기본 사용 기능을, 한국어 배열로 두벌식을 선택했다. 현재 검증한 ADB 인증·FBE·SELinux와 기준 이미지를 유지한다.

| 기능 | 완료 기준 | 상태 |
|---|---|---|
| 두벌식 입력 | 실제 화면 키보드에서 한글 조합·겹받침·삭제·영문 전환을 확인하고 설정이 유지됨 | 통과 |
| 파일 선택·다운로드·저장 | 일반 앱에서 SAF 생성·열기와 실제 다운로드 완료·내용 일치 확인 | 통과 |
| USB 파일 전송 | MTP 연결과 양방향 시험 파일의 동일 해시 확인, 이후 ADB 인증 유지 | 통과 |
| 앱 권한 | 일반 앱의 런타임 권한 허용·거부에 따라 실제 API 접근 성공·차단 확인 | 통과 |

작업 시작 시 입력기는 AOSP LatinIME 하나였으며, 빌드 소스의 `packages/inputmethods/LatinIME/java/res/xml/method.xml`에 한국어 subtype이 없었다. DocumentsUI·Seedvault·Play 스토어·Play 서비스는 설치돼 있었고 USB 기능은 `adb`였다. 앱 존재나 속성값만으로 해당 기능의 실사용 검증이 끝났다고 판단하지 않는다.

## 설치한 두벌식 입력기

공식 KeliBoard 4.0.1 릴리스를 사용한다. 프로젝트는 HeliBoard 기반이며 두벌식 조합을 지원한다고 명시한다. 구체적인 실기 동작은 아래 시험에서 별도로 확인한다.

- 패키지: `io.github.gplaider.keliboard`, versionCode 4019.
- APK: 22,784,167 bytes.
- 게시된 SHA-256과 다운로드 파일 일치: `f915dcceac3a3871cb6817587f551cb039a9a7ea136c88e30d94e119fd27883a`.
- apksigner 종료 0, v1·v2·v3 검증 통과.
- 서명 인증서 SHA-256: `cda14ac8e6b7b73b73e025e60c9b650ed6cf82b472ad1a951b2ac826adf32276`.
- 실제 APK의 minSdk 21, targetSdk 36, arm64-v8a 포함.
- 실제 APK에 INTERNET 권한 없음. 연락처·사진 등 선택 권한은 자동으로 부여하지 않는다.

apksigner는 일부 META-INF 항목의 JAR 서명 경고도 출력했다. 경고 원문을 보존했으며 APK를 수정하거나 경고를 숨기지 않았다. 재현용 배포 정보는 `configs/plf02wh/keliboard.json`, 검증 증거는 `private/features-20261119/`에 있다.

첫 단계에서는 일반 앱으로 설치했고 기존 LatinIME를 복구용으로 유지했다. 이후 사용자의 별도 요청으로 KeliBoard를 product 기본 앱에 통합하고 적용·재부팅 검증까지 완료했다. 자세한 내용은 [기본 앱 통합 기록](ime-system.md)을 따른다.

설치는 Success였고 실제 서비스 ID `io.github.gplaider.keliboard/helium314.keyboard.latin.LatinIME`를 활성화·선택했다. 설정 화면에서 한국어 기본 배열과 영어(미국)를 활성화했다. 다른 앱으로 이동한 뒤에도 두 언어가 선택 목록에 남았다. 진단 앱의 실제 화면 키로 “한글 값”을 입력했고 composing=3..4였다. 삭제 한 번으로 “갑”이 됐으며 ㅅ·ㅣ를 이어 입력하면 “갑시”로 재조합됐다. 스페이스로 확정하면 composing=-1..-1이었다. 스페이스 길게 누르기로 영문 QWERTY로 전환해 “abc”를 입력했다. 완성 문자열을 ADB로 주입한 시험은 아니다.

첫 검증에서는 영어 지역명 불일치로 기록했다. 이후 기본 앱 통합 요청을 받고 실제 저장값을 읽자 `en-CA`였고 다시 연 설정 화면도 캐나다가 켜져 있었다. 앞선 미국 선택 확인이 잘못된 것이었다. 미국으로 바로잡은 뒤 저장값 `en-US`와 선택창의 “영어(미국)”이 일치했다. 원본 APK의 번역 수정은 필요 없었다. 후속 [기본 앱 통합](ime-system.md)과 재부팅 후에도 언어 표시·한영 입력·선택 유지가 정상임을 확인했다.

UI 검증 중 반복 잠금을 피하려고 기존 `stay_on_while_plugged_in=0`, `screen_off_timeout=60000`을 기록한 뒤 USB 연결 시 화면 유지 설정만 적용했다. 종료 시 화면 유지 설정을 원래 0으로 복원했다. 화면 잠금 PIN이나 인증 정책은 변경하지 않았다.

## 검증용 앱

키보드 입력·SAF·DownloadManager·런타임 권한을 일반 앱 UID에서 검사하는 임시 진단 앱을 제작했다. ROM 설치 대상에 넣지 않으며 실제 테스트 결과와 생성한 파일·다운로드 ID를 기록한다. 사용자 연락처의 이름·내용이나 PIN은 수집하지 않는다. 검사 후 진단 앱과 자체 생성 파일을 정리한다.

첫 APK는 서명·manifest 검사는 통과했지만 `classes.dex`가 없어 실행 대상으로 거부했다. `installable:false`는 유지하고 `compile_dex:true`를 명시한 수정본의 빌드는 9분 12초, 종료 0이었다. 수정 APK의 v3 서명·manifest·네트워크 정책·DEX·ZIP 검사를 통과한 후 설치했다. SHA-256은 `070e9ae532b0c1aefdd49e61e8e54bf89f4a0780bc5040563b2625e7a48fa824`, UID는 10179다.

## SAF와 권한 실기 결과

문서 선택기의 Download 폴더에 `plf02wh-test-6318f73a-badc-443c-b354-30213aefd002.txt`를 저장하고 다시 선택해 읽었다. 25바이트 마커와 SHA-256 `eec150a8750e7765479a038592600ef339ea943ad8ac2545915a613b32c21488`가 일치했다. 파일의 생성·선택·쓰기는 실제 SAF 경로를 사용했다.

READ_CONTACTS 미허용 상태와 실제 권한 대화상자에서 거부한 상태 모두 API가 SecurityException을 반환했다. 같은 대화상자에서 허용하면 GRANTED 및 API=SUCCESS, count=0이었다. 연락처 행의 이름·값은 읽지 않았고 연락처를 생성하거나 수정하지 않았다.

## 다운로드·USB 시험 준비

다운로드는 사용자 데이터가 없는 61바이트 로컬 시험 파일을 사용한다. SHA-256은 `c00e49b062a723b5a3b803bb37da720d775f1f4b1fc1c2a20a45727fa5e19f8e`다. 호스트 127.0.0.1:8765의 HTTP 응답이 같은 해시임을 확인했고 인증된 ADB reverse로 연결했다. 시험 종료 후 reverse와 서버를 정리한다.

DownloadManager ID=1, 파일명 `plf02wh-test-download-c046ff37-16c4-45b6-88d0-0aeed2385d11.txt`로 요청했다. 첫 조회는 PENDING이었고 실제 JobScheduler에서 CONNECTIVITY 제약이 충족되지 않았다. 당시 기기의 Active default network는 none이었고 다운로드 작업은 INTERNET·VALIDATED 네트워크를 요구했다. 스케줄러 제약을 우회하지 않고 사용자의 정상 네트워크 연결 후 검증을 이어갔다.

이후 사용자가 네트워크를 연결하자 시험 파일이 실제로 저장됐으며 파일 SHA-256이 원본과 일치했다. 진단 앱을 다시 실행한 뒤 결과 조회에서 NumberFormatException이 발생했다. 진단 앱 자체의 SharedPreferences XML에는 `<string name="downloadIds">1&#10;    </string>`가 저장돼 있었다. 줄바꿈만으로 나누면 공백 문자열이 별도 토큰으로 남아 숫자 변환이 실패한다. 앱 소유 파일만 임시 root ADB로 확인했고 바로 UID 2000으로 복원했다.

ID 목록을 끝 줄바꿈 없이 저장하고 읽기 경계에서 공백을 정규화하도록 수정했다. 수정본 빌드는 2분 56초, 종료 0이었고 APK 서명·DEX·ZIP·권한 검사도 통과했다. 최종 진단 APK SHA-256은 `bd8964ce3298573a7bc0137f483f09f287a8b93f63a0aaea968d0fbea433c24a`다. 기존 앱 데이터를 보존해 갱신한 뒤 동일한 ID 1을 조회했고 `SUCCESSFUL(8)`, reason=0, 61바이트, 원본 SHA-256 일치를 확인했다. 실기 실패 화면은 `download-success-hash.png`, 수정 후 결과는 `fixed-download-verified.png`에 보존했다. 설치 과정에서 Google로 APK를 보내는 선택은 거절했고 Play Protect 설정은 끄지 않았다.

Mac에 MTP 클라이언트가 없어 기존 libusb 1.0.30을 사용해 공식 libmtp 1.1.23 소스를 프로젝트 내부에서 빌드했다. 공식 소스 archive SHA-256 `74a2b6e8cb4a0304e95b995496ea3ac644c29371649b892b856e22f12a0bdeed`가 일치했고 빌드는 종료 0이었다. 시스템 설치·sudo는 사용하지 않았다.

`svc usb setFunctions mtp` 적용 후 실제 USB 구성은 `mtp,adb`였다. Mac의 `ptpcamerad`가 MTP 인터페이스를 독점해 첫 연결은 실패했다. IORegistry에서 인터페이스 0의 점유 프로세스와 USB 일련번호 `PLF02WH_SERIAL`을 확인했다. 시험 동안 `icdd`의 자동 재점유를 잠시 멈추고 카메라 점유 프로세스를 종료한 뒤 전송했다. 종료 경로의 trap으로 `icdd`를 다시 실행 상태로 돌렸고 상태 S를 확인했다. 시스템 서비스 설정을 영구 변경하지 않았다.

한글 이름의 `plf02wh-mtp-a4e17fa4-9d4b-4489-a3c9-289c8c2e2cdc-한글.bin` 1 MiB를 실제 MTP로 전송했고 생성된 파일 ID 32로 다시 받았다. 원본·기기 저장 파일·MTP 수신 파일 SHA-256은 모두 `06b7bbfb7824aa03382051691630eb26de85102d1b08a81e907ec0744cd8a286`으로 일치했다. 전송 후에도 ro.adb.secure=1, shell UID 2000, SELinux Enforcing이었다. ADB는 기기 파일의 해시 확인에만 사용했고 전송 자체를 대신하지 않았다.

MTP의 장치 정보 일련번호는 USB 일련번호와 다른 `PLF02WH_MTP_SERIAL`이었다. 두 식별자는 공개용 가명이다. 단일 장치의 USB 버스·주소·VID/PID와 IORegistry를 대조했다. libmtp의 VID/PID 이름표는 다른 제품명으로 나왔지만 실제 장치 모델 응답은 `TrebleDroid with GApps`였다.

완료된 SAF·MTP 시험 파일은 기기에서 삭제했고 임시 앱의 READ_CONTACTS 권한도 회수했다. 다운로드 ID 1은 공급자 API로 제거했으며 이후 일반 ADB UID 2000으로 복귀했다. 진단 앱 삭제는 Success였다. 로컬 서버를 종료했고 reverse 연결은 남아 있지 않았다. 임시 UI 덤프와 불필요한 Wi-Fi 화면 캡처도 제거했다. 화면 유지 설정 복원 후 mStayOn=false와 Dozing 상태를 확인했다.

## 사용 시 참고와 남은 범위

- 최초 묶음에서는 KeliBoard를 일반 앱으로 설치했으며, 후속 요청으로 ROM의 product 기본 앱에 통합했다. 기존 일반 설치본은 UPDATED_SYSTEM_APP으로 남아 있다. 설치 artifact는 `configs/plf02wh/keliboard.json`으로 고정했다.
- 한영 전환은 스페이스를 길게 눌러 입력 방법을 선택하면 된다. 마지막 선택은 한국어로 돌렸다.
- USB는 이번 연결에서 `mtp,adb`로 시험했다. 연결을 새로 할 때는 USB 설정에서 파일 전송을 선택한다. Mac의 자동 카메라 서비스가 MTP를 독점하면 클라이언트 연결이 실패할 수 있다.
- 기본 기능 네 가지는 통과했다. 백업·복원, 방화벽, OTA, 장기 안정성, 깊은 절전은 이번 묶음의 완료 항목이 아니다.
