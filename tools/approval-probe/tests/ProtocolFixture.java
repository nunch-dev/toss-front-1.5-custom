package org.plf02wh.approvalprobe;

import com.nimbusds.jose.*;
import com.nimbusds.jose.crypto.*;
import com.nimbusds.jose.jwk.*;
import com.nimbusds.jose.jwk.gen.ECKeyGenerator;
import com.nimbusds.jose.util.Base64URL;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

final class ProtocolFixture {
    static final long NOW = 1700000000L;
    static final String NONCE = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    static final String REQUEST_ID = "12345678-1234-4234-8234-123456789abc";
    final ECKey requester = new ECKeyGenerator(Curve.P_256).generate();
    final ECKey approver = new ECKeyGenerator(Curve.P_256).generate();
    final ApprovalProtocol protocol = protocol();
    int checks;
    int rejections;

    ProtocolFixture() throws Exception {}

    ApprovalProtocol protocol() throws Exception {
        return new ApprovalProtocol("relay", "android", "mac", "local.user",
                requester.toPublicJWK(), approver.toECPrivateKey());
    }

    Map<String, Object> request() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("version", 1);
        m.put("kind", "request");
        m.put("issuer", "mac");
        m.put("audience", "android");
        m.put("issuedAt", NOW);
        m.put("expiresAt", NOW + 45);
        m.put("requestId", REQUEST_ID);
        m.put("nonce", NONCE);
        m.put("account", "local.user");
        m.put("action", "screen-unlock");
        return m;
    }

    String token(Map<String, Object> m) throws Exception {
        return raw(new Payload(m).toBytes(), header(), requester);
    }

    JWSHeader header() {
        return new JWSHeader.Builder(JWSAlgorithm.ES256)
                .type(new JOSEObjectType("remote-unlock+jws")).keyID("mac").build();
    }

    String raw(byte[] payload, JWSHeader header, ECKey key) throws Exception {
        JWSObject object = new JWSObject(header, new Payload(payload));
        object.sign(new ECDSASigner(key));
        return object.serialize();
    }

    String raw(String payload) throws Exception {
        return raw(payload.getBytes(StandardCharsets.UTF_8), header(), requester);
    }

    // JWS signing of deliberately malformed header bytes still uses Nimbus/JCA.
    String rawHeader(String header) throws Exception {
        String h = Base64URL.encode(header).toString();
        String p = Base64URL.encode(new Payload(request()).toBytes()).toString();
        byte[] input = (h + "." + p).getBytes(StandardCharsets.US_ASCII);
        return h + "." + p + "." + new ECDSASigner(requester).sign(header(), input);
    }

    Map<String, Object> signed(String token) throws Exception {
        JWSObject jws = JWSObject.parse(token);
        check(jws.verify(new ECDSAVerifier(approver.toPublicJWK())), "approver signature");
        Map<String, Object> h = jws.getHeader().toJSONObject();
        check(h.size() == 3 && "ES256".equals(h.get("alg"))
                && "remote-unlock+jws".equals(h.get("typ"))
                && "android".equals(h.get("kid")), "outgoing exact header");
        return jws.getPayload().toJSONObject();
    }

    void check(boolean condition, String label) {
        if (!condition) throw new AssertionError(label);
        checks++;
    }

    void reject(String label, String code, Attempt action) throws Exception {
        try {
            action.run();
        } catch (ApprovalProtocol.ProtocolException e) {
            check(code.equals(e.code), label + ": expected " + code + ", got " + e.code);
            rejections++;
            return;
        }
        throw new AssertionError(label + ": unexpectedly accepted");
    }

    interface Attempt { void run() throws Exception; }
}
