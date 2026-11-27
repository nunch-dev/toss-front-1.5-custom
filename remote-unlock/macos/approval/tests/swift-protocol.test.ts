import { expect, test } from "bun:test";
import { fileURLToPath } from "node:url";
import { CompactSign, exportJWK, generateKeyPair } from "jose";
import type { CompactJWSHeaderParameters } from "jose";
import { z } from "zod";
import {
  ActorIdSchema,
  DecisionSchema,
  MessageSchema,
  newNonce,
  PublicJwkSchema,
  RequestSchema,
  requestHash,
  signMessage,
  verifyMessage,
} from "../../../src/protocol";

const executable = fileURLToPath(
  new URL("../../../../private/macos-approval-20261120/protocol-conformance", import.meta.url),
);
const requester = ActorIdSchema.parse("native-mac-test");
const approver = ActorIdSchema.parse("native-approver-test");
const requesterKeys = await generateKeyPair("ES256", { extractable: true });
const approverKeys = await generateKeyPair("ES256", { extractable: true });
const requesterPublic = PublicJwkSchema.parse(await exportJWK(requesterKeys.publicKey));
const approverPublic = PublicJwkSchema.parse(await exportJWK(approverKeys.publicKey));
const now = 1_800_000_000;
const request = RequestSchema.parse({
  version: 1,
  kind: "request",
  issuer: requester,
  audience: approver,
  issuedAt: now,
  expiresAt: now + 30,
  requestId: crypto.randomUUID(),
  nonce: newNonce(),
  account: "isolated-right-test",
  action: "screen-unlock",
});
const requestToken = await signMessage(request, requesterKeys.privateKey);
const header = { alg: "ES256", typ: "remote-unlock+jws", kid: requester };
const successToken = z.strictObject({ ok: z.literal(true), token: z.string() });

class ConformanceFailure extends Error {
  constructor(readonly reason: "missing_binary" | "process_failed" | "missing_signature") {
    super(reason);
    this.name = "ConformanceFailure";
  }
}

async function native(input: Readonly<Record<string, unknown>>): Promise<unknown> {
  if (!(await Bun.file(executable).exists())) throw new ConformanceFailure("missing_binary");
  const child = Bun.spawn([executable], {
    env: process.env,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
    timeout: 5000,
    killSignal: "SIGKILL",
  });
  await child.stdin.write(JSON.stringify(input));
  await child.stdin.end();
  const [output, diagnostics, exitCode] = await Promise.all([
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
    child.exited,
  ]);
  if (exitCode !== 0 || diagnostics.length !== 0) {
    throw new ConformanceFailure("process_failed");
  }
  const result: unknown = JSON.parse(output);
  return result;
}

async function rawRequest(
  payload: unknown,
  protectedHeader: CompactJWSHeaderParameters = header,
): Promise<string> {
  return new CompactSign(new TextEncoder().encode(JSON.stringify(payload)))
    .setProtectedHeader(protectedHeader)
    .sign(requesterKeys.privateKey);
}

function verification(token: string, time = now) {
  return {
    op: "verify",
    token,
    publicKey: requesterPublic,
    issuer: requester,
    audience: approver,
    now: time,
  };
}

test("Swift verifies an unchanged jose ES256 request", async () => {
  expect(await native(verification(requestToken))).toEqual({ ok: true, message: request });
});

test("jose verifies a Swift ES256 signature with raw 64-byte encoding", async () => {
  const response = successToken.parse(
    await native({
      op: "sign",
      message: request,
      privateKey: await exportJWK(requesterKeys.privateKey),
    }),
  );
  expect(
    await verifyMessage(response.token, requesterKeys.publicKey, {
      issuer: requester,
      audience: approver,
      now: () => now,
    }),
  ).toEqual(request);
  const signature = response.token.split(".")[2];
  if (signature === undefined) throw new ConformanceFailure("missing_signature");
  expect(Buffer.from(signature, "base64url")).toHaveLength(64);
});

test("Swift signs relay authentication accepted by the common verifier", async () => {
  const authentication = MessageSchema.parse({
    version: 1,
    kind: "authenticate",
    issuer: requester,
    audience: "test-relay",
    issuedAt: now,
    expiresAt: now + 10,
    nonce: newNonce(),
  });
  const response = successToken.parse(
    await native({
      op: "sign",
      message: authentication,
      privateKey: await exportJWK(requesterKeys.privateKey),
    }),
  );
  expect(
    await verifyMessage(response.token, requesterKeys.publicKey, {
      issuer: requester,
      audience: ActorIdSchema.parse("test-relay"),
      now: () => now,
    }),
  ).toEqual(authentication);
});

test("Swift rejects a modified signature", async () => {
  const index = requestToken.lastIndexOf(".") + 1;
  const token =
    requestToken.slice(0, index) +
    (requestToken[index] === "A" ? "B" : "A") +
    requestToken.slice(index + 1);
  expect(await native(verification(token))).toEqual({ ok: false, error: "invalid_signature" });
});

test("Swift rejects an unrelated verification key", async () => {
  expect(await native({ ...verification(requestToken), publicKey: approverPublic })).toEqual({
    ok: false,
    error: "invalid_signature",
  });
});

for (const [name, payload, error] of [
  ["wrong audience", { ...request, audience: requester }, "wrong_target"],
  ["future issue time", { ...request, issuedAt: now + 6 }, "future_message"],
  ["expired message", { ...request, issuedAt: now - 30, expiresAt: now }, "expired"],
  ["excessive lifetime", { ...request, expiresAt: now + 61 }, "invalid_ttl"],
  ["fractional issue time", { ...request, issuedAt: now + 0.5 }, "invalid_message"],
  ["boolean issue time", { ...request, issuedAt: true }, "invalid_message"],
  ["unknown field", { ...request, unexpected: true }, "invalid_message"],
  ["noncanonical nonce", { ...request, nonce: "A".repeat(42) + "B" }, "invalid_message"],
  ["invalid account", { ...request, account: "../another-user" }, "invalid_message"],
] satisfies readonly (readonly [string, unknown, string])[]) {
  test(`Swift rejects a signed request with ${name}`, async () => {
    expect(await native(verification(await rawRequest(payload)))).toEqual({ ok: false, error });
  });
}

test("Swift rejects additional protected header fields", async () => {
  const token = await rawRequest(request, { ...header, extra: "untrusted" });
  expect(await native(verification(token))).toEqual({ ok: false, error: "invalid_header" });
});

for (const requestId of [
  "00000000-0000-0000-0000-000000000000",
  "ffffffff-ffff-ffff-ffff-ffffffffffff",
  "550e8400-e29b-01d4-a716-446655440000",
  "550e8400-e29b-41d4-0716-446655440000",
]) {
  test(`Swift matches the reference UUID acceptance for ${requestId}`, async () => {
    const payload = { ...request, requestId };
    const expectedValid = RequestSchema.safeParse(payload).success;
    expect(await native(verification(await rawRequest(payload)))).toMatchObject({
      ok: expectedValid,
    });
  });
}

for (const outcome of ["approve", "deny"] as const) {
  test(`Swift verifies a jose ${outcome} bound to the exact original request`, async () => {
    const decision = DecisionSchema.parse({
      version: 1,
      kind: "decision",
      issuer: approver,
      audience: requester,
      issuedAt: now,
      expiresAt: now + 20,
      requestId: request.requestId,
      requestHash: requestHash(requestToken),
      decision: outcome,
      method: "manual",
    });
    const token = await signMessage(decision, approverKeys.privateKey);
    const input = {
      op: "verify-decision",
      requestToken,
      request,
      decisionToken: token,
      publicKey: approverPublic,
      now,
    };
    expect(await native(input)).toEqual({ ok: true, message: decision });
    const wrongHash = await signMessage(
      { ...decision, requestHash: newNonce() },
      approverKeys.privateKey,
    );
    expect(await native({ ...input, decisionToken: wrongHash })).toEqual({
      ok: false,
      error: "request_mismatch",
    });
  });
}

test("Swift refuses to sign a private key with mismatched public coordinates", async () => {
  const key = await exportJWK(requesterKeys.privateKey);
  const result = await native({
    op: "sign",
    message: request,
    privateKey: { ...key, x: approverPublic.x, y: approverPublic.y },
  });
  expect(result).toMatchObject({ ok: false });
});
