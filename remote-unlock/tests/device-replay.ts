import assert from "node:assert/strict";
import { resolve } from "node:path";
import { z } from "zod";
import { connectPeer } from "../src/connection";
import { readCredentials } from "../src/credentials";
import {
  newNonce,
  PendingApproval,
  ProtocolError,
  RequestSchema,
  signMessage,
} from "../src/protocol";
import { loadRegistry } from "../src/registry";

// Explicit LAN scenario, not an automatically discovered unit-test file.
// The real device must deny this request through its ordinary approval screen.
const [directory, relayURL] = z
  .tuple([z.string().min(1), z.string().url()])
  .parse(process.argv.slice(2));
const registry = await loadRegistry(
  await Bun.file(resolve(directory, "identity/registry.json")).json(),
);
const credential = await readCredentials(resolve(directory, "identity/mac.private.json"));
const grant = registry.grants.find((entry) => entry.requestor === credential.actor);
assert(grant, "The trial requestor must have a registered grant");
const approver = registry.devices.get(grant.approver);
assert(approver?.role === "approver", "The grant must target the registered device");
const now = () => Math.floor(Date.now() / 1000);
const connection = await connectPeer({
  url: relayURL,
  actor: credential.actor,
  relay: registry.relayId,
  key: credential.key,
  now,
});
try {
  const issuedAt = now();
  const request = RequestSchema.parse({
    version: 1,
    kind: "request",
    issuer: credential.actor,
    audience: approver.id,
    issuedAt,
    expiresAt: issuedAt + 30,
    requestId: crypto.randomUUID(),
    nonce: newNonce(),
    account: grant.account,
    action: "screen-unlock",
  });
  const token = await signMessage(request, credential.key);
  const pending = new PendingApproval(token, request);
  connection.send(token);
  const submitted = await connection.next();
  assert(submitted.kind === "submitted", "The initial request must be accepted");
  assert.equal(submitted.requestId, request.requestId);
  console.info(`DEVICE_REPLAY_REQUEST_SENT requestId=${request.requestId}`);
  const response = await connection.next();
  assert(response.kind === "signed", "A real signed device response is required");
  const decision = await pending.consume(response.token, approver.key, now);
  assert.equal(decision.decision, "deny");
  await assert.rejects(
    () => pending.consume(response.token, approver.key, now),
    (error: unknown) => error instanceof ProtocolError && error.code === "replayed",
  );
  console.info("DEVICE_RESPONSE_REPLAY_REJECTED");
  connection.send(token);
  const duplicate = await connection.next();
  assert(duplicate.kind === "error", "A repeated request must not reach the device again");
  assert.equal(duplicate.code, "duplicate_request");
  console.info("DEVICE_REQUEST_REPLAY_REJECTED");
} finally {
  connection.close();
}
