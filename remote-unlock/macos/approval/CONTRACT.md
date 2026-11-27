# Mac 원격 승인 시험 구성

현재 구현 상태: 별도 권한의 서명된 승인·거부·만료·취소를 검증했다. 실행 UID와 대상 UID를 분리한 로컬 정책·파이프 v2를 사용해, 실제 잠금 호스트 UID 92에서 PLF02WH의 서명된 응답을 받아 승인 시 `allow=1 helper_exit=0`, 거부 시 `allow=0 helper_exit=0`을 반환하는 것도 확인했다. 다만 사용자는 Mac 암호를 먼저 입력한 뒤 장치 버튼을 눌렀고, 암호 입력 전에는 장치 버튼이 활성화되지 않았다고 확인했다. 암호 입력 없는 독립적인 화면 해제·재잠금 보장과 키체인 연동은 미검증이다. 설치 영향·시험 증거·복구 범위는 [INSTALLATION.md](INSTALLATION.md)를 따른다.

2026-11-20 사용자 승인 후 임시 루트 CA와 서버 인증서를 분리하고 서버 인증서에 `serverAuth`, CA:FALSE, 정확한 호스트명을 명시했다. 신뢰하지 않는 CA와 잘못된 호스트명을 거부하는 조건은 유지했다. CA는 프로젝트 임시 파일과 시험 프로세스에서만 사용하며 시스템 신뢰 저장소에는 추가하지 않는다. 시험 종료 시 인증서와 키를 제거한다.

## 범위

로컬 모드는 `isolated-right-test`와 `screen-trial`로 구분한다. 네이티브 메커니즘 이름은 각각 기존 `approval`과 새 `screen-trial`이다. 전자는 기존 별도 권한 시험 동작을 보존한다. 후자는 한 Mac의 한 로컬 콘솔 로그인이 요청 동안 유지되는 조건의 시험이며, 빌드·로컬 검증 후 설치 영향과 복구 범위를 제시하고 사용자 승인·준비 확인을 받는다.

서명된 네트워크 프로토콜은 기존 v1을 유지한다. action은 `screen-unlock`이며 account는 모드에 따라 `isolated-right-test` 또는 `screen-trial-uid-<대상 UID의 정규 십진수>`다. 별도 권한 성공, 실제 화면 해제, 키체인 사용 가능성을 각각 구분한다.

## 구성과 신뢰 경계

- 플러그인은 관리자 소유의 고정 경로에 있는 보조 프로그램만 실행한다. 임의 명령·환경·작업 폴더·사용자 힌트가 실행 파일이나 정책을 선택하게 하지 않는다.
- 보조 프로그램은 Swift의 CryptoKit·URLSession으로 표준 ES256/JWS와 WSS를 처리한다. 기존 TypeScript 구현과 상호 검증한다.
- 공개 정책에는 중계 URL·ID, 요청자·승인자의 ID와 공개키, 시험 계정, 시험 요청자 키 경로를 고정한다. 정책과 실행 파일은 root 소유이며 일반 사용자가 바꿀 수 없어야 한다.
- 요청자 시험 키는 별도 생성하며 실제 Mac 암호·키체인 항목을 읽지 않는다. 요청자 키의 공개키가 정책의 고정 공개키와 같아야 한다. 승인자 개인키는 보조 프로그램에 제공하지 않는다.
- 보조 프로그램의 서명과 hardened runtime을 확인하며 JIT·미서명 코드·DYLD 환경·라이브러리 검증·디버깅 예외를 추가하지 않는다.

## 호출별 파이프 계약

플러그인은 호출마다 새 generation UUID, requestId UUID, 32바이트 nonce와 30초 이내의 issuedAt·expiresAt을 만든다. 플러그인과 자식 사이의 상속된 전용 파이프만 사용한다. 공유 파일·로컬 HTTP 응답·임의 CLI 출력이나 종료 코드만으로 허용하지 않는다.

stdin 첫 줄은 아래 필드만 가진 JSON이다. 최대 4096바이트이며 추가 입력이나 EOF는 취소로 취급한다.

```json
{
  "version": 2,
  "mode": "screen-trial",
  "account": "screen-trial-uid-501",
  "context": {
    "executionUID": 92,
    "callerSecuritySession": 100023,
    "attributes": 8240,
    "consoleUID": 501,
    "cgUID": 501,
    "onConsole": true,
    "loginDone": true
  },
  "generation": "UUID",
  "requestId": "UUID",
  "nonce": "canonical-base64url-32-bytes",
  "issuedAt": 0,
  "expiresAt": 30
}
```

위 값은 형식 예시다. 실제 실행에는 새 난수와 현재 Unix 초를 사용한다.

`isolated-right-test`에서는 account도 같은 값이고 context는 반드시 null이다. `screen-trial`에서는 native owner가 공개 시스템 API로 직접 캡처한 context를 넣는다. mode·account·context와 기존 필드 이외의 값은 거부한다. 로컬 v1 입력은 수용하지 않으며 테스트 호출기도 v2로 함께 갱신한다.

보조 프로그램은 최대 두 개의 JSON 줄을 stdout에 쓴다. 줄당 최대 4096바이트다.

| kind     | 필드                                                                                       |
| -------- | ------------------------------------------------------------------------------------------ |
| `bound`  | version=2, mode, account, context, generation, requestId, requestHash, expiresAt           |
| `result` | version=2, mode, account, context, generation, requestId, requestHash, expiresAt, decision |

`bound`는 실제 서명한 요청의 해시와 만료를 보고한다. `result`는 검증된 승인자의 응답이며 decision은 `approve` 또는 `deny`다. 오류나 정상 결과 없는 종료는 허용으로 처리하지 않는다. 개인키·JWS 원문은 stdout·stderr에 기록하지 않는다.

플러그인은 generation·요청 ID·원문 해시·만료와 자체 단조 시계 제한을 확인하고 한 번만 결과를 전달한다. 취소가 먼저 확정되면 이후 결과가 허용으로 바뀔 수 없다. helper 종료 코드가 0이어도 유효한 결합 결과가 없으면 거부한다.

두 응답은 최초 invocation의 mode·account·context를 그대로 되돌려야 한다. 필드 타입·값 변경, 누락·추가, 다른 호출의 context는 거부한다. owner는 화면 모드의 최종 Allow 확정 직전에 새 시스템 관찰값과 최초 context가 같은지도 확인한다.

## 수명 관리

Invoke는 비동기 작업을 시작하고 반환한다. Deactivate는 먼저 요청을 무효화하고 파이프를 닫으며 자식 작업을 종료·회수한다. 작업이 멈춘 뒤 DidDeactivate를 호출한다. Destroy 뒤에는 엔진 참조를 사용하는 콜백이 남지 않아야 한다. 상태 잠금을 잡은 채 엔진 콜백을 호출하지 않는다.

첫 구현은 동시에 한 호출만 처리한다. 중복·동시 호출, 지연 승인, 연결 종료, 시간 초과, 잘못된 실행 파일·정책·파이프 레코드를 거부하는지 검증한다.

같은 플러그인에서 이전 호출의 작업과 콜백이 끝난 뒤 새 메커니즘을 실행할 수 있다. 동일 메커니즘 재호출은 거부한다. 취소와 결과 확정은 같은 잠금으로 중재하고 엔진 콜백은 잠금 밖에서 실행한다. 콜백 중 같은 스레드의 Destroy 재진입은 이후 콜백을 막으며, 다른 스레드의 Destroy는 진행 중인 작업과 콜백 종료를 기다린다. 실제 인증 호스트의 콜백·SIGCHLD·모듈 수명과의 호환성은 설치 후 시험 대상이다.

## 고정 정책과 실행 환경

보조 프로그램은 `Contents/Resources/policy.json` 한 경로만 읽는다. 최상위 필드는 `version=2`, `mode`, `executionUID`, `targetConsoleUID`, `relay`, `requesterKeyFile`, `caCertificateFile`이며 다른 필드는 거부한다. 실제·유효 UID는 정책의 비-root executionUID와 모두 일치해야 한다. isolated 모드의 targetConsoleUID는 null이고 screen 모드는 양의 대상 UID를 지정한다. relay.account는 이 모드·대상으로부터 정해진 정확한 account와 일치해야 한다.

`requesterKeyFile`은 isolated 모드에서 `/Library/Application Support/PLF02WHRemoteApproval/requester.private.json`, screen 모드에서 같은 디렉터리의 `screen-requester.private.json`으로 고정한다. 화면 시험은 새 전용 요청자 키를 사용한다. 내용은 EC/P-256 개인 JWK 자체이며 CLI의 자격 증명 래퍼 객체가 아니다. executionUID 소유와 정확한 0600 권한, 부모 디렉터리의 root 소유·쓰기 제한, ACL, 심볼릭 링크·하드 링크 여부를 검사한다. 파생 공개키가 고정 공개키와 같아야 한다. 런타임에서 UID를 전환하거나 권한을 높이지 않는다.

`caCertificateFile`은 null 또는 번들의 `Contents/Resources/relay-ca.der` 절대 경로다. 사설 CA도 인증서 체인과 호스트명 검증을 통과해야 한다. 파일은 최대 크기보다 한 바이트까지만 읽어, 열린 뒤 파일이 늘어나는 경우도 차단한다.

부모는 빈 환경과 인수 없는 고정 실행 파일을 사용한다. 보조 프로그램의 C 진입점은 Swift·CoreFoundation 초기화 전의 원래 실행 환경을 검사한다. 플러그인에는 실제 서명한 보조 프로그램의 CDHash를 빌드 시 고정하며 hardened runtime과 entitlement 부재도 확인한다.

## 화면 context와 검증 경계

공유 C 구현은 `context/ScreenContext.h`와 `ScreenContext.c`다. `PLFCaptureScreenContext`는 실제·유효 UID 일치, 유효한 호출자 security session, graphic-access 속성, root·remote 세션 제외, SC·CG 콘솔 UID 일치, on-console·login-done을 확인한다. 알려지지 않은 속성 비트는 허용하며 실제 관찰값 8240 자체를 고정 조건으로 쓰지 않는다. `PLFScreenContextValid`와 `PLFScreenContextsEqual`을 경계 검증과 비교에 사용한다. 실패 시 context를 대체하거나 조건을 낮추지 않는다.

화면 모드의 account는 캡처한 consoleUID로 생성한다. helper는 정책 모드·account·대상 UID와 invocation이 일치하는지 확인하고, 자신이 독립적으로 읽은 context도 일치하는지 검사한 뒤에만 키를 읽거나 중계에 접속한다. bound와 result를 내보내기 전에도 확인한다. isolated 모드는 CG context를 요구하지 않는다.

취소·만료·한 번만 소비하는 상태 전이는 기존 owner가 유지한다. 최종 context 검사도 Allow 확정과 같은 중재 경계 안에서 수행하며 엔진 콜백은 잠금 밖에서 호출한다. 공개 관찰 API의 호출과 다른 로그인 세션으로의 전환은 하나의 원자적 작업이 아니다. 전환 후 복귀를 모두 검출하거나 authorization engine의 실제 대상 계정을 독립적으로 증명한다고 주장하지 않는다.

네트워크 서명은 account와 원문 요청 해시를 결합한다. 로컬 context는 owner의 불변 invocation에 결합되지만, 승인자 서명이 macOS 세션 상태를 별도로 증명하는 것은 아니다. 일반적인 다중 사용자·세션 보증과 키체인 해제는 이 한정 시험 밖의 미검증 항목이다.

실기 검증은 먼저 UID 92 helper의 context 일치와 서명된 거부를 확인한 뒤 승인으로 진행한다. 승인 후 같은 임시 규칙 아래 다시 잠갔을 때도 새 요청이 필요해야 한다. 새 승인 없이 열리면 OS 권한 캐시나 기존 메커니즘의 영향과 구분되지 않으므로 성공으로 처리하지 않고 원복한다. 로컬 owner의 재사용 차단 시험만으로 이 OS 동작을 대신하지 않는다.
