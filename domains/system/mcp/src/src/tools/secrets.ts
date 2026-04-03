/**
 * hwc_secrets_* tools — secret inventory and usage mapping.
 * NEVER returns secret values. Only names, categories, paths, and references.
 */

import { readdir, readFile, access } from "node:fs/promises";
import { join, relative } from "node:path";
import type { ToolDef, ToolResult } from "../types.js";
import { catchError } from "../errors.js";

interface SecretDeclaration {
  name: string;
  category: string;
  ageFileExists: boolean;
  mode?: string;
  owner?: string;
  group?: string;
}

export function secretsTools(nixosConfigPath: string): ToolDef[] {
  return [
    // ── hwc_secrets_inventory ───────────────────────────────────────────
    {
      name: "hwc_secrets_inventory",
      description:
        "List all agenix-managed secrets — name, category, .age file existence, permissions. " +
        "NEVER returns secret values. Filter by category (system, home, services, infrastructure).",
      inputSchema: {
        type: "object",
        properties: {
          category: {
            type: "string",
            description: "Filter by category (e.g. 'system', 'home', 'services', 'infrastructure')",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const filterCategory = args.category as string | undefined;
          const declDir = join(nixosConfigPath, "domains/secrets/declarations");
          const partsDir = join(nixosConfigPath, "domains/secrets/parts");

          const entries = await readdir(declDir);
          const nixFiles = entries.filter(
            (f) => f.endsWith(".nix") && f !== "index.nix" && f !== "caddy.nix"
          );

          const secrets: SecretDeclaration[] = [];

          for (const file of nixFiles) {
            const category = file.replace(".nix", "");
            if (filterCategory && category !== filterCategory) continue;

            const content = await readFile(join(declDir, file), "utf-8");
            const parsed = parseSecretDeclarations(content, category, partsDir);
            secrets.push(...(await parsed));
          }

          secrets.sort((a, b) => a.category.localeCompare(b.category) || a.name.localeCompare(b.name));

          const byCategory: Record<string, number> = {};
          for (const s of secrets) {
            byCategory[s.category] = (byCategory[s.category] || 0) + 1;
          }

          return {
            status: "ok",
            message: `${secrets.length} secrets across ${Object.keys(byCategory).length} categories`,
            data: { secrets, byCategory, total: secrets.length },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to read secret inventory", err, "Check that domains/secrets/declarations/ exists");
        }
      },
    },

    // ── hwc_secrets_usage_map ───────────────────────────────────────────
    {
      name: "hwc_secrets_usage_map",
      description:
        "Map which services reference which secrets. Greps for age.secrets references across the codebase. " +
        "Use to understand secret rotation impact or find unused secrets.",
      inputSchema: {
        type: "object",
        properties: {
          service: {
            type: "string",
            description: "Filter to show secrets used by a specific domain/service.",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const filterService = (args.service as string)?.toLowerCase();
          const domainsDir = join(nixosConfigPath, "domains");
          const usageMap = await buildSecretUsageMap(domainsDir);

          const filtered = filterService
            ? usageMap.filter((entry) =>
                entry.domain.toLowerCase().includes(filterService) ||
                entry.file.toLowerCase().includes(filterService)
              )
            : usageMap;

          // Group by secret name
          const bySecret: Record<string, string[]> = {};
          for (const entry of filtered) {
            for (const secret of entry.secrets) {
              if (!bySecret[secret]) bySecret[secret] = [];
              bySecret[secret].push(`${entry.domain}/${entry.file}`);
            }
          }

          // Group by domain
          const byDomain: Record<string, string[]> = {};
          for (const entry of filtered) {
            if (!byDomain[entry.domain]) byDomain[entry.domain] = [];
            byDomain[entry.domain].push(...entry.secrets);
          }
          // Deduplicate
          for (const key of Object.keys(byDomain)) {
            byDomain[key] = [...new Set(byDomain[key])];
          }

          return {
            status: "ok",
            message: `${Object.keys(bySecret).length} secrets referenced across ${Object.keys(byDomain).length} domains`,
            data: {
              bySecret,
              byDomain,
              totalSecrets: Object.keys(bySecret).length,
              totalReferences: filtered.reduce((sum, e) => sum + e.secrets.length, 0),
            },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to build secret usage map", err);
        }
      },
    },
  ];
}

// ── Helpers ──────────────────────────────────────────────────────────────

async function parseSecretDeclarations(
  content: string,
  category: string,
  partsDir: string
): Promise<SecretDeclaration[]> {
  const secrets: SecretDeclaration[] = [];

  // Two formats:
  // 1. Flat: age.secrets.name = { ... };
  // 2. Nested: age.secrets = { name = { ... }; name2 = { ... }; };

  // Try flat format first
  const flatRegex = /age\.secrets\.([\w-]+)\s*=\s*\{/g;
  let match: RegExpExecArray | null;
  let foundFlat = false;

  while ((match = flatRegex.exec(content)) !== null) {
    foundFlat = true;
    const name = match[1];
    const blockStart = match.index + match[0].length - 1;
    const block = extractBlock(content, blockStart);
    secrets.push(await parseSecretBlock(name, block, category, partsDir));
  }

  // If no flat matches, try nested format: age.secrets = { ... }
  if (!foundFlat) {
    const nestedMatch = content.match(/age\.secrets\s*=\s*\{/);
    if (nestedMatch && nestedMatch.index !== undefined) {
      const outerBlock = extractBlock(content, nestedMatch.index + nestedMatch[0].length - 1);
      // Parse individual secret entries within the block
      const entryRegex = /([\w-]+)\s*=\s*\{/g;
      let entryMatch: RegExpExecArray | null;

      while ((entryMatch = entryRegex.exec(outerBlock)) !== null) {
        const name = entryMatch[1];
        // Skip Nix keywords that aren't secret names
        if (["file", "mode", "owner", "group", "path"].includes(name)) continue;
        const innerBlock = extractBlock(outerBlock, entryMatch.index + entryMatch[0].length - 1);
        secrets.push(await parseSecretBlock(name, innerBlock, category, partsDir));
      }
    }
  }

  return secrets;
}

/** Extract a { ... } block from content starting at the opening brace */
function extractBlock(content: string, braceStart: number): string {
  let depth = 0;
  for (let i = braceStart; i < content.length; i++) {
    if (content[i] === "{") depth++;
    if (content[i] === "}") {
      depth--;
      if (depth === 0) return content.slice(braceStart, i + 1);
    }
  }
  return content.slice(braceStart);
}

async function parseSecretBlock(
  name: string,
  block: string,
  category: string,
  partsDir: string
): Promise<SecretDeclaration> {
  const modeMatch = block.match(/mode\s*=\s*"([^"]+)"/);
  const ownerMatch = block.match(/owner\s*=\s*"([^"]+)"/);
  const groupMatch = block.match(/group\s*=\s*"([^"]+)"/);

  // Check if .age file exists
  let ageFileExists = false;
  // Match: file = ../parts/category/name.age; or file = ./parts/...
  const fileMatch = block.match(/file\s*=\s*(?:\.\.\/|\.\/)parts\/([^;]+\.age)/);
  if (fileMatch) {
    try {
      await access(join(partsDir, fileMatch[1]));
      ageFileExists = true;
    } catch {
      // file doesn't exist
    }
  } else {
    // Try common path patterns
    const possiblePaths = [
      join(partsDir, category, `${name}.age`),
      join(partsDir, `${name}.age`),
    ];
    for (const p of possiblePaths) {
      try {
        await access(p);
        ageFileExists = true;
        break;
      } catch {
        // continue
      }
    }
  }

  return {
    name,
    category,
    ageFileExists,
    mode: modeMatch?.[1],
    owner: ownerMatch?.[1],
    group: groupMatch?.[1],
  };
}

interface SecretUsageEntry {
  domain: string;
  file: string;
  secrets: string[];
}

async function buildSecretUsageMap(domainsDir: string): Promise<SecretUsageEntry[]> {
  const entries: SecretUsageEntry[] = [];
  await walkForSecretRefs(domainsDir, domainsDir, entries);
  return entries;
}

async function walkForSecretRefs(
  dir: string,
  baseDir: string,
  entries: SecretUsageEntry[]
): Promise<void> {
  let dirEntries;
  try {
    dirEntries = await readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of dirEntries) {
    const fullPath = join(dir, entry.name);

    if (entry.isDirectory()) {
      // Skip secrets declarations themselves and node_modules
      if (entry.name === "node_modules" || entry.name === "dist" ||
          (fullPath.includes("secrets/declarations"))) continue;
      await walkForSecretRefs(fullPath, baseDir, entries);
    } else if (entry.name.endsWith(".nix")) {
      try {
        const content = await readFile(fullPath, "utf-8");
        const refs: string[] = [];

        // Match age.secrets.name references (not declarations)
        const refRegex = /(?:config\.)?age\.secrets\.([\w-]+)(?:\.path)?/g;
        let match: RegExpExecArray | null;
        while ((match = refRegex.exec(content)) !== null) {
          if (!refs.includes(match[1])) {
            refs.push(match[1]);
          }
        }

        if (refs.length > 0) {
          const relPath = relative(baseDir, fullPath);
          const domain = relPath.split("/")[0];
          entries.push({
            domain,
            file: relPath,
            secrets: refs,
          });
        }
      } catch {
        // Skip unreadable files
      }
    }
  }
}
