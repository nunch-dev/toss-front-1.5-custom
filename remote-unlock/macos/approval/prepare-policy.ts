import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { z } from "zod";
import { PrivateCredentialsSchema } from "../../src/credentials";
import { ConfigurationError, RegistrySchema } from "../../src/registry";

const positional = [
  z.string().min(1),
  z.string().min(1),
  z.coerce.number().int().min(1).max(65535),
  z.coerce.number().int().min(1).max(4294967294),
] as const;
const [
  identityDirectory,
  outputDirectory,
  port,
  executionUID,
  mode = "isolated-right-test",
  targetConsoleUID = null,
] = z
  .union([
    z.tuple(positional),
    z.tuple([...positional, z.literal("isolated-right-test")]),
    z.tuple([
      ...positional,
      z.literal("screen-trial"),
      z
        .string()
        .regex(/^[1-9][0-9]*$/)
        .transform(Number)
        .pipe(z.number().int().max(4294967294)),
    ]),
  ])
  .parse(process.argv.slice(2));
const [account, keyFilename] = (
  {
    "isolated-right-test": ["isolated-right-test", "requester.private.json"],
    "screen-trial": [`screen-trial-uid-${targetConsoleUID}`, "screen-requester.private.json"],
  } as const
)[mode];
const registry = RegistrySchema.parse(
  await Bun.file(resolve(identityDirectory, "registry.json")).json(),
);
const credential = PrivateCredentialsSchema.parse(
  await Bun.file(resolve(identityDirectory, "mac.private.json")).json(),
);
const requestor = registry.devices.find(
  (device) => device.id === credential.actor && device.role === "requestor",
);
const approver = registry.devices.find((device) => device.role === "approver");
if (
  !requestor ||
  !approver ||
  requestor.publicKey.x !== credential.privateKey.x ||
  requestor.publicKey.y !== credential.privateKey.y ||
  !registry.grants.some(
    (grant) =>
      grant.requestor === requestor.id &&
      grant.approver === approver.id &&
      grant.account === account,
  )
) {
  throw new ConfigurationError("invalid_registry");
}
const policy = {
  version: 2,
  mode,
  executionUID,
  targetConsoleUID,
  relay: {
    relayURL: `wss://127.0.0.1:${port}/v1/relay`,
    relayId: registry.relayId,
    requesterId: requestor.id,
    approverId: approver.id,
    requesterPublicKey: requestor.publicKey,
    approverPublicKey: approver.publicKey,
    account,
  },
  requesterKeyFile: `/Library/Application Support/PLF02WHRemoteApproval/${keyFilename}`,
  caCertificateFile:
    "/Library/Security/SecurityAgentPlugins/PlfRemoteApproval.bundle/Contents/Resources/relay-ca.der",
};
await mkdir(outputDirectory, { mode: 0o700 });
await writeFile(resolve(outputDirectory, "policy.json"), JSON.stringify(policy, null, 2), {
  flag: "wx",
  mode: 0o600,
});
await writeFile(resolve(outputDirectory, keyFilename), JSON.stringify(credential.privateKey), {
  flag: "wx",
  mode: 0o600,
});
console.info("NATIVE_POLICY_READY");
