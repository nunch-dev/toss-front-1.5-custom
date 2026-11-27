package org.plf02wh.cameraprobe;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureFailure;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.TotalCaptureResult;
import android.hardware.camera2.params.OutputConfiguration;
import android.hardware.camera2.params.SessionConfiguration;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.hardware.display.DisplayManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Size;
import android.view.Gravity;
import android.view.Surface;
import android.view.TextureView;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.Arrays;
import java.util.Collections;
import java.util.Locale;

public final class MainActivity extends Activity {
    private static final int CAMERA_PERMISSION_REQUEST = 1;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private CameraManager cameraManager;
    private DisplayManager displayManager;
    private RadioGroup cameraChoices;
    private Button startButton;
    private Button stopButton;
    private TextView statusView;
    private TextView metadataView;
    private FrameLayout preview;
    private TextView previewPlaceholder;
    private String selectedId;
    private CameraCharacteristics selectedCharacteristics;
    private Size selectedSize;
    private String status = "카메라를 선택한 뒤 시작을 누르세요.";
    private boolean resumed;
    private boolean permissionPending;
    private ProbeRun run;
    private long previewFrames;
    private long completedMetadata;
    private long lastCounterUpdate;

    // All state, Camera2 callbacks, and TextureView callbacks share the main looper.
    // A stopped run remains owned until onClosed, so a new Start cannot race its close.
    private final class ProbeRun {
        final String cameraId;
        final CameraCharacteristics characteristics;
        final Size size;
        final TextureView texture;
        CameraDevice device;
        CameraCaptureSession session;
        Surface surface;
        boolean openRequested;
        boolean stopped;
        boolean repeating;

        ProbeRun(String id, CameraCharacteristics info, Size previewSize) {
            cameraId = id;
            characteristics = info;
            size = previewSize;
            texture = new TextureView(MainActivity.this);
            texture.setOpaque(false);
            texture.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        }
    }

    private final DisplayManager.DisplayListener displayListener =
            new DisplayManager.DisplayListener() {
                @Override
                public void onDisplayAdded(int displayId) {}

                @Override
                public void onDisplayRemoved(int displayId) {}

                @Override
                public void onDisplayChanged(int displayId) {
                    if (getDisplay().getDisplayId() == displayId) {
                        if (isCurrent(run)) {
                            transformPreview(run);
                        }
                        renderMetadata();
                    }
                }
            };

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        cameraManager = getSystemService(CameraManager.class);
        displayManager = getSystemService(DisplayManager.class);
        if (savedInstanceState != null) {
            selectedId = savedInstanceState.getString("cameraId");
        }
        buildUi();
    }

    private void buildUi() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(16), dp(16), dp(16), dp(24));
        scroll.addView(content);

        TextView title = text("카메라 프리뷰 진단", 22);
        title.setAccessibilityHeading(true);
        content.addView(title);
        content.addView(text("프리뷰만 표시합니다. 촬영·저장·전송하지 않습니다.\n"
                + "화면 캡처가 차단됩니다. 영상은 직접 눈으로 확인하세요.", 16));

        cameraChoices = new RadioGroup(this);
        cameraChoices.setId(R.id.camera_choices);
        cameraChoices.setOrientation(RadioGroup.VERTICAL);
        content.addView(cameraChoices, spacedParams());

        LinearLayout actions = new LinearLayout(this);
        startButton = new Button(this);
        startButton.setId(R.id.start);
        startButton.setText("시작");
        startButton.setMinHeight(dp(48));
        startButton.setOnClickListener(view -> startPreview());
        actions.addView(startButton, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        stopButton = new Button(this);
        stopButton.setId(R.id.stop);
        stopButton.setText("정지");
        stopButton.setMinHeight(dp(48));
        stopButton.setOnClickListener(view -> stopRun("정지했습니다. 다시 시작할 수 있습니다."));
        LinearLayout.LayoutParams stopParams = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1);
        stopParams.setMarginStart(dp(8));
        actions.addView(stopButton, stopParams);
        content.addView(actions, spacedParams());

        statusView = text("", 17);
        statusView.setId(R.id.status);
        statusView.setTextIsSelectable(true);
        // The visible text includes both counters for accessibility and UIAutomator.
        // Do not announce each frame through an accessibility live region.
        content.addView(statusView, spacedParams());
        metadataView = text("", 16);
        metadataView.setId(R.id.metadata);
        metadataView.setTextIsSelectable(true);
        content.addView(metadataView, spacedParams());

        preview = new FrameLayout(this);
        preview.setId(R.id.preview);
        preview.setBackgroundColor(Color.BLACK);
        previewPlaceholder = text("프리뷰 없음\n시작을 누르세요.", 17);
        previewPlaceholder.setTextColor(Color.WHITE);
        previewPlaceholder.setGravity(Gravity.CENTER);
        preview.addView(previewPlaceholder, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        LinearLayout.LayoutParams previewParams = spacedParams();
        previewParams.height = Math.max(dp(240),
                getResources().getDisplayMetrics().heightPixels / 2);
        content.addView(preview, previewParams);
        setContentView(scroll);
        renderStatus();
    }

    private TextView text(String value, int sp) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(sp);
        view.setPadding(0, dp(4), 0, dp(4));
        return view;
    }

    private LinearLayout.LayoutParams spacedParams() {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.topMargin = dp(12);
        return params;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    @Override
    protected void onResume() {
        super.onResume();
        resumed = true;
        displayManager.registerDisplayListener(displayListener, mainHandler);
        discoverCameras();
        renderStatus();
    }

    @Override
    protected void onPause() {
        resumed = false;
        displayManager.unregisterDisplayListener(displayListener);
        stopRun("일시 중지했습니다. 돌아온 뒤 시작을 다시 누르세요.");
        super.onPause();
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        outState.putString("cameraId", selectedId);
        super.onSaveInstanceState(outState);
    }

    private void discoverCameras() {
        cameraChoices.removeAllViews();
        try {
            String[] ids = cameraManager.getCameraIdList();
            Arrays.sort(ids);
            if (!Arrays.asList(ids).contains(selectedId)) {
                selectedId = ids.length == 0 ? null : ids[0];
            }
            for (String id : ids) {
                RadioButton button = new RadioButton(this);
                button.setId(View.generateViewId());
                button.setText("카메라 " + id);
                button.setMinHeight(dp(48));
                button.setChecked(id.equals(selectedId));
                cameraChoices.addView(button);
                button.setOnClickListener(view -> {
                    if (!id.equals(selectedId)) {
                        stopRun("카메라 " + id + " 선택됨. 시작을 누르세요.");
                        selectedId = id;
                        previewFrames = 0;
                        completedMetadata = 0;
                        loadSelectedCharacteristics();
                        renderStatus();
                    }
                });
            }
            if (ids.length == 0) {
                status = "감지된 카메라가 없습니다.";
            }
            loadSelectedCharacteristics();
        } catch (CameraAccessException | SecurityException | IllegalArgumentException e) {
            selectedId = null;
            selectedCharacteristics = null;
            selectedSize = null;
            status = "카메라 목록 조회 실패: " + describe(e);
            renderMetadata();
        }
    }

    private void loadSelectedCharacteristics() {
        selectedCharacteristics = null;
        selectedSize = null;
        if (selectedId != null) {
            try {
                selectedCharacteristics = cameraManager.getCameraCharacteristics(selectedId);
            } catch (CameraAccessException | SecurityException | IllegalArgumentException e) {
                status = "카메라 정보 조회 실패: " + describe(e);
            }
        }
        renderMetadata();
    }

    private void startPreview() {
        if (!resumed || run != null || selectedId == null || permissionPending) {
            return;
        }
        if (checkSelfPermission(Manifest.permission.CAMERA)
                != PackageManager.PERMISSION_GRANTED) {
            permissionPending = true;
            status = "프리뷰를 위해 카메라 권한을 허용하세요. 허용 후 시작을 다시 누르세요.";
            renderStatus();
            requestPermissions(new String[] {Manifest.permission.CAMERA},
                    CAMERA_PERMISSION_REQUEST);
            return;
        }
        try {
            CameraCharacteristics info = cameraManager.getCameraCharacteristics(selectedId);
            Integer orientation = info.get(CameraCharacteristics.SENSOR_ORIENTATION);
            if (orientation == null || orientation % 90 != 0) {
                status = "센서 방향 정보가 없거나 올바르지 않아 시작할 수 없습니다.";
                renderStatus();
                return;
            }
            StreamConfigurationMap map = info.get(
                    CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
            Size[] sizes = map == null ? null : map.getOutputSizes(SurfaceTexture.class);
            if (sizes == null || sizes.length == 0) {
                status = "TextureView 프리뷰 출력 크기가 없습니다.";
                renderStatus();
                return;
            }
            Size size = chooseSize(sizes);
            selectedCharacteristics = info;
            selectedSize = size;
            previewFrames = 0;
            completedMetadata = 0;
            lastCounterUpdate = 0;
            ProbeRun candidate = new ProbeRun(selectedId, info, size);
            run = candidate;
            candidate.texture.setSurfaceTextureListener(surfaceListener(candidate));
            preview.addView(candidate.texture, new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
            previewPlaceholder.setVisibility(View.GONE);
            status = "카메라 " + selectedId + " 프리뷰 표면 준비 중…";
            renderMetadata();
            renderStatus();
        } catch (CameraAccessException | SecurityException | IllegalArgumentException e) {
            stopRun("시작 실패: " + describe(e));
        }
    }

    private static Size chooseSize(Size[] sizes) {
        Size smallest = sizes[0];
        Size bounded = null;
        for (Size size : sizes) {
            long area = (long) size.getWidth() * size.getHeight();
            if (area < (long) smallest.getWidth() * smallest.getHeight()) {
                smallest = size;
            }
            if (Math.max(size.getWidth(), size.getHeight()) <= 1280
                    && Math.min(size.getWidth(), size.getHeight()) <= 720
                    && (bounded == null
                    || area > (long) bounded.getWidth() * bounded.getHeight())) {
                bounded = size;
            }
        }
        return bounded != null ? bounded : smallest;
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions,
            int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != CAMERA_PERMISSION_REQUEST) {
            return;
        }
        permissionPending = false;
        if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            status = "카메라 권한을 허용했습니다. 시작을 다시 누르세요.";
        } else {
            status = shouldShowRequestPermissionRationale(Manifest.permission.CAMERA)
                    ? "카메라 권한이 거부되었습니다. 시작을 눌러 다시 요청할 수 있습니다."
                    : "카메라 권한이 거부되었거나 요청이 취소되었습니다. "
                            + "계속 거부되면 시스템 앱 설정에서 카메라 권한을 허용하세요.";
        }
        renderStatus();
    }

    private boolean isCurrent(ProbeRun candidate) {
        return candidate != null && run == candidate && !candidate.stopped && resumed;
    }

    private TextureView.SurfaceTextureListener surfaceListener(ProbeRun candidate) {
        return new TextureView.SurfaceTextureListener() {
            @Override
            public void onSurfaceTextureAvailable(SurfaceTexture texture, int width, int height) {
                if (isCurrent(candidate) && !candidate.openRequested) {
                    openCamera(candidate, texture);
                }
            }

            @Override
            public void onSurfaceTextureSizeChanged(SurfaceTexture texture, int width, int height) {
                if (isCurrent(candidate)) {
                    transformPreview(candidate);
                }
            }

            @Override
            public boolean onSurfaceTextureDestroyed(SurfaceTexture texture) {
                if (isCurrent(candidate)) {
                    stopRun("프리뷰 표면이 사라졌습니다. 시작을 다시 누르세요.");
                }
                return true;
            }

            @Override
            public void onSurfaceTextureUpdated(SurfaceTexture texture) {
                if (isCurrent(candidate) && candidate.repeating) {
                    previewFrames++;
                    renderCountersIfDue();
                }
            }
        };
    }

    private void openCamera(ProbeRun candidate, SurfaceTexture texture) {
        try {
            texture.setDefaultBufferSize(candidate.size.getWidth(), candidate.size.getHeight());
            candidate.surface = new Surface(texture);
            transformPreview(candidate);
            candidate.openRequested = true;
            status = "카메라 " + candidate.cameraId + " 여는 중…";
            renderStatus();
            cameraManager.openCamera(candidate.cameraId, new CameraDevice.StateCallback() {
                @Override
                public void onOpened(CameraDevice device) {
                    candidate.device = device;
                    if (!isCurrent(candidate)) {
                        device.close();
                        return;
                    }
                    configureSession(candidate);
                }

                @Override
                public void onDisconnected(CameraDevice device) {
                    candidate.device = device;
                    if (isCurrent(candidate)) {
                        stopRun("카메라 연결이 끊겼습니다. 자동 재시도하지 않습니다.");
                    } else {
                        device.close();
                    }
                }

                @Override
                public void onError(CameraDevice device, int error) {
                    candidate.device = device;
                    if (isCurrent(candidate)) {
                        stopRun("카메라 오류: " + cameraError(error)
                                + " (" + error + "). 자동 재시도하지 않습니다.");
                    } else {
                        device.close();
                    }
                }

                @Override
                public void onClosed(CameraDevice device) {
                    if (isCurrent(candidate)) {
                        stopRun("카메라가 닫혔습니다. 시작을 다시 누르세요.");
                    }
                    finishClose(candidate);
                }
            }, mainHandler);
        } catch (CameraAccessException | SecurityException | IllegalArgumentException
                | IllegalStateException e) {
            candidate.openRequested = false;
            stopRun("카메라 열기 실패: " + describe(e));
        }
    }

    private void configureSession(ProbeRun candidate) {
        status = "프리뷰 세션 구성 중…";
        renderStatus();
        try {
            candidate.device.createCaptureSession(new SessionConfiguration(
                    SessionConfiguration.SESSION_REGULAR,
                    Collections.singletonList(new OutputConfiguration(candidate.surface)),
                    getMainExecutor(), new CameraCaptureSession.StateCallback() {
                        @Override
                        public void onConfigured(CameraCaptureSession session) {
                            if (!isCurrent(candidate)) {
                                session.close();
                                return;
                            }
                            candidate.session = session;
                            startRepeating(candidate);
                        }

                        @Override
                        public void onConfigureFailed(CameraCaptureSession session) {
                            session.close();
                            if (isCurrent(candidate)) {
                                stopRun("프리뷰 세션 구성 실패. 자동 재시도하지 않습니다.");
                            }
                        }
                    }));
        } catch (CameraAccessException | IllegalArgumentException | IllegalStateException e) {
            stopRun("세션 구성 오류: " + describe(e));
        }
    }

    private void startRepeating(ProbeRun candidate) {
        try {
            CaptureRequest.Builder request = candidate.device.createCaptureRequest(
                    CameraDevice.TEMPLATE_PREVIEW);
            request.addTarget(candidate.surface);
            request.set(CaptureRequest.STATISTICS_FACE_DETECT_MODE,
                    CaptureRequest.STATISTICS_FACE_DETECT_MODE_OFF);
            int[] afModes = candidate.characteristics.get(
                    CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES);
            if (afModes != null) {
                for (int mode : afModes) {
                    if (mode == CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE) {
                        request.set(CaptureRequest.CONTROL_AF_MODE, mode);
                        break;
                    }
                }
            }
            candidate.session.setRepeatingRequest(request.build(),
                    new CameraCaptureSession.CaptureCallback() {
                        @Override
                        public void onCaptureCompleted(CameraCaptureSession session,
                                CaptureRequest request, TotalCaptureResult result) {
                            if (isCurrent(candidate)) {
                                completedMetadata++;
                                renderCountersIfDue();
                            }
                        }

                        @Override
                        public void onCaptureFailed(CameraCaptureSession session,
                                CaptureRequest request, CaptureFailure failure) {
                            if (isCurrent(candidate)) {
                                stopRun("프리뷰 프레임 처리 실패 (이유 " + failure.getReason()
                                        + "). 자동 재시도하지 않습니다.");
                            }
                        }

                        @Override
                        public void onCaptureBufferLost(CameraCaptureSession session,
                                CaptureRequest request, Surface target, long frameNumber) {
                            if (isCurrent(candidate)) {
                                stopRun("프리뷰 버퍼 손실. 자동 재시도하지 않습니다.");
                            }
                        }
                    }, mainHandler);
            candidate.repeating = true;
            status = "프리뷰 요청 중. 영상과 프레임 증가를 확인하세요.";
            renderStatus();
        } catch (CameraAccessException | IllegalArgumentException | IllegalStateException e) {
            stopRun("프리뷰 요청 실패: " + describe(e));
        }
    }

    private void stopRun(String reason) {
        status = reason;
        ProbeRun candidate = run;
        if (candidate != null && !candidate.stopped) {
            candidate.stopped = true;
            candidate.texture.setVisibility(View.INVISIBLE);
            previewPlaceholder.setText("프리뷰 없음\n시작을 누르세요.");
            previewPlaceholder.setVisibility(View.VISIBLE);
            if (candidate.session != null) {
                candidate.session.close();
            }
            if (candidate.device != null) {
                candidate.device.close();
            }
            if (!candidate.openRequested) {
                finishClose(candidate);
            }
        }
        renderStatus();
    }

    private void finishClose(ProbeRun candidate) {
        if (candidate.surface != null) {
            candidate.surface.release();
            candidate.surface = null;
        }
        preview.removeView(candidate.texture);
        if (run == candidate) {
            run = null;
        }
        renderStatus();
    }

    private void transformPreview(ProbeRun candidate) {
        int width = candidate.texture.getWidth();
        int height = candidate.texture.getHeight();
        if (width == 0 || height == 0) {
            return;
        }
        int sensor = candidate.characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
        int rotation = displayDegrees();
        // TextureView already applies the camera's sensor transform. Restore that
        // oriented buffer's aspect ratio, then compensate display rotation and fit
        // the whole image inside black letterboxing; never stretch or crop it.
        boolean sensorSwapped = sensor % 180 != 0;
        float naturalWidth = sensorSwapped ? candidate.size.getHeight() : candidate.size.getWidth();
        float naturalHeight = sensorSwapped ? candidate.size.getWidth() : candidate.size.getHeight();
        boolean displaySwapped = rotation % 180 != 0;
        float rotatedWidth = displaySwapped ? naturalHeight : naturalWidth;
        float rotatedHeight = displaySwapped ? naturalWidth : naturalHeight;
        float fit = Math.min(width / rotatedWidth, height / rotatedHeight);
        float cx = width / 2f;
        float cy = height / 2f;
        Matrix transform = new Matrix();
        transform.setScale(naturalWidth / width, naturalHeight / height, cx, cy);
        transform.postRotate(-rotation, cx, cy);
        transform.postScale(fit, fit, cx, cy);
        candidate.texture.setTransform(transform);
        renderMetadata();
    }

    private int displayDegrees() {
        return getDisplay().getRotation() * 90;
    }

    private void renderMetadata() {
        Integer orientation = selectedCharacteristics == null ? null
                : selectedCharacteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
        metadataView.setText("선택 카메라 ID: " + (selectedId == null ? "없음" : selectedId)
                + "\n프리뷰 버퍼 크기: " + (selectedSize == null ? "시작 전" : selectedSize.toString())
                + "\n센서 방향: " + (orientation == null ? "알 수 없음" : orientation + "°")
                + "\n현재 디스플레이 회전: " + displayDegrees() + "°");
    }

    private void renderCountersIfDue() {
        long now = SystemClock.uptimeMillis();
        if (lastCounterUpdate == 0 || now - lastCounterUpdate >= 500) {
            lastCounterUpdate = now;
            renderStatus();
        }
    }

    private void renderStatus() {
        statusView.setText(String.format(Locale.KOREAN,
                "%s%s\n프리뷰 업데이트: %d 프레임\n완료 메타데이터: %d 프레임",
                status, run != null && run.stopped ? "\n카메라 자원 해제 중…" : "",
                previewFrames, completedMetadata));
        startButton.setEnabled(resumed && selectedId != null && run == null && !permissionPending);
        stopButton.setEnabled(run != null && !run.stopped);
    }

    private static String describe(Exception exception) {
        if (exception instanceof CameraAccessException) {
            return "CameraAccessException (이유 "
                    + ((CameraAccessException) exception).getReason() + ")";
        }
        return exception.getClass().getSimpleName() + ": " + exception.getMessage();
    }

    private static String cameraError(int error) {
        switch (error) {
            case CameraDevice.StateCallback.ERROR_CAMERA_IN_USE:
                return "다른 앱에서 사용 중";
            case CameraDevice.StateCallback.ERROR_MAX_CAMERAS_IN_USE:
                return "동시 사용 가능한 카메라 수 초과";
            case CameraDevice.StateCallback.ERROR_CAMERA_DISABLED:
                return "시스템 정책으로 사용 중지";
            case CameraDevice.StateCallback.ERROR_CAMERA_DEVICE:
                return "카메라 장치 오류";
            case CameraDevice.StateCallback.ERROR_CAMERA_SERVICE:
                return "카메라 서비스 오류";
            default:
                return "알 수 없는 오류";
        }
    }
}
