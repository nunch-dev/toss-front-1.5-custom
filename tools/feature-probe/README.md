# PLF02WH 진단 APK

ROM에 포함하지 않는 수동 진단 도구다. `installable:false`, 일반 앱 UID이며
권한은 `INTERNET`, `READ_CONTACTS` 두 개만 선언한다. 백업은 비활성화한다.
연락처 요청과 실제 조회는 별도 버튼이다. 조회는 `_ID`만 투영하고
`getCount()`만 호출한다. 행 이동, 이름·값 읽기, 연락처 쓰기를 하지 않는다.

패키지: `org.plf02wh.featureprobe`
액티비티: `org.plf02wh.featureprobe.MainActivity`

## 수동 확인

1. 실제 한국어 IME로 여러 줄을 입력한다. 표시되는 원문, UTF-16 길이,
   선택 범위, 실제 composing span을 확인한다. 입력을 합성하지 않는다.
2. SAF 생성 버튼에서 제안된 고유 파일명을 유지한다. 선택된 새 문서에만
   UTF-8 `PLF02WH_FEATURE_PROBE_V1\n` 마커를 기록한다. 생성된 URI는
   이름 검증이나 쓰기가 실패해도 정리 목록에 남는다.
3. SAF 열기 버튼에서 `plf02wh-test-` 접두어의 테스트 문서만 선택한다.
   접두어가 다르면 내용을 열지 않는다. 일치하면 스트리밍 SHA256과
   전체 바이트 수, 마커 일치 여부를 표시한다. URI 권한을 영구 보관하지 않는다.
4. 부모 작업에서 준비한 reverse/fixture를 사용해 다운로드를 등록한다.
   기본 URL은 `http://127.0.0.1:8765/plf02wh-download.txt`이다.
   별도 조회 버튼이 실제 DownloadManager 상태·reason·성공 파일 해시를 표시한다.
   등록만으로 성공으로 간주하지 않는다. HTTP는 127.0.0.1만 허용하며,
   HTTPS URL도 편집해서 사용할 수 있다. URL 내 인증 정보는 거부한다.
   앱 프로세스를 종료한 뒤 다시 실행해서 같은 ID의 조회 결과도 확인한다.
   저장된 ID 목록 끝에 줄바꿈·들여쓰기 공백이 있어도 숫자 ID만 읽어야 한다.
5. 연락처 조회를 권한 거부 상태와 사용자가 허용한 상태에서 각각 실행한다.
   권한 상태와 실제 API 성공·SecurityException·그 밖의 예외를 구분한다.

## 소유 파일 정리

생성 문서는 `plf02wh-test-<UUID>.txt`,
다운로드는 공용 Downloads의 `plf02wh-test-download-<UUID>.txt`다.
앱 하단의 영구 목록은 생성 문서 URI/파일명, 다운로드 ID/파일명을 보여준다.
다운로드 조회 결과에는 실제 local URI도 포함한다.
목록을 확보한 뒤 정확히 해당 파일과 DownloadManager ID만 부모 작업에서 제거한다.
SAF에서 제안된 이름을 변경하면 내용은 쓰지 않지만 빈 문서가 남을 수 있으므로
이 경우에도 표시된 URI로 정리한다. 앱 삭제만으로 공용 파일이 지워진다고 가정하지 않는다.
연락처, 문서 자동 삭제, 백업, 운영 앱 기능은 구현하지 않는다.

## 빌드

원격 소스 위치는 `device/phh/treble/plf02wh_feature_probe`다.
Soong 명시 출력 타깃:

```text
out/soong/.intermediates/device/phh/treble/plf02wh_feature_probe/Plf02whFeatureProbe/android_common/Plf02whFeatureProbe.apk
```

이 트리의 Soong은 `installable:false`이면 기본적으로 dex 생성을 생략한다.
따라서 `compile_dex:true`를 함께 지정해 ROM 설치 제외를 유지하면서
실행에 필요한 `classes.dex`를 APK에 포함한다.

기존 빌드의 기본 개발용 인증서로 서명한다. 플랫폼 인증서나 shared UID를
요청하지 않는다. 소스·manifest 정적 검토와 APK 빌드는 실제 기기에서의
IME·SAF·다운로드·권한·화면 검증을 대체하지 않는다.
