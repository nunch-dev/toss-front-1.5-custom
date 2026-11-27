import { describe, expect, test } from "bun:test";
import { CompactSign, compactVerify, generateKeyPair } from "jose";
import type { CompactJWSHeaderParameters } from "jose";
import {
  ActorIdSchema,
  MessageSchema,
  RequestSchema,
  DecisionSchema,
  PendingApproval,
  ProtocolError,
  newNonce,
  requestHash,
  signMessage,
  verifyMessage,
} from "../src/protocol";
import type { ProtocolErrorCode } from "../src/protocol";

const requester = ActorIdSchema.parse("mac-1");
const approver = ActorIdSchema.parse("phone_1");
const requesterKeys = await generateKeyPair("ES256", { extractable: true });
const approverKeys = await generateKeyPair("ES256", { extractable: true });
const now = () => 1_000;
const request = RequestSchema.parse({
  version: 1,
  kind: "request",
  issuer: requester,
  audience: approver,
  issuedAt: 1_000,
  expiresAt: 1_060,
  requestId: "550e8400-e29b-41d4-a716-446655440000",
  nonce: newNonce(),
  account: "local.user",
  action: "screen-unlock",
});
const requestToken = await signMessage(request, requesterKeys.privateKey);
const decision = DecisionSchema.parse({
  version: 1,
  kind: "decision",
  issuer: approver,
  audience: requester,
  issuedAt: 1_000,
  expiresAt: 1_050,
  requestId: request.requestId,
  requestHash: requestHash(requestToken),
  decision: "approve",
  method: "manual",
});
const header = { alg: "ES256", typ: "remote-unlock+jws", kid: requester };
const expected = { issuer: requester, audience: approver, now };

async function rawToken(
  payload: unknown,
  protectedHeader: CompactJWSHeaderParameters = header,
): Promise<string> {
  return new CompactSign(new TextEncoder().encode(JSON.stringify(payload)))
    .setProtectedHeader(protectedHeader)
    .sign(requesterKeys.privateKey);
}

async function rejectsCode(promise: Promise<unknown>, code: ProtocolErrorCode): Promise<void> {
  const error: unknown = await promise.catch((caught: unknown) => caught);
  expect(error).toBeInstanceOf(ProtocolError);
  if (!(error instanceof ProtocolError)) throw new Error("Expected ProtocolError");
  expect(error.code).toBe(code);
}

describe("signed messages", () => {
  test.each([
    request,
    MessageSchema.parse({
      version: 1,
      kind: "authenticate",
      issuer: requester,
      audience: approver,
      issuedAt: 1_000,
      expiresAt: 1_060,
      nonce: newNonce(),
    }),
  ])("round trips $kind with the exact JOSE protected header", async (message) => {
    const token = await signMessage(message, requesterKeys.privateKey);
    const jose = await compactVerify(token, requesterKeys.publicKey);
    expect(jose.protectedHeader).toEqual(header);
    expect(await verifyMessage(token, requesterKeys.publicKey, expected)).toEqual(message);
  });
  test("rejects a tampered signature", async () => {
    const start = requestToken.lastIndexOf(".") + 1;
    const changed =
      requestToken.slice(0, start) +
      (requestToken[start] === "A" ? "B" : "A") +
      requestToken.slice(start + 1);
    await rejectsCode(
      verifyMessage(changed, requesterKeys.publicKey, expected),
      "invalid_signature",
    );
  });
  test("rejects the wrong verification key", async () => {
    await rejectsCode(
      verifyMessage(requestToken, approverKeys.publicKey, expected),
      "invalid_signature",
    );
  });
  test.each([
    { ...header, typ: "JWT" },
    { ...header, kid: approver },
    { ...header, extra: true },
    { alg: "ES256", kid: requester },
  ])("rejects unexpected protected header %j", async (protectedHeader) => {
    const token = await rawToken(request, protectedHeader);
    await rejectsCode(verifyMessage(token, requesterKeys.publicKey, expected), "invalid_header");
  });
  test("rejects a correctly signed non-ES256 algorithm", async () => {
    const keys = await generateKeyPair("ES384");
    const token = await new CompactSign(new TextEncoder().encode(JSON.stringify(request)))
      .setProtectedHeader({ ...header, alg: "ES384" })
      .sign(keys.privateKey);
    await rejectsCode(verifyMessage(token, keys.publicKey, expected), "invalid_signature");
  });
  test.each([
    [{ ...request, audience: requester }, "wrong_target"],
    [{ ...request, issuer: approver }, "wrong_target"],
    [{ ...request, issuedAt: 1_006 }, "future_message"],
    [{ ...request, expiresAt: 1_000 }, "invalid_ttl"],
    [{ ...request, expiresAt: 999 }, "invalid_ttl"],
    [{ ...request, expiresAt: 1_061 }, "invalid_ttl"],
    [{ ...request, issuedAt: 940, expiresAt: 1_000 }, "expired"],
    [{ ...request, issuedAt: 1_000.1 }, "invalid_message"],
    [{ ...request, expiresAt: 1_059.9 }, "invalid_message"],
    [{ ...request, unknown: true }, "invalid_message"],
    [{ ...request, account: "../user" }, "invalid_message"],
    [{ ...request, nonce: "A".repeat(42) + "B" }, "invalid_message"],
    [{ ...request, action: "execute" }, "invalid_message"],
  ] satisfies readonly (readonly [unknown, ProtocolErrorCode])[])(
    "rejects signed invalid payload %j",
    async (payload, code) => {
      await rejectsCode(
        verifyMessage(await rawToken(payload), requesterKeys.publicKey, expected),
        code,
      );
    },
  );
  test("accepts exactly five seconds of future skew", async () => {
    const payload = { ...request, issuedAt: 1_005 };
    expect(await verifyMessage(await rawToken(payload), requesterKeys.publicKey, expected)).toEqual(
      payload,
    );
  });
  test("rejects tokens exceeding 16 KiB", async () => {
    const token = await rawToken({ ...request, padding: "a".repeat(16 * 1024) });
    await rejectsCode(verifyMessage(token, requesterKeys.publicKey, expected), "invalid_token");
  });
  test("checks signature before trusting malformed payloads", async () => {
    const token = await rawToken({ unknown: true });
    await rejectsCode(verifyMessage(token, approverKeys.publicKey, expected), "invalid_signature");
  });
});

describe("pending approvals", () => {
  test.each(["approve", "deny"] as const)("consumes a valid %s once", async (outcome) => {
    const response = DecisionSchema.parse({ ...decision, decision: outcome });
    const token = await signMessage(response, approverKeys.privateKey);
    const pending = new PendingApproval(requestToken, request);
    expect(await pending.consume(token, approverKeys.publicKey, now)).toEqual(response);
    await rejectsCode(pending.consume(token, approverKeys.publicKey, now), "replayed");
  });
  test.each([
    [{ ...decision, requestId: "550e8400-e29b-41d4-a716-446655440001" }, "request_mismatch"],
    [{ ...decision, requestHash: newNonce() }, "request_mismatch"],
    [{ ...decision, issuedAt: 1_001, expiresAt: 1_061 }, "request_mismatch"],
    [{ ...decision, audience: approver }, "wrong_target"],
    [{ ...decision, issuer: requester }, "wrong_target"],
    [{ ...decision, issuedAt: 940, expiresAt: 1_000 }, "expired"],
    [request, "wrong_target"],
    [{ ...request, issuer: approver, audience: requester }, "request_mismatch"],
  ] satisfies readonly (readonly [unknown, ProtocolErrorCode])[])(
    "rejects mismatched responses without consuming the request %j",
    async (payload, code) => {
      const pending = new PendingApproval(requestToken, request);
      const token = await new CompactSign(new TextEncoder().encode(JSON.stringify(payload)))
        .setProtectedHeader({ ...header, kid: approver })
        .sign(approverKeys.privateKey);
      await rejectsCode(pending.consume(token, approverKeys.publicKey, now), code);
      const valid = await signMessage(decision, approverKeys.privateKey);
      expect(await pending.consume(valid, approverKeys.publicKey, now)).toEqual(decision);
    },
  );
  test("binds the original token bytes, including alternate valid serializations", async () => {
    const alternate = await new CompactSign(
      new TextEncoder().encode(JSON.stringify(request, null, 2)),
    )
      .setProtectedHeader(header)
      .sign(requesterKeys.privateKey);
    const pending = new PendingApproval(alternate, request);
    const token = await signMessage(decision, approverKeys.privateKey);
    await rejectsCode(pending.consume(token, approverKeys.publicKey, now), "request_mismatch");
  });
  test("rejects the wrong peer key without consuming the request", async () => {
    const pending = new PendingApproval(requestToken, request);
    const token = await signMessage(decision, approverKeys.privateKey);
    await rejectsCode(pending.consume(token, requesterKeys.publicKey, now), "invalid_signature");
    expect(await pending.consume(token, approverKeys.publicKey, now)).toEqual(decision);
  });
  test("rejects an expired request even while its response remains valid", async () => {
    const pending = new PendingApproval(requestToken, { ...request, expiresAt: 1_020 });
    const token = await signMessage(decision, approverKeys.privateKey);
    await rejectsCode(
      pending.consume(token, approverKeys.publicKey, () => 1_020),
      "expired",
    );
  });
  test("rejects cancellation before consumption", async () => {
    const pending = new PendingApproval(requestToken, request);
    const token = await signMessage(decision, approverKeys.privateKey);
    pending.cancel();
    await rejectsCode(pending.consume(token, approverKeys.publicKey, now), "cancelled");
  });
  test("honors cancellation during signature verification", async () => {
    const pending = new PendingApproval(requestToken, request);
    const token = await signMessage(decision, approverKeys.privateKey);
    const consuming = pending.consume(token, approverKeys.publicKey, now);
    pending.cancel();
    await rejectsCode(consuming, "cancelled");
  });
  test("rejects expiry reached during signature verification", async () => {
    const pending = new PendingApproval(requestToken, request);
    const token = await signMessage(decision, approverKeys.privateKey);
    let clock = 1_000;
    const consuming = pending.consume(token, approverKeys.publicKey, () => clock);
    clock = 1_060;
    await rejectsCode(consuming, "expired");
  });
  test("rejects concurrent consumption and accepts only the first response", async () => {
    const pending = new PendingApproval(requestToken, request);
    const token = await signMessage(decision, approverKeys.privateKey);
    const first = pending.consume(token, approverKeys.publicKey, now);
    await rejectsCode(pending.consume(token, approverKeys.publicKey, now), "in_progress");
    expect(await first).toEqual(decision);
    await rejectsCode(pending.consume(token, approverKeys.publicKey, now), "replayed");
  });
});
