// HTTP shell over the engine core (hexagonal: a shell that translates inbound
// HTTP into core calls). Serves the interactive board and the intake/amend/
// rewind/profile-toggle endpoints, operating on the MarkdownItemStore + the
// ProfileCatalog + triage. Engine-only items — it never touches the live
// gauntlet hopper. All config late-bound from the environment.

import { createServer, IncomingMessage, ServerResponse } from "node:http";
import { Item } from "../contracts.js";
import { MarkdownItemStore } from "../stores/markdown-store.js";
import { ProfileCatalog } from "../profiles/catalog.js";
import { resolveLlm } from "../adapters/resolver.js";
import { triageSentence, makeTriagedItem, UNTRIAGED } from "../triage.js";
import { rewind } from "../runner.js";
import { LlmPort } from "../gates/llm-port.js";
import { renderGauntlet, renderHopperPage } from "./render.js";
import { readHopperCards, renderHopper } from "./hopper.js";

export interface HttpShellConfig {
  port: number;
  itemsDir: string;
  profilesDir: string;
  profileStatePath: string;
  triageProvider: string;
  clock: () => string;
  vaultDir?: string; // for the read-only /hopper route; optional
  triageLlm?: LlmPort; // test override; production resolves from triageProvider
}

export function configFromEnv(): HttpShellConfig {
  const home = process.env.HOME ?? "/tmp";
  return {
    port: Number(process.env.REFINERY_PORT || 8060),
    itemsDir: process.env.REFINERY_ITEMS_DIR || `${home}/.local/state/refinery/items`,
    profilesDir: process.env.REFINERY_PROFILES_DIR || "profiles",
    profileStatePath:
      process.env.REFINERY_PROFILE_STATE || `${home}/.local/state/refinery/profiles.json`,
    triageProvider: process.env.REFINERY_TRIAGE_PROVIDER || "claude-cli",
    vaultDir: process.env.REFINERY_VAULT_DIR,
    clock: () => new Date().toISOString(),
  };
}

function readBody(req: IncomingMessage): Promise<URLSearchParams> {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (c) => {
      data += c;
      if (data.length > 1_000_000) reject(new Error("body too large"));
    });
    req.on("end", () => resolve(new URLSearchParams(data)));
    req.on("error", reject);
  });
}

function slug(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40) || "item";
}

function redirect(res: ServerResponse): void {
  res.writeHead(303, { location: "/" });
  res.end();
}

export function createShell(cfg: HttpShellConfig) {
  const store = new MarkdownItemStore(cfg.itemsDir);
  const catalog = new ProfileCatalog({ dir: cfg.profilesDir, statePath: cfg.profileStatePath });

  async function intake(text: string): Promise<void> {
    const enabled = catalog.enabled();
    const options = enabled.map((p) => ({ genre: p.genre, label: p.label }));
    const llm = cfg.triageLlm ?? resolveLlm(cfg.triageProvider);
    const decision = await triageSentence(text, options, llm);
    const profile = catalog.get(decision.genre);
    const firstPhase = profile?.gates[0] ?? "triage";
    const id = `${slug(text)}-${Date.now()}`;
    await store.save(makeTriagedItem(id, text, decision, firstPhase, cfg.clock));
  }

  async function amend(id: string, note: string): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    const payload = (item.payload && typeof item.payload === "object" ? item.payload : {}) as Record<string, unknown>;
    const amendments = Array.isArray(payload.amendments) ? payload.amendments : [];
    const updated: Item = {
      ...item,
      phaseStatus: "pending", // re-run the parked gate with the amendment in context
      parkedReason: undefined,
      payload: { ...payload, amendments: [...amendments, note] },
      history: [...item.history, { phase: item.phase, status: "entered", at: cfg.clock(), note }],
    };
    await store.save(updated);
  }

  async function doRewind(id: string, toPhase: string, note: string): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    await store.save(rewind(item, toPhase, note, { clock: cfg.clock }));
  }

  const server = createServer((req, res) => {
    void (async () => {
      try {
        const url = req.url ?? "/";
        if (req.method === "GET" && url === "/healthz") {
          res.writeHead(200, { "content-type": "text/plain" });
          res.end("ok");
          return;
        }
        if (req.method === "GET" && (url === "/" || url === "/hopper")) {
          const [items, profiles] = [await store.list(), catalog.list()];
          res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
          if (url === "/hopper") {
            // Hopper = raw untriaged ideas + the intake box.
            const ideas = items.filter((i) => i.genre === UNTRIAGED);
            res.end(renderHopperPage(ideas, profiles));
          } else {
            // Gauntlet = triaged projects moving through phases.
            const projects = items.filter((i) => i.genre !== UNTRIAGED);
            res.end(renderGauntlet(projects, profiles));
          }
          return;
        }
        if (req.method === "GET" && url === "/cards") {
          // Legacy read-only view of the nightly-builds gauntlet cards.
          const cards = cfg.vaultDir ? readHopperCards(cfg.vaultDir) : [];
          res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
          res.end(renderHopper(cards));
          return;
        }
        if (req.method === "POST") {
          const body = await readBody(req);
          if (url === "/intake") {
            const text = (body.get("text") ?? "").trim();
            if (text) await intake(text);
            return redirect(res);
          }
          if (url === "/amend") {
            await amend(body.get("id") ?? "", (body.get("note") ?? "").trim());
            return redirect(res);
          }
          if (url === "/rewind") {
            await doRewind(body.get("id") ?? "", body.get("toPhase") ?? "", (body.get("note") ?? "").trim());
            return redirect(res);
          }
          if (url === "/profiles/toggle") {
            const genre = body.get("genre") ?? "";
            if (genre) catalog.setEnabled(genre, body.get("enabled") === "true");
            return redirect(res);
          }
        }
        res.writeHead(404, { "content-type": "text/plain" });
        res.end("not found");
      } catch (e) {
        res.writeHead(500, { "content-type": "text/plain" });
        res.end(`refinery error: ${(e as Error).message}`);
      }
    })();
  });

  return { server, store, catalog, intake, amend, doRewind };
}
