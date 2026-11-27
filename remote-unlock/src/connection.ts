import { z } from "zod";
import { MessageSchema, signMessage } from "./protocol";
import type { ActorId } from "./protocol";
import { ConfigurationError } from "./registry";
import { RelayError, ServerPacketSchema } from "./wire";
import type { ServerPacket } from "./wire";

export class ConnectionError extends Error {
  constructor(readonly code: "closed" | "timeout" | "invalid_message" | "busy") {
    super(code);
    this.name = "ConnectionError";
  }
}

export class Connection {
  private readonly socket: WebSocket;
  private readonly lifetime = new AbortController();
  private readonly queue: ServerPacket[] = [];
  private failure: ConnectionError | undefined;
  private waiter:
    | {
        readonly resolve: (packet: ServerPacket) => void;
        readonly reject: (error: ConnectionError) => void;
        readonly timer: ReturnType<typeof setTimeout>;
      }
    | undefined;

  constructor(url: string) {
    const parsed = new URL(url);
    if (
      parsed.username ||
      parsed.password ||
      parsed.search ||
      parsed.hash ||
      parsed.pathname !== "/v1/relay" ||
      (parsed.protocol !== "wss:" &&
        !(parsed.protocol === "ws:" && ["127.0.0.1", "[::1]"].includes(parsed.hostname)))
    ) {
      throw new ConfigurationError("invalid_transport");
    }
    this.socket = new WebSocket(url);
    this.socket.addEventListener("message", (event) => {
      try {
        if (typeof event.data !== "string" || event.data.length > 17000) {
          this.fail(new ConnectionError("invalid_message"));
          return;
        }
        const packet = ServerPacketSchema.parse(JSON.parse(event.data));
        if (this.waiter) {
          const waiter = this.waiter;
          this.waiter = undefined;
          clearTimeout(waiter.timer);
          waiter.resolve(packet);
        } else if (this.queue.length < 16) {
          this.queue.push(packet);
        } else {
          this.fail(new ConnectionError("invalid_message"));
        }
      } catch (error) {
        if (error instanceof SyntaxError || error instanceof z.ZodError) {
          this.fail(new ConnectionError("invalid_message"));
        } else {
          throw error;
        }
      }
    });
    this.socket.addEventListener("close", () => this.fail(new ConnectionError("closed")));
    this.socket.addEventListener("error", () => this.fail(new ConnectionError("closed")));
  }

  next(timeoutMs = 65000): Promise<ServerPacket> {
    if (this.failure) return Promise.reject(this.failure);
    const queued = this.queue.shift();
    if (queued) return Promise.resolve(queued);
    if (this.waiter) return Promise.reject(new ConnectionError("busy"));
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => this.fail(new ConnectionError("timeout")), timeoutMs);
      this.waiter = { resolve, reject, timer };
    });
  }

  send(token: string): void {
    if (this.failure || this.socket.readyState !== WebSocket.OPEN) {
      throw new ConnectionError("closed");
    }
    this.socket.send(JSON.stringify({ kind: "signed", token }));
  }

  close(): void {
    this.fail(new ConnectionError("closed"));
  }

  get signal(): AbortSignal {
    return this.lifetime.signal;
  }

  private fail(error: ConnectionError): void {
    if (this.failure) return;
    this.failure = error;
    this.lifetime.abort(error);
    this.queue.length = 0;
    if (this.waiter) {
      clearTimeout(this.waiter.timer);
      this.waiter.reject(error);
      this.waiter = undefined;
    }
    this.socket.close();
  }
}

export interface ConnectionOptions {
  readonly url: string;
  readonly actor: ActorId;
  readonly relay: ActorId;
  readonly key: CryptoKey;
  readonly now?: () => number;
}

export async function connectPeer(options: ConnectionOptions): Promise<Connection> {
  const connection = new Connection(options.url);
  const now = options.now ?? (() => Math.floor(Date.now() / 1000));
  try {
    const challenge = await connection.next(10000);
    if (challenge.kind !== "challenge" || challenge.relayId !== options.relay) {
      throw new ConnectionError("invalid_message");
    }
    const issuedAt = now();
    const authentication = MessageSchema.parse({
      version: 1,
      kind: "authenticate",
      issuer: options.actor,
      audience: options.relay,
      issuedAt,
      expiresAt: Math.min(issuedAt + 10, challenge.expiresAt),
      nonce: challenge.nonce,
    });
    connection.send(await signMessage(authentication, options.key));
    const acknowledgement = await connection.next(10000);
    if (acknowledgement.kind === "error") throw new RelayError(acknowledgement.code);
    if (acknowledgement.kind !== "authenticated" || acknowledgement.actor !== options.actor)
      throw new ConnectionError("invalid_message");
    return connection;
  } catch (error) {
    connection.close();
    throw error;
  }
}
