# 카메라 미리보기와 권한 검증

## 범위

2026-11-20 사용자가 카메라 0·1의 미리보기 시험 앱 구현을 요청했다. 실제 영상 수신과 방향을 확인하는 단계이며 얼굴 등록·인식·PC 잠금 해제는 포함하지 않는다.

앱 소스는 `tools/camera-probe/`, 패키지는 `org.plf02wh.cameraprobe`다. CAMERA만 요청하고 영상 저장·외부 전송·프레임 추출을 하지 않는다. `FLAG_SECURE`로 화면 캡처도 차단한다. 실물 영상과 색상·회전은 사용자가 기기 화면에서 확인한다. 자동 검증은 UI에 표시되는 프리뷰 업데이트 수와 완료 메타데이터 수를 사용한다.

## 확인한 기기 정보

일반 ADB에서 조회한 `dumpsys media.camera`는 카메라 0·1을 각각 FRONT, 센서 배열 2592×1944, BGGR, 센서 방향 270도로 보고한다. AE 프레임 범위는 15–30 및 30–30이며 실제 영상의 측정 FPS를 뜻하지 않는다. 지원 capability는 BACKWARD_COMPATIBLE이고 HAL 얼굴 검출 모드는 OFF다. 이 정보만으로 실제 IR 모듈 부재를 확정하지 않는다.

`/sys/class/video4linux/v4l-subdev0/name`부터 `v4l-subdev5/name`까지는 일반 ADB에서 Permission denied였다. `/vendor/etc/camera/camera3_profiles.xml`에는 여러 센서 프로파일이 포함돼 있어 파일의 후보 이름만으로 실제 장착 센서를 확정할 수 없다.

## 앱 동작

- 카메라를 선택하고 시작을 누르면 CAMERA 런타임 권한을 요청한다. 허용 후 시작을 다시 누른다.
- 프리뷰는 최대 1280×720 범위의 지원 크기를 우선 선택한다. 화면에는 버퍼 크기·센서 방향·디스플레이 회전과 프레임 카운터를 표시한다.
- 정지·카메라 변경·앱 일시 중지 시 카메라를 해제한다. 다시 시작하려면 시작 버튼을 눌러야 한다.
- 영상은 비율을 유지해 표시하고 HAL 오류를 화면에 노출한다. 실패를 숨기는 자동 재시도는 없다.

## 빌드와 실기 상태

`bash tools/camera-probe/build-local.sh`는 설치된 Android SDK 34와 JDK 17로 APK를 빌드한다. `ANDROID_HOME`과 `JAVA_HOME`으로 경로를 지정할 수 있다. 개발용 서명과 APK는 `private/camera-probe-20261120/`에 생성한다. 플랫폼 서명이나 system UID를 사용하지 않는다.

로컬 빌드는 종료 0으로 완료했고 APK의 v3 서명·DEX 포함·CAMERA 단독 선언을 확인했다. APK SHA-256은 `55300b0ff13dd64160fce47ef22ab881639f297ed64d3808fd69b711210c3f57`다. 첫 컴파일은 Android 스텁의 LambdaMetafactory 때문에 실패했다. JDK의 Java 8 표준 API와 Android 클래스 경로를 함께 쓰도록 빌드 명령을 수정해 해결했다.

일반 앱으로 설치하고 시스템 대화상자에서 CAMERA를 “앱 사용 중에만 허용”으로 부여했다. 권한 허용만으로 카메라를 자동으로 열지 않으며 시작 버튼을 다시 눌러야 함을 확인했다.

| 검증 항목 | 결과 |
|---|---|
| 카메라 0 | 1280×720, TextureView 업데이트 409회·완료 메타데이터 409회 |
| 카메라 1 | 1280×720, TextureView 업데이트 247회·완료 메타데이터 247회 |
| 카메라 선택 변경 | 카메라 1 선택 시 카운터 초기화·수동 시작 대기 |
| 정지 버튼 | 카메라 0 닫힘, 다시 시작 가능 |
| 홈 이동 | 카메라 1 닫힘, 서비스의 활성 클라이언트 목록 비어 있음 |
| 앱 복귀 | 카메라를 자동 재개하지 않고 수동 시작 대기 |
| 실제 색상·방향·움직임 | 사용자가 두 카메라 모두 컬러이며 현재 기기 방향에서 정상이라고 확인 |

서비스에서도 카메라 0의 Frames produced 274, 카메라 1의 123을 각각 동작 중 확인했다. 위 UI 카운터는 그 뒤 정지 시점의 값이다. Camera error traces는 0이었다. 프레임 수신은 확인했지만 검은 영상이나 회전 문제까지 배제하는 근거로 삼지 않는다.

사용자는 “영상 색상: 둘 다 컬러”, “영상 동작: 둘 다 정상”이라고 확인했다. 현재 두 경로가 컬러 영상을 제공함을 확인했으며 별도 IR·깊이 하드웨어의 물리적 부재까지 검증한 것은 아니다.

확인 후 시험 앱을 force-stop으로 종료했다. 재사용할 수 있도록 설치본은 유지했다. 임시 UI 덤프는 제거했다. 카메라 이미지나 화면 캡처는 보관하지 않았다. ROM과 SELinux 정책·화면 유지 설정은 변경하지 않았다.

## ROM 권한 부여와 sysfs 접근의 차이

ROM에 포함된 특정 앱에는 기본 런타임 권한 부여 정책을 구성할 수 있다. system 앱으로 설치하는 것만으로 모든 권한이 자동으로 생기지는 않는다.

CAMERA는 앱이 카메라 서비스를 사용하는 권한이다. 앞선 거부는 shell 도메인의 sysfs 파일 읽기였으며 앱 권한과 별개로 파일 접근 권한과 SELinux 정책의 영향을 받는다. 해당 오류만으로 DAC와 SELinux 중 어느 것이 거부했는지는 확정하지 않았다. CAMERA 자동 부여는 이 파일 접근 거부를 해소하지 않는다.

이번 시험에서는 ROM·SELinux·sysfs 권한을 변경하지 않는다. 미리보기 성공 여부를 먼저 확인하고, 이후 기본 앱 통합이 필요하면 해당 앱에 필요한 CAMERA 권한 부여 범위를 별도로 정한다.

공식 근거:
- AOSP `DefaultPermissionGrantPolicy`: https://android.googlesource.com/platform/frameworks/base/+/master/services/core/java/com/android/server/pm/permission/DefaultPermissionGrantPolicy.java
- Android SELinux와 DAC: https://source.android.com/docs/security/features/selinux
