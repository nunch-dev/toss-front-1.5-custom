import { CompactSign, compactVerify, base64url, errors } from "jose";
import { createHash } from "node:crypto";
import { z } from "zod";

export const ActorIdSchema = z
  .string()
  .regex(/^[A-Za-z0-9_-]{1,64}$/)
  .brand<"ActorId">();
export const RequestIdSchema = z.uuid().brand<"RequestId">();
const Bytes32Schema = z.string().regex(/^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/);
export const PublicJwkSchema = z
  .strictObject({
    kty: z.literal("EC"),
    crv: z.literal("P-256"),
    x: Bytes32Schema,
    y: Bytes32Schema,
  })
  .readonly();

const common = {
  version: z.literal(1),
  issuer: ActorIdSchema,
  audience: ActorIdSchema,
  issuedAt: z.number().int().nonnegative(),
  expiresAt: z.number().int().nonnegative(),
};
const authenticate = z.strictObject({
  ...common,
  kind: z.literal("authenticate"),
  nonce: Bytes32Schema,
});
const requestShape = z.strictObject({
  ...common,
  kind: z.literal("request"),
  requestId: RequestIdSchema,
  nonce: Bytes32Schema,
  account: z.string().regex(/^[A-Za-z0-9_.-]{1,64}$/),
  action: z.literal("screen-unlock"),
});
const decision = z.strictObject({
  ...common,
  kind: z.literal("decision"),
  requestId: RequestIdSchema,
  requestHash: Bytes32Schema,
  decision: z.enum(["approve", "deny"]),
  method: z.literal("manual"),
});
export const RequestSchema = requestShape.readonly();
export const DecisionSchema = decision.readonly();
export const MessageSchema = z
  .discriminatedUnion("kind", [authenticate, requestShape, decision])
  .readonly();
export type ActorId = z.infer<typeof ActorIdSchema>;
export type RequestId = z.infer<typeof RequestIdSchema>;
export type PublicJwk = z.infer<typeof PublicJwkSchema>;
export type Message = z.infer<typeof MessageSchema>;
export type ApprovalRequest = z.infer<typeof RequestSchema>;
export type Decision = z.infer<typeof DecisionSchema>;

export type ProtocolErrorCode =
  | "invalid_token"
  | "invalid_header"
  | "invalid_signature"
  | "invalid_message"
  | "wrong_target"
  | "invalid_ttl"
  | "future_message"
  | "expired"
  | "cancelled"
  | "replayed"
  | "in_progress"
  | "request_mismatch";

export class ProtocolError extends Error {
  constructor(readonly code: ProtocolErrorCode) {
    super(code);
    this.name = "ProtocolError";
  }
}

const HeaderSchema = z.strictObject({
  alg: z.literal("ES256"),
  typ: z.literal("remote-unlock+jws"),
  kid: ActorIdSchema,
});
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });

export function newNonce(): string {
  return base64url.encode(crypto.getRandomValues(new Uint8Array(32)));
}

export function requestHash(jws: string): string {
  return createHash("sha256").update(jws, "utf8").digest("base64url");
}

function checkTtl(message: Message): void {
  const ttl = message.expiresAt - message.issuedAt;
  if (ttl <= 0 || ttl > 60) throw new ProtocolError("invalid_ttl");
}

export async function signMessage(message: Message, key: CryptoKey): Promise<string> {
  const parsed = MessageSchema.safeParse(message);
  if (!parsed.success) throw new ProtocolError("invalid_message");
  checkTtl(parsed.data);
  return new CompactSign(encoder.encode(JSON.stringify(parsed.data)))
    .setProtectedHeader({
      alg: "ES256",
      typ: "remote-unlock+jws",
      kid: parsed.data.issuer,
    })
    .sign(key);
}

export async function verifyMessage(
  token: string,
  key: CryptoKey,
  expected: {
    readonly issuer: ActorId;
    readonly audience: ActorId;
    readonly now: () => number;
  },
): Promise<Message> {
  if (token.length > 16 * 1024) throw new ProtocolError("invalid_token");
  let verified;
  try {
    verified = await compactVerify(token, key, { algorithms: ["ES256"] });
  } catch (error) {
    if (
      error instanceof errors.JOSEError ||
      error instanceof TypeError ||
      error instanceof DOMException
    ) {
      throw new ProtocolError("invalid_signature");
    }
    throw error;
  }
  const header = HeaderSchema.safeParse(verified.protectedHeader);
  if (!header.success || header.data.kid !== expected.issuer) {
    throw new ProtocolError("invalid_header");
  }
  let payload: unknown;
  try {
    payload = JSON.parse(decoder.decode(verified.payload));
  } catch (error) {
    if (error instanceof SyntaxError || error instanceof TypeError) {
      throw new ProtocolError("invalid_message");
    }
    throw error;
  }
  const parsed = MessageSchema.safeParse(payload);
  if (!parsed.success) throw new ProtocolError("invalid_message");
  const message = parsed.data;
  if (message.issuer !== expected.issuer || message.audience !== expected.audience) {
    throw new ProtocolError("wrong_target");
  }
  checkTtl(message);
  const now = expected.now();
  if (!Number.isFinite(now)) throw new ProtocolError("invalid_message");
  if (message.issuedAt > now + 5) throw new ProtocolError("future_message");
  if (now >= message.expiresAt) throw new ProtocolError("expired");
  return message;
}

export class PendingApproval {
  readonly #requestToken: string;
  readonly #request: ApprovalRequest;
  #state: "pending" | "cancelled" | "consumed" = "pending";
  #consuming = false;

  constructor(requestToken: string, request: ApprovalRequest) {
    const parsed = RequestSchema.safeParse(request);
    if (!parsed.success) throw new ProtocolError("invalid_message");
    checkTtl(parsed.data);
    this.#requestToken = requestToken;
    this.#request = parsed.data;
  }

  cancel(): void {
    if (this.#state === "pending") this.#state = "cancelled";
  }

  #checkPending(now: number): void {
    if (this.#state === "cancelled") throw new ProtocolError("cancelled");
    if (this.#state === "consumed") throw new ProtocolError("replayed");
    if (!Number.isFinite(now)) throw new ProtocolError("invalid_message");
    if (now >= this.#request.expiresAt) throw new ProtocolError("expired");
  }

  async consume(
    decisionToken: string,
    approverKey: CryptoKey,
    now: () => number,
  ): Promise<Decision> {
    this.#checkPending(now());
    if (this.#consuming) throw new ProtocolError("in_progress");
    this.#consuming = true;
    try {
      const message = await verifyMessage(decisionToken, approverKey, {
        issuer: this.#request.audience,
        audience: this.#request.issuer,
        now,
      });
      const parsed = DecisionSchema.safeParse(message);
      if (!parsed.success) throw new ProtocolError("request_mismatch");
      const response = parsed.data;
      if (
        response.requestId !== this.#request.requestId ||
        response.requestHash !== requestHash(this.#requestToken) ||
        response.expiresAt > this.#request.expiresAt
      ) {
        throw new ProtocolError("request_mismatch");
      }
      const completedAt = now();
      this.#checkPending(completedAt);
      if (completedAt >= response.expiresAt) throw new ProtocolError("expired");
      this.#state = "consumed";
      return response;
    } finally {
      this.#consuming = false;
    }
  }
}
