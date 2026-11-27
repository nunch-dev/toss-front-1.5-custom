package org.plf02wh.approvalprobe;

import java.nio.ByteBuffer;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import org.java_websocket.client.WebSocketClient;
import org.java_websocket.drafts.Draft_6455;
import org.java_websocket.handshake.ServerHandshake;
import org.json.JSONObject;

final class ApprovalConnection extends WebSocketClient {
    interface Listener {
        void changed(String status, ApprovalProtocol.PendingRequest request, boolean connected);
    }
    private enum Phase { CONNECTING, AUTHENTICATING, READY, PENDING, DELIVERING, CLOSED }
    private final ProbeConfig config;
    private final ApprovalProtocol protocol;
    private final Listener listener;
    private final ScheduledExecutorService clock = Executors.newSingleThreadScheduledExecutor();
    private final Map<String, Long> seen = new HashMap<>();
    private Phase phase = Phase.CONNECTING;
    private ApprovalProtocol.PendingRequest pending;
    private String sentId;
    private boolean sentApproval;
    private ScheduledFuture<?> deadline;

    ApprovalConnection(ProbeConfig config, ApprovalProtocol protocol, Listener listener) {
        super(config.relayURL, new Draft_6455(Collections.emptyList(), 17000),
                Collections.emptyMap(), 10000);
        this.config = config;
        this.protocol = protocol;
        this.listener = listener;
        setConnectionLostTimeout(30);
        arm(10000, "연결 시간이 초과됐습니다. 다시 연결해 주세요.");
    }

    @Override public synchronized void onOpen(ServerHandshake handshake) {
        if (phase == Phase.CLOSED) { close(); return; }
        listener.changed("서버 연결됨 · 장치 인증 중", null, true);
    }

    @Override public synchronized void onMessage(String text) {
        if (phase == Phase.CLOSED) return;
        try {
            if (text.length() > 17000) throw new IllegalArgumentException("size");
            JSONObject message = new JSONObject(text);
            String kind = string(message, "kind");
            switch (kind) {
                case "challenge":
                    if (phase != Phase.CONNECTING || message.length() != 4 ||
                            !config.relayId.equals(string(message, "relayId")))
                        throw new IllegalArgumentException("challenge");
                    Object expiry = message.get("expiresAt");
                    if (!(expiry instanceof Long) && !(expiry instanceof Integer))
                        throw new IllegalArgumentException("time");
                    phase = Phase.AUTHENTICATING;
                    sendToken(protocol.authenticate(string(message, "nonce"),
                            ((Number) expiry).longValue(), now()));
                    break;
                case "authenticated":
                    if (phase != Phase.AUTHENTICATING || message.length() != 2 ||
                            !config.approverId.equals(string(message, "actor")))
                        throw new IllegalArgumentException("authenticated");
                    disarm();
                    phase = Phase.READY;
                    listener.changed("연결됨 · Mac의 요청을 기다립니다", null, true);
                    break;
                case "signed":
                    if (phase != Phase.READY || message.length() != 2)
                        throw new IllegalArgumentException("pending");
                    ApprovalProtocol.PendingRequest request = protocol.receive(
                            string(message, "token"), now());
                    seen.entrySet().removeIf(entry -> entry.getValue() <= now());
                    if (seen.size() >= 4096 || seen.containsKey(request.requestId))
                        throw new IllegalArgumentException("replay");
                    seen.put(request.requestId, request.expiresAt);
                    pending = request;
                    phase = Phase.PENDING;
                    arm(Math.max(1, request.expiresAt * 1000 - System.currentTimeMillis()),
                            "요청이 만료됐습니다. 새로 연결해 주세요.");
                    listener.changed("대상과 계정을 확인한 뒤 선택해 주세요", request, true);
                    break;
                case "delivered":
                    if (phase != Phase.DELIVERING || message.length() != 2 ||
                            !sentId.equals(string(message, "requestId")))
                        throw new IllegalArgumentException("delivered");
                    disarm();
                    phase = Phase.READY;
                    listener.changed(sentApproval ? "승인 전달 완료 · Mac 검증 결과를 확인하세요"
                            : "거부 전달 완료 · 다음 요청 대기 중", null, true);
                    break;
                case "error":
                    if (message.length() != 2) throw new IllegalArgumentException("error");
                    String code = string(message, "code");
                    if (!code.matches("invalid_message|not_allowed|peer_offline|busy|" +
                            "no_pending_request|expired|cancelled|duplicate_request"))
                        throw new IllegalArgumentException("code");
                    fail("서버가 요청을 거부했습니다: " + code);
                    break;
                default:
                    throw new IllegalArgumentException("kind");
            }
        } catch (Exception error) {
            fail("메시지 검증 실패: " + error.getClass().getSimpleName());
        }
    }

    synchronized void decide(boolean approve) {
        if (phase != Phase.PENDING || pending == null) return;
        ApprovalProtocol.PendingRequest request = pending;
        pending = null;
        phase = Phase.DELIVERING;
        sentId = request.requestId;
        sentApproval = approve;
        listener.changed("서명한 응답을 전송하는 중", null, true);
        try {
            sendToken(protocol.decision(request, approve, now()));
        } catch (Exception error) {
            fail("응답을 보낼 수 없습니다: " + error.getClass().getSimpleName());
        }
    }

    synchronized void cancel() { fail("연결이 종료됐습니다. 다시 연결해 주세요."); }

    private void sendToken(String token) throws Exception {
        send(new JSONObject().put("kind", "signed").put("token", token).toString());
    }

    private void arm(long millis, String reason) {
        disarm();
        deadline = clock.schedule(() -> {
            synchronized (ApprovalConnection.this) { fail(reason); }
        }, millis, TimeUnit.MILLISECONDS);
    }

    private void disarm() {
        if (deadline != null) { deadline.cancel(false); deadline = null; }
    }

    private void fail(String reason) {
        if (phase == Phase.CLOSED) return;
        phase = Phase.CLOSED;
        pending = null;
        disarm();
        clock.shutdownNow();
        close();
        listener.changed(reason, null, false);
    }

    @Override public synchronized void onClose(int code, String reason, boolean remote) {
        fail("연결 종료 · 대기 요청은 취소됐습니다");
    }

    @Override public synchronized void onError(Exception error) {
        fail("연결 실패: " + error.getClass().getSimpleName());
    }

    @Override public synchronized void onMessage(ByteBuffer bytes) {
        fail("허용하지 않는 바이너리 메시지");
    }

    private static long now() { return System.currentTimeMillis() / 1000; }

    private static String string(JSONObject object, String key) throws Exception {
        Object value = object.get(key);
        if (!(value instanceof String)) throw new IllegalArgumentException("type");
        return (String) value;
    }
}
