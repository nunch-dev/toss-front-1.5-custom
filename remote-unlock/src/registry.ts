import { importJWK } from "jose";
import { z } from "zod";
import { ActorIdSchema, PublicJwkSchema } from "./protocol";
import type { ActorId } from "./protocol";

export const AccountSchema = z.string().regex(/^[A-Za-z0-9_.-]{1,64}$/);
export const RegistrySchema = z
  .strictObject({
    relayId: ActorIdSchema,
    devices: z
      .array(
        z
          .strictObject({
            id: ActorIdSchema,
            role: z.enum(["requestor", "approver"]),
            publicKey: PublicJwkSchema,
          })
          .readonly(),
      )
      .min(2)
      .max(128),
    grants: z
      .array(
        z
          .strictObject({
            requestor: ActorIdSchema,
            approver: ActorIdSchema,
            account: AccountSchema,
          })
          .readonly(),
      )
      .min(1)
      .max(1024),
  })
  .readonly();

export class ConfigurationError extends Error {
  constructor(
    readonly code:
      | "invalid_registry"
      | "invalid_public_key"
      | "invalid_private_key"
      | "invalid_transport",
  ) {
    super(code);
    this.name = "ConfigurationError";
  }
}

export interface RegisteredDevice {
  readonly id: ActorId;
  readonly role: "requestor" | "approver";
  readonly key: CryptoKey;
}

export interface Registry {
  readonly relayId: ActorId;
  readonly devices: ReadonlyMap<ActorId, RegisteredDevice>;
  readonly grants: readonly {
    readonly requestor: ActorId;
    readonly approver: ActorId;
    readonly account: string;
  }[];
}

export async function loadRegistry(input: unknown): Promise<Registry> {
  const parsed = RegistrySchema.parse(input);
  const devices = new Map<ActorId, RegisteredDevice>();
  for (const device of parsed.devices) {
    if (device.id === parsed.relayId || devices.has(device.id)) {
      throw new ConfigurationError("invalid_registry");
    }
    const key = await importJWK(device.publicKey, "ES256");
    if (key instanceof Uint8Array) throw new ConfigurationError("invalid_public_key");
    devices.set(device.id, { id: device.id, role: device.role, key });
  }
  for (const grant of parsed.grants) {
    if (
      devices.get(grant.requestor)?.role !== "requestor" ||
      devices.get(grant.approver)?.role !== "approver"
    ) {
      throw new ConfigurationError("invalid_registry");
    }
  }
  return { relayId: parsed.relayId, devices, grants: parsed.grants };
}

export function allows(
  registry: Registry,
  route: {
    readonly requestor: ActorId;
    readonly approver: ActorId;
    readonly account: string;
  },
): boolean {
  return registry.grants.some(
    (grant) =>
      grant.requestor === route.requestor &&
      grant.approver === route.approver &&
      grant.account === route.account,
  );
}
