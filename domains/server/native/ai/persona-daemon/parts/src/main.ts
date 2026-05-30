// Composition root for persona-daemon.
//
// All wiring lives here so the rest of the code stays pure / port-driven.
// Config flows in via env vars (Charter: environment-agnostic late binding —
// nothing in core or adapters reads process.env).

import { PersonaManifestSchema } from "./core/types.ts";
import { systemClock } from "./adapters/clock-system.ts";
import { createStderrLogger } from "./adapters/log-stderr.ts";
import { createChatHttp } from "./adapters/llm-llamacpp.ts";
import {
  createConversationStoreSqlite,
  openDatabase,
} from "./adapters/store-sqlite.ts";
import { createOrchestrator } from "./core/chat.ts";
import { createOpenAiShell } from "./shells/http-openai.ts";
import { createInternalShell } from "./shells/http-internal.ts";

interface RuntimeConfig {
  bindAddr: string;
  port: number;
  dbPath: string;
  manifestPath: string;
  gpuUrl: string;
  cpuUrl: string;
  embedUrl: string;
  maxRecent: number;
  keepRecent: number;
  logLevel: "debug" | "info" | "warn" | "error";
}

function readConfig(): RuntimeConfig {
  const need = (k: string): string => {
    const v = Deno.env.get(k);
    if (!v) throw new Error(`required env var missing: ${k}`);
    return v;
  };
  const num = (k: string): number => {
    const n = Number.parseInt(Deno.env.get(k) ?? "", 10);
    if (Number.isNaN(n)) throw new Error(`env ${k} must be an integer`);
    return n;
  };
  const lvl = Deno.env.get("PERSONA_DAEMON_LOG_LEVEL") ?? "info";
  if (!["debug", "info", "warn", "error"].includes(lvl)) {
    throw new Error(`invalid log level: ${lvl}`);
  }
  return {
    bindAddr: need("PERSONA_DAEMON_BIND_ADDR"),
    port: num("PERSONA_DAEMON_PORT"),
    dbPath: need("PERSONA_DAEMON_DB_PATH"),
    manifestPath: need("PERSONA_DAEMON_MANIFEST"),
    gpuUrl: need("PERSONA_DAEMON_GPU_URL"),
    cpuUrl: need("PERSONA_DAEMON_CPU_URL"),
    embedUrl: need("PERSONA_DAEMON_EMBED_URL"),
    maxRecent: num("PERSONA_DAEMON_MAX_RECENT"),
    keepRecent: num("PERSONA_DAEMON_KEEP_RECENT"),
    logLevel: lvl as RuntimeConfig["logLevel"],
  };
}

async function loadManifest(path: string) {
  const text = await Deno.readTextFile(path);
  const raw = JSON.parse(text);
  const parsed = PersonaManifestSchema.safeParse(raw);
  if (!parsed.success) {
    throw new Error(
      `persona manifest at ${path} failed schema validation: ${
        JSON.stringify(parsed.error.issues.slice(0, 5))
      }`,
    );
  }
  return parsed.data;
}

async function main() {
  const cfg = readConfig();
  const log = createStderrLogger(cfg.logLevel);

  log.info("persona-daemon.start", {
    bind: `${cfg.bindAddr}:${cfg.port}`,
    dbPath: cfg.dbPath,
    manifestPath: cfg.manifestPath,
  });

  const personas = await loadManifest(cfg.manifestPath);
  log.info("manifest.loaded", {
    count: Object.keys(personas).length,
    names: Object.keys(personas),
  });

  const db = openDatabase(cfg.dbPath);
  const store = createConversationStoreSqlite({ db, clock: systemClock });

  const chat = createChatHttp({
    gpuUrl: cfg.gpuUrl,
    cpuUrl: cfg.cpuUrl,
  });

  const orchestrate = createOrchestrator({
    personas,
    chat,
    store,
    log,
    maxRecentTurns: cfg.maxRecent,
    keepRecentTurns: cfg.keepRecent,
  });

  const startedAt = Date.now();
  const openai = createOpenAiShell({ orchestrate, personas, log });
  const internal = createInternalShell({ store, personas, startedAt });

  const handler = async (req: Request): Promise<Response> => {
    const r = (await internal(req)) ?? (await openai(req));
    if (r) return r;
    return new Response(JSON.stringify({
      error: { code: "INVALID_REQUEST", message: "route not found" },
    }), { status: 404, headers: { "content-type": "application/json" } });
  };

  Deno.serve({ hostname: cfg.bindAddr, port: cfg.port, onListen: ({ hostname, port }) => {
    log.info("persona-daemon.listening", { hostname, port });
  }}, handler);
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(JSON.stringify({
      ts: new Date().toISOString(),
      level: "error",
      msg: "fatal",
      err: e instanceof Error ? { message: e.message, stack: e.stack } : String(e),
    }));
    Deno.exit(1);
  });
}
