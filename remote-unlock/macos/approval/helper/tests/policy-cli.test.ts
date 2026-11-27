import { expect, test } from "bun:test";
import { mkdtemp, mkdir, rm, writeFile, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { exportJWK, generateKeyPair } from "jose";
import { z } from "zod";

const cli = fileURLToPath(new URL("../../prepare-policy.ts", import.meta.url));
const publicKey = z.strictObject({
  kty: z.literal("EC"),
  crv: z.literal("P-256"),
  x: z.string(),
  y: z.string(),
});
const relay = z.strictObject({
  relayURL: z.string(),
  relayId: z.string(),
  requesterId: z.string(),
  approverId: z.string(),
  requesterPublicKey: publicKey,
  approverPublicKey: publicKey,
  account: z.string(),
});
const policy = z.strictObject({
  version: z.literal(2),
  mode: z.enum(["isolated-right-test", "screen-trial"]),
  executionUID: z.number().int(),
  targetConsoleUID: z.number().int().nullable(),
  relay,
  requesterKeyFile: z.string(),
  caCertificateFile: z.string(),
});

const cases = [
  { args: [], grant: "isolated-right-test", accepted: true, target: null },
  { args: ["isolated-right-test"], grant: "isolated-right-test", accepted: true, target: null },
  { args: ["screen-trial", "501"], grant: "screen-trial-uid-501", accepted: true, target: 501 },
  { args: ["screen-trial", "92"], grant: "screen-trial-uid-92", accepted: true, target: 92 },
  { args: ["screen-trial", "501"], grant: "isolated-right-test", accepted: false, target: null },
  ...["0", "0501", "+501", "1.5", "4294967295"].map((target) => ({
    args: ["screen-trial", target],
    grant: "screen-trial-uid-501",
    accepted: false,
    target: null,
  })),
  { args: ["screen-trial"], grant: "screen-trial-uid-501", accepted: false, target: null },
  {
    args: ["isolated-right-test", "501"],
    grant: "isolated-right-test",
    accepted: false,
    target: null,
  },
  { args: ["other"], grant: "isolated-right-test", accepted: false, target: null },
] as const;

for (const row of cases) {
  test(`prepare policy ${row.args.join(" ") || "legacy four args"} with grant ${row.grant}`, async () => {
    const directory = await mkdtemp(join(tmpdir(), "plf-policy-cli-"));
    const identity = join(directory, "identity");
    const output = join(directory, "output");
    const requester = await generateKeyPair("ES256", { extractable: true });
    const approver = await generateKeyPair("ES256");
    await mkdir(identity);
    const requesterPublicKey = await exportJWK(requester.publicKey);
    const approverPublicKey = await exportJWK(approver.publicKey);
    await writeFile(
      join(identity, "registry.json"),
      JSON.stringify({
        relayId: "relay",
        devices: [
          { id: "requester", role: "requestor", publicKey: requesterPublicKey },
          { id: "approver", role: "approver", publicKey: approverPublicKey },
        ],
        grants: [{ requestor: "requester", approver: "approver", account: row.grant }],
      }),
      { mode: 0o600 },
    );
    await writeFile(
      join(identity, "mac.private.json"),
      JSON.stringify({
        actor: "requester",
        privateKey: await exportJWK(requester.privateKey),
      }),
      { mode: 0o600 },
    );
    const child = Bun.spawn([process.execPath, cli, identity, output, "443", "92", ...row.args], {
      env: process.env,
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
    });
    try {
      const [exit, stdout] = await Promise.all([child.exited, new Response(child.stdout).text()]);
      if (row.accepted) {
        expect(exit).toBe(0);
        expect(stdout).toBe("NATIVE_POLICY_READY\n");
        const parsed = policy.parse(await Bun.file(join(output, "policy.json")).json());
        expect(parsed.executionUID).toBe(92);
        expect(parsed.targetConsoleUID).toBe(row.target);
        expect(parsed.mode).toBe(row.target === null ? "isolated-right-test" : "screen-trial");
        expect(parsed.relay.account).toBe(row.grant);
        const filename =
          row.target === null ? "requester.private.json" : "screen-requester.private.json";
        expect(parsed.requesterKeyFile).toBe(
          `/Library/Application Support/PLF02WHRemoteApproval/${filename}`,
        );
        expect((await readdir(output)).sort()).toEqual(["policy.json", filename].sort());
      } else {
        expect(exit).toBe(1);
        expect(await Bun.file(join(output, "policy.json")).exists()).toBe(false);
      }
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });
}
