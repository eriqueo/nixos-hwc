// CLI shell: `refinery run --genre project-ideation --input "<sentence>" --once`.
// Thin — it parses args, wires the real adapters (Claude LLM, markdown store,
// write-spec effector), and delegates to runGenreOnce. All config is late-bound
// from flags/env; no hardcoded paths.

import { readFileSync } from "node:fs";
import { parseProfile } from "./profile.js";
import { gateList } from "./gates/index.js";
import { makeWriteSpecEffector } from "./effectors/write-spec.js";
import { MarkdownItemStore } from "./stores/markdown-store.js";
import { resolveLlm } from "./adapters/resolver.js";
import { runGenreOnce } from "./cli/run-once.js";

interface Args {
  genre: string;
  input: string;
  id: string;
  profile: string;
  storeDir: string;
  scratchDir: string;
}

function parseArgs(argv: string[]): Args {
  const get = (flag: string, fallback?: string): string => {
    const i = argv.indexOf(flag);
    if (i >= 0 && argv[i + 1] !== undefined) return argv[i + 1]!;
    if (fallback !== undefined) return fallback;
    throw new Error(`missing required ${flag}`);
  };
  const genre = get("--genre", "project-ideation");
  const input = get("--input");
  const slug = input.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 48);
  return {
    genre,
    input,
    id: get("--id", slug || "item"),
    profile: get("--profile", `profiles/${genre}.yaml`),
    storeDir: get("--store-dir", ".scratch/items"),
    scratchDir: get("--scratch-dir", ".scratch/specs"),
  };
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const profile = parseProfile(readFileSync(args.profile, "utf8"));
  // The profile picks its own LLM adapter (claude-cli | anthropic-api | ollama).
  const llm = resolveLlm(profile.llmProvider);
  const result = await runGenreOnce(
    { id: args.id, input: args.input },
    {
      profile,
      gates: gateList(llm),
      integrate: makeWriteSpecEffector({ scratchDir: args.scratchDir }, llm),
      store: new MarkdownItemStore(args.storeDir),
    },
  );

  if (result.parked) {
    console.log(`PARKED at ${result.item.phase}: ${result.item.parkedReason ?? "(no reason)"}`);
    process.exitCode = 0;
    return;
  }
  const out = result.integrated?.output as { specPath?: string } | undefined;
  console.log(`DONE — ran [${result.ran.join(", ")}]; spec: ${out?.specPath ?? "(none)"}`);
}

main().catch((e) => {
  console.error(`refinery: ${(e as Error).message}`);
  process.exitCode = 1;
});
