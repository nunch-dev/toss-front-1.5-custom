import { createInterface } from "node:readline/promises";
import { stdin, stdout } from "node:process";
import { z } from "zod";
import { ActorIdSchema } from "./protocol";
import { readCredentials } from "./credentials";
import { loadRegistry } from "./registry";
import { connectPeer } from "./connection";
import { receiveRequest, requestApproval, sendDecision } from "./approval";
import { RelayError } from "./wire";

const ConfigSchema = z.object({
  RELAY_URL: z.string().url(),
  REGISTRY_FILE: z.string().min(1),
  CREDENTIAL_FILE: z.string().min(1),
});
const config = ConfigSchema.parse(process.env);
const mode = z.enum(["request", "approve"]).parse(process.argv[2]);
const credential = await readCredentials(config.CREDENTIAL_FILE);
const registry = await loadRegistry(await Bun.file(config.REGISTRY_FILE).json());
const now = () => Math.floor(Date.now() / 1000);
const connection = await connectPeer({
  url: config.RELAY_URL,
  actor: credential.actor,
  relay: registry.relayId,
  key: credential.key,
  now,
});
const context = { connection, registry, actor: credential.actor, key: credential.key, now };
try {
  switch (mode) {
    case "request": {
      const approver = ActorIdSchema.parse(process.argv[3]);
      const account = z.string().min(1).parse(process.argv[4]);
      const result = await requestApproval(context, { approver, account });
      console.info(`DECISION=${result.decision} METHOD=${result.method}`);
      console.info("OS_UNLOCK=unavailable");
      break;
    }
    case "approve": {
      if (registry.devices.get(credential.actor)?.role !== "approver") {
        throw new RelayError("not_allowed");
      }
      console.info("APPROVER_READY");
      const received = await receiveRequest(context);
      console.info(`REQUEST actor=${received.request.issuer} account=${received.request.account}`);
      const prompt = createInterface({ input: stdin, output: stdout });
      try {
        const answer = await prompt.question("승인하려면 APPROVE, 거부하려면 DENY를 입력하세요: ", {
          signal: AbortSignal.timeout(Math.max(1, (received.request.expiresAt - now()) * 1000)),
        });
        const decision = z.enum(["APPROVE", "DENY"]).parse(answer.trim());
        await sendDecision(context, received, decision === "APPROVE" ? "approve" : "deny");
        console.info("DECISION_DELIVERED");
      } finally {
        prompt.close();
      }
      break;
    }
    default: {
      const unreachable: never = mode;
      throw unreachable;
    }
  }
} finally {
  connection.close();
}
