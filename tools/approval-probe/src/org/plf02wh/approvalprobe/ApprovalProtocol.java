package org.plf02wh.approvalprobe;

import com.nimbusds.jose.JOSEException;
import com.nimbusds.jose.JOSEObjectType;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.JWSObject;
import com.nimbusds.jose.Payload;
import com.nimbusds.jose.crypto.ECDSASigner;
import com.nimbusds.jose.crypto.ECDSAVerifier;
import com.nimbusds.jose.jwk.Curve;
import com.nimbusds.jose.jwk.ECKey;
import com.nimbusds.jose.util.Base64URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.PrivateKey;
import java.text.ParseException;
import java.util.LinkedHashMap;
import java.util.Map;
import static org.plf02wh.approvalprobe.ProtocolJson.*;

/**
 * Stateless protocol boundary. The caller owns socket generations, cancellation,
 * the sole pending request, and atomic one-time decision commit. Repeated calls
 * can sign repeated decisions: this class does not prevent replay.
 */
public final class ApprovalProtocol {
    private static final String ID = "[A-Za-z0-9_-]{1,64}";
    private static final String BYTES32 = "[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]";
    private static final String UUID = "(?i)(?:[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}"
            + "-[89ab][0-9a-f]{3}-[0-9a-f]{12}|00000000-0000-0000-0000-000000000000"
            + "|ffffffff-ffff-ffff-ffff-ffffffffffff)";
    private final String relayId, approverId, requesterId, account;
    private final ECDSAVerifier verifier;
    private final PrivateKey signingKey;

    // Positional constructor preserves the parent app's explicit API contract.
    public ApprovalProtocol(String relayId, String approverId, String requesterId,
            String account, ECKey requesterPublicKey, PrivateKey signingKey)
            throws ProtocolException {
        matches(relayId, ID);
        matches(approverId, ID);
        matches(requesterId, ID);
        matches(account, "[A-Za-z0-9_.-]{1,64}");
        if (requesterPublicKey == null || requesterPublicKey.isPrivate()
                || !Curve.P_256.equals(requesterPublicKey.getCurve())
                || signingKey == null || !"EC".equals(signingKey.getAlgorithm())) {
            throw error("invalid_message");
        }
        matches(requesterPublicKey.getX().toString(), BYTES32);
        matches(requesterPublicKey.getY().toString(), BYTES32);
        try {
            this.verifier = new ECDSAVerifier(requesterPublicKey.toECPublicKey());
        } catch (JOSEException e) {
            throw error("invalid_message");
        }
        this.relayId = relayId;
        this.approverId = approverId;
        this.requesterId = requesterId;
        this.account = account;
        this.signingKey = signingKey;
    }

    public String authenticate(String nonce, long challengeExpiresAt, long now)
            throws ProtocolException {
        matches(nonce, BYTES32);
        clock(now);
        if (challengeExpiresAt < 0 || challengeExpiresAt > MAX_INTEGER) {
            throw error("invalid_message");
        }
        if (now >= challengeExpiresAt) throw error("expired");
        Map<String, Object> message = common("authenticate", relayId, now,
                Math.min(challengeExpiresAt, now + 10));
        message.put("nonce", nonce);
        return sign(message);
    }

    public PendingRequest receive(String token, long now) throws ProtocolException {
        if (token == null || token.length() > 16384) throw error("invalid_token");
        String[] parts = token.split("\\.", -1);
        if (parts.length != 3) throw error("invalid_token");
        byte[] headerBytes = decode(parts[0]);
        byte[] payloadBytes = decode(parts[1]);
        if (decode(parts[2]).length != 64) throw error("invalid_signature");
        Map<String, Object> header = object(headerBytes, "invalid_header");
        fields(header, "invalid_header", "alg", "typ", "kid");
        if (!"ES256".equals(header.get("alg"))
                || !"remote-unlock+jws".equals(header.get("typ"))
                || !requesterId.equals(header.get("kid"))) throw error("invalid_header");
        try {
            if (!JWSObject.parse(token).verify(verifier)) throw error("invalid_signature");
        } catch (ParseException | JOSEException e) {
            throw error("invalid_signature");
        }
        // Payload parsing and interpretation happen only after signature verification.
        Map<String, Object> message = object(payloadBytes, "invalid_message");
        fields(message, "invalid_message", "version", "kind", "issuer", "audience",
                "issuedAt", "expiresAt", "requestId", "nonce", "account", "action");
        if (integer(message, "version") != 1 || !"request".equals(message.get("kind"))
                || !"screen-unlock".equals(message.get("action"))) throw error("invalid_message");
        String issuer = string(message, "issuer");
        String audience = string(message, "audience");
        matches(issuer, ID);
        matches(audience, ID);
        if (!requesterId.equals(issuer) || !approverId.equals(audience)) throw error("wrong_target");
        String requestId = string(message, "requestId");
        matches(requestId, UUID);
        matches(string(message, "nonce"), BYTES32);
        String targetAccount = string(message, "account");
        matches(targetAccount, "[A-Za-z0-9_.-]{1,64}");
        if (!account.equals(targetAccount)) throw error("wrong_target");
        long issuedAt = integer(message, "issuedAt");
        long expiresAt = integer(message, "expiresAt");
        if (expiresAt <= issuedAt || expiresAt - issuedAt > 60) throw error("invalid_ttl");
        clock(now);
        if (issuedAt > now + 5) throw error("future_message");
        if (now >= expiresAt) throw error("expired");
        try {
            String hash = Base64URL.encode(MessageDigest.getInstance("SHA-256")
                    .digest(token.getBytes(StandardCharsets.UTF_8))).toString();
            return new PendingRequest(this, requestId, issuer, targetAccount, expiresAt, hash);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("JCA SHA-256 unavailable", e);
        }
    }

    public String decision(PendingRequest pending, boolean approve, long now)
            throws ProtocolException {
        if (pending == null || pending.owner != this) throw error("request_mismatch");
        clock(now);
        if (now >= pending.expiresAt) throw error("expired");
        Map<String, Object> message = common("decision", pending.issuer, now,
                Math.min(pending.expiresAt, now + 60));
        message.put("requestId", pending.requestId);
        message.put("requestHash", pending.requestHash);
        message.put("decision", approve ? "approve" : "deny");
        message.put("method", "manual");
        return sign(message);
    }

    private Map<String, Object> common(String kind, String audience, long now, long expiresAt) {
        Map<String, Object> message = new LinkedHashMap<>();
        message.put("version", 1);
        message.put("kind", kind);
        message.put("issuer", approverId);
        message.put("audience", audience);
        message.put("issuedAt", now);
        message.put("expiresAt", expiresAt);
        return message;
    }

    private String sign(Map<String, Object> message) throws ProtocolException {
        JWSObject jws = new JWSObject(new JWSHeader.Builder(JWSAlgorithm.ES256)
                .type(new JOSEObjectType("remote-unlock+jws")).keyID(approverId).build(),
                new Payload(message));
        try {
            jws.sign(new ECDSASigner(signingKey, Curve.P_256));
            return jws.serialize();
        } catch (JOSEException e) {
            throw new ProtocolException("signing_failed", e);
        }
    }

    private static void clock(long now) throws ProtocolException {
        if (now < 0 || now > MAX_INTEGER - 60) throw error("invalid_message");
    }

    public static final class ProtocolException extends Exception {
        private static final long serialVersionUID = 1L;
        public final String code;
        ProtocolException(String code) { super(code); this.code = code; }
        ProtocolException(String code, Throwable cause) { super(code, cause); this.code = code; }
    }

    /** Immutable verified data, not a cancellation or one-time-consumption capability. */
    public static final class PendingRequest {
        public final String requestId, issuer, account, requestHash;
        public final long expiresAt;
        private final ApprovalProtocol owner;
        private PendingRequest(ApprovalProtocol owner, String requestId, String issuer,
                String account, long expiresAt, String requestHash) {
            this.owner = owner;
            this.requestId = requestId;
            this.issuer = issuer;
            this.account = account;
            this.expiresAt = expiresAt;
            this.requestHash = requestHash;
        }
    }
}
