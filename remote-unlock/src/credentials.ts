import { stat } from "node:fs/promises";
import { importJWK } from "jose";
import { z } from "zod";
import { ActorIdSchema, PublicJwkSchema } from "./protocol";
import { ConfigurationError } from "./registry";

export const PrivateCredentialsSchema = z.strictObject({
  actor: ActorIdSchema,
  privateKey: z.strictObject({
    kty: z.literal("EC"),
    crv: z.literal("P-256"),
    x: z.string(),
    y: z.string(),
    d: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
  }),
});

export async function readCredentials(path: string) {
  const info = await stat(path);
  if (!info.isFile() || (info.mode & 0o077) !== 0) {
    throw new ConfigurationError("invalid_private_key");
  }
  const credential = PrivateCredentialsSchema.parse(await Bun.file(path).json());
  const { kty, crv, x, y, d } = credential.privateKey;
  PublicJwkSchema.parse({ kty, crv, x, y });
  if (Buffer.from(d, "base64url").toString("base64url") !== d) {
    throw new ConfigurationError("invalid_private_key");
  }
  const key = await importJWK(credential.privateKey, "ES256");
  if (key instanceof Uint8Array || key.type !== "private") {
    throw new ConfigurationError("invalid_private_key");
  }
  return { actor: credential.actor, key };
}
