import { decodeProtectedHeader } from "jose";
import {
  ActorIdSchema,
  DecisionSchema,
  newNonce,
  PendingApproval,
  RequestSchema,
  requestHash,
  signMessage,
  verifyMessage,
} from "./protocol";
import type { ActorId, ApprovalRequest, Decision } from "./protocol";
import { ConnectionError } from "./connection";
import type { Connection } from "./connection";
import { allows } from "./registry";
import type { Registry } from "./registry";
import { RelayError } from "./wire";

export interface ApprovalContext {
  readonly connection: Connection;
  readonly registry: Registry;
  readonly actor: ActorId;
  readonly key: CryptoKey;
  readonly now: () => number;
}

export async function requestApproval(
  context: ApprovalContext,
  target: {
    readonly approver: ActorId;
    readonly account: string;
  },
): Promise<Decision> {
  const device = context.registry.devices.get(target.approver);
  if (
    !device ||
    device.role !== "approver" ||
    !allows(context.registry, {
      requestor: context.actor,
      approver: target.approver,
      account: target.account,
    })
  )
    throw new RelayError("not_allowed");
  const issuedAt = context.now();
  const request = RequestSchema.parse({
    version: 1,
    kind: "request",
    issuer: context.actor,
    audience: target.approver,
    issuedAt,
    expiresAt: issuedAt + 30,
    requestId: crypto.randomUUID(),
    nonce: newNonce(),
    account: target.account,
    action: "screen-unlock",
  });
  const token = await signMessage(request, context.key);
  const pending = new PendingApproval(token, request);
  const cancel = () => pending.cancel();
  context.connection.signal.addEventListener("abort", cancel, { once: true });
  try {
    if (context.connection.signal.aborted) throw new ConnectionError("closed");
    context.connection.send(token);
    while (true) {
      const packet = await context.connection.next();
      switch (packet.kind) {
        case "submitted":
          if (packet.requestId !== request.requestId) {
            throw new ConnectionError("invalid_message");
          }
          break;
        case "signed":
          return await pending.consume(packet.token, device.key, context.now);
        case "error":
          throw new RelayError(packet.code);
        case "challenge":
        case "authenticated":
        case "delivered":
          throw new ConnectionError("invalid_message");
        default: {
          const unreachable: never = packet;
          return unreachable;
        }
      }
    }
  } finally {
    context.connection.signal.removeEventListener("abort", cancel);
    pending.cancel();
  }
}

export interface ReceivedRequest {
  readonly token: string;
  readonly request: ApprovalRequest;
}

export async function receiveRequest(context: ApprovalContext): Promise<ReceivedRequest> {
  const packet = await context.connection.next();
  if (packet.kind === "error") throw new RelayError(packet.code);
  if (packet.kind !== "signed") throw new ConnectionError("invalid_message");
  const claimedIssuer = ActorIdSchema.parse(decodeProtectedHeader(packet.token).kid);
  const device = context.registry.devices.get(claimedIssuer);
  if (!device || device.role !== "requestor") throw new RelayError("not_allowed");
  const request = await verifyMessage(packet.token, device.key, {
    issuer: device.id,
    audience: context.actor,
    now: context.now,
  });
  if (
    request.kind !== "request" ||
    !allows(context.registry, {
      requestor: device.id,
      approver: context.actor,
      account: request.account,
    })
  )
    throw new RelayError("not_allowed");
  return { token: packet.token, request };
}

export async function sendDecision(
  context: ApprovalContext,
  received: ReceivedRequest,
  decision: "approve" | "deny",
): Promise<void> {
  const issuedAt = context.now();
  if (issuedAt >= received.request.expiresAt) throw new RelayError("expired");
  const message = DecisionSchema.parse({
    version: 1,
    kind: "decision",
    issuer: context.actor,
    audience: received.request.issuer,
    issuedAt,
    expiresAt: Math.min(issuedAt + 30, received.request.expiresAt),
    requestId: received.request.requestId,
    requestHash: requestHash(received.token),
    decision,
    method: "manual",
  });
  context.connection.send(await signMessage(message, context.key));
  const packet = await context.connection.next();
  if (packet.kind === "error") throw new RelayError(packet.code);
  if (packet.kind !== "delivered" || packet.requestId !== message.requestId) {
    throw new ConnectionError("invalid_message");
  }
}
