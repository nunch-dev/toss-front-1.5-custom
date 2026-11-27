import { z } from "zod";
import { ActorIdSchema, RequestIdSchema } from "./protocol";

export const SignedPacketSchema = z
  .strictObject({
    kind: z.literal("signed"),
    token: z.string().min(1).max(16384),
  })
  .readonly();

export const ServerPacketSchema = z
  .discriminatedUnion("kind", [
    z.strictObject({
      kind: z.literal("challenge"),
      relayId: ActorIdSchema,
      nonce: z.string(),
      expiresAt: z.number().int(),
    }),
    z.strictObject({ kind: z.literal("authenticated"), actor: ActorIdSchema }),
    SignedPacketSchema,
    z.strictObject({ kind: z.literal("submitted"), requestId: RequestIdSchema }),
    z.strictObject({ kind: z.literal("delivered"), requestId: RequestIdSchema }),
    z.strictObject({
      kind: z.literal("error"),
      code: z.enum([
        "invalid_message",
        "not_allowed",
        "peer_offline",
        "busy",
        "no_pending_request",
        "expired",
        "cancelled",
        "duplicate_request",
      ]),
    }),
  ])
  .readonly();

export type ServerPacket = z.infer<typeof ServerPacketSchema>;
export type RelayErrorCode = Extract<ServerPacket, { kind: "error" }>["code"];
export class RelayError extends Error {
  constructor(readonly code: RelayErrorCode) {
    super(code);
    this.name = "RelayError";
  }
}
