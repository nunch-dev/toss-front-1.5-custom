package org.plf02wh.approvalprobe;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

public final class MainActivity extends Activity {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView status, details, remaining;
    private Button connect, approve, deny;
    private ProbeConfig config;
    private DeviceIdentity identity;
    private ApprovalConnection connection;
    private ApprovalProtocol.PendingRequest shown;
    private long generation;
    private final Runnable countdown = new Runnable() {
        @Override public void run() {
            if (shown == null) return;
            long seconds = Math.max(0, shown.expiresAt - System.currentTimeMillis() / 1000);
            remaining.setText("남은 시간 " + seconds + "초");
            approve.setEnabled(seconds > 0);
            deny.setEnabled(seconds > 0);
            if (seconds > 0) handler.postDelayed(this, 250);
        }
    };

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        ScrollView scroll = new ScrollView(this);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(24), dp(28), dp(24), dp(24));
        scroll.addView(content);
        setContentView(scroll);
        text(content, "수동 승인 시험", 28);
        text(content, "Mac Studio와 승인 메시지만 교환합니다.", 16);
        status = text(content, "시험 설정을 확인하는 중", 20);
        status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        details = text(content, "", 18);
        remaining = text(content, "", 18);
        connect = button(content, "서버 연결");
        approve = button(content, "승인");
        deny = button(content, "거부");
        approve.setEnabled(false);
        deny.setEnabled(false);
        int[][] states = {new int[] {-android.R.attr.state_enabled}, new int[] {}};
        approve.setBackgroundTintList(new android.content.res.ColorStateList(states,
                new int[] {Color.rgb(238, 238, 238), Color.rgb(24, 70, 166)}));
        approve.setTextColor(new android.content.res.ColorStateList(states,
                new int[] {Color.rgb(120, 120, 120), Color.WHITE}));
        text(content, "화면 잠금 해제와 얼굴 인식은 이번 시험에 포함되지 않습니다.", 14);
        connect.setOnClickListener(view -> {
            if (connection == null) start(); else stop();
        });
        approve.setOnClickListener(view -> { if (connection != null) connection.decide(true); });
        deny.setOnClickListener(view -> { if (connection != null) connection.decide(false); });
        try {
            config = new ProbeConfig(this);
            identity = new DeviceIdentity(this);
            details.setText("서버: " + config.relayURL.getHost() + "\n장치: " + config.approverId);
            status.setText("준비됨 · 서버 연결을 눌러 주세요");
            Log.i("ApprovalProbe", "IDENTITY_READY");
        } catch (Exception error) {
            status.setText("초기화 실패: " + error.getClass().getSimpleName());
            connect.setEnabled(false);
            Log.e("ApprovalProbe", "INITIALIZATION_FAILED " + error.getClass().getSimpleName());
        }
    }

    private void start() {
        long current = ++generation;
        try {
            ApprovalProtocol protocol = new ApprovalProtocol(config.relayId, config.approverId,
                    config.requesterId, config.account, config.requesterKey, identity.signingKey);
            connection = new ApprovalConnection(config, protocol, (message, request, active) ->
                    runOnUiThread(() -> {
                        if (generation != current) return;
                        shown = request;
                        handler.removeCallbacks(countdown);
                        status.setText(message);
                        approve.setEnabled(request != null);
                        deny.setEnabled(request != null);
                        remaining.setText("");
                        if (request != null) {
                            details.setText("요청: " + request.issuer + "\n계정: " + request.account +
                                    "\n요청 ID: " + request.requestId);
                            countdown.run();
                        }
                        connect.setText(active ? "연결 종료" : "서버 연결");
                        if (!active) {
                            connection = null;
                            getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                        }
                        Log.i("ApprovalProbe", message + (request == null ? "" :
                                " requestId=" + request.requestId));
                    }));
            status.setText("서버에 연결하는 중");
            connect.setText("연결 종료");
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            connection.connect();
        } catch (Exception error) {
            stop();
            status.setText("연결 준비 실패: " + error.getClass().getSimpleName());
        }
    }

    private void stop() {
        generation++;
        if (connection != null) { connection.cancel(); connection = null; }
        shown = null;
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        handler.removeCallbacks(countdown);
        approve.setEnabled(false);
        deny.setEnabled(false);
        remaining.setText("");
        status.setText("연결 종료 · 대기 요청은 취소됐습니다");
        connect.setText("서버 연결");
    }

    @Override protected void onStop() {
        stop();
        super.onStop();
    }

    private TextView text(LinearLayout parent, String value, int size) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(Color.rgb(30, 33, 38));
        view.setPadding(0, 0, 0, dp(18));
        parent.addView(view, new LinearLayout.LayoutParams(-1, -2));
        return view;
    }

    private Button button(LinearLayout parent, String label) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextSize(18);
        button.setAllCaps(false);
        button.setFilterTouchesWhenObscured(true);
        LinearLayout.LayoutParams layout = new LinearLayout.LayoutParams(-1, dp(56));
        layout.bottomMargin = dp(12);
        parent.addView(button, layout);
        return button;
    }

    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
}
