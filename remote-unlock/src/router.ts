import { decodeJwt, decodeProtectedHeader } from "jose";
import { ActorIdSchema, requestHash, verifyMessage } from "./protocol";
import type { ActorId, ApprovalRequest, RequestId } from "./protocol";
import { allows } from "./registry";
import type { Registry } from "./registry";
import { RelayError } from "./wire";
import type { ServerPacket } from "./wire";

export interface Peer {
  readonly nonce: string;
  readonly expiresAt: number;
  actor: ActorId | undefined;
  closed: boolean;
  send(packet: ServerPacket): void;
}

interface Pending {
  readonly request: ApprovalRequest;
  readonly hash: string;
  readonly sender: Peer;
  readonly recipient: Peer;
}

export class Router {
  private readonly peers = new Map<ActorId, Peer>();
  private readonly pending = new Map<RequestId, Pending>();
  private readonly seen = new Map<RequestId, number>();

  constructor(
    readonly registry: Registry,
    private readonly now: () => number,
  ) {}

  async receive(peer: Peer, token: string): Promise<void> {
    this.expire();
    const claimedActor = ActorIdSchema.parse(decodeProtectedHeader(token).kid);
    const device = this.registry.devices.get(claimedActor);
    if (!device || (peer.actor !== undefined && peer.actor !== device.id)) {
      throw new RelayError("not_allowed");
    }
    const claimedAudience = ActorIdSchema.parse(decodeJwt(token)["audience"]);
    const message = await verifyMessage(token, device.key, {
      issuer: device.id,
      audience: claimedAudience,
      now: this.now,
    });
    if (peer.closed) throw new RelayError("cancelled");
    if (peer.actor === undefined) {
      if (
        message.kind !== "authenticate" ||
        message.audience !== this.registry.relayId ||
        message.nonce !== peer.nonce ||
        this.now() >= peer.expiresAt
      ) {
        throw new RelayError("not_allowed");
      }
      if (this.peers.has(device.id)) throw new RelayError("busy");
      peer.actor = device.id;
      this.peers.set(device.id, peer);
      peer.send({ kind: "authenticated", actor: device.id });
      return;
    }
    switch (message.kind) {
      case "authenticate":
        throw new RelayError("not_allowed");
      case "request": {
        if (
          device.role !== "requestor" ||
          !allows(this.registry, {
            requestor: device.id,
            approver: message.audience,
            account: message.account,
          })
        )
          throw new RelayError("not_allowed");
        if (this.seen.has(message.requestId)) throw new RelayError("duplicate_request");
        if (this.seen.size >= 4096) throw new RelayError("busy");
        if (
          [...this.pending.values()].some(
            (item) => item.sender === peer || item.recipient.actor === message.audience,
          )
        )
          throw new RelayError("busy");
        const recipient = this.peers.get(message.audience);
        if (!recipient || recipient.closed) throw new RelayError("peer_offline");
        this.pending.set(message.requestId, {
          request: message,
          hash: requestHash(token),
          sender: peer,
          recipient,
        });
        this.seen.set(message.requestId, message.expiresAt);
        recipient.send({ kind: "signed", token });
        peer.send({ kind: "submitted", requestId: message.requestId });
        return;
      }
      case "decision": {
        const pending = this.pending.get(message.requestId);
        if (!pending) throw new RelayError("no_pending_request");
        if (
          device.role !== "approver" ||
          pending.recipient !== peer ||
          pending.sender.actor !== message.audience ||
          pending.hash !== message.requestHash ||
          message.expiresAt > pending.request.expiresAt
        ) {
          throw new RelayError("not_allowed");
        }
        if (this.now() >= pending.request.expiresAt || pending.sender.closed) {
          this.pending.delete(message.requestId);
          throw new RelayError("expired");
        }
        this.pending.delete(message.requestId);
        pending.sender.send({ kind: "signed", token });
        peer.send({ kind: "delivered", requestId: message.requestId });
        return;
      }
      default: {
        const unreachable: never = message;
        return unreachable;
      }
    }
  }

  disconnect(peer: Peer): void {
    peer.closed = true;
    if (peer.actor !== undefined && this.peers.get(peer.actor) === peer) {
      this.peers.delete(peer.actor);
    }
    for (const [id, pending] of this.pending) {
      if (pending.sender === peer || pending.recipient === peer) {
        this.pending.delete(id);
        const remaining = pending.sender === peer ? pending.recipient : pending.sender;
        if (!remaining.closed) remaining.send({ kind: "error", code: "cancelled" });
      }
    }
  }

  expire(): void {
    const now = this.now();
    for (const [id, pending] of this.pending) {
      if (now >= pending.request.expiresAt) {
        this.pending.delete(id);
        pending.sender.send({ kind: "error", code: "expired" });
        pending.recipient.send({ kind: "error", code: "expired" });
      }
    }
    for (const [id, expiresAt] of this.seen) {
      if (now >= expiresAt) this.seen.delete(id);
    }
  }
}
