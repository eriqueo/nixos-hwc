// Domain registry — the categorical IDENTITY axis (color + tag) of the Refinery,
// orthogonal to genre (pipeline) and stage/phase (lane). Loaded from the
// data-driven domains.yaml; the renderer derives label/color from it, never a
// hardcoded map (Charter principle 2 / the card-standard drift lesson). An
// idea's domain is auto-classified from its text prefix and overridable per card.

import { readFileSync, existsSync } from "node:fs";
import { parse as parseYaml } from "yaml";
import { z } from "zod";

export const DomainSchema = z.object({
  key: z.string().min(1),
  label: z.string().min(1),
  color: z.string().min(1),
  match: z.array(z.string().min(1)).default([]),
});
export type Domain = z.infer<typeof DomainSchema>;

const DomainsFileSchema = z.object({
  domains: z.array(DomainSchema).default([]),
  fallback: DomainSchema,
});

export interface DomainRegistry {
  domains: Domain[];
  fallback: Domain;
}

// Built-in fallback so the board still renders if the data file is absent.
const BUILTIN_FALLBACK: Domain = { key: "misc", label: "Misc", color: "#a7aaad", match: [] };

export function loadDomains(file?: string): DomainRegistry {
  if (!file || !existsSync(file)) return { domains: [], fallback: BUILTIN_FALLBACK };
  const parsed = DomainsFileSchema.parse(parseYaml(readFileSync(file, "utf8")));
  return { domains: parsed.domains, fallback: parsed.fallback };
}

/** Classify an idea's domain from its leading "prefix:" (the brain _ideas.md
 *  convention — "kidpix: …", "nixos repo: …"). Returns a domain key, or the
 *  fallback key when there's no clear short prefix or no alias matches. */
export function classifyDomain(text: string, reg: DomainRegistry): string {
  const head = (text.split(":")[0] || "").toLowerCase().replace(/\(.*?\)/g, "").trim();
  if (!head || head.length > 30) return reg.fallback.key; // no clear prefix → unknown
  for (const d of reg.domains) {
    const aliases = [d.key.toLowerCase(), ...d.match.map((m) => m.toLowerCase())];
    if (aliases.some((a) => head === a || head.startsWith(a))) return d.key;
  }
  return reg.fallback.key;
}

export function resolveDomain(key: string, reg: DomainRegistry): Domain {
  return reg.domains.find((d) => d.key === key) ?? reg.fallback;
}

/** The resolved domain of an item: a manual override (payload.domain) wins,
 *  else classify the idea text (payload.input, falling back to the title). */
export function domainOf(item: { payload?: unknown }, reg: DomainRegistry): Domain {
  const pl = item.payload && typeof item.payload === "object" ? (item.payload as Record<string, unknown>) : {};
  const override = typeof pl.domain === "string" ? pl.domain : "";
  if (override) return resolveDomain(override, reg);
  const text = typeof pl.input === "string" ? pl.input : typeof pl.title === "string" ? pl.title : "";
  return resolveDomain(classifyDomain(text, reg), reg);
}
