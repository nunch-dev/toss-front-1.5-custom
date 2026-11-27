import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { exportJWK, generateKeyPair } from "jose";
import { z } from "zod";
import { AccountSchema, RegistrySchema } from "./registry";
import { PublicJwkSchema } from "./protocol";

const directory = resolve(z.string().min(1).parse(process.argv[2]));
const account = AccountSchema.parse(process.argv[3] ?? "local-session");
await mkdir(directory, { mode: 0o700 });
const requestor = await generateKeyPair("ES256", { extractable: true });
const approver = await generateKeyPair("ES256", { extractable: true });
const registry = RegistrySchema.parse({
  relayId: "relay-demo",
  devices: [
    {
      id: "mac-demo",
      role: "requestor",
      publicKey: PublicJwkSchema.parse(await exportJWK(requestor.publicKey)),
    },
    {
      id: "device-demo",
      role: "approver",
      publicKey: PublicJwkSchema.parse(await exportJWK(approver.publicKey)),
    },
  ],
  grants: [{ requestor: "mac-demo", approver: "device-demo", account }],
});
await writeFile(resolve(directory, "registry.json"), JSON.stringify(registry, null, 2), {
  flag: "wx",
  mode: 0o600,
});
await writeFile(
  resolve(directory, "mac.private.json"),
  JSON.stringify({
    actor: "mac-demo",
    privateKey: await exportJWK(requestor.privateKey),
  }),
  { flag: "wx", mode: 0o600 },
);
await writeFile(
  resolve(directory, "approver.private.json"),
  JSON.stringify({
    actor: "device-demo",
    privateKey: await exportJWK(approver.privateKey),
  }),
  { flag: "wx", mode: 0o600 },
);
console.info(`PROVISIONED ${directory}`);
