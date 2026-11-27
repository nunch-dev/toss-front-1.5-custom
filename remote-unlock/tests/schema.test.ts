import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { exportJWK, generateKeyPair } from "jose";
import {
  ActorIdSchema,
  RequestIdSchema,
  PublicJwkSchema,
  newNonce,
  requestHash,
} from "../src/protocol";

const requesterKeys = await generateKeyPair("ES256");
const requester = ActorIdSchema.parse("mac-1");

describe("protocol boundaries", () => {
  test.each(["", "a b", "é", "a".repeat(65), "a\n"])("rejects actor ID %j", (id) => {
    expect(ActorIdSchema.safeParse(id).success).toBe(false);
  });
  test("accepts bounded actor IDs and requires UUID request IDs", () => {
    expect(String(ActorIdSchema.parse("A".repeat(64)))).toBe("A".repeat(64));
    expect(RequestIdSchema.safeParse("arbitrary-id").success).toBe(false);
  });
  test("accepts only strict public P-256 JWKs with canonical coordinates", async () => {
    const jwk = await exportJWK(requesterKeys.publicKey);
    expect(jwk).toEqual(PublicJwkSchema.parse(jwk));
    for (const invalid of [
      { ...jwk, d: "private" },
      { ...jwk, kid: requester },
      { ...jwk, crv: "P-384" },
      { ...jwk, x: "A".repeat(42) + "B" },
      { ...jwk, y: "A".repeat(44) },
      { ...jwk, x: "A".repeat(43) + "=" },
    ])
      expect(PublicJwkSchema.safeParse(invalid).success).toBe(false);
  });
  test("generates fresh canonical 32-byte nonces", () => {
    const first = newNonce();
    expect(first).toMatch(/^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/);
    expect(Buffer.from(first, "base64url")).toHaveLength(32);
    expect(newNonce()).not.toBe(first);
  });
  test("hashes exact UTF-8 request bytes with SHA-256", () => {
    const original = "signed.request.é";
    expect(requestHash(original)).toBe(
      createHash("sha256").update(original, "utf8").digest("base64url"),
    );
    expect(requestHash(original + " ")).not.toBe(requestHash(original));
  });
});
