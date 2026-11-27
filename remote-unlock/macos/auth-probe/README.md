# Mac 인증 플러그인 호출 시험

2026-11-20 전용 시험 권한에서 실제 인증 호스트 호출과 거부 결과를 확인하고 당시 설치·임시 항목을 제거했다. 이후 화면 경로 진단의 설치 상태와 결과는 [후속 시험 기록](../approval/INSTALLATION.md)을 따른다. 별도 권한의 성공을 실제 화면 잠금 해제나 키체인 해제의 성공으로 간주하지 않는다.

## 목적

현재 Mac만 사용할 수 있어 별도의 시험 권한에서 플러그인 로딩과 호출을 먼저 확인한다. 이 코드는 잠금 해제 기능이 아니다. `probe` 메커니즘은 항상 거부하며 네트워크·사용자 자격 증명·키체인에 접근하지 않는다.

플러그인이 호출되면 `org.plf02wh.remoteunlock.authprobe` 로그에 `AUTH_PROBE_INVOKED result=deny`를 남긴다. 후속 진단에서는 `AUTH_PROBE_CONTEXT`에 호출자 UID·세션 상태와 콘솔 상태도 기록한다. 사용자명·자격 증명·힌트·평가 ID 주소는 기록하지 않는다. 이 로그는 권한의 거부 결과와 실제 플러그인 호출을 구분하기 위한 것이며, 호출자 관찰값이 잠금 대상의 신원을 보증하지는 않는다.

## 프로젝트 내부 빌드

```sh
bash remote-unlock/macos/auth-probe/build-local.sh
```

빌드 결과는 프로젝트의 `private/macos-auth-probe-20261120/`에 생성한다. Clang의 `-Wall -Wextra -Werror`, plist 검사, 로컬 ad-hoc 서명 검증과 콜백 시험을 실행한다. 배포용 Developer ID 서명이나 공증을 대신하지 않는다.

| 파일                  | 역할                                            |
| --------------------- | ----------------------------------------------- |
| `PlfAuthProbe.bundle` | 거부 전용 인증 플러그인                         |
| `probe-self-test`     | 직접 모듈을 로드해 호출·거부·해제 콜백을 검사   |
| `run-probe`           | 설치 후 전용 권한의 정확한 정의를 확인하고 요청 |

`probe-self-test`는 로컬 콜백 시험이다. macOS의 인증 호스트에서 로딩됐다는 증거가 아니다. `run-probe`의 거부 결과만으로도 로딩 성공을 판정하지 않으며, 해당 시점의 인증 호스트 로그를 함께 확인해야 한다.

Desktop 아래의 빌드 산출물은 보관·검증용으로 두고, 실제 `run-probe` 호출은 승인된 Shared 시험 폴더에 배치한 사본으로 수행한다. authd가 보호된 Desktop 경로의 호출기 코드를 읽지 못하면 권한 조회가 `-60008`로 실패한다. 2026-11-23에는 커널의 해당 접근 차단과 같은 바이너리의 Shared 실행 성공을 함께 확인했다. 접근 거부 뒤 다른 위치에서 임의로 재시도하거나 TCC 설정을 완화하지 않는다.

기본 호출은 `org.plf02wh.remoteunlock.probe`를 사용한다. `--screen-trial` 하나만 추가로 허용하며, 이때는 `org.plf02wh.remoteunlock.screen-test`의 정의를 확인하고 요청한다. 임의 권한 이름은 받지 않으며 이 옵션도 화면을 잠그거나 잠금을 해제하지 않는다.

2026-11-20 로컬 빌드·plist·서명·콜백 검사가 모두 통과했다. 반환값을 허용으로 바꾼 변이에서는 콜백 시험이 실패했고, 거부로 복구한 최종 빌드가 다시 통과했다. 최종 arm64 실행 파일의 SHA-256은 `f8db53f873af3337486d97baf6d5ce84d8f3705df60e35fe03cf28934762ed48`이다. 시스템 설치와 실제 인증 호스트 호출은 아직 수행하지 않았다.

## 현재 Mac 기준 상태

- macOS 26.6.2, 빌드 25G83.
- MDM 미등록.
- `system.login.screensaver`는 기존 원격 제어 프로그램의 항목과 `use-login-window-ui`를 참조하며 `k-of-n=1`이다.
- `screenUnlockMode` 설정은 존재하지 않는다.
- 전용 시험 권한 `org.plf02wh.remoteunlock.probe`와 설치 경로 `PlfAuthProbe.bundle`은 준비 단계에서 존재하지 않았다.

## 승인 후 수행할 범위

사용자는 2026-11-20 전용 시험물의 관리자 설치·호출 시험·제거를 승인했다. 설치 시도는 원본 번들의 해시를 읽는 단계에서 `Operation not permitted`로 종료했다. 이 단계는 플러그인 복사·권한 등록보다 앞이므로 설치 항목은 생성되지 않았다.

동일 시각 TCC 로그에는 `/usr/bin/perl`로 실행된 `shasum`의 접근 책임 주체가 `com.apple.authtrampoline`이고 요청 서비스가 `SystemPolicyDesktopFolder`인 것으로 나타났다. OmO의 일반 파일 읽기와 관리자 중계 프로세스의 접근 경계가 달랐다. 거부 후 원본에 대한 관리자 읽기를 재시도하거나 다른 경로로 복사하지 않았다. 이후 접근 경로 변경은 사용자에게 별도 설명·승인을 받아야 한다.

이후 사용자는 `/Users/Shared/plf02wh-auth-probe-20261120/`에 시험 번들만 임시 복사하는 경로 변경을 추가 승인했다. 현재 상태는 아래 실기 결과를 따른다.

1. 두 시험 이름이 여전히 비어 있는지 확인한다. 기존 항목이 있으면 덮어쓰지 않는다.
2. `/Library/Security/SecurityAgentPlugins/PlfAuthProbe.bundle`에 빌드한 플러그인을 추가한다. 서명을 검증하고 root 소유·일반 사용자 쓰기 불가 상태로 둔다.
3. 인증 DB에 `org.plf02wh.remoteunlock.probe`만 추가한다. 정의는 `right.plist`의 `PlfAuthProbe:probe` 메커니즘 하나다.
4. 일반 사용자로 `run-probe`를 실행한다. 새 권한의 거부 결과와 실제 인증 호스트의 고정 로그를 함께 확인한다.
5. 시험 후 추가한 권한과 플러그인만 제거한다.

현재 로그인·화면 잠금 권한은 이 시험 권한을 참조하지 않는다. 이 단계에서는 화면을 잠그거나 재부팅하지 않고 `system.login.screensaver`, `screenUnlockMode`, 기존 원격 제어 프로그램, FileVault 설정을 변경하지 않는다.

## 제거 범위

시험에서 새로 만든 항목에만 다음 제거가 적용된다.

```sh
sudo security authorizationdb remove org.plf02wh.remoteunlock.probe
sudo rm -R -- /Library/Security/SecurityAgentPlugins/PlfAuthProbe.bundle
```

다른 이름의 권한·플러그인이나 상위 폴더는 제거하지 않는다. 최초 확인 이후 항목이 다른 내용으로 변경됐다면 자동으로 삭제하지 않고 충돌을 확인한다.

이 호출 시험이 통과해도 실제 화면 잠금 해제나 data-protection keychain의 정상 해제까지 증명하지 않는다. 그 단계는 원격 승인 검증을 연결한 뒤 별도 변경 범위와 복구 절차를 제시해야 한다.

## 승인 후 실기 결과와 정리 완료

공유 폴더 경유 설치의 첫 시도에서는 설치 스크립트의 XML 종료 표식 누락으로 권한만 남았다. 해당 권한을 제거하고 종료 표식을 수정했다. 수정본은 `PROBE_INSTALL_OK`로 종료했고 플러그인과 전용 권한을 설치했다.

일반 사용자 호출 프로그램은 `AuthorizationRightGet` 단계에서 -60008 내부 오류로 종료했다. authd에는 호출 프로세스의 `failed to create code ref 100001`, `failed to register connection`과 UNIX error 1이 기록됐다. 정확한 거부 원인은 아직 확정하지 않았다. 시험 플러그인의 호출 로그는 없으므로 인증 호스트 로딩·호출 성공으로 판정하지 않는다. 내부 오류를 “권한 미등록”으로 표시하던 호출 프로그램의 문구는 수정·빌드했으며 재실행하지 않았다.

설치본의 실행 파일 해시와 전용 권한 정의를 확인한 경우에만 제거하는 관리자 정리 명령을 실행했으나 시간 초과됐다. 이후 읽기 전용 확인에서 `/Library/Security/SecurityAgentPlugins/PlfAuthProbe.bundle`과 `org.plf02wh.remoteunlock.probe`가 남아 있었다. 관련 명령의 실행 프로세스는 확인되지 않았다. 공유 폴더의 임시 복사본은 일반 사용자 권한으로 제거했다.

기존 `system.login.screensaver` 내용은 설치 전과 바이트 단위로 같았고 `screenUnlockMode`도 계속 미설정 상태임을 확인했다. 사용자가 관리자 인증 창을 확인할 수 있는 상태라고 답한 뒤 같은 제거 명령을 재실행했고 `PROBE_CLEANUP_OK`, 종료 0으로 완료했다. 시험 플러그인과 전용 권한은 제거됐고 공유 폴더 임시 복사본도 남기지 않았다.

호출 프로그램 자체의 엄격한 코드 서명 검증은 통과했다. 수정한 `run-probe`의 SHA-256은 `cba92f0352307c50702b36174b80661b49615b5ba9f4a5bc3e197f6645bf1efd`다. 첫 시도를 정리한 시점에는 코드 참조 오류와 Desktop 실행 경로의 관계를 확인하지 못했고, 호출 프로그램까지 공유 폴더로 복사하는 시험도 추가 승인 전이었다.

## 호출 프로그램의 공유 경로 시험

사용자가 호출 프로그램까지 포함한 임시 복사·시험·정리를 추가 승인했다. 동일한 해시의 번들과 `run-probe`를 `/Users/Shared/plf02wh-auth-probe-20261120/`에 복사하고 전용 권한을 다시 설치했다.

이번에는 일반 사용자 UID 501의 호출 프로그램이 권한 조회와 요청까지 진행했고 `PROBE_RIGHT_RESULT status=-60005 release=0`으로 종료했다. 2026-11-20 12:55:40 +09:00 로그에는 실제 `SecurityAgentHelper-arm64` 프로세스가 `/Library/Security/SecurityAgentPlugins/PlfAuthProbe.bundle/Contents/MacOS/PlfAuthProbe`에서 `AUTH_PROBE_INVOKED result=deny`를 남긴 기록이 있었다. 이는 로컬 모의 콜백이 아닌 macOS 인증 호스트의 실제 호출 증거다.

이 결과로 현재 macOS 빌드에서 해당 인증 확장 지점의 호출을 확인했다. 앞선 Desktop 실행의 정확한 거부 원인까지 확정한 것은 아니다.

이후 이번 설치본에 결합된 해시 검사와 관리자 제거 명령이 `PROBE_CLEANUP_OK`, 종료 0으로 완료했다. 시험 권한·플러그인과 두 파일의 임시 복사 폴더를 제거했다. 기존 화면 잠금 규칙은 시험 전과 동일했고 `screenUnlockMode`도 미설정 상태를 유지했다.

실기 로그는 프로젝트 `private/macos-auth-probe-20261120/host-invocation-shared-runner.ndjson`에 보존한다. 원격 승인에 따른 허용 결과와 실제 화면 잠금·키체인 해제는 아직 검증하지 않았다.
