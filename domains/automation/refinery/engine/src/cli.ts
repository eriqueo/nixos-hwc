// CLI shell: `refinery run --pipeline project-ideation --input "<sentence>" --once`.
// Thin — it parses args, wires the real adapters (Claude LLM, markdown store,
// spec executor), and delegates to runPipelineOnce. All config is late-bound
// from flags/env; no hardcoded paths.

import { readFileSync } from "node:fs";
import { parsePipeline } from "./pipeline.js";
import { gateList } from "./gates/index.js";
import { makeSpecExecutor } from "./executors/spec.js";
import { MarkdownItemStore } from "./stores/markdown-store.js";
import { resolveLlm } from "./adapters/resolver.js";
import { runPipelineOnce } from "./cli/run-once.js";

interface Args {
  pipeline: string;
  input: string;
  id: string;
  pipelineFile: string;
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
  const pipeline = get("--pipeline", "project-ideation");
  const input = get("--input");
  const slug = input.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 48);
  return {
    pipeline,
    input,
    id: get("--id", slug || "item"),
    pipelineFile: get("--pipeline-file", `pipelines/${pipeline}.yaml`),
    storeDir: get("--store-dir", ".scratch/items"),
    scratchDir: get("--scratch-dir", ".scratch/specs"),
  };
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const pipeline = parsePipeline(readFileSync(args.pipelineFile, "utf8"));
  // The pipeline picks its own LLM adapter (claude-cli | anthropic-api | ollama).
  const llm = resolveLlm(pipeline.llmProvider);
  const result = await runPipelineOnce(
    { id: args.id, input: args.input },
    {
      pipeline,
      gates: gateList(llm),
      integrate: makeSpecExecutor({ scratchDir: args.scratchDir }, llm),
      store: new MarkdownItemStore(args.storeDir),
    },
  );

  if (result.parked) {
    console.log(`PARKED at ${result.item.step}: ${result.item.parkedReason ?? "(no reason)"}`);
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
