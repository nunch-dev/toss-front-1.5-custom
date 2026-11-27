import { expect, test } from "bun:test";
import { receiveRequest, sendDecision } from "../../../src/approval";
import { requestHash } from "../../../src/protocol";
import { NativeRelayFailure, recordsSchema, setup } from "../helper/tests/RelayFixture";

for (const account of ["isolated-right-test", "screen-trial-uid-501"]) {
  for (const decision of ["approve", "deny"] as const) {
    test(`Swift requester receives bound ${decision} for ${account} over WSS`, async () => {
      const fixture = await setup({ account });
      const device = await fixture.device();
      const incoming = receiveRequest(device);
      const native = await fixture.requester();
      try {
        const received = await Promise.race([
          incoming,
          native.result.then((result) => {
            throw new NativeRelayFailure(result.stderr);
          }),
        ]);
        await sendDecision(device, received, decision);
        const result = await native.result;
        expect(result.exit).toBe(0);
        expect(result.stderr).toBe("");
        const records = recordsSchema.parse(
          result.stdout
            .trim()
            .split("\n")
            .map((line) => JSON.parse(line)),
        );
        expect(records).toHaveLength(2);
        const binding = {
          version: 2,
          mode: fixture.invocation.mode,
          account,
          context: fixture.invocation.context,
          generation: fixture.invocation.generation,
          requestId: fixture.invocation.requestId,
          requestHash: requestHash(received.token),
        } as const;
        expect(records[0]).toEqual({
          ...binding,
          kind: "bound",
          expiresAt: fixture.invocation.expiresAt,
        });
        expect(records[1]).toMatchObject({ ...binding, kind: "result", decision });
        expect(received.request.account).toBe(account);
      } finally {
        await native.stop();
        device.connection.close();
        await fixture.relay.stop();
      }
    });
  }
}

test("Swift requester refuses a TLS certificate without an explicitly trusted anchor", async () => {
  const fixture = await setup();
  const native = await fixture.requester(false);
  try {
    const result = await native.result;
    expect(result.exit).toBe(1);
    expect(result.stdout).toBe("");
    expect(result.stderr).toBe("REQUESTOR_FAILED transport_or_process_failure\n");
  } finally {
    await native.stop();
    await fixture.relay.stop();
  }
});

test("Swift requester rejects the wrong hostname even when its certificate is trusted", async () => {
  const fixture = await setup({ certificate: "wrong-host" });
  const native = await fixture.requester();
  try {
    const result = await native.result;
    expect(result.exit).toBe(1);
    expect(result.stdout).toBe("");
    expect(result.stderr).toBe("REQUESTOR_FAILED transport_or_process_failure\n");
  } finally {
    await native.stop();
    await fixture.relay.stop();
  }
});

test("Swift screen requester refuses an isolated-only relay grant", async () => {
  const fixture = await setup({ account: "screen-trial-uid-501", grant: "isolated-right-test" });
  const device = await fixture.device();
  const native = await fixture.requester();
  try {
    const result = await native.result;
    expect(result.exit).toBe(1);
    expect(result.stderr).toBe("REQUESTOR_FAILED remote_rejected\n");
    const records = recordsSchema.parse(
      result.stdout
        .trim()
        .split("\n")
        .filter(Boolean)
        .map((line) => JSON.parse(line)),
    );
    expect(records.some((record) => record.kind === "result")).toBe(false);
  } finally {
    await native.stop();
    device.connection.close();
    await fixture.relay.stop();
  }
});

test("closing the control pipe cancels the native requester without a result", async () => {
  const fixture = await setup();
  const device = await fixture.device();
  const incoming = receiveRequest(device);
  const native = await fixture.requester();
  try {
    await Promise.race([
      incoming,
      native.result.then((result) => {
        throw new NativeRelayFailure(result.stderr);
      }),
    ]);
    await native.child.stdin.end();
    const result = await native.result;
    expect(result.stderr).toBe("");
    expect(result.exit).toBe(2);
    const records = recordsSchema.parse(
      result.stdout.trim()
        ? result.stdout
            .trim()
            .split("\n")
            .map((line) => JSON.parse(line))
        : [],
    );
    expect(records.some((record) => record.kind === "result")).toBe(false);
    expect(await device.connection.next()).toEqual({ kind: "error", code: "cancelled" });
  } finally {
    await native.stop();
    device.connection.close();
    await fixture.relay.stop();
  }
});
