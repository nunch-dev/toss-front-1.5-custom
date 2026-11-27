package org.plf02wh.approvalprobe;

import com.nimbusds.jose.util.Base64URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Map;

public final class ApprovalProtocolTest {
    public static void main(String[] args) throws Exception {
        ProtocolFixture f = new ProtocolFixture();
        for (boolean approve : new boolean[] { true, false }) {
            String token = f.raw(" \n" + new com.nimbusds.jose.Payload(f.request()).toString() + "\n");
            ApprovalProtocol.PendingRequest pending = f.protocol.receive(token, ProtocolFixture.NOW);
            f.check(pending.requestId.equals(ProtocolFixture.REQUEST_ID)
                    && pending.issuer.equals("mac") && pending.account.equals("local.user")
                    && pending.expiresAt == ProtocolFixture.NOW + 45, "verified display fields");
            Map<String, Object> result = f.signed(f.protocol.decision(pending, approve,
                    ProtocolFixture.NOW + 1));
            String hash = Base64URL.encode(MessageDigest.getInstance("SHA-256")
                    .digest(token.getBytes(StandardCharsets.UTF_8))).toString();
            f.check(hash.equals(result.get("requestHash")) && hash.equals(pending.requestHash),
                    "hash of exact received compact bytes");
            f.check(result.size() == 10 && "manual".equals(result.get("method"))
                    && (approve ? "approve" : "deny").equals(result.get("decision"))
                    && ProtocolFixture.REQUEST_ID.equals(result.get("requestId"))
                    && "android".equals(result.get("issuer")) && "mac".equals(result.get("audience"))
                    && "decision".equals(result.get("kind"))
                    && ((Number) result.get("version")).longValue() == 1
                    && ((Number) result.get("issuedAt")).longValue() == ProtocolFixture.NOW + 1
                    && ((Number) result.get("expiresAt")).longValue() == pending.expiresAt,
                    "manual decision contract and request expiry cap");
            f.reject("decision at expiry", "expired",
                    () -> f.protocol.decision(pending, approve, pending.expiresAt));
            f.reject("foreign pending owner", "request_mismatch",
                    () -> f.protocol().decision(pending, approve, ProtocolFixture.NOW));
            // Repetition is deliberately allowed here; the app owns terminal state.
            f.signed(f.protocol.decision(pending, approve, ProtocolFixture.NOW + 2));
        }
        for (long lifetime : new long[] { 1, 7, 10, 100 }) {
            Map<String, Object> auth = f.signed(f.protocol.authenticate(ProtocolFixture.NONCE,
                    ProtocolFixture.NOW + lifetime, ProtocolFixture.NOW));
            f.check(auth.size() == 7 && "authenticate".equals(auth.get("kind"))
                    && "relay".equals(auth.get("audience")) && "android".equals(auth.get("issuer"))
                    && ProtocolFixture.NONCE.equals(auth.get("nonce"))
                    && ((Number) auth.get("version")).longValue() == 1
                    && ((Number) auth.get("issuedAt")).longValue() == ProtocolFixture.NOW
                    && ((Number) auth.get("expiresAt")).longValue()
                    == ProtocolFixture.NOW + Math.min(10, lifetime), "challenge expiry bound");
        }
        f.reject("expired challenge", "expired", () -> f.protocol.authenticate(
                ProtocolFixture.NONCE, ProtocolFixture.NOW, ProtocolFixture.NOW));
        f.reject("invalid nonce", "invalid_message",
                () -> f.protocol.authenticate("bad", ProtocolFixture.NOW + 10, ProtocolFixture.NOW));
        f.reject("negative clock", "invalid_message",
                () -> f.protocol.authenticate(ProtocolFixture.NONCE, 10, -1));
        f.reject("unsafe clock", "invalid_message",
                () -> f.protocol.authenticate(ProtocolFixture.NONCE, Long.MAX_VALUE, Long.MAX_VALUE));
        for (String uuid : new String[] { "00000000-0000-0000-0000-000000000000",
                "ffffffff-ffff-ffff-ffff-ffffffffffff", "12345678-1234-1234-8234-123456789ABC",
                "12345678-1234-8234-b234-123456789abc" }) {
            Map<String, Object> m = f.request();
            m.put("requestId", uuid);
            f.check(uuid.equals(f.protocol.receive(f.token(m), ProtocolFixture.NOW).requestId),
                    "TS UUID acceptance " + uuid);
        }
        // JSON numbers 1.0 and exponents have integer JS values and must interoperate.
        String numeric = new com.nimbusds.jose.Payload(f.request()).toString()
                .replace("\"version\":1", "\"version\":1.0")
                .replace(Long.toString(ProtocolFixture.NOW), "1.7e9");
        f.check(f.protocol.receive(f.raw(numeric), ProtocolFixture.NOW) != null,
                "integer-valued JSON numbers");
        Map<String, Object> boundary = f.request();
        boundary.put("issuedAt", ProtocolFixture.NOW + 5);
        boundary.put("expiresAt", ProtocolFixture.NOW + 65);
        f.protocol.receive(f.token(boundary), ProtocolFixture.NOW);
        f.check(true, "five second future and sixty second TTL accepted");
        InvalidProtocolTest.run(f);
        System.out.println("PASS ApprovalProtocol: " + f.checks
                + " assertions; " + f.rejections + " rejection cases; fresh ephemeral P-256 keys");
    }
}
