import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { exportJWK, generateKeyPair } from "jose";
import { z } from "zod";
import { connectPeer } from "../../../../src/connection";
import { ActorIdSchema, newNonce } from "../../../../src/protocol";
import { loadRegistry } from "../../../../src/registry";
import { startRelay } from "../../../../src/relay";

const output = fileURLToPath(
  new URL("../../../../../private/macos-approval-20261120/", import.meta.url),
);
const tlsDirectory = z.string().min(1).parse(process.env["NATIVE_TLS_DIR"]);
const fields = {
  version: z.literal(2),
  mode: z.enum(["isolated-right-test", "screen-trial"]),
  account: z.string(),
  context: z.unknown(),
  generation: z.uuid(),
  requestId: z.uuid(),
  requestHash: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
  expiresAt: z.number().int(),
};
export const recordsSchema = z.array(
  z.discriminatedUnion("kind", [
    z.strictObject({ ...fields, kind: z.literal("bound") }),
    z.strictObject({ ...fields, kind: z.literal("result"), decision: z.enum(["approve", "deny"]) }),
  ]),
);

export class NativeRelayFailure extends Error {
  constructor(readonly diagnostic: string) {
    super("native_relay_failed");
    this.name = "NativeRelayFailure";
  }
}

export async function setup(
  options: {
    readonly certificate?: string;
    readonly account?: string;
    readonly grant?: string;
  } = {},
) {
  const account = options.account ?? "isolated-right-test";
  const mode =
    account === "isolated-right-test"
      ? ("isolated-right-test" as const)
      : ("screen-trial" as const);
  const macKeys = await generateKeyPair("ES256", { extractable: true });
  const deviceKeys = await generateKeyPair("ES256");
  const macId = ActorIdSchema.parse("swift-mac");
  const deviceId = ActorIdSchema.parse("swift-approver");
  const macPublic = await exportJWK(macKeys.publicKey);
  const devicePublic = await exportJWK(deviceKeys.publicKey);
  const registry = await loadRegistry({
    relayId: "swift-relay",
    devices: [
      { id: macId, role: "requestor", publicKey: macPublic },
      { id: deviceId, role: "approver", publicKey: devicePublic },
    ],
    grants: [{ requestor: macId, approver: deviceId, account: options.grant ?? account }],
  });
  const certificate = options.certificate ?? "server";
  const relay = startRelay({
    registry,
    hostname: "127.0.0.1",
    port: 0,
    tls: { cert: `${tlsDirectory}/${certificate}.pem`, key: `${tlsDirectory}/${certificate}.key` },
  });
  const now = () => Math.floor(Date.now() / 1000);
  const url = `wss://127.0.0.1:${relay.port}/v1/relay`;
  const issuedAt = now();
  const invocation = {
    version: 2,
    mode,
    account,
    context:
      mode === "screen-trial"
        ? {
            executionUID: process.getuid?.(),
            callerSecuritySession: 100023,
            attributes: 8240,
            consoleUID: 501,
            cgUID: 501,
            onConsole: true,
            loginDone: true,
          }
        : null,
    generation: crypto.randomUUID(),
    requestId: crypto.randomUUID(),
    nonce: newNonce(),
    issuedAt,
    expiresAt: issuedAt + 30,
  };
  const policy = {
    relayURL: url,
    relayId: registry.relayId,
    requesterId: macId,
    approverId: deviceId,
    requesterPublicKey: macPublic,
    approverPublicKey: devicePublic,
    account,
  };
  const helperPolicy = {
    version: 2,
    mode,
    executionUID: process.getuid?.(),
    targetConsoleUID: mode === "screen-trial" ? 501 : null,
    relay: policy,
    requesterKeyFile:
      "/Library/Application Support/PLF02WHRemoteApproval/" +
      (mode === "screen-trial" ? "screen-requester.private.json" : "requester.private.json"),
    caCertificateFile:
      "/Library/Security/SecurityAgentPlugins/PlfRemoteApproval.bundle/Contents/Resources/relay-ca.der",
  };
  return {
    relay,
    invocation,
    policy,
    helperPolicy,
    async device() {
      const connection = await connectPeer({
        url,
        actor: deviceId,
        relay: registry.relayId,
        key: deviceKeys.privateKey,
        now,
      });
      return { connection, registry, actor: deviceId, key: deviceKeys.privateKey, now };
    },
    async requester(trust = true, helperChangeAt?: number) {
      const certificateBytes = await Bun.file(`${tlsDirectory}/ca.der`).arrayBuffer();
      const privateKey = await exportJWK(macKeys.privateKey);
      const directory = await mkdtemp(join(tmpdir(), "plf-helper-relay-"));
      await writeFile(join(directory, "policy.json"), JSON.stringify(helperPolicy), {
        mode: 0o600,
      });
      await writeFile(join(directory, "requester.private.json"), JSON.stringify(privateKey), {
        mode: 0o600,
      });
      await writeFile(join(directory, "relay-ca.der"), Buffer.from(certificateBytes), {
        mode: 0o600,
      });
      const child = Bun.spawn(
        helperChangeAt === undefined
          ? [join(output, "requestor-conformance")]
          : [
              join(output, "helper-runtime-launcher"),
              join(output, "helper-runtime-conformance"),
              directory,
              String(helperChangeAt),
            ],
        {
          env: process.env,
          stdin: "pipe",
          stdout: "pipe",
          stderr: "pipe",
          timeout: 8000,
          killSignal: "SIGKILL",
        },
      );
      const result = Promise.all([
        new Response(child.stdout).text(),
        new Response(child.stderr).text(),
        child.exited,
      ]).then(([stdout, stderr, exit]) => ({ stdout, stderr, exit }));
      await child.stdin.write(
        JSON.stringify(
          helperChangeAt === undefined
            ? {
                policy,
                privateKey,
                invocation,
                caCertificateDER: trust ? Buffer.from(certificateBytes).toString("base64") : null,
              }
            : invocation,
        ) + "\n",
      );
      return {
        child,
        result,
        directory,
        async stop() {
          if (child.exitCode === null) child.kill();
          await child.exited;
          await child.stdin.end();
          await rm(directory, { recursive: true, force: true });
        },
      };
    },
  };
}
