import { z } from "zod";
import { loadRegistry } from "./registry";
import { startRelay } from "./relay";

const EnvironmentSchema = z.object({
  REGISTRY_FILE: z.string().min(1),
  HOST: z.string().default("127.0.0.1"),
  PORT: z.coerce.number().int().min(1).max(65535).default(8787),
  TLS_CERT_FILE: z.string().min(1).optional(),
  TLS_KEY_FILE: z.string().min(1).optional(),
});
const config = EnvironmentSchema.parse(process.env);
if (Boolean(config.TLS_CERT_FILE) !== Boolean(config.TLS_KEY_FILE)) {
  throw new TypeError("TLS_CERT_FILE and TLS_KEY_FILE must be supplied together");
}
const registry = await loadRegistry(await Bun.file(config.REGISTRY_FILE).json());
const relay = startRelay({
  registry,
  hostname: config.HOST,
  port: config.PORT,
  ...(config.TLS_CERT_FILE && config.TLS_KEY_FILE
    ? {
        tls: { cert: config.TLS_CERT_FILE, key: config.TLS_KEY_FILE },
      }
    : {}),
});
console.info(`RELAY_READY port=${relay.port} protocol=1`);
process.once("SIGINT", () => {
  void relay.stop();
});
process.once("SIGTERM", () => {
  void relay.stop();
});
