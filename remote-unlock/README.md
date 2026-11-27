# 공통 승인 중계

PLF02WH와 Mac이 중계 서버에 각각 연결하는 승인 프로토콜과 참조 클라이언트다. 서버와 Mac CLI는 Bun으로 실행하고, Android 수동 승인 시험 앱은 Java로 구현했다. 메시지 계약은 [PROTOCOL.md](PROTOCOL.md)에 있다.

현재 구현한 것은 서명된 승인·거부의 전달과 검증이다. **macOS 화면 잠금 해제는 구현·검증되지 않았다.** 요청 CLI는 승인 후에도 `OS_UNLOCK=unavailable`을 출력한다. 얼굴 인식은 포함하지 않는다. 2026-11-23에는 사용 중인 Mac Studio를 임시 서버로 삼아 실제 PLF02WH 시험 앱과의 LAN 왕복을 검증했다.

Mac 네이티브 구성은 [설계 초안](macos/approval/CONTRACT.md)을 따른다. Swift와 jose의 교차 검증 22개와 실제 로컬 WSS 시험 5개가 통과했다. WSS 시험은 승인·거부·제어 파이프 취소와 미신뢰 CA·잘못된 호스트명 차단을 확인한다. 공통 서버 시험과 Mac 전용 시험은 분리했으며 후자는 `bun run test:macos`로 실행한다.

Mac 시험에는 Xcode의 Swift 컴파일러와 OpenSSL 3이 필요하다. OpenSSL 기본 경로는 `/opt/homebrew/opt/openssl@3/bin/openssl`이며 `OPENSSL_BIN`으로 지정할 수 있다. 시험마다 임시 CA와 서버 인증서를 새로 만들고 종료 시 제거한다. 시스템 신뢰 저장소는 변경하지 않는다. 별도로 설치용 보조 프로그램과 인증 플러그인을 실제 호스트에 임시 설치해 전용 권한의 승인·거부·만료·연결 취소를 확인했고 모두 제거했다. [설치 시험 결과와 복구 기록](macos/approval/INSTALLATION.md)을 확인한다.

## 검증

```sh
bun install --frozen-lockfile
bun run typecheck
bun run lint
bun run format:check
bun test ./tests --timeout 15000
```

개발에 사용한 Bun CLI는 1.4.2다. 이 버전에 없는 내장 타입·포맷 명령 대신 프로젝트에 설치한 TypeScript와 Oxfmt를 사용한다.

## 로컬 실행

프로젝트 루트의 `private/` 디렉터리는 버전 관리에서 제외한다. 아래 명령은 그 안에 새 디렉터리를 만들고 시험용 키를 생성한다. 이미 존재하는 디렉터리나 파일을 덮어쓰지 않는다.

```sh
cd remote-unlock
bun src/provision.ts ../private/remote-unlock-demo
```

| 생성 파일               | 역할                               |
| ----------------------- | ---------------------------------- |
| `registry.json`         | 공개키와 허용된 장치·계정 조합     |
| `mac.private.json`      | 시험 요청자 개인키, 파일 권한 0600 |
| `approver.private.json` | 시험 승인자 개인키, 파일 권한 0600 |

`mac-demo`, `device-demo`, `local-session`은 시험용 식별자다. 실제 Mac 계정이나 PLF02WH의 등록을 대신하지 않는다. 운영에서는 등록 상대의 공개키를 별도 경로로 확인하고, 개인키는 각 장치에만 둔다. 이 개발용 키는 파일에 저장되며 하드웨어 보호를 주장하지 않는다.

서버 터미널:

```sh
REGISTRY_FILE=../private/remote-unlock-demo/registry.json \
bun src/server.ts
```

승인자 터미널을 먼저 실행한다:

```sh
REGISTRY_FILE=../private/remote-unlock-demo/registry.json \
CREDENTIAL_FILE=../private/remote-unlock-demo/approver.private.json \
RELAY_URL=ws://127.0.0.1:8787/v1/relay \
bun src/client-cli.ts approve
```

요청자 터미널:

```sh
REGISTRY_FILE=../private/remote-unlock-demo/registry.json \
CREDENTIAL_FILE=../private/remote-unlock-demo/mac.private.json \
RELAY_URL=ws://127.0.0.1:8787/v1/relay \
bun src/client-cli.ts request device-demo local-session
```

승인자 화면에서 상대와 계정을 확인하고 30초 안에 `APPROVE` 또는 `DENY`를 입력한다. 한 번의 요청을 처리하면 CLI는 종료한다.

## 외부 서버 구성

| 환경 변수                       | 설명                                                                |
| ------------------------------- | ------------------------------------------------------------------- |
| `REGISTRY_FILE`                 | 공개키·허용 관계 설정 파일, 필수                                    |
| `HOST`                          | 기본 `127.0.0.1`. 외부 인터페이스에 직접 바인딩하려면 TLS 설정 필수 |
| `PORT`                          | 기본 `8787`                                                         |
| `TLS_CERT_FILE`, `TLS_KEY_FILE` | 서버 인증서와 키 경로, 함께 지정                                    |
| `RELAY_URL`                     | 클라이언트의 `wss://호스트/v1/relay` 주소                           |
| `CREDENTIAL_FILE`               | 해당 클라이언트의 개인키 파일, 그룹·다른 사용자 접근 불허           |

인증서 검증을 끄는 옵션은 제공하지 않는다. 사설 CA 시험에서는 해당 프로세스의 `NODE_EXTRA_CA_CERTS`에 시험 CA를 지정할 수 있다. 시스템 신뢰 저장소를 바꿀 필요는 없다.

서버는 `/health`와 `/v1/relay`만 제공한다. 브라우저 Origin이 있는 연결은 받지 않고, 등록된 네이티브 클라이언트의 연결별 서명을 확인한다. 연결은 최대 128개, 인증 대기는 10초다. 각 장치는 활성 연결 하나만 가질 수 있으며 요청자와 승인자 각각 대기 요청 하나만 허용한다. 요청 ID는 만료 전까지 보존하되 최대 4096개로 제한한다.

등록 설정은 기동 때 읽는다. 공개키나 허용 관계 변경·폐기 후에는 서버를 재시작해야 한다. 종료된 연결의 승인을 큐에 넣었다가 재접속 후 실행하지 않는다. 네트워크 장애는 승인 실패로 처리한다.

외부 서버의 주소·인증서·배포 대상은 아직 지정하지 않았고 실제 외부 배포도 하지 않았다.

## Mac 연동 상태

확인한 호스트는 macOS 26.6.2, 빌드 25G83이며 MDM에 등록돼 있지 않다. CLI에서 WSS 승인 메시지를 검증하는 것은 가능하지만, 이것만으로 잠금 화면을 해제하지는 않는다.

- 현재 `system.login.screensaver`는 `k-of-n=1`이며 `com.openai.sky.CUAService.AuthorizationPlugin.remote`, `use-login-window-ui`를 순서대로 참조한다. 기존 프로그램의 인증 규칙을 기본값으로 덮어쓰면 안 된다. `screenUnlockMode` 설정은 존재하지 않는다.
- Authorization Plug-in은 별도 관리자 설치와 인증 정책 변경이 필요하다. Apple DTS는 화면 잠금 해제 경로의 호환성 문제와 data-protection keychain이 풀리지 않는 문제를 설명한다. 이 호스트에서 동작한다고 검증하지 않았다.
- Platform SSO는 관리 등록과 호환 확장·IdP 연동이 필요한 별도 경로다. 현재 중계 서버는 그 IdP나 keybag 연동 구현이 아니다.
- [전용 시험물](macos/auth-probe/README.md)의 첫 Desktop 호출은 인증 서비스 내부 오류로 끝났다. 호출 프로그램까지 공유 경로로 옮기는 추가 승인 후에는 실제 `SecurityAgentHelper-arm64`의 플러그인 호출과 예상한 거부 결과를 확인했다. 시험 권한·플러그인과 임시 복사본은 모두 제거했다. 기존 화면 잠금 규칙과 미설정 screenUnlockMode는 그대로였고 키체인·로그인·FileVault 설정은 변경하지 않았다. 이 첫 진단은 항상 거부하는 플러그인의 호출만 검증했다.
- 후속 조건부 승인 구성은 실제 `SecurityAgentHelper-arm64`에서 서명된 승인에만 전용 권한의 status=0을 반환했다. 서명된 거부·30초 만료·승인자 연결 종료는 status=-60005였다. 이 시험은 같은 Mac의 시험 키와 CLI를 사용했고, 실제 화면 잠금 해제나 키체인 정상 해제를 검증한 것은 아니다. 전용 권한·번들·키·공유 임시 파일을 제거했으며 기존 screensaver 규칙은 원본과 같았다.

## 2026-11-20 실행 결과

Mac 전용 시험은 2개 파일의 27개 시험·45개 assertion이 통과했다. Swift 6 경고 오류 처리 빌드, 타입·린트·포맷 검사도 통과했다. 최초 TLS 실패는 시험 인증서의 ServerAuthEKU 조건 불충족으로 확인했고 승인된 범위에서 발급 프로파일을 수정했다. 이어 파이프 취소 시 발견한 Swift 격리 문맥 오류는 전역 큐 콜백을 `@Sendable`로 명시해 수정했다. 취소 시험은 종료 2, 빈 stderr, 승인 결과 없음, 중계 서버의 취소 통지를 확인한다.

최종 타입·타입 기반 린트·포맷 검사가 통과했고 3개 파일의 60개 시험이 모두 통과했다. 중복 승인 소비, 허용 계정, 연결별 nonce 검증을 각각 제거했을 때 관련 시험이 실패하는 것도 확인했다. 변이 코드는 원래 바이트와 동일하게 복구한 뒤 전체 시험을 다시 통과했다.

로컬 loopback의 실제 WebSocket 연결과 독립된 요청자·승인자 키로 승인·거부 전달을 시험했다. 별도로 하루짜리 시험 인증서를 만든 WSS 서버에 실제 CLI 두 개를 연결했다. 해당 프로세스에만 시험 CA를 지정했을 때 `DECISION=approve METHOD=manual`, `OS_UNLOCK=unavailable`로 종료했다. CA를 지정하지 않은 클라이언트는 연결을 거부하고 종료 1을 반환했다.

이 시험은 같은 Mac에서 수행했다. 외부 서버 배포나 PLF02WH 네트워크 클라이언트 실기 시험을 대신하지 않는다. WSS 시험 서버와 두 CLI는 종료했다. 시험 키와 인증서는 저장소 밖으로 전송하지 않았으며 프로젝트의 `private/remote-unlock-20261120/`에 보관한다.

공식 참고:

- [Apple Authorization Plug-in](https://developer.apple.com/documentation/security/extending-authorization-services-with-plug-ins)
- [화면 잠금 해제와 screenUnlockMode 관련 DTS 답변](https://developer.apple.com/forums/thread/737268)
- [data-protection keychain 문제 FB13128730](https://developer.apple.com/forums/thread/796487)
- [Platform SSO 관리 설정](https://developer.apple.com/documentation/devicemanagement/extensiblesinglesignon)

## 2026-11-23 Mac Studio와 실제 PLF02WH의 LAN 시험

사용자가 외부 서버 준비보다 현재 사용 중인 Mac Studio에서의 시험을 요청했다. Mac의 `192.168.0.202:18788`에만 WSS 서버를 열고, 같은 LAN의 PLF02WH `192.168.0.26`이 직접 연결했다. ADB는 시험 앱 설치·공개키 추출·버튼 조작·로그 수집에 사용했으며, 승인 통신은 USB 포트 전달 없이 Wi-Fi로 오갔다.

시험 앱은 [tools/approval-probe](../tools/approval-probe/)에 있다. Android Keystore에서 앱 전용 P-256 키를 생성하고 공개키만 중계 등록 파일에 넣었다. 개인키는 장치 밖으로 내보내지 않았다. 해당 장치에서 하드웨어 키 보호를 제공한다고 주장하지 않는다. Mac 요청자 키는 별도의 새 시험 키를 사용했다.

TLS는 LAN IP를 SAN으로 가진 하루짜리 서버 인증서와 분리된 시험 CA를 사용했다. 앱은 번들에 넣은 시험 CA만 신뢰하고 호스트명 검증을 유지한다. Mac CLI는 해당 프로세스의 `NODE_EXTRA_CA_CERTS`로 CA를 지정했다. 시스템 신뢰 저장소, macOS 인증 정책, ROM, 카메라 시험 앱은 변경하지 않았다.

| 실제 시험         | 결과                                                                           |
| ----------------- | ------------------------------------------------------------------------------ |
| 장치 연결 인증    | 장치 Keystore 키의 ES256 서명을 기존 TypeScript 중계가 검증                    |
| 거부 버튼         | Mac에서 `DECISION=deny METHOD=manual`, 종료 0                                  |
| 승인 버튼         | Mac에서 `DECISION=approve METHOD=manual`, 종료 0                               |
| 응답 없이 만료    | 장치가 만료를 표시하고 연결을 닫음. Mac은 `cancelled`로 종료하며 승인하지 않음 |
| 대기 중 연결 종료 | Mac이 `cancelled`로 종료하고 장치의 승인·거부 버튼 비활성화                    |
| 실제 응답 재사용  | 같은 장치 서명을 두 번 소비하려는 시도에 `replayed`                            |
| 원본 요청 재사용  | 같은 요청 JWS 재전송에 서버가 `duplicate_request` 반환                         |

위 자동 시험의 버튼은 에이전트가 ADB 입력으로 조작했다. 이 회차는 실제 사람의 직접 승인이나 생체 인증을 검증한 것이 아니다. 승인·거부 모두 Mac 출력에 `OS_UNLOCK=unavailable`이 명시됐으며 OS 잠금 해제는 시도하지 않았다.

### 앱과 검증 구성

앱 권한은 `INTERNET` 하나다. 연결·대기·요청·완료·만료·취소 상태를 한국어로 표시하며, 검증된 요청 하나에만 승인·거부 버튼을 활성화한다. 응답 선택 시 대기 상태를 먼저 소비하고, 연결 종료·앱 중단·만료 시 무효화한다. 실제 800×1280 화면에서 초기·요청·거부·승인·만료·취소 상태의 글자와 버튼을 확인했다. 데스크톱 UI나 다른 화면 크기에 대한 검증은 아니다.

Nimbus JOSE JWT 10.10, Java-WebSocket 1.6.0, SLF4J 2.0.13을 사용한다. [빌드 스크립트](../tools/approval-probe/build-local.sh)는 버전과 SHA-256을 고정하고 프로젝트의 `private/` 아래에만 라이브러리를 받는다. JDK 17, Android 플랫폼 34, Build Tools 36.1.0을 사용하며 최소 API는 30이다. `debuggable=true`인 로컬 시험 APK이고 배포용 앱이 아니다.

| 명령 (`remote-unlock/` 기준)                               | 용도와 전제                                                                                    |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `bash ../tools/approval-probe/build-local.sh "$TRIAL_DIR"` | 새 시험 디렉터리의 `config.json`과 `tls/ca.pem`을 포함해 APK 생성                              |
| `bash ../tools/approval-probe/tests/run-protocol-tests.sh` | JVM에서 실제 키로 프로토콜 경계 검사. 빌드 라이브러리 준비 필요                                |
| `bun tests/device-replay.ts "$TRIAL_DIR" "$RELAY_URL"`     | 실제 장치가 거부한 응답과 원본 요청의 재사용 검사. 새 시험 키·등록·TLS 설정과 연결된 장치 필요 |

`config.json`의 필드는 `version=1`, `relayURL`, `relayId`, `requesterId`, `approverId`, `account`, `requesterPublicKey`다. 이번 식별자는 각각 `relay-demo`, `mac-demo`, `device-demo`, `mac-studio-test`였으며 실제 로그인 계정의 권한을 부여하지 않는다. 앱 첫 실행으로 생성되는 `files/public-key.json`의 공개 JWK를 등록 파일의 승인자 키로 사용한다. 앱을 재설치해 키가 바뀌면 새 공개키를 등록하고 중계를 다시 시작해야 한다.

JVM 검사는 114개 assertion과 82개 거부 사례를 통과했다. 계정 결합 검사를 제거한 변이는 해당 시험에서 실패했고 복원 후 통과했다. 앱 Java 소스는 `--release 8 -Xlint:all -Werror`로 컴파일됐고 APK 서명이 검증됐다. 실제 장치 재사용 검사 스크립트도 타입·린트·형식 검사와 LAN 실행을 통과했다.

### 시험 중 수정과 정리

Build Tools 34.0.0의 D8 8.2.2-dev는 SLF4J `Level.class`에서 내부 NullPointerException으로 실패했다. 앱 소스나 의존성을 완화하지 않고 이미 설치돼 있던 Build Tools 36.1.0으로 바꿨을 때 동일 입력의 APK 빌드가 통과했다.

첫 요청은 장치 화면이 기본 60초 절전으로 꺼지면서 앱의 중단 처리로 연결이 닫혀 `peer_offline`이 됐다. 전역 절전 설정을 바꾸는 대신 명시적으로 연결한 동안에만 앱 창의 `FLAG_KEEP_SCREEN_ON`을 사용하도록 수정했다. 연결 종료·실패·앱 중단 시 해제한다.

시험 후 중계와 로그 감시를 종료하고 앱을 제거했다. Mac 요청자 개인키, TLS 키·인증서, 이번 개발 서명 키도 제거했다. 소스, 공개 설정, APK와 증거는 남겼다. 로그·화면 증거는 프로젝트 `private/approval-probe-20261123/lan.805wzu/`에 있으며, 승인·거부·만료·취소·재사용 로그를 각각 구분했다. 비밀키와 TLS 원본을 제거했으므로 이 증거 디렉터리만으로 서버를 다시 실행할 수는 없다.

### 사용자가 직접 누른 승인

자동 시험 정리 후 사용자가 직접 버튼을 누를 수 있다고 답해, 같은 앱 코드에 새 시험 키·CA를 넣어 별도 회차를 준비했다. 첫 요청은 입력 없이 만료됐다. 사용자가 기기 화면을 보고 있다고 다시 확인한 뒤 새 요청을 보냈고, 이 회차의 승인 버튼은 에이전트가 조작하지 않았다.

2026-11-23 13:42:03.717(+09:00)에 장치가 요청 `af0fdc4c-26c5-46bf-b8cf-4f7287eb94a8`을 표시했다. 13:42:05.307에 응답 서명을 시작하고 13:42:05.354에 전달 완료를 기록했다. Mac은 `DECISION=approve METHOD=manual`, `OS_UNLOCK=unavailable`, 종료 0을 반환했다. 사용자도 “승인을 눌렀어”라고 확인했다. 실제 사람의 버튼 입력부터 장치 서명, LAN 중계, Mac 검증까지 확인한 결과이며, 실제 Mac 잠금 해제 성공을 뜻하지 않는다.

증거는 `private/approval-probe-20261123/manual.NwljG2/`의 `device.log`, `human-approve-ready-request.log`, `human-approve-delivered.png`에 있다. 첫 만료 요청은 `human-approve-request.log`로 구분했다. 이후 서버·로그 감시를 종료했고 시험 앱 제거는 `Success`였다. 이 회차의 Mac 개인키·TLS 자료·개발 서명 키도 제거했다. 현재 실행 중인 시험 서버나 설치된 승인 시험 앱은 없다.
