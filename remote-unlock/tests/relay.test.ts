import { expect, test } from "bun:test";
import { exportJWK, generateKeyPair } from "jose";
import { receiveRequest, requestApproval, sendDecision } from "../src/approval";
import { Connection, connectPeer } from "../src/connection";
import {
  ActorIdSchema,
  MessageSchema,
  newNonce,
  RequestSchema,
  signMessage,
} from "../src/protocol";
import { loadRegistry } from "../src/registry";
import { startRelay } from "../src/relay";
import { RelayError } from "../src/wire";

async function setup() {
  const macKeys = await generateKeyPair("ES256");
  const deviceKeys = await generateKeyPair("ES256");
  const macId = ActorIdSchema.parse("test-mac");
  const deviceId = ActorIdSchema.parse("test-device");
  const registry = await loadRegistry({
    relayId: "test-relay",
    devices: [
      { id: macId, role: "requestor", publicKey: await exportJWK(macKeys.publicKey) },
      { id: deviceId, role: "approver", publicKey: await exportJWK(deviceKeys.publicKey) },
    ],
    grants: [{ requestor: macId, approver: deviceId, account: "test-account" }],
  });
  const now = () => Math.floor(Date.now() / 1000);
  const relay = startRelay({ registry, hostname: "127.0.0.1", port: 0, now });
  const url = `ws://127.0.0.1:${relay.port}/v1/relay`;
  const connections: Connection[] = [];
  return {
    registry,
    now,
    relay,
    url,
    macId,
    deviceId,
    macKeys,
    deviceKeys,
    async connect(role: "requestor" | "approver") {
      const actor = role === "requestor" ? macId : deviceId;
      const key = role === "requestor" ? macKeys.privateKey : deviceKeys.privateKey;
      const connection = await connectPeer({ url, actor, relay: registry.relayId, key, now });
      connections.push(connection);
      return { connection, registry, actor, key, now };
    },
    async stop() {
      for (const connection of connections) connection.close();
      await relay.stop();
    },
  };
}

for (const decision of ["approve", "deny"] as const) {
  test(`delivers a verified ${decision} over two real WebSocket connections`, async () => {
    const fixture = await setup();
    try {
      const mac = await fixture.connect("requestor");
      const device = await fixture.connect("approver");
      const incoming = receiveRequest(device);
      const result = requestApproval(mac, { approver: fixture.deviceId, account: "test-account" });
      const request = await incoming;
      await sendDecision(device, request, decision);
      const received = await result;
      expect(received.decision).toBe(decision);
      expect(received.requestId).toBe(request.request.requestId);
      expect(received.method).toBe("manual");
    } finally {
      await fixture.stop();
    }
  });
}

test("server rejects an ungranted account even with a valid requestor signature", async () => {
  const fixture = await setup();
  try {
    const mac = await fixture.connect("requestor");
    await fixture.connect("approver");
    const issuedAt = fixture.now();
    const token = await signMessage(
      RequestSchema.parse({
        version: 1,
        kind: "request",
        issuer: fixture.macId,
        audience: fixture.deviceId,
        issuedAt,
        expiresAt: issuedAt + 30,
        requestId: crypto.randomUUID(),
        nonce: newNonce(),
        account: "another-account",
        action: "screen-unlock",
      }),
      fixture.macKeys.privateKey,
    );
    mac.connection.send(token);
    expect(await mac.connection.next()).toEqual({ kind: "error", code: "not_allowed" });
  } finally {
    await fixture.stop();
  }
});

test("server rejects duplicate request IDs without forwarding another approval", async () => {
  const fixture = await setup();
  try {
    const mac = await fixture.connect("requestor");
    const device = await fixture.connect("approver");
    const issuedAt = fixture.now();
    const request = RequestSchema.parse({
      version: 1,
      kind: "request",
      issuer: fixture.macId,
      audience: fixture.deviceId,
      issuedAt,
      expiresAt: issuedAt + 30,
      requestId: crypto.randomUUID(),
      nonce: newNonce(),
      account: "test-account",
      action: "screen-unlock",
    });
    const token = await signMessage(request, fixture.macKeys.privateKey);
    mac.connection.send(token);
    expect(await mac.connection.next()).toEqual({
      kind: "submitted",
      requestId: request.requestId,
    });
    const incoming = await receiveRequest(device);
    await sendDecision(device, incoming, "deny");
    expect((await mac.connection.next()).kind).toBe("signed");
    mac.connection.send(token);
    expect(await mac.connection.next()).toEqual({ kind: "error", code: "duplicate_request" });
  } finally {
    await fixture.stop();
  }
});

test("disconnecting the approver cancels the waiting request", async () => {
  const fixture = await setup();
  try {
    const mac = await fixture.connect("requestor");
    const device = await fixture.connect("approver");
    const incoming = receiveRequest(device);
    const result = requestApproval(mac, {
      approver: fixture.deviceId,
      account: "test-account",
    }).then(
      (value) => value,
      (error: unknown) => error,
    );
    await incoming;
    device.connection.close();
    const error = await result;
    expect(error).toBeInstanceOf(RelayError);
    expect(error).toMatchObject({ code: "cancelled" });
  } finally {
    await fixture.stop();
  }
});

test("offline approvers cannot queue an approval for later execution", async () => {
  const fixture = await setup();
  try {
    const mac = await fixture.connect("requestor");
    const error: unknown = await requestApproval(mac, {
      approver: fixture.deviceId,
      account: "test-account",
    }).then(
      (value) => value,
      (caught: unknown) => caught,
    );
    expect(error).toBeInstanceOf(RelayError);
    expect(error).toMatchObject({ code: "peer_offline" });
  } finally {
    await fixture.stop();
  }
});

test("closing the requestor invalidates its approval and cancels the peer request", async () => {
  const fixture = await setup();
  try {
    const mac = await fixture.connect("requestor");
    const device = await fixture.connect("approver");
    const incoming = receiveRequest(device);
    const result = requestApproval(mac, {
      approver: fixture.deviceId,
      account: "test-account",
    }).then(
      (value) => value,
      (error: unknown) => error,
    );
    await incoming;
    mac.connection.close();
    expect(mac.connection.signal.aborted).toBe(true);
    expect(await result).toMatchObject({ code: "closed" });
    expect(await device.connection.next()).toEqual({ kind: "error", code: "cancelled" });
  } finally {
    await fixture.stop();
  }
});

test("an authentication signature cannot be replayed on another socket", async () => {
  const fixture = await setup();
  const first = new Connection(fixture.url);
  const second = new Connection(fixture.url);
  try {
    const challenge = await first.next();
    const secondChallenge = await second.next();
    if (challenge.kind !== "challenge" || secondChallenge.kind !== "challenge") {
      throw new TypeError("Expected connection challenges");
    }
    const issuedAt = fixture.now();
    const authentication = await signMessage(
      MessageSchema.parse({
        version: 1,
        kind: "authenticate",
        issuer: fixture.macId,
        audience: fixture.registry.relayId,
        issuedAt,
        expiresAt: issuedAt + 5,
        nonce: challenge.nonce,
      }),
      fixture.macKeys.privateKey,
    );
    second.send(authentication);
    expect(await second.next()).toEqual({ kind: "error", code: "not_allowed" });
    first.send(authentication);
    expect(await first.next()).toEqual({ kind: "authenticated", actor: fixture.macId });
  } finally {
    first.close();
    second.close();
    await fixture.stop();
  }
});

test("plaintext relay binding on a public interface is rejected", async () => {
  const fixture = await setup();
  try {
    expect(() =>
      startRelay({
        registry: fixture.registry,
        hostname: "0.0.0.0",
        port: 0,
      }),
    ).toThrow("invalid_transport");
  } finally {
    await fixture.stop();
  }
});
