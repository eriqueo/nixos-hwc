// PipelineCatalog — the lead_scout-style pipeline registry, adapted for refinery's
// no-database world. Mirrors lead_scout's split of a read-only disk catalog
// (the pipeline .yaml files, version-controlled) from mutable live state (the
// enabled flag): here the live state is a small JSON overlay in a writable
// state dir, so toggling a pipeline on/off never rewrites a repo-managed file.
//
// Lifecycle (lead_scout parity): list / get / enabled / setEnabled.

import { readFileSync, readdirSync, existsSync, writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { Pipeline } from "../contracts.js";
import { parsePipeline } from "../pipeline.js";

/** A pipeline with the optional fields resolved to concrete defaults. */
export interface ResolvedPipeline extends Pipeline {
  label: string;
  enabled: boolean;
  llmProvider: string;
  color: string;
}

const DEFAULT_LLM_PROVIDER = "claude-cli";
const DEFAULT_COLOR = "#a89984"; // gruvbox gray — used when a pipeline omits color

interface EnabledOverlay {
  [pipeline: string]: { enabled: boolean };
}

export interface PipelineCatalogConfig {
  dir: string; // directory of <pipeline>.yaml pipelines (version-controlled)
  statePath?: string; // JSON overlay of enabled flags (writable state); optional
}

export class PipelineCatalog {
  constructor(private readonly cfg: PipelineCatalogConfig) {}

  private readOverlay(): EnabledOverlay {
    const p = this.cfg.statePath;
    if (!p || !existsSync(p)) return {};
    try {
      return JSON.parse(readFileSync(p, "utf8")) as EnabledOverlay;
    } catch {
      return {};
    }
  }

  private writeOverlay(overlay: EnabledOverlay): void {
    const p = this.cfg.statePath;
    if (!p) throw new Error("PipelineCatalog: setEnabled requires a statePath");
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, JSON.stringify(overlay, null, 2));
  }

  private resolve(pipeline: Pipeline, overlay: EnabledOverlay): ResolvedPipeline {
    // Overlay wins over the file's `enabled`; default enabled = true.
    const override = overlay[pipeline.pipeline]?.enabled;
    const enabled = override ?? pipeline.enabled ?? true;
    return {
      ...pipeline,
      label: pipeline.label ?? pipeline.pipeline,
      enabled,
      llmProvider: pipeline.llmProvider ?? DEFAULT_LLM_PROVIDER,
      color: pipeline.color ?? DEFAULT_COLOR,
    };
  }

  /** All pipelines on disk, with enabled/label/llmProvider resolved. */
  list(): ResolvedPipeline[] {
    if (!existsSync(this.cfg.dir)) return [];
    const overlay = this.readOverlay();
    const out: ResolvedPipeline[] = [];
    for (const f of readdirSync(this.cfg.dir)) {
      if (!f.endsWith(".yaml") && !f.endsWith(".yml")) continue;
      const pipeline = parsePipeline(readFileSync(join(this.cfg.dir, f), "utf8"));
      out.push(this.resolve(pipeline, overlay));
    }
    out.sort((a, b) => a.pipeline.localeCompare(b.pipeline));
    return out;
  }

  /** One pipeline by id, or null. */
  get(pipeline: string): ResolvedPipeline | null {
    return this.list().find((p) => p.pipeline === pipeline) ?? null;
  }

  /** Only the enabled pipelines — the set triage may route an item into. */
  enabled(): ResolvedPipeline[] {
    return this.list().filter((p) => p.enabled);
  }

  /** Toggle a pipeline on/off by writing the enabled overlay (lead_scout-style). */
  setEnabled(pipeline: string, enabled: boolean): void {
    if (!this.get(pipeline)) throw new Error(`PipelineCatalog: no pipeline "${pipeline}"`);
    const overlay = this.readOverlay();
    overlay[pipeline] = { enabled };
    this.writeOverlay(overlay);
  }
}
