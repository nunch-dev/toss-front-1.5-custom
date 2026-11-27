import { expect, test } from "bun:test";
import { receiveRequest, sendDecision } from "../../../../src/approval";
import { requestHash } from "../../../../src/protocol";
import { NativeRelayFailure, recordsSchema, setup } from "./RelayFixture";

for (const account of ["isolated-right-test", "screen-trial-uid-501"]) {
  for (const decision of ["approve", "deny"] as const) {
    test(`production helper flow emits ${decision} for ${account}`, async () => {
      const fixture = await setup({ account });
      const device = await fixture.device();
      const incoming = receiveRequest(device);
      // UINT_MAX makes capture unavailable; isolated mode must never capture.
      const native = await fixture.requester(
        true,
        account === "isolated-right-test" ? 4294967295 : 0,
      );
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
        const binding = {
          version: 2,
          mode: fixture.invocation.mode,
          account,
          context: fixture.invocation.context,
          generation: fixture.invocation.generation,
          requestId: fixture.invocation.requestId,
          requestHash: requestHash(received.token),
        } as const;
        expect(records).toHaveLength(2);
        expect(records[0]).toEqual({
          ...binding,
          kind: "bound",
          expiresAt: fixture.invocation.expiresAt,
        });
        expect(records[1]).toMatchObject({ ...binding, kind: "result", decision });
      } finally {
        await native.stop();
        device.connection.close();
        await fixture.relay.stop();
      }
    });
  }
}

for (const mismatch of ["executionUID", "targetConsoleUID", "mode", "account"] as const) {
  test(`helper rejects policy/invocation ${mismatch} mismatch`, async () => {
    const fixture = await setup({ account: "screen-trial-uid-501" });
    switch (mismatch) {
      case "executionUID":
        fixture.helperPolicy.executionUID = (process.getuid?.() ?? 0) + 1;
        break;
      case "targetConsoleUID":
        fixture.helperPolicy.targetConsoleUID = 502;
        fixture.policy.account = "screen-trial-uid-502";
        break;
      case "mode":
        fixture.helperPolicy.mode = "isolated-right-test";
        fixture.helperPolicy.targetConsoleUID = null;
        fixture.helperPolicy.requesterKeyFile =
          "/Library/Application Support/PLF02WHRemoteApproval/requester.private.json";
        fixture.policy.account = "isolated-right-test";
        break;
      case "account":
        fixture.invocation.account = "isolated-right-test";
        break;
      default: {
        const unreachable: never = mismatch;
        throw new NativeRelayFailure(unreachable);
      }
    }
    const native = await fixture.requester(true, 0);
    try {
      const result = await native.result;
      expect(result.exit).toBe(1);
      expect(result.stdout).toBe("");
      expect(result.stderr).toBe("APPROVAL_HELPER_FAILED\n");
      expect(await Bun.file(`${native.directory}/key-read`).exists()).toBe(false);
    } finally {
      await native.stop();
      await fixture.relay.stop();
    }
  });
}

for (const changeAt of [1, 2, 4294967295]) {
  test(`helper rejects unavailable or changed context before output (${changeAt})`, async () => {
    const fixture = await setup({ account: "screen-trial-uid-501" });
    const device = await fixture.device();
    const native = await fixture.requester(true, changeAt);
    try {
      const result = await native.result;
      expect(result.stdout).toBe("");
      expect(result.exit).toBe(1);
      expect(result.stderr).toBe("APPROVAL_HELPER_FAILED\n");
      expect(await Bun.file(`${native.directory}/key-read`).exists()).toBe(changeAt === 2);
    } finally {
      await native.stop();
      device.connection.close();
      await fixture.relay.stop();
    }
  });
}

test("helper withholds result when context changes after bound", async () => {
  const fixture = await setup({ account: "screen-trial-uid-501" });
  const device = await fixture.device();
  const incoming = receiveRequest(device);
  const native = await fixture.requester(true, 3);
  try {
    const received = await Promise.race([
      incoming,
      native.result.then((result) => {
        throw new NativeRelayFailure(result.stderr);
      }),
    ]);
    await sendDecision(device, received, "approve");
    const result = await native.result;
    expect(result.exit).toBe(1);
    expect(result.stderr).toBe("APPROVAL_HELPER_FAILED\n");
    const records = recordsSchema.parse(
      result.stdout
        .trim()
        .split("\n")
        .map((line) => JSON.parse(line)),
    );
    expect(records).toHaveLength(1);
    expect(records[0]?.kind).toBe("bound");
  } finally {
    await native.stop();
    device.connection.close();
    await fixture.relay.stop();
  }
});

for (const field of [
  "executionUID",
  "callerSecuritySession",
  "attributes",
  "consoleUID",
  "cgUID",
] as const) {
  test(`helper refuses invocation/runtime ${field} mismatch`, async () => {
    const fixture = await setup({ account: "screen-trial-uid-501" });
    const context = fixture.invocation.context;
    if (!context) throw new NativeRelayFailure("missing fixture context");
    const original = context[field];
    if (original === undefined) throw new NativeRelayFailure("missing execution UID");
    context[field] = field === "attributes" ? original + 0x40000000 : original + 1;
    if (field === "consoleUID") {
      context.cgUID = context.consoleUID;
      fixture.invocation.account = `screen-trial-uid-${context.consoleUID}`;
      fixture.policy.account = fixture.invocation.account;
      fixture.helperPolicy.targetConsoleUID = context.consoleUID;
    }
    const native = await fixture.requester(true, 0);
    try {
      const result = await native.result;
      expect(result.exit).toBe(1);
      expect(result.stdout).toBe("");
      expect(result.stderr).toBe("APPROVAL_HELPER_FAILED\n");
    } finally {
      await native.stop();
      await fixture.relay.stop();
    }
  });
}
