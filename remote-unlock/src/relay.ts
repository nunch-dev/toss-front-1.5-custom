import { errors } from "jose";
import { z } from "zod";
import { newNonce, ProtocolError } from "./protocol";
import { ConfigurationError } from "./registry";
import type { Registry } from "./registry";
import { Router } from "./router";
import type { Peer } from "./router";
import { RelayError, SignedPacketSchema } from "./wire";

// These fields track the live, mutable socket lifecycle.
interface SocketState {
  peer: Peer | undefined;
  busy: boolean;
  timer: ReturnType<typeof setTimeout> | undefined;
}

export interface RelayOptions {
  readonly registry: Registry;
  readonly hostname: string;
  readonly port: number;
  readonly now?: () => number;
  readonly tls?: { readonly cert: string; readonly key: string };
}

export function startRelay(options: RelayOptions) {
  if (!options.tls && !["127.0.0.1", "::1"].includes(options.hostname)) {
    throw new ConfigurationError("invalid_transport");
  }
  const now = options.now ?? (() => Math.floor(Date.now() / 1000));
  const router = new Router(options.registry, now);
  const connections = new Set<Peer>();
  const sweep = setInterval(() => router.expire(), 1000);
  sweep.unref();
  const server = Bun.serve<SocketState>({
    hostname: options.hostname,
    port: options.port,
    ...(options.tls
      ? {
          tls: {
            cert: Bun.file(options.tls.cert),
            key: Bun.file(options.tls.key),
          },
        }
      : {}),
    fetch(request, listener) {
      const path = new URL(request.url).pathname;
      if (request.method === "GET" && path === "/health") {
        return Response.json({ status: "ready", protocolVersion: 1 });
      }
      if (request.method !== "GET" || path !== "/v1/relay") {
        return new Response("Not found", { status: 404 });
      }
      if (request.headers.has("origin")) {
        return new Response("Native clients only", { status: 403 });
      }
      if (connections.size >= 128) return new Response("Busy", { status: 503 });
      if (
        listener.upgrade(request, {
          data: { peer: undefined, busy: false, timer: undefined },
        })
      )
        return undefined;
      return new Response("WebSocket upgrade required", { status: 426 });
    },
    websocket: {
      maxPayloadLength: 17000,
      idleTimeout: 120,
      backpressureLimit: 65536,
      closeOnBackpressureLimit: true,
      open(socket) {
        const peer: Peer = {
          nonce: newNonce(),
          expiresAt: now() + 10,
          actor: undefined,
          closed: false,
          send(packet) {
            if (!peer.closed) socket.send(JSON.stringify(packet));
          },
        };
        socket.data.peer = peer;
        if (connections.size >= 128) {
          socket.close(1013, "Busy");
          return;
        }
        connections.add(peer);
        socket.data.timer = setTimeout(() => {
          if (peer.actor === undefined) socket.close(1008, "Authentication timed out");
        }, 10000);
        socket.data.timer.unref();
        peer.send({
          kind: "challenge",
          relayId: options.registry.relayId,
          nonce: peer.nonce,
          expiresAt: peer.expiresAt,
        });
      },
      async message(socket, raw) {
        const peer = socket.data.peer;
        if (!peer || peer.closed) return;
        if (socket.data.busy) {
          socket.close(1008, "Wait for acknowledgement");
          return;
        }
        socket.data.busy = true;
        try {
          if (typeof raw !== "string") throw new RelayError("invalid_message");
          const packet = SignedPacketSchema.parse(JSON.parse(raw));
          await router.receive(peer, packet.token);
          if (peer.actor !== undefined && socket.data.timer !== undefined) {
            clearTimeout(socket.data.timer);
            socket.data.timer = undefined;
          }
        } catch (error) {
          if (error instanceof RelayError) {
            peer.send({ kind: "error", code: error.code });
          } else if (
            error instanceof ProtocolError ||
            error instanceof z.ZodError ||
            error instanceof errors.JOSEError ||
            error instanceof SyntaxError
          ) {
            peer.send({ kind: "error", code: "invalid_message" });
          } else {
            socket.close(1011, "Internal error");
            throw error;
          }
          if (peer.actor === undefined) socket.close(1008, "Authentication rejected");
        } finally {
          socket.data.busy = false;
        }
      },
      close(socket) {
        if (socket.data.timer !== undefined) clearTimeout(socket.data.timer);
        if (socket.data.peer) {
          router.disconnect(socket.data.peer);
          connections.delete(socket.data.peer);
        }
      },
    },
  });
  return {
    port: server.port,
    async stop() {
      clearInterval(sweep);
      for (const peer of connections) router.disconnect(peer);
      await server.stop(true);
    },
  };
}
