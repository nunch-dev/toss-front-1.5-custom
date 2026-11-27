package org.plf02wh.approvalprobe;

import com.nimbusds.jose.*;
import com.nimbusds.jose.jwk.*;
import com.nimbusds.jose.jwk.gen.ECKeyGenerator;
import com.nimbusds.jose.util.Base64URL;
import java.util.Map;

final class InvalidProtocolTest {
    static void run(ProtocolFixture f) throws Exception {
        Object[][] invalid = {
            {"version", 2, "invalid_message"}, {"version", "1", "invalid_message"},
            {"kind", "decision", "invalid_message"}, {"kind", null, "invalid_message"},
            {"issuer", "other", "wrong_target"}, {"audience", "other", "wrong_target"},
            {"issuer", "mac.", "invalid_message"}, {"audience", 1, "invalid_message"},
            {"account", "other", "wrong_target"}, {"account", "bad account", "invalid_message"},
            {"account", 1, "invalid_message"}, {"action", "login", "invalid_message"},
            {"requestId", "12345678-1234-0234-8234-123456789abc", "invalid_message"},
            {"requestId", "12345678-1234-9234-8234-123456789abc", "invalid_message"},
            {"requestId", "12345678-1234-4234-c234-123456789abc", "invalid_message"},
            {"requestId", "1-1-4-8-1", "invalid_message"},
            {"nonce", ProtocolFixture.NONCE + "=", "invalid_message"},
            {"nonce", ProtocolFixture.NONCE.substring(1) + "B", "invalid_message"},
            {"nonce", true, "invalid_message"}, {"extra", "field", "invalid_message"},
            {"issuedAt", -1, "invalid_message"}, {"issuedAt", "1700000000", "invalid_message"},
            {"issuedAt", 1700000000.5, "invalid_message"},
            {"issuedAt", 9007199254740992L, "invalid_message"},
            {"issuedAt", ProtocolFixture.NOW + 6, "future_message"},
            {"expiresAt", ProtocolFixture.NOW, "invalid_ttl"},
            {"expiresAt", ProtocolFixture.NOW - 1, "invalid_ttl"},
            {"expiresAt", ProtocolFixture.NOW + 61, "invalid_ttl"},
            {"expiresAt", false, "invalid_message"}
        };
        for (Object[] row : invalid) {
            Map<String, Object> m = f.request();
            m.put((String) row[0], row[1]);
            String token = f.token(m);
            f.reject("invalid " + row[0] + "=" + row[1], (String) row[2],
                    () -> f.protocol.receive(token, ProtocolFixture.NOW));
        }
        for (String field : f.request().keySet()) {
            Map<String, Object> m = f.request();
            m.remove(field);
            String token = f.token(m);
            f.reject("missing " + field, "invalid_message",
                    () -> f.protocol.receive(token, ProtocolFixture.NOW));
        }
        String valid = f.token(f.request());
        f.reject("expiry equality", "expired",
                () -> f.protocol.receive(valid, ProtocolFixture.NOW + 45));
        f.reject("wrong key", "invalid_signature", () -> f.protocol.receive(
                f.raw(new Payload(f.request()).toBytes(), f.header(), f.approver), ProtocolFixture.NOW));
        String[] parts = valid.split("\\.");
        byte[] signature = new Base64URL(parts[2]).decode();
        signature[0] ^= 1;
        String tampered = parts[0] + "." + parts[1] + "." + Base64URL.encode(signature);
        f.reject("tampering", "invalid_signature",
                () -> f.protocol.receive(tampered, ProtocolFixture.NOW));
        String[] malformed = { "", valid + ".", valid + "=", parts[0] + "=." + parts[1]
                + "." + parts[2], parts[0] + "." + parts[1] + "=." + parts[2],
                valid.replace('.', '+'), new String(new char[16385]).replace('\0', 'a') };
        for (String token : malformed) {
            f.reject("compact encoding", "invalid_token",
                    () -> f.protocol.receive(token, ProtocolFixture.NOW));
        }
        // Same decoded signature, non-zero unused bits: canonical base64url must reject.
        String alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        int last = alphabet.indexOf(parts[2].charAt(parts[2].length() - 1));
        String alternate = valid.substring(0, valid.length() - 1) + alphabet.charAt(last + 1);
        f.reject("noncanonical trailing bits", "invalid_token",
                () -> f.protocol.receive(alternate, ProtocolFixture.NOW));
        String baseHeader = "{\"alg\":\"ES256\",\"typ\":\"remote-unlock+jws\",\"kid\":\"mac\"}";
        String[] headers = { baseHeader.replace("ES256", "HS256"),
                baseHeader.replace("ES256", "ES384"), baseHeader.replace("remote-unlock+jws", "JWT"),
                baseHeader.replace("\"mac\"", "\"other\""),
                baseHeader.replace("}", ",\"foo\":1}"),
                baseHeader.replace("}", ",\"alg\":\"ES256\"}"),
                baseHeader.replace("\"kid\":\"mac\"", "\"kid\":1"),
                baseHeader.replace("}", ",\"b64\":true}"),
                baseHeader.replace("\"alg\"", "alg") };
        for (String header : headers) {
            String token = f.rawHeader(header);
            f.reject("strict header " + header, "invalid_header",
                    () -> f.protocol.receive(token, ProtocolFixture.NOW));
        }
        String json = new Payload(f.request()).toString();
        String[] payloads = { json + "{}", json.replace("}", ",\"version\":1}"),
                json.replace("\"version\"", "version"), "\ufeff" + json,
                json.replace("\"version\":1", "\"version\":01"),
                json.replace("\"version\":1", "\"version\":NaN"),
                json.replace("\"version\":1", "\"version\":{}"),
                json.replace("\"version\":1", "\"version\":[]"),
                json.replace("\"version\":1", "\"version\":1e9999"),
                json.replace("\"version\":1", "\"version\":1e-9999") };
        for (String payload : payloads) {
            String token = f.raw(payload);
            f.reject("strict JSON", "invalid_message",
                    () -> f.protocol.receive(token, ProtocolFixture.NOW));
        }
        String badUtf8 = f.raw(new byte[] { (byte) 0xc3, 0x28 }, f.header(), f.requester);
        f.reject("malformed UTF-8", "invalid_message",
                () -> f.protocol.receive(badUtf8, ProtocolFixture.NOW));
        String malformedUnsigned = parts[0] + "." + Base64URL.encode("{") + "." + parts[2];
        f.reject("signature precedes JSON trust", "invalid_signature",
                () -> f.protocol.receive(malformedUnsigned, ProtocolFixture.NOW));
        f.reject("private requester JWK", "invalid_message", () -> new ApprovalProtocol(
                "relay", "android", "mac", "local.user", f.requester, f.approver.toECPrivateKey()));
        ECKey p384 = new ECKeyGenerator(Curve.P_384).generate();
        f.reject("wrong requester curve", "invalid_message", () -> new ApprovalProtocol(
                "relay", "android", "mac", "local.user", p384.toPublicJWK(), f.approver.toECPrivateKey()));
        f.reject("invalid configured ID", "invalid_message", () -> new ApprovalProtocol(
                "relay.", "android", "mac", "local.user",
                f.requester.toPublicJWK(), f.approver.toECPrivateKey()));
    }
}
