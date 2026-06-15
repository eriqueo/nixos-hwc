// ProfileCatalog — the lead_scout-style profile registry, adapted for refinery's
// no-database world. Mirrors lead_scout's split of a read-only disk catalog
// (the profile .yaml files, version-controlled) from mutable live state (the
// enabled flag): here the live state is a small JSON overlay in a writable
// state dir, so toggling a profile on/off never rewrites a repo-managed file.
//
// Lifecycle (lead_scout parity): list / get / enabled / setEnabled.

import { readFileSync, readdirSync, existsSync, writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { Profile } from "../contracts.js";
import { parseProfile } from "../profile.js";

/** A profile with the optional fields resolved to concrete defaults. */
export interface ResolvedProfile extends Profile {
  label: string;
  enabled: boolean;
  llmProvider: string;
}

const DEFAULT_LLM_PROVIDER = "claude-cli";

interface EnabledOverlay {
  [genre: string]: { enabled: boolean };
}

export interface ProfileCatalogConfig {
  dir: string; // directory of <genre>.yaml profiles (version-controlled)
  statePath?: string; // JSON overlay of enabled flags (writable state); optional
}

export class ProfileCatalog {
  constructor(private readonly cfg: ProfileCatalogConfig) {}

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
    if (!p) throw new Error("ProfileCatalog: setEnabled requires a statePath");
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, JSON.stringify(overlay, null, 2));
  }

  private resolve(profile: Profile, overlay: EnabledOverlay): ResolvedProfile {
    // Overlay wins over the file's `enabled`; default enabled = true.
    const override = overlay[profile.genre]?.enabled;
    const enabled = override ?? profile.enabled ?? true;
    return {
      ...profile,
      label: profile.label ?? profile.genre,
      enabled,
      llmProvider: profile.llmProvider ?? DEFAULT_LLM_PROVIDER,
    };
  }

  /** All profiles on disk, with enabled/label/llmProvider resolved. */
  list(): ResolvedProfile[] {
    if (!existsSync(this.cfg.dir)) return [];
    const overlay = this.readOverlay();
    const out: ResolvedProfile[] = [];
    for (const f of readdirSync(this.cfg.dir)) {
      if (!f.endsWith(".yaml") && !f.endsWith(".yml")) continue;
      const profile = parseProfile(readFileSync(join(this.cfg.dir, f), "utf8"));
      out.push(this.resolve(profile, overlay));
    }
    out.sort((a, b) => a.genre.localeCompare(b.genre));
    return out;
  }

  /** One profile by genre, or null. */
  get(genre: string): ResolvedProfile | null {
    return this.list().find((p) => p.genre === genre) ?? null;
  }

  /** Only the enabled profiles — the set triage may route an item into. */
  enabled(): ResolvedProfile[] {
    return this.list().filter((p) => p.enabled);
  }

  /** Toggle a profile on/off by writing the enabled overlay (lead_scout-style). */
  setEnabled(genre: string, enabled: boolean): void {
    if (!this.get(genre)) throw new Error(`ProfileCatalog: no profile for genre "${genre}"`);
    const overlay = this.readOverlay();
    overlay[genre] = { enabled };
    this.writeOverlay(overlay);
  }
}
